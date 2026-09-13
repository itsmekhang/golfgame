class_name GolfBall
extends Node3D
## In-game golf ball driven by the OpenFairway physics engine (GDScript port).
##
## Ownership (mirrors the OpenFairway GolfBall/HoleSceneController split):
##  - This node owns launch state, ground contact, floor normal, the active
##    SurfaceType and calls into BallPhysics / BounceCalculator.
##  - Surface resolution is supplied from outside via `resolve_surface`
##    (a Callable returning { "engine": SurfaceType, "surface": id, "source": String }).
##  - Ground height/normal are analytic from CourseLayout so flight and rollout
##    never depend on Godot's rigid-body solver.

signal launched(velocity: Vector3, omega: Vector3)
signal first_impact(position: Vector3, surface: int)
signal came_to_rest(position: Vector3, surface: int)
signal entered_water(position: Vector3)
## Emitted with the WaterHazard the ball landed in (null if water came from the class map).
signal water_hazard_entered(hazard: WaterHazard, position: Vector3)
## Emitted once per shot when the ball ends up in sand (first impact or rest).
signal bunker_entered(position: Vector3, plugged: bool)
signal out_of_bounds(position: Vector3)
signal holed(position: Vector3)

const DT := BallPhysics.SIMULATION_DT
const GROUND_CLEARANCE := 0.0015  # clearance for the stripe and world-coordinate rounding
## 0.5 mph (0.5 * 0.44704 m/s per mph) -- settle to rest as soon as the ball's down to a slow
## creep instead of waiting for it to fully stop, so the next shot isn't held up by a long tail
## of barely-moving roll.
const REST_SPEED := 0.22352
## A ball trickling below this speed (m/s) for CREEP_TIME seconds -- creeping down a
## slope, wobbling in a hollow -- is called at rest rather than holding up the next shot.
const CREEP_SPEED := 0.7
const CREEP_TIME := 2.0
const MAX_SHOT_TIME := 20.0
## The visible cup and its capture region share this mouth radius. A slow ball whose
## body still overlaps the lip gets a little extra room to tip into the opening.
const CUP_RADIUS := 0.08
const CUP_CAPTURE_SPEED := 2.3
const CUP_CAPTURE_MARGIN := 0.01
const CUP_LIP_MARGIN := 0.016
const CUP_LIP_SPEED := 1.1

@export var temperature_f: float = 75.0
@export var altitude_ft: float = 0.0
@export var wind: Vector3 = Vector3.ZERO  # m/s, world-space
@export var log_level: int = PhysicsLogger.Level.INFO

var layout: CourseLayout
var resolve_surface: Callable  # (Vector3) -> Dictionary
var cup_position: Vector3 = Vector3.ZERO
var obstacle_mask: int = 2
## True for a prediction-only ball (course.gd's shadow_ball): skips the per-step
## physics-server raycast against trees/rocks, which is by far the most expensive
## part of a simulated step and isn't needed for a preview line.
var skip_obstacles: bool = false
# One response per crown per shot prevents repeated slowing at a leaf boundary.
var _foliage_touched: Array[RID] = []
var _foliage_rng := RandomNumberGenerator.new()

var velocity: Vector3 = Vector3.ZERO
var omega: Vector3 = Vector3.ZERO
var state: int = PhysicsEnums.BallState.REST
var on_ground: bool = true
var current_surface: int = PhysicsEnums.SurfaceType.FAIRWAY  # engine surface
var current_lie: int = PhysicsEnums.SurfaceType.FAIRWAY  # gameplay id (may be bunker/water/tee)
var floor_normal: Vector3 = Vector3.UP
var shot_time: float = 0.0
var carry_distance_m: float = 0.0
var total_distance_m: float = 0.0
var max_height_m: float = 0.0
var trail: PackedVector3Array = PackedVector3Array()
## Set when the ball splashed into water on the current shot.
var in_water: bool = false
var last_hazard: WaterHazard = null
## Set when the ball is in a bunker (flagged at impact or rest).
var in_bunker: bool = false
var _bunker_flagged: bool = false
var is_moving: bool:
	get:
		return state != PhysicsEnums.BallState.REST

