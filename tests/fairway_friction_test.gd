extends SceneTree
func _init() -> void:
	var adapter := PhysicsAdapter.new()
	var settings := SurfacePhysicsCatalog.get_settings(PhysicsEnums.SurfaceType.FAIRWAY)
	var tuned := settings.rolling_friction
	var shot := {"BallData": {"Speed": 160.0, "VLA": 11.5, "HLA": 0.0, "BackSpin": 2500.0, "SideSpin": 0.0}}
	settings.rolling_friction = 0.036
	var before := adapter.simulate_shot_from_json(shot)
	settings.rolling_friction = tuned
	var after := adapter.simulate_shot_from_json(shot)
	var old_roll: float = before["total_yd"] - before["carry_yd"]
	var new_roll: float = after["total_yd"] - after["carry_yd"]
	print("Fairway driver rollout: %.2f -> %.2f yd; rolling friction %.3f" % [old_roll, new_roll, tuned])
	if not is_finite(new_roll) or new_roll >= old_roll or absf(after["carry_yd"] - before["carry_yd"]) > 0.01:
		printerr("FAIRWAY FRICTION: FAIL")
		quit(1)
		return
	print("FAIRWAY FRICTION: PASS")
	quit()
