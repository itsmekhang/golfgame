class_name GolfBoardingRig
extends RefCounted
## Driver entrance choreography, using rigid body pieces and fixed-length limbs.
const Walk = preload("res://scripts/ui/golf_walk_rig.gd")
const WALK_END := 2.60
const REACH_END := 2.95
const FOOT_ON_STEP := 3.35
const STEP_UP_END := 3.75
const SIT_END := 4.30
const SETTLED := 4.60
const DRIVE_START := 4.90
const ENTRANCE_X := 12.0
const SEAT_HIP := Vector2(-8, -57)
const NEAR_FOOT := Vector2(35, -25)
const FAR_FOOT := Vector2(20, -25)
const NEAR_GRIP := Vector2(43, -70)
const FAR_GRIP := Vector2(29, -69)
const NEAR_SHOULDER := Vector2(11, -32)
const FAR_SHOULDER := Vector2(-6, -32)
const UPPER_ARM := 21.0
const LOWER_ARM := 23.0
const SEATED_LEAN := 0.14

static func blend(time: float, start: float, finish: float) -> float:
	return smoothstep(0.0, 1.0, clampf((time - start) / (finish - start), 0.0, 1.0))

static func arm_joint(shoulder: Vector2, target: Vector2) -> Dictionary:
	var delta := target - shoulder
	var distance := clampf(delta.length(), absf(LOWER_ARM - UPPER_ARM) + 0.001, UPPER_ARM + LOWER_ARM - 0.001)
	var hand := shoulder + delta.normalized() * distance
	var angle := acos(clampf((UPPER_ARM * UPPER_ARM + distance * distance - LOWER_ARM * LOWER_ARM) / (2.0 * UPPER_ARM * distance), -1.0, 1.0))
	return {"elbow": shoulder + delta.normalized().rotated(angle) * UPPER_ARM, "hand": hand}

static func sample(time: float, cart: Vector2) -> Dictionary:
	var walking_distance := minf(time, WALK_END) * Walk.STRIDE / Walk.CYCLE_SECONDS
	var total_distance := WALK_END * Walk.STRIDE / Walk.CYCLE_SECONDS
	var walk := Walk.sample(walking_distance)
	var hip := Vector2(cart.x + ENTRANCE_X - total_distance + walking_distance, walk["hip_y"])
	var near_ankle: Vector2 = hip + walk["near_ankle"]
	var far_ankle: Vector2 = hip + walk["far_ankle"]
	var near_roll: float = walk["near_roll"]
	var far_roll: float = walk["far_roll"]
	var lean := 0.0
	var near_hand: Vector2 = hip + walk["near_hand"]
	var far_hand: Vector2 = hip + walk["far_hand"]
	var phase := "walk"
	if time >= WALK_END:
		var reach := blend(time, WALK_END, REACH_END)
		var lift := blend(time, REACH_END, FOOT_ON_STEP)
		var up := blend(time, FOOT_ON_STEP, STEP_UP_END)
		var sit := blend(time, STEP_UP_END, SIT_END)
		var settle := blend(time, SIT_END, SETTLED)
		var standing_hip := hip
		var standing_near := near_ankle
		var standing_far := far_ankle
		var standing_hand := near_hand
		var ground_ankle := Walk.GROUND_Y - 6.0
		# Finish the last stride at the steering wheel. Do not hop from the rear.
		hip = standing_hip.lerp(cart + Vector2(18, -49), reach)
		near_ankle = standing_near.lerp(Vector2(cart.x + 36, ground_ankle), reach)
		far_ankle = standing_far.lerp(Vector2(standing_far.x, ground_ankle), reach)
		near_roll = lerpf(near_roll, 0.0, reach)
		far_roll = lerpf(far_roll, 0.0, reach)
		lean = lerpf(0.0, 0.16, reach)
		phase = "reach"
		if time >= REACH_END:
			# First foot rises over the sill while the other supports him on the ground.
			hip = (cart + Vector2(18, -49)).lerp(cart + Vector2(20, -49), lift)
			near_ankle = Vector2(cart.x + 36, ground_ankle).lerp(cart + NEAR_FOOT, lift)
			near_ankle.y -= sin(lift * PI) * 7.0
			lean = lerpf(0.16, 0.22, lift)
			phase = "lift_foot"
		if time >= FOOT_ON_STEP:
			# Transfer weight to the planted foot, then bring the trailing foot inside.
			hip = (cart + Vector2(20, -49)).lerp(cart + Vector2(12, -72), up)
			near_ankle = cart + NEAR_FOOT
			far_ankle = Vector2(standing_far.x, ground_ankle).lerp(cart + FAR_FOOT, up)
			far_ankle.y -= sin(up * PI) * 8.0
			far_roll = sin(up * PI) * 0.50
			lean = lerpf(0.22, 0.32, up)
			phase = "step_up"
		if time >= STEP_UP_END:
			# Both feet stay on the floorboard as the hips move BACK and DOWN to sit.
			hip = (cart + Vector2(12, -72)).lerp(cart + SEAT_HIP, sit)
			near_ankle = cart + NEAR_FOOT
			far_ankle = cart + FAR_FOOT
			far_roll = 0.0
			lean = lerpf(0.32, SEATED_LEAN, sit)
			phase = "sit"
		if time >= SIT_END:
			phase = "settle" if time < SETTLED else "seated"
			hip = cart + SEAT_HIP
			lean = SEATED_LEAN
		# Right hand holds the wheel throughout stepping and sitting.
		near_hand = standing_hand.lerp(cart + NEAR_GRIP, reach)
		# The other arm balances at his side, then joins the wheel after sitting.
		var balancing_hand := hip + Vector2(-14, 0).rotated(lean)
		far_hand = far_hand.lerp(balancing_hand, reach)
		far_hand = far_hand.lerp(cart + FAR_GRIP, settle)
	var near_hip := hip + Vector2(3, 0)
	var far_hip := hip - Vector2(3, 0)
	var near_shoulder := hip + NEAR_SHOULDER.rotated(lean)
	var far_shoulder := hip + FAR_SHOULDER.rotated(lean)
	var near_arm := arm_joint(near_shoulder, near_hand)
	var far_arm := arm_joint(far_shoulder, far_hand)
	return {"phase": phase, "hip": hip, "lean": lean,
		"near_hip": near_hip, "far_hip": far_hip,
		"near_knee": Walk.knee(near_hip, near_ankle), "far_knee": Walk.knee(far_hip, far_ankle),
		"near_ankle": near_ankle, "far_ankle": far_ankle,
		"near_roll": near_roll, "far_roll": far_roll,
		"near_shoulder": near_shoulder, "far_shoulder": far_shoulder,
		"near_elbow": near_arm["elbow"], "far_elbow": far_arm["elbow"],
		"near_hand": near_arm["hand"], "far_hand": far_arm["hand"]}
