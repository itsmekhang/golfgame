class_name GreenArea
extends CourseArea
## Putting green: a circle whose radius is modulated by two low harmonics (kidney /
## pear shapes) plus a small noise wobble. The fringe is the collar
## `CourseLayout.FRINGE_WIDTH` outside this outline.

var center: Vector2 = Vector2.ZERO
var radius: float = 12.0
var h2: float = 0.12  # second-harmonic amplitude (elongation)
var h3: float = 0.07  # third-harmonic amplitude (lobes)
var p2: float = 0.0
var p3: float = 0.0
var wobble_amp: float = 0.8
## Traced outline: radius per angle bin, bin 0 at world angle `radial_rotation`.
var radial: PackedFloat32Array = PackedFloat32Array()
var radial_rotation: float = 0.0


func setup_radial(p_center: Vector2, p_radial: PackedFloat32Array, p_rotation: float, p_hole: int) -> void:
	center = p_center
	radial = p_radial
	radial_rotation = p_rotation
	hole_index = p_hole
	kind = PhysicsEnums.SurfaceType.GREEN
	wobble_amp = 0.35
	var rmax := 0.0
	var rsum := 0.0
	for r in radial:
		rmax = maxf(rmax, r)
		rsum += r
	radius = rsum / maxf(radial.size(), 1)
	var outer := rmax + wobble_amp + CourseLayout.FRINGE_WIDTH + 2.0
	bounds = Rect2(center - Vector2.ONE * outer, Vector2.ONE * outer * 2.0)


func setup(p_center: Vector2, p_radius: float, p_hole: int, rng: RandomNumberGenerator, approach_dir: Vector2 = Vector2.ZERO) -> void:
	center = p_center
	radius = p_radius
	hole_index = p_hole
	kind = PhysicsEnums.SurfaceType.GREEN
	h2 = rng.randf_range(0.08, 0.16)
	h3 = rng.randf_range(0.04, 0.09)
	# elongate roughly along the approach so the green reads as "deep" from the fairway
	p2 = (atan2(approach_dir.y, approach_dir.x) * 2.0 if approach_dir != Vector2.ZERO else 0.0) + rng.randf_range(-0.6, 0.6)
	p3 = rng.randf_range(0.0, TAU)
	var outer := radius * (1.0 + h2 + h3) + wobble_amp + CourseLayout.FRINGE_WIDTH + 2.0
	bounds = Rect2(center - Vector2.ONE * outer, Vector2.ONE * outer * 2.0)


func radius_at(angle: float) -> float:
	if radial.is_empty():
		return radius * (1.0 + h2 * sin(2.0 * angle + p2) + h3 * sin(3.0 * angle + p3))
	var n := radial.size()
	var f := fposmod(angle - radial_rotation, TAU) / TAU * n
	var i := int(f) % n
	return lerpf(radial[i], radial[(i + 1) % n], f - int(f))


func signed_distance(p: Vector2) -> float:
	var v := p - center
	var ang := atan2(v.y, v.x)
	return v.length() - radius_at(ang) - CourseArea.wobble(p, wobble_amp, 0.09, hole_index + 40)
