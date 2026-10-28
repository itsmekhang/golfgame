extends SceneTree
## Exercise the real clubhouse callbacks without rebuilding terrain for each selection.
class CourseHarness extends "res://scripts/course.gd":
	var transitions: Array[int] = []
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)
		_transitioning = false
	func transition_to_hole(index: int) -> void:
		transitions.append(index)
		hole_index = index
	func _refresh_hud() -> void:
		pass

var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://round_span_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var course := CourseHarness.new()
	course.layout = CourseLayout.new()
	for i in range(18):
		var hole := CourseLayout.Hole.new()
		hole.index = i
		hole.par = 4 if i < 9 else 3 + i % 3
		course.layout.holes.append(hole)
	root.add_child(course)
	course._begin_round()
	var original := course.tracker
	await course._on_hub_tee_off_span("back9")
	check(course.hole_index == 9, "Back 9 starts at hole 10 with an existing untouched round")
	check(course.tracker != original and course.tracker.holes() == 9, "Back 9 gets a fresh nine-hole scorecard")
	check(course.tracker.pars == [3, 4, 5, 3, 4, 5, 3, 4, 5], "Scorecard uses selected pars")
	var back_tracker := course.tracker
	course._on_hub_closed()
	check(course.tracker == back_tracker and course.hole_index == 9, "Closing clubhouse preserves round")
	await course._on_hub_tee_off_span("front9")
	check(course.hole_index == 0 and course.tracker.holes() == 9, "Front 9 starts on hole 1")
	await course._on_hub_tee_off_span("full18")
	check(course.hole_index == 0 and course.tracker.holes() == 18, "Full 18 creates full scorecard")
	var before_loading := course.tracker
	course._transitioning = true
	await course._on_hub_tee_off_span("back9")
	check(course.round_span == "full18" and course.tracker == before_loading, "Loading cannot partially switch round span")
	course._transitioning = false
	course._round_complete_pending = true
	await course._on_hub_tee_off_span("back9")
	check(course.hole_index == 9 and course.tracker.holes() == 9 and not course._round_complete_pending, "Back 9 works after a completed round")
	check(course.scores.is_empty() and course.strokes == 0, "New scorecard starts empty")
	course.free()
	print("ROUND SPAN TEST: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
