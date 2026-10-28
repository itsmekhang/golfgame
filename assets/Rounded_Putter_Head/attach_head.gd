class_name RoundedPutterHeadAttachment
extends RefCounted

# Change this path if you place the folder elsewhere in the project.
const HEAD_PATH := "res://Rounded_Putter_Head/rounded_putter_head_shaft_attachment.glb"

static func attach(
    shaft: Node3D,
    parent: Node3D,
    socket_world_position: Vector3,
    face_forward_world: Vector3 = Vector3.FORWARD
) -> Node3D:
    var scene := load(HEAD_PATH) as PackedScene
    if scene == null:
        push_error("Set HEAD_PATH to the imported rounded_putter_head_shaft_attachment.glb")
        return null
    var head := scene.instantiate() as Node3D
    var shaft_up := shaft.global_transform.basis.y.normalized()
    var back := -face_forward_world.normalized()
    back = back - shaft_up * back.dot(shaft_up)
    if back.length_squared() < 0.000001:
        head.free()
        push_error("The face direction must not be parallel to the shaft")
        return null
    back = back.normalized()
    var right := shaft_up.cross(back).normalized()
    parent.add_child(head)
    head.global_transform = Transform3D(Basis(right, shaft_up, back), socket_world_position)
    return head

# Example, assuming the shaft's origin is at its bottom:
# var face_direction := -club_root.global_transform.basis.z.normalized()
# var head := RoundedPutterHeadAttachment.attach(
#     shaft, club_root, shaft.global_position, face_direction)
