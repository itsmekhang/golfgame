class_name CourseBackdrop
extends RefCounted
## A visual terrain apron: dense enough to join the loaded tiles, then increasingly
## coarse rings out beyond the camera's far plane. No grass, physics, or tile cache.
const REACH := 12000.0
const RINGS := [0.0, 8.0, 32.0, 96.0, 256.0, 640.0, 1600.0, 4000.0, REACH]
const GRID_STEP := 12.0
const FOREST_REACH := 2400.0

static func build(layout: CourseLayout, terrain: Node3D) -> MeshInstance3D:
	var bounds := Rect2()
	for child in terrain.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var aabb: AABB = child.mesh.get_aabb()
			var rect := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z)
			bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	if bounds.size == Vector2.ZERO:
		return null
	# Coarse terrain and baked tree cards fill the other holes. Only the active
	# region has fine terrain, grass, physics bodies, or streamed vegetation.
	var outer := layout.bounds.grow(360.0)
	var root := build_apron(layout, outer, GRID_STEP)
	var ground := MeshInstance3D.new()
	ground.name = "DistantCourse"
	ground.mesh = _course_mesh(layout, outer)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/course_backdrop.gdshader")
	mat.set_shader_parameter("rough_texture", load("res://assets/textures/tiles/rough_tile.png"))
	mat.set_shader_parameter("feature_mask", layout.mask_texture)
	mat.set_shader_parameter("mask_origin", layout.bounds.position)
	mat.set_shader_parameter("mask_size", Vector2(layout.mask_image.get_width(), layout.mask_image.get_height()) * CourseLayout.MASK_CELL)
	mat.set_shader_parameter("active_min", bounds.grow(8.0).position)
	mat.set_shader_parameter("active_max", bounds.grow(8.0).end)
	mat.set_shader_parameter("fairway_color", TerrainBuilder.COL_FAIRWAY_A)
	mat.set_shader_parameter("green_color", TerrainBuilder.COL_GREEN_A)
	mat.set_shader_parameter("sand_color", TerrainBuilder.COL_BUNKER)
	ground.material_override = mat
	root.add_child(ground)
	var join := _join_loaded_edge(layout, bounds, outer, ground.mesh)
	var join_mat: ShaderMaterial = mat.duplicate()
	join_mat.set_shader_parameter("active_min", bounds.position)
	join_mat.set_shader_parameter("active_max", bounds.end)
	join.material_override = join_mat
	root.add_child(join)
	_add_distant_trees(root, layout, bounds, outer)
	var straw := _distant_straw(layout, outer)
	for material in [mat, join_mat]:
		material.set_shader_parameter("straw_mask", straw)
		material.set_shader_parameter("straw_texture", load(TerrainBuilder.STRAW_TEXTURE))
		material.set_shader_parameter("straw_origin", outer.position)
		material.set_shader_parameter("straw_size", outer.size)
	return root

static func build_apron(layout: CourseLayout, bounds: Rect2, edge_step: float = 2.0) -> MeshInstance3D:
	var nx := maxi(1, int(ceil(bounds.size.x / edge_step)))
	var nz := maxi(1, int(ceil(bounds.size.y / edge_step)))
	var perimeter := 2 * (nx + nz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in RINGS:
		var rect := bounds.grow(ring)
		for side in range(4):
			var count := nx if side % 2 == 0 else nz
			for i in range(count):
				var t := float(i) / count
				var p: Vector2
				match side:
					0: p = Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y)
					1: p = Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t))
					2: p = Vector2(lerpf(rect.end.x, rect.position.x, t), rect.end.y)
					_: p = Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, t))
				var h := layout.height_at(p.x, p.y) if ring <= 32.0 else layout._raw_height(p.x, p.y)
				# Broad, low hills in the surrounding countryside.
				h += layout.hills_noise.get_noise_2d(p.x * 0.35, p.y * 0.35) * 18.0 * smoothstep(96.0, 640.0, ring)
				st.set_uv(p * 0.35)
				st.set_color(Color(0.8, 0.8, 0.8, 1.0).lerp(Color.WHITE, (layout.noise.get_noise_2d(p.x, p.y) + 1.0) * 0.5))
				st.add_vertex(Vector3(p.x, h - 0.04, p.y))
	for r in range(RINGS.size() - 1):
		for i in range(perimeter):
			var j := (i + 1) % perimeter
			var a := r * perimeter + i
			var b := r * perimeter + j
			var c := (r + 1) * perimeter + i
			var d := (r + 1) * perimeter + j
			for index in [a, c, b, b, c, d]:
				st.add_index(index)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "DistantLandscape"
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/course_horizon.gdshader")
	mat.set_shader_parameter("rough_texture", load("res://assets/textures/tiles/rough_tile.png"))
	node.material_override = mat
	return node


