class_name PaintedLayout
extends CourseLayout
## Plays a Course Studio course (PaintedCourse) through the normal game: the painted coverage
## layers become signed-distance fields that stand in for the traced fairway/green/tee shapes,
## bunker, water and woods paint is traced into outlines (Bunker / WaterHazard excavations dig
## themselves in, ForestPlanter grows the woods), and the sculpted height field replaces the
## procedural terrain. Everything downstream -- terrain tiles and shader, grass, forest, lies,
## ball physics -- runs unchanged on top of it.

## Signed distances are only needed near an edge (fringe, first cut, shader blends, tree
## clearances all sit within ~10 m): further away they are clamped to this.
const SD_CLAMP := 14.0
const MIN_BUNKER_M2 := 6.0
const MIN_WATER_M2 := 20.0
const MIN_WOODS_M2 := 60.0
## Painted fairways have no centreline; tree clearance code asks for a half width, and any
## value >= ForestPlanter.CARRY_LANE_HALF keeps its corridor rule "no trunks within 5 m".
const NOMINAL_HALF_WIDTH := 20.0

var course: PaintedCourse
## Each hole's line of play (tee -> bends -> pin) in world XZ.
var routes: Array[PackedVector2Array] = []
## Per hole: [[metres along the route, Vector2 bend], ...] for its dogleg bends, in order.
var bend_alongs: Array = []
var _nx := 0
var _nz := 0
## (along the nearest hole's route, distance from it) on a coarse grid, bilinearly sampled:
## a projection per cache cell would cost holes x route segments every time.
const ALONG_CELL := 4.0
var _along_grid := PackedVector2Array()
var _ag_nx := 0
var _ag_nz := 0
var _fw := PackedFloat32Array()
var _gr := PackedFloat32Array()
var _te := PackedFloat32Array()
var last_build_ms := 0


static func build(c: PaintedCourse) -> PaintedLayout:
	var t0 := Time.get_ticks_msec()
	var L := PaintedLayout.new()
	L.course = c
	L.name_pretty = c.course_name
	L.bounds = c.bounds()
	L.random_trees = false
	L.authored_hazards = true
	L._nx = c.size.x
	L._nz = c.size.y
	var turf := c.layer_a()  # the course's turf with the club's practice turf laid over
	L._fw = _signed_field(turf, 0, c.size.x, c.size.y)
	L._gr = _signed_field(turf, 1, c.size.x, c.size.y)
	L._te = _signed_field(turf, 2, c.size.x, c.size.y)
	var canvas := PackedVector2Array([L.bounds.position, Vector2(L.bounds.end.x, L.bounds.position.y), L.bounds.end, Vector2(L.bounds.position.x, L.bounds.end.y)])
	for i in range(c.holes.size()):
		var hd: Dictionary = c.holes[i]
		var tee: Vector2 = hd["tee"]
		var pin: Vector2 = hd["pin"]
		var hole := CourseLayout.Hole.new()
		hole.index = i
		hole.name = "Hole %d" % (i + 1)
		hole.par = c.hole_par(i)
		hole.tee = Vector3(tee.x, L._painted_height(tee.x, tee.y), tee.y)
		# the line of play round any doglegs / along the curve: yardage, stripes, aim
		var route := c.hole_route(i, 10.0)
		var wps: Array[Vector3] = []
		for p in route:
			wps.append(Vector3(p.x, L._painted_height(p.x, p.y), p.y))
		hole.waypoints = wps
		L.routes.append(route)
		var ba: Array = []
		for b in hd.get("bends", []):
			ba.append([_along_route(route, b), b as Vector2])
		ba.sort_custom(func(x, y) -> bool: return x[0] < y[0])
		L.bend_alongs.append(ba)
		hole.fairway_half_width = NOMINAL_HALF_WIDTH
		hole.extend_creeks = false
		hole.painted = canvas  # no auto-filled forest: only the woods the player painted
		L.holes.append(hole)
	if not L.holes.is_empty():
		var first: CourseLayout.Hole = L.holes[0]
		var k := 0
		for poly in _trace(c, c.layer_a(), 3, MIN_BUNKER_M2, 1.0):
			first.bunker_polys.append(["bunker_%d" % k, "greenside", poly])
			k += 1
		k = 0
		for poly in _trace(c, c.splat_b, 0, MIN_WATER_M2, 1.2):
			first.water_polys.append(["water_%d" % k, poly])
			k += 1
		first.woods = _trace(c, c.splat_b, 1, MIN_WOODS_M2, 2.0)
		for t in c.trees:
			first.planted_trees.append([String(t[0]), t[1] as Vector2])
	L._build_along_grid()
	L.finalize_features()
	L.last_build_ms = Time.get_ticks_msec() - t0
	return L


