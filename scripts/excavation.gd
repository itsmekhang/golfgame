class_name Excavation
extends Node3D
## Base class for anything dug into the terrain: a polygon in world XZ, a bounds box,
## a signed distance to the outline, and a height profile (`depth_offset`) that the
## course layout adds to the base terrain. `WaterHazard` and `Bunker` extend this.

var feature_name: String = "Excavation"
var surface_kind: int = PhysicsEnums.SurfaceType.ROUGH  # CourseLayout surface code (Bunker / WaterHazard set it)
var area_name: String:
	get:
		return feature_name
var polygon: PackedVector2Array = PackedVector2Array()  # world XZ, counter-clockwise
var center: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2()
var shore_width: float = 3.0  # metres of blending outside the polygon
var finalized: bool = false

# Consecutive outline segments share small bounds. Rejecting whole groups makes
# dense creek outlines cheap to sample without simplifying their shape.
const DISTANCE_GROUP_SIZE := 16
var _distance_groups: Array[Rect2] = []


# ---- polygon factories --------------------------------------------------------

## Irregular blob outline: radius modulated by two low-frequency waves plus jitter.
static func blob_polygon(p_center: Vector2, radius: float, rng: RandomNumberGenerator,
		aspect: float = 1.0, rotation_rad: float = 0.0, vertex_count: int = 20,
		wobble: float = 1.0) -> PackedVector2Array:
	var phase1 := rng.randf_range(0.0, TAU)
	var phase2 := rng.randf_range(0.0, TAU)
	var w1 := rng.randf_range(0.15, 0.35) * wobble
	var w2 := rng.randf_range(0.05, 0.2) * wobble
	var pts := PackedVector2Array()
	for i in range(vertex_count):
		var a := TAU * i / vertex_count
		var r := radius * (1.0 + w1 * sin(3.0 * a + phase1) + w2 * sin(5.0 * a + phase2) + rng.randf_range(-0.06, 0.06) * wobble)
		var local := Vector2(cos(a) * r * aspect, sin(a) * r)
		pts.append(p_center + local.rotated(rotation_rad))
	return ensure_ccw(smooth_polygon(pts, 2))


## Chaikin corner cutting on a closed polygon: each pass replaces every vertex by two
## points at 1/4 and 3/4 of its edges, converging on a smooth curve.
static func smooth_polygon(pts: PackedVector2Array, iterations: int = 2) -> PackedVector2Array:
	var cur := pts
	for _k in range(iterations):
		var out := PackedVector2Array()
		var n := cur.size()
		for i in range(n):
			var a := cur[i]
			var b := cur[(i + 1) % n]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		cur = out
	return cur


## Signed area in the (x, z) plane; positive = counter-clockwise = front face up.
static func signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(pts.size()):
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func ensure_ccw(pts: PackedVector2Array) -> PackedVector2Array:
	if signed_area(pts) < 0.0:
		var out := PackedVector2Array()
		for i in range(pts.size() - 1, -1, -1):
			out.append(pts[i])
		return out
	return pts


static func centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


func set_polygon(pts: PackedVector2Array) -> void:
	polygon = ensure_ccw(pts)
	center = centroid(polygon)
	_update_bounds()


func _update_bounds() -> void:
	_distance_groups.clear()
	if polygon.is_empty():
		bounds = Rect2()
		return
	bounds = Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	bounds = bounds.grow(shore_width + 0.5)
	for start in range(0, polygon.size(), DISTANCE_GROUP_SIZE):
		var group := Rect2(polygon[start], Vector2.ZERO)
		for i in range(start, mini(start + DISTANCE_GROUP_SIZE, polygon.size())):
			group = group.expand(polygon[(i + 1) % polygon.size()])
		_distance_groups.append(group)


# ---- geometry -----------------------------------------------------------------

## Compute levels from the layout's undisturbed terrain. Subclasses extend this.
func finalize(layout: CourseLayout) -> void:
	_update_bounds()
	name = feature_name.replace(" ", "")
	finalized = true


func contains(xz: Vector2) -> bool:
	if not bounds.has_point(xz):
		return false
	return Geometry2D.is_point_in_polygon(xz, polygon)


## Distance to the polygon outline; negative inside.
func signed_distance(xz: Vector2) -> float:
	var best := INF
	var n := polygon.size()
	for group_index in range(_distance_groups.size()):
		var group := _distance_groups[group_index]
		var dx := maxf(maxf(group.position.x - xz.x, xz.x - group.end.x), 0.0)
		var dy := maxf(maxf(group.position.y - xz.y, xz.y - group.end.y), 0.0)
		if dx * dx + dy * dy > best:
			continue
		var start := group_index * DISTANCE_GROUP_SIZE
		for i in range(start, mini(start + DISTANCE_GROUP_SIZE, n)):
			var a := polygon[i]
			var b := polygon[(i + 1) % n]
			var d := Geometry2D.get_closest_point_to_segment(xz, a, b).distance_squared_to(xz)
			best = minf(best, d)
	var distance := sqrt(best)
	return -distance if Geometry2D.is_point_in_polygon(xz, polygon) else distance


## Height change applied to the base terrain at `xz`. 0 outside the shore. Override.
func depth_offset(_base_h: float, _xz: Vector2) -> float:
	return 0.0


## A point guaranteed to be inside the polygon, and well inside it: the centroid when
## that lies inside, else the centroid of the largest triangle of the polygon's
## triangulation (a lobed outline's centroid can fall in a notch).
func inside_point() -> Vector2:
	if contains(center) and signed_distance(center) < -1.0:
		return center
	var idx := Geometry2D.triangulate_polygon(polygon)
	var best := center
	var best_area := -1.0
	for i in range(0, idx.size() - 2, 3):
		var a := polygon[idx[i]]
		var b := polygon[idx[i + 1]]
		var c := polygon[idx[i + 2]]
		var area := absf((b - a).cross(c - a))
		if area > best_area:
			best_area = area
			best = (a + b + c) / 3.0
	return best


func area_m2() -> float:
	return absf(signed_area(polygon))


## Mean base terrain height around the outline (used for rim/water levels).
func outline_levels(layout: CourseLayout) -> Dictionary:
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for p in polygon:
		var h := layout.base_height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	var hc := layout.base_height_at(center.x, center.y)
	lo = minf(lo, hc)
	hi = maxf(hi, hc)
	return {"min": lo, "max": hi, "mean": sum / maxf(polygon.size(), 1), "center": hc}


func to_dict() -> Dictionary:
	var pts := []
	for p in polygon:
		pts.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return {"name": feature_name, "polygon": pts}
