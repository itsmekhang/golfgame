extends SceneTree
## Isolated check of the scaled-down putting stroke, independent of where a real
## drive happened to land (needs a display, not --headless):
##   godot --path . --script tests/screenshot_putt_stroke.gd -- build/putt_stroke

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
	print("[putt_stroke] wrote %s" % path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/putt_stroke"
	var course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	var ok := await wait_until(func(): return course.ball != null and not course._transitioning, 300.0)
	if not ok:
		print("[putt_stroke] course never became ready")
		quit(1)
		return
	for i in range(Clubs.bag().size()):
		if Clubs.bag()[i].is_putter:
			course.club_index = i
			break
	course._refresh_hud()
	course.camera.frozen = false
	course.camera.aim_yaw = 0.0
	await snap(prefix + "_address.png")
	course._fire_shot(60.0, Vector2.ZERO)
	var shots := [0.05, 0.10, 0.15, 0.20, 0.25]
	var t0 := Time.get_ticks_msec()
	var next_i := 0
	while next_i < shots.size():
		var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
		if elapsed >= shots[next_i]:
			await snap(prefix + "_t%02d.png" % next_i)
			next_i += 1
		else:
			await process_frame
	quit(0)