static func _course_mesh(layout: CourseLayout, bounds: Rect2) -> ArrayMesh:
	if layout.has_meta("distant_course_mesh"):
		return layout.get_meta("distant_course_mesh")
	var nx := int(ceil(bounds.size.x / GRID_STEP)) + 1
	var nz := int(ceil(bounds.size.y / GRID_STEP)) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(nz):
		for x in range(nx):
			var p := bounds.position + Vector2(bounds.size.x * x / (nx - 1), bounds.size.y * z / (nz - 1))
			var h := layout._raw_height(p.x, p.y)
			var turf := 100.0
			if layout.bounds.has_point(p):
				var fds := layout._hole_fds(p)
				h = layout.base_height_from(p.x, p.y, fds)
				turf = layout.turf_sd_from(fds)
			st.set_color(Color(clampf(0.5 - turf / 24.0, 0.0, 1.0), 0, 0, 1))
			st.set_uv(p * 0.35)
			st.add_vertex(Vector3(p.x, h - 0.18, p.y))
	for z in range(nz - 1):
		for x in range(nx - 1):
			var a := z * nx + x
			for i in [a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]:
				st.add_index(i)
	st.generate_normals()
	var mesh := st.commit()
	layout.set_meta("distant_course_mesh", mesh)
	return mesh


static func _add_distant_trees(root: Node3D, layout: CourseLayout, active: Rect2, bounds: Rect2) -> void:
	const SPECIES := ["loblolly_pine_A", "longleaf_pine_A", "eastern_white_pine_A", "white_oak_A", "red_maple_A"]
	var groups: Dictionary = {}
	if layout.has_meta("distant_course_trees"):
		groups = layout.get_meta("distant_course_trees")
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = layout.terrain_seed + 809
		var nx := int(ceil(bounds.size.x / 13.0))
		var nz := int(ceil(bounds.size.y / 13.0))
		for z in range(nz):
			for x in range(nx):
				var p := bounds.position + Vector2(x + rng.randf(), z + rng.randf()) * 13.0
				if rng.randf() < 0.15 or not bounds.has_point(p):
					continue
				if layout.bounds.has_point(p):
					if layout.turf_signed_distance(p) < 10.0 or layout.hazard_near(p, 5.0) or layout.bunker_near(p, 5.0):
						continue
				var id: String = SPECIES[rng.randi_range(0, 2) if rng.randf() < 0.78 else rng.randi_range(3, 4)]
				var scale := rng.randf_range(0.8, 1.4)
				var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale)
				var h := layout.base_height_at(p.x, p.y) if layout.bounds.has_point(p) else layout._raw_height(p.x, p.y)
				if not groups.has(id):
					groups[id] = []
				groups[id].append(Transform3D(basis, Vector3(p.x, h - 0.35, p.y)))
		layout.set_meta("distant_course_trees", groups)
	var count := 0
	var forest := Node3D.new()
	forest.name = "DistantWoodland"
	root.add_child(forest)
	for id in groups:
		var transforms: Array = []
		for transform: Transform3D in groups[id]:
			var p := Vector2(transform.origin.x, transform.origin.z)
			if active.grow(4.0).has_point(p):
				continue
			transforms.append(transform)
		count += transforms.size()
		var imp := NaturePack.impostor(id)
		if imp.is_empty():
			continue
		var material: ShaderMaterial = imp[1].duplicate()
		material.set_shader_parameter("near_cut", 0.0)
		material.set_shader_parameter("far_cut", FOREST_REACH)
		material.set_shader_parameter("color_scale", 0.48)
		VegetationBatches.add_batches(forest, id, imp[0], transforms, material, false, FOREST_REACH, 192.0)
	for batch in forest.get_children():
		batch.layers = PerformanceSettings.TREE_LAYER
	root.set_meta("distant_tree_count", count)


