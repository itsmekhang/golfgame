class_name TerrainContact
extends RefCounted
## CPU height grids from the actual rendered tiles; no extra physics meshes.
var origin := Vector2.ZERO
var tiles: Dictionary = {}

## Split a flight segment at every grid edge and triangle diagonal it crosses.
## Within each interval the rendered ground is one plane, so its first hit can be
## solved continuously instead of skipping over a narrow lip between samples.
func segment_breaks(from: Vector2, to: Vector2) -> PackedFloat64Array:
	var cuts: Array[float] = [0.0, 1.0]
	var low := (from.min(to) - origin) / 64.0
	var high := (from.max(to) - origin) / 64.0
	for tz in range(int(floor(low.y)), int(floor(high.y)) + 1):
		for tx in range(int(floor(low.x)), int(floor(high.x)) + 1):
			var key := Vector2i(tx, tz)
			if not tiles.has(key):
				continue
			var tile: Dictionary = tiles[key]
			var start: Vector2 = tile.start
			var cell: float = tile.cell
			var a := (from - start) / cell
			var b := (to - start) / cell
			_append_axis_cuts(cuts, a.x, b.x, int(tile.width) - 1)
			_append_axis_cuts(cuts, a.y, b.y, int(tile.depth) - 1)
			_append_axis_cuts(cuts, a.x + a.y, b.x + b.y, int(tile.width) + int(tile.depth) - 2)
	cuts.sort()
	return PackedFloat64Array(cuts)

static func _append_axis_cuts(cuts: Array[float], a: float, b: float, last: int) -> void:
	if absf(b - a) < 0.000001:
		return
	for line in range(maxi(0, int(ceil(minf(a, b)))), mini(last, int(floor(maxf(a, b)))) + 1):
		var t := (float(line) - a) / (b - a)
		if t > 0.0 and t < 1.0:
			cuts.append(t)

func register_tile(key: Vector2i, start: Vector2, cell: float, width: int, depth: int, heights: PackedFloat32Array) -> void:
	tiles[key] = {"start": start, "cell": cell, "width": width, "depth": depth, "heights": heights}

## Lowest safe centre height for a sphere over the rendered mesh. Near a crease,
## neighbouring faces and edges can support the sphere before its centre reaches
## them. Looking only at the centre's triangle lets its side enter a bunker bank.
func support_height(x: float, z: float, radius: float) -> float:
	var plane := sample(x, z)
	var xz := Vector2(x, z)
	var key := Vector2i(int(floor((x - origin.x) / 64.0)), int(floor((z - origin.y) / 64.0)))
	if is_finite(plane.x):
		var tile: Dictionary = tiles[key]
		var cell: float = tile.cell
		var local := (xz - (tile.start as Vector2)) / cell
		var fx := local.x - floorf(local.x)
		var fz := local.y - floorf(local.y)
		var edge := minf(minf(fx, 1.0 - fx), minf(fz, 1.0 - fz))
		edge = minf(edge, absf(fx + fz - 1.0) / sqrt(2.0)) * cell
		# Most positions are wholly inside one face: keep that common query cheap.
		if edge > radius:
			return plane.x + radius * sqrt(1.0 + plane.y * plane.y + plane.z * plane.z)
	var best := -INF
	var low := (xz - Vector2.ONE * radius - origin) / 64.0
	var high := (xz + Vector2.ONE * radius - origin) / 64.0
	for tz in range(int(floor(low.y)), int(floor(high.y)) + 1):
		for tx in range(int(floor(low.x)), int(floor(high.x)) + 1):
			var tile_key := Vector2i(tx, tz)
			if not tiles.has(tile_key):
				continue
			var tile: Dictionary = tiles[tile_key]
			var cell: float = tile.cell
			var start: Vector2 = tile.start
			var local := (xz - start) / cell
			var width: int = tile.width
			var depth: int = tile.depth
			var h: PackedFloat32Array = tile.heights
			var reach := radius / cell
			var ix0 := maxi(0, int(floor(local.x - reach)))
			var ix1 := mini(width - 2, int(floor(local.x + reach)))
			var iz0 := maxi(0, int(floor(local.y - reach)))
			var iz1 := mini(depth - 2, int(floor(local.y + reach)))
			for iz in range(iz0, iz1 + 1):
				for ix in range(ix0, ix1 + 1):
					var index := iz * width + ix
					# Work relative to the ball in XZ to retain millimetre precision.
					var px := float(start.x) + ix * cell - x
					var pz := float(start.y) + iz * cell - z
					var a := Vector3(px, h[index], pz)
					var b := Vector3(px + cell, h[index + 1], pz)
					var c := Vector3(px, h[index + width], pz + cell)
					var d := Vector3(px + cell, h[index + width + 1], pz + cell)
					best = maxf(best, _triangle_support(a, b, c, radius))
					best = maxf(best, _triangle_support(b, d, c, radius))
	return best if is_finite(best) else INF

