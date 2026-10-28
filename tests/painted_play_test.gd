extends SceneTree
## A Course Studio course played through the real game scene (headless OK, ~1 min):
##   godot --headless --path . --script tests/painted_play_test.gd
## Saves the sample course, launches course.tscn on it the way the start menu does, and
## checks the round: PaintedLayout loaded, ball on the tee, the HUD shows the painted hole,
## a full drive lands and rests on a real lie inside the canvas, bunkers/water/woods exist.
## Uses a throwaway save (never the player's).

var failures := 0
var course: Node3D


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		failures += 1


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_painted_play_unused.json")
	call_deferred("run")


func wait_ready() -> void:
	for i in range(6000):
		await process_frame
		if course.ball != null and course.hud != null and course.active_region.size != Vector2.ZERO and course._loading_screen == null and not course._transitioning:
			break
	await process_frame


func run() -> void:
	var c := PaintedCourse.starter("_painted_play_test")
	var path := "user://courses/_painted_play_test.course.json"
	check(c.save(path) == OK, "sample course saved")
	GameLaunch.play_custom(path)
	var t0 := Time.get_ticks_msec()
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await wait_ready()
	print("[painted-play] ready in %d ms" % (Time.get_ticks_msec() - t0))
	check(course.layout is PaintedLayout, "course scene loaded the painted layout")
	check(course.layout.holes.size() == 1 and course.layout.holes[0].par == 4, "one par 4")
	var tee: Vector2 = c.holes[0]["tee"]
	var b: Vector3 = course.ball.global_position
	check(Vector2(b.x, b.z).distance_to(tee) < 8.0, "ball starts on the painted tee (%.1f m away)" % Vector2(b.x, b.z).distance_to(tee))
	check(course.layout.bunkers.size() == 2 and course.layout.water_hazards.size() == 1, "bunkers and pond dug")
	# the course's own name everywhere, and no hole names (only Augusta's holes have them)
	check(course._course_title() == c.course_name, "course title is the studio course's name")
	check(GolfLoadingScreen.course_title == c.course_name and not GolfLoadingScreen.augusta, "loading screen set to the studio course")
	check(course._hole_info(0)["name"] == "", "studio holes have no name")
	check(not course.hud.hole_label.visible, "HUD hides the hole name")
	check(course.hud._help_eyebrow.text.begins_with(c.course_name.to_upper()), "controls overlay names the course (%s)" % course.hud._help_eyebrow.text)
	var card: GolfLoadingScreen = course.LOADING_SCENE.instantiate()
	root.add_child(card)
	card.begin_hole(1, course._hole_info(0)["name"], 4, 380, true)
	check(card._eyebrow.text.begins_with(c.course_name.to_upper()) and not card._eyebrow.text.contains("AUGUSTA"), "loading card names the course (%s)" % card._eyebrow.text)
	check(not card._name_col.visible, "loading card shows no hole name")
	check(card._tiles.get_child_count() == 2, "loading card has no Masters scoring average")
	card.queue_free()
	check(course.nature_props_root != null and course.nature_props_root.tree_count > 50, "woods planted (%d trees)" % (course.nature_props_root.tree_count if course.nature_props_root != null else 0))
	course.skip_swing_animation = true
	course._fire_shot(100.0, Vector2.ZERO)
	for i in range(3000):
		await process_frame
		if course.phase == course.SwingPhase.IDLE:
			break
	var rest: Vector3 = course.ball.global_position
	var carried := Vector2(rest.x, rest.z).distance_to(tee)
	check(carried > 120.0, "the drive went %.0f m" % carried)
	check(c.in_canvas(Vector2(rest.x, rest.z)), "ball rests on the canvas")
	var lie: int = course.layout.lie_surface_at(Vector2(rest.x, rest.z))
	print("[painted-play] rest lie: ", CourseLayout.surface_label(lie))
	check(absf(rest.y - course.layout.height_at(rest.x, rest.z)) < 0.3, "ball rests on the ground")
	DirAccess.remove_absolute(path)
	GameLaunch.custom_course = ""
	print("DONE %d failures" % failures)
	quit(1 if failures > 0 else 0)
