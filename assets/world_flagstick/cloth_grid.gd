extends RefCounted
## One connected surface: important for soft-body pin indices and edge constraints.
const COLUMNS := 20
const ROWS := 12
const WIDTH := 0.55
const HEIGHT := 0.35
const HOIST_X := 0.015
const BOTTOM := 2.07
const COUNT := (COLUMNS + 1) * (ROWS + 1)

static func point(column: int, row: int) -> Vector3:
	var u := float(column) / COLUMNS
	var v := float(row) / ROWS
	# Small initial ripples prevent the perfectly flat sheet from being singular.
	return Vector3(HOIST_X + WIDTH * u, BOTTOM + HEIGHT * v,
		0.008 * sin(u * TAU * 1.5 + v * 0.6) * u)

static func make_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(ROWS + 1):
		for column in range(COLUMNS + 1):
			vertices.append(point(column, row))
			normals.append(Vector3.BACK)
			uv.append(Vector2(float(column) / COLUMNS, float(row) / ROWS))
	for row in range(ROWS):
		for column in range(COLUMNS):
			var a := row * (COLUMNS + 1) + column
			var b := a + 1
			var c := a + COLUMNS + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, d, b, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	return mesh
