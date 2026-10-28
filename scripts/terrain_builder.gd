class_name TerrainBuilder
extends RefCounted
## Builds the terrain as 64 m tiles (vertex-coloured by lie surface) from the layout's
## sample cache, plus water meshes. Tiles can be rebuilt individually after a dig.

const RESOLUTION := 2.0  # metres per vertex (procedural / designed)
const TILE := 64.0
const WATER_UV_DIV := 8.0  # world metres per water UV unit

# Palette matched to the supplied course flyover: restrained olive turf,
# a light putting surface, short intermediate rough, and near-white sand.
const COL_FAIRWAY_A := Color(0.34, 0.47, 0.14)
const COL_FAIRWAY_B := Color(0.33, 0.455, 0.135)
const COL_GREEN_A := Color(0.48, 0.57, 0.24)
const COL_GREEN_B := Color(0.47, 0.56, 0.23)
const COL_FIRST_CUT := Color(0.30, 0.425, 0.13)
const COL_ROUGH := Color(0.07, 0.20, 0.065)
const COL_ROUGH_DRY := Color(0.09, 0.23, 0.075)
# White sand, but not paper-white: below ~0.9 the bowl's slopes and the lip still read in sun.
const COL_BUNKER := Color(0.85, 0.85, 0.81)
const COL_TEE_A := COL_GREEN_A
const COL_TEE_B := COL_GREEN_B
const COL_WATERBED := Color(0.19, 0.24, 0.17)
const COL_PATH := Color(0.55, 0.55, 0.52)
const COL_TREES := Color(0.22, 0.38, 0.14)
const STRIPE_WIDTH := 5.0  # metres between mower passes on the fairway
const TURF_TEXTURE := "res://assets/textures/tiles/fairway_pbr_albedo.png"  # full PBR stylized grass set
const TURF_MEAN := 0.403  # its mean luminance, so the class tints keep their brightness
const TURF_NORMAL := "res://assets/textures/tiles/fairway_pbr_normal.png"
const TURF_ROUGHNESS := "res://assets/textures/tiles/fairway_pbr_roughness.png"
const TURF_AO := "res://assets/textures/tiles/fairway_pbr_ao.png"
const GREEN_CHECK := 2.0
const SAND_TEXTURE := "res://assets/textures/tiles/sand_tile.png"
const SAND_MEAN := 0.781  # its mean luminance, so sand_color/sand_color2 keep their brightness
const STRAW_TEXTURE := "res://assets/textures/tiles/woodland_ground/grass_005_albedo.png"
const STRAW_MEAN := 1.0
const STRAW_TINT := Color(0.59, 0.53, 0.39)  # subtle warm brick tone under trees
## Supplied Grass Textures pack: 009 rough, 002 first cut, 001 fringe/tees;
## 005 supplies leaf litter under trees. See tools/import_woodland_ground.py.
const ROUGH_VARIANT_DIR := "res://assets/textures/tiles/woodland_ground/"
## 009 alone read as bare sand/dirt once tiled across the whole rough at its
## natural (pale) brightness -- reported by the user as "the rough texture is
## fucked up" -- but the user then asked for 009 specifically, tinted to a
## precise dark green (#032b1a) rather than swapped for a different variant.
const ROUGH_VARIANTS := ["009"]
const ROUGH_MEAN := 1.0  # preserve source color; no luminance normalization
const ROUGH_TEXTURE := ROUGH_VARIANT_DIR + "grass_009_albedo.png"
## User-specified target colour for the rough.
const ROUGH_COLOR := Color("053b24")
## Compensate for Grass009's mean albedo (0.567, 0.571, 0.540, measured
## directly from the PNG) so its base color matches ROUGH_COLOR.
const ROUGH_TINT := Color(0.03458, 0.40537, 0.26161)
const FIRST_CUT_TINT := Color(0.42, 0.53, 0.28)
## Fringe keeps the fairway texture in a slightly lighter shade.
const FRINGE_LIGHTEN := 0.06
const FRINGE_TEXTURE := ROUGH_VARIANT_DIR + "grass_001_albedo.png"
const FIRST_CUT_TEXTURE := ROUGH_VARIANT_DIR + "grass_002_albedo.png"


