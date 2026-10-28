extends SceneTree
## Check actual imported iron and wedge head/shaft joins, including circularity.
const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")
const MUSCLE_BACK_IDS := ["blade_runner_forged", "tour_forged_cb", "combo_proto"]
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://iron_attachment_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func find_mesh(node: Node, suffix: String) -> MeshInstance3D:
	if node is MeshInstance3D and str(node.name).ends_with(suffix):
		return node
	for child in node.get_children():
		var found := find_mesh(child, suffix)
		if found != null:
			return found
	return null

func check_forge_bore(head: MeshInstance3D, shaft: MeshInstance3D, id: String) -> void:
	var axis := shaft.global_basis.y.normalized()
	var mouth := head.global_position
	var inserted := mouth - shaft.global_position
	check(inserted.cross(axis).length() < 0.00002, id + ": bore centered on shaft")
	check(absf(inserted.dot(axis) - 0.006) < 0.00002, id + ": shaft enters bore by 6 mm")
	check(head.global_basis.y.normalized().dot(axis) > 0.999999, id + ": straight neck follows shaft axis")
	check(head.global_basis.get_scale().distance_to(Vector3.ONE) < 0.00001, id + ": source head keeps real scale")
	check(absf(head.global_basis.determinant() - 1.0) < 0.00001, id + ": fitting has no mirror or shear")
	var bands: Array = [[], []]
	var depths := [0.005, 0.020]
	var head_low := INF
	var triangles := 0
	for surface in range(head.mesh.get_surface_count()):
		var arrays := head.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		for vertex in verts:
			var world := head.global_transform * vertex
			head_low = minf(head_low, world.y)
			var offset := world - mouth
			var axial := offset.dot(axis)
			for band in range(2):
				if absf(axial + depths[band]) < 0.0002:
					bands[band].append(Vector2(offset.dot(head.global_basis.x), offset.dot(head.global_basis.z)))
	var expected_triangles := 102488 if id in MUSCLE_BACK_IDS else 110000
	check(triangles == expected_triangles, id + ": complete supplied blade geometry retained")
	check(absf(head_low) < 0.00008, id + ": assembled sole rests at ground level")
	for band in range(2):
		check(bands[band].size() > 40, id + ": hollow neck exists at test section")
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		var inner_radius := INF
		for point: Vector2 in bands[band]:
			low = low.min(point)
			high = high.max(point)
			inner_radius = minf(inner_radius, point.length())
		check(((high + low) * 0.5).length() < 0.0002, id + ": neck stays centered below opening")
		check(absf((high.x - low.x) - (high.y - low.y)) < 0.0004, id + ": neck cross section remains round")
		check(absf(inner_radius - 0.0047) < 0.00003, id + ": original 9.4 mm bore preserved")
	print(id, ": Forge bore aligned, 6 mm insertion, complete head geometry (", triangles, " triangles)")

func run() -> void:
	for model in ClubCatalog.models():
		if str(model.get("type", "")) not in ["iron_set", "wedge"]:
			continue
		var id := str(model.id)
		var club := Equipment.create_club(id, 0.7)
		root.add_child(club)
		var head := find_mesh(club, "__head")
		var shaft := find_mesh(club, "__shaft")
		var fitting: Dictionary = head.get_meta("extras", {})
		if str(model.get("type", "")) == "iron_set":
			var expected_source := "Forge6_28deg_MuscleBack_RoundedHeel" if id in MUSCLE_BACK_IDS else "Forge6_28deg_StraightHosel_v3"
			check(fitting.get("source_asset", "") == expected_source, id + ": correct head assigned to set")
			check_forge_bore(head, shaft, id)
			club.free()
			continue
		var socket := shaft.global_position
		var axis := shaft.global_basis.y.normalized()
		var radial_x := axis.cross(Vector3.FORWARD).normalized()
		var radial_y := axis.cross(radial_x).normalized()
		var ring: Dictionary = {}
		var lower_ring: Dictionary = {}
		var head_low := INF
		for surface in range(head.mesh.get_surface_count()):
			var arrays := head.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for vertex in verts:
				var world := head.global_transform * vertex
				head_low = minf(head_low, world.y)
				var offset := world - socket
				if absf(offset.dot(axis)) < 0.00006 and offset.length() < 0.006:
					ring[world.snapped(Vector3.ONE * 0.000001)] = world
			# Intersect the neck with a plane 5 mm below the shaft tip. This detects
			# a bent join even if a fitting script merely moved its top into place.
			for triangle in range(0, indices.size(), 3):
				for edge in range(3):
					var a := head.global_transform * verts[indices[triangle + edge]]
					var b := head.global_transform * verts[indices[triangle + (edge + 1) % 3]]
					var da := (a - socket).dot(axis) + 0.005
					var db := (b - socket).dot(axis) + 0.005
					if da * db < 0.0:
						var point := a.lerp(b, da / (da - db))
						lower_ring[point.snapped(Vector3.ONE * 0.000001)] = point
		check(ring.size() >= 20, id + ": socket cap meets shaft perpendicularly")
		check(absf(head_low) < 0.00005, id + ": sole rests at ground level")
		if not ring.is_empty():
			var center := Vector3.ZERO
			var min_x := INF
			var max_x := -INF
			var min_y := INF
			var max_y := -INF
			for world: Vector3 in ring.values():
				center += world
				var offset := world - socket
				min_x = minf(min_x, offset.dot(radial_x))
				max_x = maxf(max_x, offset.dot(radial_x))
				min_y = minf(min_y, offset.dot(radial_y))
				max_y = maxf(max_y, offset.dot(radial_y))
			center /= ring.size()
			check(center.distance_to(socket) < 0.00015, id + ": head socket centers on shaft")
			check(absf((max_x - min_x) - (max_y - min_y)) < 0.00015, id + ": neck is round, not flattened")
			check(absf((max_x - min_x) - 0.0092) < 0.00015, id + ": neck diameter matches shaft tip")
		if lower_ring.size() >= 12:
			var center := Vector3.ZERO
			for point: Vector3 in lower_ring.values():
				center += point
			center /= lower_ring.size()
			var axis_error := (center - socket).cross(axis).length()
			check(axis_error < 0.0004, id + ": neck continues straight below joint")
			print(id, ": socket vertices=", ring.size(), ", neck axis error=", axis_error * 1000.0, " mm")
		else:
			check(false, id + ": neck exists below joint")
		club.free()
	print("IRON/WEDGE ATTACHMENT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
