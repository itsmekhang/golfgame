extends SceneTree

class FlatGreen extends CourseLayout:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

class CupProbe extends GolfBall:
	var captured := false
	func _build_visual() -> void:
		pass
	func _finish_holed() -> void:
		captured = true
		super._finish_holed()

var failed := false
var layout := FlatGreen.new()
const CUP := Vector3(8, 0, 8)

func _init() -> void:
	call_deferred('run')

func check(ok: bool, label: String) -> void:
	print('PASS ' if ok else 'FAIL ', label)
	if not ok:
		failed = true
		push_error(label)

func make_ball() -> CupProbe:
	var ball := CupProbe.new()
	ball.layout = layout
	ball.skip_obstacles = true
	ball.cup_position = CUP
	ball.log_level = PhysicsLogger.Level.ERROR
	ball.resolve_surface = func(_point: Vector3) -> Dictionary:
		return {'engine': PhysicsEnums.SurfaceType.GREEN, 'surface': PhysicsEnums.SurfaceType.GREEN, 'source': 'test'}
	root.add_child(ball)
	ball.set_physics_process(false)
	return ball

func roll_case(start_x: float, offset: float, speed: float, expected: bool, label: String, steps: int = 120) -> void:
	var ball := make_ball()
	ball.place(Vector2(CUP.x + start_x, CUP.z + offset))
	ball.putt(speed, Vector3.RIGHT)
	for step in range(steps):
		ball._physics_process(GolfBall.DT)
		if not ball.is_moving:
			break
	check(ball.captured == expected, label)
	ball.free()

func run() -> void:
	layout.bounds = Rect2(-100, -100, 200, 200)
	SurfacePhysicsCatalog.set_green_speed(9.5)
	roll_case(-0.12, 0, 0.7, true, 'Gentle centered putt drops')
	roll_case(-0.12, 0.094, 0.7, true, 'Slow right-lip brush tips in')
	roll_case(-0.12, -0.094, 0.7, true, 'Slow left-lip brush tips in')
	roll_case(-0.035, 0, 2.27, true, 'Slightly firmer centered putt is accepted')
	roll_case(-0.12, 0.094, 1.6, false, 'Firm glancing putt rolls past the lip')
	roll_case(-0.12, 0.106, 0.7, false, 'Ball clear of the lip stays outside')
	roll_case(-0.12, 0, 3.5, false, 'Overhit centered putt skips past')
	# Both endpoints miss the new 96 mm capture boundary; only the path grazes it.
	roll_case(-0.0041, 0.09595, 1.0, true, 'Lip contact between physics samples is caught', 1)
	var airborne := make_ball()
	airborne.place(Vector2(CUP.x - 0.0041, CUP.z))
	airborne.position.y = 1.0
	airborne.launch(2.2, 0.0, 0.0, 0.0, Vector3.RIGHT)
	airborne._physics_process(GolfBall.DT)
	check(not airborne.captured, 'Ball above the cup is not captured')
	airborne.free()
	var dropping := make_ball()
	var scored: Array[Vector3] = []
	dropping.holed.connect(func(point: Vector3) -> void: scored.append(point))
	dropping.place(Vector2(CUP.x - 0.05, CUP.z + 0.094))
	dropping.putt(0.7, Vector3.RIGHT)
	for step in range(120):
		dropping._physics_process(GolfBall.DT)
		if dropping.captured:
			break
	check(dropping.captured and scored.is_empty(), 'Lip catch begins the drop before scoring')
	await create_timer(0.45).timeout
	check(scored.size() == 1 and dropping.global_position.distance_to(CUP + Vector3.DOWN * 0.1) < 0.001, 'Drop finishes in the cup and scores once')
	dropping.free()
	print('CUP CAPTURE: ', 'FAIL' if failed else 'PASS')
	quit(1 if failed else 0)
