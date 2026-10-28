extends SceneTree
var failed := false

class ParkingChoiceLife extends ClubLife:
	func _clubhouse_entry() -> Vector2:
		return Vector2.ZERO

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func route_cost(nav: Dictionary, path: PackedVector2Array) -> float:
	var cost := 0.0
	for i in range(1, path.size()):
		check(FacilityBuilder._clear_line(nav, path[i-1], path[i]), "Pedestrian route crosses a solid cell")
		cost += FacilityBuilder._walk_line_cost(nav, path[i-1], path[i])
	return cost

func run() -> void:
	var course := PaintedCourse.create("Parking and starting tees", Vector2i(250, 250))
	for i in range(18):
		var tee := Vector2(-100 + (i % 6) * 35, -90 + (i / 6) * 50)
		course.holes.append({"tee": tee, "pin": tee + Vector2(0, -25), "par": 3, "bends": [], "curve": false})
	var life := ParkingChoiceLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = course
	life.business = CourseBusiness.create()
	for level in range(1, 5):
		var built := FacilityBuilder.build([{"type": "parking_lot", "level": level, "pos": Vector2(8, 12), "rot": 0.6}], func(_p: Vector2) -> float: return 0.0, false, true)
		root.add_child(built)
		life.facilities = built
		var lot := built.get_child(0) as Node3D
		var rig := FacilityBuilder.rig(lot)
		var nav: Dictionary = rig["nav"]["pedestrian"]
		var vehicle_grid: AStarGrid2D = rig["nav"][""]["astar"]
		var lanes := FacilityBuilder.lot_driving_lanes(rig)
		var aisle: Array = lanes[0]
		var z: float = aisle[0].y
		var a := Vector2(-10, z)
		var b := Vector2(10, z)
		for ends in [[a, b], [b, a]]:
			var path := FacilityBuilder.nav_route(lot, "pedestrian", ends[0], ends[1])
			check(path.size() > 2, "L%d pedestrians still walk straight down the driving aisle" % level)
			var cost := route_cost(nav, path)
			var straight := FacilityBuilder._walk_line_cost(nav, ends[0], ends[1])
			check(cost < straight * 0.7, "L%d smoothing removed the safer edge route" % level)
		var center := FacilityBuilder._nav_cell(nav, a)
		check(vehicle_grid.get_point_weight_scale(center) == 1.0, "Pedestrian costs changed a vehicle grid")
		var cross := FacilityBuilder.nav_route(lot, "pedestrian", Vector2(3, z - 2), Vector2(3, z + 2))
		check(not cross.is_empty(), "L%d no way to cross an aisle to reach a car" % level)
		route_cost(nav, cross)
		life._grounds_nav = {}
		life._build_grounds_nav()
		var wa := lot.global_transform * Vector3(a.x, 0, a.y)
		var wb := lot.global_transform * Vector3(b.x, 0, b.y)
		for shortest in [false, true]:
			var grounds := life._grounds_path(Vector2(wa.x, wa.z), Vector2(wb.x, wb.z), shortest)
			check(grounds.size() > 2, "L%d rotated-lot approach ignores parking edges (shortest=%s)" % [level, shortest])
			var path := PackedVector2Array()
			for p: Vector3 in grounds: path.append(Vector2(p.x, p.z))
			var cost := route_cost(life._grounds_nav, path)
			var direct := FacilityBuilder._walk_line_cost(life._grounds_nav, Vector2(wa.x, wa.z), Vector2(wb.x, wb.z))
			check(cost < direct * 0.7, "L%d grounds smoothing cuts down the road" % level)
		print("PARKING ROUTES L%d: lane edges, crossings, rotated approach, and vehicle separation checked" % level)
		built.queue_free()
		await process_frame
	life.facilities = null
	life._grounds_nav = {}
	parking_threshold(life)
	starting_tees(life)
	life.clear()
	life.queue_free()
	await process_frame
	print("PARKING AND TEE REGRESSION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func parking_threshold(life: ClubLife) -> void:
	# The nearest vacant bay is beside an occupied one. Below half full an isolated
	# bay wins; at/above half full its shorter walk wins instead.
	var lot := Node3D.new()
	root.add_child(lot)
	var stalls: Array = []
	for x in [0, 2.8, 12, 30, 45, 60, 75, 90, 105, 120]:
		stalls.append(Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))
	var rig := {"stalls": stalls, "ada": [], "parked": [0, 5, 6, 7], "taken": {}}
	lot.set_meta("rig", rig)
	seed(17)
	check(life._choose_stall(lot) == 2, "Under 50% no longer prefers an empty neighboring space")
	rig["taken"] = {8: true}
	seed(17)
	check(life._choose_stall(lot) == 1, "At 50% the spacing preference still blocks the closest adjacent bay")
	rig["taken"] = {8: true, 9: true}
	seed(17)
	check(life._choose_stall(lot) == 1, "Above 50% cars still avoid adjacent spaces")
	rig["taken"] = {0: true}
	seed(17)
	check(life._choose_stall(lot) == 2, "A parked/reserved overlap counts the same car twice")
	rig["parked"] = range(10)
	check(life._choose_stall(lot) == -1, "A full lot returns an occupied space")
	lot.queue_free()
	print("PARKING THRESHOLD: below, at, above 50%, reservations, duplicates, and full lot checked")

