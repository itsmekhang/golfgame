extends Node3D
## Native SoftBody3D fabric with pinned hoist, gravity, gusts and distributed forces.
## Wind is WORLD-SPACE velocity in m/s, blowing TOWARD the supplied vector.
##
## The fabric is deliberately harder to push around than the raw course wind would suggest:
## wind_velocity always holds the true value (other consumers -- ball.wind, the HUD wind arrow
## -- read the real COURSE_WIND directly, see course.gd), but only wind_tame_threshold m/s of
## it reaches the cloth at full strength; anything above that is heavily softened before it
## becomes simulation force, so gusts read on the ball/HUD don't make the flag thrash.
const Grid = preload("res://assets/world_flagstick/cloth_grid.gd")
const FABRIC = preload("res://assets/world_flagstick/fabric.gdshader")
const MASS_KG := 0.055
const CUP_DEPTH := 0.16

@export var wind_velocity := Vector3(3.0,0.0,0.6)
@export_range(0.0,0.6) var gust_strength := 0.12
@export var wind_tame_threshold := 3.0  # m/s of real wind the flag still shows undamped
@export_range(0.0,1.0) var wind_tame_softness := 0.3  # fraction of wind above the threshold that still gets through
@export var phase_offset := 0.0
@export var flag_color := Color("0f2973")  # checkered with white, see fabric.gdshader
@export_range(5.0,200.0) var simulation_distance := 75.0
@export var simulation_enabled := true
@export_flags_3d_physics var pole_collision_layer := 1
@export_flags_3d_physics var cloth_collision_mask := 1

var cloth: SoftBody3D
var anchor: Node3D
var distant: MeshInstance3D
var pole_body: StaticBody3D
var _near := true
var _time := 0.0
var _lod_clock := 0.0
var _material: ShaderMaterial
var _distant_material: ShaderMaterial
var _force_samples := PackedInt32Array()
var _filtered_wind := Vector3.ZERO
var _physical_supported := true

func _ready() -> void:
	# The supplied demo selects Jolt. Other backends use the wind-shaped fallback;
	# GodotPhysics3D was observed stretching this small light mesh excessively.
	_physical_supported = ProjectSettings.get_setting("physics/3d/physics_engine","GodotPhysics3D") == "Jolt Physics"
	var baked_flag := $Model.find_child("Flag",true,false) as MeshInstance3D
	baked_flag.visible = false
	anchor = Node3D.new()
	anchor.name = "HoistAnchor"
	add_child(anchor)
	_material = ShaderMaterial.new()
	_material.shader = FABRIC
	_material.set_shader_parameter("fabric_color",flag_color)
	_distant_material = _material.duplicate() as ShaderMaterial
	_distant_material.set_shader_parameter("distant_mode",true)
	_distant_material.set_shader_parameter("phase_offset",phase_offset)
	distant = MeshInstance3D.new()
	distant.name = "DistantFabric"
	distant.mesh = Grid.make_mesh()
	distant.material_override = _distant_material
	distant.custom_aabb = AABB(Vector3(-0.8,1.25,-0.8),Vector3(1.6,1.4,1.6))
	distant.visible = false
	add_child(distant)
	_build_pole_collision()
	for row in range(1,Grid.ROWS,2):
		for column in range(2,Grid.COLUMNS+1,3):
			_force_samples.append(row*(Grid.COLUMNS+1)+column)
	reset_cloth()
	_update_lod(true)

func _build_pole_collision() -> void:
	pole_body = StaticBody3D.new()
	pole_body.name = "PoleCollision"
	pole_body.collision_layer = pole_collision_layer
	pole_body.collision_mask = 0
	add_child(pole_body)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.009
	cylinder.height = 2.47
	shape.shape = cylinder
	shape.position.y = 1.25
	pole_body.add_child(shape)

func reset_cloth() -> void:
	## Call after relocating the entire flagstick. Never called every frame.
	if not is_instance_valid(anchor):
		return
	if is_instance_valid(cloth):
		remove_child(cloth)
		cloth.queue_free()
	cloth = SoftBody3D.new()
	cloth.name = "Fabric"
	cloth.mesh = Grid.make_mesh()
	cloth.material_override = _material
	cloth.total_mass = MASS_KG
	cloth.linear_stiffness = 1.0
	# Damping/precision raised from the original 0.12/16 -- the flag read as too loose/jittery
	# ("make the flagpin more rigid"); more solver iterations holds the pinned hoist edge
	# straighter and the extra damping settles ripple/wobble faster instead of lingering. Eased
	# back down slightly afterward ("reduce flagpin rigidity by a little bit") -- still stiffer
	# than the original, just not as stiff as the first pass.
	cloth.damping_coefficient = 0.18
	cloth.drag_coefficient = 0.16
	cloth.simulation_precision = 20
	cloth.collision_layer = 0
	cloth.collision_mask = cloth_collision_mask
	cloth.ray_pickable = false
	cloth.disable_mode = SoftBody3D.DISABLE_MODE_REMOVE
	cloth.extra_cull_margin = 0.8
	add_child(cloth)
	# Submit its initial world transform while the Jolt body still has a space.
	# Otherwise a distant body's pending transform can arrive after LOD disables it.
	cloth.force_update_transform()
	for row in range(Grid.ROWS+1):
		cloth.set_point_pinned(row*(Grid.COLUMNS+1),true,NodePath("../HoistAnchor"))
	cloth.visible = _near
	cloth.process_mode = Node.PROCESS_MODE_INHERIT if _near else Node.PROCESS_MODE_DISABLED

