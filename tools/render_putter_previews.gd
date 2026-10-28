extends SceneTree
## Render each putter through the actual Inspect UI, with private unsaved state.
## Saves to res://assets/openfairway_equipment/previews/, the path EquipmentPreview
## falls back to for any id Selected_Club_Heads doesn't cover (all putters today).
const OUT := "res://assets/openfairway_equipment/previews/"
const REVIEW := "res://build/putter_previews_review/"
var hub: HubMenu

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://putter_preview_unused.json")
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
		if str(model.get("type", "")) != "putter": continue
		var id := str(model.id)
		var viewer := inspect(id)
		await settle()
		save_image(viewer._viewport.get_texture().get_image(), OUT + "ofg_" + id + ".png")
		save_image(root.get_texture().get_image(), REVIEW + id + ".png")
		hub._inspect.visible = false
		count += 1
	print("PUTTER PREVIEWS: PASS (", count, " models)")
	quit(0)
