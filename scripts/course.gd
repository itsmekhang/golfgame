extends Node3D
const TEE_SIGN = preload("res://scripts/tee_hole_sign.gd")
## Course scene controller (mirrors OpenFairway's HoleSceneControllerBase):
## builds terrain + props, wires the ball, supplies the ResolveLieSurface delegate,
## and runs the stroke loop (aim -> power -> accuracy -> shot -> result).

enum SwingPhase { IDLE, POWER, IN_FLIGHT }

const POWER_SPEED := 110.0  # % per second

## Seed for the course routing (CourseBuilder). Press J for a new course.
static var course_seed: int = 7
## Seed for the random water hazards. Press H in game to reroll.
static var hazard_seed: int = 7
var water_balls: int = 0
var bunker_visits: int = 0

var layout: CourseLayout
var resolver: LieSurfaceResolver
var ball: GolfBall
var swing_rig: ClubSwingRig
## Tests that call _fire_shot() directly and check the ball's state on the very
## next line set this so the shot launches immediately, same as before the swing
## animation existed, instead of waiting out the animation delay.
var skip_swing_animation: bool = false
var camera: OrbitCamera
var hud: Hud
var audio: GolfAudio
var flag: Node3D
var backdrop_root: MeshInstance3D
var terrain_root: Node3D
var grass_root: Node3D
var hazards_root: Node3D
var terra_root: Node3D  # TerraBrush clipmap terrain (visual); our tiles stay for collision
## Draw the course with the TerraBrush clipmap terrain when the extension is available.
static var use_terrabrush: bool = false
var trail_mesh: MeshInstance3D
var aim_line: MeshInstance3D

## Per-hole terrain/prop loading (see _ensure_hole_region): only the active hole's region is
## built at a time, freed and rebuilt behind a loading screen on every hole transition.
var props_root: Node3D
var decor_root: Node3D
var nature_props_root: Node3D
var facilities_root: Node3D  # course-manager buildings (Course Studio courses only)
var active_region := Rect2()
var _hole_loading := false
## Cart-boarding loading screen shown at startup and on every hole change (see
## _ensure_hole_region, transition_to_hole). One shared instance at a time -- whichever call
## site created it (_ready() at startup, or transition_to_hole() otherwise) owns freeing it;
## _ensure_hole_region() just updates its progress if one is already up rather than creating
## a second overlay on top of it.
## Every hole gets its own wind (see wind_for_hole), shared by ball.wind (start_hole) and that
## hole's flagpin (_add_flag) so the flag never flutters against what the ball actually feels.
## Speeds are skewed toward calm-to-breezy with the odd properly windy hole up to this cap.
const WIND_MAX_MPS := 6.0  # ~13 mph
const LOADING_SCENE := preload("res://scenes/ui/golf_loading_screen.tscn")
## Modeled pole with real SoftBody3D cloth (see assets/world_flagstick/README.md) -- used in
## _add_flag in place of the old procedural CylinderMesh/BoxMesh pole and flag panel.
const FLAGSTICK_SCENE := preload("res://assets/world_flagstick/world_flagstick.tscn")
var _loading_screen: GolfLoadingScreen
## True from the moment a hole transition (startup or transition_to_hole) begins until
## gameplay is fully restored -- camera/ball/HUD input and physics are frozen for the
## duration (_set_transition_active) so nothing can act on a course that's mid-swap.
var _transitioning := true
## CPU-painted bunker trail (see scripts/sand_trail.gd), rebuilt alongside terrain_root.
var sand_trail: SandTrail
var _terrain_material: ShaderMaterial
var _sand_trail_tick := 0
## Extra buffer beyond hole_bbox()'s own margin, so a sliced/hooked shot still lands on
## built terrain/props instead of a void.
const HOLE_REGION_MARGIN := 60.0

var hole_index := 0
var strokes := 0
var scores: Array[int] = []
var club_index := 0
var phase: SwingPhase = SwingPhase.IDLE
var power := 0.0
var power_dir := 1.0
var locked_power := 0.0
## Strike point on the ball face, set by dragging the HUD ball graphic (see
## StrikeSelector): x is heel/toe (shot shape), y is low/high (loft and spin).
var strike := Vector2.ZERO
var shadow_ball: GolfBall  # hidden ball used only to simulate the shot preview
var shot_tracker_line: MeshInstance3D
var landing_marker: MeshInstance3D
var minimap_viewport: SubViewport
var minimap_camera: Camera3D
var minimap_pin_marker: MeshInstance3D
var _minimap_elapsed := 1.0
var _minimap_last_ball := Vector3(INF, INF, INF)
## Minimap-only tree silhouettes and pin icon, hidden from the main camera.
const MINIMAP_LAYER := 0x200  # layer 10
const MINIMAP_HEIGHT_PX := 440  # 2x the displayed height; smooth downsampling in the cached map
var _minimap_built := false
## World-space frame the minimap camera is currently cropped to (see _update_minimap_frame),
## kept around so _minimap_world_to_local can place the overhead-camera focus circle.
var _minimap_center := Vector2.ZERO
var _minimap_forward := Vector2(0.0, -1.0)
var _minimap_right := Vector2(1.0, 0.0)
var _minimap_scale := 1.0  # world metres per minimap-texture pixel
var _tracker_inputs: Array = []
var _tracker_running := false
var _tracker_steps := 0
## Full swings preview the flight only (to the first bounce); putts preview the whole roll.
## Bounce and roll steps cost ~10x a flight step (terrain normal + lie lookups every step).
var _tracker_flight_only := false
## Aim the running simulation was started with, and the aim / ball position the line on
## screen was drawn for. While a new preview computes, the old one is swung around the ball
## by the aim change so turning the aim never waits on the simulation.
var _tracker_pending_yaw := 0.0
var _tracker_shown_yaw := 0.0
var _tracker_shown_pivot := Vector3(INF, INF, INF)
var _tracker_shown_landing := Vector3.ZERO
var _tracker_shown_pts := PackedVector3Array()
var _tracker_applied_yaw := 0.0
## A putt preview rolls only this far from the ball (cup distance + PUTT_PREVIEW_PAST_CUP_M):
## the full-power putt it simulates would otherwise roll ~70 m over up to TRACKER_MAX_TIME.
var _tracker_start := Vector3.ZERO
var _tracker_putt_limit_m := 0.0
var _tracker_ring := true  # false while a cut-short putt preview has no resting spot to mark
const PUTT_PREVIEW_PAST_CUP_M := 2.0
const PUTT_PREVIEW_MIN_M := 3.0
## Hold the swing button (Space / left click) while the ball is moving to run the game this
## much faster. The ball sub-steps at a fixed 120 Hz, so the shot plays out identically.
const FAST_FORWARD_SCALE := 3.0
var _ff_armed := false  # the press that hit the shot must be released before it fast-forwards
const TRACKER_BUDGET_USEC := 4000
const TRACKER_STEPS_PER_FRAME := 240
const PREVIEW_YELLOW := Color(1.0, 0.9, 0.2)  # matches the minimap preview line
const SHOT_RIBBON = preload("res://shaders/shot_ribbon.gdshader")
const LANDING_TARGET = preload("res://shaders/landing_target.gdshader")
## Cap the preview sim so a long, slow-to-rest putt/chip can't hold a frame open;
## most shots are done well inside this and the real shot is unaffected either way.
const TRACKER_MAX_TIME := 12.0
var _pre_shot_pos := Vector3.ZERO
## Ground distance (yd) from where the current/last shot was struck to the ball: counts up
## live in flight and roll, then holds the final total on the HUD until the next swing.
var _shot_yd := 0.0
var _penalty_pending := false
var _last_interactor := Vector3(INF, INF, INF)
## Mulligan (M): a snapshot taken right when a shot is fired, restorable on demand instead of
## restarting the whole hole (R does that). Includes the stroke/penalty counters so undoing a
## shot that went in the water/bunker also undoes the count and hidden penalty stroke it added.
var _mulligan_pos := Vector3.ZERO
var _mulligan_valid := false
var _mulligan_strokes := 0
var _mulligan_water_balls := 0
var _mulligan_bunker_visits := 0

## Progression / economy layer (see scripts/economy/): the between-round clubhouse hub, the
## ledger for the round in progress, and the RNG for club dispersion on the fired shot only
## (the tracker preview always shows the intended line).
var hub: HubMenu
var tracker: RoundTracker
## True from the moment the round's last hole drops until the player tees off again.
var _round_complete_pending := false
var _shot_rng := RandomNumberGenerator.new()
var _auto_putt_busy := false


var _t0 := 0


func _t(label: String) -> void:
	var now := Time.get_ticks_msec()
	print("[build] %-14s %5d ms" % [label, now - _t0])
	_t0 = now


func _ready() -> void:
	_set_transition_active(true)
	GolfLoadingScreen.set_course(_course_title(), GameLaunch.custom_course == "")
	var first := round_start_index()  # hole 10 for the back nine
	var spec := _hole_info(first)
	_loading_screen = LOADING_SCENE.instantiate()
	add_child(_loading_screen)
	_loading_screen.begin_hole(first + 1, spec["name"], spec["par"], spec["yd"], true)
	# Let the loading screen draw before the (synchronous) course build starts.
	if DisplayServer.get_name() != "headless":
		await _loading_screen.covered
	else:
		await get_tree().process_frame
		await get_tree().process_frame
	_t0 = Time.get_ticks_msec()
	_load_layout()
	# again: an unreadable Course Studio course falls back to Augusta
	GolfLoadingScreen.set_course(_course_title(), GameLaunch.custom_course == "")
	_t("layout")
	if not layout.authored_hazards:
		WaterHazardGenerator.generate(layout, hazard_seed, 1, 0.3)
		print("[WaterHazards] ", WaterHazardGenerator.last_report)
		BunkerGenerator.generate(layout, hazard_seed + 1)
		print("[Bunkers] ", BunkerGenerator.last_report)
	print("[Course] ", CourseBuilder.last_report)
	_t("hazards")
	_loading_screen.update_progress(0.3, "Shaping the terrain…")
	layout.build_cache(TerrainBuilder.RESOLUTION, false)  # baked per hole region on demand
	layout.build_feature_mask()
	_t("mask")
	_loading_screen.update_progress(0.55, "Getting the fairways ready…")
	_build_camera_node()
	await _build_world()
	_build_ball()
	_build_camera()
	_build_minimap()
	hud = Hud.new()
	add_child(hud)
	hud.set_course_title(_course_title())
	hud.main_menu_requested.connect(_on_main_menu)
	audio = GolfAudio.new()
	add_child(audio)
	hud.strike_selector.strike_changed.connect(func(v: Vector2) -> void: strike = v)
	_shot_rng.randomize()
	hub = HubMenu.new()
	add_child(hub)
	hub.tee_off_requested.connect(_on_hub_tee_off_span)
	hub.closed.connect(_on_hub_closed)
	hub.abandon_requested.connect(_on_hub_abandon)
	if GameState.current != null:
		GameState.current.bag_changed.connect(_on_bag_changed)
		GameState.current.business_ticked.connect(_on_business_ticked)
	_begin_round()
	resolver.register_zones(get_tree())
	_loading_screen.update_progress(0.7, "Finding the first tee…")
	# _ensure_hole_region (called from start_hole) sees _loading_screen already set and just
	# updates its progress instead of creating a second overlay on top of this one.
	await start_hole(round_start_index())
	_snap_camera_to_tee()
	if grass_root is GrassStreamer:
		grass_root.active = true
	_loading_screen.update_progress(0.95, "Ready to play…")
	_loading_screen.mark_ready()
	if DisplayServer.get_name() != "headless":
		await _loading_screen.ride_finished
	_loading_screen.queue_free()
	_loading_screen = null
	_set_transition_active(false)


## Re-carve terrain, lie cache and grass inside `rect` after a dig or removal.
func rebuild_area(rect: Rect2) -> void:
	_minimap_last_ball = Vector3(INF, INF, INF)
	if grass_root is GrassStreamer:
		grass_root.finish_pending()
	_tracker_inputs.clear()
	layout.update_cache_rect(rect)
	layout.update_feature_mask_rect(rect)
	if terrain_root != null:
		TerrainBuilder.rebuild_tiles(layout, terrain_root, rect)
	if grass_root is GrassStreamer:
		grass_root.rebuild_area(rect)
	else:
		RoughGrass.rebuild_tiles(layout, grass_root, rect)
	if grass_root != null and not is_instance_valid(grass_root):
		grass_root = get_node_or_null("RoughGrass")
	if ball != null and not ball.is_moving:
		ball.place(Vector2(ball.global_position.x, ball.global_position.z))
		_refresh_hud()


