extends SceneTree
## Windowed capture of the Clubhouse shop (and the other hub tabs) on a private unsaved
## state, without loading the course:
##   godot --path . --script tests/screenshot_shop.gd -- build/shop
## Writes <prefix>_shop.png, _shop_hover.png, _haggle.png, _bag.png, _collection.png.

var hub: HubMenu


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_shop_unused.json")
	call_deferred("run")


func snap(path: String, frames: int = 50) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[shop] wrote %s" % path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/shop"
	var gs := GameState.current
	gs.autosave = false
	gs.new_game()
	gs.cash = 260
	hub = HubMenu.new()
	root.add_child(hub)
	hub.open("shop")
	await snap(prefix + "_shop.png")
	for sid in ["marketplace", "pawn", "proshop"]:
		if gs.store_unlocked(sid) or true:
			pass
	var stores := EconomyConfig.stores()
	if stores.size() > 1:
		var sid := str(stores[1]["id"])
		if not gs.store_unlocked(sid):
			gs.unlocked.append(sid)
		hub._store_id = sid
		hub._refresh()
		await snap(prefix + "_shop2.png")
	hub._store_id = "goodwill"
	hub._refresh()
	var l: Dictionary = gs.listings("goodwill")[0]
	if gs.can_haggle("goodwill", l):
		hub._haggle_dialog("goodwill", l)
		await snap(prefix + "_haggle.png")
		hub._confirm.visible = false
	hub.open("bag")
	await snap(prefix + "_bag.png")
	hub.open("collection")
	await snap(prefix + "_collection.png")
	quit(0)
