class_name WaterHazard
extends Excavation
## One water hazard: a pond blob or creek strip, a water level, a terrain bed/bank
## profile, and the water surface mesh. The ball asks `contains()` /
## `CourseLayout.hazard_at()` to flag splashes.

signal ball_entered(position: Vector3)

var hazard_name: String:
	get:
		return feature_name
	set(v):
		feature_name = v

var water_level: float = 0.0
var is_creek: bool = false
var auto_extend: bool = true
## Streams use a longitudinal water profile, while ponds remain level.
var follow_terrain: bool = false
var _stream_path := PackedVector2Array()
var _stream_width := 0.0
var _flow_path := PackedVector2Array()
var _flow_levels := PackedFloat32Array()
var _joined_pond: WaterHazard
var max_depth: float = 1.6  # bed depth below the water surface at the middle
var balls_swallowed: int = 0

var _mesh: MeshInstance3D


func _init() -> void:
	feature_name = "Pond"
	shore_width = 3.5


# ---- factories ----------------------------------------------------------------

static func make_blob(p_center: Vector2, radius: float, rng: RandomNumberGenerator,
		aspect: float = 1.0, rotation_rad: float = 0.0, vertex_count: int = 20) -> WaterHazard:
	var hz := WaterHazard.new()
	hz.surface_kind = CourseLayout.SURFACE_WATER
	hz.set_polygon(Excavation.blob_polygon(p_center, radius, rng, aspect, rotation_rad, vertex_count))
	hz.center = p_center
	hz.max_depth = clampf(radius * 0.12, 0.8, 2.2)
	return hz


## Creek: a wavy strip of `width` metres from `start` to `end`.
static func make_creek(start: Vector2, end: Vector2, width: float, rng: RandomNumberGenerator,
		segments: int = 10) -> WaterHazard:
	var hz := WaterHazard.new()
	hz.surface_kind = CourseLayout.SURFACE_WATER
	hz.is_creek = true
	hz.follow_terrain = true
	hz._stream_width = width
	hz.feature_name = "Creek"
	var dir := (end - start).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var length := start.distance_to(end)
	var amp := rng.randf_range(2.0, 5.0)
	var phase := rng.randf_range(0.0, TAU)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var mid := (start + end) * 0.5
	for i in range(segments + 1):
		var t := float(i) / segments
		var p := start + dir * length * t + nrm * (sin(t * TAU * 0.9 + phase) * amp)
		hz._stream_path.append(p)
		var w := width * (0.8 + 0.4 * sin(t * 7.0 + phase))
		left.append(p + nrm * w * 0.5)
		right.append(p - nrm * w * 0.5)
		if i == int(segments / 2):
			mid = p
	var pts := PackedVector2Array()
	for p in left:
		pts.append(p)
	for i in range(right.size() - 1, -1, -1):
		pts.append(right[i])
	pts = Excavation.smooth_polygon(pts, 2)
	hz.shore_width = 6.0
	hz.set_polygon(pts)
	hz.center = mid
	hz.max_depth = 0.7
	return hz


## Stream: a strip of `width` metres along an arbitrary polyline, edges wobbled.
static func make_stream(path: PackedVector2Array, width: float, rng: RandomNumberGenerator) -> WaterHazard:
	var hz := WaterHazard.new()
	hz._stream_path = path.duplicate()
	hz._stream_width = width
	hz.follow_terrain = true
	hz.surface_kind = CourseLayout.SURFACE_WATER
	hz.is_creek = true
	hz.feature_name = "Creek"
	var n := path.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var phase := rng.randf_range(0.0, TAU)
	var along := 0.0
	for i in range(n):
		if i > 0:
			along += path[i - 1].distance_to(path[i])
		var prev := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		# Width varies over metres, not vertex count: densely traced curves must
		# not acquire a sawtooth bank from rapidly alternating sample widths.
		var w := width * (0.95 + 0.10 * sin(along * 0.12 + phase))
		left.append(path[i] + nrm * w * 0.5)
		right.append(path[i] - nrm * w * 0.5)
	var pts := PackedVector2Array()
	pts.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		pts.append(right[i])
	hz.shore_width = 6.0
	hz.set_polygon(Excavation.smooth_polygon(pts, 2))
	hz.center = path[n / 2]
	hz.max_depth = 0.6
	return hz


static func from_polygon(pts: PackedVector2Array) -> WaterHazard:
	var hz := WaterHazard.new()
	hz.surface_kind = CourseLayout.SURFACE_WATER
	hz.set_polygon(pts)
	hz.max_depth = clampf(sqrt(hz.area_m2() / PI) * 0.12, 0.8, 2.2)
	return hz


# ---- geometry -----------------------------------------------------------------

## Water level sits just below the lowest bank so the surface never pokes through turf.
func finalize(layout: CourseLayout) -> void:
	super.finalize(layout)
	_joined_pond = null
	_flow_path.clear()
	_flow_levels.clear()
	if follow_terrain and is_creek and _stream_path.is_empty():
		# Traced narrow creek polygons do not carry a separate routing polyline.
		var axis := CourseLayout._polygon_axis(polygon)
		_stream_path = PackedVector2Array([axis[0], axis[1]])
		_stream_width = float(axis[3])
	if follow_terrain and _stream_path.size() >= 2:
		# Closely spaced bank samples keep a shallow channel along the hillside.
		# The cross-channel surface is level; only its along-stream height changes.
		for i in range(1, _stream_path.size()):
			var a := _stream_path[i - 1]
			var b := _stream_path[i]
			var direction := (b - a).normalized()
			var side := Vector2(-direction.y, direction.x) * _stream_width * 0.6
			var steps := maxi(1, ceili(a.distance_to(b) / 4.0))
			for j in range(steps + 1):
				if i > 1 and j == 0:
					continue
				var p := a.lerp(b, float(j) / steps)
				var left := layout.base_height_at(p.x + side.x, p.y + side.y)
				var right := layout.base_height_at(p.x - side.x, p.y - side.y)
				var middle := layout.base_height_at(p.x, p.y)
				_flow_path.append(p)
				_flow_levels.append(minf(middle, minf(left, right)) - 0.3)
		water_level = water_level_at(center)
		return
	var lv := outline_levels(layout)
	if layout.water_floats_on_surface():
		water_level = lv["max"] + 0.15
	else:
		water_level = lv["min"] - 0.3


