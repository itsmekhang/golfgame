extends SceneTree
var failed := false

class RowLife extends ClubLife:
	var slots: Array = []
	var shown := {}
	func _barn_slots() -> Array:
		return slots
	func _barn_slot_shown(k: int, visible_cart: bool) -> void:
		shown[k] = visible_cart

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func actor(life: ClubLife) -> ClubLife.Walker:
	var c := ClubLife.Walker.new()
	c.node = Node3D.new()
	life.add_child(c.node)
	return c

func run() -> void:
	await row_order(0.0)
	await row_order(0.8)
	await actual_barn()
	print("BARN REPARK: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func row_order(rotation: float) -> void:
	var life := RowLife.new()
	root.add_child(life)
	life.set_process(false)
	var facilities := Node3D.new()
	root.add_child(facilities)
	var barn := Node3D.new()
	barn.name = "cart_barn"
	facilities.add_child(barn)
	barn.rotation.y = rotation
	barn.position = Vector3(10, 0, -12)
	life.facilities = facilities
	var entries: Array = []
	for z in [3.0, 6.1, 9.2]:
		var local := Transform3D(Basis.IDENTITY, Vector3(0, 0, z))
		life.slots.append(barn.global_transform * local)
		entries.append({"xf": local})
	barn.set_meta("rig", {"barn_carts": entries, "barn_bays": [Transform3D.IDENTITY]})
	var carts: Array = []
	for i in range(3):
		var c := actor(life)
		c.node.global_position = barn.global_transform * Vector3(10 + i * 4, 0, -8)
		c.data = {"vehicle": true, "golf_cart": true, "half": ClubLife.CART_HALF, "barn_slot": i}
		carts.append(c)
		life._pool.append(c)
		life._barn_out[i] = c
	var p := actor(life)
	for i in range(3):
		var c: ClubLife.Walker = carts[i]
		var steps := life._barn_cart_in(c)
		check(not steps.is_empty(), "No return route for cart %d" % i)
		if steps.is_empty(): continue
		var slot := int(steps.back()["slot"])
		check(slot == 2 - i, "Empty row was not filled back-to-front: cart %d selected %d" % [i, slot])
		var reverse: Dictionary = steps[4]
		check(reverse["reverse"] == 2 and (reverse["path"] as Array).back().is_equal_approx((life.slots[slot] as Transform3D).origin), "Cart does not reverse all the way to its assigned space")
		if i < 2:
			check(life._barn_cart_in(carts[i + 1]).is_empty(), "Another attendant entered the row before its first cart parked")
		if i == 0:
			check(life._barn_out.has(0) and life._barn_out[0] == null, "Reassignment created a phantom front cart")
		if i == 1:
			c.node.global_transform = life.slots[slot]
			c.data["reverse"] = 2
			check(not life._cart_ahead(c, barn.global_basis.z.normalized()), "Road-following distance prevents a cart from reaching the middle parking space")
			c.data["reverse"] = 0
			check(life._cart_ahead(c, barn.global_basis.z.normalized()), "Tight parking changed normal road-following clearance")
		# An unexpectedly cleared route must be retried, not treated as fully parked.
		c.node.global_position = barn.global_transform * Vector3(0, 0, -5)
		c.path.clear()
		p.data["steps"] = [{"do": "drive", "cart": c, "kind": "yard", "path": reverse["path"], "reverse": 2, "set": true}]
		life._cart_boy(p)
		check(not c.path.is_empty() and not (p.data["steps"] as Array).is_empty(), "Stopped-short cart incorrectly completed its parking task")
		c.node.global_transform = life.slots[slot]
		p.data["steps"] = [{"do": "put_away", "cart": c, "slot": slot}]
		life._cart_boy(p)
		check(not life._barn_returns.has(slot) and not life._barn_out.has(slot), "Completed return did not release its row reservation")
	check(life._barn_out.is_empty() and life.shown.size() == 3, "All three carts did not finish in their row")
	print("ROW ORDER rotation %.1f: deepest, middle, front; exclusive reservations; full reverse; no phantom slots" % rotation)
	life.queue_free()
	facilities.queue_free()
	await process_frame

func actual_barn() -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Barn repark", Vector2i(180, 180))
	life.business = CourseBusiness.create()
	life.business.built = {"cart_barn": 4}
	life.business.placements = {"cart_barn": {"pos": Vector2.ZERO, "rot": 0.0}}
	var built := FacilityBuilder.build([{"type": "cart_barn", "level": 4, "pos": Vector2.ZERO, "rot": 0.0}], func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	life.facilities = built
	life._build_course_nav()
	var carts: Array = []
	for i in range(3):
		var c := life._new_barn_cart()
		check(c != null, "Could not empty the three-cart row")
		if c == null: break
		carts.append(c)
		c.node.position = Vector3(35 + i * 5, 0, -35)
	if carts.size() != 3:
		life.queue_free()
		built.queue_free()
		await process_frame
		return
	var slots := life._barn_slots()
	var lane_x: float = (slots[int(carts[0].data["barn_slot"])] as Transform3D).origin.x
	var p := life._person("staff_cart_attendant")
	p.data["role"] = "cart_attendant"
	p.think = func(worker: ClubLife.Walker) -> void: life._cart_boy(worker)
	life._staff = [p]
	var previous_depth := INF
	var expected: Array = carts.map(func(c: ClubLife.Walker) -> int: return int(c.data["barn_slot"]))
	expected.sort_custom(func(a: int, b: int) -> bool: return (slots[a] as Transform3D).origin.z > (slots[b] as Transform3D).origin.z)
	var serial := 0
	for c: ClubLife.Walker in carts:
		life._settle_in_row(c, Vector2(lane_x, 5.1))
		c.data["washing"] = true
		p.data["wash_cart"] = c
		p.path.clear()
		p.wait = 0
		p.node.global_position = life._cart_door(c, 0)
		var destination: int = expected[serial]
		var steps: Array
		if serial == 0:
			life._stock = [c]
			p.data.erase("wash_cart")
			c.data.erase("washing")  # Unreserved stock before the scheduler claims it.
			var wash := life._wash_steps(p)
			check(wash.back().get("do") == "repark" and life._barn_returns.is_empty(), "Wash did not defer its parking destination until cleaning finished")
			steps = wash  # Execute hose, drying, boarding, and the entire return maneuver.
		else:
			steps = life._barn_cart_in(c)
			check(not steps.is_empty() and int(steps.back()["slot"]) == destination, "Actual washed cart chose the wrong return space")
		check(not steps.is_empty(), "Actual washed cart has no return plan")
		if steps.is_empty(): continue
		var target: Vector3 = (slots[destination] as Transform3D).origin
		check(is_equal_approx(target.x, lane_x) and target.z < previous_depth, "Actual row does not fill deepest-first")
		previous_depth = target.z
		p.data["steps"] = steps
		var finished := false
		for tick in range(5000):
			life._clock += 0.1
			life._step(c, 0.1)
			if p.data.has("cart_move"): life._cart_move_step(p, 0.1)
			else: life._step(p, 0.1)
			if not life._pool.has(c):
				finished = true
				break
			if tick % 100 == 0: await process_frame
		if not finished: print("WORKER DEBUG ", p.node.global_position, " path ",p.path," blocked ",p.data.get("blocked")," target ",p.data.get("outdoor_target")," region ",p.data.get("walk_region",{}).get("xf"))
		if not finished:
			var nav: Dictionary = life._grounds_nav
			var grid: AStarGrid2D = nav["astar"]
			var a := FacilityBuilder._nav_cell(nav, Vector2(p.node.global_position.x,p.node.global_position.z))
			var to: Vector2 = p.data["outdoor_target"]
			var b := FacilityBuilder._nav_cell(nav,to)
			print("GRID DEBUG ",a," ",b," points ",grid.get_point_path(a,b).size()," region ",nav["rect"]," positions ",grid.get_point_position(a)," ",grid.get_point_position(b))
			for v: ClubLife.Walker in life._vehicles():
				if v.node.global_position.distance_to(p.node.global_position) < 10: print("NEAR BODY ",v.node.global_position," half ",life._footprint(v)," center ",v.data.get("body_center"))

		check(finished, "Attendant failed to reverse all the way into actual barn slot %d; cart at %s target %s steps %s" % [destination, c.node.global_position, target, p.data.get("steps", [])])
		check(not p.riding and life._barn_returns.is_empty(), "Attendant left the row before parking and dismounting were complete")
		print("ACTUAL BARN: returned slot ", destination, " at depth ", target.z, " finished ", finished, " full wash + return ", serial == 0)
		serial += 1
		await process_frame
		if not finished: break
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
