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
	if w < MIN_WIDTH:
		return d + 10.0  # no mown turf on this stretch: always rough
	var sd := d - w - CourseArea.wobble(p, wobble_amp, wobble_freq, hole_index)
	for isl in islands:
		var r: float = isl[2]
		var dd := CourseArea.dist_to_segment(p, isl[0], isl[1])
		if dd < r + 8.0:
			sd = maxf(sd, r - dd + CourseArea.wobble(p, 2.0, 0.08, hole_index + 90))
	return sd


func length_m() -> float:
	return _length