## Build only the current hole's terrain/prop region, freeing whatever hole was loaded
## before. Skipped when the new region is already fully covered (e.g. restarting the same
## hole with R). Guarded by _hole_loading against overlapping transitions (see start_hole).
## Shows the cart loading screen itself only when nothing has already put one up (startup's
## _ready() and transition_to_hole() both create their own first) -- otherwise just nudges
## that existing overlay's progress, so a hole change never shows two overlays stacked.
func _ensure_hole_region(hole: CourseLayout.Hole) -> void:
	var region := layout.hole_bbox(hole).grow(HOLE_REGION_MARGIN)
	if terrain_root != null and active_region.encloses(region):
		return
	_hole_loading = true
	var owns_screen := _loading_screen == null
	if owns_screen:
		_loading_screen = LOADING_SCENE.instantiate()
		add_child(_loading_screen)
		_loading_screen.begin_hole(hole.index + 1, _hole_info(hole.index)["name"], hole.par, int(_hole_info(hole.index).get("yd", roundi(hole.length_yd))))
		if DisplayServer.get_name() != "headless":
			await _loading_screen.covered
		else:
			await get_tree().process_frame
			await get_tree().process_frame
	else:
		_loading_screen.update_progress(0.3, "Loading hole %d…" % (hole.index + 1))
	# The lie/height bake for this region (3-4 s of pure GDScript) runs on a worker
	# thread while the main thread keeps animating the cart loading screen; nothing
	# else touches the layout until it finishes. Headless runs just bake inline.
	var t_cache := Time.get_ticks_msec()
	if DisplayServer.get_name() == "headless":
		if layout.ensure_cache_rect(region):
			print("[build] cache region %d x %d m in %d ms" % [region.size.x, region.size.y, Time.get_ticks_msec() - t_cache])
	else:
		var bake := Thread.new()
		bake.start(layout.ensure_cache_rect.bind(region))
		while bake.is_alive():
			await get_tree().process_frame
		if bake.wait_to_finish():
			print("[build] cache region %d x %d m in %d ms (background)" % [region.size.x, region.size.y, Time.get_ticks_msec() - t_cache])
	if terrain_root != null:
		terrain_root.queue_free()
	if props_root != null:
		props_root.queue_free()
	if decor_root != null:
		decor_root.queue_free()
	if nature_props_root != null:
		nature_props_root.queue_free()
	if terrain_root != null:
		# Release the previous forest's physics bodies before adding the next one.
		# Keeping both alive until the same frame ends can exhaust Jolt's body pool.
		await get_tree().process_frame
	layout.rendered_terrain.tiles.clear()
	terrain_root = Node3D.new()
	terrain_root.name = "Terrain"
	_terrain_material = TerrainBuilder.terrain_material(layout)
	TurfShells.attach(_terrain_material, layout)  # short living turf near the camera
	terrain_root.set_meta("material", _terrain_material)
	TerrainBuilder.rebuild_tiles(layout, terrain_root, region)
	add_child(terrain_root)
	if backdrop_root != null:
		backdrop_root.queue_free()
	backdrop_root = CourseBackdrop.build(layout, terrain_root)
	if backdrop_root != null:
		add_child(backdrop_root)
	# Scope the trail texture to just this hole's bunkers (grown a bit), not the whole
	# hole region -- the trail is only ever visible where mask.r (sand) is set anyway, so
	# covering hundreds of metres of fairway/rough it can never show on was just wasted
	# resolution, and was the actual reason the stamp couldn't be made any thinner (it was
	# already hitting SandTrail's 1-pixel-radius floor). Skip it entirely on bunker-less
	# holes; the shader's sand_trail uniform defaults to white (no-op) either way.
	sand_trail = null
	var bunker_rect := Rect2()
	for b in layout.bunkers:
		if not region.intersects(b.bounds):
			continue
		bunker_rect = b.bounds if bunker_rect.size == Vector2.ZERO else bunker_rect.merge(b.bounds)
	if bunker_rect.size != Vector2.ZERO:
		sand_trail = SandTrail.new(bunker_rect.grow(5.0))
		_terrain_material.set_shader_parameter("sand_trail", sand_trail.texture)
		_terrain_material.set_shader_parameter("sand_trail_origin", sand_trail.origin)
		_terrain_material.set_shader_parameter("sand_trail_size", sand_trail.size)
	var t0 := Time.get_ticks_msec()
	decor_root = PropScatter.decorate(layout, 11, region)
	add_child(decor_root)
	props_root = PropScatter.scatter(layout, course_seed, layout.random_trees, region)
	add_child(props_root)
	var t1 := Time.get_ticks_msec()
	nature_props_root = ForestPlanter.build(layout, course_seed, Rect2(0, 0, 1, 1) if OS.get_environment("GOLF_NO_FOREST") == "1" else region)
	add_child(nature_props_root)
	print("[Forest] %d trees, %d shrubs; props %d ms, forest %d ms" % [nature_props_root.tree_count, nature_props_root.shrub_count, t1 - t0, Time.get_ticks_msec() - t1])
	_build_facilities()
	active_region = region
	if owns_screen:
		_loading_screen.update_progress(0.95, "Almost ready…")
		_loading_screen.mark_ready()
		if DisplayServer.get_name() != "headless":
			await _loading_screen.ride_finished
		_loading_screen.queue_free()
		_loading_screen = null
	_hole_loading = false


func _load_layout() -> void:
	# A Course Studio course from the start menu, else Augusta.
	if GameLaunch.custom_course != "":
		var painted := PaintedCourse.load_file(GameLaunch.custom_course)
		if painted != null and not painted.holes.is_empty():
			var gs := GameState.current
			if gs != null and gs.business.owned and gs.business.course_path == GameLaunch.custom_course:
				FacilityBuilder.grade(painted, gs.business.placements, gs.business.built)  # the club's building plots
			layout = PaintedLayout.build(painted)
			print("[PaintedLayout] %s: %d holes in %d ms" % [painted.course_name, layout.holes.size(), (layout as PaintedLayout).last_build_ms])
		else:
			push_warning("Course Studio course unreadable: " + GameLaunch.custom_course)
			GameLaunch.custom_course = ""
	if layout == null:
		layout = CourseBuilder.build(course_seed)
	print("[CourseBuilder] ", CourseBuilder.last_report)
	# GOLF_STIMP can override the round's speed. Default rounds use 20% slower greens.
	var stimp_env := OS.get_environment("GOLF_STIMP")
	if stimp_env.is_valid_float():
		SurfacePhysicsCatalog.set_green_speed(stimp_env.to_float())
	else:
		var r := RandomNumberGenerator.new()
		r.seed = course_seed * 977 + 13
		SurfacePhysicsCatalog.set_green_speed(snappedf(r.randf_range(8.0, 10.0), 0.5))
	print("[Greens] ", SurfacePhysicsCatalog.green_speed_label(), " rolling mu %.3f" % SurfacePhysicsCatalog.get_settings(PhysicsEnums.SurfaceType.GREEN).rolling_friction)


func _build_world() -> void:
	# Lighting & sky
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# 25 degrees up: low enough that the sun disc (shaders/golf_sky.gdshader) is actually in
	# frame when the camera faces it, instead of sitting just above the top of the view.
	sun.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_angular_distance = 0.53
	sun.shadow_enabled = not PerformanceSettings.low()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	# The ray-marched cloud/atmosphere shader (_sky_material) recomputes a full
	# radiance cubemap every frame at realtime and has been the trigger for repeated
	# Vulkan device-lost crashes here (fence-wait timeout right after a SKY_PASS
	# breadcrumb) -- almost certainly a GPU TDR from a single frame's cloud march
	# running too long. Default to the cheap procedural sky; the expensive one is
	# still available via GOLF_SKY=cinematic for whoever wants it and can tolerate it.
	if OS.get_environment("GOLF_SKY") == "cinematic":
		sky.sky_material = _sky_material()
	else:
		# Gradient sky + cumulus cover (a generated equirect noise texture alpha-masked into
		# puffs) + a visible sun disc and glow -- one texture sample, no ray march, so it
		# costs nothing like the cinematic shader that kept tripping GPU timeouts.
		var sky_mat := ShaderMaterial.new()
		sky_mat.shader = load("res://shaders/golf_sky.gdshader")
		sky_mat.set_shader_parameter("sky_cover", _cloud_cover_texture())
		sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if OS.get_environment("GOLF_SKY") == "cinematic" else Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.35
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var tm := OS.get_environment("GOLF_TONEMAP")
	if tm == "aces":
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
	elif tm == "linear":
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	elif tm == "agx":
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
	if OS.get_environment("GOLF_TONEMAP_EXPOSURE") != "":
		e.tonemap_exposure = float(OS.get_environment("GOLF_TONEMAP_EXPOSURE"))
	e.fog_enabled = OS.get_environment("GOLF_NOFOG") != "1"
	e.fog_light_color = Color(0.75, 0.83, 0.9)
	e.fog_density = 0.00025
	e.fog_sky_affect = 0.0
	e.ssao_enabled = false
	e.glow_enabled = false
	if not GolfLook.classic() and tm == "":
		GolfLook.apply(e, sun)
	env.name = "WorldEnvironment"
	env.environment = e
	add_child(env)

	# Whole-course TerraBrush clipmap terrain, when explicitly re-enabled -- it has no
	# notion of tiles/regions, so it's intentionally left outside per-hole scoping below.
	if use_terrabrush and TerraTerrain.available() and OS.get_environment("GOLF_NO_TERRABRUSH") != "1":
		terra_root = TerraTerrain.build(layout)
	if terra_root != null:
		await get_tree().process_frame
		call_deferred("add_child", terra_root)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[TerraBrush] ", TerraTerrain.last_report)
		_t("terrabrush")
	# Otherwise terrain tiles are built per-hole by _ensure_hole_region(), called from
	# start_hole() -- see _ready().
	hazards_root = Node3D.new()
	hazards_root.name = "WaterHazards"
	add_child(hazards_root)
	for hz in layout.water_hazards:
		hazards_root.add_child(hz)
		hz.build_visual()
	_t("water")

	# Rough grass (streamed around the camera, not built for the whole course at once)
	var streamer := GrassStreamer.new()
	streamer.configure(layout, course_seed)
	grass_root = streamer
	add_child(grass_root)
	_t("grass")

	# Tee markers + flags for every hole
	for hole in layout.holes:
		add_child(TEE_SIGN.for_layout(layout,hole))
		_add_tee_markers(hole)
		_add_flag(hole)

	resolver = LieSurfaceResolver.new(layout)

	# Trail & aim line meshes
	trail_mesh = MeshInstance3D.new()
	trail_mesh.name = "Trail"
	var tmat := ShaderMaterial.new()
	tmat.shader = SHOT_RIBBON
	tmat.set_shader_parameter("color_start", Color(1, 1, 1, 0.95))
	tmat.set_shader_parameter("color_end", Color(1, 1, 1, 0.95))
	tmat.set_shader_parameter("end_fade", 0.0)  # the tail fades out through vertex alpha
	trail_mesh.material_override = tmat
	trail_mesh.layers = PerformanceSettings.SHOT_LAYER
	add_child(trail_mesh)

	shot_tracker_line = MeshInstance3D.new()
	shot_tracker_line.name = "ShotTracker"
	shot_tracker_line.layers = PerformanceSettings.SHOT_LAYER
	var amat := ShaderMaterial.new()
	amat.shader = SHOT_RIBBON
	amat.set_shader_parameter("color_start", Color(PREVIEW_YELLOW, 0.9))
	amat.set_shader_parameter("color_end", Color(PREVIEW_YELLOW, 0.95))
	amat.set_shader_parameter("core_white", 0.12)
	amat.set_shader_parameter("dash_m", 4.0)
	shot_tracker_line.material_override = amat
	add_child(shot_tracker_line)

	landing_marker = MeshInstance3D.new()
	landing_marker.name = "LandingMarker"
	landing_marker.layers = PerformanceSettings.SHOT_LAYER
	var target := QuadMesh.new()
	target.size = Vector2(2.0, 2.0)  # unit radius, camera-facing; scaled with distance in _draw_shot_tracker
	landing_marker.mesh = target
	var lmat := ShaderMaterial.new()
	lmat.shader = LANDING_TARGET
	lmat.set_shader_parameter("tint", PREVIEW_YELLOW)
	landing_marker.material_override = lmat
	add_child(landing_marker)
	aim_line = shot_tracker_line  # kept for any external references


## Cloud mask for ProceduralSkyMaterial.sky_cover: FBM noise, thresholded through a
## colour ramp so ~40% of the sky carries soft-edged white cumulus, the rest is clear.
static func _cloud_cover_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = 21
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	n.frequency = 0.0035
	var tex := NoiseTexture2D.new()
	tex.width = 1536
	tex.height = 768
	tex.seamless = true
	tex.seamless_blend_skirt = 0.15
	tex.noise = n
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.50, 0.60, 0.72, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(0.93, 0.94, 0.97, 0.55), Color(1, 1, 1, 0.95), Color(1, 1, 1, 1.0)])
	tex.color_ramp = ramp
	return tex