# ---------------------------------------------------------------- CourseLayout overrides

func finalize_features() -> void:
	_build_turf_areas()
	landform_list.clear()
	_hole_water_to_hazards()
	_hole_bunkers_to_excavations()
	for b in bunkers:
		b.feature_name = "Bunker"
	rough = RoughArea.new()
	rough.setup(self)


func build_datum() -> void:
	pass


func hole_bbox(_hole: Hole) -> Rect2:
	return bounds


func _build_turf_areas() -> void:
	fairways.clear()
	greens.clear()
	tees.clear()
	for hole in holes:
		var tee := Vector2(hole.tee.x, hole.tee.z)
		var pin := Vector2(hole.cup.x, hole.cup.z)
		var fw := PaintedFairway.new()
		fw.layout = self
		fw.hole_index = hole.index
		fw.waypoints = routes[hole.index] if hole.index < routes.size() else PackedVector2Array([tee, pin])
		fw.half_width = NOMINAL_HALF_WIDTH
		fw.bounds = bounds
		fw.area_name = "%s fairway" % hole.name
		fairways.append(fw)
		var gr := PaintedGreen.new()
		gr.layout = self
		gr.hole_index = hole.index
		gr.kind = PhysicsEnums.SurfaceType.GREEN
		var gb := _feature_box(_gr, pin, 60.0)
		gr.center = gb.get_center() if gb.size != Vector2.ZERO else pin
		gr.radius = maxf(gb.size.x, gb.size.y) * 0.5 if gb.size != Vector2.ZERO else 8.0
		hole.green_radius = gr.radius
		gr.bounds = (gb if gb.size != Vector2.ZERO else Rect2(pin, Vector2.ZERO)).grow(FRINGE_WIDTH + 4.0)
		gr.area_name = "%s green" % hole.name
		greens.append(gr)
		var te := PaintedTee.new()
		te.layout = self
		te.hole_index = hole.index
		te.kind = SURFACE_TEE
		te.center = tee
		var route:PackedVector2Array=routes[hole.index]
		te.dir = (route[1]-route[0]).normalized() if route.size()>1 else Vector2(0,-1)
		te.half = PaintedCourse.TEE_BOX_HALF
		te.corner = 0.0
		var tb := _feature_box(_te, tee, 25.0)
		te.bounds = (tb if tb.size != Vector2.ZERO else Rect2(tee, Vector2.ZERO)).grow(4.0)
		te.area_name = "%s tee" % hole.name
		tees.append(te)
		hole.bbox = bounds


## One entry for the whole course (the painted fields are global), the other holes null:
## [fairway sd, along, green sd, tee sd, distance to the hole line, along, tree patch sd,
## tree island sd, first-cut zone sd].
func _hole_fds(xz: Vector2) -> Array:
	var out := []
	out.resize(holes.size())
	if holes.is_empty():
		return out
	var along_dist := _along(xz)
	out[0] = [field_at(_fw, xz), along_dist.x, field_at(_gr, xz), tee_sd(xz), along_dist.y, along_dist.x, 1.0e9, 1.0e9, 1.0e9]
	return out


