extends SceneTree
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count

func run() -> void:
	for gid in ["bench_flat", "bench_incline"]:
		var original := FacilityBuilder._first_mesh(FacilityBuilder.GYM_SCENE % gid)
		var split := FacilityBuilder.bench_split(gid)
		var rack: Mesh = split[0]
		var bar: Mesh = split[1]
		check(bar != null, gid + " lost its barbell")
		if bar == null: continue
		check(triangles(rack) + triangles(bar) == triangles(original), gid + " lost or duplicated triangles")
		check(bar.get_aabb().size.x > 2.3 and bar.get_aabb().size.y > 0.44, gid + " lost the shaft or plates")
		check(rack.get_aabb().end.y > 1.4, gid + " lost its rack uprights")
		var center := bar.get_aabb().get_center()
		var hardware := 0
		for surface in range(bar.get_surface_count()):
			for v: Vector3 in bar.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(v.x) < 0.72 and Vector2(v.y - center.y, v.z - center.z).length() > 0.04: hardware += 1
		check(hardware == 0, gid + " lifted rack hardware with the bar")
		print(gid, ": rack=", triangles(rack), " bar=", triangles(bar), " rack hardware lifted=", hardware)
	await preview()
	print("BENCH SPLIT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func preview() -> void:
	if DisplayServer.get_name() == "headless": return
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("2a313b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	env.environment = settings
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.8
	world.add_child(sun)
	for i in range(2):
		var split := FacilityBuilder.bench_split("bench_flat" if i == 0 else "bench_incline")
		for part in range(2):
			var model := MeshInstance3D.new()
			model.mesh = split[part]
			model.position = Vector3(-1.7 + 3.4 * i, 0.65 * part, 0)
			world.add_child(model)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(4, 4, -7)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.7
	camera.current = true
	for frame in range(70): await process_frame
	root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/bench_split_fixed.png")
