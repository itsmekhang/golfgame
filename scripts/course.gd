extends Node3D
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
var camera: OrbitCamera
var hud: Hud
var audio: GolfAudio
var flag: Node3D
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
var active_region := Rect2()
var _hole_loading := false
## Cart-boarding loading screen shown at startup and on every hole change (see
## _ensure_hole_region, transition_to_hole). One shared instance at a time -- whichever call
## site created it (_ready() at startup, or transition_to_hole() otherwise) owns freeing it;
## _ensure_hole_region() just updates its progress if one is already up rather than creating
## a second overlay on top of it.
## Shared with ball.wind (_build_ball) and the flagpins' wind-responsive animation
## (_add_flag) so both agree on the same current wind instead of the flag animating an
## unrelated fixed ambient breeze regardless of what the HUD/ball physics actually use.
const COURSE_WIND := Vector3(1.5, 0.0, -0.8)
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
## A standing instance of the terrain's own ShaderMaterial, built once up front (unlike
## _terrain_material above, which only exists for whichever hole's region is currently
## loaded) so every hole's cup patch (_add_flag) can render with the exact same shading and
## feature-mask lookup as the ground around it, however that hole's own region gets built.
var _flag_patch_material: ShaderMaterial
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
var minimap_ball_marker: MeshInstance3D
var minimap_pin_marker: MeshInstance3D
var _minimap_tick := 0
## Visual layer used only by the minimap markers (bit 10), hidden from the main
## camera so the oversized dots that make the ball/pin readable at minimap scale
## never show up in the normal gameplay view.
const MINIMAP_LAYER := 0x200  # layer 10
const MINIMAP_HEIGHT_PX := 280
var _minimap_built := false
## World-space frame the minimap camera is currently cropped to (see _update_minimap_frame),
## kept around so _minimap_world_to_local can place the overhead-camera focus circle.
var _minimap_center := Vector2.ZERO
var _minimap_forward := Vector2(0.0, -1.0)
var _minimap_right := Vector2(1.0, 0.0)
var _minimap_scale := 1.0  # world metres per minimap-texture pixel
var _tracker_accum := 0.0
const TRACKER_INTERVAL := 0.35
## Cap the preview sim so a long, slow-to-rest putt/chip can't hold a frame open;
## most shots are done well inside this and the real shot is unaffected either way.
const TRACKER_MAX_TIME := 12.0
var _pre_shot_pos := Vector3.ZERO
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


var _t0 := 0


func _t(label: String) -> void:
	var now := Time.get_ticks_msec()
	print("[build] %-14s %5d ms" % [label, now - _t0])
	_t0 = now


func _ready() -> void:
	_set_transition_active(true)
	var spec := CourseBuilder.hole_info(0)
	_loading_screen = LOADING_SCENE.instantiate()
	add_child(_loading_screen)
	_loading_screen.begin_hole(1, spec["name"], spec["par"], spec["yd"], true)
	# Let the loading screen draw before the (synchronous) course build starts.
	if DisplayServer.get_name() != "headless":
		await _loading_screen.covered
	else:
		await get_tree().process_frame
		await get_tree().process_frame
	_t0 = Time.get_ticks_msec()
	_load_layout()
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
	audio = GolfAudio.new()
	add_child(audio)
	hud.strike_selector.strike_changed.connect(func(v: Vector2) -> void: strike = v)
	resolver.register_zones(get_tree())
	_loading_screen.update_progress(0.7, "Finding the first tee…")
	# _ensure_hole_region (called from start_hole) sees _loading_screen already set and just
	# updates its progress instead of creating a second overlay on top of this one.
	await start_hole(0)
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
		_loading_screen.begin_hole(hole.index + 1, hole.name, hole.par, roundi(hole.length_yd))
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
	terrain_root = Node3D.new()
	terrain_root.name = "Terrain"
	_terrain_material = TerrainBuilder.terrain_material(layout)
	terrain_root.set_meta("material", _terrain_material)
	TerrainBuilder.rebuild_tiles(layout, terrain_root, region)
	add_child(terrain_root)
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
	layout = CourseBuilder.build(course_seed)
	print("[CourseBuilder] ", CourseBuilder.last_report)
	# Green speed for the round: GOLF_STIMP=11 forces one, otherwise the round's seed
	# picks a tournament-week reading between 10 and 12.5 ft.
	var stimp_env := OS.get_environment("GOLF_STIMP")
	if stimp_env.is_valid_float():
		SurfacePhysicsCatalog.set_green_speed(stimp_env.to_float())
	else:
		var r := RandomNumberGenerator.new()
		r.seed = course_seed * 977 + 13
		SurfacePhysicsCatalog.set_green_speed(snappedf(r.randf_range(10.0, 12.5), 0.5))
	print("[Greens] ", SurfacePhysicsCatalog.green_speed_label(), " rolling mu %.3f" % SurfacePhysicsCatalog.get_settings(PhysicsEnums.SurfaceType.GREEN).rolling_friction)


