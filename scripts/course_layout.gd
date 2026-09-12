class_name CourseLayout
extends RefCounted
## Course definition: holes, terrain height, excavations (ponds, creeks, bunkers) and lie
## surface lookup. All distances in metres. Filled in by CourseBuilder.

## Extra "surface" ids layered on top of PhysicsEnums.SurfaceType for gameplay.
## They map back to an engine surface via `engine_surface()`.
const SURFACE_BUNKER := 100
const SURFACE_WATER := 101
const SURFACE_TEE := 102
## Intermediate cut: a short collar of semi-rough around every fairway.
const SURFACE_FIRST_CUT := 103
const FIRST_CUT_WIDTH := 2.5
## Fringe: the tight collar of turf around every green.
const SURFACE_FRINGE := 104
const FRINGE_WIDTH := 2.5
## Vegetation-spawn dampening border: how far past a prop's own min_dist_to_fairway
## (PropScatter) / the fairway edge (NatureSetProps) its density keeps ramping up to
## full. Purely a placement/density control, much thicker than the lie transition
## above -- it doesn't touch which surface a point lies on or how it's colored.
const FORAGE_BORDER_WIDTH := 10.0

class Hole:
	var index: int
	var name: String
	var par: int
	var tee: Vector3
	var waypoints: Array[Vector3]  # fairway centerline, first = tee area, last = green center
	var fairway_half_width: float = 16.0  # mean half width (framing / generators)
	## Traced mown width: (metres along the route, left half width, right half width)
	## every `fairway_step` metres. Empty = generic capsule fairway.
	var fairway_profile: PackedVector3Array = PackedVector3Array()
	var fairway_step: float = 4.0
	var rough_islands: Array = []  # [Vector2 a, Vector2 b, float radius] capsules of rough kept inside the fairway, with trees
	var green_radius: float = 12.0
	var green_height: float = 0.6
	var green_center: Vector2 = Vector2.ZERO
	## Traced green outline: radius (m) per angle bin around `green_center`, bins
	## starting at world angle `green_rotation`. Empty = generic harmonic circle.
	var green_radial: PackedFloat32Array = PackedFloat32Array()
	var green_rotation: float = 0.0
	var green_relief: Vector2 = Vector2(0.4, 0.8)  # proposed internal relief range (m)
	## Proposed elevation along the route: (metres from the tee, height in local metres,
	## tee = 0). Scaled by PROFILE_SCALE and offset by `tee_h`. Empty = flat.
	var profile: PackedVector2Array = PackedVector2Array()
	var tee_h: float = 0.0  # datum height of the tee (set by CourseLayout.build_datum)
	var green_h: float = 0.0  # datum height of the green
	## How much of the profile's end grade the putting surface keeps (1 = all of it);
	## capped so a green never inherits more than GREEN_MAX_GRADE from its approach.
	var green_grade_scale: float = 1.0
	var green_landform: float = 0.0  # sculpted height at the green centre (relief cap reference)
	var bunker_polys: Array = []  # [String id, String role, PackedVector2Array outline]
	var water_polys: Array = []  # [String name, PackedVector2Array outline]
	var creek_paths: Array = []  # [PackedVector2Array path, float width] hand-authored streams
	var tee_boxes: Array = []  # [Vector2 center, Vector2 dir, Vector2 half (across, along)], back tee first
	var landforms: Array = []  # {id, s0, s1} named terrain features still to sculpt
	var woods: Array = []  # PackedVector2Array traced tree-group footprints
	var painted: PackedVector2Array = PackedVector2Array()  # extent of the hole painting
	var bbox: Rect2 = Rect2()  # lazily computed influence box (see CourseLayout.hole_bbox)
	var cup: Vector3:
		get:
			return waypoints[waypoints.size() - 1]
	var length_yd: float:
		get:
			var d := 0.0
			for i in range(1, waypoints.size()):
				d += (waypoints[i] - waypoints[i - 1]).length()
			return d * ShotSetup.YARDS_PER_METER

var holes: Array[Hole] = []
## Turf areas, one per hole (built by `_build_turf_areas`, see scripts/areas/).
var fairways: Array[FairwayArea] = []
var greens: Array[GreenArea] = []
var tees: Array[TeeArea] = []
var rough: RoughArea = null
var name_pretty: String = "Willow Creek"
## Authored creeks: [Vector2 start, Vector2 end, float width]
var creeks: Array = []
var random_trees: bool = true
## True when the builder placed every hazard by hand (no random generators run).
var authored_hazards: bool = false
var terrain_seed: int = 1337
var terrain_amplitude: float = 3.0
var terrain_frequency: float = 0.006
var terrain_detail: float = 0.18
## Broad hills on top of the hole datum (metres).
var terrain_hills: float = 0.0
## Compiled named landforms (see Landforms), summed onto the shaped terrain.
var landform_list: Array = []
## Fraction of each hole's proposed elevation profile that is applied (the handoff
## heights are full-scale reconstruction proposals; 1.0 = as proposed).
const PROFILE_SCALE := 0.5
## Steepest overall grade a putting surface inherits from its hole profile (rise/run):
## a ball will not stop on much more than this at green speed.
const GREEN_MAX_GRADE := 0.022
## Flatness guarantee for putting surfaces (see base_height_from): how much of a
## surround mound/ridge survives inside the green, and the soft cap on total sculpted
## relief there (metres).
const GREEN_BUMP_SCALE := 0.25
const GREEN_MAX_RELIEF := 0.6
var hills_noise := FastNoiseLite.new()
## WaterHazard nodes (see water_hazard.gd / water_hazard_generator.gd). They override
## the lie surface and carve the terrain; the ball flags a splash when it lands in one.
var water_hazards: Array = []
## Bunker excavations (see bunker.gd / bunker_generator.gd). Fixed hole bunker circles are
## converted into these at init; generators and the dig tool add more.
var bunkers: Array = []
var bounds := Rect2(-80.0, -360.0, 400.0, 420.0)  # x, z, w, h  (terrain footprint)
var noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()