func set_wind_velocity(velocity_mps: Vector3) -> void:
	wind_velocity = velocity_mps.limit_length(20.0) if velocity_mps.is_finite() else Vector3.ZERO

## Softens wind speed above wind_tame_threshold so occasional strong gusts don't whip the
## flag around; direction is left untouched, only ever called on a magnitude.
func _tame_speed(speed: float) -> float:
	if speed <= wind_tame_threshold:
		return speed
	return wind_tame_threshold + (speed - wind_tame_threshold) * wind_tame_softness

func place_in_cup(green_surface_center: Vector3, insertion_depth: float = 0.12) -> void:
	## Root is the pole foot. A 12 cm insertion leaves 4 cm below it in your cup.
	global_position = green_surface_center - Vector3.UP * clampf(insertion_depth,0.0,CUP_DEPTH)
	reset_cloth()

func set_fabric_color(color: Color) -> void:
	flag_color = color
	if _material != null:
		_material.set_shader_parameter("fabric_color",flag_color)
		_distant_material.set_shader_parameter("fabric_color",flag_color)

func _physics_process(delta: float) -> void:
	_time += delta
	_lod_clock += delta
	if _lod_clock >= 0.5:
		_lod_clock = 0.0
		_update_lod()
	var target_wind := wind_velocity.limit_length(20.0) if wind_velocity.is_finite() else Vector3.ZERO
	_filtered_wind = _filtered_wind.lerp(target_wind,1.0-exp(-delta*2.5))
	var wind := _filtered_wind
	var horizontal := Vector3(wind.x,0.0,wind.z)
	if horizontal.length_squared() > 0.01:
		# Only the cheap distant approximation is rotated; nearby fabric turns by force.
		var local_direction := global_basis.inverse()*horizontal.normalized()
		var yaw := atan2(-local_direction.z,local_direction.x)
		distant.rotation.y = lerp_angle(distant.rotation.y,yaw,1.0-exp(-delta*1.8))
	_distant_material.set_shader_parameter("wind_speed",_tame_speed(wind.length()))
	if not _near or not simulation_enabled:
		return
	var raw_speed := wind.length()
	if raw_speed < 0.02:
		return # With no wind, gravity and damping let the cloth hang naturally.
	var direction := wind / raw_speed
	var speed := _tame_speed(raw_speed)
	var gust := 1.0 + gust_strength*(0.65*sin(_time*1.17+phase_offset)+0.35*sin(_time*2.63+1.4+phase_offset))
	# Bounded artistic aerodynamic force, not a meteorological wind-tunnel model. speed here is
	# already tamed, so a strong real gust looks like a calm, heavy flag stirring, not thrashing.
	var pressure := minf(0.85,0.5*1.225*Grid.WIDTH*Grid.HEIGHT*0.55*speed*speed*gust)
	cloth.apply_central_force(direction*pressure)
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	var amplitude := pressure*0.26/maxi(1,_force_samples.size())
	for index in _force_samples:
		var column := index % (Grid.COLUMNS+1)
		var row := index / (Grid.COLUMNS+1)
		var u := float(column)/Grid.COLUMNS
		var v := float(row)/Grid.ROWS
		var ripple := sin(u*11.0-_time*(3.0+speed*0.8)+v*2.0+phase_offset)
		ripple += 0.45*sin(u*19.0+v*5.0-_time*7.1)
		cloth.apply_force(index,side*amplitude*ripple*u)

func _update_lod(force: bool = false) -> void:
	var camera := get_viewport().get_camera_3d()
	var should_simulate := simulation_enabled and _physical_supported
	if camera != null:
		var threshold := simulation_distance + (10.0 if _near else -10.0)
		should_simulate = should_simulate and camera.global_position.distance_to(global_position) < threshold
	if should_simulate == _near and not force:
		return
	var was_near := _near
	_near = should_simulate
	cloth.process_mode = Node.PROCESS_MODE_INHERIT if _near else Node.PROCESS_MODE_DISABLED
	if _near and not was_near:
		# Jolt recreates a removed soft body from its local mesh when it wakes.
		# Restore its world placement after it has re-entered the physics space.
		cloth.global_transform = global_transform
		cloth.force_update_transform()
	cloth.visible = _near
	distant.visible = not _near

func is_cloth_simulating() -> bool:
	return _near and simulation_enabled