func _build_world() -> void:
	# Lighting & sky
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.88)
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
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.25, 0.48, 0.9)
		psm.sky_horizon_color = Color(0.7, 0.8, 0.9)
		# Cumulus cover: a generated equirect noise texture alpha-masked into puffs and
		# painted over the procedural sky -- one texture sample, no ray march, so it costs
		# nothing like the cinematic shader that kept tripping GPU timeouts.
		psm.sky_cover = _cloud_cover_texture()
		psm.sky_cover_modulate = Color(1.0, 1.0, 1.0, 0.9)
		sky.sky_material = psm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
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
	_flag_patch_material = TerrainBuilder.terrain_material(layout)
	for hole in layout.holes:
		_add_tee_markers(hole)
		_add_flag(hole)

	resolver = LieSurfaceResolver.new(layout)

	# Trail & aim line meshes
	trail_mesh = MeshInstance3D.new()
	trail_mesh.name = "Trail"
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	tmat.vertex_color_use_as_albedo = true  # the tail fades out through vertex alpha
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.no_depth_test = false
	trail_mesh.material_override = tmat
	add_child(trail_mesh)

	shot_tracker_line = MeshInstance3D.new()
	shot_tracker_line.name = "ShotTracker"
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(1.0, 0.9, 0.2, 0.9)
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shot_tracker_line.material_override = amat
	add_child(shot_tracker_line)

	landing_marker = MeshInstance3D.new()
	landing_marker.name = "LandingMarker"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.8
	landing_marker.mesh = torus
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.9, 0.2, 0.85)
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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


func _add_tee_markers(hole: CourseLayout.Hole) -> void:
	for sx: float in [-2.0, 2.0]:
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.1
		cm.height = 0.25
		m.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 0.95)
		m.material_override = mat
		var x := hole.tee.x + sx
		var z := hole.tee.z
		m.position = Vector3(x, layout.height_at(x, z) + 0.12, z)
		add_child(m)


