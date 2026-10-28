extends SceneTree
## Capture the actual Inspect dialog for every driver, using a private unsaved state.
## Run with a real renderer: godot --path . --script tests/screenshot_driver_inspect.gd
var hub: HubMenu
var prefix := "res://build/driver_inspect"

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://driver_inspect_capture_unused.json")
	call_deferred("run")

func snap(path: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	assert(error == OK)
	print("[driver_inspect] ", path)

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

func inspect(id: String, condition: float, angle: float) -> ClubViewer3D:
	hub._show_inspect(ClubCatalog.model(id), {"kind": "preview", "listing": {"condition": condition}})
	var viewer := find_viewer(hub._inspect)
	if viewer == null:
		printerr("FAIL: no 3D driver viewer for ", id)
		quit(1)
		return null
	viewer._spin = false
	viewer._yaw = angle
	viewer._pitch = -0.38
	viewer._update_camera()
	return viewer

func run() -> void:
	AdminAccess.set_override(true)
	hub = HubMenu.new()
	root.add_child(hub)
	hub.open("admin")
	await snap(prefix + "_admin.png")
	var count := 0
	for model: Dictionary in ClubCatalog.models():
		if str(model.get("type", "")) != "driver":
			continue
		var id := str(model.id)
		if inspect(id, 1.0, 2.45) == null:
			return
		await snap(prefix + "_" + id + ".png")
		hub._inspect.visible = false
		count += 1
	if inspect("loaner_driver", 0.35, 2.45) == null:
		return
	await snap(prefix + "_worn.png")
	hub._inspect.visible = false
	if inspect("loaner_driver", 1.0, 0.6) == null:
		return
	await snap(prefix + "_rear.png")
	print("DRIVER INSPECT CAPTURE: PASS (", count, " drivers)")
	quit(0)
