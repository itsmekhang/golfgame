class_name PaintedCourse
extends RefCounted
## A user-made course from the Course Studio: painted surface layers, a sculpted height field,
## hand-placed trees and the holes (tee + pin). Pure data + brush operations, no nodes, so the
## studio, the game (PaintedLayout) and headless tests all share it.
##
## Layers follow TerraBrush's splat-map idea: every surface is a 0..255 coverage channel and
## brushes blend them with a soft falloff, so edges stay smooth; the game reads a surface where
## its coverage passes one half. All grids share one cell size (CELL metres) over the canvas,
## whose top-left corner is `origin` in world XZ (the canvas is centred on the world origin).
##   splat_a: R fairway, G green, B tee, A bunker     (exclusive turf/hazard surfaces)
##   splat_b: R water,   G woods, B -, A -           (woods = forest planted on the rough)
##   height:  metres, before bunkers/water are dug (the game digs those itself)

enum Surface { ROUGH, FAIRWAY, GREEN, TEE, BUNKER, WATER, WOODS }

const CELL := 1.0
const VERSION := 1
const MAX_CANVAS_CELLS := 2000
const LAND_EXPANSION_METRES := 200
const DIR := "user://courses/"
const EXT := ".course.json"
## Surfaces that replace each other where painted (woods sits on rough, so turf clears it).
const EXCLUSIVE := [Surface.FAIRWAY, Surface.GREEN, Surface.TEE, Surface.BUNKER, Surface.WATER]
const SURFACE_NAMES := ["Rough", "Fairway", "Green", "Tee", "Bunker", "Water", "Woods"]
## Par from hole length (metres, tee to pin): men's yardage guidelines.
const PAR3_MAX_M := 229.0  # 250 yd
const PAR4_MAX_M := 430.0  # 470 yd
## Default tee box: (half width across, half length along the line of play), metres.
const TEE_BOX_HALF := Vector2(4.5, 6.0)

var course_name := "My Course"
var size := Vector2i(600, 600)  # cells (= metres at CELL 1.0)
var origin := Vector2(-300, -300)
var splat_a := PackedByteArray()
var splat_b := PackedByteArray()
var height := PackedFloat32Array()
## Individually placed trees: [String NaturePack species, Vector2 world XZ].
var trees: Array = []
## Holes in playing order: {"tee": Vector2, "pin": Vector2, "par": int (0 = from length)}.
var holes: Array = []
## Bumped on every edit, so views know when to rebuild.
var revision := 0
## Building plots the club has graded flat (Course Manager; set by FacilityBuilder.grade(),
## never saved): [{"pos": Vector2, "rot": float, "half": Vector2, "h": float, "foot": the plot's
## half size, "mask": where on it is built on (Image, if built), "blend": how far round it the
## ground eases back (m, PAD_BLEND if unset)}]. height_at() and height_image() see the ground
## eased to each pad's height over its blend; `height` itself (what the Studio sculpts and
## saves) is untouched.
var pads: Array = []
const PAD_BLEND := 10.0
const FLAT_MARGIN := 3.0  # m round a built pad's paving levelled flat (graded): over a drawn cell's diagonal
## The club's practice turf (the short game area's greens, collars and bunkers, painted by
## FacilityBuilder.grade() with the course's own brushes; never saved): splat_a's layout, laid
## over the course's own layers by layer_a(), which is what every reader of the turf sees --
## the views (greens shaded, bunkers dug), the game's layout, surface_at(). Empty when none.
var turf_a := PackedByteArray()
var _turf_b := PackedByteArray()  # what turf painting clears in splat_b's place (thrown away)
var _turf_rect := Rect2i()
var _turf_rev := 0
var _layered := PackedByteArray()
var _layered_key := Vector2i(-1, -1)
var _tee_grade_revision := -1
var _tee_grade_count := -1
var _tee_grades: Array = []


static func create(p_name: String, p_size: Vector2i = Vector2i(600, 600)) -> PaintedCourse:
	var c := PaintedCourse.new()
	c.course_name = p_name
	c.size = p_size
	c.origin = -Vector2(p_size) * CELL * 0.5
	var n := p_size.x * p_size.y
	c.splat_a.resize(n * 4)
	c.splat_a.fill(0)
	c.splat_b.resize(n * 4)
	c.splat_b.fill(0)
	c.height.resize(n)
	c.height.fill(0.0)
	return c


## A playable starting point: gently rolling ground and one par 4 with a fairway, green,
## tee, two bunkers, a pond and woods down both sides.
static func starter(p_name: String) -> PaintedCourse:
	var c := create(p_name)
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	for z in range(c.size.y):
		for x in range(c.size.x):
			c.height[z * c.size.x + x] = noise.get_noise_2d(x, z) * 4.0
	var tee := Vector2(0, 170)
	var pin := Vector2(25, -175)
	var mid := Vector2(-12, 0)
	# woods first: every surface painted afterwards clears the woods under it
	for side in [-1.0, 1.0]:
		for i in range(0, 11):
			var p := tee.lerp(pin, i / 10.0) + Vector2(side * 78.0, 0.0)
			c.paint(Surface.WOODS, p, 30.0, 1.0, 0.6)
	for i in range(0, 41):
		var t := i / 40.0
		var p := tee.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(pin, (t - 0.5) * 2.0)
		if t > 0.12 and t < 0.93:
			c.paint(Surface.FAIRWAY, p, 17.0 + 6.0 * sin(t * 9.0), 1.0, 0.75)
	c.paint(Surface.GREEN, pin, 15.0, 1.0, 0.8)
	c.paint_box(Surface.TEE, tee, TEE_BOX_HALF, mid - tee, 1.0, 0.9)
	c.paint(Surface.BUNKER, pin + Vector2(-17, 8), 6.5, 1.0, 0.75)
	c.paint(Surface.BUNKER, Vector2(10, -40), 7.0, 1.0, 0.75)
	c.paint(Surface.WATER, Vector2(-48, -70), 22.0, 1.0, 0.7)
	c.sculpt("flatten", pin, 18.0, 1.0, 0.6, c.height_at(pin))
	c.sculpt("flatten", tee, 9.0, 1.0, 0.6, c.height_at(tee) + 0.4)
	c.holes = [{"tee": tee, "pin": pin, "par": 0, "bends": [mid], "curve": true}]
	# Room for multiple holes, the clubhouse and a full range around the sample hole.
	c.expand_land(300)
	return c