var _physics := BallPhysics.new()
var _aero := Aerodynamics.new()
var _factory := PhysicsParamsFactory.new()
var _shot_setup := ShotSetup.new()
var _ball_profile := BallPhysicsProfile.new()
var _params: PhysicsParams
var _launch_pos: Vector3
var _launch_dir: Vector3 = Vector3.FORWARD
var _launch_vla: float = 0.0
var _launch_speed_mph: float = 0.0
var _launch_spin_rpm: float = 0.0
var _impact_spin_rpm: float = 0.0
var _first_impact_done := false
## Post-bounce vertical speed of the previous bounce (-1 = no bounce yet this shot). Real
## bounces lose energy each time, so this is used to stop a later bounce from launching
## higher (a faster vertical speed) than the one before it -- see _handle_impact.
var _last_bounce_vy := -1.0
var _accum := 0.0
var _rest_timer := 0.0
var _creep_timer := 0.0
var _prev_speed := 0.0
var _finished := false
var _mesh: MeshInstance3D
var _spin_visual := Basis.IDENTITY
var _shadow_mesh: MeshInstance3D
var _shadow_mat: StandardMaterial3D


func _ready() -> void:
	PhysicsLogger.set_level(log_level)
	_physics.set_profiles(_ball_profile.resolved_rollout, _ball_profile.resolved_bounce)
	_build_visual()


## Real-world scanned/modeled golf ball, ~43,500 real dimpled vertices, matched with its own
## PBR "used/worn" skin (assets/textures/ball). _mesh itself stays an empty, unscaled wrapper
## -- used for the spin-rotation visual (_update_visual sets _mesh.basis) and as the Stripe's
## parent -- with the actual OBJ model nested one level deeper as `model`, carrying the
## cm-to-metres scale and the recentring offset (the source mesh's own local origin is at its
## bottom, resting-on-ground point, not its centre) so those don't also shrink/misplace the
## stripe if applied directly on _mesh.
func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "BallMesh"
	add_child(_mesh)

	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = load("res://assets/models/ball/golf_ball.obj")
	# The source mesh is authored in centimetres, already at real golf-ball scale (its own
	# radius comes out to ~2.13cm, matching BallPhysics.RADIUS almost exactly) -- only a unit
	# conversion is needed, not a size correction. Y is offset because the mesh's local origin
	# sits at its bottom (Y ~0..4.26cm) rather than its centre.
	model.scale = Vector3.ONE * 0.01
	model.position = Vector3(0, -BallPhysics.RADIUS, 0)
	var mat := StandardMaterial3D.new()
	# Metalness/roughness in the source textures were flat 0/1 everywhere (a plain matte
	# dielectric ball, no metallic fleck anywhere) -- constants instead of loading two more
	# textures that would only ever sample one uniform value.
	mat.albedo_texture = load("res://assets/textures/ball/ball_basecolor_512.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/ball/ball_normal_512.png")
	mat.metallic = 0.0
	mat.roughness = 1.0
	model.material_override = mat
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh.add_child(model)

	# Dimple-ish logo stripe so spin is visible
	var stripe := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = BallPhysics.RADIUS * 0.98
	tm.outer_radius = BallPhysics.RADIUS * 1.02
	tm.rings = 24
	tm.ring_segments = 8
	stripe.mesh = tm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.15, 0.12)
	stripe.material_override = smat
	stripe.name = "Stripe"
	_mesh.add_child(stripe)

	# Soft ground-contact "blob" shadow: a real-time directional shadow from a ball this
	# small is easy to lose against grass/terrain detail, especially mid-flight -- this
	# gives a reliable, always-visible depth cue for height above ground regardless of the
	# sun's shadow settings. Shrinks/darkens near the ground, grows/fades higher up.
	_shadow_mesh = MeshInstance3D.new()
	_shadow_mesh.name = "BallShadow"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	qm.orientation = PlaneMesh.FACE_Y
	_shadow_mesh.mesh = qm
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var shadow_tex := GradientTexture2D.new()
	shadow_tex.gradient = grad
	shadow_tex.fill = GradientTexture2D.FILL_RADIAL
	shadow_tex.fill_from = Vector2(0.5, 0.5)
	shadow_tex.width = 32
	shadow_tex.height = 32
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = shadow_tex
	_shadow_mat.no_depth_test = true
	_shadow_mat.render_priority = 1
	_shadow_mesh.material_override = _shadow_mat
	add_child(_shadow_mesh)


