extends CharacterBody3D
func _physics_process(delta: float) -> void:
    var move := Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_LEFT): move.x -= 1.0
    if Input.is_physical_key_pressed(KEY_RIGHT): move.x += 1.0
    if Input.is_physical_key_pressed(KEY_UP): move.z -= 1.0
    if Input.is_physical_key_pressed(KEY_DOWN): move.z += 1.0
    move = move.normalized() * 1.8
    velocity.x = move.x
    velocity.z = move.z
    if not is_on_floor(): velocity.y -= 9.8 * delta
    else: velocity.y = 0.0
    move_and_slide()
