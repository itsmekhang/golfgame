extends SceneTree

var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var terrain := func(p: Vector2) -> float: return sin(p.x * .04) * 2.0 + cos(p.y * .03) * 3.0
	var ctx := {"node": holder, "pos": Vector2(20, 35), "rot": .63, "floor": 1.5, "height_at": terrain}
	FacilityBuilder._range_field(ctx, 2)
	check(holder.get_node_or_null("RangePerimeter") == null, "Level 2 must have no perimeter nets")
	var body := StaticBody3D.new()
	holder.add_child(body)
	ctx["body"] = body
	FacilityBuilder._range_perimeter(ctx, -13)
	var fence := holder.get_node("RangePerimeter")
	var pole_count := 0
	var panel_count := 0
	var min_z := 0.0
	var max_x := 0.0
	for child in fence.get_children():
		if str(child.name).begins_with("NetPole"):
			pole_count += 1
			var p: Vector3 = child.position
			var g := FacilityBuilder._ground(ctx, p.x, p.z)
			check(absf(p.y - 16.25 - g) < .001, "Fence post must sit on terrain")
			min_z = minf(min_z, p.z)
			max_x = maxf(max_x, absf(p.x))
		elif child is MeshInstance3D and child.material_override is ShaderMaterial:
			panel_count += 1
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0, vertices.size(), 6):
				for index in [i, i + 1]:
					var p := vertices[index]
					check(absf(p.y - FacilityBuilder._ground(ctx, p.x, p.z) + .08) < .001, "Net lower edge must follow rotated terrain")
	check(panel_count == pole_count - 1 and panel_count > 40, "Continuous three-sided perimeter")
	check(body.get_child_count() == panel_count, "Every net panel has ball collision when enabled")
	check(min_z < -264 and is_equal_approx(max_x, 42), "Nets extend beyond the final target and wrap around it")
	holder.queue_free()
	print("RANGE PERIMETER: ", "FAIL" if failed else "PASS", " (", pole_count, " poles, ", panel_count, " panels)")
	if failed or not "--preview" in OS.get_cmdline_user_args():
		quit(1 if failed else 0)
		return
	await process_frame
	root.size = Vector2i(1600, 1000)
	var world := Node3D.new()
	root.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("aabec8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce5ed")
	env.ambient_light_energy = .65
	env_node.environment = env
	world.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 350)
	ground.mesh = plane
	ground.position = Vector3(0, -.06, -130)
	ground.material_override = FacilityBuilder._mat(Color("41773b"))
	world.add_child(ground)
	var facilities := FacilityBuilder.build([{"type": "driving_range", "level": 4, "pos": Vector2.ZERO, "rot": 0.0}], func(_p: Vector2) -> float: return 0.0, false)
	world.add_child(facilities)
	var camera := Camera3D.new()
	camera.far = 1500
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	for view in [
		["range_enclosure.png", Vector3(170, 170, -355), Vector3(0, 5, -120), 310.0],
		["range_bays_game.png", Vector3(20, 11, -34), Vector3(0, 4.0, -9), 35.0],
		["range_outfield.png", Vector3(0, 5.8, -14), Vector3(0, 10, -170), 80.0]]:
		camera.position = view[1]
		camera.look_at(view[2])
		camera.size = view[3]
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE if view[0] == "range_outfield.png" else Camera3D.PROJECTION_ORTHOGONAL
		for i in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/driving_range/" + str(view[0])
		root.get_texture().get_image().save_png(path)
		print("PREVIEW ", path)
	quit()
