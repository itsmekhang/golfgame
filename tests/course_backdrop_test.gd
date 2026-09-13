extends SceneTree
func _init() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(-100, -100, 200, 200)
	var bounds := Rect2(-64, -128, 128, 256)
	var node := CourseBackdrop.build_apron(layout, bounds)
	var box := node.mesh.get_aabb()
	assert(box.position.x <= bounds.position.x - 12000.0)
	assert(box.end.z >= bounds.end.y + 12000.0)
	var arrays := node.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for normal in normals:
		assert(normal.y > 0, "Landscape faces must point up")
	assert(node.mesh.get_faces().size() / 3 < 10000, "Background geometry stays cheap")
	assert(node.get_child_count() == 0, "Backdrop needs no physics bodies")
	print("COURSE BACKDROP: PASS; ", node.mesh.get_faces().size() / 3, " triangles; 12km apron")
	node.free()
	var course := CourseBuilder.build(7)
	course.build_feature_mask()
	var region := course.hole_bbox(course.holes[0]).grow(60.0)
	var terrain := Node3D.new()
	var tile := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [region.position, Vector2(region.end.x, region.position.y), region.end, region.position, region.end, Vector2(region.position.x, region.end.y)]:
		st.add_vertex(Vector3(p.x, 0.0, p.y))
	tile.mesh = st.commit()
	terrain.add_child(tile)
	var backdrop := CourseBackdrop.build(course, terrain)
	assert(backdrop.get_meta('distant_tree_count') > 1000)
	assert(backdrop.get_node('DistantCourse').mesh != null)
	assert(backdrop.get_node('CourseEdgeJoin').mesh != null)
	var triangles := visual_budget(backdrop)
	assert(triangles < 250000, 'Full-course backdrop exceeds its geometry budget')
	print('DISTANT COURSE: PASS; ', backdrop.get_meta('distant_tree_count'), ' inexpensive trees; ', triangles, ' total triangles; no collision bodies')
	backdrop.free()
	terrain.free()
	for hazard in course.water_hazards:
		hazard.free()
	for bunker in course.bunkers:
		bunker.free()
	quit()

func visual_budget(node: Node) -> int:
	assert(not node is CollisionObject3D, 'Backdrop must remain visual only')
	var triangles := 0
	if node is MeshInstance3D and node.mesh != null:
		triangles += node.mesh.get_faces().size() / 3
	if node is MultiMeshInstance3D:
		triangles += node.multimesh.mesh.get_faces().size() / 3 * node.multimesh.instance_count
	for child in node.get_children():
		triangles += visual_budget(child)
	return triangles
