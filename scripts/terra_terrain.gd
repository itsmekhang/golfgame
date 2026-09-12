class_name TerraTerrain
extends RefCounted
## Renders the course with the TerraBrush GDExtension (addons/terrabrush, MIT): a clipmap
## terrain with LOD, per-texture normal maps, height-blended splatting and anti-tiling.
## The course layout stays the source of truth (ball physics, lies); this only feeds
## TerraBrush a heightmap, splat maps and a colour map built from the layout cache.
##
## TerraBrush semantics (measured): a zone is always `zonesSize` metres wide, zone (i, j) is
## centred at (i, j) * zonesSize from the node, and `resolution` is metres per pixel, so a
## zone image is zonesSize / resolution pixels. Texture sets: 0 = fairway turf, 1 = rough,
## 2 = sand, 3 = putting green.

const ZONE_SIZE := 512  # metres per zone (9 zones over the course)
static var ZONE_SIZE_OVERRIDE := 0  # debug
static var RESOLUTION := 2  # metres per pixel -> 256 px zone images (512 px images crash the extension)
# TerraBrush's native extension crashed intermittently (dig_test) when the turf
# texture set pointed at the new fairway_pbr_* images (regardless of which fields
# were set) -- keep it on the original, known-stable pair here. The new full-PBR
# set is used by the tile fallback (terrain_builder.gd / terrain.gdshader) instead.
const TEX_TURF := "res://assets/textures/tiles/fairway_tile.png"
const TEX_TURF_N := "res://assets/textures/tiles/fairway_tile_normal.png"
const TEX_ROUGH := "res://assets/textures/tiles/rough_tile.png"
const TEX_SAND := "res://assets/textures/tiles/sand_tile.png"
const TEX_SAND_N := "res://assets/textures/tiles/sand_tile_normal.png"
const TEX_GREEN := "res://assets/textures/tiles/green_tile.png"

static var last_report := ""


static func available() -> bool:
	return ClassDB.class_exists("TerraBrush") and ResourceLoader.exists(TEX_TURF)


## Build the TerraBrush node for `layout`. Add it to the tree only after the main loop has
## started (the extension crashes if it enters the tree during SceneTree init).
static func build(layout: CourseLayout) -> Node3D:
	if not available():
		return null
	var t0 := Time.get_ticks_msec()
	var sets: Resource = ClassDB.instantiate("TextureSetsResource")
	# roughness/height slots on TextureSetResource are left unused: TerraBrush's native
	# extension crashed intermittently when they were wired in (dig_test), so the tile
	# fallback (terrain.gdshader) is the one with full PBR normal+roughness+AO.
	sets.textureSets = [_texture_set("turf", TEX_TURF, TEX_TURF_N), _texture_set("rough", TEX_ROUGH, TEX_TURF_N), _texture_set("sand", TEX_SAND, TEX_SAND_N), _texture_set("green", TEX_GREEN, TEX_TURF_N)]

	var b := layout.bounds
	var centre := b.get_center()
	var zsize := ZONE_SIZE_OVERRIDE if ZONE_SIZE_OVERRIDE > 0 else ZONE_SIZE
	if OS.get_environment("TB_ZONE") != "":
		zsize = int(OS.get_environment("TB_ZONE"))
	if OS.get_environment("TB_RES") != "":
		RESOLUTION = int(OS.get_environment("TB_RES"))
	var zone_m := float(zsize)
	var px_n := int(zsize / RESOLUTION)
	# node sits at the bounds centre; zone (i, j) covers [centre + (i - 0.5) * zone_m, ...]
	var zx0 := int(floor((b.position.x - centre.x) / zone_m + 0.5))
	var zx1 := int(floor((b.end.x - centre.x) / zone_m + 0.5))
	var zz0 := int(floor((b.position.y - centre.y) / zone_m + 0.5))
	var zz1 := int(floor((b.end.y - centre.y) / zone_m + 0.5))

	var zones: Resource = ClassDB.instantiate("ZonesResource")
	var zone_list: Array = []
	var px_total := 0
	for zj in range(zz0, zz1 + 1):
		for zi in range(zx0, zx1 + 1):
			zone_list.append(_build_zone(layout, zi, zj, centre, zone_m, px_n))
			px_total += px_n * px_n
	zones.zones = zone_list

	var tb: Node3D = ClassDB.instantiate("TerraBrush")
	tb.name = "TerraBrushTerrain"
	tb.zonesSize = zsize
	tb.resolution = RESOLUTION
	tb.dataPath = "user://terrabrush_zones"
	tb.textureSets = sets
	tb.terrainZones = zones
	tb.collisionOnly = false
	tb.createCollisionInThread = OS.get_environment("TB_THREAD") == "1"
	tb.objectLoadingStrategy = 3  # NotThreaded
	tb.collisionLayers = 1
	tb.useAntiTile = true
	tb.heightBlendFactor = 10.0
	# clipmap LOD: cells must not be finer than the heightmap pixels
	tb.lodInitialCellWidth = float(RESOLUTION)
	tb.position = Vector3(centre.x, 0.0, centre.y)
	last_report = "%d zones, %d px, %d ms" % [zone_list.size(), px_total, Time.get_ticks_msec() - t0]
	return tb


