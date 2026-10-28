extends SceneTree
var failed := false
const OUT := "C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/range_access/"
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func wall_hits(fac: Node3D, from: Vector3, to: Vector3) -> int:
	var count := 0
	for part: Node in fac.find_children("*", "MeshInstance3D", true, false):
		if not str(part.name).begins_with("WALLS_HIGH") and not str(part.name).begins_with("BASE"): continue
		var xf: Transform3D = fac.global_transform.affine_inverse()*part.global_transform
		for si in range(part.mesh.get_surface_count()):
			var arr: Array = part.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else v.size()
			for t in range(0, n-2, 3):
				var a := xf*v[idx[t] if not idx.is_empty() else t]
				var b := xf*v[idx[t+1] if not idx.is_empty() else t+1]
				var c := xf*v[idx[t+2] if not idx.is_empty() else t+2]
				if Geometry3D.segment_intersects_triangle(from, to, a, b, c) != null: count += 1
	return count
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1500, 1000)
	var world := Node3D.new()
	root.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("aabec8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce5ed")
	env.ambient_light_energy = 0.7
	env_node.environment = env
	world.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.far = 1500
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	for type in ["driving_range", "clubhouse"]:
		var built := FacilityBuilder.build([{"type": type, "level": 4, "pos": Vector2.ZERO, "rot": 0.0, "rooms": {"spa_fitness": 1, "pro_shop": 1, "lobby": 1}}], func(_p: Vector2) -> float: return 0.0, false, true)
		world.add_child(built)
		FacilityBuilder.set_view(built, FacilityBuilder.View.ROOF_OFF)
		var fac := built.get_child(0) as Node3D
		var views: Array
		if type == "driving_range":
			check((FacilityBuilder.rig(fac).get("door_leaves", []) as Array).is_empty(), "Upper range still has closed passage doors")
			check(wall_hits(fac, Vector3(9.5, 5.5, -10), Vector3(12.5, 5.5, -10)) == 0, "Upper bridge passage blocked")
			views = [["catch_nets.png", Vector3(21, 7, -21), Vector3(12, 4.1, -13)], ["open_passage.png", Vector3(15, 8.6, -18), Vector3(11, 5.2, -9.7)]]
		else:
			for z in [19.8, 20.15, 20.5]:
				for y in [1.1, 1.7, 2.3]:
					check(wall_hits(fac, Vector3(29.4, y, z), Vector3(30.6, y, z)) == 0, "Gym doorway still has a solid wall across it")
			var gym_doors := 0
			for leaf: Node3D in FacilityBuilder.rig(fac).get("door_leaves", []):
				if absf(leaf.position.x-30) < 0.2 and absf(leaf.position.z-20.15) < 1.0: gym_doors += 1
			check(gym_doors == 2, "Gym needs a usable double door")
			views = [["clubhouse_glass_entry.png", Vector3(5, 3.5, -0.5), Vector3(0, 1.8, 10.5)], ["gym_entry.png", Vector3(34, 2.5, 20.0), Vector3(29.6, 1.7, 20.15)]]
		if not "--check-only" in OS.get_cmdline_user_args():
			for view in views:
				if "--gym-only" in OS.get_cmdline_user_args() and view[0] != "gym_entry.png": continue
				camera.position = view[1]
				camera.look_at(view[2])
				for i in range(8): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUT+view[0])
				print("PREVIEW ", OUT+view[0])
		built.queue_free()
		await process_frame
	print("RANGE AND GYM GEOMETRY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