## Physically based sky + ray-marched clouds (user-supplied sky shader) with generated noise.
func _sky_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky_atmosphere.gdshader")
	mat.set_shader_parameter("cloud_shape", _noise3d(11, 0.06, 64, FastNoiseLite.TYPE_CELLULAR))
	mat.set_shader_parameter("cloud_noise", _noise3d(12, 0.15, 32, FastNoiseLite.TYPE_SIMPLEX))
	mat.set_shader_parameter("cloud_color_texture", _noise2d(13, 0.02))
	mat.set_shader_parameter("cirrus_texture", _noise2d(14, 0.05))
	mat.set_shader_parameter("cirrus_distortion_texture", _noise2d(15, 0.03))
	mat.set_shader_parameter("cirrus_mask_texture", _noise2d(16, 0.01))
	var grad := GradientTexture1D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.RED, Color.ORANGE, Color.YELLOW, Color.GREEN, Color.CYAN, Color.BLUE, Color.PURPLE])
	g.offsets = PackedFloat32Array([0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0])
	grad.gradient = g
	mat.set_shader_parameter("rainbow_gradient", grad)
	mat.set_shader_parameter("coverage", 0.22)
	mat.set_shader_parameter("cloud_marches", 32)
	mat.set_shader_parameter("light_marches", 6)
	mat.set_shader_parameter("atmosphere_sample_count", 32)
	mat.set_shader_parameter("exposure", 12.0)
	mat.set_shader_parameter("use_cirrus", false)
	mat.set_shader_parameter("cloud_base_color", Color(0.95, 0.95, 0.97))
	mat.set_shader_parameter("light_strength", 20.0)
	mat.set_shader_parameter("sundisc_intensity", 40.0)
	mat.set_shader_parameter("mie_strength", 0.6)
	mat.set_shader_parameter("cloud_shape_size", 0.6)
	mat.set_shader_parameter("cloud_noise_size", 1.5)
	mat.set_shader_parameter("wind_speed", 0.3)
	mat.set_shader_parameter("noise_wind_speed_mult", 1.0)
	mat.set_shader_parameter("cirrus_opacity", 0.18)
	# Debug overrides for tuning from the command line
	for key in ["exposure", "rayleigh_strength", "mie_strength", "coverage", "atmosphere_density"]:
		var env_v := OS.get_environment("GOLF_SKY_" + key.to_upper())
		if env_v != "":
			mat.set_shader_parameter(key, float(env_v))
	print("[sky] exposure=", mat.get_shader_parameter("exposure"), " mie=", mat.get_shader_parameter("mie_strength"), " fog=", OS.get_environment("GOLF_NOFOG") != "1")
	return mat


static func _noise3d(seed_v: int, frequency: float, size: int, kind: int) -> NoiseTexture3D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = frequency
	n.noise_type = kind
	n.fractal_octaves = 3
	if kind == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	var t := NoiseTexture3D.new()
	t.noise = n
	t.width = size
	t.height = size
	t.depth = size
	t.seamless = true
	t.invert = kind == FastNoiseLite.TYPE_CELLULAR
	return t


static func _noise2d(seed_v: int, frequency: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	return t


## Tee markers: a pair of oversized lacquered golf balls on low dark-green collars, set square
## to the line of play either side of the tee.
func _add_tee_markers(hole: CourseLayout.Hole) -> void:
	var next := hole.waypoints[1] if hole.waypoints.size() > 1 else hole.cup
	var dir := Vector2(next.x - hole.tee.x, next.z - hole.tee.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.95, 0.95, 0.93)
	ball_mat.roughness = 0.25
	ball_mat.clearcoat_enabled = true
	ball_mat.clearcoat = 0.6
	var collar_mat := StandardMaterial3D.new()
	collar_mat.albedo_color = Color(0.06, 0.2, 0.12)
	collar_mat.roughness = 0.4
	for s: float in [-2.6, 2.6]:
		var p := Vector2(hole.tee.x, hole.tee.z) + side * s
		var root := Node3D.new()
		root.name = "TeeMarker"
		root.position = Vector3(p.x, layout.height_at(p.x, p.y), p.y)
		var collar := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.09
		cm.height = 0.06
		collar.mesh = cm
		collar.material_override = collar_mat
		collar.position.y = 0.02
		root.add_child(collar)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		ball.mesh = sm
		ball.material_override = ball_mat
		ball.position.y = 0.15
		root.add_child(ball)
		add_child(root)


## Builds the cup at the same position and mouth radius used by GolfBall's capture
## check. Capture includes a small margin for a ball overlapping the lip, then the
## visible drop animation finishes before the hole is scored.
func _add_flag(hole: CourseLayout.Hole) -> void:
	var root := Node3D.new()
	root.name = "Flag%d" % (hole.index + 1)
	var c := hole.cup
	var gy := layout.height_at(c.x, c.z)
	root.position = Vector3(c.x, gy, c.z)

	# TerrainBuilder cuts the actual tile mesh at the mouth. Normal depth testing
	# now reveals the recessed liner and the ball instead of a solid black cover.
	const CUP_DEPTH := 0.16
	var wall := MeshInstance3D.new()
	wall.name = "CupLiner"
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = GolfBall.CUP_RADIUS
	wall_mesh.bottom_radius = GolfBall.CUP_RADIUS
	wall_mesh.height = CUP_DEPTH
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	wall_mesh.radial_segments = TerrainCupCutout.SEGMENTS
	wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.42, 0.45, 0.41)
	# Only the concave inward-facing side should ever be visible (the outward face is,
	# physically, underground) -- with normal depth testing now in effect this also avoids
	# any near/far-wall ambiguity, since only one side exists to draw at all.
	wall_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	wall_mat.roughness = 1.0
	wall.material_override = wall_mat
	wall.position = Vector3(0, -CUP_DEPTH * 0.5, 0)
	root.add_child(wall)

	var cup_floor := MeshInstance3D.new()
	cup_floor.name = "CupFloor"
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = GolfBall.CUP_RADIUS
	floor_mesh.bottom_radius = GolfBall.CUP_RADIUS
	floor_mesh.height = 0.01
	floor_mesh.radial_segments = TerrainCupCutout.SEGMENTS
	cup_floor.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.015, 0.015, 0.015)
	cup_floor.material_override = floor_mat
	cup_floor.position = Vector3(0, -CUP_DEPTH - 0.005, 0)
	root.add_child(cup_floor)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = GolfBall.CUP_RADIUS - 0.004
	rim_mesh.outer_radius = GolfBall.CUP_RADIUS + 0.006
	rim_mesh.ring_segments = 8
	rim_mesh.rings = TerrainCupCutout.SEGMENTS
	rim.mesh = rim_mesh
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.92, 0.92, 0.88)
	rim.material_override = rim_mat
	rim.position = Vector3(0, -0.004, 0)
	root.add_child(rim)

	# Flagstick: real SoftBody3D cloth (Jolt Physics, see assets/world_flagstick/README.md) --
	# actual gravity sag and wind-driven flutter instead of a fixed curved pose with a vertex
	# ripple on top. Only the nearest hole's flag ever runs live physics (the asset's own
	# distance LOD disables the rest past ~75m and swaps in a cheap wind-shaded fallback
	# mesh), so having all 18 built up front like every other flag here is still fine.
	add_child(root)
	var pole: Node3D = FLAGSTICK_SCENE.instantiate()
	root.add_child(pole)
	pole.phase_offset = hole.index * 0.7  # stops multiple simultaneously-visible flags (rare, but possible near-adjacent holes) fluttering in lockstep
	pole.place_in_cup(root.global_position, 0.12)
	pole.set_wind_velocity(wind_for_hole(hole.index))


func _build_ball() -> void:
	ball = GolfBall.new()
	ball.name = "Ball"
	ball.layout = layout
	ball.resolve_surface = Callable(self, "_resolve_lie_surface")
	ball.obstacle_mask = PropScatter.OBSTACLE_LAYER
	ball.wind = wind_for_hole(0)
	add_child(ball)
	ball.came_to_rest.connect(_on_ball_rest)
	ball.water_hazard_entered.connect(_on_ball_water)
	ball.bunker_entered.connect(_on_ball_bunker)
	ball.out_of_bounds.connect(_on_ball_ob)
	ball.holed.connect(_on_ball_holed)
	ball.first_impact.connect(_on_first_impact)

	swing_rig = ClubSwingRig.new()
	swing_rig.name = "SwingRig"
	add_child(swing_rig)

	# Hidden twin used only to simulate the pre-shot trajectory preview with the
	# exact same flight/bounce/roll code the real shot will run.
	shadow_ball = GolfBall.new()
	shadow_ball.name = "ShadowBall"
	shadow_ball.layout = layout
	shadow_ball.resolve_surface = Callable(self, "_resolve_lie_surface")
	shadow_ball.obstacle_mask = PropScatter.OBSTACLE_LAYER
	shadow_ball.wind = ball.wind
	shadow_ball.log_level = PhysicsLogger.Level.ERROR
	shadow_ball.skip_obstacles = true
	add_child(shadow_ball)
	shadow_ball.visible = false
	shadow_ball.set_physics_process(false)
	shadow_ball.set_process(false)


func _build_camera_node() -> void:
	camera = OrbitCamera.new()
	camera.name = "Camera"
	add_child(camera)
	camera.current = true
	camera.cull_mask = 0xFFFFF & ~MINIMAP_LAYER  # never show minimap-only markers in the main view


## Small top-down SubViewport, always framing the whole current hole tee-to-green
## (shares the main World3D, so it needs no duplicate geometry or lighting). Shown
## in the HUD's top-right corner while playing in first-person/follow camera modes.
func _build_minimap() -> void:
	if DisplayServer.get_name() == "headless":
		return  # SubViewports are unreliable under the headless dummy renderer (tests/servers)
	minimap_viewport = SubViewport.new()
	minimap_viewport.name = "MinimapViewport"
	minimap_viewport.size = Vector2i(MINIMAP_HEIGHT_PX, MINIMAP_HEIGHT_PX)  # resized per hole in _update_minimap_frame
	minimap_viewport.own_world_3d = false
	minimap_viewport.transparent_bg = false
	minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(minimap_viewport)

	minimap_camera = Camera3D.new()
	minimap_camera.name = "MinimapCamera"
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.cull_mask = 0xFFFFF & ~(PerformanceSettings.DETAIL_LAYER | PerformanceSettings.TREE_LAYER | PerformanceSettings.SHOT_LAYER)
	minimap_camera.far = 3000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.56, 0.34)
	env.fog_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	minimap_camera.environment = env
	minimap_viewport.add_child(minimap_camera)
	minimap_camera.current = true

	minimap_pin_marker = MeshInstance3D.new()
	minimap_pin_marker.name = "MinimapPin"
	# A flat flag icon instead of a plain dot -- lies in the XZ plane (FACE_Y) so it reads
	# correctly under the minimap's top-down orthogonal camera; which way it faces just
	# rotates with the hole like any other flat icon would, which is fine for a symbol.
	var pm := QuadMesh.new()
	pm.size = Vector2(20.0, 20.0)
	pm.orientation = PlaneMesh.FACE_Y
	minimap_pin_marker.mesh = pm
	minimap_pin_marker.layers = MINIMAP_LAYER
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# The minimap camera views this from very far away, so the icon file is now cropped
	# tightly to its actual content (no big transparent margin left to get averaged/diluted
	# away at that tiny effective on-screen size). Load the real imported Texture2D resource,
	# not Image.load_from_file() on the raw res:// path -- that only works when running from
	# loose source files; in an exported build it silently fails (Godot warns about exactly
	# this), leaving no texture at all and this material rendering as a flat opaque white
	# square instead -- which is exactly what shipped.
	pmat.albedo_texture = load("res://assets/flagpin/flagpin_icon_ui.png")
	pmat.no_depth_test = true
	pmat.render_priority = 11  # above the ball marker so the two never fight if they overlap
	minimap_pin_marker.material_override = pmat
	add_child(minimap_pin_marker)

	_minimap_built = true


