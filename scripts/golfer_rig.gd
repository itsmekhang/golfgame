class_name GolferRig
extends Node3D
## The golfer: Mixamo character "Ch01" (assets/golfer/golfer.fbx) playing the "Golf Drive" mocap
## from assets/golfer/golf_swing.fbx, holding and swinging the equipped club. ClubSwingRig
## drives it for every full swing (putts keep the club-only putting stroke).
##
## Rig, under the character's Skeleton3D:
##   LeadHand (BoneAttachment3D, left hand) > GripOffset (Node3D) > club, shifted by minus its
##     __grip_anchor so the grip sits on GripOffset's origin (same trick as ClubSwingRig).
##   GripOffset is solved per club at the address frame: grip in the left palm, shaft carrying
##     on from the left forearm, head resting on the ground, face square to the target. That
##     one offset then rides the hand through the whole swing.
##   TrailArmIK (TwoBoneIK3D: RightArm > RightForeArm > RightHand) pulls the right hand onto
##     TrailHandTarget, a marker on the grip just below the left hand (a child of the club), with
##     the pole on a marker behind the right elbow (on a chest attachment, so it turns with the
##     torso) to keep the elbow bending the right way.
## Address/top/impact/finish times and the facing/target directions are measured from the clip
## itself in _ready(), so another Mixamo swing on the same skeleton drops straight in.

const CHARACTER_PATH := "res://assets/golfer/golfer.fbx"
const SWING_PATH := "res://assets/golfer/golf_swing.fbx"
## Every club played off the turf (ClubSwingRig's turf families) swings with the iron clip when
## it is present. The drive clip stands taller through the ball: at impact its lead shoulder is
## ~4 cm further from the address hand spot than the arm can reach, so the hands stop short and
## the head comes through ~4 cm above its address spot, over the top of a ball on the turf. The
## driver still connects only because ClubSwingRig sets it up 2.5 cm deeper.
const IRON_SWING_PATH := "res://assets/golfer/golf_swing_iron.fbx"
const IRON_FAMILIES := ["iron", "wedge", "hybrid", "fairway"]
## Putts use their own clip when it is present (otherwise ClubSwingRig's club-only stroke).
const PUTT_PATH := "res://assets/golfer/golf_putt.fbx"
## Chips: the long chip inside CHIP_MAX_YD of the pin, the short chip around the hole.
const CHIP_PATH := "res://assets/golfer/golf_chip.fbx"
const CHIP_SHORT_PATH := "res://assets/golfer/golf_chip_short.fbx"
const CHIP_MAX_YD := 30.0
const SHORT_CHIP_MAX_YD := 12.0
## Steepest lie a club is allowed at address. A club too short to reach the ground from the
## mocap's hand height at this lie (the putter) gets the hands lowered by the hand guide.
const MAX_LIE_DEG := 72.0
## Hold the club at the very end: the butt sits just past the lead hand's pinky (the top of
## the left hand on the grip), measured from the clip's address pose, so no grip or shaft
## sticks out above the hands.
const PINKY_MARGIN := 0.01  # butt this far beyond the pinky knuckle line
## The grip sits on the palm side of each hand, this far from the middle of the hand's
## thickness (bone line) toward the palm: palm skin plus the grip's radius.
const GRIP_DEPTH := 0.028
const BUTT_PAST_PALM := 0.05  # fallback when the pinky can't be measured
const SHAFT_SHADOW_RADIUS := 0.012  # shadow-only rod along the shaft (see _ensure_club)
const BONE := "mixamorig12_"
const TRAIL_GRIP_GAP := 0.09   # right hand sits this far below the left on the grip (m)
const FINISH_HOLD := 0.42      # past the high finish, the club settles behind the neck: hold there
const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")
## Ball cap (assets/golfer/cap/cap.fbx, model units, brim toward +Z) on the Head bone: scaled
## to wrap the head and sat with its band at forehead level. The head bone's rest frame faces
## +Z like the cap, so no rotation is needed.
const CAP_PATH := "res://assets/golfer/cap/cap.fbx"
const CAP_SCALE := Vector3(0.045, 0.050, 0.053)  # narrower side to side, a touch deeper front to back
const CAP_OFFSET := Vector3(0.0, 0.130, 0.125)  # head-bone space, metres
const CAP_TILT_DEG := -10.0  # brim up / back down, so the band follows forehead -> back of skull
const CAP_COLOR := Color(0.11, 0.16, 0.32)
## The cap casts no real shadow; a soft decal under the brim fakes its shade on the face. The
## decal only touches meshes on GOLFER_LAYER (the body), never the club or the course.
const GOLFER_LAYER := 0x1000  # render layer 13
const BRIM_SHADE_STRENGTH := 0.45