## Place the ball at rest on the ground at an XZ position.
func place(xz: Vector2) -> void:
	_foliage_touched.clear()
	global_position = Vector3(xz.x, _contact_height(Vector3(xz.x, 0, xz.y)), xz.y)
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	state = PhysicsEnums.BallState.REST
	on_ground = true
	_finished = false
	_first_impact_done = false
	_last_bounce_vy = -1.0
	if _mesh != null:
		_mesh.position.y = 0.0
	in_water = false
	last_hazard = null
	_bunker_flagged = false
	trail.clear()
	_refresh_lie()
	in_bunker = current_lie == CourseLayout.SURFACE_BUNKER


func _refresh_lie() -> void:
	if resolve_surface.is_valid():
		var r: Dictionary = resolve_surface.call(global_position)
		current_surface = r["engine"]
		current_lie = r["surface"]
	if layout != null:
		floor_normal = layout.normal_at(global_position.x, global_position.z)


## Launch with launch-monitor style numbers (mph, deg, rpm) toward `aim_dir` (world XZ).
func launch(ball_speed_mph: float, vla_deg: float, backspin_rpm: float, sidespin_rpm: float, aim_dir: Vector3) -> void:
	_foliage_touched.clear()
	_foliage_rng.seed = hash([global_position, ball_speed_mph, vla_deg, aim_dir, backspin_rpm, sidespin_rpm])
	if ball_speed_mph <= 0.0:
		return
	var flat := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	flat = flat.normalized()

	# ShotSetup builds vectors for a shot along +X (HLA 0) -> rotate into aim_dir.
	var launch := _shot_setup.build_launch_vectors_from_components(ball_speed_mph, vla_deg, 0.0, backspin_rpm, sidespin_rpm)
	var yaw := atan2(-flat.z, flat.x)  # angle from +X toward -Z is positive rotation about +Y
	var v: Vector3 = (launch["velocity"] as Vector3).rotated(Vector3.UP, yaw)
	var w: Vector3 = (launch["omega"] as Vector3).rotated(Vector3.UP, yaw)

	velocity = v
	omega = w
	state = PhysicsEnums.BallState.FLIGHT
	on_ground = false
	shot_time = 0.0
	_accum = 0.0
	_rest_timer = 0.0
	_creep_timer = 0.0
	_finished = false
	_first_impact_done = false
	_last_bounce_vy = -1.0
	if _mesh != null:
		_mesh.position.y = 0.0
	_impact_spin_rpm = 0.0
	carry_distance_m = 0.0
	total_distance_m = 0.0
	max_height_m = 0.0
	_launch_pos = global_position
	_launch_dir = flat
	_launch_vla = vla_deg
	_launch_speed_mph = ball_speed_mph
	_launch_spin_rpm = sqrt(backspin_rpm * backspin_rpm + sidespin_rpm * sidespin_rpm)
	in_water = false
	last_hazard = null
	in_bunker = false
	_bunker_flagged = false
	trail.clear()
	trail.append(global_position)
	_refresh_lie()
	_rebuild_params()
	PhysicsLogger.info("[Launch] %.1f mph  VLA %.1f  BS %.0f  SS %.0f  surface=%s" % [ball_speed_mph, vla_deg, backspin_rpm, sidespin_rpm, SurfacePhysicsCatalog.surface_name(current_surface)])
	launched.emit(velocity, omega)


## Putt: pure rollout launch along the ground.
func putt(speed_mps: float, aim_dir: Vector3) -> void:
	var flat := Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	velocity = flat * speed_mps
	# Rolling spin about the axis perpendicular to travel
	omega = Vector3.UP.cross(flat).normalized() * (speed_mps / BallPhysics.RADIUS) * -1.0
	state = PhysicsEnums.BallState.ROLLOUT
	on_ground = true
	shot_time = 0.0
	_accum = 0.0
	_rest_timer = 0.0
	_creep_timer = 0.0
	_finished = false
	_first_impact_done = true
	_impact_spin_rpm = 0.0
	carry_distance_m = 0.0
	total_distance_m = 0.0
	max_height_m = 0.0
	_launch_pos = global_position
	_launch_dir = flat
	_launch_vla = 0.0
	_launch_speed_mph = speed_mps / ShotSetup.MPS_PER_MPH
	_launch_spin_rpm = 0.0
	trail.clear()
	trail.append(global_position)
	_refresh_lie()
	_rebuild_params()
	launched.emit(velocity, omega)


func _rebuild_params() -> void:
	var air_density := _aero.get_air_density(altitude_ft, temperature_f, PhysicsEnums.Units.IMPERIAL)
	var air_viscosity := _aero.get_dynamic_viscosity(temperature_f, PhysicsEnums.Units.IMPERIAL)
	_params = _factory.create(air_density, air_viscosity, 1.0, 1.0, current_surface, floor_normal,
		_impact_spin_rpm, _ball_profile, _launch_vla, _launch_speed_mph, _launch_spin_rpm)