## Reframe the minimap on the whole current hole (tee through green, including its
## bunkers/ponds) and place the pin marker. Called once per hole from start_hole().
func _update_minimap_frame(hole: CourseLayout.Hole) -> void:
	if minimap_camera == null:
		return
	var tee := Vector2(hole.tee.x, hole.tee.z)
	var forward := Vector2(hole.cup.x - tee.x, hole.cup.z - tee.y)
	if forward.length() < 0.01:
		forward = Vector2(0.0, -1.0)
	forward = forward.normalized()
	var right := Vector2(-forward.y, forward.x)

	# Measure the hole in its own along/across frame (not world XZ) so a long, narrow
	# hole gets a long, narrow crop instead of a wide square that spills into the
	# corridors on either side -- corridors are only ~130 m apart, well inside a
	# world-space bounding circle for a 400+ m hole.
	var pts: Array[Vector2] = [tee]
	pts.append_array(layout.feature_points(hole))
	var a0 := INF
	var a1 := -INF
	var r0 := INF
	var r1 := -INF
	for p in pts:
		var d := p - tee
		var along := d.dot(forward)
		var across := d.dot(right)
		a0 = minf(a0, along)
		a1 = maxf(a1, along)
		r0 = minf(r0, across)
		r1 = maxf(r1, across)
	var margin := hole.fairway_half_width + hole.green_radius + 15.0
	var along_extent := maxf((a1 - a0) + margin * 2.0, 60.0)
	var across_extent := maxf((r1 - r0) + margin * 2.0, 60.0)
	var mid_along := (a0 + a1) * 0.5
	var mid_across := (r0 + r1) * 0.5
	var center := tee + forward * mid_along + right * mid_across
	var ground_y := layout.height_at(center.x, center.y)
	minimap_camera.global_position = Vector3(center.x, ground_y + 300.0, center.y)
	minimap_camera.look_at(minimap_camera.global_position + Vector3.DOWN, Vector3(forward.x, 0.0, forward.y))
	# Resize the viewport itself to the hole's own along:across ratio (clamped so a
	# very straight hole doesn't become a sliver and a very bent one doesn't become a
	# square) so width and height each get a tight, independent fit -- a fixed-aspect
	# viewport forced the "size" to follow the long axis on both, pulling in whatever
	# sat in the neighbouring 130 m corridor either side.
	var ratio := clampf(across_extent / along_extent, 0.2, 0.85)
	minimap_viewport.size = Vector2i(maxi(int(MINIMAP_HEIGHT_PX * ratio), 56), MINIMAP_HEIGHT_PX)
	minimap_camera.size = along_extent  # keep_aspect = KEEP_HEIGHT (default): this covers the height exactly
	# The cup's own ground height, not `ground_y` (sampled at the hole's along/across centre
	# above, for framing the camera) -- holes slope tee-to-green, so reusing that for the pin
	# marker could place it well off the real terrain height at the cup's own position,
	# occasionally ending up buried under the (taller, real) terrain there and invisible.
	var cup_ground_y := layout.height_at(hole.cup.x, hole.cup.z)
	minimap_pin_marker.global_position = Vector3(hole.cup.x, cup_ground_y + 1.0, hole.cup.z)
	_minimap_center = center
	_minimap_forward = forward
	_minimap_right = right
	_minimap_scale = along_extent / float(MINIMAP_HEIGHT_PX)
	_minimap_elapsed = 1.0
	_minimap_last_ball = Vector3(INF, INF, INF)



func _build_camera() -> void:
	camera.target = ball
	camera.height_at_ground = Callable(layout, "height_at")


## The ResolveLieSurface delegate handed to the ball.
func _resolve_lie_surface(point: Vector3) -> Dictionary:
	return resolver.resolve(point)


func start_hole(index: int) -> void:
	if _hole_loading:
		return
	var hole := layout.holes[index]
	await _ensure_hole_region(hole)
	hole_index = index
	strokes = 0
	_shot_yd = 0.0
	_mulligan_valid = false
	ball.cup_position = Vector3(hole.cup.x, layout.height_at(hole.cup.x, hole.cup.z), hole.cup.z)
	ball.wind = wind_for_hole(index)
	shadow_ball.wind = ball.wind
	ball.place(Vector2(hole.tee.x, hole.tee.z))
	_face_cup()
	camera.mode = OrbitCamera.Mode.AIM
	camera.distance = OrbitCamera.DEFAULT_AIM_DISTANCE
	club_index = 0
	phase = SwingPhase.IDLE
	trail_mesh.mesh = null
	_update_minimap_frame(hole)
	_refresh_hud()
	hud.clear_shot_result()
	hud.show_hole_intro(index + 1, _hole_info(index)["name"], hole.par, int(_hole_info(index).get("yd", roundi(hole.length_yd))),
		wind_report(ball.wind, Vector2(hole.cup.x - hole.tee.x, hole.cup.z - hole.tee.z)))