## Add rough around all four edges, keeping every existing cell at its world position.
## New ground carries the nearest boundary height, so there is no height seam.
func expand_land(border_metres: int = LAND_EXPANSION_METRES) -> bool:
	var border := mini(roundi(border_metres / CELL), (MAX_CANVAS_CELLS - maxi(size.x, size.y)) / 2)
	if border <= 0:
		return false
	var next_size := size + Vector2i.ONE * border * 2
	var next_a := PackedByteArray()
	var next_b := PackedByteArray()
	var next_h := PackedFloat32Array()
	var empty_side := PackedByteArray()
	empty_side.resize(border * 4)
	empty_side.fill(0)
	var empty_row := PackedByteArray()
	empty_row.resize(next_size.x * 4)
	empty_row.fill(0)
	for nz in range(next_size.y):
		var oz := clampi(nz - border, 0, size.y - 1)
		var first := oz * size.x
		if nz >= border and nz < border + size.y:
			next_a.append_array(empty_side)
			next_a.append_array(splat_a.slice(first * 4, (first + size.x) * 4))
			next_a.append_array(empty_side)
			next_b.append_array(empty_side)
			next_b.append_array(splat_b.slice(first * 4, (first + size.x) * 4))
			next_b.append_array(empty_side)
		else:
			next_a.append_array(empty_row)
			next_b.append_array(empty_row)
		var side := PackedFloat32Array()
		side.resize(border)
		side.fill(height[first])
		next_h.append_array(side)
		next_h.append_array(height.slice(first, first + size.x))
		side.fill(height[first + size.x - 1])
		next_h.append_array(side)
	size = next_size
	origin -= Vector2.ONE * border * CELL
	splat_a = next_a
	splat_b = next_b
	height = next_h
	revision += 1
	return true


# ---------------------------------------------------------------- grid helpers

func cell_of(world: Vector2) -> Vector2:
	return (world - origin) / CELL


func world_of(cx: float, cz: float) -> Vector2:
	return origin + Vector2(cx, cz) * CELL


func bounds() -> Rect2:
	return Rect2(origin, Vector2(size) * CELL)


func in_canvas(world: Vector2) -> bool:
	return bounds().has_point(world)


## Coverage 0..1 of `surface` at a cell (nearest); `turf`: with the practice turf laid over.
func coverage_at_cell(surface: int, x: int, z: int, turf: bool = true) -> float:
	x = clampi(x, 0, size.x - 1)
	z = clampi(z, 0, size.y - 1)
	var i := z * size.x + x
	var a := layer_a() if turf else splat_a
	match surface:
		Surface.FAIRWAY:
			return a[i * 4] / 255.0
		Surface.GREEN:
			return a[i * 4 + 1] / 255.0
		Surface.TEE:
			return a[i * 4 + 2] / 255.0
		Surface.BUNKER:
			return a[i * 4 + 3] / 255.0
		Surface.WATER:
			return splat_b[i * 4] / 255.0
		Surface.WOODS:
			return splat_b[i * 4 + 1] / 255.0
	return 0.0


## Bilinear coverage at a world point (samples sit at cell centres, like a texture's texels).
func coverage(surface: int, world: Vector2, turf: bool = true) -> float:
	if surface == Surface.TEE and turf:
		var distance := tee_rectangle_distance(world)
		if distance < 1.0e8:return 1.0-smoothstep(-.02,.02,distance)
	var f := cell_of(world) - Vector2(0.5, 0.5)
	var x0 := int(floor(f.x))
	var z0 := int(floor(f.y))
	var tx := f.x - x0
	var tz := f.y - z0
	return lerpf(lerpf(coverage_at_cell(surface, x0, z0, turf), coverage_at_cell(surface, x0 + 1, z0, turf), tx),
		lerpf(coverage_at_cell(surface, x0, z0 + 1, turf), coverage_at_cell(surface, x0 + 1, z0 + 1, turf), tx), tz)


## surface_at() from the nearest cell alone (no blending), for sweeping a grid over the whole
## course: `a` is layer_a(), fetched once by the caller. WOODS when the rough there is woods.
func surface_nearest(world: Vector2, a: PackedByteArray) -> int:
	var x := clampi(int((world.x - origin.x) / CELL), 0, size.x - 1)
	var z := clampi(int((world.y - origin.y) / CELL), 0, size.y - 1)
	var i := (z * size.x + x) * 4
	var best := Surface.ROUGH
	var best_v := 127
	for k in range(4):
		if a[i + k] > best_v:
			best_v = a[i + k]
			best = [Surface.FAIRWAY, Surface.GREEN, Surface.TEE, Surface.BUNKER][k]
	if splat_b[i] > best_v:
		return Surface.WATER
	if best == Surface.ROUGH and splat_b[i + 1] > 127:
		return Surface.WOODS
	return best


## The surface that wins at a world point (coverage > 0.5), else rough; `turf`: with the
## practice turf (false: the course as painted, e.g. where a facility may go).
func surface_at(world: Vector2, turf: bool = true) -> int:
	var best := Surface.ROUGH
	var best_v := 0.5
	for s in EXCLUSIVE:
		var v := coverage(s, world, turf)
		if v > best_v:
			best_v = v
			best = s
	return best


func height_at(world: Vector2) -> float:
	var h := _grade_tees(world, raw_height_at(world))
	return h if pads.is_empty() else graded(world, h)


