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
	hz.shore_width = 2.0
	hz.set_polygon(pts)
	hz.center = mid
	hz.max_depth = 0.7
	return hz


## Stream: a strip of `width` metres along an arbitrary polyline, edges wobbled.
static func make_stream(path: PackedVector2Array, width: float, rng: RandomNumberGenerator) -> WaterHazard:
	var hz := WaterHazard.new()
	hz.surface_kind = CourseLayout.SURFACE_WATER
	hz.is_creek = true
	hz.feature_name = "Creek"
	var n := path.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var phase := rng.randf_range(0.0, TAU)
	for i in range(n):
		var prev := path[maxi(i - 1, 0)]
		var next := path[mini(i + 1, n - 1)]
		var dir := (next - prev).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var w := width * (0.85 + 0.3 * sin(i * 1.7 + phase))
		left.append(path[i] + nrm * w * 0.5)
		right.append(path[i] - nrm * w * 0.5)
	var pts := PackedVector2Array()
	pts.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		pts.append(right[i])
	hz.shore_width = 2.0
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
	var lv := outline_levels(layout)
	if layout.water_floats_on_surface():
		water_level = lv["max"] + 0.15
	else:
		water_level = lv["min"] - 0.3


## Bed + banks: gentle bank down to just below the surface, then a bowl.
func depth_offset(base_h: float, xz: Vector2) -> float:
	if not bounds.has_point(xz):
		return 0.0
	var sd := signed_distance(xz)
	if sd >= shore_width:
		return 0.0
	var target: float
	if sd <= 0.0:
		var inside := -sd
		# creeks are only a few metres wide: their banks must drop within the first metre
		var bank := 0.7 if is_creek else 1.5
		target = water_level + 0.25 - 0.6 * smoothstep(0.0, bank, inside) - max_depth * smoothstep(bank, 8.0, inside)
	else:
		var t := 1.0 - smoothstep(0.0, shore_width, sd)
		target = lerpf(base_h, water_level + 0.25, t)
	return target - base_h


# ---- visuals ------------------------------------------------------------------

func build_visual() -> void:
	if _mesh != null:
		_mesh.queue_free()
		_mesh = null
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		push_warning("WaterHazard %s: polygon could not be triangulated" % feature_name)
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in polygon:
		st.set_normal(Vector3.UP)
		st.set_uv(p / TerrainBuilder.WATER_UV_DIV)
		st.add_vertex(Vector3(p.x, water_level, p.y))
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var tri := PackedVector2Array([polygon[a], polygon[b], polygon[c]])
		if signed_area(tri) < 0.0:
			var tmp := b
			b = c
			c = tmp
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "WaterSurface"
	_mesh.mesh = mesh
	_mesh.material_override = TerrainBuilder.water_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func notify_ball_entered(pos: Vector3) -> void:
	balls_swallowed += 1
	ball_entered.emit(pos)