## Deterministic per course seed and hole, so R (restart) and replays of the same course play
## in the same conditions while each hole still plays differently from the last.
static func wind_for_hole(index: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([course_seed, index, "wind"])
	var speed := WIND_MAX_MPS * pow(rng.randf(), 1.6)
	var angle := rng.randf() * TAU
	return Vector3(sin(angle), 0.0, -cos(angle)) * speed


## Tee-box read of the wind relative to the line of play (tee -> cup), e.g.
## "Wind 9 mph: into you, right-to-left".
static func wind_report(wind: Vector3, play_dir: Vector2) -> String:
	var mph := wind.length() / ShotSetup.MPS_PER_MPH
	if mph < 2.0 or play_dir.length() < 0.01:
		return "Calm on this hole"
	var w := Vector2(wind.x, wind.z).normalized()
	var fwd := play_dir.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var along := w.dot(fwd)
	var across := w.dot(right)
	var parts: Array[String] = []
	if along > 0.38:
		parts.append("helping")
	elif along < -0.38:
		parts.append("into you")
	if absf(across) > 0.38:
		parts.append("left-to-right" if across > 0.0 else "right-to-left")
	return "Wind %.0f mph: %s" % [mph, ", ".join(parts)]


## Freezes/restores gameplay input and physics for the duration of a loading screen --
## nothing should be able to swing, drag the camera, or have the ball keep moving while the
## course underneath it is being torn down and rebuilt.
func _set_transition_active(active: bool) -> void:
	if active:
		_tracker_running = false
		_tracker_inputs.clear()
	if grass_root is GrassStreamer:
		grass_root.set_suspended(active)
	_transitioning = active
	if is_instance_valid(camera):
		camera.set_process(not active)
		camera.set_process_unhandled_input(not active)
		if active:
			camera._dragging = false
	if is_instance_valid(ball):
		ball.set_physics_process(not active)
	if is_instance_valid(hud):
		hud.visible = not active
		hud.set_process(not active)
		if active:
			hud.strike_selector._dragging = false


## Instantly places the camera at the new hole's tee view instead of letting its normal
## smooth-follow lerp glide across the map from wherever the previous hole left it --
## camera processing is frozen during the load anyway (_set_transition_active), so without
## this it would jump-cut mid-lerp the first frame gameplay resumes.
func _snap_camera_to_tee() -> void:
	var direction := camera.aim_direction()
	camera.global_position = ball.global_position - direction * camera.distance + Vector3.UP * 2.0
	camera._smooth_pos = camera.global_position
	camera._smooth_look = ball.global_position + direction * 12.0 + Vector3.UP * 0.5
	camera.look_at(camera._smooth_look, Vector3.UP)


## Player-facing hole navigation (N key, holing out): covers the old hole with the loading
## screen, freezes gameplay, does the real start_hole() work underneath, then uncovers.
## start_hole() itself stays the plain, synchronous-ish entry point scripts/tests use
## directly (see _ensure_hole_region's "owns_screen" dedup -- it detects the screen this
## already put up and just updates its progress instead of layering a second one on top).
func transition_to_hole(index: int) -> void:
	if _transitioning or index < 0 or index >= layout.holes.size():
		return
	_set_transition_active(true)
	var hole := layout.holes[index]
	_loading_screen = LOADING_SCENE.instantiate()
	add_child(_loading_screen)
	_loading_screen.begin_hole(index + 1, _hole_info(index)["name"], hole.par, int(_hole_info(index).get("yd", roundi(hole.length_yd))))
	if DisplayServer.get_name() != "headless":
		await _loading_screen.covered
	else:
		await get_tree().process_frame
		await get_tree().process_frame
	await start_hole(index)
	_snap_camera_to_tee()
	_loading_screen.update_progress(0.9, "Your tee is ready…")
	await get_tree().process_frame
	_loading_screen.mark_ready()
	if DisplayServer.get_name() != "headless":
		await _loading_screen.ride_finished
	_loading_screen.queue_free()
	_loading_screen = null
	_set_transition_active(false)


## Minimum ball-to-cup distance (metres) this will actually turn the camera for. Any
## closer and the direction is too short to be a stable bearing -- a few centimetres of
## rest-position noise between putts can swing it by nearly 180°, which the camera then
## visibly whips around to follow. Below this, just keep the last aim_yaw (already
## pointing roughly at the cup from the previous, farther-away shot) instead of
## recomputing a jittery direction from a near-zero vector.
const FACE_CUP_MIN_DIST := 1.2

func _face_cup() -> void:
	var to_cup := ball.cup_position - ball.global_position
	to_cup.y = 0.0
	if to_cup.length() < FACE_CUP_MIN_DIST:
		return
	# Course Studio doglegs and curves: aim down the hole's line of play (a drive ahead at
	# most), not straight at a pin hidden round the corner.
	if layout is PaintedLayout:
		var b := Vector2(ball.global_position.x, ball.global_position.z)
		var p := (layout as PaintedLayout).aim_point(hole_index, b, 215.0)
		if p.distance_to(b) >= FACE_CUP_MIN_DIST:
			to_cup = Vector3(p.x - b.x, 0.0, p.y - b.y)
	camera.aim_yaw = atan2(-to_cup.x, -to_cup.z)


func _current_club() -> Clubs.Club:
	return Clubs.bag()[club_index]


func _unhandled_input(event: InputEvent) -> void:
	if ball == null:
		return
	if hub != null and hub.is_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("hub_toggle"):
			hub.close()
		return  # the clubhouse owns input while it's up
	if event.is_action_pressed("ui_cancel"):
		hud.toggle_help()
		return
	if hud != null and hud.is_help_open():
		return  # swallow gameplay input while the how-to-play overlay is open
	if event.is_action_pressed("hub_toggle"):
		if phase == SwingPhase.IDLE and not _transitioning and not _auto_putt_busy:
			hub.open()
		return
	if event.is_action_pressed("reset_hole"):
		if tracker != null:
			tracker.restart_hole()
		start_hole(hole_index)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_J:
			course_seed = randi() % 100000
			hazard_seed = course_seed
			get_tree().reload_current_scene()
			return
		if k == KEY_N and phase != SwingPhase.IN_FLIGHT:
			if tracker != null:
				tracker.skip_hole()
			if hole_index + 1 >= round_start_index() + round_holes():
				# Skipping off the end of the round abandons it: no payout, no restock.
				hud.show_message("Round abandoned (hole skipped). Back to the 1st tee.", 2.5)
				_begin_round()
				transition_to_hole(round_start_index())
			else:
				hud.show_message("Hole skipped: this round can't be completed for pay.", 2.5)
				transition_to_hole(hole_index + 1)
			return
		if k == KEY_H and not layout.authored_hazards:
			hazard_seed = randi() % 100000
			get_tree().reload_current_scene()
			return
		if k == KEY_M:
			_mulligan()
			return
	if event.is_action_pressed("cam_toggle"):
		if camera.mode == OrbitCamera.Mode.OVERHEAD:
			camera.set_mode(OrbitCamera.Mode.AIM if phase != SwingPhase.IN_FLIGHT else OrbitCamera.Mode.FOLLOW)
		else:
			camera.set_mode(OrbitCamera.Mode.OVERHEAD)
		return
	# In the bird's-eye view the arrow keys pan the camera instead of changing clubs / aim
	if camera.mode == OrbitCamera.Mode.OVERHEAD and event is InputEventKey:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_LEFT or kc == KEY_RIGHT or kc == KEY_UP or kc == KEY_DOWN:
			return
	if phase == SwingPhase.IN_FLIGHT:
		return
	if event.is_action_pressed("club_next"):
		# W/up: toward the top of the bag (Driver, index 0 -- see Clubs.bag()).
		club_index = maxi(club_index - 1, 0)
		_refresh_hud()
	elif event.is_action_pressed("club_prev"):
		# S/down: toward the bottom of the bag (Putter, the last index).
		club_index = mini(club_index + 1, Clubs.bag().size() - 1)
		_refresh_hud()
	elif event.is_action_pressed("swing"):
		# No swinging blind: the bird's-eye view (C) and the Z landing-spot scout both look
		# away from the ball, so the swing is locked until the player is back behind it.
		if camera.mode == OrbitCamera.Mode.OVERHEAD or camera.scouting or Input.is_physical_key_pressed(KEY_Z):
			hud.show_message("Back to the ball to swing (%s)" % ("press C" if camera.mode == OrbitCamera.Mode.OVERHEAD else "release Z"), 1.5)
			return
		match phase:
			SwingPhase.IDLE:
				if _current_club().illegal_kind == "auto_putt":
					_auto_putt()
					return
				phase = SwingPhase.POWER
				power = 0.0
				power_dir = 1.0
			SwingPhase.POWER:
				locked_power = power
				_fire_shot(locked_power, strike)


func _process(delta: float) -> void:
	_update_fast_forward()
	if ball == null or _transitioning or _hole_loading:
		return
	if grass_root is GrassStreamer:
		var grass_focus: Vector3 = ball.global_position
		if camera.scouting:
			grass_focus = camera.scout_target
		elif camera.mode == OrbitCamera.Mode.OVERHEAD:
			grass_focus = camera.overhead_focus_point
		grass_root.focus_position = Vector2(grass_focus.x, grass_focus.z)
		grass_root.view_position = camera.global_position
	# Terrain/props only exist within active_region -- shrunk by a margin so the overhead
	# camera's pan can't push its look-at centre right up to the edge (see OVERHEAD_TILT_MAX
	# for the matching cap on tilting toward the horizon at that edge). Falls back to the
	# unshrunk region if it's too small for the margin rather than an inverted Rect2.
	if active_region.size.x > 130.0 and active_region.size.y > 130.0:
		camera.pan_bounds = active_region.grow(-65.0)
	else:
		camera.pan_bounds = active_region
	hud.set_shot_phase(phase)
	match phase:
		SwingPhase.POWER:
			power += power_dir * POWER_SPEED * delta
			if power >= 100.0:
				power = 100.0
				power_dir = -1.0
			elif power <= 0.0:
				power = 0.0
				power_dir = 1.0
			hud.power_bar.value = power
		SwingPhase.IN_FLIGHT:
			trail_mesh.visible = true
			_update_trail()
			_push_interactor()
			hud.set_flight(ball.velocity.length() / ShotSetup.MPS_PER_MPH,
				(ball.global_position.y - layout.height_at(ball.global_position.x, ball.global_position.z)) * ShotSetup.FEET_PER_METER,
				ball.on_ground, _shot_distance_yd())
		_:
			pass
	if phase != SwingPhase.IN_FLIGHT:
		var club := _current_club()
		swing_rig.show_at_address(club.model_id, club.condition, ball.global_position, camera.aim_direction(), ball.distance_to_cup_yd())
		_update_shot_tracker(delta)
		_push_interactor()
		# Z: hold to snap-look at the anticipated landing spot, release to fly back.
		camera.scouting = Input.is_physical_key_pressed(KEY_Z)
		camera.scout_target = landing_marker.global_position
	else:
		camera.scouting = false
	_update_minimap(delta)
	_update_hole_marker()
	_update_wind_arrow()
	_sand_trail_tick += 1
	if sand_trail != null and _sand_trail_tick % 6 == 0:
		sand_trail.flush()


## Hold the swing button while the ball is moving to fast-forward the shot. Only a fresh
## press counts, so keeping the button down after the strike doesn't speed the shot up.
func _update_fast_forward() -> void:
	var held := Input.is_action_pressed("swing")
	if not held:
		_ff_armed = true
	var moving := ball != null and phase == SwingPhase.IN_FLIGHT and ball.is_moving and not _transitioning and not _hole_loading
	var overlay_open := (hud != null and hud.is_help_open()) or (hub != null and hub.is_open())
	var on := moving and held and _ff_armed and not overlay_open
	var speed := FAST_FORWARD_SCALE if on else 1.0
	if Engine.time_scale != speed:
		Engine.time_scale = speed
		if hud != null:
			hud.set_fast_forward(speed)


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the menu or a reloaded course running fast


## The club's buildings (Course Manager) when this is the club's course: each at the level it's
## built to, a staked-out "coming soon" site while it's only placed. Walls block the ball.
func _build_facilities() -> void:
	if facilities_root != null:
		facilities_root.queue_free()
		facilities_root = null
	if not (layout is PaintedLayout):
		return
	var gs := GameState.current
	if gs == null or not gs.business.owned or gs.business.course_path != GameLaunch.custom_course or gs.business.placements.is_empty():
		return
	var painted: PaintedCourse = (layout as PaintedLayout).course
	var items: Array = []
	for t in gs.business.placements:
		var pl: Dictionary = gs.business.placements[t]
		items.append({"type": t, "pos": pl["pos"], "rot": pl["rot"], "level": gs.business.level(t), "name": painted.course_name if painted != null else "", "rooms": gs.business.rooms})
	facilities_root = FacilityBuilder.build(items, func(p: Vector2) -> float: return layout.height_at(p.x, p.y), true)
	add_child(facilities_root)


## Push the ball position into the grass/vegetation shaders only when it actually
## moved, instead of every frame.
func _push_interactor() -> void:
	if not is_finite(_last_interactor.x) or _last_interactor.distance_squared_to(ball.global_position) > 0.0001:
		RoughGrass.set_interactor(ball.global_position)
		if sand_trail != null and ball.on_ground and ball.current_lie == CourseLayout.SURFACE_BUNKER:
			sand_trail.stamp(Vector2(ball.global_position.x, ball.global_position.z))
		_last_interactor = ball.global_position


## Shared by the real shot and the preview predictor, so the tracker line can never
## show a different flight than the one the ball will actually fly.
##  - pfrac: 0..1, how well the power tap was timed (1 = perfect, full swing).
##  - hit: strike point on the ball face (see StrikeSelector) -- x shapes the shot
##    (heel/toe -> push/pull + side spin), y is loft/spin (low/high strike).
func _shot_params(club: Clubs.Club, pfrac: float, hit: Vector2, lie: int, aim: Vector3) -> Dictionary:
	# Strike-point sensitivity is deliberately gentle: a full heel/toe or low/high
	# strike shapes the shot, it does not wreck it.
	var shape := clampf(hit.x, -1.0, 1.0)
	# Equipment layer (data/club_catalog.json via Clubs.make_club, bounded by economy.json):
	#  - control  >1: heel/toe shaping is more precise, i.e. less unintended push/side spin;
	#  - forgiveness >1: off-centre strikes cost less speed, <1 they cost more;
	#  - distance: ball-speed multiplier; spin: backspin multiplier;
	#  - condition: a worn club loses up to a few % of speed (dispersion is applied in
	#    _fire_shot only, never in this shared preview path). Loaners are all 1.0, so the
	#    stock bag plays exactly as before.
	var sidespin := shape * 1300.0 / club.control
	var push_deg := shape * 3.0 / club.control
	var dir := aim.rotated(Vector3.UP, deg_to_rad(-push_deg))
	var cond_pen := (1.0 - clampf(club.condition, 0.0, 1.0)) * EconomyConfig.modifier_bound("condition_speed_penalty_max", 0.03)
	if club.is_putter:
		# Putter forgiveness: a heel/toe putt loses a little pace on an unforgiving head. Small
		# on purpose -- rarity and scratches must never make putting random.
		var putt_pen := absf(shape) * 0.05 * clampf(2.0 - club.forgiveness, 0.5, 1.5)
		return {"putter": true, "dir": dir, "speed_mps": lerpf(0.4, 9.0, pfrac * pfrac) * (1.0 - putt_pen) * (1.0 - cond_pen * 0.5)}

	var low := clampf(-hit.y, 0.0, 1.0)   # strike below centre: more loft & spin, less speed
	var high := clampf(hit.y, 0.0, 1.0)   # strike above centre: flatter, less spin, more roll
	var off_center := clampf(absf(hit.y), 0.0, 1.0)
	var off_pen := clampf(off_center * 0.25 / club.forgiveness, 0.0, 0.4)
	var speed_mph := club.ball_speed_mph * club.distance * lerpf(0.35, 1.0, pfrac) * (1.0 - off_pen) * (1.0 - cond_pen)
	var backspin := club.backspin_rpm * club.spin * lerpf(0.7, 1.0, pfrac) * (1.0 + low * 0.4) * (1.0 - high * 0.3)
	var vla := maxf(club.vla_deg + low * 7.0 - high * 4.0, 2.0)
	# Lie penalties (rough: flyer/less spin & speed, bunker: much less speed, more loft)
	if CourseLayout.engine_surface(lie) == PhysicsEnums.SurfaceType.ROUGH:
		speed_mph *= 0.9
		backspin *= 0.65
		vla += 1.5
	elif lie == CourseLayout.SURFACE_FIRST_CUT:
		speed_mph *= 0.97
		backspin *= 0.85
		vla += 0.5
	elif lie == CourseLayout.SURFACE_BUNKER:
		speed_mph *= 0.72
		backspin *= 0.5
		vla += 6.0
	return {"putter": false, "dir": dir, "speed_mph": speed_mph, "vla": vla, "backspin": backspin, "sidespin": sidespin}


func _fire_shot(pwr: float, hit: Vector2, override_sp: Dictionary = {}) -> void:
	_tracker_running = false
	_tracker_inputs.clear()
	var club := _current_club()
	var aim := camera.aim_direction()
	# Dispersion: a small random push on the *fired* shot only, scaled by how far off the
	# sweet spot the strike was, the club's own dispersion and its condition. Bounded by
	# economy.json; loaners have none, putters at most a fraction of a degree.
	var jitter := _dispersion_deg(club, hit)
	if jitter != 0.0:
		aim = aim.rotated(Vector3.UP, deg_to_rad(jitter))
	_mulligan_pos = ball.global_position
	_mulligan_strokes = strokes
	_mulligan_water_balls = water_balls
	_mulligan_bunker_visits = bunker_visits
	_mulligan_valid = true
	strokes += 1
	if tracker != null:
		tracker.record_stroke(club)
		if tracker.sandbox and GameState.current != null:
			GameState.current.round_in_progress = false
	_sync_round_in_progress()
	_pre_shot_pos = ball.global_position
	_shot_yd = 0.0
	phase = SwingPhase.IN_FLIGHT
	_ff_armed = false
	shot_tracker_line.visible = false
	landing_marker.visible = false
	# IN_FLIGHT also covers the backswing, before launch()/putt() clears the
	# ball's path. Retire the previous shot now so it cannot flash before impact.
	ball.trail.clear()
	trail_mesh.mesh = null
	trail_mesh.visible = false
	hud.minimap_shot_overlay.set_tail(PackedVector3Array())
	hud.power_bar.value = 0
	hud.result_label.text = ""
	hud.clear_shot_result()

	var lie := ball.current_lie
	# Mistimed power taps shorten the shot below the full-swing distance shown by
	# the tracker; only a perfectly timed tap (pwr == 100) reaches it.
	var pfrac := clampf(pwr / 100.0, 0.05, 1.0)
	var sp := _shot_params(club, pfrac, hit, lie, aim) if override_sp.is_empty() else override_sp
	var est_carry_yd := Clubs.stock_carry_yd(club_index, pfrac)
	# The camera stays in the player's aim view through the swing (so the club is
	# actually visible swinging) and only cuts to FOLLOW at the moment of impact,
	# which is also when the ball is actually launched -- see _impact_shot().
	if skip_swing_animation or swing_rig == null:
		_impact_shot(club, sp, lie, hit, est_carry_yd)
	else:
		swing_rig.swing(func() -> void: _impact_shot(club, sp, lie, hit, est_carry_yd), club.is_putter)


## The instant the club reaches the ball: launches it, plays the shot sound and cuts
## the camera to follow the flight. Runs synchronously and immediately when
## skip_swing_animation is set (tests, tools) or there is no visual club to swing;
## otherwise it is the impact callback of swing_rig.swing(), fired partway through
## the animated downswing so the ball leaves exactly when the club gets there.
func _impact_shot(club: Clubs.Club, sp: Dictionary, lie: int, hit: Vector2, est_carry_yd: float) -> void:
	camera.mode = OrbitCamera.Mode.FOLLOW
	if lie == CourseLayout.SURFACE_BUNKER and not sp["putter"]:
		var toward: Vector3 = sp["dir"]
		_spawn_sand_blast(ball.global_position, Vector3(toward.x, 0.0, toward.z))
	if club.illegal_kind == "grenade":
		audio.play_grenade(ball.global_position)
		_grenade_effect(ball.global_position)
	else:
		audio.play_shot(club, lie, hit, ball.global_position, est_carry_yd)
	if sp["putter"]:
		ball.putt(sp["speed_mps"], sp["dir"])
	else:
		ball.launch(sp["speed_mph"], sp["vla"], sp["backspin"], sp["sidespin"], sp["dir"])
	strike = Vector2.ZERO
	hud.strike_selector.reset()
	_refresh_hud()


## M: replay the last shot from where it was hit, instead of restarting the whole hole (R).
## Undoes the stroke and any water/bunker penalty count the shot added; one mulligan per
## shot -- pressing M again with nothing new fired since does nothing.
func _mulligan() -> void:
	if not _mulligan_valid or ball == null:
		return
	if tracker != null:
		tracker.undo_last_stroke()
	strokes = _mulligan_strokes
	water_balls = _mulligan_water_balls
	bunker_visits = _mulligan_bunker_visits
	ball.place(Vector2(_mulligan_pos.x, _mulligan_pos.z))
	phase = SwingPhase.IDLE
	camera.mode = OrbitCamera.Mode.AIM
	_face_cup()
	_mulligan_valid = false
	_shot_yd = 0.0
	hud.show_callout("Mulligan", "Take it again", "info", 1.2)
	_refresh_hud()


func _on_first_impact(pos: Vector3, _surface: int) -> void:
	audio.play_bounce(pos)


func _shot_distance_yd() -> float:
	var d := ball.global_position - _pre_shot_pos
	_shot_yd = Vector2(d.x, d.z).length() * ShotSetup.YARDS_PER_METER
	return _shot_yd


func _on_ball_rest(_pos: Vector3, lie: int) -> void:
	_shot_distance_yd()
	phase = SwingPhase.IDLE
	camera.mode = OrbitCamera.Mode.AIM
	_face_cup()
	var d := ball.distance_to_cup_yd()
	hud.show_shot_result(ball.carry_distance_m * ShotSetup.YARDS_PER_METER, ball.total_distance_m * ShotSetup.YARDS_PER_METER,
		ball.max_height_m * ShotSetup.FEET_PER_METER, d, CourseLayout.surface_label(lie), lie)
	club_index = Clubs.suggest(d, lie == PhysicsEnums.SurfaceType.GREEN)
	_refresh_hud()


func _on_ball_water(hz: WaterHazard, pos: Vector3) -> void:
	strokes += 1
	water_balls += 1
	var where: String = hz.hazard_name if hz != null else "the water"
	hud.show_callout("Splash", "In %s   ·   +1 penalty stroke" % where, "bad")
	hud.show_shot_penalty("Water hazard", "%s   ·   carry %.0f yds" % [where, ball.carry_distance_m * ShotSetup.YARDS_PER_METER])
	_spawn_splash(pos)
	_refresh_hud()
	_drop_ball(_pre_shot_pos)


func _on_ball_bunker(pos: Vector3, plugged: bool) -> void:
	bunker_visits += 1
	hud.show_callout("Bunker", "Plugged in the sand" if plugged else "Rolled into the sand", "bad", 1.8)
	if sand_trail != null:
		sand_trail.stamp(Vector2(pos.x, pos.z), 1.6 if plugged else 1.0)
	_refresh_hud()


func _spawn_splash(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 90
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.14
	p.color = Color(0.75, 0.9, 1.0, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.92, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.material = mat
	p.mesh = sm
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## A soft round white puff (alpha falls off to the edge), built synchronously and cached: a
## GradientTexture2D is generated in the background and draws black for its first frames.
static var _puff_texture: ImageTexture
const SAND_DUST_SHADER := preload("res://shaders/sand_dust.gdshader")

static func _soft_puff_texture() -> ImageTexture:
	if _puff_texture == null:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in range(size):
			for x in range(size):
				var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
		_puff_texture = ImageTexture.create_from_image(img)
	return _puff_texture


## Bunker shot: a spray of sand grains thrown up and toward the target, a soft dust cloud that
## drifts up and fades, and a crater stamped where the ball sat.
func _spawn_sand_blast(pos: Vector3, toward: Vector3) -> void:
	var fwd := toward.normalized() if toward.length() > 0.01 else Vector3.FORWARD
	var sand_ramp := Gradient.new()
	sand_ramp.colors = PackedColorArray([Color(0.84, 0.74, 0.55), Color(0.7, 0.6, 0.43)])

	# grains: a fast, dense burst that falls back to the sand
	var grains := CPUParticles3D.new()
	grains.one_shot = true
	grains.explosiveness = 0.92
	grains.amount = 170
	grains.lifetime = 1.1
	grains.direction = (Vector3.UP * 1.2 + fwd).normalized()
	grains.spread = 38.0
	grains.initial_velocity_min = 2.5
	grains.initial_velocity_max = 8.0
	grains.gravity = Vector3(0, -9.8, 0)
	grains.damping_min = 0.5
	grains.damping_max = 1.5
	grains.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	grains.emission_sphere_radius = 0.08
	grains.scale_amount_min = 0.012
	grains.scale_amount_max = 0.035
	grains.color_initial_ramp = sand_ramp
	# unshaded so the grains read as sand even inside the golfer's shadow
	var grain_mat := StandardMaterial3D.new()
	grain_mat.vertex_color_use_as_albedo = true
	grain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var grain_mesh := SphereMesh.new()
	grain_mesh.radius = 0.5
	grain_mesh.height = 1.0
	grain_mesh.radial_segments = 6
	grain_mesh.rings = 3
	grain_mesh.material = grain_mat
	grains.mesh = grain_mesh
	grains.position = pos
	grains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grains)
	grains.emitting = true

	# dust: soft billboard puffs that rise slowly, swell and fade
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.amount = 40
	dust.lifetime = 2.4
	dust.direction = (Vector3.UP * 1.5 + fwd).normalized()
	dust.spread = 55.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 2.2
	dust.gravity = Vector3(0, 0.15, 0)
	dust.damping_min = 1.2
	dust.damping_max = 2.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 0.15
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.1
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.5))
	swell.add_point(Vector2(1.0, 1.6))
	dust.scale_amount_curve = swell
	var puff_mat := ShaderMaterial.new()
	puff_mat.shader = SAND_DUST_SHADER
	puff_mat.set_shader_parameter("puff", _soft_puff_texture())
	puff_mat.set_shader_parameter("tint", Color(0.7, 0.63, 0.5, 0.7))
	var puff := QuadMesh.new()
	puff.material = puff_mat
	dust.mesh = puff
	dust.position = pos + Vector3.UP * 0.1
	# a transparent billboard still casts a solid shadow -- a black disc on the sand
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	dust.emitting = true

	if sand_trail != null:
		sand_trail.stamp(Vector2(pos.x, pos.z), 1.4)
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		grains.queue_free()
		dust.queue_free())


