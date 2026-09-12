class_name TerrainBuilder
extends RefCounted
## Builds the terrain as 64 m tiles (vertex-coloured by lie surface) from the layout's
## sample cache, plus water meshes. Tiles can be rebuilt individually after a dig.

const RESOLUTION := 2.0  # metres per vertex (procedural / designed)
const TILE := 64.0
const WATER_UV_DIV := 8.0  # world metres per water UV unit

# Palette from the reference photos: bright striped fairway, checkered green,
# a slightly darker first cut, and a deep blue-green rough under the blades.
const COL_FAIRWAY_A := Color(0.44, 0.70, 0.24)
const COL_FAIRWAY_B := Color(0.35, 0.60, 0.20)
const COL_GREEN_A := Color(0.50, 0.78, 0.30)
const COL_GREEN_B := Color(0.43, 0.71, 0.27)
const COL_FIRST_CUT := Color(0.30, 0.53, 0.18)
const COL_ROUGH := Color(0.20, 0.40, 0.12)
const COL_ROUGH_DRY := Color(0.27, 0.42, 0.13)
const COL_BUNKER := Color(0.90, 0.83, 0.62)
const COL_TEE_A := Color(0.42, 0.68, 0.24)
const COL_TEE_B := Color(0.36, 0.61, 0.21)
const COL_WATERBED := Color(0.30, 0.36, 0.26)
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
const STRAW_TEXTURE := "res://assets/textures/tiles/pine_straw_tile.png"  # tools/make_pine_straw.py
const STRAW_MEAN := 0.356


static func terrain_material(layout: CourseLayout) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("detail_noise", _noise_texture(0.35, 7))
	mat.set_shader_parameter("macro_noise", _noise_texture(0.05, 9))
	mat.set_shader_parameter("detail_scale", 2.2)
	mat.set_shader_parameter("detail_strength", 0.10)
	mat.set_shader_parameter("macro_strength", 0.07)
	if layout.mask_texture == null:
		layout.build_feature_mask()
	mat.set_shader_parameter("feature_mask", layout.mask_texture)
	mat.set_shader_parameter("mask_origin", layout.bounds.position)
	mat.set_shader_parameter("mask_size", Vector2(layout.mask_image.get_width(), layout.mask_image.get_height()) * CourseLayout.MASK_CELL)
	if layout.sdf_texture == null and layout.has_cache():
		layout._build_sdf_texture()
	mat.set_shader_parameter("turf_sdf", layout.sdf_texture)
	mat.set_shader_parameter("sdf_size", layout.sdf_texture_size())
	mat.set_shader_parameter("first_cut_width", CourseLayout.FIRST_CUT_WIDTH)
	mat.set_shader_parameter("fringe_width", CourseLayout.FRINGE_WIDTH)
	if ResourceLoader.exists("res://assets/textures/tiles/rough_tile.png"):
		mat.set_shader_parameter("rough_texture", load("res://assets/textures/tiles/rough_tile.png"))
		mat.set_shader_parameter("rough_mean", 0.2)
	if ResourceLoader.exists("res://assets/textures/tiles/green_tile.png"):
		mat.set_shader_parameter("green_texture", load("res://assets/textures/tiles/green_tile.png"))
		mat.set_shader_parameter("green_mean", 0.72)
	if ResourceLoader.exists(TURF_TEXTURE):
		mat.set_shader_parameter("turf_texture", load(TURF_TEXTURE))
		mat.set_shader_parameter("turf_scale", 0.2)
		# The photo grass patch reads true-to-life at roughly 1 tile per metre; the old
		# 0.2 (a 5 m tile) blew every blade up ~5x, which is what "too big and pixelated"
		# was describing -- this is the fix, not a resolution/file-size change.
		mat.set_shader_parameter("fairway_scale", 1.0)
		mat.set_shader_parameter("turf_strength", 0.8)
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
		mat.set_shader_parameter("straw_scale", 0.5)
	return mat


static func resolution_for(_layout: CourseLayout) -> float:
	return RESOLUTION


## Whole terrain: a Node3D holding one MeshInstance3D (+ collider) per 64 m tile.
static func build_terrain(layout: CourseLayout) -> Node3D:
	var res := resolution_for(layout)
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
	if _needs_fine_mesh(layout, tile_rect):
		return _build_tile_fine(layout, tx, tz, mat, tile_rect)
	return _build_tile_cached(layout, tx, tz, mat)


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
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var i := iz * nx + ix
			var x := b.position.x + ix * res
			var z := b.position.y + iz * res
			var s := layout.cache_surface[i]
			var col := _color_for(layout, x, z, s, layout.cache_along[i])
			# alpha = rough weight so the shader can swap in the rough texture
			var turf_d := layout.cache_turf[i]
			col.a = clampf((turf_d - CourseLayout.FIRST_CUT_WIDTH) / 4.0, 0.0, 1.0) if s == PhysicsEnums.SurfaceType.ROUGH else 0.0
			var hl := layout.cache_height[iz * nx + maxi(ix - 1, 0)]
			var hr := layout.cache_height[iz * nx + mini(ix + 1, nx - 1)]
			var hd := layout.cache_height[maxi(iz - 1, 0) * nx + ix]
			var hu := layout.cache_height[mini(iz + 1, nz - 1) * nx + ix]
			st.set_normal(Vector3(hl - hr, 2.0 * res, hd - hu).normalized())
			st.set_color(col.srgb_to_linear())
			st.set_uv(Vector2(x, z) * 0.05)
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
			var turf_d := layout.cached_turf(Vector2(x, z))
			col.a = clampf((turf_d - CourseLayout.FIRST_CUT_WIDTH) / 4.0, 0.0, 1.0) if s == PhysicsEnums.SurfaceType.ROUGH else 0.0
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			st.set_normal(Vector3(hl - hr, 2.0 * res, hd - hu).normalized())
			st.set_color(col.srgb_to_linear())
			st.set_uv(Vector2(x, z) * 0.05)
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
	var mi := MeshInstance3D.new()
	mi.name = _tile_name(tx, tz)
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Rebuild every tile that intersects `rect` (world XZ). Call after the cache was updated.
static func rebuild_tiles(layout: CourseLayout, root: Node3D, rect: Rect2) -> void:
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
			var edge := smoothstep(CourseLayout.FIRST_CUT_WIDTH, CourseLayout.FIRST_CUT_WIDTH + 4.0, layout.cached_turf(xz))
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
	mat.set_shader_parameter("color", Color(0.16, 0.40, 0.58, 1.0))
	mat.set_shader_parameter("rapid", 0.02)
	mat.set_shader_parameter("transparency", 0.72)
	_water_material = mat
	return mat
