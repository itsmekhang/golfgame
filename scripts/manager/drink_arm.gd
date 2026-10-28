class_name DrinkArm
extends SkeletonModifier3D
## A seated guest holds an upright glass at the bar and brings its rim to their
## mouth. Solve the arm to the wrist target, then close the fingers around it.

var upper := -1
var fore := -1
var hand := -1
var head := -1
var every := 10.0
var phase := 0.0
var _t := 0.0
var cup: Node3D
var _palm := Vector3.ZERO
var _hand_basis := Basis.IDENTITY
var _fingers := PackedInt32Array()


static func on(skel: Skeleton3D, glass: Node3D) -> DrinkArm:
	var m := DrinkArm.new()
	m.name = "DrinkArm"
	m.upper = skel.find_bone("upper_arm.R")
	m.fore = skel.find_bone("forearm.R")
	m.hand = skel.find_bone("hand.R")
	m.head = skel.find_bone("head")
	m.cup = glass
	m.phase = randf() * m.every
	if m.hand >= 0:
		var rest := skel.get_bone_global_rest(m.hand)
		var grip := skel.find_bone("grip.R")
		m._palm = rest.affine_inverse() * skel.get_bone_global_rest(grip).origin if grip >= 0 else Vector3(0, 0.06, 0)
		# Right palm faces inward; fingers run forward around the near side.
		var desired := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		m._hand_basis = desired
	for b in skel.get_bone_count():
		var n := skel.get_bone_name(b)
		if n.begins_with("finger_") and n.ends_with(".R"):
			m._fingers.append(b)
	skel.add_child(m)
	return m


func _process(delta: float) -> void:
	_t += delta


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or upper < 0 or fore < 0 or hand < 0 or head < 0 or not is_instance_valid(cup):
		return
	var k := fmod(_t + phase, every)
	var lift := smoothstep(0.0, 1.2, k) - smoothstep(2.0, 3.2, k)
	var face := skel.get_bone_global_pose(head)
	var cup_basis := Basis(Vector3.RIGHT, deg_to_rad(12.0) * lift)
	var mouth := face.origin + face.basis * Vector3(0, 0.07, -0.10)
	var down := face.origin + Vector3(-0.23, -0.19, -0.32)
	var sip := mouth - cup_basis * Vector3(0, 0.065, 0) + Vector3(0, 0, -0.035)
	var centre := down.lerp(sip, lift)
	var hand_basis := cup_basis * _hand_basis
	var wrist := centre - cup_basis * Vector3(0.038, 0, 0) - hand_basis * _palm
	_solve(skel, wrist)
	var pose := skel.get_bone_global_pose(hand)
	pose.basis = hand_basis
	skel.set_bone_global_pose(hand, pose)
	# Keep the glass anchored to the solved palm, including at reach limits.
	centre = pose.origin + hand_basis * _palm + cup_basis * Vector3(0.038, 0, 0)
	cup.transform = Transform3D(cup_basis, centre)
	for b in _fingers:
		var n := skel.get_bone_name(b)
		var rest := skel.get_bone_rest(b).basis.get_rotation_quaternion()
		skel.set_bone_pose_rotation(b, rest)
		var finger := skel.get_bone_global_pose(b)
		var palm_normal := cup_basis * Vector3.RIGHT
		var axis := finger.basis.y.cross(palm_normal).normalized()
		var curl := 24.0 if n.contains("1.") else (48.0 if n.contains("2.") else 32.0)
		if n.contains("thumb"):
			curl = 12.0
		finger.basis = Basis(axis, deg_to_rad(curl)) * finger.basis
		skel.set_bone_global_pose(b, finger)


func _solve(skel: Skeleton3D, target: Vector3) -> void:
	var a := skel.get_bone_global_pose(upper).origin
	var b := skel.get_bone_global_pose(fore).origin
	var c := skel.get_bone_global_pose(hand).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var reach := target - a
	var d := clampf(reach.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := reach.normalized()
	var pole := Vector3(-0.4, -0.8, 0.1)
	pole = (pole - dir * pole.dot(dir)).normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var elbow := a + dir * along + pole * sqrt(maxf(0.0, l1 * l1 - along * along))
	_aim(skel, upper, b - a, elbow - a)
	b = skel.get_bone_global_pose(fore).origin
	c = skel.get_bone_global_pose(hand).origin
	_aim(skel, fore, c - b, target - b)


func _aim(skel: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	var pose := skel.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)