func _on_ball_ob(_pos: Vector3) -> void:
	strokes += 1
	hud.show_callout("Out of bounds", "+1 penalty stroke", "bad")
	_drop_ball(_pre_shot_pos)


func _drop_ball(pos: Vector3) -> void:
	await get_tree().create_timer(1.2).timeout
	ball.place(Vector2(pos.x, pos.z))
	phase = SwingPhase.IDLE
	camera.mode = OrbitCamera.Mode.AIM
	_face_cup()
	club_index = Clubs.suggest(ball.distance_to_cup_yd(), ball.current_lie == PhysicsEnums.SurfaceType.GREEN)
	_refresh_hud()


func _on_ball_holed(_pos: Vector3) -> void:
	var hole := layout.holes[hole_index]
	var rel := strokes - hole.par
	var names := {-3: "Albatross!", -2: "Eagle!", -1: "Birdie!", 0: "Par", 1: "Bogey", 2: "Double bogey"}
	var label: String = names.get(rel, "+%d" % rel if rel > 0 else "%d" % rel)
	if strokes == 1:
		label = "Hole in one!"
	scores.append(strokes)
	var tone := "great" if rel < 0 else ("good" if rel == 0 else "info")
	hud.show_callout(label.trim_suffix("!"), "In the hole   ·   %d stroke%s   ·   %s" % [strokes, "" if strokes == 1 else "s", "E" if rel == 0 else "%+d" % rel], tone, 2.6)
	audio.play_holed()
	if rel <= 0:
		audio.play_crowd_cheer()
	phase = SwingPhase.IN_FLIGHT
	if tracker != null:
		tracker.finish_hole(hole_index - round_start_index(), strokes)
	await get_tree().create_timer(3.0).timeout
	if hole_index + 1 < round_start_index() + round_holes():
		await transition_to_hole(hole_index + 1)
	else:
		_finish_round()


func _refresh_hud() -> void:
	var hole := layout.holes[hole_index]
	var club := _current_club()
	hud.set_hole(hole_index + 1, _hole_info(hole_index)["name"], hole.par, int(_hole_info(hole_index).get("yd", roundi(hole.length_yd))))
	var total_score := 0
	var total_par := 0
	for i in range(scores.size()):
		total_score += scores[i]
		total_par += layout.holes[round_start_index() + i].par
	hud.set_score(strokes, total_score, total_score - total_par, water_balls, bunker_visits)
	hud.set_club(club.name, club.short,
		EconomyConfig.condition_grade(club.condition) if not club.is_starter and club.instance_id != "" else "",
		club.model_id)
	if GameState.current != null:
		hud.wallet_footer.visible = true
		hud.cash_label.text = str(GameState.current.cash)
		var sandbox_now := (tracker != null and tracker.sandbox) or GameState.current.bag_has_illegal()
		hud.sandbox_label.visible = sandbox_now
		hud.sandbox_label.text = "SANDBOX ROUND: illegal club in play. No money, progress, records or restock." if (tracker != null and tracker.sandbox) else "ILLEGAL CLUB EQUIPPED: the first swing with it makes this a sandbox round."
	else:
		hud.wallet_footer.visible = false
		hud.sandbox_label.visible = false
	hud.set_lie(CourseLayout.surface_label(ball.current_lie), rad_to_deg(acos(clampf(ball.floor_normal.y, -1.0, 1.0))), ball.current_lie)
	hud.set_distance(_shot_yd)
	var w := ball.wind
	hud.set_conditions(w.length() / ShotSetup.MPS_PER_MPH, _compass(w), SurfacePhysicsCatalog.green_speed_ft)
	# Live side-bet status; sandbox rounds can't pay, so they don't show bets.
	if tracker != null and not tracker.sandbox:
		hud.set_side_bets(SideBets.rows(tracker.side_bets, tracker.to_result()))
	else:
		hud.set_side_bets([])


func _update_minimap(delta: float) -> void:
	if not _minimap_built:
		return
	hud.minimap_rect.visible = true
	hud.set_minimap_texture(minimap_viewport.get_texture())
	# Shot graphics update in 2D from the same points as the main view, independently
	# of the expensive map texture. Aiming while stationary must update the tracer too.
	var tex_size := Vector2(minimap_viewport.size)
	var display_scale := _minimap_display_scale()
	var draw_size := tex_size * display_scale
	var pixels_per_metre := display_scale / _minimap_scale
	var projection := Transform2D(
		Vector2(_minimap_right.x, -_minimap_forward.x) * pixels_per_metre,
		Vector2(_minimap_right.y, -_minimap_forward.y) * pixels_per_metre,
		draw_size * 0.5)
	projection.origin -= projection.basis_xform(_minimap_center)
	hud.minimap_shot_overlay.configure(Rect2((hud.minimap_rect.size - draw_size) * 0.5, draw_size), projection)
	# The map retains the planned path while the main-view yellow line is hidden in flight.
	hud.minimap_shot_overlay.update_ball(ball.global_position, shot_tracker_line.mesh != null, trail_mesh.visible)
	_minimap_elapsed += delta
	if _minimap_elapsed >= 0.125 and _minimap_last_ball.distance_squared_to(ball.global_position) > 0.01:
		minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_minimap_elapsed = 0.0
		_minimap_last_ball = ball.global_position
	# Bird's-eye view: draw the camera's ground focus as a moving circle on the minimap
	# instead of hiding the minimap outright (arrows pan it, wheel resizes it).
	if camera.mode == OrbitCamera.Mode.OVERHEAD:
		var focus := Vector2(camera.overhead_focus_point.x, camera.overhead_focus_point.z)
		var radius_m := clampf(camera.overhead_height * 0.6, 6.0, _minimap_scale * MINIMAP_HEIGHT_PX * 0.5)
		var disp_scale := _minimap_display_scale()
		hud.set_minimap_focus(_minimap_world_to_local(focus), (radius_m / _minimap_scale) * disp_scale)
	else:
		hud.hide_minimap_focus()


## An upright waypoint slides along the top of the screen toward the pin.
const HOLE_MARKER_TOP_Y := 70.0


func _update_hole_marker() -> void:
	if hud.hole_marker == null or ball == null or layout == null:
		return
	# The bird's-eye view already shows the whole hole at once; scouting is already a direct
	# look at the landing spot. A screen-space marker would just be visual clutter in either.
	if camera.mode == OrbitCamera.Mode.OVERHEAD or camera.scouting:
		hud.hole_marker.visible = false
		return
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		hud.hole_marker.visible = false
		return
	var marker := hud.hole_marker
	var half_width := marker.size.x * marker.scale.x * 0.5
	var min_x := half_width + 12.0
	var max_x := vp_size.x - half_width - 12.0
	# Only the screen edges constrain the waypoint. Hud draws its visible content
	# above it without hiding the transparent space inside any layout container.
	var target := ball.cup_position + Vector3.UP * 2.0
	var offset := target - camera.global_position
	var depth := (-camera.global_transform.basis.z).dot(offset)
	var x: float
	if depth > camera.near:
		x = clampf(camera.unproject_position(target).x, min_x, max_x)
	else:
		# Keep the same flag at the appropriate side when the cup is out of view.
		x = max_x if camera.global_transform.basis.x.dot(offset) >= 0.0 else min_x
	marker.set_distance(ball.distance_to_cup_yd())
	marker.global_position = Vector2(x - half_width, HOLE_MARKER_TOP_Y - PinIndicator.SYMBOL_CENTER.y * marker.scale.y)
	hud.hole_marker.visible = true


