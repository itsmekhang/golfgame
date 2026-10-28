extends SceneTree
## Windowed capture of the animated club swing (needs a display, not --headless):
##   godot --path . --script tests/screenshot_swing_rig.gd -- build/swing_rig

func _init() -> void:
	call_deferred("run")


func wait_until(pred: Callable, max_seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not pred.call():
		if Time.get_ticks_msec() - t0 > max_seconds * 1000.0:
			return false
		await process_frame
	return true


func snap(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[swing_rig] wrote %s" % path)


func capture_shot(course, prefix: String, pwr: float) -> void:
	course._fire_shot(pwr, Vector2.ZERO)
	var shots := [0.05, 0.12, 0.20, 0.27, 0.32]
	var t0 := Time.get_ticks_msec()
	var next_i := 0
	while next_i < shots.size():
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		if elapsed >= shots[next_i]:
			await snap(prefix + "_t%02d.png" % next_i)
			next_i += 1
		else:
			await process_frame
	await wait_until(func(): return not course.ball.is_moving, 20.0)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/swing_rig"
	var course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	var ok := await wait_until(func(): return course.ball != null and not course._transitioning, 300.0)
	if not ok:
		print("[swing_rig] course never became ready")
		quit(1)
		return
	course.camera.frozen = false
	await snap(prefix + "_address.png")
	await capture_shot(course, prefix + "_drive", 100.0)
	# Switch to the putter and take a short putt to check the scaled-down stroke.
	for i in range(Clubs.bag().size()):
		if Clubs.bag()[i].is_putter:
			course.club_index = i
			break
	await snap(prefix + "_putt_address.png")
	await capture_shot(course, prefix + "_putt", 40.0)
	quit(0)
