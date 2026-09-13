extends SceneTree
func _init() -> void:
	var ids: Array = []
	for group in [ForestPlanter.PINES, ForestPlanter.HARDWOODS, ForestPlanter.UNDERSTORY_TREES, ForestPlanter.FRINGE_TREES, ForestPlanter.WATERSIDE]:
		for id in group:
			if not ids.has(id):
				ids.append(id)
	for id in ids:
		var imp := NaturePack.impostor(id)
		if imp.is_empty():
			push_error("Missing cross cards: " + id)
			quit(1)
			return
		assert(imp[0].get_faces().size() == 18)
		assert(imp[1].get_shader_parameter("near_cut") == 450.0)
		assert(imp[1].get_shader_parameter("far_cut") == PerformanceSettings.tree_distance())
		var mid := NaturePack.mesh_mid(id)
		assert(mid.surface_get_material(0).get_shader_parameter("max_dist") == minf(NaturePack.DENSE_AT, PerformanceSettings.tree_distance()))
		var distance_mesh := NaturePack.mesh_distance(id)
		assert(distance_mesh != null, "Missing intermediate tree geometry: " + id)
		var triangles := distance_mesh.get_faces().size() / 3
		assert(triangles <= 6500 and triangles < mid.get_faces().size() / 12, "Tree geometry budget exceeded: " + id)
		assert(distance_mesh.surface_get_material(0).get_shader_parameter("min_dist") == NaturePack.DENSE_AT)
		assert(distance_mesh.surface_get_material(0).get_shader_parameter("max_dist") == minf(450.0, PerformanceSettings.tree_distance()))
		assert(distance_mesh.get_aabb().size.y > mid.get_aabb().size.y * 0.9, "Tree silhouette lost height")
	print("TREE DISTANCE: PASS; ", ids.size(), " species; detailed trees to 90m; cheaper 3D trees to 450m; cross cards to ", PerformanceSettings.tree_distance(), "m")
	quit()
