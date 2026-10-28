extends SceneTree
## Windowed capture of the clubhouse screens for a visual check (needs a display):
##   godot --path . --script tests/screenshot_hub.gd -- build/hub
## Writes <prefix>_shop.png, _inspect.png, _bag.png, _collection.png, _showcase.png,
## _objectives.png, _summary.png and (with GOLF_ADMIN=1) _admin.png using a throwaway save.

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
	print("[hub] wrote %s" % path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/hub"
	var gs := GameState.new()
	gs.save_path = "user://_screenshot_hub.json"
	gs.delete_save()
	gs.new_game()
	root.add_child(gs)
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	var ok := await wait_until(func(): return course.ball != null and not course._transitioning, 300.0)
	if not ok:
		print("[hub] course never became ready")
		quit(1)
		return
	var hub: HubMenu = course.hub
	# Give the player something to look at: a cheap buy, a cabinet putter, some cash.
	gs.cash = 140
	var l: Dictionary = gs.listings("goodwill")[0]
	gs.buy("goodwill", str(l["id"]))
	var putter_l := {}
	for cand in gs.listings("goodwill"):
		if ClubCatalog.is_putter(ClubCatalog.model(str(cand["model_id"]))):
			putter_l = cand
	if putter_l.is_empty():
		gs.stores["goodwill"]["listings"].append({"id": "demo-putter", "model_id": "brass_relic", "condition": 0.48, "price": 14, "seller": "", "seller_blurb": "", "provenance": "Demo listing.", "generation": 0, "reserved": false, "reserve_rounds_left": 0, "deposit": 0})
		putter_l = gs.find_listing("goodwill", "demo-putter")
	gs.buy("goodwill", str(putter_l["id"]))
	hub.open("shop")
	await snap(prefix + "_shop.png")
	var first: Dictionary = gs.listings("goodwill")[0]
	hub._show_inspect(ClubCatalog.model(str(first["model_id"])), {"kind": "listing", "store_id": "goodwill", "listing": first})
	await snap(prefix + "_inspect.png")
	hub._inspect.visible = false
	hub.open("bag")
	await snap(prefix + "_bag.png")
	hub._cabinet_selected = 1
	hub.open("collection")
	await snap(prefix + "_collection.png")
	hub._show_showcase()
	await snap(prefix + "_showcase.png")
	hub._showcase.visible = false
	hub.open("objectives")
	await snap(prefix + "_objectives.png")
	var fake_result := {"round_id": "demo", "pars": [4, 5, 4, 3, 4, 3, 4, 5, 4], "hole_strokes": [5, 6, 4, 4, 6, 3, 5, 7, 5], "total": 45, "par": 36, "rel_par": 9, "complete": true, "sandbox": false, "assisted": false, "strokes_by_instance": {}, "store_by_instance": {}, "illegal_used": []}
	var summary := gs.complete_round(fake_result)
	hub.show_round_summary(summary, fake_result)
	await snap(prefix + "_summary.png")
	hub._summary.visible = false
	if AdminAccess.is_admin():
		hub.open("admin")
		await snap(prefix + "_admin.png")
	hub.close()
	await snap(prefix + "_hud.png")
	gs.delete_save()
	quit(0)
