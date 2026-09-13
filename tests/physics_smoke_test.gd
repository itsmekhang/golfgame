extends SceneTree
## Headless smoke test for the OpenFairway GDScript port.
## Run: godot --headless --path . --script tests/physics_smoke_test.gd

func _init() -> void:
	PhysicsLogger.set_level(PhysicsLogger.Level.INFO)
	var adapter := PhysicsAdapter.new()

	var shots := [
		{"name": "Driver",  "BallData": {"Speed": 160.0, "VLA": 11.5, "HLA": 0.0, "BackSpin": 2500.0, "SideSpin": 0.0}},
		{"name": "7 Iron",  "BallData": {"Speed": 120.0, "VLA": 16.5, "HLA": 0.0, "BackSpin": 7000.0, "SideSpin": 0.0}},
		{"name": "PW",      "BallData": {"Speed": 102.0, "VLA": 24.0, "HLA": 0.0, "BackSpin": 9300.0, "SideSpin": 0.0}},
		{"name": "Chip",    "BallData": {"Speed": 45.0,  "VLA": 20.0, "HLA": 0.0, "BackSpin": 3500.0, "SideSpin": 0.0}},
		{"name": "Slice",   "BallData": {"Speed": 150.0, "VLA": 12.0, "HLA": 0.0, "BackSpin": 3000.0, "SideSpin": 800.0}},
	]

	var failures := 0
	for shot in shots:
		var r := adapter.simulate_shot_from_json(shot)
		var g := adapter.simulate_shot_from_json(shot, PhysicsEnums.SurfaceType.GREEN, Vector3.UP)
		print("%-8s carry=%6.1f yd  total=%6.1f yd  apex=%5.1f ft  hang=%4.2f s  regime=%s (%s) | green total=%6.1f spinback=%s" % [
			shot["name"], r["carry_yd"], r["total_yd"], r["apex_ft"], r["hang_time_s"],
			r["launch_regime_key"], r["matched_regime_override_key"], g["total_yd"], str(g["first_impact_spinback"])])
		if not is_finite(r["carry_yd"]) or r["carry_yd"] <= 0.0:
			failures += 1

	# Sanity windows (rough real-world expectations)
	var driver := adapter.simulate_carry_only_from_json(shots[0])
	if driver["carry_yd"] < 240.0 or driver["carry_yd"] > 300.0:
		printerr("Driver carry out of window: %.1f yd" % driver["carry_yd"])
		failures += 1
	var pw := adapter.simulate_carry_only_from_json(shots[2])
	if pw["carry_yd"] < 110.0 or pw["carry_yd"] > 150.0:
		printerr("PW carry out of window: %.1f yd" % pw["carry_yd"])
		failures += 1

	# Regime lookup parity check
	var profile := BallPhysicsProfile.new()
	var res := profile.resolve_scale_override(160.0, 11.5, 2500.0)
	print("Regime for driver: %s -> matched '%s'" % [res["regime_key"], res["matched_key"]])
	if res["regime_key"] != "D-S4-V1-P1" or res["matched_key"] != "D-S4-V1-P1":
		printerr("Regime key mismatch")
		failures += 1

	# Surface dictionary check
	# Green rolling friction follows the configured Stimpmeter setting.
	var s := Surface.new().get_params(PhysicsEnums.SurfaceType.GREEN)
	var want_mu := SurfacePhysicsCatalog.STIMP_RELEASE_MPS ** 2 / (2.0 * 9.81 * SurfacePhysicsCatalog.green_speed_ft * 0.3048)
	if absf(s["u_kr"] - want_mu) > 1e-6:
		printerr("Green rolling friction mismatch")
		failures += 1

	if failures == 0:
		print("PHYSICS SMOKE TEST: PASS")
		quit(0)
	else:
		printerr("PHYSICS SMOKE TEST: FAIL (%d)" % failures)
		quit(1)
