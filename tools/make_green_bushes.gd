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
		for lod in range(3):
			bake(spec[0], spec[1], spec[2], lod)
		write_scene(spec[0])
	quit()

func bake(label: String, size: Vector3, seed_value: int, lod: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.24, 0.39, 0.115)
	# Overlapping irregular foliage masses keep the silhouette solid at distance.
	var lobe_count := 16 if lod == 2 else 32
	for lobe in range(lobe_count):
		var angle := lobe * 2.399963
		var up := (lobe + 0.5) / float(lobe_count)
		var ring := sqrt(1.0 - up * up)
		var center := Vector3(cos(angle) * size.x * ring * 0.8, size.y * (0.20 + up * 0.9), sin(angle) * size.z * ring * 0.8)
		center.y += rng.randf_range(-0.055, 0.055) * size.y
		var radius := size * Vector3(0.31, 0.38, 0.31) * rng.randf_range(0.86, 1.12)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 6 if lod == 2 else 8
		sphere.rings = 2 if lod == 2 else 4
		var a := sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var tint := base.darkened(rng.randf_range(0.02, 0.22)).srgb_to_linear()
		for idx in (indices if lod > 0 else PackedInt32Array()):
			var v := vertices[idx]
			var ripple := 1.0 + 0.07 * sin(v.x * 19.0 + v.y * 11.0 + v.z * 17.0 + lobe)
			var p := center + v * radius * ripple
			p.y = maxf(p.y, 0.015)
			st.set_normal((normals[idx] / radius).normalized())
			st.set_color(tint)
			st.add_vertex(p)
		# Pointed leaf clusters add readable foliage close up without alpha overdraw.
		if lod == 0:
			branch(st, Vector3(0, 0.04, 0), center)
		var leaf_count: int = [80, 14, 0][lod]
		for leaf in range(leaf_count):
			var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.45, 1), rng.randf_range(-1, 1)).normalized()
			var p := center + n * radius * 1.02
			var side := n.cross(Vector3.UP).normalized()
			if side.length_squared() < 0.01:
				side = Vector3.RIGHT
			var along := side.cross(n).normalized()
			var length := rng.randf_range(0.075, 0.125)
			var width := length * 0.48
			var pts := [p - along * length, p - along * length * 0.35 + side * width, p + along * length * 0.4 + side * width * 0.85, p + along * length, p + along * length * 0.4 - side * width * 0.85, p - along * length * 0.35 - side * width, p + n * 0.018]
			var tint_leaf := base.lightened(rng.randf_range(0.0, 0.10)).srgb_to_linear()
			for edge in range(6):
				var tri := [edge, (edge + 1) % 6, 6]
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
	var suffix: String = ["", "_mid", "_far"][lod]
	mesh.custom_aabb = AABB(Vector3(-size.x * 1.25, 0, -size.z * 1.25), Vector3(size.x * 2.5, size.y * 1.8, size.z * 2.5))
	var mesh_path := OUT + "green_bush_" + label + suffix + ".res"
	assert(ResourceSaver.save(mesh, mesh_path) == OK)
	mesh.take_over_path(mesh_path)
	var node := MeshInstance3D.new()
	node.name = "GreenBush" + label.capitalize()
	node.mesh = mesh
	node.visibility_range_end = 100.0
	if lod == 0:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert(doc.append_from_scene(node, state) == OK)
		assert(doc.write_to_filesystem(state, OUT + "green_bush_" + label + ".glb") == OK)
	print(label, suffix, ": ", mesh.get_faces().size() / 3, " triangles; bounds ", mesh.get_aabb())
	node.free()



func branch(st: SurfaceTool, start: Vector3, end: Vector3) -> void:
	var direction := (end - start).normalized()
	var right := direction.cross(Vector3.FORWARD).normalized()
	var up := direction.cross(right).normalized()
	for side in range(4):
		var a := right * cos(side * PI * 0.5) + up * sin(side * PI * 0.5)
		var b := right * cos((side + 1) * PI * 0.5) + up * sin((side + 1) * PI * 0.5)
		var pts := [start + a * 0.016, start + b * 0.016, end + b * 0.004, end + a * 0.004]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal((a + b).normalized())
			st.set_color(Color(0.22, 0.17, 0.10).srgb_to_linear())
			st.add_vertex(pts[i])

func write_scene(label: String) -> void:
	var root_node := Node3D.new()
	root_node.name = "GreenBush" + label.capitalize()
	for lod in range(3):
		var suffix: String = ["", "_mid", "_far"][lod]
		var node := MeshInstance3D.new()
		node.name = ["Leaves", "Mid", "Distant"][lod]
		node.mesh = load(OUT + "green_bush_" + label + suffix + ".res")
		node.visibility_range_begin = [0.0, 14.0, 35.0][lod]
		node.visibility_range_end = [14.0, 35.0, 100.0][lod]
		node.visibility_range_begin_margin = 0.0
		node.visibility_range_end_margin = 0.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root_node.add_child(node)
		node.owner = root_node
	var scene := PackedScene.new()
	assert(scene.pack(root_node) == OK)
	assert(ResourceSaver.save(scene, OUT + "green_bush_" + label + ".tscn") == OK)
	root_node.free()
