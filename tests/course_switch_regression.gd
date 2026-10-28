extends SceneTree
const DIR := "user://_course_switch_regression/"
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var a := PaintedCourse.starter("Switch course A")
	var b := PaintedCourse.starter("Switch course B")
	var path_a := DIR + "a.course.json"
	var path_b := DIR + "b.course.json"
	a.save(path_a)
	b.save(path_b)
	var gs := GameState.new()
	gs.autosave = false
	gs.save_path = DIR + "state.json"
	gs.new_game()
	gs.cash = 45678
	gs.unlocked.append(str(gs.manager_status()["store_id"]))
	gs.business = CourseBusiness.create()
	gs.business.built = {"clubhouse": 4, "cart_barn": 4, "driving_range": 4, "parking_lot": 4, "short_game": 2}
	gs.business.rooms = {"pro_shop": 3, "restaurant": 3, "spa_fitness": 3}
	gs.business.staff = {"cart_attendant": 3, "shop_clerk": 1, "chef": 1, "trainer": 1}
	gs.business.hours = 20
	gs.business.lifetime["revenue"] = 500.0
	var upgrades := gs.business.built.duplicate(true)
	var rooms := gs.business.rooms.duplicate(true)
	var staff := gs.business.staff.duplicate(true)
	var unlocks := gs.unlocked.duplicate()
	var identity := gs.business.get_instance_id()
	check(gs.set_business_course(path_a)["ok"], "First course could not be selected")
	gs.place_facility("clubhouse", Vector2(10, 20), 0.4)
	gs.place_facility("cart_barn", Vector2(30, 40), 0.8)
	gs.business.auto_parked = true
	var layout_a := gs.business.placements.duplicate(true)
	check(gs.set_business_course(path_b)["ok"], "Second course could not be selected")
	check(gs.business.get_instance_id() == identity, "Switch replaced the upgraded business with a fresh level-one business")
	check(gs.business.built.is_empty() and gs.business.rooms.is_empty() and gs.business.staff.is_empty(), "An unmanaged course inherited another course's facilities or crew")
	check(gs.business.hours == 0 and gs.business.lifetime["revenue"] == 0 and not gs.business.accepting_visitors, "New course inherited another club's history or open state")
	check(gs.business.placements.is_empty() and not gs.business.auto_parked, "New course inherited invalid old positions or lost its deed-parking setup")
	check(gs.cash == 45678 and gs.unlocked == unlocks, "Switch charged for unlocks or reset player progress")
	gs.business.built = {"clubhouse": 1, "driving_range": 2}
	gs.business.rooms = {"pro_shop": 1}
	gs.business.staff = {"cart_attendant": 1, "range_attendant": 2}
	gs.business.green_fee = 7
	gs.business.hours = 3
	gs.business.condition = .8
	gs.business.lifetime["revenue"] = 75.0
	var upgrades_b := gs.business.built.duplicate(true)
	var rooms_b := gs.business.rooms.duplicate(true)
	var staff_b := gs.business.staff.duplicate(true)
	gs.place_facility("clubhouse", Vector2(-25, 15), 1.2)
	gs.place_facility("driving_range", Vector2(25, -30), 0.2)
	var layout_b := gs.business.placements.duplicate(true)
	check(gs.business.level("clubhouse") == 1, "Placing a facility changed this course's purchased level")
	check(gs.set_business_course(path_a)["ok"] and gs.business.placements == layout_a and gs.business.auto_parked, "Returning to course A lost its facility layout")
	check(gs.business.built == upgrades and gs.business.rooms == rooms and gs.business.staff == staff, "Returning to course A lost max upgrades, rooms or crew")
	check(gs.business.hours == 20 and gs.business.lifetime["revenue"] == 500.0, "Course A lost its own business history")
	check(gs.set_business_course(path_b)["ok"] and gs.business.placements == layout_b and not gs.business.auto_parked, "Returning to course B lost its distinct layout")
	check(gs.business.built == upgrades_b and gs.business.rooms == rooms_b and gs.business.staff == staff_b, "Returning to course B restored another course's upgrades or crew")
	check(gs.business.green_fee == 7 and gs.business.hours == 3 and is_equal_approx(gs.business.condition,.8), "Course B lost fees, clock or turf condition")
	check(gs.set_business_course(path_b)["ok"] and gs.business.placements == layout_b, "Reselecting the same course cleared buildings")
	var before := gs.business.to_dict()
	check(not gs.set_business_course(DIR + "missing.json")["ok"] and gs.business.to_dict() == before, "A failed course switch changed progress")
	gs.force_save()
	var loaded := GameState.new()
	loaded.autosave = false
	loaded.save_path = gs.save_path
	check(loaded.load_game(), "Saved progress failed to load")
	check(loaded.business.built == upgrades_b and loaded.business.rooms == rooms_b and loaded.business.staff == staff_b, "Current course upgrades or staff were lost after save/load")
	check(loaded.business.placements == layout_b, "Current course layout was lost after restart")
	check(loaded.set_business_course(path_a)["ok"] and loaded.business.placements == layout_a and loaded.business.auto_parked, "Other course's layout was lost after restart")
	check(loaded.business.built == upgrades and loaded.business.rooms == rooms and loaded.business.staff == staff, "Other course's max levels or crew were lost after restart")
	check(loaded.business.hours == 20 and loaded.business.lifetime["revenue"] == 500.0, "Switch reset business history")
	var encoded := loaded.business.to_dict()
	for site in encoded["course_sites"].values():
		check(not site.has("course_sites"), "Course snapshots recursively include other courses")
	check(loaded.cash == 45678 and loaded.unlocked == unlocks, "Save/reload lost cash or unlocks")
	# Existing saves have one layout and no new field. Keep that layout on the first switch.
	var legacy := loaded.business.to_dict()
	legacy.erase("course_sites")
	loaded.business = CourseBusiness.from_dict(legacy)
	check(loaded.set_business_course(path_b)["ok"] and loaded.set_business_course(path_a)["ok"], "Legacy save cannot switch courses")
	check(loaded.business.placements == layout_a and loaded.business.built == upgrades, "Legacy-save migration lost the original layout or levels")
	# Migrate the short-lived layout-only format without dropping paid upgrades.
	var layout_only := loaded.business.to_dict()
	layout_only["course_sites"] = {path_b: {"placements": {"clubhouse": [-25,15,1.2]}, "auto_parked": false}}
	loaded.business = CourseBusiness.from_dict(layout_only)
	check(loaded.set_business_course(path_b)["ok"] and loaded.business.built == upgrades and loaded.business.staff == staff, "Layout-only save migration lost shared purchases")
	check(loaded.business.placements["clubhouse"]["pos"] == Vector2(-25,15), "Layout-only save lost its saved positions")
	loaded.reset_manager_progress(true)
	check(loaded.business.course_sites.is_empty() and loaded.business.built.is_empty(), "Explicit business reset retained stale layouts or upgrades")
	check(loaded.cash == 45678 and loaded.unlocked == unlocks, "Business reset damaged shared player unlocks")
	gs.free()
	loaded.free()
	print("COURSE SWITCH: ", "FAIL" if failed else "PASS", "; independent A/B/A levels, layouts, rooms, staff, fees, history, save/load, legacy migration, unlocks and reset")
	quit(1 if failed else 0)