static func terrain_material(layout: CourseLayout) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("detail_noise", _noise_texture(0.35, 7))
	mat.set_shader_parameter("macro_noise", _noise_texture(0.05, 9))
	mat.set_shader_parameter("detail_scale", 2.2)
	mat.set_shader_parameter("detail_strength", 0.045)
	mat.set_shader_parameter("macro_strength", 0.035)
	if layout.mask_texture == null:
		layout.build_feature_mask()
	mat.set_shader_parameter("feature_mask", layout.mask_texture)
	mat.set_shader_parameter("mask_origin", layout.bounds.position)
	mat.set_shader_parameter("mask_size", Vector2(layout.mask_image.get_width(), layout.mask_image.get_height()) * CourseLayout.MASK_CELL)
	if layout.sdf_texture == null and layout.has_cache():
		layout._build_sdf_texture()
	mat.set_shader_parameter("turf_sdf", layout.sdf_texture)
	mat.set_shader_parameter("sdf_size", layout.sdf_texture_size())
	mat.set_shader_parameter("green_color_a", COL_GREEN_A)
	mat.set_shader_parameter("green_color_b", COL_GREEN_B)
	mat.set_shader_parameter("stripe_width", STRIPE_WIDTH)
	mat.set_shader_parameter("fringe_color", COL_FIRST_CUT)
	mat.set_shader_parameter("sand_color", COL_BUNKER)
	mat.set_shader_parameter("sand_color2", Color(0.79, 0.80, 0.77))
	mat.set_shader_parameter("sand_grain_normal", _noise_texture(0.12, 11, true, 2.0))
	mat.set_shader_parameter("waterbed_color", COL_WATERBED)
	mat.set_shader_parameter("first_cut_width", CourseLayout.FIRST_CUT_WIDTH)
	mat.set_shader_parameter("fringe_width", CourseLayout.FRINGE_WIDTH)
	for water: WaterHazard in layout.water_hazards:
		if water.hazard_name == "White Pond":
			var bank_bounds := water.bounds.merge(layout.greens[10].bounds).grow(3.0)
			mat.set_shader_parameter("greenside_bank_enabled", true)
			mat.set_shader_parameter("greenside_bank_rect", Vector4(bank_bounds.position.x,bank_bounds.position.y,bank_bounds.end.x,bank_bounds.end.y))
	var rough_albedo_arr := _build_rough_array("albedo")
	if rough_albedo_arr != null:
		mat.set_shader_parameter("rough_texture_array", rough_albedo_arr)
		mat.set_shader_parameter("rough_normal_array", _build_rough_array("normal"))
		mat.set_shader_parameter("rough_roughness_array", _build_rough_array("roughness"))
		mat.set_shader_parameter("rough_ao_array", _build_rough_array("ao"))
		mat.set_shader_parameter("rough_layer_count", ROUGH_VARIANTS.size())
		mat.set_shader_parameter("rough_mean", ROUGH_MEAN)
		mat.set_shader_parameter("rough_scale", 1.0)
		mat.set_shader_parameter("rough_tint", ROUGH_TINT)
		mat.set_shader_parameter("rough_variant_noise", _noise_texture(0.025, 13))
	mat.set_shader_parameter("fringe_texture", load(FRINGE_TEXTURE))
	mat.set_shader_parameter("first_cut_texture", load(FIRST_CUT_TEXTURE))
	mat.set_shader_parameter("first_cut_tint", FIRST_CUT_TINT)
	mat.set_shader_parameter("fringe_turf_color", COL_FAIRWAY_B.lightened(FRINGE_LIGHTEN))
	if ResourceLoader.exists("res://assets/textures/tiles/green_tile.png"):
		var green_texture: Texture2D = load("res://assets/textures/tiles/green_tile.png")
		mat.set_shader_parameter("green_texture", green_texture)
		# Match the green's average in linear light without changing its texture.
		var green_image := green_texture.get_image()
		if green_image.is_compressed():
			green_image.decompress()
		var average := Vector3.ZERO
		var count := 0
		for y in range(0, green_image.get_height(), maxi(1, green_image.get_height() / 64)):
			for x in range(0, green_image.get_width(), maxi(1, green_image.get_width() / 64)):
				var color := green_image.get_pixel(x, y).srgb_to_linear()
				average += Vector3(color.r, color.g, color.b)
				count += 1
		mat.set_shader_parameter("green_texture_average", average / count)
		mat.set_shader_parameter("green_mean", 0.72)
	if ResourceLoader.exists(TURF_TEXTURE):
		mat.set_shader_parameter("turf_texture", load(TURF_TEXTURE))
		mat.set_shader_parameter("turf_scale", 0.2)
		# The photo grass patch reads true-to-life at roughly 1 tile per metre; the old
		# 0.2 (a 5 m tile) blew every blade up ~5x, which is what "too big and pixelated"
		# was describing -- this is the fix, not a resolution/file-size change.
		mat.set_shader_parameter("fairway_scale", 1.0)
		mat.set_shader_parameter("turf_strength", 0.42)
		mat.set_shader_parameter("turf_mean", TURF_MEAN)
		if ResourceLoader.exists(TURF_NORMAL):
			mat.set_shader_parameter("turf_normal", load(TURF_NORMAL))
		if ResourceLoader.exists(TURF_ROUGHNESS):
			mat.set_shader_parameter("turf_roughness", load(TURF_ROUGHNESS))
		if ResourceLoader.exists(TURF_AO):
			mat.set_shader_parameter("turf_ao", load(TURF_AO))
	else:
		mat.set_shader_parameter("turf_strength", 0.0)
	if ResourceLoader.exists(SAND_TEXTURE):
		mat.set_shader_parameter("sand_texture", load(SAND_TEXTURE))
		mat.set_shader_parameter("sand_mean", SAND_MEAN)
	# pine-straw beds under the tree lines (ForestPlanter paints the mask later)
	layout.ensure_straw()
	mat.set_shader_parameter("straw_mask", layout.straw_texture)
	mat.set_shader_parameter("straw_size", layout.straw_texture_size())
	if ResourceLoader.exists(STRAW_TEXTURE):
		mat.set_shader_parameter("straw_texture", load(STRAW_TEXTURE))
		mat.set_shader_parameter("straw_mean", STRAW_MEAN)
		mat.set_shader_parameter("straw_scale", 0.8)
		mat.set_shader_parameter("straw_color", STRAW_TINT)
	return mat