## A flat ring from `inner` to `outer` radius (in the XZ plane, local to `center`), with a
## genuine triangulated gap in the middle -- see _add_flag: this is what lets the cup actually
## be seen at all without faking draw order, since the terrain mesh itself has no real opening
## cut into it anywhere. Vertex colour/UV are sampled the exact same way TerrainBuilder builds
## the real terrain tiles (matched against `layout`'s world position, not just a flat guessed
## colour), and the caller is expected to render it with that same ShaderMaterial -- a flat
## StandardMaterial3D here was tried first and reliably came out visibly off (too cool/teal
## when shaded, too bright when unshaded) because it responds to scene lighting differently
## than the terrain's own custom shader does, however its albedo was tuned.
static func _terrain_matched_annulus_mesh(layout: CourseLayout, center: Vector2, inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := i * TAU / segments
		var a1 := (i + 1) * TAU / segments
		var in0 := Vector2(cos(a0), sin(a0)) * inner
		var out0 := Vector2(cos(a0), sin(a0)) * outer
		var in1 := Vector2(cos(a1), sin(a1)) * inner
		var out1 := Vector2(cos(a1), sin(a1)) * outer
		for p in [in0, out0, out1, in0, out1, in1]:
			var wx: float = center.x + p.x
			var wz: float = center.y + p.y
			var col := TerrainBuilder._color_for(layout, wx, wz, PhysicsEnums.SurfaceType.GREEN, 0.0)
			st.set_color(col.srgb_to_linear())
			st.set_uv(Vector2(wx, wz) * 0.05)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	return st.commit() as ArrayMesh


## Builds the visible hole/cup/flag for `hole`. There is only one radius and one position
## here -- GolfBall.CUP_RADIUS and layout.height_at(hole.cup) -- shared with the actual
## putt-capture check in golf_ball.gd (see cup_position there). "Hole" and "cup" are not
## modelled as two separate things: the capture check uses exactly this position/radius, so
## the ball is never flagged as holed at some other, wider checkpoint before it visually
## reaches this same spot -- see also golf_ball.gd's _finish_holed(), which now waits for the
## drop-in animation to finish before emitting `holed`, instead of firing it immediately.
func _add_flag(hole: CourseLayout.Hole) -> void:
	var root := Node3D.new()
	root.name = "Flag%d" % (hole.index + 1)
	var c := hole.cup
	var gy := layout.height_at(c.x, c.z)
	root.position = Vector3(c.x, gy, c.z)

	# The terrain mesh is solid and unbroken -- there's no real hole cut into it anywhere
	# near the cup, and the whole-course grid is far too coarse to cut an 8cm hole out of
	# precisely. A previous version tried to fake this with no_depth_test (draw the cup on
	# top of everything, ignoring what's actually in front), but that made the *terrain*
	# look wrong instead: from any low/grazing angle the cup's full silhouette painted over
	# perfectly valid, closer ground, reading as the cup floating above the green or the
	# ground going transparent around it, because nothing was actually being occluded by
	# anything -- draw order was mesh-index order, not physical depth.
	#
	# Real fix: give the cup a genuine geometric opening near ground level, with everything
	# below using normal depth testing so it's only ever seen through that real opening --
	# not painted on top of nearer ground regardless of what's actually in front.
	#
	# `patch` is a small green-tinted annulus (the old fake "collar"'s shape, done right this
	# time) covering the ring just outside the cup mouth: raised a hair above the real terrain
	# so it reliably wins depth-testing against the redundant, untouched terrain triangles
	# directly beneath it, blending the transition into the surrounding green.
	#
	# The terrain tile itself still has one continuous, unbroken triangle spanning straight
	# across the cup's own opening too, though (nothing has actually cut a hole in *it*) --
	# without addressing that separately it would still win the depth test there (it's above
	# y=0, closer to the camera than anything recessed below it) and hide the cup outright,
	# same as before this rewrite. `mask` is a flat, near-zero-height dark disc sized to just
	# that opening, using no_depth_test purely to beat that one triangle. Unlike the old
	# wall's no_depth_test (a 16cm-tall structure that painted a visible floating silhouette
	# from any angle), a flat disc with no vertical extent can't read as "floating" -- worst
	# case it draws in front of the wall/floor/rim's own correct shading too and the hole just
	# looks like a flat dark circle instead of a shaded 3D bowl, never like it's above ground.
	const CUP_DEPTH := 0.16
	const PATCH_EPSILON := 0.003  # just enough to beat coplanar z-fighting with the tile below
	# Starts just outside the rim's own outer edge (CUP_RADIUS + 0.006) so the two abut
	# cleanly instead of overlapping and fighting over which one covers the rim's outer lip.
	var patch := MeshInstance3D.new()
	patch.mesh = _terrain_matched_annulus_mesh(layout, Vector2(c.x, c.z),
		GolfBall.CUP_RADIUS + 0.006, GolfBall.CUP_RADIUS + 0.22, 24)
	# The real terrain shader/mask, not a guessed flat colour (see _terrain_matched_annulus_mesh)
	# -- this is what actually guarantees a match under any lighting, not just the one
	# screenshot a colour was picked from.
	patch.material_override = _flag_patch_material
	patch.position = Vector3(0, PATCH_EPSILON, 0)
	root.add_child(patch)

	var mask := MeshInstance3D.new()
	var mask_mesh := CylinderMesh.new()
	mask_mesh.top_radius = GolfBall.CUP_RADIUS
	mask_mesh.bottom_radius = GolfBall.CUP_RADIUS
	mask_mesh.height = 0.002
	mask_mesh.radial_segments = 24
	mask.mesh = mask_mesh
	var mask_mat := StandardMaterial3D.new()
	mask_mat.albedo_color = Color(0.02, 0.018, 0.018)
	mask_mat.no_depth_test = true
	mask_mat.render_priority = -1
	mask.material_override = mask_mat
	mask.position = Vector3(0, -0.002, 0)
	root.add_child(mask)

	var wall := MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = GolfBall.CUP_RADIUS
	wall_mesh.bottom_radius = GolfBall.CUP_RADIUS
	wall_mesh.height = CUP_DEPTH
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	wall_mesh.radial_segments = 24
	wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.035, 0.03, 0.03)
	# Only the concave inward-facing side should ever be visible (the outward face is,
	# physically, underground) -- with normal depth testing now in effect this also avoids
	# any near/far-wall ambiguity, since only one side exists to draw at all.
	wall_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	wall_mat.roughness = 1.0
	wall.material_override = wall_mat
	wall.position = Vector3(0, -CUP_DEPTH * 0.5, 0)
	root.add_child(wall)

	var cup_floor := MeshInstance3D.new()
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = GolfBall.CUP_RADIUS
	floor_mesh.bottom_radius = GolfBall.CUP_RADIUS
	floor_mesh.height = 0.01
	floor_mesh.radial_segments = 24
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
	rim_mesh.rings = 24
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
	pole.set_wind_velocity(COURSE_WIND)


