extends SceneTree
## Regression checks for the user's reported rear-entry and shrinking-body defects.
const Walk = preload("res://scripts/ui/golf_walk_rig.gd")
const Board = preload("res://scripts/ui/golf_boarding_rig.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			printerr(message)

func _init() -> void:
	var art := GolfCartArt.new()
	var cart := Vector2(730, 493)
	var start := Board.sample(0.0, cart)
	check(start["hip"].x < cart.x - 180, "Golfer no longer starts left of the cart")
	var entrance := Board.sample(Board.WALK_END, cart)
	check(entrance["hip"].x > cart.x and entrance["hip"].x < cart.x + 45, "Boarding begins at the rear instead of beside the wheel")
	# Check actual joint geometry at 120 Hz, including every phase boundary.
	for frame in range(601):
		var time := frame / 120.0
		var joints := Board.sample(time, cart)
		for side in ["near", "far"]:
			check(absf(joints[side + "_hip"].distance_to(joints[side + "_knee"]) - Walk.UPPER_LEG) < 0.002, "Upper leg changed length at %.3f" % time)
			check(absf(joints[side + "_knee"].distance_to(joints[side + "_ankle"]) - Walk.LOWER_LEG) < 0.002, "Lower leg stretched at %.3f" % time)
			check(absf(joints[side + "_shoulder"].distance_to(joints[side + "_elbow"]) - Board.UPPER_ARM) < 0.002, "Upper arm changed length at %.3f" % time)
			check(absf(joints[side + "_elbow"].distance_to(joints[side + "_hand"]) - Board.LOWER_ARM) < 0.002, "Forearm changed length at %.3f" % time)
		var outline := GolfCartArt.torso_outline(joints)
		for i in range(outline.size()):
			for j in range(i + 1, outline.size()):
				check(absf(outline[i].distance_to(outline[j]) - GolfCartArt.TORSO_POINTS[i].distance_to(GolfCartArt.TORSO_POINTS[j])) < 0.002, "Torso shrank or folded at %.3f" % time)
		if time < Board.WALK_END:
			check(joints["phase"] == "walk", "Boarding started before reaching the entrance")
		if time >= Board.REACH_END:
			check(joints["near_hand"].distance_to(cart + Board.NEAR_GRIP) < 0.002, "Holding hand left the wheel at %.3f" % time)
		if time >= Board.FOOT_ON_STEP:
			check(joints["near_ankle"].distance_to(cart + Board.NEAR_FOOT) < 0.002, "Planted boarding foot slid at %.3f" % time)
		if time >= Board.STEP_UP_END:
			check(joints["far_ankle"].distance_to(cart + Board.FAR_FOOT) < 0.002, "Trailing foot left the floorboard at %.3f" % time)
	# There must be no position pops between phases.
	for boundary: float in [Board.WALK_END, Board.REACH_END, Board.FOOT_ON_STEP, Board.STEP_UP_END, Board.SIT_END, Board.SETTLED]:
		var before := Board.sample(boundary - 0.0001, cart)
		var after := Board.sample(boundary + 0.0001, cart)
		for key in ["hip", "near_ankle", "far_ankle", "near_hand", "far_hand"]:
			check(before[key].distance_to(after[key]) < 0.05, "%s popped at phase boundary %.2f" % [key, boundary])
	var standing := Board.sample(Board.STEP_UP_END, cart)
	var seated := Board.sample(Board.SETTLED, cart)
	check(seated["hip"].x < standing["hip"].x and seated["hip"].y > standing["hip"].y, "Sitting did not move hips back and down")
	check(seated["hip"].distance_to(cart + Board.SEAT_HIP) < 0.002, "Pelvis did not reach the seat")
	check(seated["far_hand"].distance_to(cart + Board.FAR_GRIP) < 0.002, "Seated left hand did not reach the wheel")
	# Check the layers in the actual drawing commands.
	for time: float in [1.6, 2.5, 3.6, 4.6]:
		art.elapsed = time
		var commands := art.build_commands()
		var torso_index := -1
		var bench_index := -1
		var body_index := -1
		for i in range(commands.size()):
			var command: Dictionary = commands[i]
			if command["kind"] != "polygon":
				continue
			if command["color"] == "#2e6950ff" and command["points"].size() == 6:
				torso_index = i
			elif command["color"] == "#f0dfbaff":
				bench_index = i
			elif command["color"] == "#438d82ff":
				body_index = i
		check(torso_index >= 0 and bench_index >= 0 and body_index >= 0, "Missing visual layer")
		check(torso_index < bench_index if time < Board.WALK_END else torso_index > bench_index, "Bench is on the wrong side of the golfer")
		check(body_index > torso_index, "Cart body is no longer in the foreground")
	art.free()
	print("BOARDING RIG TEST: %s (%d failures; driver entrance, rigid torso, fixed limbs, wheel grip, seated feet, depth order)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
