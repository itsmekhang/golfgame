extends SceneTree
## Windowed capture of the Clubhouse Inspect dialog in each of its contexts (shop listing,
## owned club, admin preview, cabinet putter), on a private unsaved state:
##   godot --path . --script tests/screenshot_inspect.gd -- build/inspect
## Writes <prefix>_listing.png, _owned.png, _preview_driver.png, _putter.png.

var hub: HubMenu


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_inspect_unused.json")
	call_deferred("run")


func snap(path: String) -> void:
	for i in range(70):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[inspect] wrote %s" % path)


func find_viewer(node: Node) -> ClubViewer3D:
	if node.is_queued_for_deletion():
		return null
	if node is ClubViewer3D:
		return node
	for child in node.get_children():
		var found := find_viewer(child)
		if found != null:
			return found
	return null


## Freeze the turntable so captures are repeatable.
func hold_viewer() -> void:
	var v := find_viewer(hub._inspect)
	if v != null:
		v._spin = false
		v._update_camera()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/inspect"
	var gs := GameState.current
	gs.autosave = false
	gs.new_game()
	gs.cash = 400
	hub = HubMenu.new()
	root.add_child(hub)
	hub.open("shop")
	await process_frame

	var listing: Dictionary = {}
	for l in gs.listings("goodwill"):
		if not ClubCatalog.is_putter(ClubCatalog.model(str(l["model_id"]))):
			listing = l
			break
	if listing.is_empty():
		listing = gs.listings("goodwill")[0]
	hub._show_inspect(ClubCatalog.model(str(listing["model_id"])), {"kind": "listing", "store_id": "goodwill", "listing": listing})
	hold_viewer()
	await snap(prefix + "_listing.png")

	var owned: ClubInstance = null
	for id in gs.clubs:
		var inst: ClubInstance = gs.clubs[id]
		if not ClubCatalog.is_putter(inst.model()):
			owned = inst
			break
	if owned != null:
		hub._show_inspect(owned.model(), {"kind": "owned", "instance": owned})
		hold_viewer()
		await snap(prefix + "_owned.png")

	var best_driver := {}
	for m: Dictionary in ClubCatalog.models():
		if str(m.get("type", "")) == "driver" and not ClubCatalog.is_illegal(m):
			if best_driver.is_empty() or EconomyConfig.rarity_rank(str(m.get("rarity", ""))) > EconomyConfig.rarity_rank(str(best_driver.get("rarity", ""))):
				best_driver = m
	if not best_driver.is_empty():
		hub._show_inspect(best_driver, {"kind": "preview", "listing": {"condition": 1.0}})
		hold_viewer()
		await snap(prefix + "_preview_driver.png")

	var putters := ClubCatalog.collectible_putters()
	if not putters.is_empty():
		var p: Dictionary = putters[putters.size() - 1]
		hub._show_inspect(p, {"kind": "preview", "listing": {"condition": 0.82}})
		hold_viewer()
		await snap(prefix + "_putter.png")
	quit(0)