func _build_ball() -> void:
	ball = GolfBall.new()
	ball.name = "Ball"
	ball.layout = layout
	ball.resolve_surface = Callable(self, "_resolve_lie_surface")
	ball.obstacle_mask = PropScatter.OBSTACLE_LAYER
	ball.wind = COURSE_WIND
	add_child(ball)
	ball.came_to_rest.connect(_on_ball_rest)
	ball.water_hazard_entered.connect(_on_ball_water)
	ball.bunker_entered.connect(_on_ball_bunker)
	ball.out_of_bounds.connect(_on_ball_ob)
	ball.holed.connect(_on_ball_holed)
	ball.first_impact.connect(_on_first_impact)

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
	minimap_camera.cull_mask = 0xFFFFF & ~PerformanceSettings.DETAIL_LAYER  # course + minimap-only markers, no grass/vegetation clutter
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

	minimap_ball_marker = MeshInstance3D.new()
	minimap_ball_marker.name = "MinimapBall"
	var bm := SphereMesh.new()
	bm.radius = 3.5
	bm.height = 7.0
	minimap_ball_marker.mesh = bm
	minimap_ball_marker.layers = MINIMAP_LAYER
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 1.0, 1.0)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# These are UI markers riding along in a 3D viewport, not real geometry needing correct
	# occlusion -- no_depth_test + a high render_priority means neither can ever end up
	# invisible under a tree, a slope, or (as just happened to the pin) a stale height value.
	bmat.no_depth_test = true
	bmat.render_priority = 10
	minimap_ball_marker.material_override = bmat
	add_child(minimap_ball_marker)

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
	_minimap_tick = 0



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
	_mulligan_valid = false
	ball.cup_position = Vector3(hole.cup.x, layout.height_at(hole.cup.x, hole.cup.z), hole.cup.z)
	ball.place(Vector2(hole.tee.x, hole.tee.z))
	_face_cup()
	camera.mode = OrbitCamera.Mode.AIM
	camera.distance = 6.0
	club_index = 0
	phase = SwingPhase.IDLE
	trail_mesh.mesh = null
	_update_minimap_frame(hole)
	_refresh_hud()


## Freezes/restores gameplay input and physics for the duration of a loading screen --
## nothing should be able to swing, drag the camera, or have the ball keep moving while the
## course underneath it is being torn down and rebuilt.
func _set_transition_active(active: bool) -> void:
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
	_loading_screen.begin_hole(index + 1, hole.name, hole.par, roundi(hole.length_yd))
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


func _face_cup() -> void:
	var to_cup := ball.cup_position - ball.global_position
	camera.aim_yaw = atan2(-to_cup.x, -to_cup.z)


func _current_club() -> Clubs.Club:
	return Clubs.bag()[club_index]


