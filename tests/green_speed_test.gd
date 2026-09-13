extends SceneTree
## Stimpmeter check: a ball released at 1.83 m/s on a level green must roll about
## the configured green speed (feet), for a few settings.
## Run: godot --headless --path . --script tests/green_speed_test.gd

## A perfectly level green: the Stimpmeter is defined on level ground.
class FlatLayout extends CourseLayout:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP


func _init() -> void:
	PhysicsLogger.set_level(PhysicsLogger.Level.ERROR)
	var layout := FlatLayout.new()
	layout.bounds = Rect2(-200, -200, 400, 400)
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	ball.resolve_surface = func(_p: Vector3) -> Dictionary:
		return {"surface": PhysicsEnums.SurfaceType.GREEN, "engine": PhysicsEnums.SurfaceType.GREEN, "source": "test"}
	root.add_child(ball)
	await process_frame
	var failures := 0
	for stimp in [8.0, 9.0, 9.5, 10.0, 12.0]:
		SurfacePhysicsCatalog.set_green_speed(stimp)
		ball.place(Vector2.ZERO)
		ball.putt(SurfacePhysicsCatalog.STIMP_RELEASE_MPS, Vector3(1, 0, 0))
		for i in range(60 * 30):
			ball._physics_process(1.0 / 60.0)
			if not ball.is_moving:
				break
		var rolled_ft := ball.global_position.x / 0.3048
		var ok: bool = absf(rolled_ft - stimp) < stimp * 0.25
		print("%s stimp %4.1f ft -> rolled %5.1f ft" % ["PASS" if ok else "FAIL", stimp, rolled_ft])
		if not ok:
			failures += 1
	if failures == 0:
		print("GREEN SPEED TEST: PASS")
		quit(0)
	else:
		printerr("GREEN SPEED TEST: FAIL (%d)" % failures)
		quit(1)