static func _texture_set(name: String, albedo: String, normal: String, roughness: String = "", height: String = "") -> Resource:
	var ts: Resource = ClassDB.instantiate("TextureSetResource")
	ts.name = name
	ts.albedoTexture = load(albedo)
	if normal != "" and ResourceLoader.exists(normal):
		ts.normalTexture = load(normal)
	if roughness != "" and ResourceLoader.exists(roughness):
		ts.roughnessTexture = load(roughness)
	if height != "" and ResourceLoader.exists(height):
		ts.heightTexture = load(height)
	return ts


## One zone: heightmap (RF), splat (RGBA8: turf, rough, sand, unused) and colour tint.
static func _build_zone(layout: CourseLayout, zi: int, zj: int, centre: Vector2, zone_m: float, n: int) -> Resource:
	var zone: Resource = ClassDB.instantiate("ZoneResource")
	zone.zonePosition = Vector2i(zi, zj)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var splat := PackedByteArray()
	splat.resize(n * n * 4)
	var color := PackedByteArray()
	color.resize(n * n * 4)
	var origin_x := centre.x + (zi - 0.5) * zone_m
	var origin_z := centre.y + (zj - 0.5) * zone_m
	var mask := layout.mask_image
	var b := layout.bounds
	var mw := mask.get_width() if mask != null else 0
	var mh := mask.get_height() if mask != null else 0
	var fill_h := layout.cached_height(clampf(origin_x, b.position.x, b.end.x), clampf(origin_z, b.position.y, b.end.y))
	for py in range(n):
		var wz := origin_z + py * RESOLUTION
		var inside_z := wz >= b.position.y and wz <= b.end.y
		for px in range(n):
			var wx := origin_x + px * RESOLUTION
			var i := py * n + px
			if not inside_z or wx < b.position.x or wx > b.end.x:
				heights[i] = fill_h
				splat[i * 4] = 0
				splat[i * 4 + 1] = 255
				splat[i * 4 + 2] = 0
				splat[i * 4 + 3] = 0
				color[i * 4] = 255
				color[i * 4 + 1] = 255
				color[i * 4 + 2] = 255
				color[i * 4 + 3] = 0
				continue
			heights[i] = layout.cached_height(wx, wz)
			var xz := Vector2(wx, wz)
			var s := layout.cached_surface(xz)
			# Signed distances: sand/green/tee/water from the 1 m mask, turf from the
			# 2 m cache (bilinear). Coverage ramps span two splat pixels so the GPU's
			# linear filtering reconstructs the outline between pixels (no staircase).
			var soft := float(RESOLUTION) * 2.0
			var sd_sand := 1.0e9
			var sd_green := 1.0e9
			var sd_water := 1.0e9
			var sd_tee := 1.0e9
			if mask != null:
				var mx := clampi(int(round((wx - b.position.x) / CourseLayout.MASK_CELL)), 0, mw - 1)
				var mz := clampi(int(round((wz - b.position.y) / CourseLayout.MASK_CELL)), 0, mh - 1)
				var mc := mask.get_pixel(mx, mz)
				sd_sand = (0.5 - mc.r) * CourseLayout.SDF_RANGE * 2.0
				sd_green = (0.5 - mc.g) * CourseLayout.SDF_RANGE * 2.0
				sd_tee = (0.5 - mc.b) * CourseLayout.SDF_RANGE * 2.0
				sd_water = (0.5 - mc.a) * CourseLayout.SDF_RANGE * 2.0
			var sdf := layout.cached_sdf(wx, wz)
			var sd_turf := minf(sdf.x, sd_tee)
			sd_green = minf(sd_green, sdf.y)
			var sand := _cov(sd_sand, soft)
			var green := _cov(sd_green, soft)
			var fringe := _cov(sd_green - CourseLayout.FRINGE_WIDTH, soft) * (1.0 - green)
			var water := _cov(sd_water, soft)
			var turf_w := _cov(sd_turf, soft)
			var first_cut := _cov(sd_turf - CourseLayout.FIRST_CUT_WIDTH, soft) * (1.0 - turf_w)
			turf_w = maxf(turf_w + first_cut * 0.5, maxf(green, fringe))
			var rough_w := 1.0 - turf_w
			var sand_w := maxf(sand, water * 0.8)
			var green_w := green * (1.0 - sand_w)
			turf_w *= 1.0 - sand_w
			rough_w *= 1.0 - sand_w
			turf_w *= 1.0 - green_w
			splat[i * 4] = int(turf_w * 255.0)
			splat[i * 4 + 1] = int(rough_w * 255.0)
			splat[i * 4 + 2] = int(sand_w * 255.0)
			splat[i * 4 + 3] = int(green_w * 255.0)
			# colour tint: mowing stripes on the fairway, checker on greens, darker water bed
			# Colour image is blended over the textures by its alpha: use real turf greens.
			var tint := Color(1, 1, 1, 0)
			if green > 0.01:
				# putting green: much lighter lime with a 2 m checker
				var checker := int(floor(wx / TerrainBuilder.GREEN_CHECK) + floor(wz / TerrainBuilder.GREEN_CHECK)) % 2 == 0
				var g_tint := Color(0.78, 1.0, 0.55) if checker else Color(0.62, 0.88, 0.42)
				tint = Color(g_tint.r, g_tint.g, g_tint.b, 0.3 * green)
			elif fringe > 0.01:
				tint = Color(0.50, 0.80, 0.32, 0.6 * fringe)
			elif s == PhysicsEnums.SurfaceType.FAIRWAY or s == CourseLayout.SURFACE_TEE:
				var stripe := int(floor(layout.cached_along(xz) / TerrainBuilder.STRIPE_WIDTH)) % 2 == 0
				tint = Color(0.48, 0.78, 0.30, 0.5) if stripe else Color(0.38, 0.66, 0.24, 0.5)
			elif s == CourseLayout.SURFACE_FIRST_CUT:
				tint = Color(0.33, 0.58, 0.20, 0.5 * first_cut)
			if water > 0.01:
				tint = Color(0.35, 0.4, 0.3, 0.8 * water)
			# the colour map is read as linear data: convert the sRGB tint
			var lin := Color(tint.r, tint.g, tint.b, 1.0).srgb_to_linear()
			color[i * 4] = int(lin.r * 255.0)
			color[i * 4 + 1] = int(lin.g * 255.0)
			color[i * 4 + 2] = int(lin.b * 255.0)
			color[i * 4 + 3] = int(tint.a * 255.0)
	zone.heightMapImage = Image.create_from_data(n, n, false, Image.FORMAT_RF, heights.to_byte_array())
	zone.splatmapsImage = [Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, splat)]
	zone.colorImage = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, color)
	return zone


static func _cov(sd: float, soft: float) -> float:
	return clampf(0.5 - sd / soft, 0.0, 1.0)
