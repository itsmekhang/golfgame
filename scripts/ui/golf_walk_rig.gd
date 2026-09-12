class_name GolfWalkRig
extends RefCounted
## Side-view walk reconstructed from the supplied 30-frame / 0.9 s reference.
## Feet plant during stance; the swing foot lifts before the passing pose.
## Fixed segment lengths and two-bone knees prevent stretching/reversed joints.

const CYCLE_SECONDS := 0.9
const STRIDE := 94.0
const STANCE := 0.56
const UPPER_LEG := 33.0
const LOWER_LEG := 34.0
const GROUND_Y := 501.0
const SHOE_POINTS := [Vector2(-6, -3), Vector2(5, -3), Vector2(8, 0), Vector2(15, 0), Vector2(17, 3), Vector2(15, 6), Vector2(-6, 6)]

static func knee(hip: Vector2, ankle: Vector2) -> Vector2:
	var delta := ankle - hip
	var distance := clampf(delta.length(), 0.001, UPPER_LEG + LOWER_LEG - 0.001)
	var angle := acos(clampf((UPPER_LEG * UPPER_LEG + distance * distance - LOWER_LEG * LOWER_LEG) / (2.0 * UPPER_LEG * distance), -1.0, 1.0))
	return hip + delta.normalized().rotated(-angle) * UPPER_LEG

static func foot(phase: float, hip_y: float) -> Dictionary:
	var x: float
	var lift := 0.0
	var roll := 0.0
	var half_contact := STRIDE * STANCE * 0.5
	if phase < STANCE:
		var contact := phase / STANCE
		# This moves backward at exactly the root's forward speed: no sliding.
		x = lerpf(half_contact, -half_contact, contact)
		roll = -0.16 * (1.0 - smoothstep(0.0, 0.2, contact)) + 0.40 * smoothstep(0.78, 1.0, contact)
	else:
		var swing := (phase - STANCE) / (1.0 - STANCE)
		x = lerpf(-half_contact, half_contact, smoothstep(0.0, 1.0, swing))
		lift = sin(PI * swing) * 9.0
		roll = lerpf(0.40, -0.16, swing) + sin(PI * swing) * 0.65
	var sole := -INF
	for point: Vector2 in SHOE_POINTS:
		sole = maxf(sole, point.rotated(roll).y)
	return {"ankle": Vector2(x, GROUND_Y - sole - lift - hip_y), "roll": roll, "planted": phase < STANCE}

static func arm(shoulder: Vector2, phase: float) -> Dictionary:
	# Near arm swings back when the near foot leads, as in the reference GIF.
	var upper_angle := -cos(TAU * phase) * 0.55
	var lower_angle := upper_angle + 0.18 + 0.12 * maxf(0.0, sin(TAU * phase))
	var elbow := shoulder + Vector2(sin(upper_angle), cos(upper_angle)) * 21.0
	var hand := elbow + Vector2(sin(lower_angle), cos(lower_angle)) * 23.0
	return {"elbow": elbow, "hand": hand}

static func sample(distance: float) -> Dictionary:
	var phase := fposmod(distance / STRIDE, 1.0)
	var near_foot := foot(phase, 0.0)
	var far_foot := foot(fposmod(phase + 0.5, 1.0), 0.0)
	# Let the pelvis rise over the straight support leg and lower into contact.
	# The former fixed-height pelvis made both knees crouch throughout the walk.
	var extension := UPPER_LEG + LOWER_LEG - 0.5
	var near_required: float = near_foot["ankle"].y - sqrt(extension * extension - pow(near_foot["ankle"].x - 3.0, 2))
	var far_required: float = far_foot["ankle"].y - sqrt(extension * extension - pow(far_foot["ankle"].x + 3.0, 2))
	var hip_y := maxf(near_required, far_required)
	near_foot["ankle"] -= Vector2(0, hip_y)
	far_foot["ankle"] -= Vector2(0, hip_y)
	var near_arm := arm(Vector2(11, -32), phase)
	var far_arm := arm(Vector2(-6, -32), fposmod(phase + 0.5, 1.0))
	return {"hip_y": hip_y, "near_ankle": near_foot["ankle"], "far_ankle": far_foot["ankle"],
		"near_roll": near_foot["roll"], "far_roll": far_foot["roll"],
		"near_planted": near_foot["planted"], "far_planted": far_foot["planted"],
		"near_elbow": near_arm["elbow"], "near_hand": near_arm["hand"],
		"far_elbow": far_arm["elbow"], "far_hand": far_arm["hand"]}