var top_time := 0.9      # top of the backswing
var impact_time := 1.2   # hands back through their address spot (any club)
var finish_time := 1.6
var club_impact_time := 1.2  # this club's head closest to the ball: when the ball launches

var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _lead_hand: BoneAttachment3D
var _grip_offset: Node3D
var _ik: TwoBoneIK3D
var _wrist_fix: GolferWristFix
var _hand_guide: GolferHandGuide
var _trail_aim: GolferTrailAim
var _fingers: GolferGripFingers
var _lead_ik: TwoBoneIK3D
var _pole: Marker3D
var _club: Node3D
var _asset_id := ""
var _forward := Vector3(-1, 0, 0)    # golfer faces this way (golfer space)
var _target_dir := Vector3(0, 0, 1)  # direction of play (golfer space)
var _head_local := Vector3.ZERO      # club head contact point at address (golfer space)
var _tween: Tween
var _clip := "drive"            # active clip: "drive" or "iron"
var _clips: Dictionary = {}     # clip -> {impact, finish, forward, target} measured in _ready()


static func available() -> bool:
	return ResourceLoader.exists(CHARACTER_PATH) and ResourceLoader.exists(SWING_PATH)


func _ready() -> void:
	top_level = true  # placed directly in world space, not under the club rig's transform
	_model = (load(CHARACTER_PATH) as PackedScene).instantiate()
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_fix_materials()
	_add_swing_clip("drive", SWING_PATH)
	if ResourceLoader.exists(IRON_SWING_PATH):
		_add_swing_clip("iron", IRON_SWING_PATH)
	if ResourceLoader.exists(PUTT_PATH):
		_add_swing_clip("putt", PUTT_PATH)
	if ResourceLoader.exists(CHIP_PATH):
		_add_swing_clip("chip", CHIP_PATH)
	if ResourceLoader.exists(CHIP_SHORT_PATH):
		_add_swing_clip("chip_short", CHIP_SHORT_PATH)
	for clip in _clips.keys():
		_use_clip(clip)
		_analyse_swing()
		_clips[clip] = {"top": top_time, "impact": impact_time, "finish": finish_time, "forward": _forward, "target": _target_dir}
	_use_clip("drive")
	_build_rig()
	_pose_at(0.0)


func has_clip(clip: String) -> bool:
	return _clips.has(clip)


## Which clip a club plays from `distance_yd` out: putts, then the two chips near the green,
## then the iron swing for everything played off the turf, else (the driver) the drive.
func clip_for(asset_id: String, distance_yd: float) -> String:
	var family := str(Equipment.catalog().get(asset_id, {}).get("family", ""))
	if family == "putter":
		return "putt" if _clips.has("putt") else "drive"
	if distance_yd <= SHORT_CHIP_MAX_YD and _clips.has("chip_short"):
		return "chip_short"
	if distance_yd <= CHIP_MAX_YD and _clips.has("chip"):
		return "chip"
	if family in IRON_FAMILIES and _clips.has("iron"):
		return "iron"
	return "drive"


func _anim_name() -> StringName:
	return StringName("golfer/" + _clip)


## Switches the active clip and its measured timings/directions.
func _use_clip(clip: String) -> void:
	_clip = clip
	var data: Dictionary = _clips.get(clip, {})
	if not data.is_empty():
		top_time = data["top"]
		impact_time = data["impact"]
		finish_time = data["finish"]
		_forward = data["forward"]
		_target_dir = data["target"]


## Swing clips ship without a body; their tracks address the same Skeleton3D bones.
func _add_swing_clip(clip: String, path: String) -> void:
	var src := (load(path) as PackedScene).instantiate()
	var src_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var clip_anim: Animation = null
	for name in src_ap.get_animation_list():
		var cand := src_ap.get_animation(name)
		if clip_anim == null or cand.length > clip_anim.length:
			clip_anim = cand
	if not _anim.has_animation_library("golfer"):
		_anim.add_animation_library("golfer", AnimationLibrary.new())
	_anim.get_animation_library("golfer").add_animation(clip, clip_anim.duplicate())
	_clips[clip] = {}
	src.free()