## Shared by the visible water, channel bed and ball splash detection.
func water_level_at(xz: Vector2) -> float:
	var best := INF
	var level := water_level
	for i in range(1, _flow_path.size()):
		var a := _flow_path[i - 1]
		var ab := _flow_path[i] - a
		var t := clampf((xz - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var distance := xz.distance_squared_to(a + ab * t)
		if distance < best:
			best = distance
			level = lerpf(_flow_levels[i - 1], _flow_levels[i], t)
	return level


func join_pond_level(at_start: bool, level: float, pond: WaterHazard = null) -> void:
	_joined_pond = pond
	# Keep the entire overlap level, including the full width of the mouth.
	# Blending immediately at the endpoint makes two intersecting water planes.
	var flat_length := 0.0
	if pond != null:
		var along := 0.0
		var last := 0 if at_start else _flow_path.size() - 1
		for step in range(_flow_path.size()):
			var i := step if at_start else _flow_path.size() - 1 - step
			along += _flow_path[i].distance_to(_flow_path[last])
			if pond.signed_distance(_flow_path[i]) < _stream_width:
				flat_length = along
			last = i
	var distance := 0.0
	var previous := 0 if at_start else _flow_path.size() - 1
	for step in range(_flow_path.size()):
		var i := step if at_start else _flow_path.size() - 1 - step
		distance += _flow_path[i].distance_to(_flow_path[previous])
		if distance > flat_length + 32.0: break
		_flow_levels[i] = lerpf(_flow_levels[i], level, 1.0 - smoothstep(flat_length, flat_length + 32.0, distance))
		previous = i
	water_level = water_level_at(center)


## Bed + banks: gentle bank down to just below the surface, then a bowl.
func depth_offset(base_h: float, xz: Vector2) -> float:
	if not bounds.has_point(xz):
		return 0.0
	var sd := signed_distance(xz)
	if sd >= shore_width:
		return 0.0
	var target: float
	var local_level := water_level_at(xz)
	if sd <= 0.0:
		var inside := -sd
		# A shallow inner bank avoids a sharp ledge at the waterline.
		var bank := 1.5
		target = local_level + 0.25 - 0.6 * smoothstep(0.0, bank, inside) - max_depth * smoothstep(bank, 8.0, inside)
	else:
		var t := 1.0 - smoothstep(0.0, shore_width, sd)
		target = lerpf(base_h, local_level + 0.25, t)
	return target - base_h


# ---- visuals ------------------------------------------------------------------

func build_visual() -> void:
	if _mesh != null:
		_mesh.queue_free()
		_mesh = null
	var outlines: Array[PackedVector2Array] = [polygon]
	if _joined_pond != null:
		# One visible surface at the confluence: coplanar overlapping meshes
		# otherwise flicker even when their water levels agree exactly.
		outlines = Geometry2D.clip_polygons(polygon, _joined_pond.polygon)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangle_count := 0
	for outline in outlines:
		var indices := Geometry2D.triangulate_polygon(outline)
		for i in range(0, indices.size(), 3):
			var a := outline[indices[i]]
			var b := outline[indices[i + 1]]
			var c := outline[indices[i + 2]]
			if signed_area(PackedVector2Array([a,b,c])) < 0.0:
				var swap := b
				b = c
				c = swap
			if _flow_path.is_empty():
				for p in [a,b,c]:
					st.set_normal(Vector3.UP)
					st.set_uv(p / TerrainBuilder.WATER_UV_DIV)
					st.add_vertex(Vector3(p.x, water_level, p.y))
			else:
				_emit_flow_triangle(st, a, b, c)
			triangle_count += 1
	if triangle_count == 0: return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "WaterSurface"
	_mesh.mesh = mesh
	_mesh.material_override = TerrainBuilder.water_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _emit_flow_triangle(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, depth: int = 0) -> void:
	# Subdivide long polygon diagonals so the mesh follows the sampled stream grade.
	var ab := a.distance_squared_to(b)
	var bc := b.distance_squared_to(c)
	var ca := c.distance_squared_to(a)
	if maxf(ab, maxf(bc, ca)) > 36.0 and depth < 16:
		if ab >= bc and ab >= ca:
			var m := (a + b) * 0.5
			_emit_flow_triangle(st, a, m, c, depth + 1)
			_emit_flow_triangle(st, m, b, c, depth + 1)
		elif bc >= ca:
			var m := (b + c) * 0.5
			_emit_flow_triangle(st, a, b, m, depth + 1)
			_emit_flow_triangle(st, a, m, c, depth + 1)
		else:
			var m := (c + a) * 0.5
			_emit_flow_triangle(st, a, b, m, depth + 1)
			_emit_flow_triangle(st, m, b, c, depth + 1)
		return
	for p in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.set_uv(p / TerrainBuilder.WATER_UV_DIV)
		st.add_vertex(Vector3(p.x, water_level_at(p), p.y))


func notify_ball_entered(pos: Vector3) -> void:
	balls_swallowed += 1
	ball_entered.emit(pos)
