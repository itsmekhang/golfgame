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

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

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
	var nodes_before := _count(overlay)
	for frame in range(900):
		overlay._process(1.0 / 60.0)
	check(finishes == 0 and not overlay._departing, "Long load exited before it was ready")
	check(_count(overlay) == nodes_before, "Loading screen accumulated nodes during a long load")
	check(overlay.hole_number == 12 and overlay._name.text == "Golden Bell" and overlay._number.text == "12", "Hole details did not reach the screen")
	check(overlay._status_label.visible and not overlay._go.visible, "Tee-off prompt shown before the load finished")
	# Every hole has its postcard stills, and the slideshow keeps cycling them.
	for n in range(1, 19):
		check(GolfLoadingScreen._load_stills(n).size() == 3, "Postcard stills missing for hole %d" % n)
	# (15 s cycles all three stills, so the index may be back at 0; the second layer only
	# ever gets a still by crossfading to the next one.)
	check(overlay._slides.size() == 3 and overlay._slide_b.texture != null, "Slideshow did not advance during a long load")
	overlay.mark_ready()
	overlay._process(1.0 / 60.0)
	check(overlay._go.visible, "Tee-off prompt missing once ready")
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
	print("[loading animation] long load, postcard slideshow, ready skip, repeated hole changes checked")
	print("LOADING ANIMATION TEST: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
