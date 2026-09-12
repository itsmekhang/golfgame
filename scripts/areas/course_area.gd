class_name CourseArea
extends RefCounted
## Base class for every playing area of the course: fairway, green, tee, rough.
## (Bunkers and water hazards are dug into the terrain, so they live in `Excavation`
## instead, but they expose the same `signed_distance` / `bounds` / `kind` interface.)
##
## An area is a *signed distance field*, not a polygon: `signed_distance(p)` is negative
## inside, positive outside, in metres. Everything downstream (lie classification,
## the splat/feature masks, the terrain shaders) samples that field and converts it to
## coverage with a smoothstep, so edges are anti-aliased curves at any resolution and
## never follow the terrain grid. Straight polygon sides are avoided by building the
## distance from smooth primitives (capsules, harmonically-modulated circles, rounded
## boxes) and by adding a low-frequency noise wobble to the outline.

var kind: int = PhysicsEnums.SurfaceType.ROUGH  # CourseLayout surface code (Excavation calls this surface_kind)
var area_name: String = "Area"
var hole_index: int = -1
var bounds: Rect2 = Rect2()  # world XZ box outside of which signed_distance() is far


## Signed distance to the outline (metres, negative inside). Override.
func signed_distance(_p: Vector2) -> float:
	return 1.0e9


## Coverage 0..1 with an anti-aliased edge `soft` metres wide, centred on the outline.
func coverage(p: Vector2, soft: float = 1.0) -> float:
	return clampf(0.5 - signed_distance(p) / maxf(soft, 0.001), 0.0, 1.0)


func contains(p: Vector2) -> bool:
	return bounds.has_point(p) and signed_distance(p) < 0.0


## Shared outline wobble: a smooth noise field in metres that every turf area adds to
## its distance, so fairway/green edges meander instead of running straight.
## One FastNoiseLite per frequency (never re-tuned after creation) so the bake can call
## this from worker threads: get_noise_2d is a pure read.
static var _wobble_noises: Dictionary = {}
static var _wobble_lock := Mutex.new()


static func wobble(p: Vector2, amplitude: float, frequency: float = 0.035, seed_offset: int = 0) -> float:
	var n: FastNoiseLite = _wobble_noises.get(frequency)
	if n == null:
		_wobble_lock.lock()
		n = _wobble_noises.get(frequency)
		if n == null:
			n = FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.fractal_octaves = 2
			n.seed = 9001
			n.frequency = frequency
			_wobble_noises[frequency] = n
		_wobble_lock.unlock()
	return n.get_noise_2d(p.x + seed_offset * 173.0, p.y - seed_offset * 91.0) * amplitude


static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
