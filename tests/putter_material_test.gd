extends SceneTree
## Check imported assets, including packed builds: replacement heads require UVs
## on every material surface and the matching PBR/condition texture set.
const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://putter_material_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func inspect_head(node: Node, id: String) -> int:
	var heads := 0
	if node is MeshInstance3D and str(node.name).ends_with("__head"):
		heads += 1
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
			check(uv is PackedVector2Array and uv.size() == vertices.size(), id + ": every head vertex has a UV")
			if uv is PackedVector2Array and not uv.is_empty():
				var low: Vector2 = uv[0]
				var high: Vector2 = uv[0]
				for point: Vector2 in uv:
					low = low.min(point)
					high = high.max(point)
				check(low.x >= 0.0 and low.y >= 0.0 and high.x <= 1.0 and high.y <= 1.0,
					id + ": UVs stay inside the atlas")
				check(low.distance_to(high) > 0.01, id + ": finish is mapped over the surface")
			var material := node.get_active_material(surface) as ShaderMaterial
			check(material != null, id + ": condition material is installed")
			if material != null:
				for kind in ["albedo", "orm", "normal", "wear"]:
					var texture := material.get_shader_parameter(kind + "_tex") as Texture2D
					check(texture != null and texture.get_width() == 1024 and
						texture.resource_path.ends_with("/ofg_%s_%s.png" % [id, kind]),
						id + ": correct " + kind + " atlas")
	for child in node.get_children():
		heads += inspect_head(child, id)
	return heads

func run() -> void:
	var count := 0
	for item: Dictionary in Equipment.catalog().values():
		if str(item.get("family", "")) != "putter":
			continue
		var id := str(item.id)
		var club := Equipment.create_club(id, 0.7, true)
		check(club != null, id + ": putter loads")
		if club == null:
			continue
		root.add_child(club)
		check(inspect_head(club, id) > 0, id + ": inspectable head exists")
		club.free()
		count += 1
		print("Checked putter UVs and PBR maps: ", id)
	check(count == 9, "all nine putters are covered")
	print("PUTTER MATERIALS: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
