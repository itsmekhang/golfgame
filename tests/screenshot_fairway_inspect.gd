extends SceneTree
## Windowed capture of the Inspect dialog for a few fairway woods, to check the swapped
## Fairway_Wood_Head sits correctly on the shaft (needs a display, not --headless):
##   godot --path . --script tests/screenshot_fairway_inspect.gd -- build/fairway_inspect
## Writes <prefix>_<id>.png for each id below, at a couple of orbit angles.

const IDS := ["loaner_3w", "steelhead_classic", "tour_spoon"]
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
	print("[fairway_inspect] wrote %s" % path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/fairway_inspect"
	var gs := GameState.new()
	gs.save_path = "user://_screenshot_fairway_inspect.json"
	gs.delete_save()
	gs.new_game()
	root.add_child(gs)
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	var ok := await wait_until(func(): return course.ball != null and not course._transitioning, 300.0)
	if not ok:
		print("[fairway_inspect] course never became ready")
		quit(1)
		return
	var hub: HubMenu = course.hub
	hub.open("shop")
	await snap(prefix + "_hub_open_check.png")
	for id in IDS:
		var model := ClubCatalog.model(id)
		hub._show_inspect(model, {"kind": "listing", "store_id": "goodwill", "listing": {"id": "demo", "model_id": id, "condition": 0.85, "price": 1, "seller": "", "seller_blurb": "", "provenance": "", "generation": 0, "reserved": false, "reserve_rounds_left": 0, "deposit": 0}})
		await snap(prefix + "_" + id + "_a.png")
		var viewer: ClubViewer3D = hub._inspect.find_children("*", "ClubViewer3D", true, false)[0]
		viewer._yaw = 2.2
		viewer._pitch = -0.15
		viewer._spin = false
		viewer._update_camera()
		await snap(prefix + "_" + id + "_b.png")
		hub._inspect.visible = false
	gs.delete_save()
	quit(0)
