extends SceneTree
## Verify slow loads cannot be skipped, the overlay is bounded, and controls return.

var failures := 0
var finishes := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func run() -> void:
	var overlay: GolfLoadingScreen = load("res://scenes/ui/golf_loading_screen.tscn").instantiate()
	root.add_child(overlay)
	overlay.set_process(false)
	overlay.begin_hole(12, "Golden Bell", 3, 155)
	overlay.ride_finished.connect(func() -> void: finishes += 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	overlay._input(space)
	for frame in range(900):
		overlay._process(1.0 / 60.0)
	check(finishes == 0 and not overlay._departing, "Long load exited before it was ready")
	check(overlay.get_child_count() == 1, "Animation accumulated nodes during a long load")
	check(overlay.art.hole_number == 12 and overlay.art.hole_name == "Golden Bell", "Hole details did not reach the illustration")
	check(overlay.art.pose()["drive"] > 0, "Long load did not reach the cruising phase")
	# The real drawing commands should stay finite and bounded throughout walking, boarding, and departure.
	var max_commands := 0
	for frame in range(ceili(GolfLoadingScreen.DEMO_LENGTH * 60.0)):
		overlay.art.elapsed = frame / 60.0
		var commands := overlay.art.build_commands()
		max_commands = maxi(max_commands, commands.size())
		for command: Dictionary in commands:
			if command["kind"] == "polygon":
				check(not Geometry2D.triangulate_polygon(GolfCartArt._vectors(command["points"])).is_empty(), "Illustration polygon failed Godot triangulation")
			for point: Array in command.get("points", []):
				check(is_finite(point[0]) and is_finite(point[1]), "Non-finite animation vertex")
	check(max_commands < 300, "Animation drawing exceeded its fixed budget")
	overlay.mark_ready()
	for frame in range(120):
		overlay._process(1.0 / 60.0)
	check(finishes == 1 and overlay._completed, "Ready overlay did not finish exactly once")
	overlay.queue_free()
	await process_frame
	# Early ready loads can be skipped, but the event must be consumed.
	var quick: GolfLoadingScreen = load("res://scenes/ui/golf_loading_screen.tscn").instantiate()
	root.add_child(quick)
	quick.set_process(false)
	quick.begin_hole(1, "Tea Olive", 4, 445, true)
	quick.mark_ready()
	quick._input(space)
	check(root.is_input_handled(), "Continue key leaked through to gameplay")
	for frame in range(60):
		quick._process(1.0 / 60.0)
	check(quick._completed, "Ready skip did not finish promptly")
	quick.queue_free()
	await process_frame
	# Exercise real course wiring, including duplicate and invalid requests.
	var course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	var deadline := Time.get_ticks_msec() + 60000
	while (course.hud == null or course._transitioning) and Time.get_ticks_msec() < deadline:
		await process_frame
	if course.hud == null or course._transitioning:
		printerr("Course startup never finished")
		quit(1)
		return
	await process_frame
	var original_children: int = course.get_child_count()
	var previous_hole: int = course.hole_index
	await course.transition_to_hole(-1)
	check(course.hole_index == previous_hole and not course._transitioning, "Invalid transition changed course state")
	course.camera._dragging = true
	course.hud.strike_selector._dragging = true
	course.transition_to_hole(1)
	check(not course.camera._dragging and not course.hud.strike_selector._dragging, "Transition retained a stale mouse drag")
	check(course._transitioning and not course.hud.visible, "Transition failed to cover and lock gameplay")
	check(not course.ball.is_physics_processing(), "Ball physics remained live under the overlay")
	await course.transition_to_hole(5)
	while course._transitioning:
		await process_frame
	check(course.hole_index == 1, "Overlapping transition changed the destination")
	check(course.hud.visible and course.camera.is_processing() and course.ball.is_physics_processing(), "Gameplay did not resume after transition")
	check(course.camera.global_position.distance_to(course.ball.global_position) < 12, "Camera did not arrive at the new tee")
	for index in [17, 0, 11, 1]:
		await course.transition_to_hole(index)
		await process_frame
		check(course.hole_index == index and course._loading_screen == null, "Repeated transition left an overlay behind")
	await process_frame
	check(course.get_child_count() == original_children, "Repeated transitions leaked course children")
	course.queue_free()
	await process_frame
	await process_frame
	print("[loading animation] max vector commands=%d; long load, ready skip, repeated hole changes checked" % max_commands)
	print("LOADING ANIMATION TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
