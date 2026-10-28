class_name ForestPlanter
extends Node3D
## Plants the course's woodland from the traced paintings: dense tree groups inside
## every hole's `woods` footprints, a continuous forest wherever the paintings do not
## reach (between corridors, past the course edges), flowering dogwood / azalea along
## the woodland edges, and nothing on turf, sand or water.
##
## Rendering is all instanced: one MultiMesh tile per species/LOD (VegetationBatches),
## Detailed near trees, lighter 3D crowns to 260 m, then baked cards. Shadows cover
## the near tiers. The map has its own inexpensive crown silhouettes. Collision is
## separate PhysicsServer bodies for solid trunks and permeable crowns (no
## nodes), on PropScatter.OBSTACLE_LAYER so the ball can hit them.

const FOLIAGE_LAYER := 4  # queried by GolfBall as a soft, permeable crown

const TREE_SPACING := 7.5  # metres between trees inside a wood (jittered grid)
const FILL_SPACING := 9.0  # metres between trees in the fill forest off the paintings
const FILL_TURF_CLEARANCE := 6.0  # fill forest keeps this far from any mown turf
const WOODS_TURF_CLEARANCE := 4.0  # traced tree groups keep this far from any mown turf
const CORRIDOR_MARGIN := 5.0  # rough strip beside every fairway corridor kept free of trunks
const TEE_CLEARANCE := 60.0  # no trees this close to a back tee (crowns are 10-17 m wide)
const CARRY_LANE_HALF := 18.0  # half width of the tree-free lane along a rough carry
const EDGE_BAND := 7.0  # metres inside a wood's edge that reads as its flowering fringe
const SHRUB_SPACING := 3.0  # metres between candidate bushes along a wood's edge
const EDGE_SHRUB_CHANCE := 0.32  # share of edge candidates that get a bush
const UNDERSTORY_SHRUB_CHANCE := 0.55  # bushes under the canopy, per tree planted
const SHRUB_TURF_CLEARANCE := 3.0  # bushes may sit this close to mown turf
const SHRUB_CORRIDOR_MARGIN := 4.0  # and this far outside a fairway corridor
const SHRUB_TEE_CLEARANCE := 14.0
const GREENSIDE_SHRUB_MIN := 12.0  # azalea clumps ring each green at this range
const GREENSIDE_SHRUB_MAX := 34.0
const GREENSIDE_SHRUB_TRIES := 40
const STRAW_CANOPY_FACTOR := 1.25  # straw bed radius as a multiple of the canopy radius
## Tier hand-over distances: the high-fidelity mesh (47k-238k tris, every leaf) up
## close, then a baked impostor card of the same model for the forest bulk. Where no
## impostor is baked the old low-poly LOD1/LOD2 meshes stand in.
## Baked impostor cards (tools/bake_impostors.gd) as the far tier.
const USE_IMPOSTORS := true
## Trees: the pack's medium-detail LOD2 mesh from the camera out to DENSE_AT, then the cheap
## baked impostor cards (rendered from the detailed models) out to the tree distance. No
## high-poly tier, no sparse low-poly crown (that is only a fallback for a species with no baked
## impostor). The hand-over is per tree in the shaders. Shrubs keep their own tiers.
const LOW_POLY_TREES := true
const MESH_AT := NaturePack.MESH_AT
const SHRUB_MESH_AT := NaturePack.SHRUB_MESH_AT
const LOD1_AT := 70.0
const LOD2_AT := 180.0
const SHRUB_FAR_AT := 60.0
## Batch tile sizes per LOD tier: every MultiMeshInstance3D is a draw call and a cull
## test, so far tiers use big tiles (fewer nodes) and only the near tier stays fine
## enough to cull tightly and switch LOD close to the camera.
## Near tiles are small: every LOD1 mesh in a tile within range costs its full
## 50-240k vertices even when the shader collapses it, so only tiles actually
## next to the camera may carry meshes.
const TILE_NEAR := 16.0
const TILE_MID := 24.0
const TILE_DISTANCE := 64.0
const TILE_FAR := 256.0