func _physics_process(delta: float) -> void:
	if state == PhysicsEnums.BallState.REST or _finished:
		return
	# Fixed 120 Hz sub-stepping, independent of the engine tick rate.
	_accum += delta
	var steps := 0
	while _accum >= DT and steps < 8:
		_step(DT)
		_accum -= DT
		steps += 1
		if _finished or state == PhysicsEnums.BallState.REST:
			break
	_update_visual(delta)


## Soft crowns never push the ball back to an artificial cylinder wall. Trunks still
## use the solid obstacle sweep. Multiple overlapping crowns can each affect a shot.
func _pass_foliage(from: Vector3, to: Vector3) -> void:
	if from.is_equal_approx(to):
		return
	var space := get_world_3d().direct_space_state
	for i in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to, ForestPlanter.FOLIAGE_LAYER, _foliage_touched)
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		_foliage_touched.append(hit["rid"])
		var before := velocity.length()
		velocity = foliage_velocity(velocity, _foliage_rng.randf(), _foliage_rng.randf_range(-1.0, 1.0))
		omega *= velocity.length() / maxf(before, 0.001)


## Gaps preserve flight; leaves take a little speed; a branch contact loses lift
## and much more speed. The cap prevents any contact from adding kinetic energy.
static func foliage_velocity(incoming: Vector3, contact: float, side: float) -> Vector3:
	if contact < 0.25:
		return incoming
	var speed := incoming.length()
	var result: Vector3
	if contact < 0.78:
		result = incoming.rotated(Vector3.UP, side * 0.055) * lerpf(0.92, 0.72, (contact - 0.25) / 0.53)
		result.y -= minf(speed * 0.035, 1.5)
	else:
		result = incoming.rotated(Vector3.UP, side * 0.22) * lerpf(0.48, 0.18, (contact - 0.78) / 0.22)
		result.y = minf(result.y, -minf(speed * 0.12, 4.0))
	return result.limit_length(speed)


func _ground_height(p: Vector3) -> float:
	if layout != null:
		var drawn := layout.rendered_terrain.sample(p.x, p.z)
		return drawn.x if is_finite(drawn.x) else layout.height_at(p.x, p.z)
	return 0.0


func _contact_height(p: Vector3) -> float:
	if layout != null:
		var supported := layout.rendered_terrain.support_height(p.x, p.z, BallPhysics.RADIUS + GROUND_CLEARANCE)
		if is_finite(supported):
			return supported
		var normal := layout.normal_at(p.x, p.z)
		return layout.height_at(p.x, p.z) + (BallPhysics.RADIUS + GROUND_CLEARANCE) / maxf(normal.y, 0.05)
	return BallPhysics.RADIUS + GROUND_CLEARANCE


## Solve first contact with each rendered triangle crossed by the flight segment.
## This catches shallow strikes on narrow bunker lips even when both ends are clear.
func _sweep_ground(from: Vector3, to: Vector3) -> Variant:
	if layout == null or layout.rendered_terrain.tiles.is_empty():
		return _sweep_unmeshed_ground(from, to)
	var cuts := layout.rendered_terrain.segment_breaks(Vector2(from.x, from.z), Vector2(to.x, to.z))
	var travel := to - from
	for i in range(1, cuts.size()):
		var t0: float = cuts[i - 1]
		var t1: float = cuts[i]
		if t1 - t0 < 0.0000001:
			continue
		var mid := from.lerp(to, (t0 + t1) * 0.5)
		var plane := layout.rendered_terrain.sample(mid.x, mid.z)
		if not is_finite(plane.x):
			var fallback = _sweep_unmeshed_ground(from.lerp(to, t0), from.lerp(to, t1))
			if fallback != null:
				return fallback
			continue
		var contact0 := plane.x + plane.y * (from.x - mid.x) + plane.z * (from.z - mid.z)
		contact0 += (BallPhysics.RADIUS + GROUND_CLEARANCE) * sqrt(1.0 + plane.y * plane.y + plane.z * plane.z)
		var contact_delta := plane.y * travel.x + plane.z * travel.z
		var gap0 := from.y - contact0 + (travel.y - contact_delta) * t0
		var gap1 := from.y - contact0 + (travel.y - contact_delta) * t1
		var hit_t := -1.0
		if gap0 < -0.0005 or (gap0 <= 0.0 and gap1 < gap0):
			hit_t = t0
		elif gap0 > 0.0 and gap1 <= 0.0:
			hit_t = lerpf(t0, t1, gap0 / (gap0 - gap1))
		if hit_t >= 0.0:
			var hit := from.lerp(to, hit_t)
			hit.y = maxf(contact0 + contact_delta * hit_t, _contact_height(hit))
			return hit
	return null

