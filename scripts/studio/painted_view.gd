class_name PaintedView
extends Node3D
## Live preview of a PaintedCourse: one displaced grid mesh with the studio terrain shader
## (shaders/studio_terrain.gdshader) plus impostor trees for the woods and single trees.
## Used by the Course Studio while painting and by the start menu backdrop.

const TILE_DIR := "res://assets/textures/tiles/"
## Dense grass for the rough, tinted to the game's rough green (darker than the fairway).
const ROUGH_TEX := "res://assets/textures/tiles/rough_variants/rough_001_albedo.png"
const WOODS_PREVIEW_SPACING := 8.5
const MAP_TILE := 64.0  # m: the trees' batches, culled each on its own
## How far out (from the camera) the woods and trees are their species' real low-poly meshes
## (NaturePack.mesh_map: ~3-5k triangles each) before the cheap crowns take over (user: real
## trees, not the crowns' shapes) -- beyond the game's own tree distance: the map's camera stands
## back further.
static func real_tree_reach() -> float:
	return PerformanceSettings.tree_distance() * 1.3


const WOODS_SPECIES := ["loblolly_pine_A", "longleaf_pine_A", "loblolly_pine_A", "white_oak_A", "red_maple_A", "sweetgum_A", "tulip_poplar_A"]

var course: PaintedCourse
var terrain: MeshInstance3D
var material: ShaderMaterial
var trees_root: Node3D
var _tex_h: ImageTexture
var _tex_a: ImageTexture
var _tex_b: ImageTexture
## Grid spacing of the terrain mesh (m); the menu uses a finer grid over a small canvas.
var grid_step := 2.0
var _proxy_mat: StandardMaterial3D


func _init() -> void:
	terrain = MeshInstance3D.new()
	terrain.name = "Terrain"
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/studio_terrain.gdshader")
	material.set_shader_parameter("fairway_tex", load(TILE_DIR + "fairway_tile.png"))
	material.set_shader_parameter("rough_tex", load(ROUGH_TEX))
	material.set_shader_parameter("rough_col", TerrainBuilder.ROUGH_COLOR)
	material.set_shader_parameter("green_tex", load(TILE_DIR + "green_tile.png"))
	material.set_shader_parameter("sand_tex", load(TILE_DIR + "sand_tile.png"))
	material.set_shader_parameter("straw_tex", load(TILE_DIR + "pine_straw_tile.png"))
	terrain.material_override = material
	terrain.extra_cull_margin = 400.0
	add_child(terrain)
	trees_root = Node3D.new()
	trees_root.name = "Trees"
	add_child(trees_root)


func set_course(c: PaintedCourse) -> void:
	course = c
	var pm := PlaneMesh.new()
	pm.size = Vector2(course.size) * PaintedCourse.CELL
	pm.subdivide_width = int(pm.size.x / grid_step)
	pm.subdivide_depth = int(pm.size.y / grid_step)
	terrain.mesh = pm
	terrain.position = Vector3(course.origin.x + pm.size.x * 0.5, 0.0, course.origin.y + pm.size.y * 0.5)
	_tex_h = ImageTexture.create_from_image(course.height_image())
	_tex_a = ImageTexture.create_from_image(course.splat_a_image())
	_tex_b = ImageTexture.create_from_image(course.splat_b_image())
	material.set_shader_parameter("height_tex", _tex_h)
	material.set_shader_parameter("splat_a", _tex_a)
	material.set_shader_parameter("splat_b", _tex_b)
	material.set_shader_parameter("canvas_origin", course.origin)
	material.set_shader_parameter("canvas_size", Vector2(course.size) * PaintedCourse.CELL)
	material.set_shader_parameter("texel", PaintedCourse.CELL)
	if not course.holes.is_empty():
		var h: Dictionary = course.holes[0]
		material.set_shader_parameter("stripe_dir", ((h["pin"] as Vector2) - (h["tee"] as Vector2)).normalized())
	rebuild_trees()