func _init() -> void:
	noise.seed = terrain_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = terrain_frequency
	noise.fractal_octaves = 3
	detail_noise.seed = 4242
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.08
	hills_noise.seed = 777
	hills_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills_noise.frequency = 0.0012
	hills_noise.fractal_octaves = 2


## Call once the holes are set: builds the turf areas and elevation datum, then digs
## every hole's water and bunker outlines into Excavations.
func finalize_features() -> void:
	_build_turf_areas()
	build_datum()
	landform_list.clear()
	for hole in holes:
		landform_list.append_array(Landforms.compile(hole))
	for hole in holes:
		var s := Landforms.offset_split(landform_list, Vector2(hole.cup.x, hole.cup.z))
		hole.green_landform = s.y + s.x * GREEN_BUMP_SCALE
	_hole_water_to_hazards()
	_creeks_to_hazards()
	_hole_bunkers_to_excavations()
	_extend_creeks()  # after the sand, so streams can steer round bunkers
	rough = RoughArea.new()
	rough.setup(self)


## Every XZ point a hole owns (routing, hazards, tees): framing and bounds.
func feature_points(hole: Hole) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wp in hole.waypoints:
		out.append(Vector2(wp.x, wp.z))
	for b in hole.bunker_polys:
		for p in b[2]:
			out.append(p)
	for w in hole.water_polys:
		for p in w[1]:
			out.append(p)
	for t in hole.tee_boxes:
		out.append(t[0])
	if not hole.green_radial.is_empty():
		out.append(hole.green_center)
	return out


## One FairwayArea / GreenArea / TeeArea per hole from the hole geometry.
func _build_turf_areas() -> void:
	fairways.clear()
	greens.clear()
	tees.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 17
	for hole in holes:
		var pts := PackedVector2Array()
		for wp in hole.waypoints:
			pts.append(Vector2(wp.x, wp.z))
		var fw := FairwayArea.new()
		fw.setup(pts, hole.fairway_half_width, hole.index, rng, hole.fairway_profile, hole.fairway_step)
		fw.islands = hole.rough_islands
		fw.area_name = "%s fairway" % hole.name
		fairways.append(fw)
		var approach := (pts[pts.size() - 1] - pts[maxi(pts.size() - 2, 0)]).normalized()
		var gr := GreenArea.new()
		if hole.green_radial.is_empty():
			gr.setup(pts[pts.size() - 1], hole.green_radius, hole.index, rng, approach)
		else:
			gr.setup_radial(hole.green_center, hole.green_radial, hole.green_rotation, hole.index)
		gr.area_name = "%s green" % hole.name
		greens.append(gr)
		var first_dir := (pts[1] - pts[0]).normalized() if pts.size() > 1 else Vector2(0, -1)
		var te := TeeArea.new()
		if hole.tee_boxes.is_empty():
			te.setup(pts[0], first_dir, hole.index)
		else:
			te.setup(hole.tee_boxes[0][0], hole.tee_boxes[0][1], hole.index, hole.tee_boxes[0][2])
		te.area_name = "%s tee" % hole.name
		tees.append(te)
		hole.bbox = Rect2()


func _ensure_areas() -> void:
	if fairways.size() != holes.size():
		_build_turf_areas()


## Every area object of the course (turf areas plus dug hazards).
func all_areas() -> Array:
	var out: Array = []
	out.append_array(fairways)
	out.append_array(greens)
	out.append_array(tees)
	out.append_array(bunkers)
	out.append_array(water_hazards)
	if rough != null:
		out.append(rough)
	return out


func _creeks_to_hazards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3030
	for ck in creeks:
		var hz := WaterHazard.make_creek(ck[0], ck[1], float(ck[2]), rng)
		var owner: String = String(ck[3]) if ck.size() > 3 else name_pretty.split(" ")[0]
		hz.hazard_name = "%s Creek" % owner
		hz.finalize(self)
		water_hazards.append(hz)


## Dig every hole's traced sand outlines.
func _hole_bunkers_to_excavations() -> void:
	for hole in holes:
		for bk in hole.bunker_polys:
			var b := Bunker.from_polygon(bk[2])
			b.kind = bk[1]
			if b.kind == "fairway":
				b.depth = clampf(b.depth * 1.6, 0.6, 1.4)
			b.feature_name = "%s bunker" % hole.name
			b.finalize(self)
			bunkers.append(b)


## Dig every hole's traced water outlines (a long thin body is called a creek).
func _hole_water_to_hazards() -> void:
	for hole in holes:
		for w in hole.water_polys:
			var pts: PackedVector2Array = w[1]
			var hz := WaterHazard.from_polygon(pts)
			var r := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				r = r.expand(p)
			var aspect := maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)
			var first := hole.name.split(" ")[0]
			if aspect > 3.0 or hz.area_m2() < 900.0:
				hz.is_creek = true
				hz.shore_width = 2.0
				hz.max_depth = 0.7
				hz.hazard_name = "%s Creek" % first
			else:
				hz.hazard_name = "%s Pond" % first
			hz.finalize(self)
			water_hazards.append(hz)
		var rng := RandomNumberGenerator.new()
		rng.seed = 6060 + hole.index
		for cp in hole.creek_paths:
			var s := WaterHazard.make_stream(cp[0], float(cp[1]), rng)
			s.hazard_name = "%s Creek" % hole.name.split(" ")[0]
			s.finalize(self)
			water_hazards.append(s)