## Analytic fallback for previews and terrain outside the loaded tile region.
func _sweep_unmeshed_ground(from: Vector3, to: Vector3) -> Variant:
	var steps := maxi(1, int(ceil(from.distance_to(to) / 0.35)))
	var previous := 0.0
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := from.lerp(to, t)
		if p.y <= _contact_height(p):
			var lo := previous
			var hi := t
			for j in range(8):
				var mid := (lo + hi) * 0.5
				var point := from.lerp(to, mid)
				if point.y > _contact_height(point):
					lo = mid
				else:
					hi = mid
			var hit := from.lerp(to, hi)
			hit.y = _contact_height(hit)
			return hit
		previous = t
	return null


func _step(dt: float) -> void:
	shot_time += dt
	var pos := global_position
	var was_on_ground := on_ground

	# Relative-air velocity for wind: integrate with (v - wind) for aero, but move with v.
	var v_air := velocity - wind if not on_ground else velocity
	var res := _physics.integrate_step(v_air, omega, on_ground, _params, dt)
	var new_v_air: Vector3 = res[0]
	omega = res[1]
	velocity = new_v_air + wind if not on_ground else new_v_air

	var new_pos := pos + velocity * dt

	# Obstacle collision (tree trunks, rocks) via a ray/shape sweep on layer 2.
	if not skip_obstacles and (state == PhysicsEnums.BallState.FLIGHT or velocity.length() > 1.0):
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos, new_pos + velocity.normalized() * BallPhysics.RADIUS, obstacle_mask)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			var vn := velocity.dot(n)
			if vn < 0.0:
				velocity = (velocity - n * vn * 1.55) * 0.55  # inelastic tree/rock bounce
				omega *= 0.4
				new_pos = (hit["position"] as Vector3) + n * (BallPhysics.RADIUS * 1.5)
				PhysicsLogger.info("[Obstacle] hit at %s" % [new_pos])

	if not skip_obstacles and not on_ground:
		_pass_foliage(pos, new_pos)

	if not on_ground:
		var ground_hit = _sweep_ground(pos, new_pos)
		if ground_hit != null:
			new_pos = ground_hit
			_handle_impact(new_pos)
	else:
		# Follow terrain while rolling
		new_pos.y = _contact_height(new_pos)
		floor_normal = layout.normal_at(new_pos.x, new_pos.z) if layout != null else Vector3.UP
		_params.floor_normal = floor_normal
		# Slope gravity: BallPhysics zeros the Y component; keep the ball on the surface and
		# let along-slope gravity live in XZ (already applied in calculate_forces).
		velocity.y = 0.0
		# Small bumps/hops when rolling fast over uneven ground are ignored (analytic ground).
		# Re-resolve lie surface every few cm of travel so fairway->green->rough transitions apply.
		_update_surface_if_changed(new_pos)

	global_position = new_pos
	max_height_m = maxf(max_height_m, new_pos.y - _launch_pos.y)
	if trail.is_empty() or trail[trail.size() - 1].distance_to(new_pos) > 0.5:
		trail.append(new_pos)

	# A landing checks its contact point; only a rolling step sweeps across the lip.
	if _cup_catches_step(pos if was_on_ground else new_pos, new_pos):
		_finish_holed()
		return

	# Water: splash as soon as the ball drops through a hazard's surface, or when it
	# comes to ground on any water cell (class map water on scanned courses).
	var hz: WaterHazard = layout.hazard_at(Vector2(new_pos.x, new_pos.z)) if layout != null else null
	if hz != null and new_pos.y <= hz.water_level + BallPhysics.RADIUS and (velocity.y <= 0.0 or on_ground):
		_finish_water(hz)
		return
	if on_ground and current_lie == CourseLayout.SURFACE_WATER:
		_finish_water(hz)
		return
	if layout != null and not layout.in_bounds(new_pos.x, new_pos.z):
		_finish_ob()
		return

	# Rest detection. Spin is not a condition: a rolling ball's omega is tied to its
	# speed (v / R, ~10 rad/s at REST_SPEED), so requiring it near zero meant waiting
	# for a complete standstill -- and on a slope that could take the whole shot cap.
	if on_ground:
		var speed := velocity.length()
		var slowing := speed <= _prev_speed + 1.0e-4  # a ball gathering pace down a slope is not at rest
		_prev_speed = speed
		if speed < REST_SPEED and slowing:
			_rest_timer += dt
			if _rest_timer > 0.15:
				_finish_rest()
				return
		else:
			_rest_timer = 0.0
		if speed < CREEP_SPEED:
			_creep_timer += dt
			if _creep_timer > CREEP_TIME:
				_finish_rest()
				return
		else:
			_creep_timer = 0.0
	if shot_time > MAX_SHOT_TIME:
		_finish_rest()