static func resolution_for(_layout: CourseLayout) -> float:
	return RESOLUTION


## Whole terrain: a Node3D holding one MeshInstance3D (+ collider) per 64 m tile.
static func build_terrain(layout: CourseLayout) -> Node3D:
	layout.rendered_terrain.tiles.clear()
	var res := resolution_for(layout)
	layout.rendered_terrain.origin = layout.bounds.position
	if not layout.has_cache() or layout.cache_cell != res:
		layout.build_cache(res)
	var root := Node3D.new()
	root.name = "Terrain"
	var mat := terrain_material(layout)
	root.set_meta("material", mat)
	var tiles_x := int(ceil(layout.bounds.size.x / TILE))
	var tiles_z := int(ceil(layout.bounds.size.y / TILE))
	for tz in range(tiles_z):
		for tx in range(tiles_x):
			var tile := build_tile(layout, tx, tz, mat)
			if tile != null:
				root.add_child(tile)
	return root


static func _tile_name(tx: int, tz: int) -> String:
	return "Tile_%d_%d" % [tx, tz]


## Bunkers dip up to ~1m within a couple of metres of their edge, including a raised lip
## right at the rim (see bunker.gd's depth_offset) -- steeper than the whole-course lie
## cache's 2m grid can represent. A coarse mesh there can sit visibly above or below the
## exact analytic surface the ball actually uses, reading as the ball sinking through the
## sand or floating over the lip. Tiles near a bunker/hazard are rebuilt from the exact
## analytic height/surface at a finer resolution instead of the cache.
const FINE_RESOLUTION := 1.0
const FINE_MARGIN := 4.0


