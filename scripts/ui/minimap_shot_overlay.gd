class_name MinimapShotOverlay
extends Control
## Live shot graphics above the cached map. Both paths come from the main view.

var _projection := Transform2D.IDENTITY
var _preview := PackedVector3Array()
var _tail := PackedVector3Array()
var _preview_points := PackedVector2Array()
var _tail_points := PackedVector2Array()
var _tail_colors := PackedColorArray()
var _landing := Vector3.ZERO
var _ball := Vector3.ZERO
var _show_preview := false
var _show_tail := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func configure(rect: Rect2, projection: Transform2D) -> void:
	position = rect.position
	size = rect.size
	if projection == _projection:
		return
	_projection = projection
	_preview_points = _project_path(_preview)
	_tail_points = _project_path(_tail)
	queue_redraw()

func set_preview(points: PackedVector3Array, landing: Vector3) -> void:
	_preview = points
	_landing = landing
	_preview_points = _project_path(points)
	queue_redraw()

func set_tail(points: PackedVector3Array) -> void:
	_tail = points
	_tail_points = _project_path(points)
	_tail_colors.resize(points.size())
	for i in range(points.size()):
		var t := float(i) / maxf(points.size() - 1, 1)
		_tail_colors[i] = Color(1, 1, 1, t * t * 0.9)
	queue_redraw()

func update_ball(point: Vector3, show_preview: bool, show_tail: bool) -> void:
	if _ball == point and _show_preview == show_preview and _show_tail == show_tail:
		return
	_ball = point
	_show_preview = show_preview
	_show_tail = show_tail
	queue_redraw()

func _project(point: Vector3) -> Vector2:
	return _projection * Vector2(point.x, point.z)

func _project_path(points: PackedVector3Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	projected.resize(points.size())
	for i in range(points.size()):
		projected[i] = _project(points[i])
	return projected

func _draw() -> void:
	if _show_preview and _preview_points.size() >= 2:
		draw_polyline(_preview_points, Color(1.0, 0.9, 0.2, 0.9), 1.5, true)
		draw_arc(_project(_landing), 3.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.2, 0.85), 1.2, true)
	if _show_tail and _tail_points.size() >= 2:
		draw_polyline_colors(_tail_points, _tail_colors, 1.5, true)
	var center := _project(_ball)
	draw_circle(center, 2.7, Color(0.05, 0.1, 0.05, 0.65), true, -1.0, true)
	draw_circle(center, 2.0, Color.WHITE, true, -1.0, true)
