class_name FairwayArea
extends CourseArea
## Mown fairway: a capsule corridor along the hole's centreline whose width swells at
## the landing zones and whose edge meanders with a noise wobble. The first cut is the
## band `CourseLayout.FIRST_CUT_WIDTH` outside this outline.

var waypoints: PackedVector2Array = PackedVector2Array()  # centreline, tee -> green
var half_width: float = 16.0
var swell: float = 0.22  # fractional width variation along the hole
var swell_period: float = 95.0  # metres between wide spots
var wobble_amp: float = 3.0  # metres of edge meander
var wobble_freq: float = 0.03
var phase: float = 0.0
## Traced width: (along, left half width, right half width) every `profile_step` m.
## When set it replaces the swell formula; a sample under MIN_WIDTH means "no fairway
## here" (rough carry, tee corridor).
var profile: PackedVector3Array = PackedVector3Array()
var profile_step: float = 4.0
const MIN_WIDTH := 1.5
var _seg_len: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0
var _extend: float = 0.0  # metres the mown band continues past the last waypoint
## Rough islands cut out of the fairway: [Vector2 a, Vector2 b, radius] capsules,
## wobbled like every edge.
var islands: Array = []
var patches: Array = []  # added fairway capsules, evaluated before the rough cutouts
var cut_zones: Array = []  # PackedVector2Array outlines mown as first cut (see CourseLayout._mown_sd)
var _cut_bounds: Array = []


func setup(pts: PackedVector2Array, p_half_width: float, p_hole: int, rng: RandomNumberGenerator,
		p_profile: PackedVector3Array = PackedVector3Array(), p_step: float = 4.0) -> void:
	waypoints = pts
	half_width = p_half_width
	hole_index = p_hole
	kind = PhysicsEnums.SurfaceType.FAIRWAY
	profile = p_profile
	profile_step = p_step
	phase = rng.randf_range(0.0, TAU)
	swell = rng.randf_range(0.15, 0.28)
	swell_period = rng.randf_range(80.0, 120.0)
	# traced edges already meander; only a little wobble to soften the sampling
	wobble_amp = rng.randf_range(2.2, 3.6) if profile.is_empty() else 1.0
	_seg_len.resize(maxi(pts.size() - 1, 0))
	_length = 0.0
	for i in range(1, pts.size()):
		_seg_len[i - 1] = pts[i - 1].distance_to(pts[i])
		_length += _seg_len[i - 1]
	# a traced profile may run on past the green centre (mown surrounds behind it)
	_extend = maxf(profile[profile.size() - 1].x - _length, 0.0) if not profile.is_empty() else 0.0
	bounds = Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	var reach := half_width * (1.0 + swell)
	for s in profile:
		reach = maxf(reach, maxf(s.y, s.z))
	bounds = bounds.grow(reach + wobble_amp + CourseLayout.FIRST_CUT_WIDTH + 2.0)


## [distance to centreline, along-hole distance, side, along_ext] for `p`; side is +1
## on the golfer's right of the routing, -1 on the left. `along_ext` keeps running past
## the green centre (up to EXTEND_PAST_END m along the final segment's direction) so the
## elevation profile can continue smoothly through and behind the green.
const EXTEND_PAST_END := 60.0

func centreline(p: Vector2) -> Array:
	var best := INF
	var along := 0.0
	var side := 1.0
	var along_ext := 0.0
	var acc := 0.0
	var last := waypoints.size() - 1
	for i in range(1, waypoints.size()):
		var a := waypoints[i - 1]
		var b := waypoints[i]
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.0001)
		var pa := p - a
		var raw := pa.dot(ab) / l2
		var t_max := 1.0 + _extend / _seg_len[i - 1] if i == last else 1.0
		var t := clampf(raw, 0.0, t_max)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			along = acc + t * _seg_len[i - 1]
			along_ext = along
			if i == last and raw > 1.0:
				along_ext = acc + minf(raw * _seg_len[i - 1], _seg_len[i - 1] + EXTEND_PAST_END)
			side = 1.0 if ab.x * pa.y - ab.y * pa.x >= 0.0 else -1.0
		acc += _seg_len[i - 1]
	return [best, along, side, along_ext]


## Distance down the hole for the mowing stripes. centreline()'s nearest-point `along` jumps
## across the bisector on the inside of every bend (and stalls in a wedge on the outside),
## which tore the stripe bands apart on doglegs. Here every segment's own unclamped
## projection is blended by how much farther the point is from that segment than from the
## nearest one, so the value runs smoothly round a bend and the bands fan through it.
const STRIPE_BLEND_M := 15.0

func stripe_along(p: Vector2) -> float:
	var n := waypoints.size() - 1
	if n < 1:
		return 0.0
	var dists := PackedFloat32Array()
	var alongs := PackedFloat32Array()
	dists.resize(n)
	alongs.resize(n)
	var nearest := INF
	var acc := 0.0
	for i in range(1, n + 1):
		var a := waypoints[i - 1]
		var ab := waypoints[i] - a
		var raw := (p - a).dot(ab) / maxf(ab.length_squared(), 0.0001)
		var seg := ab.length()
		dists[i - 1] = p.distance_to(a + ab * clampf(raw, 0.0, 1.0))
		alongs[i - 1] = acc + raw * seg
		nearest = minf(nearest, dists[i - 1])
		acc += seg
	var sum := 0.0
	var weight := 0.0
	for i in range(n):
		var w := exp(-(dists[i] - nearest) / STRIPE_BLEND_M)
		sum += alongs[i] * w
		weight += w
	return sum / weight