## The ground as PaintedView draws it at `world`: its terrain is a grid every `step` m whose
## corners take height_at() less the bunkers' and water's dig, and between them a pair of flat
## triangles (split corner to corner the way PlaneMesh splits them). People and carts stand on
## this, not on height_at() -- in a dip the drawn triangles ride above it.
func drawn_height_at(world: Vector2, step: float = 2.0) -> float:
	var span := Vector2(size) * CELL
	var n := Vector2(floorf(span.x / step) + 1.0, floorf(span.y / step) + 1.0)
	var d := span / n
	var f := (world - origin) / d
	var i := clampf(floorf(f.x), 0.0, n.x - 1.0)
	var j := clampf(floorf(f.y), 0.0, n.y - 1.0)
	var u := clampf(f.x - i, 0.0, 1.0)
	var v := clampf(f.y - j, 0.0, 1.0)
	var corner := origin + Vector2(i, j) * d
	var h10 := _drawn_corner(corner + Vector2(d.x, 0.0))
	var h01 := _drawn_corner(corner + Vector2(0.0, d.y))
	if u + v <= 1.0:
		var h00 := _drawn_corner(corner)
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	var h11 := _drawn_corner(corner + d)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


## A corner of the drawn terrain: the ground, less what studio_terrain.gdshader digs for sand and
## water there.
func _drawn_corner(p: Vector2) -> float:
	return height_at(p) - smoothstep(0.3, 0.9, coverage(Surface.BUNKER, p)) * 0.6 - smoothstep(0.2, 0.9, coverage(Surface.WATER, p)) * 1.4


## The sculpted ground at `world`, before any building pad grades it.
func raw_height_at(world: Vector2) -> float:
	var f := cell_of(world) - Vector2(0.5, 0.5)
	var x0 := clampi(int(floor(f.x)), 0, size.x - 2)
	var z0 := clampi(int(floor(f.y)), 0, size.y - 2)
	var tx := clampf(f.x - x0, 0.0, 1.0)
	var tz := clampf(f.y - z0, 0.0, 1.0)
	var i := z0 * size.x + x0
	return lerpf(lerpf(height[i], height[i + 1], tx), lerpf(height[i + size.x], height[i + size.x + 1], tx), tz)


## Ground height `h` at `world` eased toward the building pads around it.
func graded(world: Vector2, h: float) -> float:
	# A neighbouring pad's ease must never tilt another facility's flat ground; where two eases
	# overlap the ground is shared between them, evenly, not the later one's. On more than one
	# pad's levelled ground (two plots built close): the one whose paving it's nearest -- the one
	# it's built on -- not whichever came first, which would lift or bury the other's paving.
	var weight := 0.0
	var sum := 0.0
	var on := -1
	var nearest := INF
	var outs: Array = []
	for i in range(pads.size()):
		var p: Dictionary = pads[i]
		var out := _flat_reach(p, world)
		outs.append(out)
		if out <= 0.0:
			var d := pad_reach(p, world, true)
			if d < nearest:
				nearest = d
				on = i
	if on >= 0:
		return float(pads[on]["h"])
	for i in range(pads.size()):
		var p: Dictionary = pads[i]
		var out: float = outs[i]
		var blend := float(p.get("blend", PAD_BLEND))
		if out < blend:
			var w := 1.0 - smoothstep(0.0, blend, out)
			weight += w
			sum += w * float(p["h"])
	if weight <= 0.0:
		return h
	if weight >= 1.0:
		return sum / weight
	return h * (1.0 - weight) + sum


## How far `world` is from the ground pad `p` levels flat: FLAT_MARGIN round what's built on it
## (wider than its field's metre: the drawn terrain's triangles, DRAWN_STEP across, that reach
## onto its paving stay flat right across, never tipping up over its edge), or its whole plot.
static func _flat_reach(p: Dictionary, world: Vector2) -> float:
	if not p.has("field"):
		return pad_distance(p, world)
	return maxf(pad_reach(p, world, true) - FLAT_MARGIN, 0.0)


## How far `world` is from the part of pad `p` that's levelled: what's built on there (its
## "field", FacilityBuilder.grade(): a metre round the paving, floors, decks and beds), or the
## whole plot when there's no knowing (no field). 0 on it.
static func pad_reach(p: Dictionary, world: Vector2, raw: bool = false) -> float:
	var f: Dictionary = p.get("field", {})
	if f.is_empty():
		return pad_distance(p, world) if not raw else pad_distance(p, world) - 1.0
	var d: Vector2 = world - (p["pos"] as Vector2)
	var c := cos(float(p["rot"]))
	var s := sin(float(p["rot"]))
	var g := Vector2(d.x * c - d.y * s, d.x * s + d.y * c) - (f["origin"] as Vector2)
	var n: Vector2i = f["n"]
	if g.x < 0.0 or g.y < 0.0 or g.x > n.x - 1 or g.y > n.y - 1:
		return 1.0e6
	var i := mini(int(g.x), n.x - 2)
	var j := mini(int(g.y), n.y - 2)
	var tx := g.x - i
	var tz := g.y - j
	var dist: PackedFloat32Array = f["dist"]
	var k := j * n.x + i
	var v := lerpf(lerpf(dist[k], dist[k + 1], tx), lerpf(dist[k + n.x], dist[k + n.x + 1], tx), tz)
	return v if raw else maxf(v - 1.0, 0.0)


## How far `world` is outside pad `p`'s rectangle (0 inside it).
static func pad_distance(p: Dictionary, world: Vector2) -> float:
	var d: Vector2 = world - (p["pos"] as Vector2)
	var c := cos(float(p["rot"]))
	var s := sin(float(p["rot"]))
	var half: Vector2 = p["half"]
	var ox := maxf(absf(d.x * c - d.y * s) - half.x, 0.0)
	var oz := maxf(absf(d.x * s + d.y * c) - half.y, 0.0)
	return sqrt(ox * ox + oz * oz)


## Whether `world` is on a building pad (grown by `grow` metres; negative shrinks it): on (or
## by) what's built on it, where its field says (the open ground of a plot is the course's own:
## its trees and its rough stay), else anywhere in the plot.
func on_pad(world: Vector2, grow: float = 0.0) -> bool:
	for p in pads:
		if p.has("field"):
			if pad_reach(p, world) <= maxf(grow, 0.0) + 2.0:
				return true
			continue
		var half: Vector2 = p["half"]
		var d: Vector2 = world - (p["pos"] as Vector2)
		var c := cos(float(p["rot"]))
		var s := sin(float(p["rot"]))
		if absf(d.x * c - d.y * s) <= half.x + grow and absf(d.x * s + d.y * c) <= half.y + grow:
			return true
	return false


