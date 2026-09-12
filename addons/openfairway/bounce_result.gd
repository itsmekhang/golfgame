class_name BounceResult
extends RefCounted
## GDScript port of OpenFairway `BounceResult.cs`.

var new_velocity: Vector3 = Vector3.ZERO
var new_omega: Vector3 = Vector3.ZERO
var new_state: int = PhysicsEnums.BallState.REST


func _init(vel: Vector3 = Vector3.ZERO, omg: Vector3 = Vector3.ZERO, st: int = PhysicsEnums.BallState.REST) -> void:
	new_velocity = vel
	new_omega = omg
	new_state = st
