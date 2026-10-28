extends "res://tests/screenshot_course.gd"
## Real clubhouse buttons, course transition, ball placement and nine-hole tracker.
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://back_nine_menu_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func press(hub: HubMenu, label: String) -> void:
	for child in hub._header.find_children("*", "Button", true, false):
		if child.text.to_lower() == label.to_lower():
			child.pressed.emit()
			return
	check(false, "Button present: " + label)

func run() -> void:
	var course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await _wait_ready(course)
	check(course.hole_index == 0 and course.tracker != null, "Fresh course has an untouched round at hole 1")
	var original: RoundTracker = course.tracker
	course.hub.open()
	press(course.hub, "Back 9")
	check(course.hub._round_span == "back9", "Back 9 button selects back nine")
	press(course.hub, "Tee off")
	await _wait_ready(course)
	check(not course._transitioning and course.hole_index == 9, "Tee off finishes loading hole 10")
	check(course.tracker != original and course.tracker.holes() == 9, "New nine-hole scorecard")
	var pars: Array[int] = []
	for i in range(9, 18):
		pars.append(course.layout.holes[i].par)
	check(course.tracker.pars == pars, "Scorecard covers holes 10 through 18")
	var tee: Vector3 = course.layout.holes[9].tee
	check(Vector2(course.ball.global_position.x, course.ball.global_position.z).distance_to(Vector2(tee.x, tee.z)) < 0.1, "Ball placed on hole 10 tee")
	check(not course.hub.is_open() and course.scores.is_empty() and course.strokes == 0, "Menu closes and play begins with an empty card")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/back-nine-tee.png")
	print("BACK NINE MENU TEST: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
