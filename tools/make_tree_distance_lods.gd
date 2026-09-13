extends SceneTree
## Retain the source canopy's occupied space with small crossed leaf clusters.
## Real 3D geometry for 90-450 m; high-detail meshes remain in the near tiers.
const OUTPUT := 'res://nature_pack/models/trees/distance/'

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var ids: Array = []
	for group in [ForestPlanter.PINES, ForestPlanter.HARDWOODS, ForestPlanter.UNDERSTORY_TREES, ForestPlanter.FRINGE_TREES, ForestPlanter.WATERSIDE]:
		for id in group:
			if not ids.has(id):
				ids.append(id)
	for id in ids:
		bake(id)
	quit()

func bake(id: String) -> void:
	var source := NaturePack.mesh_mid(id)
	var result := ArrayMesh.new()
	var original := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		original += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var material := source.surface_get_material(surface)
		var foliage := material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path.ends_with('nature_leaves.gdshader')
		if not foliage:
			var info := RenderingServer.mesh_get_surface(source.get_rid(), surface)
			for lod in info.get('lods', []):
				var bytes: PackedByteArray = lod.index_data
				var stride := 4 if int(info.vertex_count) > 65536 else 2
				var count := bytes.size() / stride
				if count < 700:
					break
				var indices := PackedInt32Array()
				indices.resize(count)
				for i in range(count):
					indices[i] = bytes.decode_u32(i * stride) if stride == 4 else bytes.decode_u16(i * stride)
				arrays[Mesh.ARRAY_INDEX] = indices
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var cells: Dictionary = {}
			const CELL := 0.62
			for i in range(vertices.size()):
				var p := vertices[i]
				var key := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
				if not cells.has(key):
					cells[key] = [p, colors[i], 1, p, p]
				else:
					var cell: Array = cells[key]
					cell[0] += p
					cell[1] += colors[i]
					cell[2] += 1
					cell[3] = (cell[3] as Vector3).min(p)
					cell[4] = (cell[4] as Vector3).max(p)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for cell in cells.values():
				var center: Vector3 = cell[0] / float(cell[2])
				var color: Color = cell[1] / float(cell[2])
				var extent: Vector3 = cell[4] - cell[3]
				var reach := clampf(extent.length() * 0.60, 0.22, 0.60)
				var yaw := rng.randf_range(0, TAU)
				for j in range(3):
					var axis := Vector3(cos(yaw + j * TAU / 3), rng.randf_range(-0.45, 0.45), sin(yaw + j * TAU / 3)).normalized()
					var across := axis.cross(Vector3.UP).normalized().rotated(axis, j * 1.05)
					var normal := across.cross(axis).normalized()
					var points := [center - axis * reach, center + across * reach * 0.56, center + axis * reach, center - across * reach * 0.56]
					for k in [0, 1, 2, 0, 2, 3]:
						st.set_normal(normal)
						st.set_color(color * rng.randf_range(0.94, 1.04))
						st.set_uv2(Vector2.ZERO)
						st.add_vertex(points[k])
			st.index()
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		result.surface_set_name(result.get_surface_count() - 1, 'leaves' if foliage else 'bark')
	var output := OUTPUT + id + '.res'
	var error := ResourceSaver.save(result, output, ResourceSaver.FLAG_COMPRESS)
	assert(error == OK)
	print('%s: %d -> %d triangles' % [id, original, result.get_faces().size() / 3])