## Species lists are kept short on purpose: every species in a tile is another
## MultiMesh node per LOD tier. Scale jitter supplies the size variety instead.
## Only the A (small) size variant of each species -- B/C were dropped at the user's
## request to cut the number of distinct meshes/MultiMesh batches (every extra size
## variant is another species-tier pair of nodes to cull and draw). Per-instance
## scale jitter (see `place` below, 0.7-1.2x) still supplies size variety.
const PINES := ["loblolly_pine_A", "longleaf_pine_A", "eastern_white_pine_A"]
const HARDWOODS := ["white_oak_A", "red_maple_A", "sweetgum_A", "tulip_poplar_A", "southern_magnolia_A", "live_oak_A"]
const UNDERSTORY_TREES := ["eastern_red_cedar_A", "river_birch_A"]
const FRINGE_TREES := ["flowering_dogwood_white_A", "flowering_dogwood_pink_A", "crape_myrtle_A"]
const SHRUBS := ["azalea_pink_A", "azalea_white_A", "azalea_red_A", "rhododendron_A", "hydrangea_A", "boxwood_A", "boxwood_hedge_A", "wax_myrtle_A", "yaupon_holly_A"]
const WATERSIDE := ["bald_cypress_A", "weeping_willow_A", "river_birch_A", "loblolly_pine_A", "longleaf_pine_A"]
## Low woodland-floor cover (ferns/hosta) scattered densely under the canopy, distinct
## from the taller ornamental SHRUBS above -- this is what actually reads as "carpet".
const FERNS := ["bracken_fern_A", "bracken_fern_B", "sword_fern_A", "sword_fern_B", "hosta_A", "hosta_B"]
const FERN_SPACING := 2.2  # metres between candidate cells inside a wood
const FERN_FILL_CHANCE := 0.8  # share of cells (that pass clearance) that get a plant
## Real (decimated) bush meshes for the fill forest's floor cover, replacing the
## earlier billboard-card shader experiment entirely (no shader/quad-card code
## remains). Source color/opacity maps are rebuilt explicitly by
## tools/rebuild_woodland_bushes.py; Forsythia uses its separate LS12 pipeline.
## Broad button bushes form the tall border; low leaf clusters/flowers are accents.
const FOREST_BUSHES := [
	preload("res://assets/foliage_bushes/forsythia_02.glb"),
	preload("res://assets/foliage_bushes/leafcluster_01.glb"),
	preload("res://assets/foliage_bushes/buttonbush_01.glb"),
	preload("res://assets/foliage_bushes/buttonbush_02.glb"),
	preload("res://assets/foliage_bushes/forsythia_01.glb"),
]
# Forest flowers and border shrubs stay below head height, with natural size variety.
# These scales affect forest planting only; facility beds keep their own dimensions.
const FOREST_SHRUB_MAX_HEIGHT := 1.8
const FOREST_SHRUB_MAX_WIDTH := 2.8
const FOREST_BUSH_SCALE_RANGES := [
	Vector2(0.8, 1.2),
	Vector2(1.4, 2.0),  # Low leaf clusters already fit the woodland floor.
	Vector2(0.5, 0.68),
	Vector2(0.7, 0.95),
	Vector2(1.15, 1.6),
]
const BUSH_SPACING := 3.6  # metres between candidate cells (widened per user: "reduce bush spawn rate")
const BUSH_FILL_CHANCE := 0.5  # share of candidates that get a bush (lowered from 0.68)
const BUSH_DISTANCE := 160.0
## Simplified far-tier copy of each FOREST_BUSHES mesh, built once per run.
static var _bush_far_cache: Dictionary = {}

var _colliders: Array = []  # [Vector3 base, float trunk_r, float trunk_h, float canopy_r, float canopy_h]
var _rids: Array[RID] = []  # one static body (trunk + canopy shape) per tree
var tree_count := 0
var shrub_count := 0
## Every planted tree's transform, pooled by proxy kind (not species) for the far
## tier -- see NaturePack.far_proxy_mesh.
var _far_pine: Array = []
var _far_hardwood: Array = []