## Wind sock, not a compass: points where the wind blows relative to wherever the camera is
## currently facing (arrow "up" = downwind/blowing the same way the camera looks, "down" =
## into the golfer's face), so it turns to match as the camera rotates -- during aiming,
## bird's-eye, scouting, all of it -- rather than pointing at a fixed absolute direction.
func _update_wind_arrow() -> void:
	if hud.wind_arrow == null or camera == null:
		return
	var wind_xz := Vector2(ball.wind.x, ball.wind.z)
	if wind_xz.length() < 0.01:
		hud.wind_arrow.visible = false
		return
	wind_xz = wind_xz.normalized()
	var cam_fwd := -camera.global_transform.basis.z
	var cam_right := camera.global_transform.basis.x
	var cam_fwd_xz := Vector2(cam_fwd.x, cam_fwd.z).normalized()
	var cam_right_xz := Vector2(cam_right.x, cam_right.z).normalized()
	hud.wind_arrow.rotation = atan2(wind_xz.dot(cam_right_xz), wind_xz.dot(cam_fwd_xz))
	hud.wind_arrow.visible = true


## Scale factor (display pixels per minimap-texture pixel) applied by minimap_rect's
## STRETCH_KEEP_ASPECT_CENTERED, since the SubViewport is narrower than the panel for
## bent holes (see _update_minimap_frame).
func _minimap_display_scale() -> float:
	var tex_size := Vector2(minimap_viewport.size)
	var ctrl_size: Vector2 = hud.minimap_rect.size
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or ctrl_size.x <= 0.0 or ctrl_size.y <= 0.0:
		return 0.0
	return minf(ctrl_size.x / tex_size.x, ctrl_size.y / tex_size.y)


## Project a world XZ point into minimap_rect's local pixel space, matching the minimap
## camera's orthogonal top-down crop from _update_minimap_frame.
func _minimap_world_to_local(p: Vector2) -> Vector2:
	var d := p - _minimap_center
	var across := d.dot(_minimap_right)
	var along := d.dot(_minimap_forward)
	var tex_size := Vector2(minimap_viewport.size)
	var tex_pos := Vector2(tex_size.x * 0.5 + across / _minimap_scale, tex_size.y * 0.5 - along / _minimap_scale)
	var disp_scale := _minimap_display_scale()
	var disp_offset: Vector2 = (hud.minimap_rect.size - tex_size * disp_scale) * 0.5
	return disp_offset + tex_pos * disp_scale


static func _compass(v: Vector3) -> String:
	if v.length() < 0.1:
		return "calm"
	var a := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return "to " + dirs[int(round(a / 45.0)) % 8]


## Smooths a raw physics-sample polyline for display only (Catmull-Rom interpolation between
## the real sample points, never altering the underlying physics) -- a bounce's instantaneous
## velocity reversal is a real sharp corner in the raw samples, but reads as a rounded
## parabola once drawn through this instead of straight point-to-point segments.
## A flat ribbon along `pts` (width laid horizontally across the path) for the tracer and
## the flight trail: UV.x 0..1 along, UV.y across, UV2.x metres along, vertex alpha per point.
static func _ribbon_mesh(pts: PackedVector3Array, widths: PackedFloat32Array, alphas: PackedFloat32Array) -> ArrayMesh:
	var n := pts.size()
	if n < 2:
		return null
	var total := 0.0
	for k in range(1, n):
		total += pts[k].distance_to(pts[k - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_uv := 0.0
	var prev_m := 0.0
	var prev_a := 0.0
	for k in range(n):
		if k > 0:
			along += pts[k].distance_to(pts[k - 1])
		var tangent := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = Vector3.RIGHT
		side = side.normalized() * widths[k] * 0.5
		var l := pts[k] - side
		var r := pts[k] + side
		var uv := along / maxf(total, 0.001)
		if k > 0:
			for v in [[prev_l, prev_uv, 0.0, prev_m, prev_a], [prev_r, prev_uv, 1.0, prev_m, prev_a], [r, uv, 1.0, along, alphas[k]],
					[prev_l, prev_uv, 0.0, prev_m, prev_a], [r, uv, 1.0, along, alphas[k]], [l, uv, 0.0, along, alphas[k]]]:
				st.set_color(Color(1, 1, 1, v[4]))
				st.set_uv(Vector2(v[1], v[2]))
				st.set_uv2(Vector2(v[3], 0.0))
				st.add_vertex(v[0])
		prev_l = l
		prev_r = r
		prev_uv = uv
		prev_m = along
		prev_a = alphas[k]
	return st.commit()


static func _smooth_path(points: PackedVector3Array, subdivisions: int = 5) -> PackedVector3Array:
	var n := points.size()
	if n < 3 or subdivisions <= 1:
		return points
	var out := PackedVector3Array()
	for i in range(n - 1):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, n - 1)]
		for s in range(subdivisions):
			out.append(_catmull_rom(p0, p1, p2, p3, float(s) / float(subdivisions)))
	out.append(points[n - 1])
	return out


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Length of the white tail streaming behind the ball, in metres of flown path.
const TRAIL_TAIL_M := 3.0


## A short comet tail: only the last TRAIL_TAIL_M of the ball's path, fading from
## solid at the ball to nothing at its tip, so it reads as motion rather than a
## drawn trajectory (the yellow tracer already shows the plan).
func _update_trail() -> void:
	if ball.trail.size() < 1:
		trail_mesh.mesh = null
		hud.minimap_shot_overlay.set_tail(PackedVector3Array())
		return
	var src: PackedVector3Array = ball.trail
	var pts := PackedVector3Array([ball.global_position])
	var length := 0.0
	var i := src.size() - 1
	while i >= 0 and length < TRAIL_TAIL_M:
		var p: Vector3 = src[i]
		var seg := p.distance_to(pts[pts.size() - 1])
		if seg > 0.05:
			if length + seg > TRAIL_TAIL_M:
				# trim the last segment so the tail ends exactly at TRAIL_TAIL_M
				p = pts[pts.size() - 1].lerp(p, (TRAIL_TAIL_M - length) / seg)
				seg = TRAIL_TAIL_M - length
			pts.append(p)
			length += seg
		i -= 1
	if pts.size() < 2:
		trail_mesh.mesh = null
		hud.minimap_shot_overlay.set_tail(PackedVector3Array())
		return
	pts.reverse()  # tip first, ball last
	pts = _smooth_path(pts)
	hud.minimap_shot_overlay.set_tail(pts)
	var n := pts.size()
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for k in range(n):
		var t := float(k) / float(n - 1)  # 0 at the tip, 1 at the ball
		widths.append(lerpf(0.015, 0.085, t))
		alphas.append(t * t * 0.9)
	trail_mesh.mesh = _ribbon_mesh(pts, widths, alphas)


## Simulate a full-power (pfrac = 1) shot with the current club, aim and strike point using
## the same physics the real shot uses, and draw the path with a landing ring: the flight to
## the first bounce for a full swing, the whole roll for a putt. The inputs are compared every
## frame and a change restarts the simulation at once; small bounded batches keep it from
## blocking a frame, and meanwhile the previous line swings with the aim (_follow_aim_preview).
func _update_shot_tracker(_delta: float) -> void:
	var showing := phase != SwingPhase.IN_FLIGHT
	# A preview drawn from the ball's previous spot stays hidden until the new one is ready.
	var drawn_here := showing and ball != null and _tracker_shown_pivot.is_equal_approx(ball.global_position)
	shot_tracker_line.visible = drawn_here
	landing_marker.visible = drawn_here and _tracker_ring
	# the white flight trail only while the ball is flying (the IN_FLIGHT branch shows
	# it again); at address just the tracer
	trail_mesh.visible = false
	if not showing or ball == null or shadow_ball == null or _auto_putt_busy or _transitioning or _hole_loading:
		_tracker_running = false
		_tracker_inputs.clear()
		return
	if _tracker_running and _tracker_inputs.is_empty():
		# Terrain edits explicitly invalidate even an in-flight preview.
		_tracker_running = false
		return
	var club := _current_club()
	var aim := camera.aim_direction()
	var inputs: Array = [layout, ball.global_position, ball.cup_position, ball.wind,
		_shot_params(club, 1.0, strike, ball.current_lie, aim), strike]
	if inputs != _tracker_inputs:
		# Drop a stale simulation rather than finish a preview for an aim already left behind.
		_tracker_inputs = inputs
		_tracker_pending_yaw = camera.aim_yaw
		_begin_trajectory(club, strike, aim)
		_tracker_steps = 0
		_tracker_running = true
	if _tracker_running and _advance_trajectory():
		_tracker_running = false
		_tracker_shown_yaw = _tracker_pending_yaw
		_tracker_applied_yaw = 0.0
		_tracker_shown_pivot = ball.global_position
		_draw_shot_tracker(_trajectory_result())
		shot_tracker_line.visible = true
		landing_marker.visible = _tracker_ring
	elif drawn_here:
		_follow_aim_preview()


## Swing the last drawn preview around the ball by however far the aim has turned since it
## was simulated, so the line follows A/D and right-drag immediately; the exact simulation
## replaces it a few frames later (wind and terrain differ slightly along the new line).
func _follow_aim_preview() -> void:
	var dyaw := camera.aim_yaw - _tracker_shown_yaw
	if is_equal_approx(dyaw, _tracker_applied_yaw):
		return
	_tracker_applied_yaw = dyaw
	var pivot := Transform3D(Basis.IDENTITY, _tracker_shown_pivot)
	var about := pivot * Transform3D(Basis(Vector3.UP, dyaw), Vector3.ZERO) * pivot.affine_inverse()
	shot_tracker_line.global_transform = about
	landing_marker.global_position = about * _tracker_shown_landing
	if hud != null:
		hud.minimap_shot_overlay.set_preview(about * _tracker_shown_pts, about * _tracker_shown_landing)


func _begin_trajectory(club: Clubs.Club, hit: Vector2, aim: Vector3) -> void:
	var lie := ball.current_lie
	var sp := _shot_params(club, 1.0, hit, lie, aim)
	shadow_ball.cup_position = ball.cup_position
	shadow_ball.wind = ball.wind
	shadow_ball.place(Vector2(ball.global_position.x, ball.global_position.z))
	_tracker_flight_only = not sp["putter"]
	_tracker_start = ball.global_position
	var to_cup := Vector2(ball.cup_position.x - _tracker_start.x, ball.cup_position.z - _tracker_start.z).length()
	_tracker_putt_limit_m = maxf(to_cup + PUTT_PREVIEW_PAST_CUP_M, PUTT_PREVIEW_MIN_M) if sp["putter"] else 0.0
	if sp["putter"]:
		shadow_ball.putt(sp["speed_mps"], sp["dir"])
	else:
		shadow_ball.launch(sp["speed_mph"], sp["vla"], sp["backspin"], sp["sidespin"], sp["dir"])


func _advance_trajectory() -> bool:
	var deadline := Time.get_ticks_usec() + TRACKER_BUDGET_USEC
	var max_steps := int(TRACKER_MAX_TIME / GolfBall.DT) + 4
	var batch_steps := 0
	while not _trajectory_done() and _tracker_steps < max_steps:
		shadow_ball._physics_process(GolfBall.DT)
		_tracker_steps += 1
		batch_steps += 1
		if batch_steps >= TRACKER_STEPS_PER_FRAME or Time.get_ticks_usec() >= deadline:
			break
	return _trajectory_done() or _tracker_steps >= max_steps


## A full swing's preview stops where the ball first comes down; a putt's once it has rolled
## a little past the cup's distance (or comes to rest sooner).
func _trajectory_done() -> bool:
	if not shadow_ball.is_moving:
		return true
	if _tracker_flight_only:
		return shadow_ball._first_impact_done
	var p := shadow_ball.global_position
	return Vector2(p.x - _tracker_start.x, p.z - _tracker_start.z).length() >= _tracker_putt_limit_m


func _trajectory_result() -> Dictionary:
	return {
		"trail": shadow_ball.trail,
		"landing": shadow_ball.global_position,
		"carry_yd": shadow_ball.carry_distance_m * ShotSetup.YARDS_PER_METER,
		# a flight-only or cut-short putt preview never comes to rest, so it has no total
		"total_yd": -1.0 if _tracker_flight_only or shadow_ball.is_moving else shadow_ball.total_distance_m * ShotSetup.YARDS_PER_METER,
		"in_water": shadow_ball.in_water,
		"putt": not _tracker_flight_only,
		"stopped": not shadow_ball.is_moving,
	}


