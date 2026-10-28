extends SceneTree
## The range attendant's ball picker: the caged cart with its gang, parked by the range; the
## attendant (down from the lounge first, on a range with one) in at its driver's side, out round
## the field in its lanes picking up the balls lying there, back to park, out and on about their
## posts.
## Run: godot --headless --path . --script tests/range_picker_test.gd

var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_range_picker_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [1, 4]:
		scenario(level)
	print("RANGE PICKER: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func scenario(level: int) -> void:
	var c := PaintedCourse.create("Range picker", Vector2i(600, 600))
	c.holes.append({"tee": Vector2(-200, 200), "pin": Vector2(-200, 110), "par": 3, "bends": [], "curve": false})
	var b := CourseBusiness.create()
	b.accepting_visitors = false
	b.placements = {"driving_range": {"pos": Vector2(0, 220), "rot": 0.0}}
	b.built = {"driving_range": level}
	b.staff = {"range_attendant": 1}
	var items: Array = [{"type": "driving_range", "level": level, "pos": Vector2(0, 220), "rot": 0.0}]
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	check(life._pickers.size() == 1, "Level %d: no ball picker by the range" % level)
	if life._pickers.is_empty():
		life.free()
		built.free()
		return
	var picker: ClubLife.Walker = life._pickers[0]
	var attendant: ClubLife.Walker = null
	for p in life._staff:
		if p.data.has("picker"):
			attendant = p
	check(attendant != null, "Level %d: the range attendant hasn't the picker" % level)
	# balls lying out on the field, in a line across it at 120 m (some under each lane)
	var fac := built.get_node("driving_range") as Node3D
	var lying := ClubLife.Group.new()
	lying.phase = "at_place"  # (no golfers: a flight sat down for good, holding the balls)
	lying.timer = 1.0e9
	var front := -FacilityBuilder.footprint("driving_range").y * 0.5
	for x in range(-24, 25, 1):
		var ball := MeshInstance3D.new()
		ball.mesh = SphereMesh.new()
		life.add_child(ball)
		ball.global_position = fac.global_transform * Vector3(x, 0.045, front - 120.0)
		lying.practice_balls.append(ball)
	life._groups.append(lying)
	var start := picker.node.global_position
	attendant.data["pick_at"] = 0.0
	var rode := false
	var farthest := 0.0
	var fullest := 0  # balls showing in the picker's baskets at most
	for step in range(9000):
		life._process(0.1)
		fullest = maxi(fullest, life._basket_count(picker))
		rode = rode or attendant.riding
		farthest = maxf(farthest, picker.node.global_position.distance_to(start))
		if rode and not attendant.riding and attendant.data.get("pick", "") == "":
			break
	var picked := lying.practice_balls.filter(func(ball) -> bool: return not is_instance_valid(ball) or not (ball as Node3D).visible).size()
	check(rode, "Level %d: the attendant never got in the picker" % level)
	check(farthest > 100.0, "Level %d: the picker never went out over the field (%.0f m at most)" % [level, farthest])
	check(picked >= 4, "Level %d: the picker picked up only %d of the balls in its lanes" % [level, picked])
	check(fullest >= picked * ClubLife.BASKET_SHOW, "Level %d: the baskets didn't fill with what it picked up (%d showing for %d)" % [level, fullest, picked])
	check(life._basket_count(picker) == 0, "Level %d: the baskets weren't emptied once it was parked (%d left)" % [level, life._basket_count(picker)])
	check(picker.node.global_position.distance_to(start) < 2.5, "Level %d: the picker isn't parked back by the range (%.1f m off)" % [level, picker.node.global_position.distance_to(start)])
	check(not attendant.riding and attendant.node.get_parent() == life, "Level %d: the attendant didn't get out at the end" % level)
	life._groups.erase(lying)
	life.clear()
	life.free()
	built.free()
