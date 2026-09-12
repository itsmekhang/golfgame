extends SceneTree
## Regenerate the plain green bush assets. No plugins, textures or runtime generation.
const OUT := "res://assets/vegetation/green_bushes/"
const VARIANTS := [
	["rounded", Vector3(0.85, 0.65, 0.8), 1401],
	["spreading", Vector3(1.25, 0.43, 0.85), 1402],
	["upright", Vector3(0.62, 1.0, 0.62), 1403],
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for spec in VARIANTS:
		bake(spec[0], spec[1], spec[2])
	quit()

func bake(label: String, size: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.24, 0.39, 0.115)
	# Overlapping irregular foliage masses keep the silhouette solid at distance.
	for lobe in range(32):
		var angle := lobe * 2.399963
		var up := (lobe + 0.5) / 32.0
		var ring := sqrt(1.0 - up * up)
		var center := Vector3(cos(angle) * size.x * ring * 0.8, size.y * (0.20 + up * 0.9), sin(angle) * size.z * ring * 0.8)
		center.y += rng.randf_range(-0.055, 0.055) * size.y
		var radius := size * Vector3(0.31, 0.38, 0.31) * rng.randf_range(0.86, 1.12)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var a := sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var tint := base.darkened(rng.randf_range(0.02, 0.22)).srgb_to_linear()
		for idx in indices:
			var v := vertices[idx]
			var ripple := 1.0 + 0.07 * sin(v.x * 19.0 + v.y * 11.0 + v.z * 17.0 + lobe)
			var p := center + v * radius * ripple
			p.y = maxf(p.y, 0.015)
			st.set_normal((normals[idx] / radius).normalized())
			st.set_color(tint)
			st.add_vertex(p)
		# Pointed leaf clusters add readable foliage close up without alpha overdraw.
		for leaf in range(14):
			var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.45, 1), rng.randf_range(-1, 1)).normalized()
			var p := center + n * radius * 1.02
			var side := n.cross(Vector3.UP).normalized()
			if side.length_squared() < 0.01:
				side = Vector3.RIGHT
			var along := side.cross(n).normalized()
			var length := rng.randf_range(0.05, 0.10)
			var width := length * 0.48
			var pts := [p - along * length, p + side * width, p + along * length, p - side * width, p + n * 0.025]
			var tint_leaf := base.lightened(rng.randf_range(0.0, 0.10)).srgb_to_linear()
			for tri in [[0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]:
				for index in tri:
					st.set_normal(n)
					st.set_color(tint_leaf)
					var leaf_vertex: Vector3 = pts[index]
					leaf_vertex.y = maxf(leaf_vertex.y, 0.015)
					st.add_vertex(leaf_vertex)
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Plain green foliage"
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	st.index()
	var mesh := st.commit()
	mesh.resource_name = "Green bush " + label
	var mesh_path := OUT + "green_bush_" + label + ".res"
	assert(ResourceSaver.save(mesh, mesh_path) == OK)
	mesh.take_over_path(mesh_path)
	var node := MeshInstance3D.new()
	node.name = "GreenBush" + label.capitalize()
	node.mesh = mesh
	node.visibility_range_end = 100.0
	var scene := PackedScene.new()
	assert(scene.pack(node) == OK)
	assert(ResourceSaver.save(scene, OUT + "green_bush_" + label + ".tscn") == OK)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_scene(node, state) == OK)
	assert(doc.write_to_filesystem(state, OUT + "green_bush_" + label + ".glb") == OK)
	print(label, ": ", mesh.get_faces().size() / 3, " triangles; bounds ", mesh.get_aabb())
	node.free()