func _bone_pos(bone: String) -> Vector3:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(BONE + bone)).origin


## [palm centre, palm normal] of a hand ("Left"/"Right") in skeleton space, current pose. The
## normal points out of the palm. Anatomical, so it doesn't depend on how curled the fingers
## are: (knuckles - wrist) x (index - pinky) for the left hand, mirrored for the right (in the
## Mixamo bind pose both give palms facing down).
func _palm(side: String) -> Array:
	var wrist := _bone_pos(side + "Hand")
	var middle := _bone_pos(side + "HandMiddle1")
	var across := _bone_pos(side + "HandIndex1") - _bone_pos(side + "HandPinky1")
	var n := (middle - wrist).cross(across) if side == "Left" else across.cross(middle - wrist)
	return [(wrist + middle) * 0.5, n.normalized()]


## Where the grip's centre line runs through a hand: on the palm side of its centre.
func _grip_point(side: String) -> Vector3:
	var p := _palm(side)
	return p[0] + p[1] * GRIP_DEPTH


func _hands() -> Vector3:
	return (_bone_pos("LeftHand") + _bone_pos("RightHand")) * 0.5


## Finds the top, impact and finish in the clip, and which way the golfer faces and swings.
func _analyse_swing() -> void:
	var length := _anim.get_animation(_anim_name()).length
	var step := 1.0 / 120.0
	var times: Array[float] = []
	var hands: Array[Vector3] = []
	var t := 0.0
	while t <= length:
		_pose_at(t)
		times.append(t)
		hands.append(_hands())
		t += step
	_pose_at(0.0)
	var address := hands[0]
	var hips := _bone_pos("Hips")
	# top of the backswing (or putting backstroke): the first peak of the hands' distance from
	# their address spot, once they have clearly moved away
	var top := 0
	for i in range(hands.size()):
		var d := hands[i].distance_to(address)
		if d > 0.08:
			if d >= hands[top].distance_to(address):
				top = i
			elif d < hands[top].distance_to(address) - 0.05:
				break
	# impact: hands back through their address spot on the way down
	var impact := top
	for i in range(top, hands.size()):
		if times[i] > times[top] + 0.8:
			break
		if hands[i].distance_to(address) < hands[impact].distance_to(address):
			impact = i
	# finish: the next high point after impact
	var peak := impact
	for i in range(impact, hands.size()):
		if hands[i].y >= hands[peak].y:
			peak = i
		elif hands[i].y < hands[peak].y - 0.1:
			break
	top_time = times[top]
	impact_time = times[impact]
	finish_time = minf(times[peak] + FINISH_HOLD, length)
	var f := hands[0] - hips
	_forward = Vector3(f.x, 0.0, f.z).normalized()
	var v := hands[mini(impact + 1, hands.size() - 1)] - hands[maxi(impact - 1, 0)]
	v.y = 0.0
	v -= _forward * v.dot(_forward)
	_target_dir = v.normalized() if v.length() > 0.0001 else Vector3(0, 0, 1)