func starting_tees(life: ClubLife) -> void:
	check(life._starting_hole() == 0, "Empty course should favor hole 1")
	var first := ClubLife.Group.new()
	first.hole = 0
	first.hole_reserved = true
	life._groups.append(first)
	check(life._starting_hole() == 9, "Busy hole 1 should offer hole 10")
	var tenth := ClubLife.Group.new()
	tenth.start_hole = 9
	tenth.hole = 9
	tenth.hole_reserved = true
	life._groups.append(tenth)
	var waiting := ClubLife.Group.new()
	waiting.start_hole = life._starting_hole()
	waiting.hole = waiting.start_hole
	waiting.stops = [life.course.holes[waiting.hole]["tee"]]
	check(waiting.hole in [0, 9] and life._tee_entry_blocked(waiting), "Both starts occupied: flight must wait at 1 or 10")
	life.business.hours = 2.0
	life.business.next_tee_hour = 2.0
	check(life._record_tee_start(tenth), "Legal tenth-tee start denied")
	check(not life._record_tee_start(waiting), "Tenth-tee start did not enforce the start interval")
	var invalid := ClubLife.Group.new()
	invalid.hole = 4
	invalid.stop = 1
	check(not life._tee_time_ready(invalid) and life._tee_entry_blocked(invalid), "A new flight can bypass the queue on a middle hole")
	life._groups.clear()
	var corrected := life._new_group(5, true, 0, 1, false)
	check(corrected != null and corrected.hole == 0 and corrected.stop == 0 and not corrected.hole_reserved and corrected.phase == "tee_queue", "New flight seeded onto a middle hole instead of queuing")
	life._groups.erase(corrected)
	life._free_group(corrected)
	var back := life._new_group(9, false, 0, 1, false)
	check(back.hole == 9 and back.holes_left == 18 and back.stop == 0, "Tenth-tee round does not contain the whole course")
	life._groups.erase(back)
	life._free_group(back)
	# Advance an established flight from 18 to 1, without spawning a new flight there.
	var ongoing := ClubLife.Group.new()
	ongoing.hole = 17
	ongoing.start_hole = 9
	ongoing.tee_started = true
	ongoing.holes_left = 10
	ongoing.stops = [Vector2.ZERO]
	life._next_stop(ongoing)
	check(ongoing.hole == 0 and ongoing.holes_left == 9 and ongoing.phase == "tee_queue", "Round starting at 10 does not wrap from 18 to 1")
	check(life._tee_time_ready(ongoing), "An ongoing round is treated as an illegal new start")
	var full_round := ClubLife.Group.new()
	full_round.hole = 9
	full_round.start_hole = 9
	full_round.tee_started = true
	full_round.holes_left = 18
	life._plan_hole(full_round)
	for i in range(18):
		full_round.queue_hole = full_round.hole
		full_round.queue_ticket = i
		full_round.stop = full_round.stops.size() - 1
		life._next_stop(full_round)
	check(full_round.queue_hole == -1 and full_round.queue_ticket == -1, "Finished round still blocks the last tee queue")
	check(full_round.scores.size() == 18 and full_round.holes_left == 0, "Tenth-tee round did not finish exactly 18 holes")
	for i in range(full_round.scores.size()):
		check(full_round.scores[i]["hole"] == (9 + i) % 18 + 1, "Tenth-tee round skipped or repeated a hole")
	var short_course := life.course.holes.duplicate()
	life.course.holes = life.course.holes.slice(0, 9)
	life._groups.append(first)
	check(life._starting_hole() == 0, "Nine-hole course offers nonexistent tenth tee")
	life.course.holes = short_course
	life._groups.clear()
	print("STARTING TEES: legal starts, busy-tee waiting, interval, middle-hole rejection, and full-round wrap checked")
	# Exercise the optional warm-up with an explicit first-tee backlog, rather than
	# relying on random arrival and delivery timing to create one.
	var practice := FacilityBuilder.build([{"type": "short_game", "level": 1, "pos": Vector2(40, 50), "rot": 0.0}], func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(practice)
	life.facilities = practice
	life.business.built = {"short_game": 1}
	life.business.placements = {"short_game": {"pos": Vector2(40, 50), "rot": 0.0}}
	life._build_course_nav()
	var head := life._new_group(0, false, 0, 1, false)
	var follower := life._new_group(0, false, 0, 1, false)
	head.queue_hole = 0
	head.queue_ticket = 100
	follower.queue_hole = 0
	follower.queue_ticket = 101
	check(life._try_wait_practice(follower), "A first-tee backlog no longer offers waiting practice")
	check(life._tee_rank(follower) == 1, "Warm-up lost the flight's place in the tee queue")
	var third := life._new_group(0, false, 0, 1, false)
	third.queue_hole = 0
	third.queue_ticket = 102
	check(life._tee_entry_blocked(third), "A later flight overtook the waiting flight at practice")
	print("WAITING PRACTICE: explicit first-tee backlog and queue order checked")
	practice.queue_free()
