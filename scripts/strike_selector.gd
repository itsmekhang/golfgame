class_name StrikeSelector
extends Control
## Ball-face strike point picker: drag inside the circle to choose where the club
## contacts the ball, instead of a timed accuracy tap.
##
##  - Horizontal offset (x) is heel/toe contact -> shot shape: push/pull and side
##    spin, same role the old timed "accuracy" bar played.
##  - Vertical offset (y) is low/high contact -> loft and spin: a strike below
##    centre (y < 0) adds loft and backspin but costs ball speed (a "lofted" hit,
##    shorter carry); a strike above centre (y > 0) flattens the launch, cuts spin
##    and rolls out more, with distance falling off again near the top (a thin hit).
##
## `offset` is in [-1, 1] on both axes and (0, 0) is the sweet spot (full speed,
## the club's stock loft and spin).

signal strike_changed(offset: Vector2)

const RADIUS := 42.0
const SWEET_SPOT := 0.16  # fraction of the radius that counts as a pure strike
const BALL_TEXTURE_PATH := "res://assets/textures/ui/golf_ball_icon.png"

var offset := Vector2.ZERO
var _dragging := false
static var _ball_texture: Texture2D = null


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 14.0, RADIUS * 2.0 + 14.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _ball_texture == null and ResourceLoader.exists(BALL_TEXTURE_PATH):
		_ball_texture = load(BALL_TEXTURE_PATH)


func _draw() -> void:
	var c := size * 0.5
	if _ball_texture != null:
		draw_texture_rect(_ball_texture, Rect2(c - Vector2.ONE * RADIUS, Vector2.ONE * RADIUS * 2.0), false)
	else:
		draw_circle(c, RADIUS, Color(1.0, 1.0, 1.0, 0.92))
		draw_arc(c, RADIUS, 0.0, TAU, 48, Color(0.15, 0.15, 0.15, 0.8), 2.0, true)
	draw_line(c - Vector2(RADIUS - 3.0, 0.0), c + Vector2(RADIUS - 3.0, 0.0), Color(0.15, 0.15, 0.15, 0.22), 1.0)
	draw_line(c - Vector2(0.0, RADIUS - 3.0), c + Vector2(0.0, RADIUS - 3.0), Color(0.15, 0.15, 0.15, 0.22), 1.0)
	draw_arc(c, RADIUS * SWEET_SPOT, 0.0, TAU, 20, Color(0.3, 0.75, 0.25, 0.85), 1.5, true)
	var mark := c + Vector2(offset.x, -offset.y) * (RADIUS - 6.0)
	draw_circle(mark, 6.5, Color(0.95, 0.2, 0.15, 0.95))
	draw_arc(mark, 6.5, 0.0, TAU, 18, Color(0.1, 0.0, 0.0, 0.9), 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from_local(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_local(event.position)
		accept_event()


func _set_from_local(local_pos: Vector2) -> void:
	var c := size * 0.5
	var v := (local_pos - c) / (RADIUS - 6.0)
	if v.length() > 1.0:
		v = v.normalized()
	offset = Vector2(v.x, -v.y)
	queue_redraw()
	strike_changed.emit(offset)


func reset() -> void:
	offset = Vector2.ZERO
	queue_redraw()
	strike_changed.emit(offset)


## Human-readable summary, e.g. "toe, low (extra loft)".
func describe() -> String:
	var parts := PackedStringArray()
	if absf(offset.x) > SWEET_SPOT:
		parts.append("toe" if offset.x > 0.0 else "heel")
	if offset.y < -SWEET_SPOT:
		parts.append("low (extra loft, less speed)")
	elif offset.y > SWEET_SPOT:
		parts.append("high (flatter, more roll)")
	if parts.is_empty():
		return "sweet spot"
	return ", ".join(parts)