func _build_rig() -> void:
	_add_cap()
	_lead_hand = BoneAttachment3D.new()
	_lead_hand.name = "LeadHand"
	_lead_hand.bone_name = BONE + "LeftHand"
	_skeleton.add_child(_lead_hand)
	_grip_offset = Node3D.new()
	_grip_offset.name = "GripOffset"
	_lead_hand.add_child(_grip_offset)
	# pole behind the right elbow, carried by the chest so it turns with the body
	_pose_at(0.0)
	var chest := BoneAttachment3D.new()
	chest.name = "Chest"
	chest.bone_name = BONE + "Spine2"
	_skeleton.add_child(chest)
	_pole = Marker3D.new()
	_pole.name = "TrailElbowPole"
	chest.add_child(_pole)
	var shoulder := _bone_pos("RightArm")
	var elbow := _bone_pos("RightForeArm")
	var wrist := _bone_pos("RightHand")
	var bend := (elbow - (shoulder + wrist) * 0.5).normalized()
	var chest0 := _skeleton.get_bone_global_pose(_skeleton.find_bone(BONE + "Spine2"))
	_pole.position = chest0.affine_inverse() * (elbow + bend * 0.5)
	# Modifier order: hand guide > lead-arm IK > wrist (swing plane) > trail-arm IK.
	var lead_target := Marker3D.new()
	lead_target.name = "LeadHandTarget"
	_skeleton.add_child(lead_target)
	var lead_pole := Marker3D.new()
	lead_pole.name = "LeadElbowPole"
	chest.add_child(lead_pole)
	var l_shoulder := _bone_pos("LeftArm")
	var l_elbow := _bone_pos("LeftForeArm")
	var l_wrist := _bone_pos("LeftHand")
	var l_bend := (l_elbow - (l_shoulder + l_wrist) * 0.5).normalized()
	lead_pole.position = chest0.affine_inverse() * (l_elbow + l_bend * 0.5)
	_hand_guide = GolferHandGuide.new()
	_hand_guide.name = "HandGuide"
	_hand_guide.bone = _skeleton.find_bone(BONE + "LeftHand")
	_hand_guide.anim = _anim
	_hand_guide.target = lead_target
	_skeleton.add_child(_hand_guide)
	_lead_ik = TwoBoneIK3D.new()
	_lead_ik.name = "LeadArmIK"
	_skeleton.add_child(_lead_ik)
	_lead_ik.set_setting_count(1)
	_lead_ik.set_root_bone_name(0, BONE + "LeftArm")
	_lead_ik.set_middle_bone_name(0, BONE + "LeftForeArm")
	_lead_ik.set_end_bone_name(0, BONE + "LeftHand")
	_lead_ik.set_target_node(0, _lead_ik.get_path_to(lead_target))
	_lead_ik.set_pole_node(0, _lead_ik.get_path_to(lead_pole))
	_wrist_fix = GolferWristFix.new()
	_wrist_fix.name = "WristFix"
	_wrist_fix.bone = _skeleton.find_bone(BONE + "LeftHand")
	_wrist_fix.reference = lead_target
	_wrist_fix.anim = _anim
	_skeleton.add_child(_wrist_fix)
	# right palm (not wrist) onto the grip: aim the trail IK through a palm offset
	_pose_at(0.0)
	var r_palm := _palm("Right")
	var r_hand := _skeleton.get_bone_global_pose(_skeleton.find_bone(BONE + "RightHand"))
	var trail_target := Marker3D.new()
	trail_target.name = "TrailIKTarget"
	_skeleton.add_child(trail_target)
	_trail_aim = GolferTrailAim.new()
	_trail_aim.name = "TrailAim"
	_trail_aim.bone = _skeleton.find_bone(BONE + "RightHand")
	_trail_aim.target = trail_target
	_trail_aim.palm_offset = r_hand.basis.orthonormalized().inverse() * (r_palm[0] + r_palm[1] * GRIP_DEPTH - r_hand.origin)
	_skeleton.add_child(_trail_aim)
	_ik = TwoBoneIK3D.new()
	_ik.name = "TrailArmIK"
	_skeleton.add_child(_ik)
	_ik.set_setting_count(1)
	_ik.set_root_bone_name(0, BONE + "RightArm")
	_ik.set_middle_bone_name(0, BONE + "RightForeArm")
	_ik.set_end_bone_name(0, BONE + "RightHand")
	_ik.set_pole_node(0, _ik.get_path_to(_pole))
	_ik.set_target_node(0, _ik.get_path_to(trail_target))
	# last: close both hands' fingers around the grip
	var l_palm := _palm("Left")
	var l_hand := _skeleton.get_bone_global_pose(_skeleton.find_bone(BONE + "LeftHand"))
	_fingers = GolferGripFingers.new()
	_fingers.name = "GripFingers"
	_fingers.prefix = BONE
	_fingers.palm_normal_left = l_hand.basis.orthonormalized().inverse() * l_palm[1]
	_fingers.palm_normal_right = r_hand.basis.orthonormalized().inverse() * r_palm[1]
	_skeleton.add_child(_fingers)