func base_height_from(x: float, z: float, _fds: Array) -> float:
	return _painted_height(x, z)


func in_pad(xz: Vector2, grow: float = 0.0) -> bool:
	return not course.pads.is_empty() and course.on_pad(xz, grow)


func in_paving(xz: Vector2, grow: float = 0.0) -> bool:
	return not course.pads.is_empty() and course.on_paving(xz, grow)


func pads() -> Array:
	return course.pads


# ---------------------------------------------------------------- painted fields

func _painted_height(x: float, z: float) -> float:
	return course.height_at(Vector2(x, z))


## Bilinear sample of a signed-distance grid (metres) at world `xz`.
func field_at(f: PackedFloat32Array, xz: Vector2) -> float:
	var fx := (xz.x - bounds.position.x) / PaintedCourse.CELL - 0.5
	var fz := (xz.y - bounds.position.y) / PaintedCourse.CELL - 0.5
	if fx < -1.0 or fz < -1.0 or fx > _nx or fz > _nz:
		return SD_CLAMP
	var x0 := clampi(int(floor(fx)), 0, _nx - 2)
	var z0 := clampi(int(floor(fz)), 0, _nz - 2)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var tz := clampf(fz - z0, 0.0, 1.0)
	var i := z0 * _nx + x0
	return lerpf(lerpf(f[i], f[i + 1], tx), lerpf(f[i + _nx], f[i + _nx + 1], tx), tz)


func fairway_sd(xz: Vector2) -> float:
	return field_at(_fw, xz)


func green_sd(xz: Vector2) -> float:
	return field_at(_gr, xz)


func tee_sd(xz: Vector2) -> float:
	var distance := course.tee_rectangle_distance(xz)
	return distance if distance < 1.0e8 else field_at(_te, xz)


