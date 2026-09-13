extends SceneTree
## Loads the course scene, waits a few frames, saves a screenshot and quits.
## Run (needs a display): godot --path . --script tests/screenshot_course.gd -- moccasin out.png
## Optional 3rd arg: "shot" fires a driver from the tee and captures the ball in flight.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var course := args[0] if args.size() > 0 else "moccasin"
	var out := args[1] if args.size() > 1 else "screenshot.png"
	var shot := args.size() > 2 and args[2] == "shot"
	var scene: PackedScene = load("res://scenes/course.tscn")
	var t0 := Time.get_ticks_msec()
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	print("[shot] scene built in %d ms" % (Time.get_ticks_msec() - t0))
	await _wait_ready(inst)
	var course_node = inst
	var hole_idx := int(OS.get_environment("GOLF_HOLE")) if OS.get_environment("GOLF_HOLE") != "" else 0
	if hole_idx > 0:
		course_node.transition_to_hole(hole_idx)
		await _wait_ready(inst)
	if OS.get_environment("GOLF_NOSHADOW") == "1":
		course_node.get_node("Sun").shadow_enabled = false
		print("[shot] shadows disabled")
	if OS.get_environment("GOLF_OVERHEAD") == "1":
		course_node.camera.mode = OrbitCamera.Mode.OVERHEAD
	if OS.get_environment("GOLF_LOOK_GREEN") == "1":
		var hole = course_node.layout.holes[hole_idx]
		var c: Vector3 = Vector3(hole.cup.x, course_node.layout.height_at(hole.cup.x, hole.cup.z), hole.cup.z)
		course_node.camera.frozen = true
		course_node.camera.global_position = c + Vector3(0, 14, 34)
		course_node.camera.look_at(c, Vector3.UP)
	if OS.get_environment("GOLF_LOOK_UP") == "1":
		course_node.camera.frozen = true
		course_node.camera.rotation_degrees.x += 32.0
	if OS.get_environment("GOLF_LOOK_WATER") == "1" and not course_node.layout.water_hazards.is_empty():
		var hz = course_node.layout.water_hazards[int(OS.get_environment("GOLF_WATER_INDEX")) if OS.get_environment("GOLF_WATER_INDEX") != "" else 0]
		var c: Vector3 = Vector3(hz.center.x, hz.water_level, hz.center.y)
		course_node.camera.frozen = true
		course_node.camera.global_position = c + Vector3(0, 9, 22)
		course_node.camera.look_at(c, Vector3.UP)
		print("[shot] looking at ", hz.hazard_name)
	if OS.get_environment("GOLF_LOOK_ROUGH") == "1":
		var hole = course_node.layout.holes[hole_idx]
		var forward: Vector3 = (hole.waypoints[1] - hole.waypoints[0]).normalized()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var focus: Vector3 = hole.tee
		for distance in range(12, 61, 2):
			var candidate: Vector3 = hole.tee + forward * 15.0 + right * distance
			var xz := Vector2(candidate.x, candidate.z)
			if course_node.layout.cached_surface(xz) == PhysicsEnums.SurfaceType.ROUGH and course_node.layout.cached_turf(xz) > 4.5 and course_node.layout.straw_at(xz) < 0.3:
				focus = candidate
				break
		focus.y = course_node.layout.cached_height(focus.x, focus.z)
		course_node.camera.frozen = true
		course_node.camera.global_position = focus - forward * 5.0 + Vector3.UP * 1.4
		course_node.camera.look_at(focus + forward * 3.0 + Vector3.UP * 0.15)
		course_node.set_process(false)
		course_node.grass_root.focus_position = Vector2(focus.x, focus.z)
		course_node.grass_root.view_position = course_node.camera.global_position
		for frame in range(70):
			await process_frame
		print("[grass] stored %d clumps; max commit %.2f ms" % [course_node.grass_root.instance_count, course_node.grass_root.max_tile_build_usec / 1000.0])
	if OS.get_environment("GOLF_HIGH_SHOT") == "1":
		var hole = course_node.layout.holes[hole_idx]
		var centre: Vector3 = (hole.tee + hole.cup) * 0.5
		centre.y = course_node.layout.height_at(centre.x, centre.z)
		course_node.camera.frozen = true
		course_node.camera.global_position = centre + Vector3(70, 110, 120)
		course_node.camera.look_at(centre + Vector3(0, 0, -250))
		print("[shot] high camera; backdrop triangles ", course_node.backdrop_root.mesh.get_faces().size() / 3)
	if shot:
		course_node._fire_shot(100.0, Vector2.ZERO)
		for i in range(90):
			await process_frame
	else:
		for i in range(12):
			await process_frame
	var t_fps := Time.get_ticks_usec()
	for i in range(60):
		await process_frame
	print("[shot] %.1f fps over 60 frames (%d MultiMesh nodes)" % [60.0 / ((Time.get_ticks_usec() - t_fps) / 1.0e6), _count(root, "MultiMeshInstance3D")])
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[shot] saved ", out, " ", img.get_size())
	var ball = course_node.ball
	print("[shot] ball at ", ball.global_position, " state ", ball.state, " lie ", CourseLayout.surface_label(ball.current_lie))
	quit(0)


func _count(n: Node, cls: String) -> int:
	var c := 1 if n.is_class(cls) else 0
	for ch in n.get_children():
		c += _count(ch, cls)
	return c


## Wait until the course is playable and the cart loading screen has left, tapping
## Space every few frames to shorten the ride once loading is done.
func _wait_ready(inst) -> void:
	for i in range(3000):
		await process_frame
		if inst.ball != null and inst.hud != null and inst.active_region.size != Vector2.ZERO and inst._loading_screen == null:
			break
		if i % 10 == 0 and inst._loading_screen != null:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
	await process_frame
