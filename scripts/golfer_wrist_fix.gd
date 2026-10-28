class_name GolferWristFix
extends SkeletonModifier3D
## Keeps GolferRig's club on a swing plane that suits the club. The Mixamo swings were captured
## without a club (and for a driver's flat plane), so a short, steep iron held rigidly in the
## lead hand wanders flat and wide through the hitting zone. Each frame this:
##   1. reads where the mocap's lead hand would point the shaft (grip -> head),
##   2. projects that direction into the club's own swing plane (through the ball, along the
##      target line, tilted to the club's address shaft angle -- steep for wedges, flatter for
##      the driver),
##   3. adds one fixed in-plane angle -- the amount the mocap's club still lags the ball at
##      impact -- ramped in from the top and out after impact, so the head meets the ball at
##      impact. A fixed angle always turns the club the way the swing is already turning; aiming
##      at the ball afresh each frame would take the shortest way round, which from the top
##      swings the head down through the body,
##   4. turns the lead wrist by exactly the rotation that carries the shaft there.
## After impact the plane hold fades out over PLANE_RELEASE seconds, so the follow-through and
## finish are the mocap's own (forcing them into the address plane flips the club around).
## The club stays rigidly in the hand (one grip offset); timing, hinge and face rotation all
## still come from the mocap. Runs before the trail-arm IK so the right hand follows.

const PLANE_RELEASE := 0.3

var bone := -1
var anim: AnimationPlayer
var shaft_in_hand := Vector3.DOWN  # grip -> head direction, lead-hand bone space
var plane_normal := Vector3.ZERO   # club swing plane normal, skeleton space (ZERO = off)
var grip_in_hand := Transform3D.IDENTITY  # club grip frame in lead-hand bone space
var impact_angle := 0.0            # in-plane angle added at full weight (radians, about plane_normal)
## The lead-arm IK target (GolferHandGuide's marker). It carries the hand's mocap orientation
## from before the IK bent the arm; the wrist starts from that so moving the hands never
## twists the club. Null: use the hand's current orientation.
var reference: Node3D
var t_start := 0.0   # top of the backswing: impact correction starts ramping in
var t_full := 1.2    # impact: full correction
var t_end := 1.4     # gone again by here


func weight_at(t: float) -> float:
	if t <= t_start or t >= t_end:
		return 0.0
	if t <= t_full:
		return smoothstep(t_start, t_full, t)
	return 1.0 - smoothstep(t_full, t_end, t)


func _in_plane(v: Vector3) -> Vector3:
	return v - plane_normal * v.dot(plane_normal)


## Desired shaft direction (grip -> head) for a raw (mocap) shaft direction at clip time `t`.
func plane_shaft(raw: Vector3, t: float) -> Vector3:
	var q := _in_plane(raw)
	# Nearly edge-on to the plane (only ever for an instant at the top): leave it alone.
	if q.length() < 0.25:
		return raw
	q = q.normalized()
	var w := weight_at(t)
	if w > 0.0 and impact_angle != 0.0:
		q = (Basis(plane_normal, impact_angle * w) * q).normalized()
	return q


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bone < 0 or anim == null or anim.current_animation == "" or plane_normal == Vector3.ZERO:
		return
	var lead := skeleton.get_bone_global_pose(bone)
	if reference != null:
		lead.basis = reference.transform.basis
	var raw := (lead.basis.orthonormalized() * shaft_in_hand).normalized()
	var t := anim.current_animation_position
	var want := plane_shaft(raw, t)
	var hold := 1.0 - smoothstep(t_full, t_full + PLANE_RELEASE, t)
	if hold < 1.0:
		want = raw.slerp(want, hold).normalized()
	var turn := Basis(Quaternion(raw, want)) if not raw.is_equal_approx(want) else Basis.IDENTITY
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * (turn * lead.basis.orthonormalized())
	skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
