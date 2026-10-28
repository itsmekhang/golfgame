class_name OpenHand
extends SkeletonModifier3D
## A hand held open and flat, fingers straight up from the palm (a wave, a high five), over
## whatever its animation does with them: the cart boy's drying hand, its rag pressed under the
## palm (ClubLife._rag_on). Its fingers' bones set back to their rest -- straight on from the hand
## -- each frame after the animation; the thumb spread off them a little.

var bones := PackedInt32Array()  # the hand's finger bones
var thumbs := PackedInt32Array()  # its thumb's, among them


## Open hand `side` ("L" / "R") of `skel`'s rig.
static func on(skel: Skeleton3D, side: String) -> OpenHand:
	var m := OpenHand.new()
	m.name = "OpenHand" + side
	for i in range(skel.get_bone_count()):
		var n := skel.get_bone_name(i)
		if n.begins_with("finger_") and n.ends_with("." + side):
			m.bones.append(i)
			if n.contains("thumb"):
				m.thumbs.append(i)
	skel.add_child(m)
	return m


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for b in bones:
		var rest := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		if b in thumbs and skel.get_bone_name(b).contains("thumb1"):
			rest = rest * Quaternion(Vector3.FORWARD, deg_to_rad(18.0))  # (out off the fingers)
		skel.set_bone_pose_rotation(b, rest)