func _update_surface_if_changed(pos: Vector3) -> void:
	if not resolve_surface.is_valid():
		return
	var r: Dictionary = resolve_surface.call(pos)
	var eng: int = r["engine"]
	current_lie = r["surface"]
	if eng != current_surface:
		current_surface = eng
		var keep_rollout_spin := _params.rollout_impact_spin
		_rebuild_params()
		_params.rollout_impact_spin = keep_rollout_spin
		_params.floor_normal = floor_normal
		PhysicsLogger.info("[Surface] now %s (%s)" % [SurfacePhysicsCatalog.surface_name(eng), r["source"]])


func _handle_impact(pos: Vector3) -> void:
	floor_normal = layout.normal_at(pos.x, pos.z) if layout != null else Vector3.UP
	if layout != null:
		var drawn := layout.rendered_terrain.sample(pos.x, pos.z)
		if is_finite(drawn.x):
			floor_normal = Vector3(-drawn.y, 1.0, -drawn.z).normalized()
	var r: Dictionary = resolve_surface.call(pos) if resolve_surface.is_valid() else {"engine": current_surface, "surface": current_lie, "source": "default"}
	current_surface = r["engine"]
	current_lie = r["surface"]
	if not _first_impact_done:
		_impact_spin_rpm = omega.length() / ShotSetup.RAD_PER_RPM
	_rebuild_params()

	var pre_speed := velocity.length()
	# How steep the incoming trajectory is at landing: 0 = grazing/flat (a low bump-and-run),
	# 1 = straight down. A higher-apex shot descends steeper for a given landing speed, so
	# this is the direct physical proxy for "how high was the apex" -- used below to make
	# soft, high-arc shots plug into sand/rough instead of skipping through, while a flatter,
	# lower-flighted shot into the same lie still runs out some, matching real golf.
	var impact_steepness := clampf(-velocity.normalized().dot(floor_normal), 0.0, 1.0) if pre_speed > 0.01 else 1.0
	var incoming_horiz := Vector3(velocity.x, 0.0, velocity.z)

	var bounce := _physics.calculate_bounce(velocity, omega, floor_normal, state, _params)
	velocity = bounce.new_velocity
	omega = bounce.new_omega
	state = bounce.new_state

	# The engine's steep-impact (Penner) bounce model can reverse tangential velocity from
	# backspin -- realistic on a green (checking/spinback), but its speed-based trigger isn't
	# actually gated to greens, so a strong enough iron shot could do the same thing landing
	# on the fairway and visibly roll backward. Off the green, treat a reversal as "stopped"
	# instead of "rolling backward": the ball can be killed dead by spin, just not sent the
	# wrong way.
	if current_lie != PhysicsEnums.SurfaceType.GREEN:
		var post_horiz := Vector3(velocity.x, 0.0, velocity.z)
		if incoming_horiz.length() > 0.1 and post_horiz.dot(incoming_horiz) < 0.0:
			velocity.x = 0.0
			velocity.z = 0.0

	# Fairway: the lower the apex (shallow impact_steepness), the more it skips forward and
	# the livelier it bounces off the firm turf -- inverse of rough/bunker below. A high,
	# soft-landing apex shot is close to the engine's ordinary bounce (t -> 0, no extra boost).
	if current_lie == PhysicsEnums.SurfaceType.FAIRWAY:
		var t := 1.0 - smoothstep(0.15, 0.65, impact_steepness)
		# No forced minimum here (was 1.05, an unconditional bonus on every single fairway
		# bounce with nothing equivalent on green) -- that alone was enough to make fairway
		# consistently outroll green regardless of the surface friction tuning above. Only a
		# genuinely shallow, skipping impact gets extra life now.
		var horiz := Vector3(velocity.x, 0.0, velocity.z) * lerpf(1.0, 1.2, t)
		var vert := velocity.y * lerpf(1.0, 1.2, t) if velocity.y > 0.0 else velocity.y
		velocity = Vector3(horiz.x, vert, horiz.z)
		# High-backspin clubs (irons/wedges) should roll out less than a low-spin wood/driver
		# shot even on the fairway, which -- unlike the green -- has no explicit spin-check
		# mechanic of its own to do this automatically (measured: with only impact_steepness
		# driving the boost above, a 7 iron still out-rolled a driver in testing, backwards).
		# _impact_spin_rpm is the spin at landing, a direct, club-agnostic proxy for "iron-ness".
		var spin_t := clampf((_impact_spin_rpm - 2000.0) / 6000.0, 0.0, 1.0)
		velocity *= lerpf(1.0, 0.7, spin_t)

	# Extra post-bounce damping on top of the OpenFairway engine's bounce model, layered over
	# SurfacePhysicsCatalog's per-surface rolling friction: green/fringe get none (an ordinary
	# bounce), rough reads noticeably deader, and bunker is close to dead below -- both rough
	# and bunker scale that damping up with impact_steepness rather than applying a single
	# fixed cut, so only the higher-arc shots really stick.
	if current_lie == PhysicsEnums.SurfaceType.ROUGH:
		var t := smoothstep(0.35, 0.85, impact_steepness)
		velocity *= lerpf(1.0, 0.8, t)
		velocity.y = maxf(velocity.y * lerpf(1.0, 0.72, t), 0.0)
		omega *= lerpf(1.0, 0.85, t)

	# Bunker: kill nearly all bounce & roll so it plugs like sand, and flag it. A flatter,
	# skulled-in shot still skids on a bit; a steep, high-apex one settles almost on the spot;
	# past STICK_STEEPNESS it plugs dead exactly where it lands.
	if current_lie == CourseLayout.SURFACE_BUNKER:
		const STICK_STEEPNESS := 0.9
		if impact_steepness >= STICK_STEEPNESS:
			velocity = Vector3.ZERO
			omega *= 0.05
		else:
			var t := smoothstep(0.3, STICK_STEEPNESS, impact_steepness)
			velocity *= lerpf(0.6, 0.12, t)
			velocity.y = maxf(velocity.y * lerpf(0.55, 0.05, t), 0.0)
			omega *= lerpf(0.5, 0.08, t)
		_flag_bunker(pos, true)
		# Sand still kills the shot's bounce and roll; keep the visible ball at its
		# contact point instead of burying the mesh below the sand with a tween.

	if not _first_impact_done:
		_first_impact_done = true
		carry_distance_m = Vector2(pos.x - _launch_pos.x, pos.z - _launch_pos.z).dot(Vector2(_launch_dir.x, _launch_dir.z))
		PhysicsLogger.info("[LandingSurface] surface=%s lie=%s speed_in=%.1f m/s spin=%.0f rpm source=%s" % [
			SurfacePhysicsCatalog.surface_name(current_surface), CourseLayout.surface_label(current_lie), pre_speed, _impact_spin_rpm, r["source"]])
		first_impact.emit(pos, current_lie)

	# A real ball loses energy every bounce -- never gains it. Cap this bounce's vertical
	# speed at the previous bounce's, so a livelier surface response (e.g. the fairway boost
	# above) can never make bounce N+1 launch higher than bounce N.
	if velocity.y > 0.0:
		if _last_bounce_vy >= 0.0:
			velocity.y = minf(velocity.y, _last_bounce_vy)
		_last_bounce_vy = velocity.y

	# Decide whether the ball leaves the ground again
	var vn := velocity.dot(floor_normal)
	if vn > 0.35:
		# Bounce back into flight-like ballistic motion but keep ROLLOUT state for bounce rules.
		on_ground = false
	else:
		velocity -= floor_normal * vn
		velocity.y = 0.0
		on_ground = true


