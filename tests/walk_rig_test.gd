extends SceneTree
## Regression checks for the reported walking and cart-occlusion defects.
const Rig = preload("res://scripts/ui/golf_walk_rig.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func _init() -> void:
	var art := GolfCartArt.new()
	for frame in range(240):
		var distance := Rig.STRIDE * frame / 120.0
		var pose := Rig.sample(distance)
		check(pose["near_planted"] or pose["far_planted"], "Walking pose left both feet unplanted")
		for side in ["near", "far"]:
			var hip := Vector2(3, 0) if side == "near" else Vector2(-3, 0)
			var ankle: Vector2 = pose[side + "_ankle"]
			var knee: Vector2 = Rig.knee(hip, ankle)
			check(absf(knee.distance_to(hip) - Rig.UPPER_LEG) < 0.001, "Upper leg changed length")
			check(absf(knee.distance_to(ankle) - Rig.LOWER_LEG) < 0.001, "Lower leg stretched")
			var next := Rig.sample(distance + 0.01)
			if pose[side + "_planted"] and next[side + "_planted"]:
				var world_x: float = distance + ankle.x
				var next_x: float = distance + 0.01 + next[side + "_ankle"].x
				check(absf(world_x - next_x) < 0.002, "A planted foot slid while the root moved")
	art.free()
	print("WALK RIG TEST: %s (fixed leg lengths and planted feet)" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
