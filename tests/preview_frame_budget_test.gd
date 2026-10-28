extends SceneTree

class PreviewCourse:
	extends "res://scripts/course.gd"
	var completed: Array = []
	func _ready() -> void:
		set_process(false)
	func _current_club() -> Clubs.Club:
		return Clubs.stock_bag()[club_index]
	func _draw_shot_tracker(result: Dictionary) -> void:
		completed.append(result)

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false)
	call_deferred("run")

func run() -> void:
	var course := PreviewCourse.new()
	root.add_child(course)
	course._transitioning = false
	course.layout = CourseLayout.new()
	course.layout.bounds = Rect2(-500, -500, 1000, 1000)
	course.layout.terrain_amplitude = 0.0
	course.layout.terrain_detail = 0.0
	course.ball = GolfBall.new()
	course.shadow_ball = GolfBall.new()
	course.camera = OrbitCamera.new()
	course.shot_tracker_line = MeshInstance3D.new()
	course.landing_marker = MeshInstance3D.new()
	course.trail_mesh = MeshInstance3D.new()
	for node in [course.ball, course.shadow_ball, course.camera, course.shot_tracker_line, course.landing_marker, course.trail_mesh]:
		course.add_child(node)
		node.set_process(false)
		node.set_physics_process(false)
	for ball: GolfBall in [course.ball, course.shadow_ball]:
		ball.layout = course.layout
		ball.skip_obstacles = true
		ball.log_level = PhysicsLogger.Level.ERROR
		ball.cup_position = Vector3(0, 0, -300)
	course.ball.place(Vector2.ZERO)
	# Reference: exactly the old single-frame simulation, same launch and steps.
	course._begin_trajectory(course._current_club(), Vector2.ZERO, Vector3.FORWARD)
	var started := Time.get_ticks_usec()
	var steps := 0
	while not course._trajectory_done() and steps < int(course.TRACKER_MAX_TIME / GolfBall.DT) + 4:
		course.shadow_ball._physics_process(GolfBall.DT)
		steps += 1
	var reference_usec := Time.get_ticks_usec() - started
	var expected := course._trajectory_result()
	var frames := 0
	var max_usec := 0
	while course.completed.is_empty() and frames < 400:
		var previous_steps: int = course._tracker_steps if course._tracker_running else 0
		started = Time.get_ticks_usec()
		course._update_shot_tracker(1.0 if frames == 0 else 1.0 / 60.0)
		max_usec = maxi(max_usec, Time.get_ticks_usec() - started)
		assert(course._tracker_steps - previous_steps <= course.TRACKER_STEPS_PER_FRAME, "Unbounded prediction batch")
		frames += 1
	assert(frames > 1 and frames < 400, "Prediction must yield and then finish")
	assert(course.completed.size() == 1)
	var actual: Dictionary = course.completed[0]
	assert(actual.trail == expected.trail, "Budgeting changed the trajectory")
	assert(actual.landing == expected.landing, "Budgeting changed the landing")
	assert(actual.carry_yd == expected.carry_yd and actual.total_yd == expected.total_yd)
	for frame in range(60):
		course._update_shot_tracker(1.0 / 60.0)
	assert(course.completed.size() == 1, "Idle prediction repeated")
	course.camera.aim_yaw += 0.2
	course._update_shot_tracker(1.0)
	assert(course._tracker_running, "Aim change did not start a new prediction")
	course._tracker_inputs.clear() # terrain rebuild cancels the old job
	course._update_shot_tracker(0.0)
	assert(not course._tracker_running, "Invalidated prediction still running")
	assert(course.completed.size() == 1, "Invalidated preview was displayed")
	course._update_shot_tracker(1.0)
	course.phase = course.SwingPhase.IN_FLIGHT
	course._update_shot_tracker(1.0 / 60.0)
	assert(not course._tracker_running, "Real shot did not cancel its preview")
	course.free()
	print("PREVIEW FRAME BUDGET: PASS; identical %d-step trajectory, %d batches; old %.2f ms, largest new batch %.2f ms" % [steps, frames, reference_usec / 1000.0, max_usec / 1000.0])
	quit()