static func _triangle_support(a: Vector3, b: Vector3, c: Vector3, radius: float) -> float:
	var normal := (b - a).cross(c - a)
	var slope := Vector2(-normal.x / normal.y, -normal.z / normal.y)
	var factor := sqrt(1.0 + slope.length_squared())
	var contact := slope * (radius / factor)
	var av := Vector2(a.x, a.z)
	var bv := Vector2(b.x, b.z)
	var cv := Vector2(c.x, c.z)
	# The maximum over the infinite plane is valid only if it lies on this face.
	if (bv - av).cross(contact - av) >= 0.0 and (cv - bv).cross(contact - bv) >= 0.0 and (av - cv).cross(contact - cv) >= 0.0:
		return a.y - slope.dot(av) + radius * factor
	return maxf(_edge_support(a, b, radius), maxf(_edge_support(b, c, radius), _edge_support(c, a, radius)))

static func _edge_support(a: Vector3, b: Vector3, radius: float) -> float:
	var av := Vector2(a.x, a.z)
	var edge := Vector2(b.x - a.x, b.z - a.z)
	var length := edge.length()
	var direction := edge / length
	var projected := -av.dot(direction)
	var perpendicular := av + direction * projected
	var available := radius * radius - perpendicular.length_squared()
	if available < 0.0:
		return -INF
	var slope := (b.y - a.y) / length
	var along := clampf(projected + slope * sqrt(available / (1.0 + slope * slope)), 0.0, length)
	var remaining := available - (along - projected) * (along - projected)
	if remaining < -0.0000001:
		return -INF
	return a.y + slope * along + sqrt(maxf(0.0, remaining))

## Returns height and X/Z slopes of the same triangle used by TerrainBuilder.
func sample(x: float, z: float) -> Vector3:
	var key := Vector2i(int(floor((x - origin.x) / 64.0)), int(floor((z - origin.y) / 64.0)))
	if not tiles.has(key):
		return Vector3(INF, 0, 0)
	var tile: Dictionary = tiles[key]
	var p := (Vector2(x, z) - (tile.start as Vector2)) / float(tile.cell)
	if p.x < 0 or p.y < 0 or p.x > tile.width - 1 or p.y > tile.depth - 1:
		return Vector3(INF, 0, 0)
	var ix := mini(int(floor(p.x)), int(tile.width) - 2)
	var iz := mini(int(floor(p.y)), int(tile.depth) - 2)
	var fx := p.x - ix
	var fz := p.y - iz
	var heights: PackedFloat32Array = tile.heights
	var index: int = iz * int(tile.width) + ix
	var h00 := heights[index]
	var h10 := heights[index + 1]
	var h01 := heights[index + int(tile.width)]
	var h11 := heights[index + int(tile.width) + 1]
	var dx: float
	var dz: float
	var h: float
	if fx + fz <= 1.0:
		dx = h10 - h00
		dz = h01 - h00
		h = h00 + fx * dx + fz * dz
	else:
		dx = h11 - h01
		dz = h11 - h10
		h = h11 - (1.0 - fx) * dx - (1.0 - fz) * dz
	return Vector3(h, dx / float(tile.cell), dz / float(tile.cell))