## A painted creek fragment is only the stretch the illustration shows; a stream
## cannot simply stop, so each one is continued from both ends: the lower end runs
## downhill (meandering, steering round greens, tees and sand) until it reaches other
## water or the course edge, the upper end climbs toward a source the same way.
const CREEK_EXTEND_M := 260.0
const CREEK_STEP := 12.0
const CREEK_TURN_DEG := [-45.0, -22.0, 0.0, 22.0, 45.0]


func _extend_creeks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5050
	var originals := water_hazards.duplicate()
	for hz in originals:
		if not hz.is_creek:
			continue
		var axis := _polygon_axis(hz.polygon)  # [end_a, end_b, dir a->b, width]
		var end_a: Vector2 = axis[0]
		var end_b: Vector2 = axis[1]
		var axis_dir: Vector2 = axis[2]
		var width: float = axis[3]
		var h_a := base_height_at(end_a.x, end_a.y)
		var h_b := base_height_at(end_b.x, end_b.y)
		for e in [[end_a, -axis_dir, h_a <= h_b], [end_b, axis_dir, h_b <= h_a]]:
			var start: Vector2 = e[0]
			var dir0: Vector2 = e[1]
			var downhill: bool = e[2]
			var path := _march_stream(start, dir0, downhill, hz, rng)
			if path.size() < 3:
				continue
			var s := WaterHazard.make_stream(path, maxf(width * 0.8, 2.5), rng)
			s.hazard_name = hz.hazard_name
			s.finalize(self)
			water_hazards.append(s)


