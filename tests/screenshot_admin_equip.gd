extends SceneTree
## Windowed capture of the Admin tab's "Browse All Clubs" section with the new
## Inspect/Equip buttons (needs a display, not --headless):
##   godot --path . --script tests/screenshot_admin_equip.gd -- build/admin_equip

var course: Node3D


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
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[admin_equip] wrote %s" % path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/admin_equip"
	AdminAccess.set_override(true)
	var gs := GameState.new()
	gs.save_path = "user://_screenshot_admin_equip.json"
	gs.delete_save()
	gs.new_game()
	root.add_child(gs)
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	var ok := await wait_until(func(): return course.ball != null and not course._transitioning, 300.0)
	if not ok:
		print("[admin_equip] course never became ready")
		quit(1)
		return
	var hub: HubMenu = course.hub
	hub.open("admin")
	await snap(prefix + "_top.png")
	# admin_equip a fairway wood so its card shows "Equipped" for the screenshot.
	gs.admin_equip("steelhead_classic")
	hub._refresh()
	await snap(prefix + "_after_equip.png")
	gs.delete_save()
	quit(0)
