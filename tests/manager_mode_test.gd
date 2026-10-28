extends SceneTree
## Course Manager mode (separate from Course Studio): loads the club's course, places facilities
## with the site rules (no fairway, no overlaps), turns and cancels a move, clears planted trees
## under a footprint, shows the tabs, and the start menu reports the club.
## Run: godot --headless --path . --script tests/manager_mode_test.gd

const DIR := "user://_manager_mode_test/"
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://manager_mode_test_unused.json")
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)


func run() -> void:
	await process_frame
	var gs: GameState = GameState.current
	gs.autosave = false
	gs.new_game()
	# locked first: the mode opens on the requirements
	var mgr = load("res://scenes/course_manager.tscn").instantiate()
	root.add_child(mgr)
	await process_frame
	check(mgr.course == null and mgr._tabs_row.get_child_count() == 0, "Locked: no course, no tabs")
	mgr.queue_free()
	await process_frame

	gs.unlocked.append(str(gs.manager_status()["store_id"]))
	gs.cash = 100000
	gs.buy_course()
	DirAccess.make_dir_recursive_absolute(DIR)
	var c := PaintedCourse.starter("Manager Mode Test")
	var h0: Dictionary = c.holes[0]
	for k in range(2):
		c.holes.append({"tee": h0["tee"] + Vector2(40 * (k + 1), 0), "pin": h0["pin"] + Vector2(40 * (k + 1), 0), "par": 0, "bends": [], "curve": false})
	var path := DIR + "manager_mode_test.course.json"
	c.save(path)
	gs.set_business_course(path)

	mgr = load("res://scenes/course_manager.tscn").instantiate()
	root.add_child(mgr)
	for i in range(3):
		await process_frame
	check(mgr.course != null and mgr._view.visible, "Club's course loaded and drawn")
	check(mgr._tabs_row.get_child_count() == 5, "Club / Facilities / Rooms / Staff / Books tabs")
	var course: PaintedCourse = mgr.course
	var tee: Vector2 = course.holes[0]["tee"]

	# fairway refused
	var fairway := Vector2.INF
	for x in range(-280, 281, 6):
		for z in range(-280, 281, 6):
			if fairway == Vector2.INF and course.surface_at(Vector2(x, z)) == PaintedCourse.Surface.FAIRWAY:
				fairway = Vector2(x, z)
	mgr._begin_placing("clubhouse")
	check(mgr._placing == "clubhouse" and mgr._ghost != null, "Placing starts with a ghost")
	mgr._place_rot = FacilityBuilder.default_facing(course, "clubhouse", fairway)
	check(not mgr._try_place_at(fairway) and gs.business.placements.is_empty(), "Refused on the fairway")

	# open rough accepted
	var spot := _spot(course, {}, "clubhouse", tee)
	check(spot != Vector2.INF, "Found open rough")
	mgr._place_rot = FacilityBuilder.default_facing(course, "clubhouse", spot)
	check(mgr._try_place_at(spot), "Placed on open rough")
	check(gs.business.placements.has("clubhouse") and mgr._placing == "", "Club now has its clubhouse; placing ended")
	await process_frame
	check(mgr._facilities_root.get_child_count() == 1, "Clubhouse drawn")

	# overlap refused
	mgr._begin_placing("pro_shop")
	mgr._place_rot = 0.0
	check(not mgr._try_place_at(spot + Vector2(2, 0)), "Pro shop can't overlap the clubhouse")
	mgr._cancel_placing()
	check(not gs.business.placements.has("pro_shop") and mgr._ghost == null, "Cancel leaves nothing behind")

	# moving: R turns it, Esc keeps the old spot
	var before: Dictionary = gs.business.placements["clubhouse"].duplicate()
	mgr._begin_placing("clubhouse")
	mgr._rotate(15.0)
	check(absf(wrapf(mgr._place_rot - float(before["rot"]), -PI, PI) - deg_to_rad(15.0)) < 1e-4, "R turns the facility being moved")
	mgr._cancel_placing()
	check(is_equal_approx(float(gs.business.placements["clubhouse"]["rot"]), float(before["rot"])), "Cancelled move keeps the old facing")

	# trees under a facility don't grow through it (manager view only)
	course.trees.append(["white_oak_A", spot + Vector2(1, 1)])
	mgr._clear_trees_under_facilities()
	var under := false
	for t in course.trees:
		under = under or FacilityBuilder.contains("clubhouse", spot, float(before["rot"]), t[1])
	check(not under, "Planted tree under the clubhouse cleared")

	# the range hits away from the tee
	var rp := Vector2(-150, 150)
	var nearest := tee
	for h in course.holes:
		if rp.distance_to(h["tee"]) < rp.distance_to(nearest):
			nearest = h["tee"]
	check(absf(wrapf(FacilityBuilder.default_facing(course, "driving_range", rp) - FacilityBuilder.facing(rp, nearest) - PI, -PI, PI)) < 1e-4, "Range defaults to hitting away from the tee")

	# building it opens the club; the pages all build
	gs.build_facility("clubhouse")
	await process_frame
	check(mgr._status.text == "CLOSED", "Course waits for owner to open")
	mgr._status.pressed.emit()
	check(mgr._status.text == "OPEN", "Status button opens the club")
	for tab in ["facilities", "staff", "books", "club"]:
		mgr._tab = tab
		mgr._refresh()
		await process_frame
		check(mgr._side.get_child_count() > 0, "%s page builds" % tab)
	var menu = load("res://scenes/start_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu._manager_caption().contains("Manager Mode Test") and menu._manager_caption().contains("open"), "Start menu names the club and that it's open")
	menu.queue_free()
	mgr.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("MANAGER MODE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _spot(course: PaintedCourse, others: Dictionary, type: String, near: Vector2) -> Vector2:
	var best := Vector2.INF
	for x in range(-260, 261, 8):
		for z in range(-260, 261, 8):
			var p := Vector2(x, z)
			if best != Vector2.INF and p.distance_to(near) >= best.distance_to(near):
				continue
			if FacilityBuilder.site_problem(course, others, type, p, FacilityBuilder.default_facing(course, type, p)) == "":
				best = p
	return best
