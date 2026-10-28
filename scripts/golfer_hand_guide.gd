class_name GolferHandGuide
extends SkeletonModifier3D
## Feeds GolferRig's lead-arm IK. The Mixamo swings bring the hands through impact well outside
## and above where they were at address (no club in the capture), so even a perfectly angled
## club can't reach the ball from there. Each frame this puts `target` on the mocap's lead-hand
## pose, shifted by `offset` -- the address-minus-impact hand position -- with a weight that
## ramps in from the top of the backswing, peaks at impact and fades into the follow-through.
## The TwoBoneIK3D that follows (LeftArm > LeftForeArm > LeftHand) then returns the hands to
## their address spot at impact, as a real golfer's do.

var bone := -1
var anim: AnimationPlayer
var target: Node3D            # child of the Skeleton3D, so its transform is skeleton space
var offset := Vector3.ZERO       # impact correction, applied with the ramp weight
var base_offset := Vector3.ZERO  # applied all the time (e.g. lower hands for a short putter)
var t_start := 0.0
var t_full := 1.2
var t_end := 1.4


func weight_at(t: float) -> float:
	if t <= t_start or t >= t_end:
		return 0.0
	if t <= t_full:
		return smoothstep(t_start, t_full, t)
	return 1.0 - smoothstep(t_full, t_end, t)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bone < 0 or target == null:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var w := 0.0
	if anim != null and anim.current_animation != "":
		w = weight_at(anim.current_animation_position)
	target.transform = Transform3D(pose.basis, pose.origin + base_offset + offset * w)
