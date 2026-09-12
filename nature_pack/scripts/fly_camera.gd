extends Camera3D

@export var move_speed: float = 14.0
@export var mouse_sensitivity: float = 0.0025

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotation.y -= event.relative.x * mouse_sensitivity
        rotation.x = clampf(rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)

func _process(delta: float) -> void:
    var direction := Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_W): direction.z -= 1.0
    if Input.is_physical_key_pressed(KEY_S): direction.z += 1.0
    if Input.is_physical_key_pressed(KEY_A): direction.x -= 1.0
    if Input.is_physical_key_pressed(KEY_D): direction.x += 1.0
    if Input.is_physical_key_pressed(KEY_Q): direction.y -= 1.0
    if Input.is_physical_key_pressed(KEY_E): direction.y += 1.0
    var speed := move_speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
    position += global_basis * direction.normalized() * speed * delta
