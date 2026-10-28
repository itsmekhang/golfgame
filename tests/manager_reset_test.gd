extends SceneTree

var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	var gs := GameState.new()
	gs.autosave = false
	gs.save_path = "user://manager_reset_test_never_saved.json"
	gs.cash = 5432
	gs.clubs = {"sentinel": "equipment preserved"}
	gs.unlocked = ["pga"]
	gs.rounds_completed = 7
	gs.business = CourseBusiness.create()
	gs.business.course_path = "user://course_to_preserve.json"
	gs.business.built = {"driving_range": 4}
	gs.business.placements = {"driving_range": {"pos": Vector2.ONE, "rot": 0.0}}
	gs.business.rooms = {"pro_shop": 3}
	gs.business.staff = {"range_attendant": 2}
	gs.business.hours = 55
	gs.business.lifetime["revenue"] = 1000.0
	gs.offline_report = {"net": 12}
	gs.reset_manager_progress(true)
	check(gs.business.owned and gs.business.course_path == "user://course_to_preserve.json", "Reset must retain deed and selected map")
	check(gs.business.built.is_empty() and gs.business.placements.is_empty() and gs.business.rooms.is_empty() and gs.business.staff.is_empty(), "Business upgrades were not reset")
	check(gs.business.hours == 0 and gs.business.lifetime["revenue"] == 0 and gs.offline_report.is_empty(), "Business earnings history was not reset")
	check(gs.cash == 5432 and gs.clubs.has("sentinel") and gs.unlocked == ["pga"] and gs.rounds_completed == 7, "Reset damaged player progress")
	check(not gs.business.accepting_visitors, "Reset must leave the course closed")
	var restored := CourseBusiness.from_dict(gs.business.to_dict())
	check(restored.owned and restored.built.is_empty(), "Reset does not serialize correctly")
	gs.reset_manager_progress(false)
	check(not gs.business.owned and gs.business.course_path == "", "Delete must clear manager ownership")
	check(gs.cash == 5432 and gs.clubs.has("sentinel") and gs.rounds_completed == 7, "Delete damaged player progress")
	check(not CourseBusiness.from_dict(gs.business.to_dict()).owned, "Deleted manager progress returns after reload")
	gs.free()
	print("MANAGER RESET: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