func _finish_rest() -> void:
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	state = PhysicsEnums.BallState.REST
	on_ground = true
	_finished = true
	total_distance_m = Vector2(global_position.x - _launch_pos.x, global_position.z - _launch_pos.z).dot(Vector2(_launch_dir.x, _launch_dir.z))
	_refresh_lie()
	in_bunker = current_lie == CourseLayout.SURFACE_BUNKER
	if in_bunker:
		_flag_bunker(global_position, false)
	PhysicsLogger.info("[Rest] carry=%.1f yd total=%.1f yd apex=%.1f ft lie=%s" % [
		carry_distance_m * ShotSetup.YARDS_PER_METER, total_distance_m * ShotSetup.YARDS_PER_METER,
		max_height_m * ShotSetup.FEET_PER_METER, CourseLayout.surface_label(current_lie)])
	came_to_rest.emit(global_position, current_lie)


func _flag_bunker(pos: Vector3, plugged: bool) -> void:
	in_bunker = true
	if _bunker_flagged:
		return
	_bunker_flagged = true
	PhysicsLogger.info("[Bunker] ball in sand at %s plugged=%s" % [pos, str(plugged)])
	bunker_entered.emit(pos, plugged)


func _finish_water(hz: WaterHazard) -> void:
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	state = PhysicsEnums.BallState.REST
	_finished = true
	in_water = true
	last_hazard = hz
	current_lie = CourseLayout.SURFACE_WATER
	if hz != null:
		global_position.y = hz.water_level - BallPhysics.RADIUS * 0.5
		hz.notify_ball_entered(global_position)
	PhysicsLogger.info("[Water] ball in %s at %s" % [hz.hazard_name if hz != null else "water", global_position])
	entered_water.emit(global_position)
	water_hazard_entered.emit(hz, global_position)