## Whether `world` is built on -- paving, floors, decks, beds (the pads' paving masks) -- or
## within `grow` metres of it. The rest of a plot is the course's own rough.
func on_paving(world: Vector2, grow: float = 0.0) -> bool:
	for p in pads:
		var mask: Image = p.get("mask")
		if mask == null:
			continue
		var foot: Vector2 = p["foot"]
		var d: Vector2 = world - (p["pos"] as Vector2)
		var c := cos(float(p["rot"]))
		var s := sin(float(p["rot"]))
		var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
		if absf(l.x) > foot.x + grow or absf(l.y) > foot.y + grow:
			continue
		if _paved(mask, foot, l):
			return true
		if grow > 0.0:
			for o in [Vector2(grow, 0), Vector2(-grow, 0), Vector2(0, grow), Vector2(0, -grow)]:
				if _paved(mask, foot, l + o):
					return true
	return false


static func _paved(mask: Image, foot: Vector2, l: Vector2) -> bool:
	var i := int(floor((l.x + foot.x) / (foot.x * 2.0) * mask.get_width()))
	var j := int(floor((l.y + foot.y) / (foot.y * 2.0) * mask.get_height()))
	if i < 0 or j < 0 or i >= mask.get_width() or j >= mask.get_height():
		return false
	return mask.get_pixel(i, j).r > 0.5


## Cell rect touched by a brush of `radius` metres at `world`, clipped to the canvas.
func brush_rect(world: Vector2, radius: float) -> Rect2i:
	var c := cell_of(world)
	var r := radius / CELL + 1.0
	var x0 := clampi(int(floor(c.x - r)), 0, size.x - 1)
	var z0 := clampi(int(floor(c.y - r)), 0, size.y - 1)
	var x1 := clampi(int(ceil(c.x + r)), 0, size.x - 1)
	var z1 := clampi(int(ceil(c.y + r)), 0, size.y - 1)
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


## Soft round falloff: 1 inside `hardness` of the radius, easing to 0 at the edge.
static func falloff(d01: float, hardness: float) -> float:
	if d01 >= 1.0:
		return 0.0
	return 1.0 - smoothstep(clampf(hardness, 0.0, 0.98), 1.0, d01)


# ---------------------------------------------------------------- brushes

## The turf layer every reader sees: splat_a with the practice turf (turf_a) laid over it --
## where the turf covers, it gives way -- or splat_a itself when there's no turf.
func layer_a() -> PackedByteArray:
	if turf_a.is_empty() and holes.is_empty():
		return splat_a
	var key := Vector2i(revision, _turf_rev)
	if key != _layered_key:
		_layered = splat_a.duplicate()
		for z: int in range(_turf_rect.position.y, _turf_rect.end.y) if not turf_a.is_empty() else []:
			for x in range(_turf_rect.position.x, _turf_rect.end.x):
				var i := (z * size.x + x) * 4
				var t := maxi(maxi(turf_a[i], turf_a[i + 1]), maxi(turf_a[i + 2], turf_a[i + 3]))
				if t == 0:
					continue
				for k in range(4):
					_layered[i + k] = maxi(_layered[i + k] * (255 - t) / 255, turf_a[i + k])
		_rectangular_tee_layer(_layered)
		_layered_key = key
	return _layered


## Paint the practice turf (turf_a) with the course's own round brush; splat_a and splat_b
## (what's saved) are left alone.
func paint_turf(surface: int, world: Vector2, radius: float, hardness: float = 0.75) -> void:
	if turf_a.size() != splat_a.size():
		turf_a.resize(splat_a.size())
		turf_a.fill(0)
		_turf_rect = Rect2i()
	if _turf_b.size() != splat_b.size():
		_turf_b.resize(splat_b.size())
	var real_a := splat_a
	var real_b := splat_b
	splat_a = turf_a
	splat_b = _turf_b
	var rect := _paint(surface, world, radius, 1.0, hardness, false, Vector2.ZERO, Vector2.ZERO)
	turf_a = splat_a
	_turf_b = splat_b
	splat_a = real_a
	splat_b = real_b
	_turf_rect = rect if _turf_rect.size == Vector2i.ZERO else _turf_rect.merge(rect)
	_turf_rev += 1


func clear_turf() -> void:
	if turf_a.is_empty():
		return
	turf_a = PackedByteArray()
	_turf_rect = Rect2i()
	_turf_rev += 1
	revision += 1


## Paints (or with `erase`, removes) `surface` with a round brush. Painting a turf/hazard
## surface clears the other exclusive surfaces and the woods under it; ROUGH clears every
## surface (the eraser); WOODS turns the ground back to rough and marks it for forest.
## Returns the touched cell rect.
func paint(surface: int, world: Vector2, radius: float, strength: float, hardness: float = 0.5, erase: bool = false) -> Rect2i:
	return _paint(surface, world, radius, strength, hardness, erase, Vector2.ZERO, Vector2.ZERO)


## A square / rectangular stamp: `half` = (half width across, half length along) in metres,
## squared to `dir` (the line of play), so tee boxes come out as proper rectangles.
func paint_box(surface: int, world: Vector2, half: Vector2, dir: Vector2, strength: float, hardness: float = 0.85, erase: bool = false) -> Rect2i:
	var d := dir.normalized() if dir.length() > 0.001 else Vector2(0, -1)
	return _paint(surface, world, half.length(), strength, hardness, erase, d, half)


