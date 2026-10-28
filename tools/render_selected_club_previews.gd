extends SceneTree
## Render each selected head through the actual Inspect UI, with private unsaved state.
const OUT := "res://assets/Selected_Club_Heads/previews/"
const REVIEW := "res://build/selected_heads_review/"
var hub: HubMenu

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://selected_heads_preview_unused.json")
	call_deferred("run")

func viewer_in(node: Node) -> ClubViewer3D:
	if node.is_queued_for_deletion(): return null
	if node is ClubViewer3D: return node
	for child in node.get_children():
		var found := viewer_in(child)
		if found != null: return found
	return null

func settle() -> void:
	for frame in range(24): await process_frame
	await RenderingServer.frame_post_draw

func inspect(id: String, condition: float = 1.0) -> ClubViewer3D:
	hub._show_inspect(ClubCatalog.model(id), {"kind": "preview", "listing": {"condition": condition}})
	var viewer := viewer_in(hub._inspect)
	assert(viewer != null, "Missing 3D inspector for " + id)
	viewer._spin = false
	viewer._update_camera()
	return viewer

func save_image(image: Image, path: String) -> void:
	var error := image.save_png(path)
	assert(error == OK, "Failed to save " + path)
	print("CAPTURED ", path)

func run() -> void:
	root.size = Vector2i(1600, 1000)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(REVIEW)
	var ignore := FileAccess.open(REVIEW + ".gdignore", FileAccess.WRITE)
	ignore.close()
	AdminAccess.set_override(true)
	hub = HubMenu.new()
	root.add_child(hub)
	hub.open("admin")
	var count := 0
	for model: Dictionary in ClubCatalog.models():
		if str(model.get("type", "")) not in ["driver", "wood", "hybrid"]: continue
		var id := str(model.id)
		var viewer := inspect(id)
		await settle()
		save_image(viewer._viewport.get_texture().get_image(), OUT + "ofg_" + id + ".png")
		save_image(root.get_texture().get_image(), REVIEW + id + ".png")
		hub._inspect.visible = false
		count += 1
	for id in ["loaner_driver", "loaner_3w"]:
		var viewer := inspect(id, 0.35)
		await settle()
		save_image(root.get_texture().get_image(), REVIEW + id + "_worn.png")
		hub._inspect.visible = false
		viewer = inspect(id)
		viewer._yaw = 0.60
		viewer._pitch = 0.85
		viewer._update_camera()
		await settle()
		save_image(root.get_texture().get_image(), REVIEW + id + "_sole.png")
		hub._inspect.visible = false
	print("SELECTED HEAD PREVIEWS: PASS (", count, " models, plus worn and sole views)")
	quit(0)