func _finish_ob() -> void:
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	state = PhysicsEnums.BallState.REST
	_finished = true
	out_of_bounds.emit(global_position)


## Sweep the rolling step so a grazing lip contact cannot fall between samples.
## The extra 6 mm only catches slow balls; faster edge brushes keep rolling past.
func _cup_catches_step(from: Vector3, to: Vector3) -> bool:
	if cup_position == Vector3.ZERO or not on_ground:
		return false
	var speed := velocity.length()
	if speed >= CUP_CAPTURE_SPEED:
		return false
	var cup := Vector2(cup_position.x, cup_position.z)
	var closest := Geometry2D.get_closest_point_to_segment(cup, Vector2(from.x, from.z), Vector2(to.x, to.z))
	var distance_sq := closest.distance_squared_to(cup)
	if distance_sq < (CUP_RADIUS + CUP_CAPTURE_MARGIN) ** 2:
		return true
	return speed < CUP_LIP_SPEED and distance_sq < (CUP_RADIUS + CUP_LIP_MARGIN) ** 2


func _finish_holed() -> void:
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	state = PhysicsEnums.BallState.REST
	_finished = true
	var start := global_position
	var target := Vector3(cup_position.x, cup_position.y - 0.1, cup_position.z)
	# A quick eased roll-to-centre-and-drop instead of an instant teleport into the cup --
	# the camera is already tracking the ball (course.gd holds FOLLOW mode for a few seconds
	# after holing out), so this reads as the ball visibly falling in rather than just
	# vanishing and reappearing a few centimetres lower.
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(self, "global_position", target, 0.35).from(start)
	# Wait for the drop-in to actually finish before telling course.gd the hole is over --
	# emitting this immediately (the old behaviour) fired the "In the hole!" message and
	# locked input at the same instant the tween *started*, so the ball dropping in was
	# rarely actually seen.
	tw.finished.connect(func(): holed.emit(target))


func _update_visual(delta: float) -> void:
	if _mesh == null:
		return
	var w := omega.length()
	if w > 0.01 and is_finite(w):
		_spin_visual = _spin_visual.rotated(omega / w, w * delta).orthonormalized()
		_mesh.basis = _spin_visual
	_update_shadow()


func _update_shadow() -> void:
	if _shadow_mesh == null or layout == null:
		return
	var ground_y := _ground_height(global_position)
	var height_above := maxf(global_position.y - ground_y, 0.0)
	_shadow_mesh.position = Vector3(0.0, ground_y - global_position.y + 0.01, 0.0)
	var scale_t := clampf(height_above / 10.0, 0.0, 1.0)
	var s := lerpf(1.0, 3.0, scale_t)
	_shadow_mesh.scale = Vector3(s, 1.0, s)
	_shadow_mat.albedo_color.a = lerpf(0.5, 0.12, scale_t)


## Distance from ball to cup in yards (flat).
func distance_to_cup_yd() -> float:
	return Vector2(global_position.x - cup_position.x, global_position.z - cup_position.z).length() * ShotSetup.YARDS_PER_METER