func _paint(surface: int, world: Vector2, radius: float, strength: float, hardness: float, erase: bool, box_dir: Vector2, box_half: Vector2) -> Rect2i:
	var rect := brush_rect(world, radius)
	var c := cell_of(world)
	var r := maxf(radius / CELL, 0.5)
	var box := box_dir != Vector2.ZERO
	var across := Vector2(-box_dir.y, box_dir.x)
	var hx := maxf(box_half.x / CELL, 0.5)
	var hz := maxf(box_half.y / CELL, 0.5)
	var ch_a := -1
	var ch_b := -1
	match surface:
		Surface.FAIRWAY: ch_a = 0
		Surface.GREEN: ch_a = 1
		Surface.TEE: ch_a = 2
		Surface.BUNKER: ch_a = 3
		Surface.WATER: ch_b = 0
		Surface.WOODS: ch_b = 1
	for z in range(rect.position.y, rect.end.y):
		var dz := (z + 0.5 - c.y)
		for x in range(rect.position.x, rect.end.x):
			var dx := (x + 0.5 - c.x)
			var d01 := sqrt(dx * dx + dz * dz) / r
			if box:
				var o := Vector2(dx, dz)
				d01 = maxf(absf(o.dot(across)) / hx, absf(o.dot(box_dir)) / hz)
			var a := falloff(d01, hardness) * strength
			if a <= 0.001:
				continue
			var i := (z * size.x + x) * 4
			var keep := 1.0 - a
			if erase:
				if ch_a >= 0:
					splat_a[i + ch_a] = int(splat_a[i + ch_a] * keep)
				elif ch_b >= 0:
					splat_b[i + ch_b] = int(splat_b[i + ch_b] * keep)
				continue
			if surface == Surface.ROUGH:
				for k in range(4):
					splat_a[i + k] = int(splat_a[i + k] * keep)
				splat_b[i] = int(splat_b[i] * keep)
				continue
			# everything else under the brush gives way
			for k in range(4):
				if k != ch_a:
					splat_a[i + k] = int(splat_a[i + k] * keep)
			if ch_b != 0:
				splat_b[i] = int(splat_b[i] * keep)
			if ch_b != 1:
				splat_b[i + 1] = int(splat_b[i + 1] * keep)
			if ch_a >= 0:
				var v := splat_a[i + ch_a] / 255.0
				splat_a[i + ch_a] = int(round((v + a * (1.0 - v)) * 255.0))
			elif ch_b >= 0:
				var v := splat_b[i + ch_b] / 255.0
				splat_b[i + ch_b] = int(round((v + a * (1.0 - v)) * 255.0))
	revision += 1
	return rect


## Height brushes. `mode`: "raise" | "lower" (metres per full-strength dab = rate),
## "smooth" (toward the 3x3 mean), "flatten" (toward `target`), "noise" (adds bumps).
func sculpt(mode: String, world: Vector2, radius: float, strength: float, hardness: float = 0.4, target: float = 0.0, rate: float = 0.35) -> Rect2i:
	var rect := brush_rect(world, radius)
	var c := cell_of(world)
	var r := maxf(radius / CELL, 0.5)
	var src := height if mode == "smooth" else PackedFloat32Array()
	if mode == "smooth":
		src = height.duplicate()
	for z in range(rect.position.y, rect.end.y):
		var dz := (z + 0.5 - c.y)
		for x in range(rect.position.x, rect.end.x):
			var dx := (x + 0.5 - c.x)
			var a := falloff(sqrt(dx * dx + dz * dz) / r, hardness) * strength
			if a <= 0.0005:
				continue
			var i := z * size.x + x
			match mode:
				"raise":
					height[i] += a * rate
				"lower":
					height[i] -= a * rate
				"flatten":
					height[i] = lerpf(height[i], target, clampf(a, 0.0, 1.0))
				"smooth":
					var s := 0.0
					var n := 0
					for oz in range(-2, 3):
						for ox in range(-2, 3):
							var xx := clampi(x + ox, 0, size.x - 1)
							var zz := clampi(z + oz, 0, size.y - 1)
							s += src[zz * size.x + xx]
							n += 1
					height[i] = lerpf(height[i], s / n, clampf(a, 0.0, 1.0))
				"noise":
					var nv := sin(x * 0.37 + z * 0.11) * cos(z * 0.29 - x * 0.07)
					height[i] += nv * a * rate * 0.5
	revision += 1
	return rect


# ---------------------------------------------------------------- holes and trees

static func auto_par(length_m: float) -> int:
	if length_m <= PAR3_MAX_M:
		return 3
	if length_m <= PAR4_MAX_M:
		return 4
	return 5


func hole_par(i: int) -> int:
	var h: Dictionary = holes[i]
	if int(h.get("par", 0)) > 0:
		return int(h["par"])
	return auto_par(route_length(hole_route(i)))


## Yardage along the line of play (round the doglegs), as on a scorecard.
func hole_yards(i: int) -> int:
	return roundi(route_length(hole_route(i)) * 1.09361)


## The hole's control points: tee, its dogleg bends in order, pin.
func hole_controls(i: int) -> PackedVector2Array:
	var h: Dictionary = holes[i]
	var pts := PackedVector2Array([h["tee"]])
	for b in h.get("bends", []):
		pts.append(b)
	pts.append(h["pin"])
	return pts


func hole_is_curve(i: int) -> bool:
	return bool((holes[i] as Dictionary).get("curve", false))


## The line of play: straight legs between the bends (a dogleg), or for a "curve" hole a
## smooth centripetal Catmull-Rom spline through them, sampled every `step` metres.
func hole_route(i: int, step: float = 4.0) -> PackedVector2Array:
	var pts := hole_controls(i)
	if pts.size() < 3 or not hole_is_curve(i):
		return pts
	return spline(pts, step)


static func route_length(route: PackedVector2Array) -> float:
	var d := 0.0
	for k in range(1, route.size()):
		d += route[k - 1].distance_to(route[k])
	return d


## The point `s` metres along a route (clamped to its ends).
static func route_point(route: PackedVector2Array, s: float) -> Vector2:
	if route.size() == 1:
		return route[0]
	var acc := 0.0
	for k in range(1, route.size()):
		var l := route[k - 1].distance_to(route[k])
		if acc + l >= s:
			return route[k - 1].lerp(route[k], clampf((s - acc) / maxf(l, 0.0001), 0.0, 1.0))
		acc += l
	return route[route.size() - 1]


## Centripetal Catmull-Rom through `pts` (no overshoot or loops on uneven spacing).
static func spline(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for k in range(n - 1):
		var p1 := pts[k]
		var p2 := pts[k + 1]
		var p0 := pts[k - 1] if k > 0 else p1 - (p2 - p1)
		var p3 := pts[k + 2] if k + 2 < n else p2 + (p2 - p1)
		var segs := maxi(int(p1.distance_to(p2) / step), 1)
		for j in range(segs):
			out.append(_centripetal(p0, p1, p2, p3, float(j) / segs))
	out.append(pts[n - 1])
	return out


static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 0.01)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 0.01)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 0.01)
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


