extends SceneTree
## A facility picked up and put down elsewhere with people at it (user): they go with it, keeping
## their places on it -- not off to where it used to be. The clubhouse moved with a flight in it,
## the parking lot with their car in its bay.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_facility_move_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func build(b: CourseBusiness) -> Node3D:
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": b.level(type), "pos": b.placements[type]["pos"], "rot": float(b.placements[type]["rot"]), "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	return built


func run() -> void:
	var c := PaintedCourse.create("Move", Vector2i(500, 500))
	c.holes.append({"tee": Vector2(80, 20), "pin": Vector2(80, -70), "par": 3, "bends": [], "curve": false})
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.built = {"clubhouse": 2, "parking_lot": 1}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1}
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}}
	var built := build(b)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	var g := life._new_arrival(0)
	check(g != null, "No flight came in")
	if g == null:
		quit(1)
		return
	g.range_visit = false
	g.short_visit = false
	var house := built.get_node("clubhouse") as Node3D
	var inside := false
	for step in range(6000):
		life._spawn_wait = 1e9
		life._process(0.25)
		var l := house.global_transform.affine_inverse() * (g.golfers[0] as ClubLife.Walker).node.global_position
		if FacilityBuilder.site("clubhouse", 2).has_point(Vector2(l.x, l.z)) and g.phase in ["lobby", "shop_walk", "check_in", "shop_front"]:
			inside = true
			break
	check(inside, "The flight never got into the clubhouse (%s)" % g.phase)
	var w: ClubLife.Walker = g.golfers[0]
	var local_before := house.global_transform.affine_inverse() * w.node.global_position
	var car_local := (built.get_node("parking_lot") as Node3D).global_transform.affine_inverse() * g.car.node.global_position
	# both picked up and put down 60 m along, the clubhouse turned a quarter round
	b.placements["clubhouse"] = {"pos": Vector2(-45, 50), "rot": PI / 2}
	b.placements["parking_lot"] = {"pos": Vector2(-45, 150), "rot": 0.0}
	built.queue_free()
	built = build(b)
	life.facilities = built
	life.refresh()
	house = built.get_node("clubhouse") as Node3D
	var local_after := house.global_transform.affine_inverse() * w.node.global_position
	check(local_after.distance_to(local_before) < 0.05, "A golfer in the clubhouse wasn't carried with it: %s -> %s (local)" % [local_before, local_after])
	var car_after := (built.get_node("parking_lot") as Node3D).global_transform.affine_inverse() * g.car.node.global_position
	check(car_after.distance_to(car_local) < 0.05, "Their car wasn't carried with the lot: %s -> %s" % [car_local, car_after])
	for p: Vector3 in w.path:
		var l := house.global_transform.affine_inverse() * p
		check(l.length() < 80.0, "A golfer's way still runs to where the clubhouse was: %s" % p)
	# and on from there: checked in, out to the course
	var phases := {}
	for step in range(12000):
		life._spawn_wait = 1e9
		life._process(0.25)
		phases[g.phase] = true
		if not life._groups.has(g) or g.phase in ["tee_queue", "play", "travel"]:
			break
	check(phases.has("tee_queue") or phases.has("play") or phases.has("travel"), "After the move the flight never got out to the course: %s" % str(phases.keys()))
	print("FACILITY MOVE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