func _add_cap() -> void:
	if not ResourceLoader.exists(CAP_PATH):
		return
	var head := BoneAttachment3D.new()
	head.name = "HeadAttach"
	head.bone_name = BONE + "Head"
	_skeleton.add_child(head)
	var cap := (load(CAP_PATH) as PackedScene).instantiate() as Node3D
	cap.name = "Cap"
	cap.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(CAP_TILT_DEG)).scaled(CAP_SCALE), CAP_OFFSET)
	head.add_child(cap)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CAP_COLOR
	mat.roughness = 0.85
	for node in cap.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fake brim shade: projected straight down from the brim onto the forehead and eyes,
	# darkest under the brim and fading down the face.
	var shade := Decal.new()
	shade.name = "BrimShade"
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	shade.texture_albedo = tex
	shade.modulate = Color(0, 0, 0, BRIM_SHADE_STRENGTH)
	shade.size = Vector3(0.2, 0.2, 0.16)
	shade.position = Vector3(0.0, 0.10, 0.10)
	shade.lower_fade = 0.6
	shade.upper_fade = 0.05
	shade.normal_fade = 0.25
	shade.cull_mask = GOLFER_LAYER
	head.add_child(shade)


## The FBX's materials come in alpha-blended (the textures carry an alpha channel), which
## leaves the shirt and trousers see-through and badly sorted. Draw the body opaque; only the
## eyelash cards keep a cut-out.
## Golf outfit: the atlas repainted by tools/golfer_outfit.py (Blender) -- polo, trousers +
## belt, lead-hand glove, hair. The polo's hem below the waistband is cut out through alpha so
## it reads as tucked in (alpha scissor on the shirt only).
const OUTFIT_ALBEDO := "res://assets/golfer/outfit_albedo.png"
const OUTFIT_NORMAL := "res://assets/golfer/outfit_normal.png"
## Fabric sheen per garment: [roughness, specular] (cotton polo, wool-blend trousers, skin).
const OUTFIT_SURFACE := {"Shirt": [0.9, 0.3], "Pants": [0.85, 0.3], "Body": [0.6, 0.45], "Sneakers": [0.55, 0.4]}


func _fix_materials() -> void:
	var outfit: Texture2D = load(OUTFIT_ALBEDO) if ResourceLoader.exists(OUTFIT_ALBEDO) else null
	var outfit_n: Texture2D = load(OUTFIT_NORMAL) if outfit != null and ResourceLoader.exists(OUTFIT_NORMAL) else null
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.layers |= GOLFER_LAYER  # receives the brim-shade decal
		var part := String(mi.name).trim_prefix("Ch01_")
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as BaseMaterial3D
			if String(mi.name).contains("Eyelash"):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				if outfit != null:
					mat.albedo_texture = outfit
					if outfit_n != null and mat.normal_enabled:
						mat.normal_texture = outfit_n
					if part == "Shirt":
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						mat.alpha_scissor_threshold = 0.5
					if OUTFIT_SURFACE.has(part):
						mat.roughness_texture = null
						mat.roughness = OUTFIT_SURFACE[part][0]
						mat.metallic_specular = OUTFIT_SURFACE[part][1]
			mi.set_surface_override_material(s, mat)


## Holds the clip at `t`. Held by playing at speed 0 rather than pausing: a paused player
## stops updating the skeleton, and the skeleton modifiers (hand guide, wrist fix, IK) would
## stop running with it.
func _pose_at(t: float) -> void:
	if _anim.current_animation != _anim_name():
		_anim.play(_anim_name())
	_anim.speed_scale = 0.0
	_anim.seek(t, true)
	_skeleton.force_update_all_bone_transforms()