## Adds a dogleg bend at `p`, slotted between the control points of the leg it is nearest.
## Returns its index in the hole's "bends".
func insert_bend(i: int, p: Vector2) -> int:
	var h: Dictionary = holes[i]
	if not h.has("bends"):
		h["bends"] = []
	var pts := hole_controls(i)
	var best := INF
	var at := 0
	for k in range(1, pts.size()):
		var d := Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k]).distance_to(p)
		if d < best:
			best = d
			at = k - 1
	(h["bends"] as Array).insert(at, p)
	revision += 1
	return at


## Lays a fairway along hole `i`'s line of play: from a short carry off the tee to just
## short of the green, `half_width` wide with gentle swells, plus a green and a tee box if
## the hole has none yet. Returns the touched cell rect.
func lay_fairway(i: int, half_width: float = 15.0) -> Rect2i:
	var route := hole_route(i, 3.0)
	var length := route_length(route)
	var start := clampf(length * 0.22, 35.0, 160.0)
	var stop := length - 18.0
	var rect := Rect2i()
	var s := start
	var step := maxf(half_width * 0.3, 2.0)
	while s <= stop:
		var p := route_point(route, s)
		# opens out from the carry, swells through the landing zones
		var w := half_width * (0.75 + 0.25 * smoothstep(start, start + 60.0, s)) * (0.9 + 0.14 * sin(s / 55.0))
		var r := paint(Surface.FAIRWAY, p, w, 1.0, 0.72)
		rect = r if rect.size == Vector2i.ZERO else rect.merge(r)
		s += step
	var h: Dictionary = holes[i]
	if coverage(Surface.GREEN, h["pin"]) < 0.5:
		rect = rect.merge(paint(Surface.GREEN, h["pin"], 13.0, 1.0, 0.75))
	if coverage(Surface.TEE, h["tee"]) < 0.5:
		rect = rect.merge(paint_box(Surface.TEE, h["tee"], TEE_BOX_HALF, route[1] - route[0], 1.0, 0.9))
	return rect


## Trees within `radius` of `world` are removed; returns how many.
func remove_trees(world: Vector2, radius: float) -> int:
	var kept: Array = []
	for t in trees:
		if (t[1] as Vector2).distance_to(world) > radius:
			kept.append(t)
	var n := trees.size() - kept.size()
	trees = kept
	if n > 0:
		revision += 1
	return n


## Problems that stop the course from playing well, as short sentences (empty = ready).
func issues() -> PackedStringArray:
	var out := PackedStringArray()
	if holes.is_empty():
		out.append("Add a hole: place a tee and a pin.")
	for i in range(holes.size()):
		var h: Dictionary = holes[i]
		var pin: Vector2 = h["pin"]
		var tee: Vector2 = h["tee"]
		if not in_canvas(pin) or not in_canvas(tee):
			out.append("Hole %d: tee or pin is off the map." % (i + 1))
			continue
		if coverage(Surface.GREEN, pin) < 0.5:
			out.append("Hole %d: the pin isn't on a green." % (i + 1))
		if surface_at(tee) in [Surface.WATER, Surface.BUNKER]:
			out.append("Hole %d: the tee is in a hazard." % (i + 1))
		if route_length(hole_route(i)) < 40.0:
			out.append("Hole %d is shorter than 45 yards." % (i + 1))
		for b in h.get("bends", []):
			if not in_canvas(b):
				out.append("Hole %d: a bend is off the map." % (i + 1))
				break
	return out


# ---------------------------------------------------------------- moving whole features

const MOVABLE := [Surface.GREEN, Surface.TEE, Surface.BUNKER, Surface.WATER]


## Which splat layer and channel a surface lives in: [bytes, channel].
func _layer_of(surface: int) -> Array:
	match surface:
		Surface.FAIRWAY: return [splat_a, 0]
		Surface.GREEN: return [splat_a, 1]
		Surface.TEE: return [splat_a, 2]
		Surface.BUNKER: return [splat_a, 3]
		Surface.WATER: return [splat_b, 0]
		Surface.WOODS: return [splat_b, 1]
	return [splat_a, -1]


## The movable feature (green, tee box, bunker, pond) under `world`: the connected cells of
## its layer, soft edge included, as {"surface", "cells" (cell indices), "values", "rect"}.
## Empty when the point is not on one.
func region_at(world: Vector2) -> Dictionary:
	var c := cell_of(world)
	var x := int(c.x)
	var z := int(c.y)
	if x < 0 or z < 0 or x >= size.x or z >= size.y:
		return {}
	for surface in MOVABLE:
		var l: Array = _layer_of(surface)
		var bytes: PackedByteArray = l[0]
		var ch: int = l[1]
		if bytes[(z * size.x + x) * 4 + ch] < 128:
			continue
		# flood the connected feature, down to its faint soft edge
		var seen := {}
		var cells := PackedInt32Array()
		var values := PackedByteArray()
		var stack: Array[int] = [z * size.x + x]
		var x0 := x
		var x1 := x
		var z0 := z
		var z1 := z
		while not stack.is_empty() and cells.size() < 250000:
			var i: int = stack.pop_back()
			if seen.has(i):
				continue
			seen[i] = true
			var v := bytes[i * 4 + ch]
			if v < 8:
				continue
			cells.append(i)
			values.append(v)
			var cx := i % size.x
			var cz := i / size.x
			x0 = mini(x0, cx)
			x1 = maxi(x1, cx)
			z0 = mini(z0, cz)
			z1 = maxi(z1, cz)
			if cx > 0: stack.append(i - 1)
			if cx < size.x - 1: stack.append(i + 1)
			if cz > 0: stack.append(i - size.x)
			if cz < size.y - 1: stack.append(i + size.x)
		return {"surface": surface, "cells": cells, "values": values, "rect": Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)}
	return {}


