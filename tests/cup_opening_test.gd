extends SceneTree
## A visual opening must also work on triangle edges and tile boundaries without
## deleting the putting surface around it. Run headless; no course build needed.
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://cup_opening_test_unused.json")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)

func tile(origin: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector2.ZERO, Vector2(2, 0), Vector2(0, 2), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)]:
		point += origin
		st.set_normal(Vector3(-0.02, 1.0, -0.01).normalized())
		st.set_color(Color(0.3, 0.6, 0.2))
		st.set_uv(point * 0.05)
		st.add_vertex(Vector3(point.x, point.x * 0.02 + point.y * 0.01, point.y))
	st.index()
	return st.commit(null, 0)

func covered(mesh: ArrayMesh, point: Vector2) -> bool:
	var faces := mesh.get_faces()
	for i in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(Vector3(point.x, 500, point.y), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false

func run() -> void:
	var origin := Vector2(2400, 1200)
	for local in [Vector2(0.6, 0.7), Vector2(1, 1), Vector2.ZERO, Vector2(2, 1)]:
		var center: Vector2 = origin + local
		var cut := TerrainCupCutout.cut(tile(origin), center, GolfBall.CUP_RADIUS)
		check(not covered(cut, center + Vector2(0.002, 0.002)), "The cup opens through the terrain at %s" % local)
		for i in range(32):
			var direction := Vector2.from_angle(i * TAU / 32)
			var outside := center + direction * 0.09
			var inside := center + direction * 0.07
			if Rect2(origin, Vector2(2, 2)).grow(-0.001).has_point(outside):
				check(covered(cut, outside), "Green remains intact just outside the lip at %s" % local)
			if Rect2(origin, Vector2(2, 2)).grow(-0.001).has_point(inside):
				check(not covered(cut, inside), "Nothing covers the cup interior at %s" % local)
		var faces := cut.get_faces()
		var area := 0.0
		for i in range(0, faces.size(), 3):
			var cross := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
			check(cross.y < 0.000001, "Cut pieces preserve the terrain face winding")
			area += absf(cross.y) * 0.5
			for j in range(3):
				var p := faces[i + j]
				# Packed mesh positions several kilometres from the origin have
				# sub-millimetre float precision; keep the surface within 0.25 mm.
				check(absf(p.y - p.x * 0.02 - p.z * 0.01) < 0.00025, "New edges follow the existing slope")
		var fraction := 0.25 if local == Vector2.ZERO else 0.5 if local.x == 2 else 1.0
		var hole_area := 0.5 * TerrainCupCutout.SEGMENTS * GolfBall.CUP_RADIUS ** 2 * sin(TAU / TerrainCupCutout.SEGMENTS)
		check(absf(area - (4.0 - fraction * hole_area)) < 0.002, "Only the cup mouth is removed")
	print("CUP OPENING: ", "FAIL" if failed else "PASS", "; sloped triangles, diagonal, corner and tile boundary")
	quit(1 if failed else 0)