func _unhandled_input(event: InputEvent) -> void:
	if ball == null:
		return
	if event.is_action_pressed("ui_cancel"):
		hud.toggle_help()
		return
	if hud != null and hud.is_help_open():
		return  # swallow gameplay input while the how-to-play overlay is open
	if event.is_action_pressed("reset_hole"):
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
			transition_to_hole((hole_index + 1) % layout.holes.size())
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
		match phase:
			SwingPhase.IDLE:
				phase = SwingPhase.POWER
				power = 0.0
				power_dir = 1.0
			SwingPhase.POWER:
				locked_power = power
				_fire_shot(locked_power, strike)


func _process(delta: float) -> void:
	if ball == null:
		return
	if grass_root is GrassStreamer:
		grass_root.focus_position = Vector2(ball.global_position.x, ball.global_position.z)
	# Terrain/props only exist within active_region -- shrunk by a margin so the overhead
	# camera's pan can't push its look-at centre right up to the edge (see OVERHEAD_TILT_MAX
	# for the matching cap on tilting toward the horizon at that edge). Falls back to the
	# unshrunk region if it's too small for the margin rather than an inverted Rect2.
	if active_region.size.x > 130.0 and active_region.size.y > 130.0:
		camera.pan_bounds = active_region.grow(-65.0)
	else:
		camera.pan_bounds = active_region
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
			hud.dist_label.text = "Ball: %.0f mph  h %.0f ft  %s" % [ball.velocity.length() / ShotSetup.MPS_PER_MPH, (ball.global_position.y - layout.height_at(ball.global_position.x, ball.global_position.z)) * ShotSetup.FEET_PER_METER, "flight" if not ball.on_ground else "rolling"]
		_:
			pass
	if phase != SwingPhase.IN_FLIGHT:
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
	var sidespin := shape * 1300.0
	var push_deg := shape * 3.0
	var dir := aim.rotated(Vector3.UP, deg_to_rad(-push_deg))
	if club.is_putter:
		return {"putter": true, "dir": dir, "speed_mps": lerpf(0.4, 9.0, pfrac * pfrac)}

	var low := clampf(-hit.y, 0.0, 1.0)   # strike below centre: more loft & spin, less speed
	var high := clampf(hit.y, 0.0, 1.0)   # strike above centre: flatter, less spin, more roll
	var off_center := clampf(absf(hit.y), 0.0, 1.0)
	var speed_mph := club.ball_speed_mph * lerpf(0.35, 1.0, pfrac) * (1.0 - off_center * 0.25)
	var backspin := club.backspin_rpm * lerpf(0.7, 1.0, pfrac) * (1.0 + low * 0.4) * (1.0 - high * 0.3)
	var vla := maxf(club.vla_deg + low * 7.0 - high * 4.0, 2.0)
	# Lie penalties (rough: flyer/less spin & speed, bunker: much less speed, more loft)
	if lie == PhysicsEnums.SurfaceType.ROUGH:
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


func _fire_shot(pwr: float, hit: Vector2) -> void:
	var club := _current_club()
	var aim := camera.aim_direction()
	_mulligan_pos = ball.global_position
	_mulligan_strokes = strokes
	_mulligan_water_balls = water_balls
	_mulligan_bunker_visits = bunker_visits
	_mulligan_valid = true
	strokes += 1
	_pre_shot_pos = ball.global_position
	phase = SwingPhase.IN_FLIGHT
	camera.mode = OrbitCamera.Mode.FOLLOW
	hud.power_bar.value = 0
	hud.result_label.text = ""

	var lie := ball.current_lie
	# Mistimed power taps shorten the shot below the full-swing distance shown by
	# the tracker; only a perfectly timed tap (pwr == 100) reaches it.
	var pfrac := clampf(pwr / 100.0, 0.05, 1.0)
	var sp := _shot_params(club, pfrac, hit, lie, aim)
	var est_carry_yd := Clubs.stock_carry_yd(club_index, pfrac)
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
	strokes = _mulligan_strokes
	water_balls = _mulligan_water_balls
	bunker_visits = _mulligan_bunker_visits
	ball.place(Vector2(_mulligan_pos.x, _mulligan_pos.z))
	phase = SwingPhase.IDLE
	camera.mode = OrbitCamera.Mode.AIM
	_face_cup()
	_mulligan_valid = false
	hud.show_message("Mulligan!", 1.5)
	_refresh_hud()


