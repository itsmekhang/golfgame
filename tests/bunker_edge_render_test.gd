extends SceneTree
## Compare gameplay lies with pixels from the real terrain shader at sand edges.
## Run with a graphical renderer: --path . --script tests/bunker_edge_render_test.gd

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://bunker_edge_test_unused.json")
	call_deferred("run")

func solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Bunker pixel test requires a graphical renderer")
		quit(1)
		return
	var layout := CourseLayout.new()
	layout.bounds = Rect2(-32, -32, 64, 64)
	# A straight lip, plus a diagonal/concave outline between mask sample points.
	var straight := Bunker.from_polygon(PackedVector2Array([
		Vector2(-12.25, -9.35), Vector2(-4.15, -9.35),
		Vector2(-4.15, 8.45), Vector2(-12.25, 8.45)]))
	var curved := Bunker.from_polygon(PackedVector2Array([
		Vector2(1.15, -10.35), Vector2(10.45, -8.65), Vector2(12.65, 1.25),
		Vector2(9.45, 9.35), Vector2(1.25, 6.45), Vector2(5.15, -1.65)]))
	layout.bunkers = [straight, curved]
	layout.build_cache(2.0, false)
	layout.build_feature_mask()
	var resolver := LieSurfaceResolver.new(layout)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	viewport.add_child(environment)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(32, 32)
	ground.mesh = plane
	var material := TerrainBuilder.terrain_material(layout)
	# Distinct grass/sand colors make classification independent of texture grain.
	var rough_array := Texture2DArray.new()
	rough_array.create_from_images([solid_texture(Color.GREEN).get_image()])
	material.set_shader_parameter("rough_texture_array", rough_array)
	material.set_shader_parameter("rough_layer_count", 1)
	material.set_shader_parameter("rough_tint", Color.WHITE)
	material.set_shader_parameter("sand_texture", solid_texture(Color.WHITE))
	material.set_shader_parameter("sand_color", Color.RED)
	material.set_shader_parameter("sand_color2", Color.RED)
	material.set_shader_parameter("sand_mean", 1.0)
	material.set_shader_parameter("rough_mean", 1.0)
	material.set_shader_parameter("detail_strength", 0.0)
	material.set_shader_parameter("macro_strength", 0.0)
	ground.material_override = material
	viewport.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32.0
	viewport.add_child(camera)
	camera.position = Vector3(0, 30, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	camera.current = true
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.save_png("res://build/bunker-edge-pixels.png")
	var mismatches := 0
	var grass_count := 0
	var sand_count := 0
	for y in range(1, 640, 2):
		for x in range(1, 640, 2):
			var color := pixels.get_pixel(x, y)
			# Exclude the few pixels where antialiasing makes the boundary ambiguous.
			if absf(color.r - color.g) < 0.20:
				continue
			var visible_sand := color.r > color.g
			var world := camera.project_ray_origin(Vector2(x + 0.5, y + 0.5))
			var lie: int = resolver.resolve(world)["surface"]
			if visible_sand:
				sand_count += 1
			else:
				grass_count += 1
			if (lie == CourseLayout.SURFACE_BUNKER) != visible_sand:
				mismatches += 1
				if mismatches <= 3:
					print("Mismatch at ", Vector2(world.x, world.z), ": visible sand=", visible_sand, ", lie=", CourseLayout.surface_label(lie))
	print("Bunker pixels: ", grass_count, " grass, ", sand_count, " sand; mismatches=", mismatches)
	var passed := mismatches == 0 and grass_count > 10000 and sand_count > 10000
	print("BUNKER EDGE RENDER: ", "PASS" if passed else "FAIL")
	straight.free()
	curved.free()
	viewport.free()
	quit(0 if passed else 1)