## Moves a feature found by region_at() by `offset` cells: lifts it (rough is left behind)
## and lays it down again, clearing whatever exclusive surface and woods it lands on, as
## painting does. Cells shifted off the canvas are dropped. Returns the touched rect.
func move_region(region: Dictionary, offset: Vector2i) -> Rect2i:
	var l: Array = _layer_of(int(region["surface"]))
	var ch: int = l[1]
	var on_a: bool = int(region["surface"]) != Surface.WATER
	var cells: PackedInt32Array = region["cells"]
	var values: PackedByteArray = region["values"]
	for i in cells:
		if on_a:
			splat_a[i * 4 + ch] = 0
		else:
			splat_b[i * 4 + ch] = 0
	for k in range(cells.size()):
		var i := cells[k]
		var nx := i % size.x + offset.x
		var nz := i / size.x + offset.y
		if nx < 0 or nz < 0 or nx >= size.x or nz >= size.y:
			continue
		var j := nz * size.x + nx
		var v := values[k] / 255.0
		var keep := 1.0 - v
		for c in range(4):
			if not (on_a and c == ch):
				splat_a[j * 4 + c] = int(splat_a[j * 4 + c] * keep)
		for c in range(2):
			if not (not on_a and c == ch):
				splat_b[j * 4 + c] = int(splat_b[j * 4 + c] * keep)
		if on_a:
			splat_a[j * 4 + ch] = maxi(splat_a[j * 4 + ch], values[k])
		else:
			splat_b[j * 4 + ch] = maxi(splat_b[j * 4 + ch], values[k])
	revision += 1
	var r: Rect2i = region["rect"]
	return r.merge(Rect2i(r.position + offset, r.size)).intersection(full_rect())


## Copies the splat layers inside `rect` back from `src` (same canvas): undoing a drag preview.
func copy_layers_from(src: PaintedCourse, rect: Rect2i) -> void:
	rect = rect.intersection(full_rect())
	for z in range(rect.position.y, rect.end.y):
		var i0 := (z * size.x + rect.position.x) * 4
		for k in range(rect.size.x * 4):
			splat_a[i0 + k] = src.splat_a[i0 + k]
			splat_b[i0 + k] = src.splat_b[i0 + k]


# ---------------------------------------------------------------- undo snapshots

## Full canvas state for undoing a map expansion (ordinary brush snapshots stay small).
func canvas_snapshot() -> Dictionary:
	return {"canvas_size": size, "origin": origin, "a": splat_a.duplicate(), "b": splat_b.duplicate(),
		"h": height.duplicate(), "trees": trees.duplicate(), "holes": holes.duplicate(true)}

## Copy of every layer inside `rect` (cells), for undo.
func snapshot(rect: Rect2i) -> Dictionary:
	var a := PackedByteArray()
	var b := PackedByteArray()
	var h := PackedFloat32Array()
	for z in range(rect.position.y, rect.end.y):
		var i0 := z * size.x + rect.position.x
		a.append_array(splat_a.slice(i0 * 4, (i0 + rect.size.x) * 4))
		b.append_array(splat_b.slice(i0 * 4, (i0 + rect.size.x) * 4))
		h.append_array(height.slice(i0, i0 + rect.size.x))
	return {"rect": rect, "a": a, "b": b, "h": h, "trees": trees.duplicate(), "holes": holes.duplicate(true)}


func restore(snap: Dictionary) -> void:
	if snap.has("canvas_size"):
		size = snap["canvas_size"]
		origin = snap["origin"]
		splat_a = (snap["a"] as PackedByteArray).duplicate()
		splat_b = (snap["b"] as PackedByteArray).duplicate()
		height = (snap["h"] as PackedFloat32Array).duplicate()
		trees = (snap["trees"] as Array).duplicate()
		holes = (snap["holes"] as Array).duplicate(true)
		revision += 1
		return
	var rect: Rect2i = snap["rect"]
	var a: PackedByteArray = snap["a"]
	var b: PackedByteArray = snap["b"]
	var h: PackedFloat32Array = snap["h"]
	var w := rect.size.x
	for row in range(rect.size.y):
		var z := rect.position.y + row
		var i0 := z * size.x + rect.position.x
		for k in range(w * 4):
			splat_a[i0 * 4 + k] = a[row * w * 4 + k]
			splat_b[i0 * 4 + k] = b[row * w * 4 + k]
		for k in range(w):
			height[i0 + k] = h[row * w + k]
	trees = (snap["trees"] as Array).duplicate()
	holes = (snap["holes"] as Array).duplicate(true)
	revision += 1


func full_rect() -> Rect2i:
	return Rect2i(0, 0, size.x, size.y)


# ---------------------------------------------------------------- images (for textures)

func splat_a_image() -> Image:
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, layer_a())


func splat_b_image() -> Image:
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, splat_b)


func height_image() -> Image:
	if pads.is_empty() and holes.is_empty():
		return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, height.to_byte_array())
	var h := height.duplicate()
	for tee in _tee_platforms():
		var rect := brush_rect(tee["center"],16.0)
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var world := origin+(Vector2(x,z)+Vector2(.5,.5))*CELL
				h[z*size.x+x]=_grade_tees(world,height[z*size.x+x])
	for p in pads:
		var half: Vector2 = p["half"]
		var r := half.length() + float(p.get("blend", PAD_BLEND))
		var a := cell_of((p["pos"] as Vector2) - Vector2(r, r))
		var b := cell_of((p["pos"] as Vector2) + Vector2(r, r))
		for z in range(maxi(int(a.y), 0), mini(int(ceil(b.y)) + 1, size.y)):
			for x in range(maxi(int(a.x), 0), mini(int(ceil(b.x)) + 1, size.x)):
				var w := origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * CELL
				h[z * size.x + x] = graded(w, h[z * size.x + x])
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, h.to_byte_array())


# ---------------------------------------------------------------- save / load

static func slug(p_name: String) -> String:
	var s := p_name.strip_edges().to_lower()
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_") if out != "" else "course"


func default_path() -> String:
	return DIR + slug(course_name) + EXT


static func _pack(bytes: PackedByteArray) -> Dictionary:
	return {"size": bytes.size(), "zstd": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}


