extends SceneTree
## The OVERHEAD (bird's-eye) camera must never see ground outside its pan_bounds,
## however far the pan offset is pushed and whatever height/tilt/heading it's at.
## Run: godot --headless --path . --script tests/overhead_bounds_test.gd

const EPS := 0.05  # floating-point slack, metres


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var cam := OrbitCamera.new()
	cam.target = target
	cam.height_at_ground = func(_x: float, _z: float) -> float: return 0.0
	root.add_child(cam)
	cam.mode = OrbitCamera.Mode.OVERHEAD
	var bounds := Rect2(-40.0, -60.0, 80.0, 120.0)
	cam.pan_bounds = bounds
	cam._process(0.016)  # warm-up: flips _was_overhead so overhead_yaw sticks below

	var failures := 0
	var checks := 0
	for h in [20.0, 45.0, 70.0, 110.0]:
		for t in [0.05, 0.2, 0.4, 0.6]:
			for yaw in [0.0, 0.7, 1.6, 2.4, 3.9, -1.3]:
				cam.overhead_height = h
				cam.overhead_tilt = t
				cam.overhead_yaw = yaw
				# try to push the pan centre far outside the bounds every which way
				cam.overhead_offset = Vector3(900.0 * cos(yaw * 1.7), 0.0, 900.0 * sin(yaw * 1.7))
				cam._process(0.016)
				var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
				var ext: Array = cam._overhead_ground_extent(fwd, cam.overhead_used_tilt, cam.overhead_used_height)
				var focus := Vector2(cam.overhead_focus_point.x, cam.overhead_focus_point.z)
				var vis_min: Vector2 = focus + ext[0]
				var vis_max: Vector2 = focus + ext[1]
				checks += 1
				var ok := vis_min.x >= bounds.position.x - EPS and vis_max.x <= bounds.end.x + EPS \
					and vis_min.y >= bounds.position.y - EPS and vis_max.y <= bounds.end.y + EPS
				if not ok:
					failures += 1
					printerr("FAIL h=%.0f tilt=%.2f yaw=%.2f  visible x[%.1f,%.1f] z[%.1f,%.1f]  bounds x[%.1f,%.1f] z[%.1f,%.1f]" % [
						h, t, yaw, vis_min.x, vis_max.x, vis_min.y, vis_max.y,
						bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y])

	if failures == 0:
		print("OVERHEAD BOUNDS TEST: PASS (%d configurations)" % checks)
		quit(0)
	else:
		printerr("OVERHEAD BOUNDS TEST: FAIL (%d/%d)" % [failures, checks])
		quit(1)