func _on_first_impact(pos: Vector3, _surface: int) -> void:
	audio.play_bounce(pos)


func _on_ball_rest(_pos: Vector3, lie: int) -> void:
	phase = SwingPhase.IDLE
	camera.mode = OrbitCamera.Mode.AIM
	_face_cup()
	var d := ball.distance_to_cup_yd()
	var lie_tag := "IN THE BUNKER" if lie == CourseLayout.SURFACE_BUNKER else "Lie"
	hud.result_label.text = "Carry %.0f yd   Total %.0f yd   Apex %.0f ft   %s: %s" % [
		ball.carry_distance_m * ShotSetup.YARDS_PER_METER, ball.total_distance_m * ShotSetup.YARDS_PER_METER,
		ball.max_height_m * ShotSetup.FEET_PER_METER, lie_tag, CourseLayout.surface_label(lie)]
	club_index = Clubs.suggest(d, lie == PhysicsEnums.SurfaceType.GREEN)
	_refresh_hud()


func _on_ball_water(hz: WaterHazard, pos: Vector3) -> void:
	strokes += 1
	water_balls += 1
	var where: String = hz.hazard_name if hz != null else "the water"
	hud.show_message("SPLASH!  Ball in %s\n+1 penalty stroke" % where, 3.0)
	hud.result_label.text = "WATER HAZARD: %s   (carry %.0f yd)" % [where, ball.carry_distance_m * ShotSetup.YARDS_PER_METER]
	_spawn_splash(pos)
	_refresh_hud()
	_drop_ball(_pre_shot_pos)


func _on_ball_bunker(pos: Vector3, plugged: bool) -> void:
	bunker_visits += 1
	hud.show_message("BUNKER!  %s" % ("Plugged in the sand" if plugged else "Rolled into the sand"), 2.5)
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


func _on_ball_ob(_pos: Vector3) -> void:
	strokes += 1
	hud.show_message("Out of bounds! +1 penalty", 2.5)
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
	scores.append(strokes)
	hud.show_message("In the hole!  %s  (%d)" % [label, strokes], 3.0)
	audio.play_holed()
	if rel <= -1:
		audio.play_crowd_cheer()
	phase = SwingPhase.IN_FLIGHT
	await get_tree().create_timer(3.0).timeout
	if hole_index + 1 < layout.holes.size():
		await transition_to_hole(hole_index + 1)
	else:
		var total := 0
		var par := 0
		for i in range(scores.size()):
			total += scores[i]
			par += layout.holes[i].par
		hud.show_message("Round complete: %d (%+d)   R to replay" % [total, total - par], 8.0)
		scores.clear()
		await transition_to_hole(0)


func _refresh_hud() -> void:
	var hole := layout.holes[hole_index]
	var club := _current_club()
	hud.hole_label.text = "Hole %d  %s   Par %d" % [hole_index + 1, hole.name, hole.par]
	var total_score := 0
	var total_par := 0
	for i in range(scores.size()):
		total_score += scores[i]
		total_par += layout.holes[i].par
	hud.score_label.text = "Strokes: %d    Round: %d (%+d)    Water: %d   Bunkers: %d" % [strokes, total_score, total_score - total_par, water_balls, bunker_visits]
	hud.club_label.text = "Club: %s  (%s)" % [club.name, club.short]
	hud.lie_label.text = "Lie: %s   Slope: %.1f°" % [CourseLayout.surface_label(ball.current_lie), rad_to_deg(acos(clampf(ball.floor_normal.y, -1.0, 1.0)))]
	hud.dist_label.text = "To pin: %.0f yd" % ball.distance_to_cup_yd()
	var w := ball.wind
	hud.wind_label.text = "Wind: %.0f mph %s    %s" % [w.length() / ShotSetup.MPS_PER_MPH, _compass(w), SurfacePhysicsCatalog.green_speed_label()]
	hud.help_label.text = "A/D or right-drag: aim   W/S: club   Drag the ball: strike point   Space/click: swing (tap to lock power)   C: bird's-eye (arrows pan, right-drag to look, wheel zoom)   Z: hold to scout the landing spot (right-drag to look)   M: mulligan (replay last shot)   N: next hole   R: restart hole   J: reroll terrain (seed %d)   Esc: how to play" % course_seed


