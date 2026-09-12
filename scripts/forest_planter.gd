class_name ForestPlanter
extends Node3D
## Plants the course's woodland from the traced paintings: dense tree groups inside
## every hole's `woods` footprints, a continuous forest wherever the paintings do not
## reach (between corridors, past the course edges), flowering dogwood / azalea along
## the woodland edges, and nothing on turf, sand or water.
##
## Rendering is all instanced: one MultiMesh tile per species/LOD (VegetationBatches),
## LOD0 close, LOD1 mid, LOD2 far, shadows only on the two near tiers. Collision is
## one PhysicsServer body holding a trunk cylinder + canopy cylinder per tree (no
## nodes), on PropScatter.OBSTACLE_LAYER so the ball can hit them.

const TREE_SPACING := 7.5  # metres between trees inside a wood (jittered grid)
const FILL_SPACING := 9.0  # metres between trees in the fill forest off the paintings
const FILL_TURF_CLEARANCE := 22.0  # fill forest keeps this far from any mown turf
const WOODS_TURF_CLEARANCE := 10.0  # traced tree groups keep this far from any mown turf
const CORRIDOR_MARGIN := 14.0  # rough strip beside every fairway corridor kept free of trunks
const TEE_CLEARANCE := 60.0  # no trees this close to a back tee (crowns are 10-17 m wide)
const CARRY_LANE_HALF := 18.0  # half width of the tree-free lane along a rough carry
const EDGE_BAND := 7.0  # metres inside a wood's edge that reads as its flowering fringe
const SHRUB_SPACING := 3.0  # metres between candidate bushes along a wood's edge
const EDGE_SHRUB_CHANCE := 0.32  # share of edge candidates that get a bush
const UNDERSTORY_SHRUB_CHANCE := 0.10  # bushes under the canopy, per tree planted
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
const USE_IMPOSTORS := false
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
const TILE_NEAR := 24.0
const TILE_MID := 128.0
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
		var sc := rng.randf_range(0.7, 1.2)
		var ang := rng.randf_range(0.0, TAU)
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
		if rng.randf() < 0.72:
			# Leave the removed bushes' positions empty and retain the seeded tree layout.
			rng.randi_range(0, 2)
			return
		else:
			id = SHRUBS[rng.randi_range(0, SHRUBS.size() - 1)]
		place.call(id, p, false)

	# ---- painted woodland footprints
	var painted: Array = []  # [Rect2 bounds, PackedVector2Array] per hole
	for hole in layout.holes:
		if not hole.painted.is_empty():
			painted.append([_poly_bounds(hole.painted), hole.painted])
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

	# ---- rough islands inside fairways: a few trees each, ignoring the corridor guard
	for hole in layout.holes:
		for isl in hole.rough_islands:
			var ia: Vector2 = isl[0]
			var ib: Vector2 = isl[1]
			var r: float = isl[2] - 3.0
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
					if CourseArea.dist_to_segment(p, ia, ib) > r or not b.has_point(p) or layout.cached_surface(p) != PhysicsEnums.SurfaceType.ROUGH:
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
				if layout.cached_surface(p) != PhysicsEnums.SurfaceType.ROUGH:
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

	# ---- pine-straw beds under everything planted (the flyover's brown needle floor)
	var stamps: Array = []
	for c in planter._colliders:
		var base: Vector3 = c[0]
		var canopy_r: float = c[3]
		stamps.append([Vector2(base.x, base.z), maxf(canopy_r * STRAW_CANOPY_FACTOR, 3.5)])
	if not stamps.is_empty():
		layout.paint_straw(stamps)

	# ---- instanced batches per species and LOD tier
	for id in per_mesh.keys():
		var xforms: Array = per_mesh[id]
		var far := PerformanceSettings.tree_distance()
		var is_shrub := SHRUBS.has(id)
		var imp := NaturePack.impostor(id) if USE_IMPOSTORS else []
		if not imp.is_empty():
			# the shaders do the exact per-instance hand-over at near_at; the tile ranges
			# just have to overlap it generously (a tile's range is measured from its centre)
			# three tiers, all hand-overs per instance in the shaders: full/LOD1 mesh
			# up close, the pack's LOD2 geometry to MID_AT, static cross-cards beyond
			var near_at := SHRUB_MESH_AT if is_shrub else MESH_AT
			VegetationBatches.add_batches(planter, id + "_L0", NaturePack.mesh(id), xforms, null, true, near_at + TILE_NEAR * 0.75, TILE_NEAR, false, 0.0)
			var mid := NaturePack.mesh_mid(id)
			if mid != null:
				VegetationBatches.add_batches(planter, id + "_L2", mid, xforms, null, true, NaturePack.MID_AT + TILE_MID * 0.75, TILE_MID, false, 0.0)
			if not is_shrub:
				VegetationBatches.add_batches(planter, id + "_IMP", imp[0], xforms, imp[1], false, far, TILE_FAR, false, 0.0)
		else:
			# real geometry only: full/LOD1 mesh up close, the pack's LOD2 mesh out to
			# MID_AT, nothing beyond. Hand-overs are per instance in the shaders; the
			# tile ranges just need to overlap them.
			var near_at := SHRUB_MESH_AT if is_shrub else MESH_AT
			VegetationBatches.add_batches(planter, id + "_L0", NaturePack.mesh(id), xforms, null, true, near_at + TILE_NEAR * 0.75, TILE_NEAR, false, 0.0)
			var mid := NaturePack.mesh_mid(id)
			if mid != null:
				var mid_far := (LOD2_AT if is_shrub else NaturePack.MID_AT)
				VegetationBatches.add_batches(planter, id + "_L2", mid, xforms, null, not is_shrub, mid_far + TILE_MID * 0.75, TILE_MID, false, 0.0)

	# ---- far tier: real geometry stopped dead at MID_AT with nothing standing in for
	# it out to PerformanceSettings.tree_distance() (900 m by default), so the forest
	# just vanished past 220 m -- pooled across every species into two cheap proxy
	# shapes (~60 tris/tree, real 3D, no billboard/cross-card) instead of one more
	# MultiMesh per species.
	if not planter._far_pine.is_empty():
		VegetationBatches.add_batches(planter, "FAR_pine", NaturePack.far_proxy_mesh("pine"), planter._far_pine, null, false, PerformanceSettings.tree_distance() + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
	if not planter._far_hardwood.is_empty():
		VegetationBatches.add_batches(planter, "FAR_hardwood", NaturePack.far_proxy_mesh("hardwood"), planter._far_hardwood, null, false, PerformanceSettings.tree_distance() + TILE_FAR * 0.75, TILE_FAR, false, maxf(0.0, NaturePack.MID_AT - TILE_FAR * 0.75))
	return planter


static func _canopy_species(rng: RandomNumberGenerator) -> String:
	# Augusta's woods are tall loblolly pines over a pine-straw floor with hardwoods
	# mixed in. Leave more space between trunks and keep flowers in edge beds.
	var r := rng.randf()
	if r < 0.78:
		return PINES[rng.randi_range(0, PINES.size() - 1)]
	if r < 0.95:
		return HARDWOODS[rng.randi_range(0, HARDWOODS.size() - 1)]
	return UNDERSTORY_TREES[rng.randi_range(0, UNDERSTORY_TREES.size() - 1)]


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
		ps.shape_set_data(trunk, {"radius": c[1], "height": c[2]})
		ps.body_add_shape(body, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, c[2] * 0.5, 0.0)))
		var canopy := ps.cylinder_shape_create()
		ps.shape_set_data(canopy, {"radius": c[3], "height": c[4]})
		ps.body_add_shape(body, canopy, Transform3D(Basis.IDENTITY, Vector3(0.0, c[2] + c[4] * 0.5, 0.0)))
		ps.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, base))
		ps.body_set_space(body, space)
		_rids.append(body)
		_rids.append(trunk)
		_rids.append(canopy)
	_colliders.clear()


func _exit_tree() -> void:
	for r in _rids:
		PhysicsServer3D.free_rid(r)
	_rids.clear()