## Build the forest for `region` (a Rect2 in world XZ; empty = whole course).
static func build(layout: CourseLayout, rng_seed: int, region: Rect2 = Rect2()) -> ForestPlanter:
	var planter := ForestPlanter.new()
	planter.name = "Forest"
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 31 + 5
	var b := region.intersection(layout.bounds) if region.size != Vector2.ZERO else layout.bounds
	var per_mesh: Dictionary = {}  # id -> Array[Transform3D]
	# Computed once per build() call, not per tree: far_proxy_mesh() is cache-backed so
	# a repeat call is cheap, but there's no reason to pay even that per tree when the
	# reference height never changes within one build. Scaling the far proxy uniformly
	# by height ratio (not a separate factor per axis) keeps its hand-tuned canopy
	# proportions intact instead of stretching it lopsided per species.
	var far_pine_h := NaturePack.far_proxy_mesh("pine").get_aabb().size.y
	var far_hardwood_h := NaturePack.far_proxy_mesh("hardwood").get_aabb().size.y

	var place := func(id: String, xz: Vector2, is_tree: bool) -> void:
		var y := layout.height_at(xz.x, xz.y)
		var is_fern := FERNS.has(id)
		# Keep woodland shrubs compact; imported species have different native dimensions.
		# Ferns already fit the woodland floor and retain their natural variation.
		var sc: float
		if is_tree:
			sc = rng.randf_range(0.7, 1.2)
		elif is_fern:
			sc = rng.randf_range(0.65, 1.15)
		else:
			sc = rng.randf_range(0.65, 0.95)
			var dimensions := NaturePack.dims(id)
			sc = minf(sc, FOREST_SHRUB_MAX_HEIGHT / maxf(dimensions.y, 0.01))
			sc = minf(sc, FOREST_SHRUB_MAX_WIDTH / maxf(maxf(dimensions.x, dimensions.z), 0.01))
		var ang := rng.randf_range(0.0, TAU)
		if layout.in_pad(xz, 1.0):
			return  # the club's buildings stand here
		var basis := Basis(Vector3.UP, ang).scaled(Vector3(sc, sc, sc))
		var bury := 0.35 if is_tree else 0.08
		var origin := Vector3(xz.x, y - bury, xz.y)
		var xf := Transform3D(basis, origin)
		if not per_mesh.has(id):
			per_mesh[id] = []
		(per_mesh[id] as Array).append(xf)
		if is_tree:
			var d := NaturePack.dims(id) * sc
			planter._colliders.append([Vector3(xz.x, y, xz.y), 0.32 * sc, d.y * 0.4, maxf(d.x, d.z) * 0.42, d.y * 0.6])
			planter.tree_count += 1
			var is_pine := PINES.has(id)
			var ref_h := far_pine_h if is_pine else far_hardwood_h
			var far_s := (NaturePack.dims(id).y / ref_h) if ref_h > 0.0 else 1.0
			var far_basis := Basis(Vector3.UP, ang).scaled(Vector3(far_s, far_s, far_s))
			var far_xf := Transform3D(far_basis, origin)
			if is_pine:
				planter._far_pine.append(far_xf)
			else:
				planter._far_hardwood.append(far_xf)
		else:
			planter.shrub_count += 1

	var ok := func(xz: Vector2, clearance: float) -> bool:
		if not b.has_point(xz):
			return false
		if layout.cached_surface(xz) != PhysicsEnums.SurfaceType.ROUGH:
			return false
		if layout.cached_turf(xz) < clearance:
			return false
		if layout.hazard_near(xz, 3.0) or layout.bunker_near(xz, 3.0):
			return false
		# Trees belong in the outside rough: never inside a fairway corridor (plus a
		# CORRIDOR_MARGIN strip of rough beside it, even where the traced width has a
		# gap) and never crowding a tee box.
		for hole in layout.holes:
			if not layout.hole_bbox(hole).has_point(xz):
				continue
			if not hole.tee_boxes.is_empty() and xz.distance_to(hole.tee_boxes[0][0]) < TEE_CLEARANCE:
				return false
			var fw: FairwayArea = layout.fairways[hole.index]
			var cl := fw.centreline(xz)
			# through a rough carry (no traced width) the shot lane itself stays open
			if cl[0] < maxf(fw.width_at(cl[1], cl[2]), CARRY_LANE_HALF) + CORRIDOR_MARGIN:
				return false
		return true

	# Bushes are low, so they may sit much closer to the mown turf and the shot lane
	# than a 17 m oak: a few metres into the rough is where azaleas actually grow.
	var ok_shrub := func(xz: Vector2) -> bool:
		if not b.has_point(xz):
			return false
		if layout.cached_surface(xz) != PhysicsEnums.SurfaceType.ROUGH:
			return false
		if layout.cached_turf(xz) < SHRUB_TURF_CLEARANCE:
			return false
		if layout.hazard_near(xz, 2.0) or layout.bunker_near(xz, 2.5):
			return false
		for hole in layout.holes:
			if not layout.hole_bbox(hole).has_point(xz):
				continue
			if not hole.tee_boxes.is_empty() and xz.distance_to(hole.tee_boxes[0][0]) < SHRUB_TEE_CLEARANCE:
				return false
			var fw: FairwayArea = layout.fairways[hole.index]
			var cl := fw.centreline(xz)
			if cl[0] < maxf(fw.width_at(cl[1], cl[2]), CARRY_LANE_HALF) + SHRUB_CORRIDOR_MARGIN:
				return false
		return true

	var shrub := func(p: Vector2) -> void:
		var id: String
		if rng.randf() < 0.15:
			rng.randi_range(0, 2)
			return
		else:
			id = SHRUBS[rng.randi_range(0, SHRUBS.size() - 1)]
		place.call(id, p, false)

	# ---- painted woodland footprints
	var painted: Array = []  # [Rect2 bounds, PackedVector2Array] per hole
	var woodland: Array = []
	for hole in layout.holes:
		if not hole.painted.is_empty():
			painted.append([_poly_bounds(hole.painted), hole.painted])
		for poly in hole.woods:
			woodland.append([_poly_bounds(poly), poly])
		if not layout.hole_bbox(hole).intersects(b):
			continue
		var near_water := false
		for w in hole.water_polys:
			near_water = true
		for poly_v in hole.woods:
			var poly: PackedVector2Array = poly_v
			var pb := _poly_bounds(poly)
			if not pb.intersects(b):
				continue
			var cell := TREE_SPACING
			var x := pb.position.x
			while x < pb.end.x:
				var z := pb.position.y
				while z < pb.end.y:
					var p := Vector2(x + rng.randf_range(0.0, cell), z + rng.randf_range(0.0, cell))
					z += cell
					if not Geometry2D.is_point_in_polygon(p, poly):
						continue
					if not ok.call(p, WOODS_TURF_CLEARANCE):
						continue
					var edge := _dist_to_outline(p, poly)
					var id: String
					if edge < EDGE_BAND and rng.randf() < 0.20:
						id = FRINGE_TREES[rng.randi_range(0, FRINGE_TREES.size() - 1)]
					elif near_water and layout.hazard_near(p, 14.0) and rng.randf() < 0.5:
						id = WATERSIDE[rng.randi_range(0, WATERSIDE.size() - 1)]
					else:
						id = _canopy_species(rng)
					place.call(id, p, true)
					# understory: a bush or two in the shade of many trees
					if rng.randf() < UNDERSTORY_SHRUB_CHANCE:
						var q := p + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
						if ok_shrub.call(q):
							shrub.call(q)
				x += cell
			# dense fern/hosta carpet across the whole wood floor, independent of where
			# the trees themselves landed -- this is what actually reads as undergrowth
			# rather than a bush parked at each trunk.
			var fern_cell := FERN_SPACING
			var fx := pb.position.x
			while fx < pb.end.x:
				var fz := pb.position.y
				while fz < pb.end.y:
					var fp := Vector2(fx + rng.randf_range(0.0, fern_cell), fz + rng.randf_range(0.0, fern_cell))
					fz += fern_cell
					if not Geometry2D.is_point_in_polygon(fp, poly):
						continue
					if rng.randf() > FERN_FILL_CHANCE:
						continue
					if not ok_shrub.call(fp):
						continue
					place.call(FERNS[rng.randi_range(0, FERNS.size() - 1)], fp, false)
				fx += fern_cell
			# flowering shrubs along the outer edge of the wood, in loose clumps
			var n := poly.size()
			for i in range(n):
				var a := poly[i]
				var c := poly[(i + 1) % n]
				var steps := maxi(1, int(a.distance_to(c) / SHRUB_SPACING))
				for k in range(steps):
					if rng.randf() > EDGE_SHRUB_CHANCE:
						continue
					var p := a.lerp(c, (k + rng.randf()) / steps)
					var outward := (p - _poly_center(poly)).normalized()
					p += outward * rng.randf_range(-1.0, 4.0)
					if ok_shrub.call(p):
						shrub.call(p)
						if rng.randf() < 0.5:
							var q := p + Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-2.2, 2.2))
							if ok_shrub.call(q):
								shrub.call(q)

	# ---- greenside azaleas: clumps in the rough behind and beside every green
	for hole in layout.holes:
		var wps := hole.waypoints
		if wps.size() < 2:
			continue
		var gc := Vector2(wps[wps.size() - 1].x, wps[wps.size() - 1].z)
		if not b.grow(GREENSIDE_SHRUB_MAX).has_point(gc):
			continue
		for i in range(GREENSIDE_SHRUB_TRIES):
			var ang := rng.randf_range(0.0, TAU)
			var p := gc + Vector2.from_angle(ang) * rng.randf_range(GREENSIDE_SHRUB_MIN, GREENSIDE_SHRUB_MAX)
			if not ok_shrub.call(p):
				continue
			shrub.call(p)
			for j in range(rng.randi_range(1, 3)):
				var q := p + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
				if ok_shrub.call(q):
					shrub.call(q)

	# Deliberately placed course-design trees still use the regular instancing and collision tiers.
	for hole in layout.holes:
		for tree in hole.planted_trees:
			var p: Vector2 = tree[1]
			# Authored trees also keep trunks clear of the final water outline.
			if layout.hazard_near(p, 3.0):
				continue
			# A third value of true lets a tree stand on a creek bank, its crown over the water.
			var waterside: bool = tree.size() > 2 and bool(tree[2])
			if b.has_point(p) and (waterside or layout.cached_surface(p) in [PhysicsEnums.SurfaceType.ROUGH, PhysicsEnums.SurfaceType.FAIRWAY, CourseLayout.SURFACE_TREE_PATCH]):
				place.call(String(tree[0]), p, true)
		# Authored flowering shrubs (the azalea bank behind 12, ...): placed as written, but
		# never on mown turf, sand or water.
		for entry in hole.planted_shrubs:
			var sp: Vector2 = entry[1]
			if b.has_point(sp) and layout.cached_surface(sp) in [PhysicsEnums.SurfaceType.ROUGH, CourseLayout.SURFACE_TREE_PATCH] and not layout.hazard_near(sp, 1.5) and not layout.bunker_near(sp, 1.5):
				place.call(String(entry[0]), sp, false)

	# ---- tree patches inside fairways, ignoring the corridor guard
	for hole in layout.holes:
		for isl in hole.rough_islands:
			if isl.size() > 3 and not bool(isl[3]):
				continue
			var ia: Vector2 = isl[0]
			var ib: Vector2 = isl[1]
			var r: float = isl[2] + 8.0  # the lobed outline reaches past the nominal radius
			var fw_area: FairwayArea = layout.fairways[hole.index]
			var box := Rect2(ia, Vector2.ZERO).expand(ib).grow(r)
			if not box.intersects(b):
				continue
			var cell := 5.5
			var x := box.position.x
			while x < box.end.x:
				var z := box.position.y
				while z < box.end.y:
					var p := Vector2(x + rng.randf_range(0.0, cell), z + rng.randf_range(0.0, cell))
					z += cell
					if CourseArea.dist_to_segment(p, ia, ib) > r or not b.has_point(p) or layout.cached_surface(p) != CourseLayout.SURFACE_TREE_PATCH:
						continue
					if fw_area.tree_patch_distance(p) > -2.5:  # keep trunks off the mown edge
						continue
					if layout.hazard_near(p, 3.0) or layout.bunker_near(p, 3.0):
						continue
					# islands sit in the line of play: smaller ornamental species, not 17 m oaks
					var isl_pool: Array = FRINGE_TREES if rng.randf() < 0.6 else UNDERSTORY_TREES
					place.call(isl_pool[rng.randi_range(0, isl_pool.size() - 1)], p, true)
				x += cell
			# a skirt of bushes around the island's edge
			var full_r: float = isl[2]
			var ring_steps := maxi(4, int((ia.distance_to(ib) * 2.0 + TAU * full_r) / 3.0))
			for i in range(ring_steps):
				var t := rng.randf()
				var on_axis := ia.lerp(ib, t)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var axis := (ib - ia).normalized() if ia != ib else Vector2.RIGHT
				var p := on_axis + Vector2(-axis.y, axis.x) * side * rng.randf_range(full_r - 4.0, full_r - 0.5)
				if CourseArea.dist_to_segment(p, ia, ib) > full_r - 0.5 or not b.has_point(p):
					continue
				if layout.cached_surface(p) != CourseLayout.SURFACE_TREE_PATCH:
					continue
				if layout.hazard_near(p, 2.0) or layout.bunker_near(p, 2.5):
					continue
				shrub.call(p)

	# ---- fill forest wherever no painting covers the ground
	var cell := FILL_SPACING
	var x := floorf(b.position.x / cell) * cell
	while x < b.end.x:
		var z := floorf(b.position.y / cell) * cell
		while z < b.end.y:
			var p := Vector2(x + rng.randf_range(0.0, cell), z + rng.randf_range(0.0, cell))
			z += cell
			var covered := false
			for pr in painted:
				if (pr[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pr[1]):
					covered = true
					break
			if covered:
				continue
			if not ok.call(p, FILL_TURF_CLEARANCE):
				continue
			place.call(_canopy_species(rng), p, true)
			if rng.randf() < UNDERSTORY_SHRUB_CHANCE:
				var q := p + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
				if ok_shrub.call(q):
					shrub.call(q)
		x += cell

	# Use the same footprint and clearances as trees. The open rough stays open;
	# broad green shrubs overlap in two rows just inside the woodland boundary.
	var forest_site := func(p: Vector2) -> bool:
		var in_woods := _inside_regions(p, woodland)
		if not in_woods and _inside_regions(p, painted):
			return false
		return ok.call(p, WOODS_TURF_CLEARANCE if in_woods else FILL_TURF_CLEARANCE)
	var bush_xforms_by_species := _understory_transforms(layout, b, rng_seed, forest_site)
	for species_i in range(FOREST_BUSHES.size()):
		var xforms: Array = bush_xforms_by_species[species_i]
		planter.shrub_count += xforms.size()
		if xforms.is_empty():
			continue
		var scene: PackedScene = FOREST_BUSHES[species_i]
		var inst := scene.instantiate()
		var found: Array = _find_first_mesh_xform(inst)
		var bush_mesh: Mesh = found[0]
		var bush_local_xform: Transform3D = found[1]
		inst.queue_free()
		if bush_mesh == null:
			continue
		_strip_foliage_metallic(bush_mesh)
		# leaves/flowers/buds thin out with distance (scripts/foliage_lod.gd); bark and
		# branches keep their own LODs
		if bush_mesh is ArrayMesh and OS.get_environment("GOLF_PINE_LOD") != "0":
			bush_mesh = FoliageLod.cached("bush_%d" % species_i, bush_mesh, func(n: String) -> bool: return not (n.to_lower().contains("bark") or n.to_lower().contains("branch")), FoliageLod.BUSH_LEVELS)
		var world_xforms: Array[Transform3D] = []
		for t in xforms:
			world_xforms.append((t as Transform3D) * bush_local_xform)
		VegetationBatches.add_batches(planter, "bush_%d" % species_i, bush_mesh, world_xforms, null, false, BUSH_DISTANCE, TILE_MID)
		# Past BUSH_DISTANCE the same tiles hand over to a low-poly mound sized to the bush,
		# out to the tree distance, so the woodland floor doesn't empty out down the hole.
		if not _bush_far_cache.has(species_i):
			_bush_far_cache[species_i] = NaturePack.simplified_mesh(bush_mesh, 0.08)
		VegetationBatches.add_batches(planter, "bushfar_%d" % species_i, _bush_far_cache[species_i], world_xforms, null, false, PerformanceSettings.tree_distance() + TILE_MID * 0.75, TILE_MID, false, BUSH_DISTANCE)

	# ---- pine-straw beds under everything planted (the flyover's brown needle floor)
	var stamps: Array = []
	for c in planter._colliders:
		var base: Vector3 = c[0]
		var canopy_r: float = c[3]
		stamps.append([Vector2(base.x, base.z), maxf(canopy_r * STRAW_CANOPY_FACTOR, 3.5)])
	for hole in layout.holes:
		for bed in hole.straw_beds:
			if b.grow(float(bed[1])).has_point(bed[0]):
				stamps.append([bed[0], float(bed[1])])
	if not stamps.is_empty():
		layout.paint_straw(stamps)

	# ---- instanced batches per species and LOD tier
	for id in per_mesh.keys():
		var xforms: Array = per_mesh[id]
		var far := PerformanceSettings.tree_distance()
		var is_shrub := SHRUBS.has(id)
		var low_poly := NaturePack.mesh_low_poly(id) if LOW_POLY_TREES and not is_shrub else null
		var imp := NaturePack.impostor(id) if USE_IMPOSTORS else []
		if low_poly != null:
			var near_mid := NaturePack.mesh_mid(id, true)
			if near_mid != null:
				VegetationBatches.add_batches(planter, id + "_L2", near_mid, xforms, null, true, NaturePack.DENSE_AT + TILE_MID * 0.75, TILE_MID, false, 0.0)
			if not imp.is_empty():
				VegetationBatches.add_batches(planter, id + "_IMP", imp[0], xforms, imp[1], false, far + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
			else:
				VegetationBatches.add_batches(planter, id + "_LP", low_poly, xforms, null, true, far + TILE_DISTANCE * 0.75, TILE_DISTANCE, false, maxf(0.0, NaturePack.DENSE_AT - TILE_DISTANCE * 0.75))
		elif not imp.is_empty():
			# the shaders do the exact per-instance hand-over at near_at; the tile ranges
			# just have to overlap it generously (a tile's range is measured from its centre)
			# three tiers, all hand-overs per instance in the shaders: full/LOD1 mesh
			# up close, the pack's LOD2 geometry to MID_AT, static cross-cards beyond
			var near_at := SHRUB_MESH_AT if is_shrub else MESH_AT
			VegetationBatches.add_batches(planter, id + "_L0", NaturePack.mesh(id), xforms, null, true, near_at + TILE_NEAR * 0.75, TILE_NEAR, false, 0.0)
			var mid := NaturePack.mesh_mid(id)
			if mid != null:
				var mid_end := NaturePack.SHRUB_MID_AT if is_shrub else NaturePack.DENSE_AT
				VegetationBatches.add_batches(planter, id + "_L2", mid, xforms, null, true, mid_end + TILE_MID * 0.75, TILE_MID, false, 0.0)
			if not is_shrub:
				var distant := NaturePack.mesh_distance(id)
				if distant != null:
					VegetationBatches.add_batches(planter, id + "_L3", distant, xforms, null, false, NaturePack.MID_AT + TILE_DISTANCE * 0.75, TILE_DISTANCE, false, maxf(0.0, NaturePack.DENSE_AT - TILE_DISTANCE * 0.75))
				VegetationBatches.add_batches(planter, id + "_IMP", imp[0], xforms, imp[1], false, far + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
		else:
			# real geometry only: full/LOD1 mesh up close, the pack's LOD2 mesh out to
			# MID_AT, nothing beyond. Hand-overs are per instance in the shaders; the
			# tile ranges just need to overlap them.
			var near_at := SHRUB_MESH_AT if is_shrub else MESH_AT
			VegetationBatches.add_batches(planter, id + "_L0", NaturePack.mesh(id), xforms, null, true, near_at + TILE_NEAR * 0.75, TILE_NEAR, false, 0.0)
			var mid := NaturePack.mesh_mid(id)
			if mid != null:
				var mid_far := NaturePack.SHRUB_MID_AT if is_shrub else NaturePack.DENSE_AT
				VegetationBatches.add_batches(planter, id + "_L2", mid, xforms, null, not is_shrub, mid_far + TILE_MID * 0.75, TILE_MID, false, 0.0)

		if is_shrub:
			# Far tier: a coloured low-poly mound per shrub out to the tree distance, scaled to
			# the species' size, handing over per instance at SHRUB_MID_AT.
			var far_mesh := NaturePack.shrub_far_mesh(id)
			if far_mesh != null:
				VegetationBatches.add_batches(planter, id + "_FAR", far_mesh, xforms, null, false, far + TILE_DISTANCE * 0.75, TILE_DISTANCE, false, maxf(0.0, NaturePack.SHRUB_MID_AT - TILE_DISTANCE * 0.75))
	# ---- far tier: real geometry stopped dead at MID_AT with nothing standing in for
	# it out to PerformanceSettings.tree_distance() (900 m by default), so the forest
	# just vanished past 220 m -- pooled across every species into two cheap proxy
	# shapes (~60 tris/tree, real 3D, no billboard/cross-card) instead of one more
	# MultiMesh per species.
	if not USE_IMPOSTORS and not planter._far_pine.is_empty():
		VegetationBatches.add_batches(planter, "FAR_pine", NaturePack.far_proxy_mesh("pine"), planter._far_pine, null, false, PerformanceSettings.tree_distance() + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
	if not USE_IMPOSTORS and not planter._far_hardwood.is_empty():
		VegetationBatches.add_batches(planter, "FAR_hardwood", NaturePack.far_proxy_mesh("hardwood"), planter._far_hardwood, null, false, PerformanceSettings.tree_distance() + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
	for batch in planter.get_children():
		if batch is GeometryInstance3D:
			batch.layers = PerformanceSettings.TREE_LAYER
	# The overhead map needs crown silhouettes, not a second pass of every leaf.
	var map_transforms: Array = []
	for c in planter._colliders:
		var origin: Vector3 = c[0] + Vector3.UP * (float(c[2]) + float(c[4]) * 0.65)
		map_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(c[3], 0.7, c[3])), origin))
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 8
	crown.rings = 3
	var map_material := StandardMaterial3D.new()
	map_material.albedo_color = Color(0.08, 0.22, 0.10)
	map_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var map_root := Node3D.new()
	map_root.name = "MapTreeCrowns"
	planter.add_child(map_root)
	VegetationBatches.add_batches(map_root, "MapCrowns", crown, map_transforms, map_material, false, 0.0, 256.0)
	for batch in map_root.get_children():
		batch.layers = PerformanceSettings.MAP_LAYER
	return planter


static func _inside_regions(p: Vector2, regions: Array) -> bool:
	for entry in regions:
		if (entry[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, entry[1]):
			return true
	return false


static func _understory_cells(bounds: Rect2, site: Callable) -> Dictionary:
	var cells := {}
	for x in range(floori(bounds.position.x / BUSH_SPACING), ceili(bounds.end.x / BUSH_SPACING)):
		for z in range(floori(bounds.position.y / BUSH_SPACING), ceili(bounds.end.y / BUSH_SPACING)):
			var key := Vector2i(x, z)
			var p := (Vector2(key) + Vector2.ONE * 0.5) * BUSH_SPACING
			if bounds.has_point(p) and site.call(p):
				cells[key] = p
	return cells


static func _understory_edge(key: Vector2i, cells: Dictionary, bounds: Rect2) -> bool:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		for step in [1, 2]:
			var neighbor: Vector2i = key + offset * step
			var p := (Vector2(neighbor) + Vector2.ONE * 0.5) * BUSH_SPACING
			# A streaming-region cut is not a real forest boundary.
			if bounds.has_point(p) and not cells.has(neighbor):
				return true
	return false


static func _understory_transforms(layout: CourseLayout, bounds: Rect2, seed_value: int, site: Callable) -> Array:
	var result: Array = []
	for species in FOREST_BUSHES:
		result.append([] as Array[Transform3D])
	var cells := _understory_cells(bounds, site)
	var authored := {}
	for hole in layout.holes:
		for p in hole.planted_bushes:
			if not bounds.has_point(p) or layout.surface_at(p) != PhysicsEnums.SurfaceType.ROUGH:
				continue
			if layout.hazard_near(p, 4.0) or layout.bunker_near(p, 3.0):
				continue
			# Replace the cell's generic shrub instead of double-planting it.
			var key := Vector2i(floori(p.x / BUSH_SPACING), floori(p.y / BUSH_SPACING))
			cells[key] = p
			authored[key] = true
	for key: Vector2i in cells:
		# Stable per-world-cell randomness keeps shrubs fixed when a region changes.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 139 + key.x * 73856093 + key.y * 19349663
		var edge := authored.has(key) or _understory_edge(key, cells, bounds)
		if not edge and rng.randf() > BUSH_FILL_CHANCE:
			continue
		var p: Vector2 = cells[key]
		var jitter := p + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
		if not authored.has(key) and bounds.has_point(jitter) and site.call(jitter):
			p = jitter
		var species := 2 if rng.randf() < 0.6 else 3
		if not edge:
			var accent := rng.randf()
			if accent < 0.035:
				species = 0
			elif accent < 0.16:
				species = 1
		var limits: Vector2 = FOREST_BUSH_SCALE_RANGES[species]
		var size := rng.randf_range(limits.x, limits.y)
		var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * size)
		var origin := Vector3(p.x, layout.height_at(p.x, p.y) - 0.10, p.y)
		if layout.in_pad(p, 1.0):
			continue
		(result[species] as Array).append(Transform3D(basis, origin))
	return result


static func _canopy_species(rng: RandomNumberGenerator) -> String:
	# Augusta's woods are tall loblolly pines over a pine-straw floor with hardwoods
	# mixed in. Leave more space between trunks and keep flowers in edge beds.
	var r := rng.randf()
	if r < 0.78:
		return PINES[rng.randi_range(0, PINES.size() - 1)]
	if r < 0.95:
		return HARDWOODS[rng.randi_range(0, HARDWOODS.size() - 1)]
	return UNDERSTORY_TREES[rng.randi_range(0, UNDERSTORY_TREES.size() - 1)]


## Returns [Mesh, Transform3D]: the mesh resource plus its full transform
## FOREST_BUSHES[i]'s mesh (foliage made matte, as in the woods) and its transform in the scene;
## the club's shrub beds plant the same bushes (FacilityBuilder).
static func bush_mesh(i: int) -> Array:
	var inst := (FOREST_BUSHES[i] as PackedScene).instantiate()
	var found: Array = _find_first_mesh_xform(inst)
	inst.free()
	if found[0] != null:
		_strip_foliage_metallic(found[0])
	return found


## relative to the scene root. Imported glTF assets often bake object scale
## onto an ancestor Node3D rather than into the mesh's own vertex data (the
## Forsythia bushes do this: a 0.01-scale wrapper node brings ~100-unit raw
## mesh data down to the correct ~1m size) -- returning the bare Mesh alone
## silently drops that scale and any offset/rotation baked onto ancestors.
static func _find_first_mesh_xform(node: Node) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		return [mi.mesh, mi.transform]
	for c in node.get_children():
		var found: Array = _find_first_mesh_xform(c)
		if found[0] != null:
			var node_xform := Transform3D.IDENTITY
			if node is Node3D:
				node_xform = (node as Node3D).transform
			return [found[0], node_xform * (found[1] as Transform3D)]
	return [null, Transform3D.IDENTITY]


const BUSH_FOLIAGE_COLOR := Color("032b1a")
## Compensate for the broad-leaf atlas's mean albedo to reach BUSH_FOLIAGE_COLOR.
## Apply to leaf/flower surfaces, preserving the separate bark/branch colors.
const BUSH_FOLIAGE_TINT := Color(0.06730, 0.43230, 0.42254)

## Several of the user-supplied bush packs' glTF export wired a glossiness/ORS
## (occlusion-roughness-specular) map into the material's metallic slot --
## Blender's exporter or Godot's importer misread it as a metallic map. On a
## leaf/flower surface that reads as a bright, sky-reflecting mirror instead of
## matte green foliage (reported by the user as "white clear color" bushes).
## Foliage should never be metallic, so strip it unconditionally.
static func _strip_foliage_metallic(mesh: Mesh) -> void:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			bm.metallic = 0.0
			bm.metallic_texture = null
			# Pale sky reflections can overwhelm dark leaf albedo. Match the
			# matte, specular-disabled grass cards instead of reflecting the sky.
			bm.metallic_specular = 0.0
			bm.roughness = 1.0
			bm.roughness_texture = null
			var name_lower := String(mat.resource_name).to_lower()
			if not (name_lower.contains("bark") or name_lower.contains("branch")):
				bm.albedo_color = BUSH_FOLIAGE_TINT


static func _poly_bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func _poly_center(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


static func _dist_to_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for i in range(n):
		best = minf(best, CourseArea.dist_to_segment(p, poly[i], poly[(i + 1) % n]))
	return best


func _ready() -> void:
	if _colliders.is_empty():
		return
	var ps := PhysicsServer3D
	var space := get_world_3d().space
	for c in _colliders:
		var base: Vector3 = c[0]
		var body := ps.body_create()
		ps.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		ps.body_set_collision_layer(body, PropScatter.OBSTACLE_LAYER)
		ps.body_set_collision_mask(body, 0)
		var trunk := ps.cylinder_shape_create()
		var trunk_height: float = c[2] + c[4] * 0.75
		ps.shape_set_data(trunk, {"radius": c[1], "height": trunk_height})
		ps.body_add_shape(body, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, trunk_height * 0.5, 0.0)))
		var crown_body := ps.body_create()
		ps.body_set_mode(crown_body, PhysicsServer3D.BODY_MODE_STATIC)
		ps.body_set_collision_layer(crown_body, FOLIAGE_LAYER)
		ps.body_set_collision_mask(crown_body, 0)
		var canopy := ps.cylinder_shape_create()
		ps.shape_set_data(canopy, {"radius": c[3], "height": c[4]})
		ps.body_add_shape(crown_body, canopy, Transform3D(Basis.IDENTITY, Vector3(0.0, c[2] + c[4] * 0.5, 0.0)))
		ps.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, base))
		ps.body_set_space(body, space)
		ps.body_set_state(crown_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, base))
		ps.body_set_space(crown_body, space)
		_rids.append(crown_body)
		_rids.append(body)
		_rids.append(trunk)
		_rids.append(canopy)
	_colliders.clear()


func _exit_tree() -> void:
	for r in _rids:
		PhysicsServer3D.free_rid(r)
	_rids.clear()