func _update_minimap(_delta: float) -> void:
	if not _minimap_built:
		return
	hud.minimap_rect.visible = true
	hud.minimap_label.visible = true
	hud.minimap_rect.texture = minimap_viewport.get_texture()
	hud.minimap_label.text = "Hole %d  %s" % [hole_index + 1, layout.holes[hole_index].name]
	minimap_ball_marker.global_position = ball.global_position + Vector3.UP * 1.0
	_minimap_tick += 1
	if _minimap_tick % 5 == 0:  # ~12 Hz at 60 fps
		minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Bird's-eye view: draw the camera's ground focus as a moving circle on the minimap
	# instead of hiding the minimap outright (arrows pan it, wheel resizes it).
	if camera.mode == OrbitCamera.Mode.OVERHEAD:
		var focus := Vector2(camera.overhead_focus_point.x, camera.overhead_focus_point.z)
		var radius_m := clampf(camera.overhead_height * 0.6, 6.0, _minimap_scale * MINIMAP_HEIGHT_PX * 0.5)
		var disp_scale := _minimap_display_scale()
		hud.set_minimap_focus(_minimap_world_to_local(focus), (radius_m / _minimap_scale) * disp_scale)
	else:
		hud.hide_minimap_focus()


## Always-on-screen waypoint to the hole, like a Fortnite/Forza Horizon compass marker: rides
## along a fixed line near the top of the screen, sliding only left/right to track which way
## the flag actually is -- never anywhere else on screen, so it's always a glance up, not a
## hunt in whichever corner it happened to land in.
const HOLE_MARKER_MARGIN := 26.0
const HOLE_MARKER_TOP_Y := 70.0


func _update_hole_marker() -> void:
	if hud.hole_marker == null or ball == null or layout == null:
		return
	# The bird's-eye view already shows the whole hole at once; scouting is already a direct
	# look at the landing spot. A screen-space marker would just be visual clutter in either.
	if camera.mode == OrbitCamera.Mode.OVERHEAD or camera.scouting:
		hud.hole_marker.visible = false
		hud.hole_marker_label.visible = false
		return
	var hole := layout.holes[hole_index]
	var cup_y := layout.height_at(hole.cup.x, hole.cup.z)
	var target := Vector3(hole.cup.x, cup_y + 2.0, hole.cup.z)

	var to_target := target - camera.global_position
	var cam_fwd := -camera.global_transform.basis.z
	var behind := cam_fwd.dot(to_target) < 0.0

	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		hud.hole_marker.visible = false
		hud.hole_marker_label.visible = false
		return
	var center := vp_size * 0.5

	# unproject_position on a point behind the camera still returns a value (via the
	# perspective divide going negative), just mirrored through the screen centre -- mirror
	# it back rather than trying to special-case the projection math directly. Only the
	# horizontal component ends up used below, but the mirroring has to happen before that
	# split or the sign comes out wrong.
	var raw := camera.unproject_position(target)
	if behind:
		raw = center * 2.0 - raw

	var m := HOLE_MARKER_MARGIN
	var x := clampf(raw.x, m, vp_size.x - m)
	hud.hole_marker.position = Vector2(x, HOLE_MARKER_TOP_Y) - hud.hole_marker.size * 0.5
	hud.hole_marker.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hud.hole_marker.visible = true

	# Caption + live yardage right under the marker, following it as it slides -- recomputed
	# every frame from the ball's actual current position, not just at hole start, so it
	# updates continuously as the ball moves (mid-flight, after a shot, while dragging putts).
	hud.hole_marker_label.text = "Pin  %.0f yd" % ball.distance_to_cup_yd()
	hud.hole_marker_label.position = Vector2(x, HOLE_MARKER_TOP_Y) - Vector2(hud.hole_marker_label.size.x * 0.5, -(hud.hole_marker.size.y * 0.5 + 2.0))
	hud.hole_marker_label.visible = true