## (metres along the nearest hole's line of play, distance from it): the mowing stripes run
## across the line of play, round the doglegs. Bilinear from the along grid.
func _along(xz: Vector2) -> Vector2:
	if _ag_nx < 2:
		return _project_routes(xz)
	var fx := clampf((xz.x - bounds.position.x) / ALONG_CELL, 0.0, _ag_nx - 1.001)
	var fz := clampf((xz.y - bounds.position.y) / ALONG_CELL, 0.0, _ag_nz - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * _ag_nx + x0
	return _along_grid[i].lerp(_along_grid[i + 1], tx).lerp(_along_grid[i + _ag_nx].lerp(_along_grid[i + _ag_nx + 1], tx), tz)


## Exact (along, distance) against every hole's route; the nearest hole wins.
func _project_routes(xz: Vector2) -> Vector2:
	var best := INF
	var along := 0.0
	for route in routes:
		var acc := 0.0
		for k in range(1, route.size()):
			var a := route[k - 1]
			var b := route[k]
			var ab := b - a
			var l2 := maxf(ab.length_squared(), 0.0001)
			var t := (xz - a).dot(ab) / l2
			# run on past the tee and the pin so stripes carry through the ends
			var lo := -0.5 if k == 1 else 0.0
			var hi := 1.5 if k == route.size() - 1 else 1.0
			t = clampf(t, lo, hi)
			var d := xz.distance_to(a + ab * t)
			if d < best:
				best = d
				along = acc + t * sqrt(l2)
			acc += sqrt(l2)
	return Vector2(along, best)


func _build_along_grid() -> void:
	_ag_nx = int(ceil(bounds.size.x / ALONG_CELL)) + 1
	_ag_nz = int(ceil(bounds.size.y / ALONG_CELL)) + 1
	_along_grid.resize(_ag_nx * _ag_nz)
	for z in range(_ag_nz):
		for x in range(_ag_nx):
			_along_grid[z * _ag_nx + x] = _project_routes(bounds.position + Vector2(x, z) * ALONG_CELL)


## Metres along `route` of the point on it nearest `p`.
static func _along_route(route: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var along := 0.0
	var acc := 0.0
	for k in range(1, route.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, route[k - 1], route[k])
		var d := q.distance_to(p)
		if d < best:
			best = d
			along = acc + route[k - 1].distance_to(q)
		acc += route[k - 1].distance_to(route[k])
	return along


## Where to aim from `from`: `reach` metres further along hole `index`'s line of play (the
## corner of a dogleg off the tee, not the hidden pin), or the pin when it is within reach.
func aim_point(index: int, from: Vector2, reach: float) -> Vector2:
	if index < 0 or index >= routes.size():
		return from
	var route: PackedVector2Array = routes[index]
	var pin := route[route.size() - 1]
	var length := PaintedCourse.route_length(route)
	var along := _along_route(route, from)
	# a dogleg corner ahead and within reach is the target (play to the corner, then turn)
	for b in bend_alongs[index]:
		if b[0] > along + 25.0 and b[0] <= along + reach:
			return b[1]
	if along + reach >= length:
		return pin
	return PaintedCourse.route_point(route, along + reach)


## Bounding box (world) of the painted cells of a field within `radius` of `near`.
func _feature_box(f: PackedFloat32Array, near: Vector2, radius: float) -> Rect2:
	var c := course.cell_of(near)
	var r := int(radius / PaintedCourse.CELL)
	var box := Rect2()
	var found := false
	for z in range(maxi(int(c.y) - r, 0), mini(int(c.y) + r, _nz)):
		for x in range(maxi(int(c.x) - r, 0), mini(int(c.x) + r, _nx)):
			if f[z * _nx + x] < 0.0:
				var p := course.world_of(x + 0.5, z + 0.5)
				if not found:
					box = Rect2(p, Vector2.ZERO)
					found = true
				else:
					box = box.expand(p)
	return box


## Signed distance (metres, negative inside) to the region where channel `ch` of a splat
## layer is at least half covered. Two-pass chamfer distance (1, sqrt 2) inside the region's
## bounding box grown by SD_CLAMP, then one 3x3 smoothing pass to soften the 1 m staircase.
static func _signed_field(bytes: PackedByteArray, ch: int, nx: int, nz: int) -> PackedFloat32Array:
	var n := nx * nz
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(SD_CLAMP)
	var x0 := nx
	var z0 := nz
	var x1 := -1
	var z1 := -1
	for z in range(nz):
		var row := z * nx
		for x in range(nx):
			if bytes[(row + x) * 4 + ch] >= 128:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				z0 = mini(z0, z)
				z1 = maxi(z1, z)
	if x1 < 0:
		return out
	var g := int(SD_CLAMP) + 2
	x0 = maxi(x0 - g, 0)
	z0 = maxi(z0 - g, 0)
	x1 = mini(x1 + g, nx - 1)
	z1 = mini(z1 + g, nz - 1)
	var w := x1 - x0 + 1
	var h := z1 - z0 + 1
	var inside := PackedByteArray()
	inside.resize(w * h)
	for z in range(h):
		for x in range(w):
			inside[z * w + x] = 1 if bytes[((z + z0) * nx + x + x0) * 4 + ch] >= 128 else 0
	var d_out := _chamfer(inside, w, h, 1)
	var d_in := _chamfer(inside, w, h, 0)
	var sd := PackedFloat32Array()
	sd.resize(w * h)
	for i in range(w * h):
		sd[i] = -(d_in[i] - 0.5) if inside[i] == 1 else (d_out[i] - 0.5)
	# soften
	for z in range(h):
		for x in range(w):
			var s := 0.0
			var c := 0
			for oz in range(-1, 2):
				var zz := z + oz
				if zz < 0 or zz >= h:
					continue
				for ox in range(-1, 2):
					var xx := x + ox
					if xx < 0 or xx >= w:
						continue
					s += sd[zz * w + xx]
					c += 1
			out[(z + z0) * nx + x + x0] = clampf(s / c, -SD_CLAMP, SD_CLAMP) * PaintedCourse.CELL
	return out


## Chamfer distance (cells) from every cell to the nearest cell whose `inside` equals `target`.
static func _chamfer(inside: PackedByteArray, w: int, h: int, target: int) -> PackedFloat32Array:
	const BIG := 1.0e6
	const D := 1.41421356
	var d := PackedFloat32Array()
	d.resize(w * h)
	for i in range(w * h):
		d[i] = 0.0 if inside[i] == target else BIG
	for z in range(h):
		for x in range(w):
			var i := z * w + x
			var v := d[i]
			if v == 0.0:
				continue
			if x > 0:
				v = minf(v, d[i - 1] + 1.0)
			if z > 0:
				v = minf(v, d[i - w] + 1.0)
				if x > 0:
					v = minf(v, d[i - w - 1] + D)
				if x < w - 1:
					v = minf(v, d[i - w + 1] + D)
			d[i] = v
	for z in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := z * w + x
			var v := d[i]
			if v == 0.0:
				continue
			if x < w - 1:
				v = minf(v, d[i + 1] + 1.0)
			if z < h - 1:
				v = minf(v, d[i + w] + 1.0)
				if x < w - 1:
					v = minf(v, d[i + w + 1] + D)
				if x > 0:
					v = minf(v, d[i + w - 1] + D)
			d[i] = minf(v, SD_CLAMP + 2.0)
	return d


## World outlines (counter-clockwise, smoothed) of the regions where channel `ch` is at least
## half covered, dropping specks under `min_m2`.
static func _trace(c: PaintedCourse, bytes: PackedByteArray, ch: int, min_m2: float, epsilon: float) -> Array:
	var bm := BitMap.new()
	bm.create(c.size)
	var any := false
	for z in range(c.size.y):
		for x in range(c.size.x):
			if bytes[(z * c.size.x + x) * 4 + ch] >= 128:
				bm.set_bit(x, z, true)
				any = true
	var out: Array = []
	if not any:
		return out
	for poly: PackedVector2Array in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, c.size), epsilon):
		var world := PackedVector2Array()
		for p in poly:
			world.append(c.origin + p * PaintedCourse.CELL)
		if absf(Excavation.signed_area(world)) < min_m2:
			continue
		world = Excavation.smooth_polygon(world, 2)
		out.append(Excavation.ensure_ccw(world))
	return out


