extends SceneTree
## People walk straight across open ground at any angle -- on the course's grid, the facilities'
## grounds and a room's floor -- not in the grid's stair steps (zig-zagging), and still round
## what's in the way.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_walk_smooth_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func length(path: Array, from: Vector2) -> float:
	var total := 0.0
	var at := from
	for p: Vector3 in path:
		total += at.distance_to(Vector2(p.x, p.z))
		at = Vector2(p.x, p.z)
	return total


func run() -> void:
	var c := PaintedCourse.create("Walk smooth", Vector2i(400, 400))
	c.holes.append({"tee": Vector2(150, 150), "pin": Vector2(150, 60), "par": 3, "bends": [], "curve": false})
	c.paint(PaintedCourse.Surface.WOODS, Vector2(-60, -60), 12, 1, 1)
	var b := CourseBusiness.create()
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}}
	b.built = {"clubhouse": 2, "parking_lot": 2}
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": 2, "pos": b.placements[type]["pos"], "rot": 0.0})
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	unstick_sequence_check(life)
	# across the open course at an awkward angle: straight there
	var a := Vector2(20, -140)
	var z := Vector2(110, -95)
	var route: Array = life._route(a, z)
	var straight := a.distance_to(z)
	check(route.size() <= 3 and length(route, a) < straight * 1.03, "Course: %d corners, %.1f m for %.1f m straight" % [route.size(), length(route, a), straight])
	# and round the woods, not through them
	var w0 := Vector2(-90, -60)
	var w1 := Vector2(-30, -60)
	var round: Array = life._route(w0, w1)
	var through := false
	for p: Vector3 in round:
		through = through or c.surface_at(Vector2(p.x, p.z)) == PaintedCourse.Surface.WOODS
	check(not round.is_empty() and not through, "Course: the way round the woods cuts through them")
	# across the clubhouse's grounds, diagonally
	var g0 := Vector2(-150, 100)
	var g1 := Vector2(-128, 112)
	var grounds: Array = life._grounds_path(g0, g1)
	check(not grounds.is_empty() and grounds.size() <= 4 and length(grounds, g0) < g0.distance_to(g1) * 1.06, "Grounds: %d corners, %.1f m for %.1f m straight" % [grounds.size(), length(grounds, g0), g0.distance_to(g1)])
	# across a room
	var house := built.get_node("clubhouse") as Node3D
	var rig := FacilityBuilder.rig(house)
	var box: Dictionary = rig["boxes"]["lobby"]
	var rect: Rect2 = (box["rect"] as Rect2).grow(-1.0)
	life._guest_nav(house)
	var r0 := FacilityBuilder.nav_floor_point(house, "guest", rect.position)
	var r1 := FacilityBuilder.nav_floor_point(house, "guest", rect.end)
	var room := FacilityBuilder.nav_route(house, "guest", r0, r1)
	check(room.size() >= 2, "Room: no way across the lobby")
	var steps := 0
	for i in range(1, room.size() - 1):
		var d0 := (room[i] - room[i - 1]).normalized()
		var d1 := (room[i + 1] - room[i]).normalized()
		if d0.dot(d1) > 0.6 and d0.dot(d1) < 0.98:
			steps += 1  # (a stair step: a small turn one way, then back)
	print("course %d points, grounds %d, room %d (%d stair steps)" % [route.size(), grounds.size(), room.size(), steps])
	check(steps <= 2, "Room: the walk across the lobby zig-zags (%d stair steps)" % steps)
	life.clear()
	life.free()
	built.free()
	print("WALK SMOOTH: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func unstick_sequence_check(life: ClubLife) -> void:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	w.node.position = Vector3(20, 0, -140)
	var goal := Vector3(20, 0, -150)
	w.path = [w.node.position + Vector3(0.25, 0, 0), goal]
	life._unstick(w, 0.1)
	check(w.path == [goal], "Walker kept circling an almost-reached intermediate corner")
	w.path = [w.node.position + Vector3(0.25, 0, 0)]
	life._unstick(w, 0.1)
	check(w.path.size() == 1, "Corner tolerance discarded the final destination")
	w.data.clear()
	w.path = [goal]
	for attempt in range(4):
		life._unstick(w, 1.6)  # Hold position to model a failed walking attempt.
		var move: Vector3 = (w.path[0] as Vector3) - w.node.position
		if attempt < 2: check(move.x > 1.5 and absf(move.z) < 0.01, "Stuck NPC did not try right twice")
		elif attempt == 2: check(move.x < -1.5 and absf(move.z) < 0.01, "Stuck NPC did not try left third")
		else: check(absf(move.x) < 0.01 and move.z < -1.5, "Stuck NPC did not walk straight fourth")
		check(w.path.size() <= 2 and w.path.back() == goal, "Recovery stacked detours or lost the original destination")
	w.path = [goal]
	w.node.position.z -= 0.4
	life._unstick(w, 0.1)
	check(int(w.data.get("stuck_stage", 0)) == 0, "Forward progress did not reset recovery")
	w.data["seated"] = true
	var path := w.path.duplicate()
	life._unstick(w, 2.0)
	check(w.path == path and not w.data.has("unstick_goal"), "Seated NPC started a walking recovery")
	# A cart to the right blocks both right attempts; the left attempt remains available.
	w.data.clear()
	w.node.position = Vector3(20, 0, -140)
	w.path = [goal]
	var cart := ClubLife.Walker.new()
	cart.node = Node3D.new()
	life.add_child(cart.node)
	cart.node.position = Vector3(20.9, 0, -140)
	cart.data = {"vehicle": true, "half": Vector2(0.4, 0.5)}
	life._pool.append(cart)
	for attempt in range(2):
		life._unstick(w, 1.6)
		check(w.path == [goal], "Right recovery cuts through a parked cart")
	life._unstick(w, 1.6)
	check((w.path[0] as Vector3).x < 19.0, "Blocked right attempts did not lead to a left escape")
	life._pool.erase(cart)
	cart.node.queue_free()
	# The same sequence must respect an indoor wall.
	w.data.clear()
	w.path = [goal]
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, 150, 150)
	grid.offset = Vector2(5.1, -165.1)
	grid.cell_size = Vector2(0.2, 0.2)
	grid.update()
	for z in range(150):
		for x in range(150):
			var cell := Vector2i(x, z)
			if grid.get_point_position(cell).x > 20.5: grid.set_point_solid(cell)
	w.data["walk_region"] = {"nav": {"astar": grid}, "xf": Transform3D.IDENTITY}
	for attempt in range(2):
		life._unstick(w, 1.6)
		check(w.path == [goal], "Right recovery cuts through a wall")
	life._unstick(w, 1.6)
	check((w.path[0] as Vector3).x < 19.0, "Wall-blocked right attempts did not lead to a left escape")
	w.node.queue_free()