## Wind sock, not a compass: points where the wind blows relative to wherever the camera is
## currently facing (arrow "up" = downwind/blowing the same way the camera looks, "down" =
## into the golfer's face), so it turns to match as the camera rotates -- during aiming,
## bird's-eye, scouting, all of it -- rather than pointing at a fixed absolute direction.
func _update_wind_arrow() -> void:
	if hud.wind_arrow == null or camera == null:
		return
	var wind_xz := Vector2(COURSE_WIND.x, COURSE_WIND.z)
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
const TRAIL_TAIL_M := 16.0


## A short comet tail: only the last TRAIL_TAIL_M of the ball's path, fading from
## solid at the ball to nothing at its tip, so it reads as motion rather than a
## drawn trajectory (the yellow tracer already shows the plan).
func _update_trail() -> void:
	if ball.trail.size() < 1:
		trail_mesh.mesh = null
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
		return
	pts.reverse()  # tip first, ball last
	pts = _smooth_path(pts)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := pts.size()
	for k in range(n):
		var t := float(k) / float(n - 1)  # 0 at the tip, 1 at the ball
		im.surface_set_color(Color(1.0, 1.0, 1.0, t * t * 0.9))
		im.surface_add_vertex(pts[k])
	im.surface_end()
	trail_mesh.mesh = im


## Simulate a full-power (pfrac = 1) shot with the current club, aim and strike
## point using the same physics the real shot uses, and draw the resulting flight
## + roll-out path with a landing marker. Recomputed a few times a second (never
## every frame -- a full flight sim is hundreds of physics steps) so it tracks the
## player's aim and strike point live without a per-frame cost.
func _update_shot_tracker(delta: float) -> void:
	var showing := phase != SwingPhase.IN_FLIGHT
	shot_tracker_line.visible = showing
	landing_marker.visible = showing
	# the white flight trail only while the ball is flying (the IN_FLIGHT branch shows
	# it again); at address just the tracer
	trail_mesh.visible = false
	if not showing or ball == null or shadow_ball == null:
		return
	_tracker_accum += delta
	if _tracker_accum < TRACKER_INTERVAL:
		return
	_tracker_accum = 0.0
	var result := _predict_trajectory(_current_club(), strike, camera.aim_direction())
	_draw_shot_tracker(result)


func _predict_trajectory(club: Clubs.Club, hit: Vector2, aim: Vector3) -> Dictionary:
	var lie := ball.current_lie
	var sp := _shot_params(club, 1.0, hit, lie, aim)
	shadow_ball.cup_position = ball.cup_position
	shadow_ball.place(Vector2(ball.global_position.x, ball.global_position.z))
	if sp["putter"]:
		shadow_ball.putt(sp["speed_mps"], sp["dir"])
	else:
		shadow_ball.launch(sp["speed_mph"], sp["vla"], sp["backspin"], sp["sidespin"], sp["dir"])
	var max_steps := int(TRACKER_MAX_TIME / GolfBall.DT) + 4
	var steps := 0
	while shadow_ball.is_moving and steps < max_steps:
		shadow_ball._physics_process(GolfBall.DT)
		steps += 1
	return {
		"trail": shadow_ball.trail,
		"landing": shadow_ball.global_position,
		"carry_yd": shadow_ball.carry_distance_m * ShotSetup.YARDS_PER_METER,
		"total_yd": shadow_ball.total_distance_m * ShotSetup.YARDS_PER_METER,
		"in_water": shadow_ball.in_water,
	}


func _draw_shot_tracker(result: Dictionary) -> void:
	var trail: PackedVector3Array = result.get("trail", PackedVector3Array())
	var im := ImmediateMesh.new()
	if trail.size() >= 2:
		var pts := _smooth_path(trail)
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in pts:
			im.surface_add_vertex(p + Vector3.UP * 0.03)
		im.surface_end()
	shot_tracker_line.mesh = im
	var landing: Vector3 = result.get("landing", ball.global_position)
	landing_marker.global_position = landing + Vector3.UP * 0.1
	var carry: float = result.get("carry_yd", 0.0)
	var total: float = result.get("total_yd", 0.0)
	var hazard_note := "  (into water)" if result.get("in_water", false) else ""
	hud.proj_label.text = "Full swing: %.0f yd carry, %.0f yd total%s" % [carry, total, hazard_note]
	hud.strike_label.text = "Strike point: %s\n(drag the ball to shape the shot)" % hud.strike_selector.describe()