static func _needs_fine_mesh(layout: CourseLayout, rect: Rect2) -> bool:
	var grown := rect.grow(FINE_MARGIN)
	for b in layout.bunkers:
		if b.bounds.intersects(grown):
			return true
	for hz in layout.water_hazards:
		if hz.bounds.intersects(grown):
			return true
	# Greens need the same treatment as bunkers/hazards: the cup and flagstick are placed
	# at the exact analytic height (course.gd's _add_flag), but a coarse cached tile can sit
	# visibly above or below that exact surface on the green's curvature, reading as a
	# floating flagstick / a cup that isn't actually sunk into the ground.
	for g in layout.greens:
		if g.bounds.intersects(grown):
			return true
	return false


## One tile of cells [tx*cpt, (tx+1)*cpt] inclusive so neighbours share an edge.
static func build_tile(layout: CourseLayout, tx: int, tz: int, mat: Material) -> MeshInstance3D:
	var b := layout.bounds
	var tile_rect := Rect2(b.position.x + tx * TILE, b.position.y + tz * TILE, TILE, TILE)
	var tile: MeshInstance3D
	if _needs_fine_mesh(layout, tile_rect):
		tile = _build_tile_fine(layout, tx, tz, mat, tile_rect)
	else:
		tile = _build_tile_cached(layout, tx, tz, mat)
	if tile != null:
		for hole in layout.holes:
			var cup := Vector2(hole.cup.x, hole.cup.z)
			if tile_rect.grow(GolfBall.CUP_RADIUS).has_point(cup):
				tile.mesh = TerrainCupCutout.cut(tile.mesh, cup, GolfBall.CUP_RADIUS)
		TurfShells.add_to_tile(tile, mat)
	return tile


static func _build_tile_cached(layout: CourseLayout, tx: int, tz: int, mat: Material) -> MeshInstance3D:
	var res := layout.cache_cell
	var cpt := maxi(int(TILE / res), 1)
	var nx := layout.cache_nx
	var nz := layout.cache_nz
	var x0 := tx * cpt
	var z0 := tz * cpt
	var x1 := mini(x0 + cpt, nx - 1)
	var z1 := mini(z0 + cpt, nz - 1)
	if x1 <= x0 or z1 <= z0:
		return null
	var b := layout.bounds
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := x1 - x0 + 1
	var tile_heights := PackedFloat32Array()
	tile_heights.resize(w * (z1 - z0 + 1))
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			tile_heights[(iz - z0) * w + ix - x0] = layout.cache_height[iz * nx + ix]
	layout.rendered_terrain.register_tile(Vector2i(tx, tz), b.position + Vector2(x0, z0) * res, res, w, z1 - z0 + 1, tile_heights)
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var i := iz * nx + ix
			var x := b.position.x + ix * res
			var z := b.position.y + iz * res
			var s := layout.cache_surface[i]
			var col := _color_for(layout, x, z, s, layout.cache_along[i])
			# alpha = rough weight so the shader can swap in the rough texture
			var turf_d := layout.cache_turf[i] if layout.cache_tree_island[i] >= 0.0 else 1.0e9
			col.a = clampf((turf_d - CourseLayout.FIRST_CUT_WIDTH) / 4.0, 0.0, 1.0) if s == PhysicsEnums.SurfaceType.ROUGH else 0.0
			var hl := layout.cache_height[iz * nx + maxi(ix - 1, 0)]
			var hr := layout.cache_height[iz * nx + mini(ix + 1, nx - 1)]
			var hd := layout.cache_height[maxi(iz - 1, 0) * nx + ix]
			var hu := layout.cache_height[mini(iz + 1, nz - 1) * nx + ix]
			st.set_normal(Vector3(hl - hr, 2.0 * res, hd - hu).normalized())
			st.set_color(col.srgb_to_linear())
			st.set_uv(Vector2(layout.cache_along[i], 0.0))  # terrain shader: mowing stripes
			st.add_vertex(Vector3(x, layout.cache_height[i], z))
	for iz in range(z1 - z0):
		for ix in range(x1 - x0):
			var i0 := iz * w + ix
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			# Godot front faces are clockwise when seen from the +Y side
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	var mi := MeshInstance3D.new()
	mi.name = _tile_name(tx, tz)
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# GolfBall uses analytic terrain height/normal; its obstacle rays query layer 2.
	# A full concave collider here duplicated unused geometry on collision layer 1.
	return mi


