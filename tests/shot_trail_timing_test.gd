extends SceneTree

class ShotProbe:
	extends "res://scripts/course.gd"
	func _ready() -> void:
		set_process(false)
	func _sync_round_in_progress() -> void:
		pass
	func _impact_shot(_club: Clubs.Club, sp: Dictionary, _lie: int, _hit: Vector2, _carry: float) -> void:
		if sp["putter"]:
			ball.putt(sp["speed_mps"], sp["dir"])
		else:
			ball.launch(sp["speed_mph"], sp["vla"], sp["backspin"], sp["sidespin"], sp["dir"])

class HeldSwing:
	extends ClubSwingRig
	var impact: Callable
	func _ready() -> void:
		set_process(false)
	func swing(on_impact: Callable, _is_putt: bool = false) -> void:
		impact = on_impact

class QuietHud:
	extends Hud
	func _ready() -> void:
		power_bar = ProgressBar.new()
		result_label = Label.new()
		minimap_shot_overlay = MinimapShotOverlay.new()
		add_child(power_bar)
		add_child(result_label)
		add_child(minimap_shot_overlay)

var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		printerr("FAIL: ", message)
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://shot_trail_test_unused.json")
	call_deferred("run")
func run() -> void:
	var course := ShotProbe.new()
	root.add_child(course)
	course.ball = GolfBall.new()
	course.camera = OrbitCamera.new()
	course.hud = QuietHud.new()
	course.swing_rig = HeldSwing.new()
	course.trail_mesh = MeshInstance3D.new()
	course.shot_tracker_line = MeshInstance3D.new()
	course.landing_marker = MeshInstance3D.new()
	for node in [course.ball, course.camera, course.hud, course.swing_rig, course.trail_mesh, course.shot_tracker_line, course.landing_marker]:
		course.add_child(node)
		node.set_process(false)
		node.set_physics_process(false)
	var putter := -1
	for i in range(Clubs.bag().size()):
		if Clubs.bag()[i].is_putter:
			putter = i
			break
	check(putter >= 0, "Putter exists in bag")
	for club_index in [putter, 0]:
		course.club_index = club_index
		course.ball.position = Vector3.ZERO
		course.ball.trail = PackedVector3Array([Vector3(-2,0,0),Vector3.ZERO])
		course._update_trail()
		check(course.trail_mesh.mesh != null, "Previous shot has a white trail")
		course._fire_shot(60, Vector2.ZERO)
		check(course.ball.trail.is_empty(), "Retire previous shot before backswing")
		check(course.trail_mesh.mesh == null, "Clear main-view trail immediately")
		check(course.hud.minimap_shot_overlay._tail.is_empty(), "Clear minimap tail immediately")
		for frame in range(8):
			course._update_trail()
			check(course.trail_mesh.mesh == null, "No white tracer before impact")
		course.swing_rig.impact.call()
		check(course.ball.trail.size() == 1, "Impact begins the new ball path")
		course.ball.position += Vector3(0,0,-1)
		course._update_trail()
		check(course.trail_mesh.mesh != null, "Live tracer resumes after impact")
		check(course.hud.minimap_shot_overlay._tail[-1] == course.ball.global_position, "New tail follows current ball")
	course.free()
	print("SHOT TRAIL TIMING: ", "FAIL" if failed else "PASS", "; putter and driver, before and after impact")
	quit(1 if failed else 0)