func _draw_shot_tracker(result: Dictionary) -> void:
	var trail: PackedVector3Array = result.get("trail", PackedVector3Array())
	var pts := _smooth_path(trail)
	var eye := camera.global_position if camera != null else ball.global_position
	shot_tracker_line.global_transform = Transform3D.IDENTITY
	if trail.size() >= 2:
		# Keep a near-constant on-screen width: thin by the ball, wider far downrange.
		var raised := PackedVector3Array()
		var widths := PackedFloat32Array()
		var alphas := PackedFloat32Array()
		for p in pts:
			raised.append(p + Vector3.UP * 0.05)
			widths.append(clampf(p.distance_to(eye) * 0.0045, 0.05, 1.6))
			alphas.append(1.0)
		shot_tracker_line.mesh = _ribbon_mesh(raised, widths, alphas)
	else:
		shot_tracker_line.mesh = null
	var landing: Vector3 = result.get("landing", ball.global_position)
	_tracker_shown_pts = pts
	_tracker_shown_landing = landing
	hud.minimap_shot_overlay.set_preview(pts, landing)
	var target_r := clampf(landing.distance_to(eye) * 0.018, 0.7, 4.0)  # ~constant on-screen size
	landing_marker.scale = Vector3.ONE * target_r
	landing_marker.global_position = landing  # the shader lifts the ring to sit on the ground
	var putt: bool = result.get("putt", false)
	_tracker_ring = not putt or result.get("stopped", true)
	if putt:
		hud.set_prediction(0.0, -1.0, result.get("in_water", false), ball.distance_to_cup_yd() * 3.0)
	else:
		hud.set_prediction(result.get("carry_yd", 0.0), result.get("total_yd", 0.0), result.get("in_water", false))


# ---------------------------------------------------------------- progression layer
# Round bookkeeping, the clubhouse hub and the admin-only illegal clubs. Everything that
# touches money, unlocks or stock goes through GameState (scripts/economy/game_state.gd);
# this file only feeds it strokes and hands it the finished round once.

## Name / par / yards for the loading screen and HUD: Augusta's card, or the Course Studio
## course's own holes (yardage from the tee to the pin). Only Augusta's holes have names;
## a Course Studio hole's name is "" and the screens show just its number.
func _hole_info(i: int) -> Dictionary:
	if GameLaunch.custom_course != "":
		if layout != null and i < layout.holes.size():
			var h: CourseLayout.Hole = layout.holes[i]
			return {"name": "", "par": h.par, "yd": roundi(h.length_yd)}
		return {"name": "", "par": 4, "yd": 0}
	return CourseBuilder.hole_info(i)


## The course's name for the loading screen and HUD: the Course Studio course's own name
## (read from its file until the layout is built), else Augusta National.
func _course_title() -> String:
	if layout != null:
		return layout.name_pretty
	if GameLaunch.custom_course != "":
		var title := PaintedCourse.peek_name(GameLaunch.custom_course)
		if title != "":
			return title
	return CourseBuilder.COURSE_NAME


## Esc overlay -> start menu. The round in progress is dropped (nothing is paid for it).
func _on_main_menu() -> void:
	if _transitioning:
		return
	if GameState.current != null:
		GameState.current.round_in_progress = false
	get_tree().change_scene_to_file(GameLaunch.exit_scene())


## First hole index (0-based) of the selected round span.
func round_start_index() -> int:
	return 9 if round_span == "back9" else 0


## Holes in this round: 9 for front9/back9, else economy.json's holes_per_round,
## capped by the course and by how many holes remain from the start index.
func round_holes() -> int:
	var course_size := layout.holes.size() if layout != null else 18
	var remaining := maxi(course_size - round_start_index(), 0)
	if round_span == "front9" or round_span == "back9":
		return mini(9, remaining)
	return mini(EconomyConfig.holes_per_round(), remaining)


func _begin_round() -> void:
	var pars: Array[int] = []
	for i in range(round_start_index(), round_start_index() + round_holes()):
		pars.append(layout.holes[i].par)
	if GameState.current != null:
		tracker = GameState.current.begin_round(pars)
	else:
		tracker = RoundTracker.start("local-%d" % Time.get_ticks_msec(), pars)
	# Course Studio courses are for fun: no money or progress (an easy home-made par 3
	# must not become a cash farm for the shops).
	if GameLaunch.custom_course != "" and tracker != null:
		tracker.sandbox = true
	scores.clear()
	strokes = 0
	water_balls = 0
	bunker_visits = 0
	_round_complete_pending = false
	_sync_round_in_progress()


## GameState locks bag edits and sales while a round has strokes on the card (a sandbox round
## is exempt: it can't pay or progress anyway).
func _sync_round_in_progress() -> void:
	if GameState.current == null:
		return
	var in_progress := tracker != null and not tracker.sandbox and (strokes > 0 or scores.size() > 0)
	GameState.current.round_in_progress = in_progress


func _finish_round() -> void:
	_round_complete_pending = true
	var result := tracker.to_result() if tracker != null else {}
	result["start_hole"] = round_start_index()
	var summary := {}
	if GameState.current != null and not result.is_empty():
		summary = GameState.current.complete_round(result)
	var total := int(result.get("total", 0))
	var rel := int(result.get("rel_par", 0))
	if summary.get("sandbox", false):
		hud.show_message("Sandbox round complete: %d (%+d). Nothing earned." % [total, rel], 4.0)
	else:
		hud.show_message("Round complete: %d (%+d)   +$%d" % [total, rel, int(summary.get("payout", 0))], 4.0)
	tracker = null
	_sync_round_in_progress()
	phase = SwingPhase.IDLE
	if hub != null:
		hub.show_round_summary(summary, result)


## "front9" | "back9" | "full18" -- set by the hub's Tee off row, read by round_holes()
## and round_start_index(). Defaults to a full round for the very first tee-off, before
## the hub has ever been opened.
var round_span := GameLaunch.round_span


func _on_hub_tee_off_span(span: String) -> void:
	if _transitioning:
		return
	round_span = span
	await _on_hub_tee_off(true)


func _on_hub_tee_off(start_new: bool = false) -> void:
	if _transitioning:
		return
	# Explicit Tee off must replace the untouched round created at scene load,
	# including its scorecard and starting tee when selecting Front/Back 9.
	if start_new or _round_complete_pending or tracker == null:
		_begin_round()
		await transition_to_hole(round_start_index())
	_refresh_hud()


func _on_hub_closed() -> void:
	if _round_complete_pending:
		_on_hub_tee_off()
	else:
		_refresh_hud()


## Give up on the current round: no payout, no restock, straight back to the first tee.
func _on_hub_abandon() -> void:
	if _transitioning:
		return
	_begin_round()
	hud.show_message("Round abandoned. Back to the tee.", 2.5)
	await transition_to_hole(round_start_index())
	_refresh_hud()


## The owned course earned (or paid out) in the background: keep the HUD wallet current.
func _on_business_ticked() -> void:
	if hud != null and GameState.current != null:
		hud.cash_label.text = str(GameState.current.cash)


func _on_bag_changed() -> void:
	var b := Clubs.bag()
	club_index = clampi(club_index, 0, maxi(0, b.size() - 1))
	if ball != null and not ball.is_moving:
		club_index = Clubs.suggest(ball.distance_to_cup_yd(), ball.current_lie == PhysicsEnums.SurfaceType.GREEN)
	_tracker_inputs.clear()
	if hud != null:
		_refresh_hud()


## Random push (degrees) for the fired shot: club dispersion scaled by how far off the sweet
## spot the strike was, divided by forgiveness, plus a condition term. Hard-capped by data.
func _dispersion_deg(club: Clubs.Club, hit: Vector2) -> float:
	var off := clampf(hit.length(), 0.0, 1.0)
	var cap := EconomyConfig.modifier_bound("putter_dispersion_deg_max", 0.3) if club.is_putter else EconomyConfig.modifier_bound("dispersion_deg_max", 2.5)
	var cond_max := EconomyConfig.modifier_bound("condition_putter_dispersion_deg_max", 0.25) if club.is_putter else EconomyConfig.modifier_bound("condition_dispersion_deg_max", 1.0)
	var sigma := club.dispersion_deg * (0.25 + 0.75 * off) / club.forgiveness + (1.0 - clampf(club.condition, 0.0, 1.0)) * cond_max * (0.3 + 0.7 * off)
	if sigma <= 0.0001:
		return 0.0
	return clampf(_shot_rng.randfn(0.0, sigma * 0.5), -cap, cap)


## Auto-Putt 9000 (admin sandbox): reads the green with the shot predictor, searches lines
## and paces, and fires the first one that drops inside its configured range. Out of range
## it still putts the best line it found. Spread over frames so it never hitches.
func _auto_putt() -> void:
	if _auto_putt_busy or ball == null or shadow_ball == null:
		return
	_tracker_running = false
	_tracker_inputs.clear()
	_auto_putt_busy = true
	var club := _current_club()
	var cfg := EconomyConfig.illegal_cfg()
	var range_m := float(cfg.get("auto_putt_range_m", 20.0))
	var max_speed := float(cfg.get("auto_putt_max_speed_mps", 9.0))
	var to_cup := ball.cup_position - ball.global_position
	to_cup.y = 0.0
	var dist := to_cup.length()
	var base_dir := to_cup.normalized() if dist > 0.001 else camera.aim_direction()
	hud.show_message("AUTO-PUTT 9000: reading the green…", 1.2)
	phase = SwingPhase.IN_FLIGHT  # blocks swing/club input while we think
	var best_dir := base_dir
	var best_speed := clampf(0.6 + dist * 0.45, 0.5, max_speed)
	var best_gap := INF
	var holed := false
	if dist <= range_m:
		# Pass 1: straight at it, find the pace that stops nearest the cup (or drops).
		var straight_speed := best_speed
		for k in range(14):
			var speed := lerpf(0.6, max_speed, float(k) / 13.0)
			var r := _sim_putt(speed, base_dir)
			if r["holed"]:
				holed = true
				best_dir = base_dir
				best_speed = speed
				break
			if r["gap"] < best_gap:
				best_gap = r["gap"]
				straight_speed = speed
				best_dir = base_dir
				best_speed = speed
			await get_tree().process_frame
		# Pass 2: play the break -- small yaw offsets around the best pace.
		if not holed:
			for yaw_deg in [-0.75, 0.75, -1.5, 1.5, -2.5, 2.5, -4.0, 4.0, -6.0, 6.0]:
				var dir := base_dir.rotated(Vector3.UP, deg_to_rad(yaw_deg))
				for f in [1.0, 0.9, 1.12, 1.25]:
					var speed := clampf(straight_speed * f, 0.5, max_speed)
					var r := _sim_putt(speed, dir)
					if r["holed"]:
						holed = true
						best_dir = dir
						best_speed = speed
						break
					if r["gap"] < best_gap:
						best_gap = r["gap"]
						best_dir = dir
						best_speed = speed
				if holed:
					break
				await get_tree().process_frame
	phase = SwingPhase.IDLE
	camera.aim_yaw = atan2(-best_dir.x, -best_dir.z)
	if dist > range_m:
		hud.show_message("AUTO-PUTT 9000: out of range (%.0f m > %.0f m). Best effort." % [dist, range_m], 2.0)
	else:
		hud.show_message("AUTO-PUTT 9000: %s" % ("LOCKED ON" if holed else "no drop found, best line"), 1.5)
	_auto_putt_busy = false
	_fire_shot(100.0, Vector2.ZERO, {"putter": true, "dir": best_dir, "speed_mps": best_speed})


func _sim_putt(speed: float, dir: Vector3) -> Dictionary:
	shadow_ball.cup_position = ball.cup_position
	shadow_ball.wind = ball.wind
	shadow_ball.place(Vector2(ball.global_position.x, ball.global_position.z))
	shadow_ball.putt(speed, dir)
	var max_steps := int(TRACKER_MAX_TIME / GolfBall.DT) + 4
	var steps := 0
	while shadow_ball.is_moving and steps < max_steps:
		shadow_ball._physics_process(GolfBall.DT)
		steps += 1
	var gap := shadow_ball.global_position.distance_to(ball.cup_position)
	return {"holed": shadow_ball.was_holed, "gap": 0.0 if shadow_ball.was_holed else gap}


## Grenade Prototype Driver (admin sandbox): a fireball, a shockwave ring and a camera kick.
func _grenade_effect(pos: Vector3) -> void:
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.amount = 160
	fire.lifetime = 1.1
	fire.direction = Vector3.UP
	fire.spread = 80.0
	fire.initial_velocity_min = 6.0
	fire.initial_velocity_max = 16.0
	fire.gravity = Vector3(0, -6.0, 0)
	fire.scale_amount_min = 0.15
	fire.scale_amount_max = 0.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	grad.add_point(0.35, Color(1.0, 0.45, 0.05, 0.9))
	fire.color_ramp = grad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.material = mat
	fire.mesh = sm
	fire.position = pos + Vector3.UP * 0.2
	add_child(fire)
	fire.emitting = true
	get_tree().create_timer(2.5).timeout.connect(fire.queue_free)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = rmat
	ring.mesh = torus
	ring.position = pos + Vector3.UP * 0.05
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(14.0, 1.0, 14.0), 0.7).from(Vector3(0.3, 1.0, 0.3)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(ring.queue_free)
	if camera != null:
		camera.shake = 0.9
