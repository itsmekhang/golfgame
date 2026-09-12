class_name SurfaceZone
extends Area3D
## Local lie-surface override. Add this to an Area3D with a CollisionShape3D;
## any ball position inside the shape resolves to `surface_type`, overriding
## the CourseLayout surface (mirrors OpenFairway's SurfaceZone.cs).

@export var surface_type: PhysicsEnums.SurfaceType = PhysicsEnums.SurfaceType.FAIRWAY


func _ready() -> void:
	monitoring = false
	monitorable = false
	add_to_group("surface_zones")


func contains_point(point: Vector3) -> bool:
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			var local: Vector3 = child.global_transform.affine_inverse() * point
			var shape: Shape3D = child.shape
			if shape is BoxShape3D:
				var half: Vector3 = (shape as BoxShape3D).size * 0.5
				if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
					return true
			elif shape is SphereShape3D:
				if local.length() <= (shape as SphereShape3D).radius:
					return true
			elif shape is CylinderShape3D:
				var cyl := shape as CylinderShape3D
				if Vector2(local.x, local.z).length() <= cyl.radius and absf(local.y) <= cyl.height * 0.5:
					return true
	return false