## Builds (or keeps) the club for `asset_id` and solves GripOffset for it at the address frame
## of `clip` (each club/clip pair has its own solve).
func _ensure_club(asset_id: String, condition: float, clip: String = "") -> bool:
	if clip == "":
		clip = clip_for(asset_id, INF)
	var key := asset_id + "|" + clip
	if key == _asset_id and _club != null:
		return true
	if _club != null:
		_club.free()
		_club = null
	_asset_id = ""
	var club := Equipment.create_club(asset_id, condition, AdminAccess.is_admin())
	if club == null:
		return false
	var grip := ClubSwingRig._find_suffix(club, "__grip_anchor")
	if grip == null:
		grip = ClubSwingRig._find_suffix(club, "__grip")
	if grip == null:
		club.free()
		return false
	var grip_local := ClubSwingRig._origin_relative_to(grip, club)
	_use_clip(clip)
	# Where the left pinky sits along the shaft at address (approximate shaft line: palm out to
	# the ball spot below it); the butt goes just past it.
	_pose_at(0.0)
	var palm0 := _grip_point("Left")
	var pinky := (_bone_pos("LeftHandPinky1") + _bone_pos("LeftHandPinky2")) * 0.5
	# The pinky sits off to the side of the shaft, so its place along the shaft depends on the
	# shaft's angle, which depends on how long the club is held -- settle it in a few passes.
	var anchor := grip_local
	var butt_past := BUTT_PAST_PALM
	for pass_i in range(4):
		var setup0 := _address_setup(palm0, grip_local.length())  # [palm, head, lowering]
		butt_past = (pinky - palm0).dot((setup0[0] - setup0[1]).normalized()) + PINKY_MARGIN
		if butt_past <= 0.0 or butt_past > 0.15:
			butt_past = BUTT_PAST_PALM
		grip_local = _hold_at_butt(club, anchor, butt_past)
	# create_club() switches club shadows off for the HUD/inspect views; in the golfer's hands
	# the club should swing in his shadow too. A ~1 cm shaft is thinner than a shadow-map texel
	# out on the course and its shadow breaks up, so an invisible, shadow-only rod along the
	# shaft gives it a solid line.
	for node in club.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var rod := MeshInstance3D.new()
	rod.name = "ShaftShadow"
	var cyl := CylinderMesh.new()
	cyl.top_radius = SHAFT_SHADOW_RADIUS
	cyl.bottom_radius = SHAFT_SHADOW_RADIUS
	cyl.height = grip_local.length() + butt_past
	cyl.radial_segments = 6
	cyl.rings = 1
	rod.mesh = cyl
	rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var axis := grip_local.normalized()
	rod.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), axis * cyl.height * 0.5)
	club.add_child(rod)
	club.position = -grip_local
	_grip_offset.add_child(club)
	_club = club
	_asset_id = key

	_pose_at(0.0)
	var length := grip_local.length()
	var setup := _address_setup(_grip_point("Left"), length)
	var palm: Vector3 = setup[0]
	_head_local = setup[1]
	_hand_guide.base_offset = setup[2]
	# Club model frame: head at the origin, grip at grip_local, face looking down -Z.
	var a1 := grip_local.normalized()
	var a2 := (Vector3.FORWARD - a1 * Vector3.FORWARD.dot(a1)).normalized()
	var b1 := (palm - _head_local).normalized()
	var b2 := (_target_dir - b1 * _target_dir.dot(b1)).normalized()
	var from := Basis(a1, a2, a1.cross(a2))
	var to := Basis(b1, b2, b1.cross(b2))
	var club_xf := Transform3D(to * from.transposed(), _head_local)
	var lead0 := _skeleton.get_bone_global_pose(_skeleton.find_bone(BONE + "LeftHand"))
	lead0.origin += _hand_guide.base_offset
	_grip_offset.transform = lead0.affine_inverse() * club_xf * Transform3D(Basis.IDENTITY, grip_local)
	_grip_offset.transform.basis = _grip_offset.transform.basis.orthonormalized()

	# Swing plane for this club: through the ball, along the target line, tilted to the
	# address shaft. GolferWristFix keeps the shaft in it every frame; here we also find the
	# impact frame and the small in-plane angle that puts the head on the ball there.
	_wrist_fix.active = false
	var lead_bone := _skeleton.find_bone(BONE + "LeftHand")
	var grip_xf := _grip_offset.transform  # club grip frame in lead-hand space
	var lead_address := _skeleton.get_bone_global_pose(lead_bone).origin
	_wrist_fix.shaft_in_hand = (grip_xf.basis * (-grip_local)).normalized()
	_wrist_fix.grip_in_hand = grip_xf
	_wrist_fix.impact_angle = 0.0
	var address_shaft := (_head_local - palm).normalized()
	_wrist_fix.plane_normal = _target_dir.cross(address_shaft).normalized()
	# The hand guide returns the hands to their address spot at the clip's impact frame, and
	# the wrist fix aims the shaft at the ball from there: that is when the ball launches.
	club_impact_time = impact_time
	_pose_at(club_impact_time)
	var lead_imp := _skeleton.get_bone_global_pose(lead_bone)
	_hand_guide.offset = lead_address - lead_imp.origin
	# How far the mocap's club (moved back to the address spot by the hand guide) still lags
	# the ball at impact, measured in the swing plane: the wrist fix adds this, ramped.
	lead_imp.origin = lead_address
	var raw_imp := (lead_imp.basis.orthonormalized() * _wrist_fix.shaft_in_hand).normalized()
	var have := _wrist_fix.plane_shaft(raw_imp, -1.0)
	var want := _head_local - (lead_imp * grip_xf).origin
	want -= _wrist_fix.plane_normal * want.dot(_wrist_fix.plane_normal)
	_wrist_fix.impact_angle = have.signed_angle_to(want.normalized(), _wrist_fix.plane_normal)
	for fix in [_hand_guide, _wrist_fix]:
		fix.t_start = top_time
		fix.t_full = club_impact_time
		fix.t_end = club_impact_time + 0.2
	_wrist_fix.active = true
	_pose_at(0.0)

	# right hand target: on the grip, just below the left hand
	var target := Marker3D.new()
	target.name = "TrailHandTarget"
	target.position = grip_local - grip_local.normalized() * TRAIL_GRIP_GAP
	club.add_child(target)
	_trail_aim.grip_point = target
	return true


