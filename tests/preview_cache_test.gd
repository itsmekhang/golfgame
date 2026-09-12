extends SceneTree

class PreviewProbe:
	extends "res://scripts/course.gd"
	var predictions := 0
	func _ready() -> void:
		set_process(false)
	func _predict_trajectory(_club: Clubs.Club, _hit: Vector2, _aim: Vector3) -> Dictionary:
		predictions += 1
		return {}
	func _draw_shot_tracker(_result: Dictionary) -> void:
		pass

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var course := PreviewProbe.new()
	root.add_child(course)
	course.layout = CourseLayout.new()
	course.ball = GolfBall.new()
	course.shadow_ball = GolfBall.new()
	course.camera = OrbitCamera.new()
	course.shot_tracker_line = MeshInstance3D.new()
	course.landing_marker = MeshInstance3D.new()
	course.trail_mesh = MeshInstance3D.new()
	for node in [course.ball, course.shadow_ball, course.camera, course.shot_tracker_line, course.landing_marker, course.trail_mesh]:
		course.add_child(node)
		node.set_process(false)
	course._update_shot_tracker(1.0)
	assert(course.predictions == 1)
	for i in range(20):
		course._update_shot_tracker(1.0)
	assert(course.predictions == 1, "Idle preview repeated its physics simulation")
	course.strike = Vector2(0.3, 0.1)
	course._update_shot_tracker(1.0)
	course.club_index += 1
	course._update_shot_tracker(1.0)
	course.ball.wind = Vector3(1, 0, 0)
	course._update_shot_tracker(1.0)
	course.ball.position.x += 1.0
	course._update_shot_tracker(1.0)
	course.camera.aim_yaw += 0.1
	course._update_shot_tracker(1.0)
	course.ball.cup_position.x += 2.0
	course._update_shot_tracker(1.0)
	assert(course.predictions == 7, "Changed shot inputs did not refresh preview")
	course._tracker_inputs.clear()
	course._update_shot_tracker(1.0)
	assert(course.predictions == 8)
	course.free()
	print("PREVIEW CACHE: PASS")
	quit()
