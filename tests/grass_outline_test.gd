extends SceneTree
## Curved rough crossing cache cells and tile boundaries, plus optional real-shader stills.

class CurvedLayout extends CourseLayout:
	func surface_at(p: Vector2) -> int:
		var d := p.length() - 12.0
		return PhysicsEnums.SurfaceType.FAIRWAY if d < 0.0 else (SURFACE_FIRST_CUT if d < FIRST_CUT_WIDTH else PhysicsEnums.SurfaceType.ROUGH)

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := CurvedLayout.new()
	layout.bounds = Rect2(-64, -64, 128, 128)
	layout.cache_cell = 2.0
	layout.cache_nx = 65
	layout.cache_nz = 65
	layout.holes.append(CourseLayout.Hole.new())
	for field in ["cache_surface", "cache_turf", "cache_green", "cache_height", "cache_tree_island"]:
		var values = layout.get(field)
		values.resize(65 * 65)
		layout.set(field, values)
	layout.cache_green.fill(100.0)
	layout.cache_tree_island.fill(100.0)
	for z in range(65):
		for x in range(65):
			var p := layout.bounds.position + Vector2(x, z) * 2.0
			layout.cache_turf[z * 65 + x] = p.length() - 12.0
			layout.cache_surface[z * 65 + x] = layout.surface_at(p)
	var params := {"seed": 7, "band": 22.0, "density": 100.0, "far": 12.0, "scale": 1.0, "mode": "kolosok", "max_per_tile": 1600}
	var partial_cell_roots := 0
	var checked_tiles := 0
	for z in range(5, 11):
		for x in range(5, 11):
			var key := Vector2i(x, z)
			var data := RoughGrass.sample_tile_buffer(layout, key, params)
			check(data.count <= 1600, "Tile budget exceeded")
			var buffer: PackedFloat32Array = data.buffer
			for i in range(data.count):
				var p := Vector2(data.origin.x + buffer[i * 16 + 3], data.origin.z + buffer[i * 16 + 11])
				check(layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH, "Grass entered mown turf")
				if layout.cached_surface(p) != PhysicsEnums.SurfaceType.ROUGH:
					partial_cell_roots += 1
			# Integrate the requested density independently over this tile's sampling
			# footprint. Partial tiles must not inflate density to use their budget.
			var expected := 0.0
			var corner := layout.bounds.position + Vector2(key) * 8.0 - Vector2.ONE
			for j in range(64):
				for k in range(64):
					var p := corner + (Vector2(k, j) + Vector2.ONE * 0.5) * 0.125
					if layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH:
						expected += minf(25.0, RoughGrass._per_cell(p.length() - 12.0, params, 1.0)) / 64.0
			if expected > 80.0:
				check(absf(data.count - expected) < maxf(25.0, expected * 0.16), "Tile %s has uneven density: %d vs %.0f" % [key, data.count, expected])
				checked_tiles += 1
	check(partial_cell_roots > 80, "Curved edges still discard partially rough cells")
	check(checked_tiles > 20, "Too few boundary/density tiles checked")
	var bunker := Bunker.from_polygon(PackedVector2Array([Vector2(-23, -3), Vector2(-17, -3), Vector2(-17, 3), Vector2(-23, 3)]))
	var water := WaterHazard.from_polygon(PackedVector2Array([Vector2(17, -3), Vector2(23, -3), Vector2(23, 3), Vector2(17, 3)]))
	layout.bunkers.append(bunker)
	layout.water_hazards.append(water)
	for key in [Vector2i(5, 8), Vector2i(10, 8)]:
		var data := RoughGrass.sample_tile_buffer(layout, key, params)
		check(data.count > 0, "Hazard incorrectly clears its entire grass tile")
		var buffer: PackedFloat32Array = data.buffer
		for i in range(data.count):
			var p := Vector2(data.origin.x + buffer[i * 16 + 3], data.origin.z + buffer[i * 16 + 11])
			check(not layout.bunker_near(p, RoughGrass.HAZARD_CLEARANCE), "Grass clips bunker")
			check(not layout.hazard_near(p, RoughGrass.HAZARD_CLEARANCE), "Grass clips water")
	layout.bunkers.clear()
	layout.water_hazards.clear()
	bunker.free()
	water.free()
	print("GRASS OUTLINE: %s; %d tiles, %d roots recovered in partial edge cells" % ["PASS" if failures == 0 else "FAIL", checked_tiles, partial_cell_roots])
	if DisplayServer.get_name() != "headless" and failures == 0:
		await render_stills(layout)
	quit(1 if failures else 0)

func render_stills(layout: CourseLayout) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := Node3D.new()
	root.add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(128, 128)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TerrainBuilder.ROUGH_COLOR
	ground.material_override = mat
	world.add_child(ground)
	var cut := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 14.5
	disc.bottom_radius = 14.5
	disc.height = 0.01
	disc.radial_segments = 128
	cut.mesh = disc
	var cut_mat := StandardMaterial3D.new()
	cut_mat.albedo_color = TerrainBuilder.COL_FAIRWAY_B
	cut.material_override = cut_mat
	world.add_child(cut)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("829eaf")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 21, 36)
	camera.look_at(Vector3.ZERO)
	var grass := GrassStreamer.new()
	grass.configure(layout, 7)
	grass.view_position = camera.position
	grass.active = true
	world.add_child(grass)
	for frame in range(1000):
		await create_timer(0.01).timeout
		if grass.pending.is_empty() and grass._jobs.is_empty() and grass.built_tiles > 20:
			break
	for view in ["high", "low", "moved"]:
		if view == "low":
			camera.position = Vector3(-18, 2.5, 23)
			camera.look_at(Vector3(0, 0, 4))
		elif view == "moved":
			camera.position += Vector3(8, 0, 0)
			camera.look_at(Vector3(0, 0, 4))
		grass.view_position = camera.position
		for frame in range(25):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("grass_%s.png" % view))
	world.queue_free()
	await process_frame
