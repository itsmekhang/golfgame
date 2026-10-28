extends SceneTree
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
	for ride in [false, true]:
		await scenario(ride)
	print("TEE CLEARANCE: ", "FAIL" if failed else "PASS", "; walkers and carts approach early, wait for distance, recheck each golfer")
	quit(1 if failed else 0)
func place(g: ClubLife.Group, at: Vector2) -> void:
	for k in range(g.golfers.size()):
		var w: ClubLife.Walker = g.golfers[k]
		w.node.global_position = Vector3(at.x + k * 2, 0, at.y)
		w.path.clear()
func scenario(ride: bool) -> void:
	var life := ClubLife.new()
	root.add_child(life); life.set_process(false)
	var tee := Vector2(0, 120)
	var pin := Vector2(0, -180)
	life.course = PaintedCourse.create("Tee clearance", Vector2i(400, 400))
	life.course.holes.append({"tee":tee,"pin":pin,"par":4,"bends":[],"curve":false})
	life.course.paint(PaintedCourse.Surface.TEE, tee, 5, 1, 1)
	life.course.paint(PaintedCourse.Surface.GREEN, pin, 9, 1, 1)
	life._build_course_nav()
	life._rng.seed = 419
	var ahead := ClubLife.Group.new()
	var next := ClubLife.Group.new()
	for g in [ahead, next]:
		for k in range(2): g.golfers.append(life._person("golfer_" + ["a", "e"][k]))
		life._plan_hole(g)
		life._groups.append(g)
	ahead.hole_reserved = true
	ahead.strokes = [1, 1]
	ahead.phase = "mount"
	next.phase = "tee_queue"
	next.queue_hole = 0
	next.queue_ticket = 2
	place(next, Vector2(-40, 155))
	place(ahead, tee + Vector2(0, -30))
	if ride:
		var cart := life._cart()
		cart.speed = ClubLife.RIDE; cart.ground = true
		cart.node.position = Vector3(-40, 0, 155)
		next.carts.append(cart)
		for k in range(2): life._seat(next.golfers[k], cart, k)
	check(life._tee_entry_blocked(next), "Admitted next flight while previous flight still owns the tee")
	ahead.stop = 1
	place(ahead, tee + Vector2(0, -6))
	check(life._tee_entry_blocked(next), "Did not let the departing flight clear the tee approach")
	place(ahead, tee + Vector2(0, -30))
	check(not life._tee_entry_blocked(next), "Waited for second shots before approaching the cleared tee")
	life._step_group(next, .1)
	check(next.phase == "travel" and next.hole_reserved, "Next flight did not approach the tee")
	# walkers gather beside the tee to wait; a flight in carts sits on in them, parked by it, while
	# the one ahead is still in reach (this one does: most do)
	var waiting := "travel" if ride else "tee_ready"
	if ride:
		next.sit_tight_hole = next.hole
		next.sit_tight = true
	for i in range(1200):
		life._step_group(next, .1)
		if next.phase == "tee_ready" or (ride and i > 20 and not life._moving(next.carts)): break
	check(next.phase == waiting, "Flight never gathered beside the tee: " + next.phase)
	if ride:
		check(next.golfers.all(func(w: ClubLife.Walker) -> bool: return w.riding), "Golfers got out of the cart while the flight ahead was in reach")
		var parked := Vector2(next.carts[0].node.global_position.x, next.carts[0].node.global_position.z)
		check(parked.distance_to(tee) < 18, "Cart did not park closer beside the tee")
		check(not life._cart_nav.is_point_solid(life._nav_cell_raw(parked)), "Cart parked on protected tee ground")
	else:
		for w: ClubLife.Walker in next.golfers:
			check(Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(tee) < 10, "Waiting golfer stayed in distant queue")
	var third := ClubLife.Group.new()
	third.hole = 0; third.queue_hole = 0; third.queue_ticket = 3; third.phase = "tee_queue"; third.stops = next.stops.duplicate()
	life._groups.append(third)
	check(life._tee_entry_blocked(third), "More than one waiting flight admitted beside the tee")
	life._groups.erase(third)
	for i in range(50): life._step_group(next, .1)
	check(next.strokes == [0, 0] and next.phase == waiting, "Shot at the group ahead before safe clearance")
	check(not next.balls[0].visible and not next.balls[1].visible, "Waiting flight spawned tee balls")
	# A distant golfer who has only hit once must not hold up the next flight.
	var safe := tee + (life._target(next) - tee).normalized() * (tee.distance_to(life._target(next)) + 55)
	# Changing holes must not release a shot while that flight is still physically ahead.
	ahead.hole = 1; ahead.hole_reserved = false
	for i in range(30): life._step_group(next, .1)
	check(next.strokes == [0, 0] and next.phase == waiting, "Ignored a flight leaving for the next hole while still in range")
	ahead.hole = 0; ahead.hole_reserved = true
	place(ahead, safe)
	life._step_group(next, .1)
	if ride:  # (out of the cart and over to the tee first)
		for i in range(300):
			if next.phase == "step_up": break
			life._step_group(next, .1)
	check(next.phase == "step_up", "Safe distance did not release the first golfer before second shots")
	# Someone returns into range while the golfer is walking into their stance.
	place(ahead, tee + Vector2(0, -40))
	for i in range(120): life._step_group(next, .1)
	check(next.strokes == [0, 0], "Step-up bypassed the distance check")
	place(ahead, safe)
	for i in range(150):
		life._step_group(next, .1)
		if next.strokes[0] == 1: break
	check(next.strokes == [1, 0] and ahead.strokes == [1, 1], "Could not tee off safely until previous flight hit again")
	place(ahead, tee + Vector2(0, -40))
	for i in range(250): life._step_group(next, .1)
	check(next.strokes == [1, 0] and next.phase == "tee_ready", "Second golfer did not recheck the group ahead")
	check(not next.balls[1].visible, "Second ball appeared before its golfer was cleared")
	# Cart bodies also count, even when the people themselves are farther away.
	place(ahead, safe)
	var occupied_lane := life._cart()
	occupied_lane.node.position = Vector3(0, 0, tee.y - 40)
	ahead.carts.append(occupied_lane)
	for i in range(30): life._step_group(next, .1)
	check(next.strokes == [1, 0], "Tee shot ignored a cart still in range")
	occupied_lane.node.position = Vector3(safe.x + 3, 0, safe.y)
	for i in range(150):
		life._step_group(next, .1)
		if next.strokes[1] == 1: break
	check(next.strokes == [1, 1], "Second golfer did not hit once the last cart cleared")
	life.clear(); life.queue_free()
	await process_frame
