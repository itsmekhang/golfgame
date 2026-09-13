extends SceneTree
## Run with the graphical renderer at 1280x720; checks the real camera and HUD.
var failed := false

func _init() -> void:
	call_deferred('run')

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)

func settle(seconds: float = 0.6) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame
	await RenderingServer.frame_post_draw

func ready_course(course) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while course.ball == null or course.hud == null or course._loading_screen != null:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error('Course load timed out')
			quit(1)
			return
		if course._loading_screen != null:
			var event := InputEventKey.new()
			event.keycode = KEY_SPACE
			event.pressed = true
			Input.parse_input_event(event)
	await settle()

func check_path(course, live: bool = false) -> void:
	var overlay = course.hud.minimap_shot_overlay
	var mesh: Mesh = course.trail_mesh.mesh if live else course.shot_tracker_line.mesh
	check(mesh != null and mesh.get_surface_count() > 0, 'Main-view path exists')
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var world: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pixels: PackedVector2Array = overlay._tail_points if live else overlay._preview_points
	check(pixels.size() == world.size(), 'Minimap contains every main-view path sample')
	if pixels.size() != world.size():
		return
	# Camera3D's own projection is independent of the overlay's coordinate math.
	for i in range(0, world.size(), maxi(1, world.size() / 24)):
		var expected: Vector2 = course.minimap_camera.unproject_position(world[i]) * course._minimap_display_scale()
		check(expected.distance_to(pixels[i]) < 0.1, 'Tracer agrees with the real map camera')
	if live:
		var ball_pixel: Vector2 = course.minimap_camera.unproject_position(course.ball.global_position) * course._minimap_display_scale()
		check(pixels[-1].distance_to(ball_pixel) < 0.1, 'White tail stays attached to the live ball')
	else:
		# Confirm visible yellow pixels, not just matching coordinates in memory.
		var screenshot := root.get_texture().get_image()
		var visible_samples := 0
		for i in range(world.size() / 4, world.size() * 3 / 4, maxi(1, world.size() / 12)):
			if not Rect2(Vector2.ZERO, overlay.size).grow(-3).has_point(pixels[i]):
				continue
			var point: Vector2 = root.get_stretch_transform() * overlay.get_global_transform_with_canvas() * pixels[i]
			var yellow := false
			for y in range(maxi(0, int(point.y) - 2), mini(screenshot.get_height(), int(point.y) + 3)):
				for x in range(maxi(0, int(point.x) - 2), mini(screenshot.get_width(), int(point.x) + 3)):
					var color := screenshot.get_pixel(x, y)
					yellow = yellow or (color.r > 0.75 and color.g > 0.65 and color.b < 0.45)
			visible_samples += int(yellow)
		check(visible_samples >= 2, 'Tracer is visible over the cached map')

func run() -> void:
	if DisplayServer.get_name() == 'headless':
		print('MINIMAP TRACER: SKIP; requires a graphical renderer')
		quit()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var course = load('res://scenes/course.tscn').instantiate()
	root.add_child(course)
	current_scene = course
	await ready_course(course)
	course.camera.frozen = true
	var start := Time.get_ticks_usec()
	for frame in range(240):
		await process_frame
	print('MINIMAP TEE CHECK: %.1f FPS at 1280x720' % (240000000.0 / (Time.get_ticks_usec() - start)))
	await RenderingServer.frame_post_draw
	check_path(course)
	var tee: Vector3 = course.ball.global_position
	var initial: PackedVector2Array = course.hud.minimap_shot_overlay._preview_points
	var map_before: PackedByteArray = course.minimap_viewport.get_texture().get_image().get_data()
	course.camera.aim_yaw += 0.16
	await settle()
	check(course.ball.global_position == tee, 'Aiming keeps the ball stationary')
	check(course.hud.minimap_shot_overlay._preview_points != initial, 'Aiming refreshes the minimap tracer')
	check(map_before == course.minimap_viewport.get_texture().get_image().get_data(), 'Aiming needs no extra 3D map render')
	check_path(course)
	root.get_texture().get_image().save_png('build/minimap-aim.png')
	var aimed: PackedVector2Array = course.hud.minimap_shot_overlay._preview_points
	course.club_index = 3
	course.strike = Vector2(0.6, -0.3)
	course._refresh_hud()
	await settle()
	check(course.hud.minimap_shot_overlay._preview_points != aimed, 'Club and strike changes refresh the tracer')
	check_path(course)
	DisplayServer.window_set_size(Vector2i(1440, 810))
	await settle()
	check_path(course)
	root.get_texture().get_image().save_png('build/minimap-resized.png')
	DisplayServer.window_set_size(Vector2i(1280, 720))
	course.camera.aim_yaw -= 0.16
	course.club_index = 0
	course.strike = Vector2.ZERO
	await settle()
	course.camera.frozen = false
	var planned: PackedVector2Array = course.hud.minimap_shot_overlay._preview_points
	course._fire_shot(100.0, Vector2.ZERO)
	check(not course.shot_tracker_line.visible and not course.landing_marker.visible, 'Main-view yellow preview hides immediately on the hit')
	await settle(2.0)
	check(not course.shot_tracker_line.visible and course.trail_mesh.visible, 'Main view keeps only the live white tail during flight')
	check(course.hud.minimap_shot_overlay._show_preview and course.hud.minimap_shot_overlay._preview_points == planned, 'Minimap retains the planned yellow path during flight')
	check_path(course)
	check_path(course, true)
	root.get_texture().get_image().save_png('build/minimap-flight.png')
	await settle(10.0)
	check(course.ball.global_position.distance_to(tee) > 100.0, 'Full shot advanced across the hole')
	check(course.phase != course.SwingPhase.IN_FLIGHT and course.shot_tracker_line.visible, 'Yellow preview returns for the next shot')
	var next_start: Vector3 = course.hud.minimap_shot_overlay._preview[0]
	check(Vector2(next_start.x, next_start.z).distance_to(Vector2(course.ball.global_position.x, course.ball.global_position.z)) < 0.1, 'Next preview starts at the new ball position')
	course.transition_to_hole(10)
	await ready_course(course)
	check_path(course)
	print('MINIMAP TRACER: ', 'FAIL' if failed else 'PASS', '; stationary aim, club/strike, resizing, live tail and hole transition')
	quit(1 if failed else 0)