func push_textures() -> void:
	_tex_h.update(course.height_image())
	_tex_a.update(course.splat_a_image())
	_tex_b.update(course.splat_b_image())


func rebuild_trees() -> void:
	for c in trees_root.get_children():
		c.queue_free()
	var by_id := {}
	var add := func(id: String, p: Vector2, s: float) -> void:
		if not course.pads.is_empty() and course.on_pad(p, 1.0):
			return  # the club's buildings stand here
		if not by_id.has(id):
			by_id[id] = []
		var y := course.height_at(p)
		var basis := Basis(Vector3.UP, fposmod(p.x * 12.9898 + p.y * 78.233, TAU)).scaled(Vector3.ONE * s)
		(by_id[id] as Array).append(Transform3D(basis, Vector3(p.x, y - 0.3, p.y)))
	# woods: a jittered grid over the painted cover (the game plants its own, denser forest)
	var sp := WOODS_PREVIEW_SPACING
	var b := course.bounds()
	var z := b.position.y + sp * 0.5
	var row := 0
	while z < b.end.y:
		var x := b.position.x + sp * (0.5 if row % 2 == 0 else 1.0)
		while x < b.end.x:
			var h := absf(sin(x * 12.9898 + z * 78.233) * 43758.5453)
			var j := Vector2(fmod(h, 1.0) - 0.5, fmod(h * 7.0, 1.0) - 0.5) * sp * 0.8
			var p := Vector2(x, z) + j
			if course.coverage(PaintedCourse.Surface.WOODS, p) > 0.5:
				var k := int(fmod(h * 13.0, 1.0) * WOODS_SPECIES.size()) % WOODS_SPECIES.size()
				add.call(WOODS_SPECIES[k], p, 0.75 + fmod(h * 3.0, 1.0) * 0.4)
			x += sp
		z += sp * 0.87
		row += 1
	for t in course.trees:
		add.call(String(t[0]), t[1] as Vector2, 0.95)
	# Each species' own low-poly tree near the camera (real_tree_reach), in tiles; past that, and
	# for a species with none, low-poly 3D crowns (NaturePack's far proxies: a conifer and a
	# hardwood shape, ~60 tris) that read right from any angle and cost next to nothing.
	var reach := real_tree_reach()
	if _proxy_mat == null:
		_proxy_mat = StandardMaterial3D.new()
		_proxy_mat.vertex_color_use_as_albedo = true
		_proxy_mat.albedo_color = Color(0.3, 0.34, 0.26)  # (toned down to the real trees' shade, so the hand-over doesn't show)
		_proxy_mat.metallic_specular = 0.0  # (no sheen off their smooth faces: the leaves have none)
		_proxy_mat.roughness = 0.95
	var pooled := {"pine": [], "hardwood": []}
	for id in by_id:
		var kind := "pine" if (String(id).contains("pine") or String(id).contains("cedar") or String(id).contains("cypress")) else "hardwood"
		var h := NaturePack.dims(id).y if NaturePack.catalog().has(id) else 15.0
		var real := NaturePack.mesh_map(String(id), reach)
		if real != null:
			VegetationBatches.add_batches(trees_root, String(id), real, by_id[id], null, true, reach, MAP_TILE)
		for xf: Transform3D in by_id[id]:
			pooled[kind].append([Transform3D(xf.basis.scaled(Vector3.ONE * h), xf.origin), real != null])
	for kind in pooled:
		var near: Array = []  # (crowns all the way in: species with no low-poly mesh)
		var far: Array = []
		for e: Array in pooled[kind]:
			(far if e[1] else near).append(e[0])
		if not near.is_empty():
			VegetationBatches.add_batches(trees_root, "crown_" + kind, NaturePack.far_proxy_mesh(kind), near, _proxy_mat, true, 1.0e5, MAP_TILE * 4.0)
		if not far.is_empty():
			VegetationBatches.add_batches(trees_root, "crown_far_" + kind, NaturePack.far_proxy_mesh(kind), far, _proxy_mat, true, 1.0e5, MAP_TILE, false, reach)