# ---------------------------------------------------------------- areas over the fields

class PaintedFairway extends FairwayArea:
	var layout: PaintedLayout

	func centreline(p: Vector2) -> Array:
		var sd := layout.fairway_sd(p)
		var al := layout._along(p)
		return [maxf(sd, 0.0) + PaintedLayout.NOMINAL_HALF_WIDTH, al.x, 1.0, al.x]

	func width_at(_along: float, _side: float = 1.0) -> float:
		return PaintedLayout.NOMINAL_HALF_WIDTH

	## The painted layout's along grid already runs smoothly round its doglegs and curves.
	func stripe_along(p: Vector2) -> float:
		return layout._along(p).x

	func signed_distance(p: Vector2) -> float:
		return layout.fairway_sd(p)

	func signed_distance_from(p: Vector2, _cl: Array) -> float:
		return layout.fairway_sd(p)

	func length_m() -> float:
		return PaintedCourse.route_length(waypoints)

	func cut_zone_distance(_p: Vector2) -> float:
		return 1.0e9

	func tree_island_distance(_p: Vector2) -> float:
		return 1.0e9

	func tree_patch_distance(_p: Vector2) -> float:
		return 1.0e9


class PaintedGreen extends GreenArea:
	var layout: PaintedLayout

	func signed_distance(p: Vector2) -> float:
		return layout.green_sd(p)


class PaintedTee extends TeeArea:
	var layout: PaintedLayout

	func signed_distance(p: Vector2) -> float:
		return layout.tee_sd(p)