static func _unpack(d: Dictionary) -> PackedByteArray:
	return Marshalls.base64_to_raw(String(d["zstd"])).decompress(int(d["size"]), FileAccess.COMPRESSION_ZSTD)


func to_dict() -> Dictionary:
	var hs: Array = []
	for h in holes:
		var bends: Array = []
		for b in h.get("bends", []):
			bends.append([snappedf(b.x, 0.01), snappedf(b.y, 0.01)])
		hs.append({"tee": [h["tee"].x, h["tee"].y], "pin": [h["pin"].x, h["pin"].y], "par": int(h.get("par", 0)), "bends": bends, "curve": bool(h.get("curve", false))})
	var ts: Array = []
	for t in trees:
		ts.append([t[0], snappedf(t[1].x, 0.01), snappedf(t[1].y, 0.01)])
	return {"version": VERSION, "name": course_name, "size": [size.x, size.y], "cell": CELL,
		"holes": hs, "trees": ts, "splat_a": _pack(splat_a), "splat_b": _pack(splat_b),
		"height": _pack(height.to_byte_array())}


static func from_dict(d: Dictionary) -> PaintedCourse:
	var c := create(String(d.get("name", "Course")), Vector2i(int(d["size"][0]), int(d["size"][1])))
	c.splat_a = _unpack(d["splat_a"])
	c.splat_b = _unpack(d["splat_b"])
	c.height = _unpack(d["height"]).to_float32_array()
	for h in d.get("holes", []):
		var bends: Array = []
		for b in h.get("bends", []):
			bends.append(Vector2(float(b[0]), float(b[1])))
		c.holes.append({"tee": Vector2(h["tee"][0], h["tee"][1]), "pin": Vector2(h["pin"][0], h["pin"][1]), "par": int(h.get("par", 0)), "bends": bends, "curve": bool(h.get("curve", false))})
	for t in d.get("trees", []):
		c.trees.append([String(t[0]), Vector2(float(t[1]), float(t[2]))])
	return c


func save(path: String = "") -> Error:
	if path == "":
		path = default_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


static func load_file(path: String) -> PaintedCourse:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return null
	return from_dict(parsed)


## Permanently remove a saved course file (and any half-written temp copy beside it).
static func delete_saved(path: String) -> Error:
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


## A saved course's name and hole count without decoding its layers ({} if unreadable).
static func peek(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {}
	return {"name": String(parsed.get("name", "")), "holes": (parsed.get("holes", []) as Array).size()}


## A saved course's name without decoding its layers ("" if the file can't be read).
static func peek_name(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return String(parsed.get("name", "")) if parsed is Dictionary else ""


## Saved courses, newest first: [{"path", "name", "holes", "modified"}].
static func list_saved() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for fname in dir.get_files():
		if not fname.ends_with(EXT):
			continue
		var path := DIR + fname
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		# cheap peek: name and hole count without decoding the layers
		var text := f.get_as_text()
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		out.append({"path": path, "name": String(parsed.get("name", fname)), "holes": (parsed.get("holes", []) as Array).size(), "modified": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b) -> bool: return a["modified"] > b["modified"])
	return out


## Tee shapes and grades are derived from routing, never baked into the saved
## sculpture. Moving a tee restores the original ground at its previous location.
func _tee_platforms() -> Array:
	if _tee_grade_revision == revision and _tee_grade_count == holes.size():return _tee_grades
	_tee_grades=[]
	for index in range(holes.size()):
		var hole:Dictionary=holes[index]
		var center:Vector2=hole["tee"]
		var route:=hole_route(index)
		var target:Vector2=route[1] if route.size()>1 else hole["pin"]
		var dir:Vector2=(target-center).normalized()
		if dir.is_zero_approx():dir=Vector2(0,-1)
		_tee_grades.append({"center":center,"dir":dir,"right":Vector2(-dir.y,dir.x),"height":raw_height_at(center)})
	_tee_grade_revision=revision;_tee_grade_count=holes.size()
	return _tee_grades

func _grade_tees(world:Vector2,h:float)->float:
	var best:=0.0
	var target:=h
	for tee in _tee_platforms():
		var offset:Vector2=world-tee["center"]
		if offset.length_squared()>256.0:continue
		var local:=Vector2(absf(offset.dot(tee["right"])),absf(offset.dot(tee["dir"])))
		var edge:=maxf(local.x-TEE_BOX_HALF.x,local.y-TEE_BOX_HALF.y)
		# Extra 2m of level ground keeps the coarse terrain triangles out of the
		# actual tee surface. The next 4m blend into the untouched sculpture.
		var weight:=1.0-smoothstep(2.0,6.0,edge)
		if weight>best:best=weight;target=float(tee["height"])
	return lerpf(h,target,best)

func _rectangular_tee_layer(layer:PackedByteArray)->void:
	for tee in _tee_platforms():
		var rect:=brush_rect(tee["center"],11.0)
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				var offset:Vector2=origin+(Vector2(x,z)+Vector2(.5,.5))*CELL-tee["center"]
				if offset.length_squared()>121.0:continue
				var local:=Vector2(absf(offset.dot(tee["right"])),absf(offset.dot(tee["dir"])))
				var edge:=maxf(local.x-TEE_BOX_HALF.x,local.y-TEE_BOX_HALF.y)
				var cover:=1.0-smoothstep(-1.0,0.0,edge)
				var index:=(z*size.x+x)*4
				layer[index+2]=roundi(cover*255.0)
				if cover>0.0:
					for channel in [0,1,3]:layer[index+channel]=roundi(layer[index+channel]*(1-cover))


## Exact shape near a routed tee; INF leaves unrelated painted practice tees alone.
func tee_rectangle_distance(world:Vector2)->float:
	var result:=INF
	for tee in _tee_platforms():
		var offset:Vector2=world-tee["center"]
		if offset.length_squared()>121.0:continue
		var q:=Vector2(absf(offset.dot(tee["right"])),absf(offset.dot(tee["dir"])))-TEE_BOX_HALF
		var distance:=Vector2(maxf(q.x,0),maxf(q.y,0)).length()+minf(maxf(q.x,q.y),0)
		result=minf(result,distance)
	return result
