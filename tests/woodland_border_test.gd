extends SceneTree
var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://woodland_border_test_unused.json")
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func run() -> void:
	var span := ForestPlanter.BUSH_SPACING * 20.0
	var bounds := Rect2(0, 0, span, span)
	var site := func(p: Vector2) -> bool: return p.x >= span * 0.5
	var cells := ForestPlanter._understory_cells(bounds, site)
	check(cells.size() == 200, "Only the forest half of the test site is occupied")
	for z in range(20):
		check(ForestPlanter._understory_edge(Vector2i(10, z), cells, bounds), "Continuous front row")
		check(ForestPlanter._understory_edge(Vector2i(11, z), cells, bounds), "Continuous second row")
		check(not ForestPlanter._understory_edge(Vector2i(19, z), cells, bounds), "No false wall on streaming-region cuts")
	for species in [1, 2, 3]:
		var inst: Node = ForestPlanter.FOREST_BUSHES[species].instantiate()
		var found := ForestPlanter._find_first_mesh_xform(inst)
		var mesh: Mesh = found[0]
		var aabb: AABB = found[1] * mesh.get_aabb()
		check(absf(aabb.position.y) < 0.002, "Bush root is at ground level")
		var cutouts := 0
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			check(mat != null and mat.albedo_texture != null, "Bush uses actual color texture")
			check(mat.metallic == 0, "Foliage is not metallic")
			if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				cutouts += 1
				var image := mat.albedo_texture.get_image()
				if image.is_compressed(): image.decompress()
				var colored := 0
				var clear := 0
				for y in range(0, image.get_height(), 16):
					for x in range(0, image.get_width(), 16):
						var c := image.get_pixel(x, y)
						clear += int(c.a < 0.1)
						colored += int(c.a > 0.8 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) > 0.08)
				check(colored > 20 and clear > 20, "Leaves retain color and transparent cutouts")
		check(cutouts > 0, "Cutout foliage exists")
		if species >= 2:
			var limits: Vector2 = ForestPlanter.FOREST_BUSH_SCALE_RANGES[species]
			check(aabb.size.y * limits.x > 1.0 and aabb.size.y * limits.y <= ForestPlanter.FOREST_SHRUB_MAX_HEIGHT, "Forest border shrub stays below head height")
			check(maxf(aabb.size.x, aabb.size.z) * limits.x > 1.5 and maxf(aabb.size.x, aabb.size.z) * limits.y <= ForestPlanter.FOREST_SHRUB_MAX_WIDTH, "Forest shrub crown remains compact with natural variety")
		print("WOODLAND_ASSET ", species, " ", aabb)
		inst.free()
	for suffix in ["albedo", "normal", "roughness", "ao"]:
		var texture := TerrainBuilder._build_rough_array(suffix)
		check(texture != null and texture.get_layers() == 1, "Grass009 rough PBR array: " + suffix)
		check(texture != null and texture.get_width() == 256, "Rough maps downsampled to 256px")
	for path in [TerrainBuilder.FIRST_CUT_TEXTURE, TerrainBuilder.FRINGE_TEXTURE]:
		var texture: Texture2D = load(path)
		check(texture.get_width() == 256 and texture.get_image().has_mipmaps(), "Surrounds have small textures and distant filtering")
	check(TerrainBuilder.COL_TEE_A == TerrainBuilder.COL_GREEN_A, "Tees share the green palette")
	check(TerrainBuilder.ROUGH_VARIANTS == ["009"], "Rough uses Grass009 exclusively")
	check(TerrainBuilder.FIRST_CUT_TEXTURE.ends_with("grass_002_albedo.png"), "First cut uses Grass002")
	check(TerrainBuilder.FRINGE_TEXTURE.ends_with("grass_001_albedo.png"), "Fringe uses Grass001")
	for spec in PropScatter.specs():
		check(not spec.meshes.has("rock_outcrop_A"), "Removed malformed outcrop from rough scatter")
	print("WOODLAND_BORDER failures=", failures)
	quit(0 if failures == 0 else 1)