## Same as _build_tile_cached but samples the exact analytic height/surface (via
## CourseLayout._cache_sample, the same function that builds the cache in the first place)
## at FINE_RESOLUTION instead of reading the coarse whole-course cache -- for tiles near a
## bunker/hazard whose depth profile the cache's 2m grid can't represent accurately.
static func _build_tile_fine(layout: CourseLayout, tx: int, tz: int, mat: Material, tile_rect: Rect2) -> MeshInstance3D:
	var res := FINE_RESOLUTION
	var n := int(round(TILE / res)) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var surfaces := PackedByteArray()
	surfaces.resize(n * n)
	var alongs := PackedFloat32Array()
	alongs.resize(n * n)
	for iz in range(n):
		var z := tile_rect.position.y + iz * res
		for ix in range(n):
			var x := tile_rect.position.x + ix * res
			var smp := layout._cache_sample(Vector2(x, z))
			var idx := iz * n + ix
			surfaces[idx] = smp[0]
			heights[idx] = smp[1]
			alongs[idx] = smp[2]
	for iz in range(n):
		var z := tile_rect.position.y + iz * res
		for ix in range(n):
			var x := tile_rect.position.x + ix * res
			var idx := iz * n + ix
			var s: int = surfaces[idx]
			var col := _color_for(layout, x, z, s, alongs[idx])
			var turf_d := layout.cached_turf(Vector2(x, z)) if layout.cached_tree_island(Vector2(x, z)) >= 0.0 else 1.0e9
			col.a = clampf((turf_d - CourseLayout.FIRST_CUT_WIDTH) / 4.0, 0.0, 1.0) if s == PhysicsEnums.SurfaceType.ROUGH else 0.0
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			st.set_normal(Vector3(hl - hr, 2.0 * res, hd - hu).normalized())
			st.set_color(col.srgb_to_linear())
			st.set_uv(Vector2(alongs[idx], 0.0))  # terrain shader: mowing stripes
			st.add_vertex(Vector3(x, heights[idx], z))
	for iz in range(n - 1):
		for ix in range(n - 1):
			var i0 := iz * n + ix
			var i1 := i0 + 1
			var i2 := i0 + n
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	layout.rendered_terrain.register_tile(Vector2i(tx, tz), tile_rect.position, res, n, n, heights)
	var mi := MeshInstance3D.new()
	mi.name = _tile_name(tx, tz)
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Rebuild every tile that intersects `rect` (world XZ). Call after the cache was updated.
static func rebuild_tiles(layout: CourseLayout, root: Node3D, rect: Rect2) -> void:
	layout.rendered_terrain.origin = layout.bounds.position
	var mat: Material = root.get_meta("material")
	var b := layout.bounds
	var tx0 := maxi(int(floor((rect.position.x - b.position.x) / TILE)), 0)
	var tz0 := maxi(int(floor((rect.position.y - b.position.y) / TILE)), 0)
	var tx1 := int(floor((rect.end.x - b.position.x) / TILE))
	var tz1 := int(floor((rect.end.y - b.position.y) / TILE))
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			var old := root.get_node_or_null(_tile_name(tx, tz))
			if old != null:
				old.name = "old"
				old.queue_free()
			var tile := build_tile(layout, tx, tz, mat)
			if tile != null:
				root.add_child(tile)


