class_name GolferGripFingers
extends SkeletonModifier3D
## Closes GolferRig's hands on the grip. The Mixamo swings were captured without a club, so the
## fingers hang half open. Every frame this curls the index..pinky chains of both hands toward
## their palm, each joint about its own bend axis (bone direction x palm normal), by a fixed
## extra angle per knuckle. Runs after the arm IKs, so it works on the final hand pose.

const FINGERS := ["Index", "Middle", "Ring", "Pinky"]
## Extra curl per knuckle (degrees): base, middle and tip joints.
const CURL_DEG := [38.0, 52.0, 32.0]

var prefix := "mixamorig12_"
var palm_normal_left := Vector3.ZERO   # palm-facing direction in LeftHand bone space
var palm_normal_right := Vector3.ZERO  # palm-facing direction in RightHand bone space
var _chains: Array = []  # [hand_bone, normal_local, [b1, b2, b3, b4]] per finger


func _setup_chains(skeleton: Skeleton3D) -> void:
	_chains.clear()
	for side in [["Left", palm_normal_left], ["Right", palm_normal_right]]:
		var hand := skeleton.find_bone(prefix + side[0] + "Hand")
		if hand < 0 or side[1] == Vector3.ZERO:
			continue
		for f in FINGERS:
			var bones: Array[int] = []
			for j in range(1, 5):
				bones.append(skeleton.find_bone("%s%sHand%s%d" % [prefix, side[0], f, j]))
			if not bones.has(-1):
				_chains.append([hand, side[1], bones])


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _chains.is_empty():
		_setup_chains(skeleton)
	for chain in _chains:
		var normal: Vector3 = (skeleton.get_bone_global_pose(chain[0]).basis.orthonormalized() * chain[1]).normalized()
		var bones: Array = chain[2]
		for j in range(3):
			var bone: int = bones[j]
			var pose := skeleton.get_bone_global_pose(bone)
			var dir := skeleton.get_bone_global_pose(bones[j + 1]).origin - pose.origin
			if dir.length() < 0.0001:
				continue
			var axis := dir.normalized().cross(normal)
			if axis.length() < 0.001:
				continue
			var turned := Basis(axis.normalized(), deg_to_rad(CURL_DEG[j])) * pose.basis.orthonormalized()
			var parent := skeleton.get_bone_parent(bone)
			var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized()
			skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())