static func _distant_straw(layout: CourseLayout, bounds: Rect2) -> ImageTexture:
	if layout.has_meta("distant_straw_mask"):
		return layout.get_meta("distant_straw_mask")
	const CELL := 4.0
	var width := int(ceil(bounds.size.x / CELL))
	var height := int(ceil(bounds.size.y / CELL))
	var image := Image.create(width, height, false, Image.FORMAT_R8)
	image.fill(Color(0, 0, 0, 1))
	var groups: Dictionary = layout.get_meta("distant_course_trees")
	for id in groups:
		var dimensions := NaturePack.dims(id)
		for transform: Transform3D in groups[id]:
			var center := Vector2(transform.origin.x, transform.origin.z)
			var radius := maxf(dimensions.x, dimensions.z) * transform.basis.get_scale().x * 0.525
			var point := (center - bounds.position) / bounds.size * Vector2(width, height)
			var pixels := radius / CELL
			for y in range(maxi(0, floori(point.y - pixels)), mini(height, ceili(point.y + pixels) + 1)):
				for x in range(maxi(0, floori(point.x - pixels)), mini(width, ceili(point.x + pixels) + 1)):
					var weight := 1.0 - smoothstep(0.5, 1.0, Vector2(x + 0.5, y + 0.5).distance_to(point) / pixels)
					image.set_pixel(x, y, Color(maxf(weight, image.get_pixel(x, y).r), 0, 0, 1))
	var texture := ImageTexture.create_from_image(image)
	layout.set_meta("distant_straw_mask", texture)
	return texture


static func _join_loaded_edge(layout: CourseLayout, active: Rect2, outer: Rect2, course_mesh: ArrayMesh) -> MeshInstance3D:
	var nx := maxi(1, int(ceil(active.size.x / 2.0)))
	var nz := maxi(1, int(ceil(active.size.y / 2.0)))
	var perimeter := 2 * (nx + nz)
	var grid_x := int(ceil(outer.size.x / GRID_STEP)) + 1
	var grid_z := int(ceil(outer.size.y / GRID_STEP)) + 1
	var vertices: PackedVector3Array = course_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in [0.0, 8.0]:
		var rect := active.grow(ring)
		for side in range(4):
			var count := nx if side % 2 == 0 else nz
			for i in range(count):
				var t := float(i) / count
				var p: Vector2
				match side:
					0: p = Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y)
					1: p = Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t))
					2: p = Vector2(lerpf(rect.end.x, rect.position.x, t), rect.end.y)
					_: p = Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, t))
				var h := layout.height_at(p.x, p.y) - 0.04
				if ring > 0.0:
					var f := (p - outer.position) / outer.size * Vector2(grid_x - 1, grid_z - 1)
					var x := clampi(floori(f.x), 0, grid_x - 2)
					var z := clampi(floori(f.y), 0, grid_z - 2)
					var u := clampf(f.x - x, 0.0, 1.0)
					var v := clampf(f.y - z, 0.0, 1.0)
					var a := vertices[z * grid_x + x].y
					var b := vertices[z * grid_x + x + 1].y
					var c := vertices[(z + 1) * grid_x + x].y
					var d := vertices[(z + 1) * grid_x + x + 1].y
					h = a + (b - a) * u + (c - a) * v if u + v <= 1.0 else d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)
				st.set_color(Color(clampf(0.5 - layout.turf_signed_distance(p) / 24.0, 0, 1), 0, 0, 1))
				st.set_uv(p * 0.35)
				st.add_vertex(Vector3(p.x, h, p.y))
	for i in range(perimeter):
		var j := (i + 1) % perimeter
		for index in [i, i + perimeter, j, j, i + perimeter, j + perimeter]:
			st.add_index(index)
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "CourseEdgeJoin"
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
