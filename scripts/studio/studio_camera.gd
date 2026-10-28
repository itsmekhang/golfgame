class_name StudioCamera
extends Camera3D
## Course Studio camera: orbits a pivot on the ground. Right drag orbits, middle drag (or
## Shift + right drag) pans, the wheel zooms toward the cursor, WASD pans, Q/E turn, Home
## gives a straight-down map view. Eases toward its targets so moves feel smooth.

signal moved

var pivot := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-55.0)
var distance := 420.0
var min_distance := 12.0
var max_distance := 2800.0
## Ground height lookup (Callable(Vector2) -> float) so the pivot follows the terrain.
var ground_height: Callable

var _goal_pivot := Vector3.ZERO
var _goal_yaw := 0.0
var _goal_pitch := deg_to_rad(-55.0)
var _goal_distance := 420.0
var _orbiting := false
var _panning := false


func _ready() -> void:
	fov = 50.0
	far = 6000.0
	near = 0.25
	_goal_pivot = pivot
	_goal_yaw = yaw
	_goal_pitch = pitch
	_goal_distance = distance
	_apply()


func focus(p: Vector3, dist: float = -1.0) -> void:
	_goal_pivot = p
	if dist > 0.0:
		_goal_distance = clampf(dist, min_distance, max_distance)


func top_view() -> void:
	_goal_pitch = deg_to_rad(-89.0)


func handle_input(event: InputEvent, cursor_world: Variant) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed and not mb.shift_pressed
			_panning = mb.pressed and mb.shift_pressed
			return true
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			return true
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if mb.ctrl_pressed or mb.alt_pressed:
				return false  # brush size, handled by the studio
			var f := 0.85 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85
			var nd := clampf(_goal_distance * f, min_distance, max_distance)
			# zoom toward the point under the cursor
			if cursor_world is Vector3 and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_goal_pivot = _goal_pivot.lerp(cursor_world, 1.0 - nd / _goal_distance)
			_goal_distance = nd
			return true
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_goal_yaw -= mm.relative.x * 0.006
			_goal_pitch = clampf(_goal_pitch - mm.relative.y * 0.005, deg_to_rad(-89.0), deg_to_rad(-8.0))
			return true
		if _panning:
			var s := _goal_distance * 0.0016
			var right := Vector3(cos(_goal_yaw), 0.0, -sin(_goal_yaw))
			var fwd := Vector3(-sin(_goal_yaw), 0.0, -cos(_goal_yaw))
			_goal_pivot += (-right * mm.relative.x + fwd * mm.relative.y) * s
			return true
	return false


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if not _text_focus():
		if Input.is_physical_key_pressed(KEY_W): move.y += 1.0
		if Input.is_physical_key_pressed(KEY_S): move.y -= 1.0
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): move.x += 1.0
		if Input.is_physical_key_pressed(KEY_Q): _goal_yaw += delta * 1.4
		if Input.is_physical_key_pressed(KEY_E): _goal_yaw -= delta * 1.4
	if move != Vector2.ZERO and not Input.is_key_pressed(KEY_CTRL):
		var speed := _goal_distance * 0.9 * delta
		var right := Vector3(cos(_goal_yaw), 0.0, -sin(_goal_yaw))
		var fwd := Vector3(-sin(_goal_yaw), 0.0, -cos(_goal_yaw))
		_goal_pivot += (right * move.x + fwd * move.y) * speed
	if ground_height.is_valid():
		_goal_pivot.y = ground_height.call(Vector2(_goal_pivot.x, _goal_pivot.z))
	var k := 1.0 - exp(-delta * 12.0)
	pivot = pivot.lerp(_goal_pivot, k)
	yaw = lerp_angle(yaw, _goal_yaw, k)
	pitch = lerpf(pitch, _goal_pitch, k)
	distance = lerpf(distance, _goal_distance, k)
	_apply()


func _apply() -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var pos := pivot + dir * distance
	if ground_height.is_valid():
		pos.y = maxf(pos.y, ground_height.call(Vector2(pos.x, pos.z)) + 2.0)
	var up := Vector3.UP if pitch > deg_to_rad(-88.5) else Vector3(-sin(yaw), 0.0, -cos(yaw))
	look_at_from_position(pos, pivot, up)
	moved.emit()


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