## Local half width on one side of the routing (`side` +1 right / -1 left). Generic
## holes: narrow off the tee, swelling in the landing zones. Traced holes: the profile.
func width_at(along: float, side: float = 1.0) -> float:
	if profile.is_empty():
		var w := half_width * (1.0 + swell * sin(along / swell_period * TAU + phase))
		# opens out from the tee over the first 40 m
		return w * (0.55 + 0.45 * smoothstep(0.0, 40.0, along))
	var f := clampf(along / profile_step, 0.0, profile.size() - 1.001)
	var i := int(f)
	var t := f - i
	var a := profile[i]
	var b := profile[i + 1]
	return lerpf(a.y, b.y, t) if side < 0.0 else lerpf(a.z, b.z, t)


func signed_distance(p: Vector2) -> float:
	var cl := centreline(p)
	return signed_distance_from(p, cl)


## Signed distance when the centreline query is already known (see CourseLayout cache).
func signed_distance_from(p: Vector2, cl: Array) -> float:
	var d: float = cl[0]
	var along: float = cl[1]
	var w := width_at(along, cl[2] if cl.size() > 2 else 1.0)
	var sd := d + 10.0  # an unmown routing stretch may still have a separate fairway patch
	if w >= MIN_WIDTH:
		sd = d - w - CourseArea.wobble(p, wobble_amp, wobble_freq, hole_index)
	for patch in patches:
		sd = minf(sd, CourseArea.dist_to_segment(p, patch[0], patch[1]) - float(patch[2]))
	for isl in islands:
		var r: float = isl[2]
		var dd := CourseArea.dist_to_segment(p, isl[0], isl[1])
		if dd < r + 12.0:
			sd = maxf(sd, r - dd + island_wobble(p, isl))
	return sd


func length_m() -> float:
	return _length


## How far an island's edge pushes out (+) or in (-) at `p`: a fine 2 m ripple, plus -- on
## tree islands -- broad lobes that scale with the island, so no two read as the same smooth
## oval. Treeless side cuts that shape a fairway edge keep just the ripple.
func island_wobble(p: Vector2, isl: Array) -> float:
	var w := CourseArea.wobble(p, 2.0, 0.08, hole_index + 90)
	if is_tree_island(isl):
		w += CourseArea.wobble(p, clampf(float(isl[2]) * 0.32, 1.5, 7.0), 0.03, hole_index + 133)
	return w


## Signed distance to the nearest first-cut zone outline (negative inside); 1e9 when far away.
func cut_zone_distance(p: Vector2) -> float:
	if cut_zones.is_empty():
		return 1.0e9
	if _cut_bounds.size() != cut_zones.size():
		_cut_bounds.clear()
		for z in cut_zones:
			var r := Rect2(z[0], Vector2.ZERO)
			for q in z:
				r = r.expand(q)
			_cut_bounds.append(r.grow(10.0))
	var sd := 1.0e9
	for k in range(cut_zones.size()):
		if not (_cut_bounds[k] as Rect2).has_point(p):
			continue
		var poly: PackedVector2Array = cut_zones[k]
		var d := 1.0e9
		for i in range(poly.size()):
			d = minf(d, CourseArea.dist_to_segment(p, poly[i], poly[(i + 1) % poly.size()]))
		sd = minf(sd, -d if Geometry2D.is_point_in_polygon(p, poly) else d)
	return sd


## True when island `isl` is a tree island: rough straight off the fairway, no first cut.
## Optional fifth value overrides; by default every tree-bearing (vegetated) island is one,
## while treeless side-rough cutouts keep the usual first-cut band.
static func is_tree_island(isl: Array) -> bool:
	if isl.size() > 4:
		return bool(isl[4])
	return isl.size() < 4 or bool(isl[3])


## Signed distance into the tree islands (negative inside), on the same wobbled outline as
## the fairway cutout itself.
func tree_island_distance(p: Vector2) -> float:
	var sd := 1.0e9
	for isl in islands:
		if not is_tree_island(isl):
			continue
		var d := CourseArea.dist_to_segment(p, isl[0], isl[1]) - float(isl[2])
		if d < 12.0:
			sd = minf(sd, d - island_wobble(p, isl))
	return sd


## Tree-bearing cutouts share exactly the fairway cutout's wobbled outline.
## A fourth value of false denotes ordinary treeless side rough instead.
func tree_patch_distance(p: Vector2) -> float:
	var sd := 1.0e9
	for isl in islands:
		if isl.size() > 3 and not bool(isl[3]):
			continue
		var d := CourseArea.dist_to_segment(p, isl[0], isl[1]) - float(isl[2])
		if d < 12.0:
			sd = minf(sd, d - island_wobble(p, isl))
	return sd
