extends SceneTree
## CPU lies/cache and optional real-shader pixels for tree islands versus side rough.
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://tree_patch_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func solid(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func run() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(-70, -110, 140, 220)
	var hole := CourseLayout.Hole.new()
	hole.index = 0
	hole.name = "Tree patch test"
	hole.tee = Vector3(0, 0, -90)
	hole.waypoints = [hole.tee, Vector3(0, 0, 90)]
	hole.fairway_half_width = 48.0
	hole.rough_islands = [
		[Vector2(-16, -20), Vector2(-16, -20), 10.0],
		[Vector2(15, 0), Vector2(15, 20), 8.0],
		[Vector2(-15, 40), Vector2(-15, 40), 7.0, false],
		[Vector2(22, 40), Vector2(22, 40), 7.0, false, true]]
	layout.holes.append(hole)
	layout.finalize_features()
	var fw := layout.fairways[0]
	fw.swell = 0.0
	fw.wobble_amp = 0.0
	layout.build_cache()
	layout.build_feature_mask()
	var resolver := LieSurfaceResolver.new(layout)
	var patch_points := 0
	var patch_edge_points := 0
	var bare_cut_points := 0
	for z in range(-40, 55):
		for x in range(-35, 36):
			var p := Vector2(x, z)
			var distance := fw.tree_patch_distance(p)
			var surface := layout.surface_at(p)
			if distance < 0.0:
				patch_points += 1
				check(surface == CourseLayout.SURFACE_TREE_PATCH, "Island has tree-patch lie at %s" % p)
				check(resolver.resolve(Vector3(x, 0, z))["surface"] == surface, "Resolver agrees")
				if distance > -CourseLayout.FIRST_CUT_WIDTH:
					patch_edge_points += 1
			elif z < 30:
				check(surface == PhysicsEnums.SurfaceType.FAIRWAY, "Fairway meets tree patch directly")
			if z > 30 and x < 8 and surface == CourseLayout.SURFACE_FIRST_CUT:
				bare_cut_points += 1
	check(patch_points > 600 and patch_edge_points > 150, "Circle and capsule interiors/edges sampled")
	check(bare_cut_points > 30, "Explicit treeless cutout retains ordinary first cut")
	# A treeless ring flagged as a tree island goes straight from fairway to rough.
	var ring_rough := 0
	for z in range(30, 51):
		for x in range(12, 33):
			var q := Vector2(x, z)
			if q.distance_to(Vector2(22, 40)) > 11.0:
				continue
			var sq := layout.surface_at(q)
			check(sq != CourseLayout.SURFACE_FIRST_CUT, "No first cut on a tree island at %s" % q)
			ring_rough += int(sq == PhysicsEnums.SurfaceType.ROUGH)
	check(ring_rough > 60, "Tree-island ring is rough")
	check(layout.surface_at(Vector2(49, 0)) == CourseLayout.SURFACE_FIRST_CUT, "Side rough retains first cut")
	check(layout.surface_at(Vector2(53, 0)) == PhysicsEnums.SurfaceType.ROUGH, "Side rough remains rough")
	check(layout.cached_surface(Vector2(-16, -20)) == CourseLayout.SURFACE_TREE_PATCH, "Streamed cache preserves tree patch")
	check(layout.sdf_image.get_pixel(27, 45).b > 0.5, "GPU mask includes tree patch")
	check(CourseLayout.surface_label(CourseLayout.SURFACE_TREE_PATCH) == "Tree patch", "HUD label")
	check(CourseLayout.engine_surface(CourseLayout.SURFACE_TREE_PATCH) == PhysicsEnums.SurfaceType.ROUGH, "Keep existing woodland shot physics")
	# Hazards still take priority over the woodland floor.
	layout.bunkers.append(Bunker.from_polygon(PackedVector2Array([
		Vector2(-19, -23), Vector2(-13, -23), Vector2(-13, -17), Vector2(-19, -17)])))
	check(layout.surface_at(Vector2(-16, -20)) == CourseLayout.SURFACE_BUNKER, "Bunker priority")
	layout.bunkers.clear()
	if DisplayServer.get_name() != "headless":
		await check_pixels(layout, fw)
	print("TREE PATCH TEST: ", "PASS" if failures == 0 else "FAIL", " (", patch_points, " interior, ", patch_edge_points, " edge, ", bare_cut_points, " treeless-cut points)")
	quit(0 if failures == 0 else 1)

func check_pixels(layout: CourseLayout, fw: FairwayArea) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 768)
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
	plane.size = Vector2(128, 128)
	ground.mesh = plane
	var mat := TerrainBuilder.terrain_material(layout)
	mat.set_shader_parameter("first_cut_texture", solid(Color.RED))
	mat.set_shader_parameter("first_cut_tint", Color.WHITE)
	mat.set_shader_parameter("straw_texture", solid(Color.BLUE))
	mat.set_shader_parameter("straw_color", Color.WHITE)
	mat.set_shader_parameter("straw_mean", 1.0)
	# A fully painted tree-canopy bed: island bases take the mulch like the woods.
	mat.set_shader_parameter("straw_mask", solid(Color.WHITE))
	mat.set_shader_parameter("detail_strength", 0.0)
	mat.set_shader_parameter("macro_strength", 0.0)
	ground.material_override = mat
	viewport.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 128.0
	viewport.add_child(camera)
	camera.position = Vector3(0, 100, 0)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	camera.current = true
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.save_png("res://build/tree-patch-pixels.png")
	var island_red := 0
	var island_blue := 0
	var side_red := 0
	for y in range(1, 768, 2):
		for x in range(1, 768, 2):
			var world := camera.project_ray_origin(Vector2(x + 0.5, y + 0.5))
			var p := Vector2(world.x, world.z)
			var c := pixels.get_pixel(x, y)
			var red := c.r > c.g + 0.2 and c.r > c.b + 0.2
			if fw.tree_patch_distance(p) < -0.8:
				island_red += int(red)
				island_blue += int(c.b > c.r + 0.2 and c.b > c.g + 0.2)
			elif p.x > 48.6 and p.x < 49.8 and absf(p.y) < 30:
				side_red += int(red)
	check(island_red < 50, "Tree-island bases render rough, not first-cut grass")
	check(island_blue > 2000, "Tree-island bases take the trees' pine-straw beds")
	check(side_red > 300, "Side first cut still renders")
	print("Tree patch pixels: ", island_red, " first cut, ", island_blue, " mulch; side first cut: ", side_red)