## Builds one Texture2DArray layer per ROUGH_VARIANTS entry for the given map
## suffix (albedo/normal/roughness/ao). Returns null if any file is missing so
## the caller can skip the whole array uniform rather than bind a partial one.
static var _rough_array_cache: Dictionary = {}


static func _build_rough_array(map_suffix: String) -> Texture2DArray:
	if _rough_array_cache.has(map_suffix):
		return _rough_array_cache[map_suffix]
	var images: Array[Image] = []
	for v in ROUGH_VARIANTS:
		var path := "%sgrass_%s_%s.png" % [ROUGH_VARIANT_DIR, v, map_suffix]
		if not ResourceLoader.exists(path):
			return null
		var tex: Texture2D = load(path)
		if tex == null:
			return null
		var image := tex.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		if not image.has_mipmaps():
			image.generate_mipmaps()
		images.append(image)
	var arr := Texture2DArray.new()
	if arr.create_from_images(images) != OK:
		return null
	_rough_array_cache[map_suffix] = arr
	return arr


static func _noise_texture(frequency: float, seed_v: int, as_normal: bool = false, bump: float = 8.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = bump
	return tex


static func _color_for(layout: CourseLayout, x: float, z: float, s: int, along: float) -> Color:
	var xz := Vector2(x, z)
	match s:
		CourseLayout.SURFACE_TREE_PATCH:
			# Tree islands are plain rough under their trees (no first cut).
			var tn := (layout.detail_noise.get_noise_2d(x * 0.5, z * 0.5) + 1.0) * 0.5
			return COL_ROUGH.lerp(COL_ROUGH_DRY, tn)
		PhysicsEnums.SurfaceType.FAIRWAY:
			var stripe := int(floor(along / STRIPE_WIDTH)) % 2 == 0
			return COL_FAIRWAY_A if stripe else COL_FAIRWAY_B
		CourseLayout.SURFACE_FIRST_CUT:
			return COL_FIRST_CUT
		CourseLayout.SURFACE_FRINGE:
			return COL_FAIRWAY_A
		PhysicsEnums.SurfaceType.FIRM:
			return COL_PATH
		CourseLayout.SURFACE_TEE:
			var stripe := int(floor(x / 1.5)) % 2 == 0
			return COL_TEE_A if stripe else COL_TEE_B
		CourseLayout.SURFACE_BUNKER, CourseLayout.SURFACE_WATER, PhysicsEnums.SurfaceType.GREEN:
			# painted by the feature mask; the vertex tint is whatever turf surrounds it
			var turf := layout.cached_turf(xz)
			if s == PhysicsEnums.SurfaceType.GREEN or turf <= 0.01:
				return COL_FAIRWAY_B
			return COL_FIRST_CUT.lerp(COL_ROUGH, smoothstep(CourseLayout.FIRST_CUT_WIDTH, CourseLayout.FIRST_CUT_WIDTH + 4.0, turf))
		_:
			var t := (layout.detail_noise.get_noise_2d(x * 0.5, z * 0.5) + 1.0) * 0.5
			var edge := 1.0 if layout.cached_tree_island(xz) < 0.0 else smoothstep(CourseLayout.FIRST_CUT_WIDTH, CourseLayout.FIRST_CUT_WIDTH + 4.0, layout.cached_turf(xz))
			var rough := COL_ROUGH.lerp(COL_ROUGH_DRY, t)
			return COL_FIRST_CUT.lerp(rough, edge)


# ---- water --------------------------------------------------------------------

static var _water_material: ShaderMaterial = null


## Scrolling normal-map water (user-supplied shader). UVs are world metres / WATER_UV_DIV.
static func water_material() -> ShaderMaterial:
	if _water_material != null:
		return _water_material
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water_simple.gdshader")
	mat.set_shader_parameter("normal_map", _noise_texture(0.12, 21, true, 6.0))
	mat.set_shader_parameter("color", Color(0.10, 0.17, 0.14, 1.0))
	mat.set_shader_parameter("rapid", 0.008)
	_water_material = mat
	return mat
