extends SceneTree
## Course Studio + start menu smoke test (headless OK):
##   godot --headless --path . --script tests/studio_smoke_test.gd
## Opens the start menu, then the studio on a fresh sample course, paints with every brush
## through the studio's own stroke code, undoes, places a new hole's tee and pin, saves, and
## checks the saved file plays (PaintedLayout builds with the new hole).

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var menu: Node = load("res://scenes/start_menu.tscn").instantiate()
	root.add_child(menu)
	await frames(10)
	check(menu.is_inside_tree(), "start menu runs")
	menu.queue_free()
	await frames(2)

	GameLaunch.custom_course = ""
	var studio: CourseStudio = load("res://scenes/course_studio.tscn").instantiate()
	root.add_child(studio)
	await frames(5)
	check(studio.course != null and studio.course.holes.size() == 1, "studio opens the sample course")
	var c := studio.course
	c.course_name = "_smoke_test_course"
	studio._name_edit.text = c.course_name
	var p := Vector3(120, 0, 60)
	p.y = c.height_at(Vector2(p.x, p.z))
	for id in ["fairway", "green", "bunker", "water", "woods", "raise", "smooth", "tree", "rough"]:
		studio._select_tool(studio._tool_index(id))
		studio._cursor = p
		studio._cursor_valid = true
		studio._begin_stroke()
		studio._stroke_to(Vector2(p.x + 12, p.z))
		studio._end_stroke()
		await frames(1)
	check(studio._undo.size() == 9, "nine strokes on the undo stack (%d)" % studio._undo.size())
	# the last stroke painted rough over the spot; undo brings the tree stroke's state back
	studio._undo_step()
	check(c.trees.size() > 0, "undo keeps the planted trees")
	# new hole: tee then pin (pin lays a green)
	studio._add_hole()
	var tee := Vector2(-150, 150)
	var pin := Vector2(-160, -40)
	studio._cursor = Vector3(tee.x, c.height_at(tee), tee.y)
	studio._begin_stroke()
	check(String(studio.TOOLS[studio.tool_index]["id"]) == "place_pin", "placing a tee switches to the pin tool")
	studio._cursor = Vector3(pin.x, c.height_at(pin), pin.y)
	studio._begin_stroke()
	await frames(3)
	check(c.holes.size() == 2, "two holes")
	check(c.coverage(PaintedCourse.Surface.GREEN, pin) > 0.5, "pin placed on a fresh green")
	check(c.coverage(PaintedCourse.Surface.TEE, tee) > 0.5, "tee placed on a fresh tee box")
	check(c.issues().is_empty(), "course has no issues: %s" % [c.issues()])
	# dogleg: a bend off to the side lengthens the hole; Curve smooths it; lay a fairway on it
	var straight_yd := c.hole_yards(1)
	studio._select_tool(studio._tool_index("bend"))
	var corner := Vector2(-90, 60)
	studio._cursor = Vector3(corner.x, c.height_at(corner), corner.y)
	studio._begin_stroke()
	await frames(1)
	var bends: Array = c.holes[1]["bends"]
	check(bends.size() == 1 and studio._drag_bend == 0, "bend tool adds a bend and grabs it")
	check(c.hole_yards(1) > straight_yd + 10, "the dogleg is longer than the straight hole (%d vs %d yd)" % [c.hole_yards(1), straight_yd])
	studio._set_curve(1, true)
	check(c.hole_route(1).size() > 10, "curve hole is a smooth route (%d points)" % c.hole_route(1).size())
	studio._lay_fairway(1)
	var mid := PaintedCourse.route_point(c.hole_route(1), PaintedCourse.route_length(c.hole_route(1)) * 0.55)
	check(c.surface_at(mid) == PaintedCourse.Surface.FAIRWAY, "laid fairway follows the curve")
	studio._undo_step()
	check(c.surface_at(mid) != PaintedCourse.Surface.FAIRWAY, "laying the fairway undoes in one step")
	studio._redo_step()
	check(c.issues().is_empty(), "dogleg course has no issues: %s" % [c.issues()])
	# move tool: drag hole 2's green 30 m east, its pin comes along; then its tee box
	studio._select_tool(studio._tool_index("move"))
	var old_pin: Vector2 = c.holes[1]["pin"]
	studio._cursor = Vector3(old_pin.x, c.height_at(old_pin), old_pin.y)
	studio._begin_stroke()
	check(not studio._move.is_empty() and int(studio._move["region"]["surface"]) == PaintedCourse.Surface.GREEN, "move tool picks up the green")
	for step in range(1, 7):
		studio._move_to(old_pin + Vector2(5.0 * step, 0.0))
	studio._end_move()
	var new_pin: Vector2 = c.holes[1]["pin"]
	check(new_pin.distance_to(old_pin + Vector2(30, 0)) < 1.5, "the pin moved with its green (%.1f m)" % new_pin.distance_to(old_pin))
	check(c.coverage(PaintedCourse.Surface.GREEN, new_pin) > 0.5, "green painted at the new spot")
	check(c.coverage(PaintedCourse.Surface.GREEN, old_pin) < 0.5, "old spot is no longer green")
	studio._undo_step()
	check((c.holes[1]["pin"] as Vector2).distance_to(old_pin) < 0.01 and c.coverage(PaintedCourse.Surface.GREEN, old_pin) > 0.5, "undo puts the green and pin back")
	studio._redo_step()
	var old_tee: Vector2 = c.holes[1]["tee"]
	studio._cursor = Vector3(old_tee.x, c.height_at(old_tee), old_tee.y)
	studio._begin_stroke()
	studio._move_to(old_tee + Vector2(0, 12))
	studio._end_move()
	check((c.holes[1]["tee"] as Vector2).distance_to(old_tee + Vector2(0, 12)) < 1.5 and c.coverage(PaintedCourse.Surface.TEE, c.holes[1]["tee"]) > 0.5, "tee box and tee moved together")
	check(c.issues().is_empty(), "course still fine after moves: %s" % [c.issues()])
	check(studio._save(), "saved")
	var path := studio.path
	var back := PaintedCourse.load_file(path)
	check(back != null and back.holes.size() == 2, "saved file reloads with both holes")
	check(back != null and (back.holes[1]["bends"] as Array).size() == 1 and back.hole_is_curve(1), "bends and curve survive save/load")
	var L := PaintedLayout.build(back)
	pin = back.holes[1]["pin"]
	tee = back.holes[1]["tee"]
	check(L.holes.size() == 2 and L.surface_at(pin) == PhysicsEnums.SurfaceType.GREEN, "second hole plays: green at its pin")
	check(L.holes[1].waypoints.size() > 3 and absf(L.holes[1].length_yd - back.hole_yards(1)) < 6.0, "game hole follows the curve (%.0f vs %d yd)" % [L.holes[1].length_yd, back.hole_yards(1)])
	var aim := L.aim_point(1, tee, 215.0)
	var direct := (pin - tee).normalized()
	check((aim - tee).normalized().dot(direct) < 0.97, "tee shot aims down the dogleg, not at the hidden pin")
	DirAccess.remove_absolute(path)
	studio.queue_free()
	await frames(2)
	print("DONE %d failures" % failures)
	quit(1 if failures > 0 else 0)
