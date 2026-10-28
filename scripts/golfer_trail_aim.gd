class_name GolferTrailAim
extends SkeletonModifier3D
## Aims GolferRig's trail-arm IK so the right PALM, not the right wrist, lands on the grip.
## The TwoBoneIK3D drives the RightHand bone (the wrist) to its target; this moves that target
## each frame to the grip point minus the wrist-to-palm offset in the hand's current
## orientation. Runs just before the trail-arm IK.

var bone := -1                       # RightHand
var grip_point: Node3D               # marker on the club where the right palm should sit
var target: Node3D                   # the IK's target (child of the Skeleton3D)
var palm_offset := Vector3.ZERO      # wrist -> palm-surface point, RightHand bone space


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bone < 0 or grip_point == null or target == null or not is_instance_valid(grip_point):
		return
	var hand := skeleton.get_bone_global_pose(bone)
	var grip := skeleton.global_transform.affine_inverse() * grip_point.global_position
	target.transform = Transform3D(hand.basis, grip - hand.basis.orthonormalized() * palm_offset)
