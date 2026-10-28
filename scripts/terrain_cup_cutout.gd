class_name TerrainCupCutout
extends RefCounted
## Cut a small polygonal opening while a terrain tile is built. Only the few
## triangles touching the cup change; rendering needs no masks or extra passes.
const SEGMENTS := 32

static func cut(mesh: ArrayMesh, center: Vector2, radius: float) -> ArrayMesh:
	var edges: Array[Vector3] = []
	var apothem := radius * cos(PI / SEGMENTS)
	for edge in range(SEGMENTS):
		var normal := Vector2.from_angle((edge + 0.5) * TAU / SEGMENTS)
		edges.append(Vector3(normal.x, normal.y, apothem))
	return _cut_polygon(mesh, center, radius, edges)


## Replace the ground beneath a tee overlay instead of drawing two competing surfaces.
static func cut_rectangle(mesh: ArrayMesh, center: Vector2, direction: Vector2, half: Vector2) -> ArrayMesh:
	var forward := direction.normalized()
	var right := Vector2(-forward.y, forward.x)
	var edges: Array[Vector3] = [Vector3(right.x, right.y, half.x), Vector3(-right.x, -right.y, half.x),
		Vector3(forward.x, forward.y, half.y), Vector3(-forward.x, -forward.y, half.y)]
	return _cut_polygon(mesh, center, half.length(), edges)


static func _cut_polygon(mesh: ArrayMesh, center: Vector2, radius: float, edges: Array[Vector3]) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array()
	for i in range(0, source.size(), 3):
		var ia := source[i]
		var ib := source[i + 1]
		var ic := source[i + 2]
		var a := vertices[ia]
		var b := vertices[ib]
		var c := vertices[ic]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		if center.x + radius < lo.x or center.x - radius > hi.x or center.y + radius < lo.z or center.y - radius > hi.z:
			indices.append_array(PackedInt32Array([ia, ib, ic]))
			continue
		# Barycentric coordinates retain the original triangle's height, tint,
		# UVs and normals exactly at each new boundary vertex.
		var remaining: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		for edge: Vector3 in edges:
			if remaining.size() < 3:
				break
			var normal := Vector2(edge.x, edge.y)
			var distances := Vector3(
				normal.dot(Vector2(a.x, a.z) - center) - edge.z,
				normal.dot(Vector2(b.x, b.z) - center) - edge.z,
				normal.dot(Vector2(c.x, c.z) - center) - edge.z)
			var outside: Array[Vector3] = []
			var inside: Array[Vector3] = []
			var previous := remaining[-1]
			var previous_d := distances.dot(previous)
			for point in remaining:
				var d := distances.dot(point)
				if (d > 0.0) != (previous_d > 0.0):
					var intersection := previous.lerp(point, previous_d / (previous_d - d))
					outside.append(intersection)
					inside.append(intersection)
				if d > 0.0:
					outside.append(point)
				else:
					inside.append(point)
				previous = point
				previous_d = d
			remaining = inside
			if outside.size() < 3:
				continue
			var first := vertices.size()
			for weight in outside:
				vertices.append(a + (b - a) * weight.y + (c - a) * weight.z)
				normals.append((normals[ia] * weight.x + normals[ib] * weight.y + normals[ic] * weight.z).normalized())
				colors.append(colors[ia] * weight.x + colors[ib] * weight.y + colors[ic] * weight.z)
				uvs.append(uvs[ia] * weight.x + uvs[ib] * weight.y + uvs[ic] * weight.z)
			for j in range(1, outside.size() - 1):
				indices.append_array(PackedInt32Array([first, first + j, first + j + 1]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	# Godot supplies default tangents when reading a mesh; let it rebuild that
	# stream for the enlarged vertex array (terrain uses world-space texturing).
	arrays[Mesh.ARRAY_TANGENT] = null
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, 0)
	return result