## Address geometry for a club `length` (palm to head) held in the mocap palm `palm_mocap`:
## returns [palm, head, hand_lowering]. A club too short for the mocap's hand height at
## MAX_LIE_DEG (the putter) gets the hands lowered, all stroke long. Face-on, the shaft carries
## on the line of the lead arm (shoulder -> wrist): same lean along the target line per metre
## of drop. Down the line, it reaches out in front to the ball, as far as the club's length
## allows with the head resting on the ground (y = 0).
func _address_setup(palm_mocap: Vector3, length: float) -> Array:
	var lowering := Vector3(0.0, minf(length * sin(deg_to_rad(MAX_LIE_DEG)) - palm_mocap.y, 0.0), 0.0)
	var palm := palm_mocap + lowering
	var arm := _bone_pos("LeftHand") - _bone_pos("LeftArm")
	var lean := clampf(arm.dot(_target_dir) / maxf(-arm.y, 0.05), -0.6, 0.6)
	var drop := palm.y
	var along := clampf(lean * drop, -0.4, 0.4)
	var reach := sqrt(maxf(length * length - drop * drop - along * along, 0.0))
	var head := palm + _forward * reach + _target_dir * along
	head.y = 0.0
	return [palm, head, lowering]


## Slides the hold point up the shaft from the club's grip marker to just below its butt end.
func _hold_at_butt(club: Node3D, grip_local: Vector3, butt_past: float = BUTT_PAST_PALM) -> Vector3:
	var axis := grip_local.normalized()  # head -> grip, continuing to the butt
	var butt := grip_local.length()
	for node in club.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		if not (n.ends_with("__grip") or n.ends_with("__shaft")) or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != club and cur is Node3D:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		for v in mi.mesh.get_faces():
			butt = maxf(butt, (xf * v).dot(axis))
	# up the grip to the butt, or down it (choked down, e.g. the putter) by up to 8 cm
	var hold := maxf(butt - butt_past, grip_local.length() - 0.08)
	return axis * hold


## Address pose, standing so the club head rests at `contact` (world) with the target along
## `aim`. Called every frame while aiming; cheap when nothing changed.
func show_at_address(asset_id: String, condition: float, contact: Vector3, aim: Vector3, distance_yd: float = INF) -> bool:
	if not _ensure_club(asset_id, condition, clip_for(asset_id, distance_yd)):
		visible = false
		return false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_pose_at(0.0)
	var a := Vector3(aim.x, 0.0, aim.z)
	a = a.normalized() if a.length() > 0.001 else Vector3.FORWARD
	var world := Basis(Vector3.UP.cross(a), Vector3.UP, a)
	var local := Basis(Vector3.UP.cross(_target_dir), Vector3.UP, _target_dir)
	var b := world * local.transposed()
	global_transform = Transform3D(b, contact - b * _head_local)
	visible = true
	return true


## Full swing from address; `on_impact` fires as the club comes through the ball, then the
## golfer holds the finish while the ball flies.
func swing(on_impact: Callable) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_anim.play(_anim_name())
	_anim.seek(0.0, true)
	_anim.speed_scale = 1.0
	_tween = create_tween()
	_tween.tween_interval(club_impact_time)
	_tween.tween_callback(on_impact)
	_tween.tween_interval(maxf(finish_time - club_impact_time, 0.0))
	_tween.tween_callback(func() -> void: _anim.speed_scale = 0.0)