func _march_stream(start: Vector2, dir0: Vector2, downhill: bool, source: WaterHazard, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array([start])
	var dir := dir0
	var p := start
	var steps := int(CREEK_EXTEND_M / CREEK_STEP)
	var wander := rng.randf_range(0.0, TAU)
	for i in range(steps):
		var best_dir := Vector2.ZERO
		var best_score := INF
		var hit_water := false
		for a in CREEK_TURN_DEG:
			var cand: Vector2 = dir.rotated(deg_to_rad(a + 12.0 * sin(i * 0.6 + wander)))
			var q := p + cand * CREEK_STEP
			if not bounds.grow(-30.0).has_point(q):
				continue
			if _stream_blocked(q):
				continue
			var other := hazard_at(q)
			if other != null and other != source:
				hit_water = true
				best_dir = cand
				break
			var h := base_height_at(q.x, q.y)
			var score := (h if downhill else -h) + absf(a) * 0.015
			if score < best_score:
				best_score = score
				best_dir = cand
		if best_dir == Vector2.ZERO:
			break
		dir = best_dir
		p += dir * CREEK_STEP
		pts.append(p)
		if hit_water:
			break
	return pts


func _stream_blocked(q: Vector2) -> bool:
	_ensure_areas()
	for i in range(holes.size()):
		if greens[i].bounds.grow(12.0).has_point(q) and greens[i].signed_distance(q) < 12.0:
			return true
		if tees[i].bounds.grow(15.0).has_point(q) and tees[i].signed_distance(q) < 15.0:
			return true
	return bunker_near(q, 6.0)


## Principal axis of a polygon: [end_a, end_b, unit dir a->b, mean width].
static func _polygon_axis(poly: PackedVector2Array) -> Array:
	var c := Excavation.centroid(poly)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in poly:
		var d := p - c
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
	var dir := Vector2(cos(ang), sin(ang))
	var lo := INF
	var hi := -INF
	var end_a := c
	var end_b := c
	for p in poly:
		var t := (p - c).dot(dir)
		if t < lo:
			lo = t
			end_a = p
		if t > hi:
			hi = t
			end_b = p
	var length := maxf(hi - lo, 1.0)
	var width := absf(Excavation.signed_area(poly)) / length
	return [end_a, end_b, dir, width]


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Influence box of a hole: centreline extent grown by the widest effect radius
## (grass band + far rough). Points outside it are treated as infinitely far.
const HOLE_BBOX_MARGIN := 70.0

func hole_bbox(hole: Hole) -> Rect2:
	if hole.bbox.size == Vector2.ZERO:
		_ensure_areas()
		var i := hole.index
		var r := fairways[i].bounds.merge(greens[i].bounds).merge(tees[i].bounds)
		for p in feature_points(hole):
			r = r.expand(p)
		hole.bbox = r.grow(HOLE_BBOX_MARGIN)
	return hole.bbox


## Returns [distance_to_fairway_centerline, distance_along_fairway] for a hole.
func fairway_distance(hole: Hole, xz: Vector2) -> Array:
	if not hole_bbox(hole).has_point(xz):
		return [1.0e9, 0.0]
	return fairways[hole.index].centreline(xz)


func is_on_tee_box(hole: Hole, xz: Vector2) -> bool:
	_ensure_areas()
	return tees[hole.index].contains(xz)


## Gameplay surface at a world XZ position (may return SURFACE_* extras).
func surface_at(xz: Vector2) -> int:
	return surface_from(xz, _hole_fds(xz))


## Per-hole [distance_to_centreline, along] for `xz`, or null when outside the hole's box.
func _hole_fds(xz: Vector2) -> Array:
	_ensure_areas()
	var out := []
	out.resize(holes.size())
	for i in range(holes.size()):
		var hole := holes[i]
		if not hole_bbox(hole).has_point(xz):
			out[i] = null
			continue
		var cl: Array = fairways[i].centreline(xz)
		var fw_sd: float = fairways[i].signed_distance_from(xz, cl)
		var g_sd: float = greens[i].signed_distance(xz) if greens[i].bounds.has_point(xz) else 1.0e9
		var t_sd: float = tees[i].signed_distance(xz) if tees[i].bounds.has_point(xz) else 1.0e9
		out[i] = [fw_sd, cl[1], g_sd, t_sd, cl[0], cl[3]]
	return out


## Signed distance to the nearest mown turf (fairway, green or tee); negative inside.
func turf_signed_distance(xz: Vector2) -> float:
	var fds := _hole_fds(xz)
	return turf_sd_from(fds)


static func turf_sd_from(fds: Array) -> float:
	var best := 1.0e9
	for f in fds:
		if f == null:
			continue
		best = minf(best, minf(f[0], minf(f[2], f[3])))
	return best


static func green_sd_from(fds: Array) -> float:
	var best := 1.0e9
	for f in fds:
		if f == null:
			continue
		best = minf(best, f[2])
	return best


## Surface classification given precomputed hole distances (see _hole_fds).
func surface_from(xz: Vector2, fds: Array) -> int:
	if hazard_at(xz) != null:
		return SURFACE_WATER
	if bunker_at(xz) != null:
		return SURFACE_BUNKER
	var first_cut := false
	var fringe := false
	for f in fds:
		if f == null:
			continue
		if f[2] < 0.0:
			return PhysicsEnums.SurfaceType.GREEN
		if f[2] < FRINGE_WIDTH:
			fringe = true
		if f[3] < 0.0:
			return SURFACE_TEE
	if fringe:
		return SURFACE_FRINGE
	for f in fds:
		if f == null:
			continue
		if f[0] < 0.0:
			return PhysicsEnums.SurfaceType.FAIRWAY
		if f[0] < FIRST_CUT_WIDTH:
			first_cut = true
	if first_cut:
		return SURFACE_FIRST_CUT
	return PhysicsEnums.SurfaceType.ROUGH


## Map a gameplay surface to the OpenFairway engine surface type.
static func engine_surface(surface: int) -> int:
	match surface:
		SURFACE_BUNKER:
			return PhysicsEnums.SurfaceType.BUNKER
		SURFACE_WATER:
			return PhysicsEnums.SurfaceType.FAIRWAY_SOFT
		SURFACE_TEE:
			return PhysicsEnums.SurfaceType.FIRM
		SURFACE_FIRST_CUT:
			return PhysicsEnums.SurfaceType.FAIRWAY_SOFT
		SURFACE_FRINGE:
			return PhysicsEnums.SurfaceType.FAIRWAY
		_:
			return surface


static func surface_label(surface: int) -> String:
	match surface:
		SURFACE_BUNKER:
			return "Bunker"
		SURFACE_WATER:
			return "Water"
		SURFACE_TEE:
			return "Tee"
		SURFACE_FIRST_CUT:
			return "First cut"
		SURFACE_FRINGE:
			return "Fringe"
		_:
			return SurfacePhysicsCatalog.surface_name(surface)


## Terrain height at world XZ, including water hazard beds and banks.
func height_at(x: float, z: float) -> float:
	var base := base_height_at(x, z)
	return base + excavation_offset(base, Vector2(x, z))


## Terrain height before water hazards are carved in.
func base_height_at(x: float, z: float) -> float:
	return base_height_from(x, z, _hole_fds(Vector2(x, z)))


## Shaped terrain (fairway flattening, raised greens/tees, bunker dips) given hole distances.
func base_height_from(x: float, z: float, fds: Array) -> float:
	var base := _raw_height(x, z)
	var datum := _datum(x, z)
	var roll := (base - datum) * 0.15  # residual undulation kept on mown turf
	var flatten := 0.0  # 0 = full noise, 1 = follows the target
	var target := base
	var offset := 0.0
	for i in range(holes.size()):
		if fds[i] == null:
			continue
		var hole := holes[i]
		var fw_sd: float = fds[i][0]
		var fw_t := (1.0 - smoothstep(0.0, 14.0, fw_sd)) * 0.85
		if fw_t > flatten:
			flatten = fw_t
			target = hole_datum(hole, fds[i][1]) + roll
		# The putting surface (plus its fringe) follows the route profile's own gentle
		# grade, continued past the green centre, so a green inherits the hole's
		# back-to-front or front-to-back tendency and its apron meets it without a
		# step; the named landforms sculpt the rest. No wide flattened ring: that made
		# every green a plateau and killed the runoffs around it.
		var g_t := 1.0 - smoothstep(-1.0, 4.0, fds[i][2])
		if g_t > flatten:
			flatten = g_t
			target = hole.green_h + (hole_datum(hole, fds[i][5]) - hole.green_h) * hole.green_grade_scale + roll * 0.3
		offset += hole.green_height * g_t
		var t_t := 1.0 - smoothstep(0.0, 6.0, fds[i][3])
		if t_t > flatten:
			flatten = t_t
			target = hole.tee_h + 0.3
	if not landform_list.is_empty():
		var lf := Landforms.offset_split(landform_list, Vector2(x, z))
		# A putting surface stays relatively flat no matter what is sculpted around it:
		# surround bumps fade to GREEN_BUMP_SCALE inside the green and the whole
		# landform relief there is soft-capped at ±GREEN_MAX_RELIEF.
		var g_max := 0.0
		var g_hole: Hole = null
		for i in range(holes.size()):
			if fds[i] != null:
				var gt := 1.0 - smoothstep(-1.0, 4.0, fds[i][2])
				if gt > g_max:
					g_max = gt
					g_hole = holes[i]
		var total := lf.y + lf.x * lerpf(1.0, GREEN_BUMP_SCALE, g_max)
		if g_hole != null:
			# cap the relief relative to the green centre, not the platform's own height
			var rel := total - g_hole.green_landform
			var capped := GREEN_MAX_RELIEF * tanh(rel / GREEN_MAX_RELIEF)
			total = g_hole.green_landform + lerpf(rel, capped, g_max)
		offset += total
	return lerpf(base, target, flatten) + offset


## Datum height of a hole `along` metres from the tee: the proposed elevation profile
## (cubic Hermite through its samples, held flat past either end) when the hole has
## one, else an S-curve from the tee height to the green height.
func hole_datum(hole: Hole, along: float) -> float:
	var prof := hole.profile
	var n := prof.size()
	if n == 0:
		var len_m := hole.length_yd / ShotSetup.YARDS_PER_METER
		var t := clampf(along / maxf(len_m, 1.0), 0.0, 1.0)
		return lerpf(hole.tee_h, hole.green_h, smoothstep(0.0, 1.0, t))
	if along <= prof[0].x:
		return hole.tee_h + prof[0].y * PROFILE_SCALE
	if along >= prof[n - 1].x:
		# carry the final grade a little way past the green centre, then hold
		var m_end := (prof[n - 1].y - prof[n - 2].y) / maxf(prof[n - 1].x - prof[n - 2].x, 1.0) if n >= 2 else 0.0
		var extra := minf(along - prof[n - 1].x, 40.0)
		return hole.tee_h + (prof[n - 1].y + m_end * extra) * PROFILE_SCALE
	var k := 0
	while k < n - 2 and along >= prof[k + 1].x:
		k += 1
	var p1 := prof[k]
	var p2 := prof[k + 1]
	var h := p2.x - p1.x
	var t := (along - p1.x) / h
	# finite-difference tangents (one-sided at the ends), non-uniform spacing
	var m1 := (p2.y - prof[k - 1].y) / (p2.x - prof[k - 1].x) if k > 0 else (p2.y - p1.y) / h
	var m2 := (prof[k + 2].y - p1.y) / (prof[k + 2].x - p1.x) if k + 2 < n else (p2.y - p1.y) / h
	var t2 := t * t
	var t3 := t2 * t
	var y := (2.0 * t3 - 3.0 * t2 + 1.0) * p1.y + (t3 - 2.0 * t2 + t) * h * m1 + (-2.0 * t3 + 3.0 * t2) * p2.y + (t3 - t2) * h * m2
	return hole.tee_h + y * PROFILE_SCALE


# ---- elevation datum ----------------------------------------------------------
## Coarse grid of the course's macro elevation: every hole is assigned a tee height
## (each tee continues from the previous green) and its profile along the routing; the
## field between holes is an inverse distance blend of the centreline heights. Noise
## is layered on top of this.

const DATUM_CELL := 8.0
const DATUM_SAMPLE_STEP := 20.0  # metres between centreline samples
var datum_grid := PackedFloat32Array()
var datum_nx := 0
var datum_nz := 0


func build_datum() -> void:
	var h := 0.0
	for hole in holes:
		hole.tee_h = h
		if hole.profile.is_empty():
			hole.green_h = h
		else:
			var end_x := hole.profile[hole.profile.size() - 1].x
			hole.green_h = hole_datum(hole, end_x)
			var grade := absf(hole_datum(hole, end_x + 10.0) - hole.green_h) / 10.0
			hole.green_grade_scale = clampf(GREEN_MAX_GRADE / maxf(grade, 0.0001), 0.0, 1.0)
		h = hole.green_h
	# sample points along every centreline
	var pts: Array[Vector3] = []
	for hole in holes:
		var acc := 0.0
		for i in range(hole.waypoints.size()):
			var wp := hole.waypoints[i]
			pts.append(Vector3(wp.x, wp.z, hole_datum(hole, acc)))
			if i + 1 < hole.waypoints.size():
				var seg := hole.waypoints[i + 1] - hole.waypoints[i]
				var seg_len := seg.length()
				var steps := int(seg_len / DATUM_SAMPLE_STEP)
				for s in range(1, steps + 1):
					var f := float(s) / (steps + 1)
					var p := hole.waypoints[i] + seg * f
					pts.append(Vector3(p.x, p.z, hole_datum(hole, acc + seg_len * f)))
				acc += seg_len
	datum_nx = int(ceil(bounds.size.x / DATUM_CELL)) + 2
	datum_nz = int(ceil(bounds.size.y / DATUM_CELL)) + 2
	datum_grid.resize(datum_nx * datum_nz)
	if pts.is_empty():
		datum_grid.fill(0.0)
		return
	# Bucket the samples on a coarse grid so each cell only visits nearby ones; far
	# samples contribute ~nothing under the 1/(d^2+2500)^2 kernel anyway.
	const BUCKET := 160.0
	var bnx := int(ceil(bounds.size.x / BUCKET)) + 1
	var bnz := int(ceil(bounds.size.y / BUCKET)) + 1
	var buckets: Array = []
	buckets.resize(bnx * bnz)
	for q in pts:
		var bx := clampi(int((q.x - bounds.position.x) / BUCKET), 0, bnx - 1)
		var bz := clampi(int((q.y - bounds.position.y) / BUCKET), 0, bnz - 1)
		if buckets[bx + bz * bnx] == null:
			buckets[bx + bz * bnx] = []
		buckets[bx + bz * bnx].append(q)
	for iz in range(datum_nz):
		var z := bounds.position.y + iz * DATUM_CELL
		var bz := clampi(int((z - bounds.position.y) / BUCKET), 0, bnz - 1)
		for ix in range(datum_nx):
			var x := bounds.position.x + ix * DATUM_CELL
			var bx := clampi(int((x - bounds.position.x) / BUCKET), 0, bnx - 1)
			var wsum := 0.0
			var hsum := 0.0
			var reach := 1
			while wsum == 0.0:
				for jz in range(maxi(bz - reach, 0), mini(bz + reach, bnz - 1) + 1):
					for jx in range(maxi(bx - reach, 0), mini(bx + reach, bnx - 1) + 1):
						var bucket = buckets[jx + jz * bnx]
						if bucket == null:
							continue
						for q in bucket:
							var d2: float = (q.x - x) * (q.x - x) + (q.y - z) * (q.y - z)
							var w := 1.0 / (d2 + 2500.0)
							w *= w
							wsum += w
							hsum += w * q.z
				reach += 2
			datum_grid[iz * datum_nx + ix] = hsum / wsum


## Bilinear datum height (0 before build_datum).
func _datum(x: float, z: float) -> float:
	if datum_nx < 2 or datum_nz < 2:
		return 0.0
	var fx := clampf((x - bounds.position.x) / DATUM_CELL, 0.0, datum_nx - 1.001)
	var fz := clampf((z - bounds.position.y) / DATUM_CELL, 0.0, datum_nz - 1.001)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var h00 := datum_grid[iz * datum_nx + ix]
	var h10 := datum_grid[iz * datum_nx + ix + 1]
	var h01 := datum_grid[(iz + 1) * datum_nx + ix]
	var h11 := datum_grid[(iz + 1) * datum_nx + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Undisturbed rolling terrain before fairways/greens/excavations are shaped.
func _raw_height(x: float, z: float) -> float:
	return _datum(x, z) + noise.get_noise_2d(x, z) * terrain_amplitude + hills_noise.get_noise_2d(x, z) * terrain_hills + detail_noise.get_noise_2d(x, z) * terrain_detail


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.35
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func in_bounds(x: float, z: float) -> bool:
	return bounds.has_point(Vector2(x, z))


# ---- sample cache -------------------------------------------------------------
## A regular grid of surface id, height, along-hole distance and distance-to-turf so
## terrain, props and grass can sample arrays instead of re-running the geometry queries.

var cache_cell := 0.0
var cache_nx := 0
var cache_nz := 0
var cache_surface := PackedByteArray()
var cache_height := PackedFloat32Array()
var cache_along := PackedFloat32Array()
var cache_turf := PackedFloat32Array()  # signed distance to mown turf (fairway/tee/green), negative inside
var cache_green := PackedFloat32Array()  # signed distance to the nearest green


## Sampling the whole course (~660k cells at 2 m) is the dominant load-time cost and
## single-threaded GDScript is the only option that scales (worker threads contend on
## engine locks and end up slower), so `full = false` only allocates: the course then
## bakes each hole's region on demand with `ensure_cache_rect`, the same way terrain,
## props and grass are already streamed per hole. Unbaked cells read as far rough at
## height 0.
var _baked_rects: Array[Rect2] = []


func build_cache(cell: float = 2.0, full: bool = true) -> void:
	cache_cell = cell
	cache_nx = int(ceil(bounds.size.x / cell)) + 1
	cache_nz = int(ceil(bounds.size.y / cell)) + 1
	var n := cache_nx * cache_nz
	cache_surface.resize(n)
	cache_surface.fill(PhysicsEnums.SurfaceType.ROUGH)
	cache_height.resize(n)
	cache_height.fill(0.0)
	cache_along.resize(n)
	cache_along.fill(0.0)
	cache_turf.resize(n)
	cache_turf.fill(1.0e9)
	cache_green.resize(n)
	cache_green.fill(1.0e9)
	_baked_rects.clear()
	if full:
		ensure_cache_rect(bounds)
	else:
		_build_sdf_texture()


## Bake `rect` if no earlier bake already covers it. Returns true when work was done.
func ensure_cache_rect(rect: Rect2) -> bool:
	var r := rect.intersection(bounds)
	for done in _baked_rects:
		if done.encloses(r):
			return false
	update_cache_rect(r)
	_baked_rects.append(r)
	return true


## One cache cell: [surface, height, along, turf_distance]. Runs the hole geometry once.
func _cache_sample(xz: Vector2) -> Array:
	var fds := _hole_fds(xz)
	var s := surface_from(xz, fds)
	var base := base_height_from(xz.x, xz.y, fds)
	var h := base + excavation_offset(base, xz)
	var best := 1.0e9
	var along := 0.0
	for i in range(holes.size()):
		if fds[i] == null:
			continue
		var d: float = fds[i][4]
		if d < best:
			best = d
			along = fds[i][1]
	return [s, h, along, turf_sd_from(fds), green_sd_from(fds)]


func has_cache() -> bool:
	return cache_nx > 0


func _cache_index(xz: Vector2) -> int:
	var ix := clampi(int(round((xz.x - bounds.position.x) / cache_cell)), 0, cache_nx - 1)
	var iz := clampi(int(round((xz.y - bounds.position.y) / cache_cell)), 0, cache_nz - 1)
	return iz * cache_nx + ix


func cached_surface(xz: Vector2) -> int:
	if cache_nx == 0:
		return surface_at(xz)
	return cache_surface[_cache_index(xz)]


func cached_turf(xz: Vector2) -> float:
	if cache_nx == 0:
		return 1.0e9
	return cache_turf[_cache_index(xz)]


## Bilinear signed distances [turf, green] from the cache: interpolating a distance
## field reproduces the outline between cells, so consumers can resample it at any
## resolution without staircase edges.
func cached_sdf(x: float, z: float) -> Vector2:
	if cache_nx < 2 or cache_nz < 2:
		return Vector2(1.0e9, 1.0e9)
	var fx := (x - bounds.position.x) / cache_cell
	var fz := (z - bounds.position.y) / cache_cell
	var ix := clampi(int(floor(fx)), 0, cache_nx - 2)
	var iz := clampi(int(floor(fz)), 0, cache_nz - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var i00 := iz * cache_nx + ix
	var i01 := i00 + cache_nx
	var t := lerpf(lerpf(cache_turf[i00], cache_turf[i00 + 1], tx), lerpf(cache_turf[i01], cache_turf[i01 + 1], tx), tz)
	var g := lerpf(lerpf(cache_green[i00], cache_green[i00 + 1], tx), lerpf(cache_green[i01], cache_green[i01 + 1], tx), tz)
	return Vector2(t, g)


## Encode a signed distance into 0..1 for an 8-bit texture (SDF_RANGE metres each side).
const SDF_RANGE := 8.0
static func encode_sdf(sd: float) -> float:
	return clampf(0.5 - sd / (SDF_RANGE * 2.0), 0.0, 1.0)


## RG8 texture at the cache resolution: R = turf SDF, G = green SDF (encoded).
var sdf_image: Image
var sdf_texture: ImageTexture


func _build_sdf_texture() -> void:
	var data := PackedByteArray()
	data.resize(cache_nx * cache_nz * 2)
	for i in range(cache_nx * cache_nz):
		data[i * 2] = int(encode_sdf(cache_turf[i]) * 255.0)
		data[i * 2 + 1] = int(encode_sdf(cache_green[i]) * 255.0)
	sdf_image = Image.create_from_data(cache_nx, cache_nz, false, Image.FORMAT_RG8, data)
	if sdf_texture == null:
		sdf_texture = ImageTexture.create_from_image(sdf_image)
	else:
		sdf_texture.set_image(sdf_image)


## World size covered by the SDF texture (its pixel grid starts at bounds.position).
func sdf_texture_size() -> Vector2:
	return Vector2(cache_nx, cache_nz) * cache_cell


func cached_along(xz: Vector2) -> float:
	if cache_nx == 0:
		return 0.0
	return cache_along[_cache_index(xz)]


## Bilinear height from the cache (falls back to the exact query).
func cached_height(x: float, z: float) -> float:
	if cache_nx < 2 or cache_nz < 2:
		return height_at(x, z)
	var fx := (x - bounds.position.x) / cache_cell
	var fz := (z - bounds.position.y) / cache_cell
	var ix := clampi(int(floor(fx)), 0, cache_nx - 2)
	var iz := clampi(int(floor(fz)), 0, cache_nz - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var h00 := cache_height[iz * cache_nx + ix]
	var h10 := cache_height[iz * cache_nx + ix + 1]
	var h01 := cache_height[(iz + 1) * cache_nx + ix]
	var h11 := cache_height[(iz + 1) * cache_nx + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func cached_normal(x: float, z: float) -> Vector3:
	var e := maxf(cache_cell, 0.5)
	var hl := cached_height(x - e, z)
	var hr := cached_height(x + e, z)
	var hd := cached_height(x, z - e)
	var hu := cached_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


# ---- feature mask -------------------------------------------------------------
## 1 m RGBA8 image over the bounds holding *encoded signed distances* (see encode_sdf):
## R = sand, G = green, B = tee, A = water. Shaders decode the distance and apply their
## own anti-aliased edge, so outlines are smooth curves regardless of the terrain grid.
## Only the cells within SDF_RANGE of each feature are touched.

const MASK_CELL := 1.0
var mask_image: Image
var mask_texture: ImageTexture


func build_feature_mask() -> void:
	var w := int(ceil(bounds.size.x / MASK_CELL)) + 1
	var h := int(ceil(bounds.size.y / MASK_CELL)) + 1
	mask_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color(0, 0, 0, 0))
	_paint_mask_rect(bounds)
	mask_texture = ImageTexture.create_from_image(mask_image)


## Repaint the mask inside `rect` (after a dig) and push it to the GPU.
func update_feature_mask_rect(rect: Rect2) -> void:
	if mask_image == null:
		return
	_paint_mask_rect(rect.grow(SDF_RANGE + 1.0))
	mask_texture.update(mask_image)


func _mask_cell_range(rect: Rect2) -> Array:
	var r := rect.intersection(bounds)
	var x0 := clampi(int(floor((r.position.x - bounds.position.x) / MASK_CELL)), 0, mask_image.get_width() - 1)
	var z0 := clampi(int(floor((r.position.y - bounds.position.y) / MASK_CELL)), 0, mask_image.get_height() - 1)
	var x1 := clampi(int(ceil((r.end.x - bounds.position.x) / MASK_CELL)), 0, mask_image.get_width() - 1)
	var z1 := clampi(int(ceil((r.end.y - bounds.position.y) / MASK_CELL)), 0, mask_image.get_height() - 1)
	return [x0, z0, x1, z1]


func _paint_mask_rect(rect: Rect2) -> void:
	_ensure_areas()
	# clear the area first (0 = far outside every feature)
	var rr := _mask_cell_range(rect)
	for z in range(rr[1], rr[3] + 1):
		for x in range(rr[0], rr[2] + 1):
			mask_image.set_pixel(x, z, Color(0, 0, 0, 0))
	for gr in greens:
		var gb := gr.bounds.grow(SDF_RANGE)
		if gb.intersects(rect):
			_paint_area(gb.intersection(rect), gr, 1)
	for te in tees:
		var tb := te.bounds.grow(SDF_RANGE)
		if tb.intersects(rect):
			_paint_area(tb.intersection(rect), te, 2)
	for b in bunkers:
		var bb: Rect2 = b.bounds.grow(SDF_RANGE)
		if bb.intersects(rect):
			_paint_area(bb.intersection(rect), b, 0)
	for hz in water_hazards:
		var hb: Rect2 = hz.bounds.grow(SDF_RANGE)
		if hb.intersects(rect):
			_paint_area(hb.intersection(rect), hz, 3)


func _mask_write(x: int, z: int, channel: int, v: float) -> void:
	var c := mask_image.get_pixel(x, z)
	match channel:
		0:
			c.r = maxf(c.r, v)
		1:
			c.g = maxf(c.g, v)
		2:
			c.b = maxf(c.b, v)
		_:
			c.a = maxf(c.a, v)
	mask_image.set_pixel(x, z, c)


func _paint_area(rect: Rect2, area, channel: int) -> void:
	var rr := _mask_cell_range(rect)
	for z in range(rr[1], rr[3] + 1):
		for x in range(rr[0], rr[2] + 1):
			var p := Vector2(bounds.position.x + x * MASK_CELL, bounds.position.y + z * MASK_CELL)
			var v := encode_sdf(area.signed_distance(p))
			if v > 0.0:
				_mask_write(x, z, channel, v)


func _paint_circle(rect: Rect2, c: Vector2, radius: float, channel: int) -> void:
	var rr := _mask_cell_range(rect)
	for z in range(rr[1], rr[3] + 1):
		for x in range(rr[0], rr[2] + 1):
			var p := Vector2(bounds.position.x + x * MASK_CELL, bounds.position.y + z * MASK_CELL)
			var v := encode_sdf(p.distance_to(c) - radius)
			if v > 0.0:
				_mask_write(x, z, channel, v)


func _paint_box(rect: Rect2, c: Vector2, half: Vector2, channel: int) -> void:
	var rr := _mask_cell_range(rect)
	for z in range(rr[1], rr[3] + 1):
		for x in range(rr[0], rr[2] + 1):
			var p := Vector2(bounds.position.x + x * MASK_CELL, bounds.position.y + z * MASK_CELL)
			var d := maxf(absf(p.x - c.x) - half.x, absf(p.y - c.y) - half.y)
			var v := encode_sdf(d)
			if v > 0.0:
				_mask_write(x, z, channel, v)


# ---- water hazards ------------------------------------------------------------

## The hazard whose polygon contains `xz`, or null.
func hazard_at(xz: Vector2) -> WaterHazard:
	for hz in water_hazards:
		if hz.contains(xz):
			return hz
	return null


## True if any hazard outline is within `margin` metres of `xz`.
func hazard_near(xz: Vector2, margin: float) -> bool:
	for hz in water_hazards:
		if not hz.bounds.grow(margin).has_point(xz):
			continue
		if hz.signed_distance(xz) < margin:
			return true
	return false


## Sum of all excavation (pond bed/bank + bunker floor/lip) offsets at `xz`.
func excavation_offset(base_h: float, xz: Vector2) -> float:
	var off := 0.0
	for hz in water_hazards:
		off += hz.depth_offset(base_h, xz)
	for b in bunkers:
		off += b.depth_offset(base_h, xz)
	return off


func water_depth_offset(base_h: float, xz: Vector2) -> float:
	return excavation_offset(base_h, xz)


## The bunker whose polygon contains `xz`, or null.
func bunker_at(xz: Vector2) -> Bunker:
	for b in bunkers:
		if b.contains(xz):
			return b
	return null


func bunker_near(xz: Vector2, margin: float) -> bool:
	for b in bunkers:
		if not b.bounds.grow(margin).has_point(xz):
			continue
		if b.signed_distance(xz) < margin:
			return true
	return false


## World rect -> inclusive cache-grid index range [ix0, iz0, ix1, iz1].
func cache_index_range(rect: Rect2) -> Array:
	var r := rect.intersection(bounds)
	var ix0 := clampi(int(floor((r.position.x - bounds.position.x) / cache_cell)), 0, cache_nx - 1)
	var iz0 := clampi(int(floor((r.position.y - bounds.position.y) / cache_cell)), 0, cache_nz - 1)
	var ix1 := clampi(int(ceil((r.end.x - bounds.position.x) / cache_cell)), 0, cache_nx - 1)
	var iz1 := clampi(int(ceil((r.end.y - bounds.position.y) / cache_cell)), 0, cache_nz - 1)
	return [ix0, iz0, ix1, iz1]


## Recompute the cache cells inside `rect` (after digging). Cheap: only the touched cells.
func update_cache_rect(rect: Rect2) -> void:
	if cache_nx == 0:
		return
	var r := rect.grow(cache_cell)
	var ix0 := clampi(int(floor((r.position.x - bounds.position.x) / cache_cell)), 0, cache_nx - 1)
	var iz0 := clampi(int(floor((r.position.y - bounds.position.y) / cache_cell)), 0, cache_nz - 1)
	var ix1 := clampi(int(ceil((r.end.x - bounds.position.x) / cache_cell)), 0, cache_nx - 1)
	var iz1 := clampi(int(ceil((r.end.y - bounds.position.y) / cache_cell)), 0, cache_nz - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var i := iz * cache_nx + ix
			var smp := _cache_sample(Vector2(bounds.position.x + ix * cache_cell, bounds.position.y + iz * cache_cell))
			cache_surface[i] = smp[0]
			cache_height[i] = smp[1]
			cache_along[i] = smp[2]
			cache_turf[i] = smp[3]
			cache_green[i] = smp[4]
	_build_sdf_texture()


## Can a hazard of radius `r` be centred at `xz`? Anywhere inside the bounds.
func hazard_site_ok(xz: Vector2, r: float) -> bool:
	return bounds.grow(-r).has_point(xz)


func water_floats_on_surface() -> bool:
	return false


const WATER_LEVEL := -0.85
