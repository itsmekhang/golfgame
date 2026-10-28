extends SceneTree
## A flight riding carts, checked in: out the back to the end of the walk, while the cart boy
## brings their carts round -- up the front drive to the curb by the bag drop, their bags carried
## from the bag drop into the bag wells, then round to them -- for them to get in and go.
## Every clubhouse level (its own front drive).
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false)
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [1, 2, 3, 4]:
		await one_level(level, 1)
	await one_level(4, 2)  # (two cart boys: a cart each at once)
	await one_level(4, 3)  # Every attendant can take delivery, replenishment, and cleaning work.
	print("BAG RUN: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func one_level(level: int, boys_hired: int) -> void:
	var c := PaintedCourse.create("Bag run test", Vector2i(400, 400))
	for points in [[Vector2(60, 20), Vector2(60, -70)], [Vector2(-20, -30), Vector2(-20, -120)]]:
		c.holes.append({"tee": points[0], "pin": points[1], "par": 3, "bends": [], "curve": false})
		c.paint(PaintedCourse.Surface.GREEN, points[1], 9, 1, 1)
		c.paint(PaintedCourse.Surface.TEE, points[0], 5, 1, 1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}, "cart_barn": {"pos": Vector2(-10, 135), "rot": 0.0}}
	b.built = {"clubhouse": level, "cart_barn": 1, "parking_lot": 1}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "cart_attendant": boys_hired}
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": b.level(type), "pos": b.placements[type]["pos"], "rot": 0.0, "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life._rng.seed = 4100 + level * 10 + boys_hired
	seed(62026 + level * 10 + boys_hired)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	var house := built.get_node("clubhouse") as Node3D
	var boxes: Dictionary = FacilityBuilder.rig(house)["boxes"]
	var drive := life._front_drive()
	check(drive.size() >= 2, "L%d: no front drive" % level)
	var curb: Vector3 = (drive[0] as Array)[(drive[0] as Array).size() - 1] if drive.size() >= 2 else Vector3.INF
	var boys: Array = life._staff.filter(func(p: ClubLife.Walker) -> bool: return str(p.data.get("role", "")) == "cart_attendant")
	check(boys.size() == boys_hired, "L%d: %d cart boys, not %d" % [level, boys.size(), boys_hired])
	delivery_required_check(life, level)
	var g := life._new_arrival(1)
	while g != null and g.golfers.size() < 4:  # (a four-ball: two carts)
		life._groups.erase(g)
		life._free_group(g)
		g = life._new_arrival(1)
	check(g != null and g.wants_cart, "L%d: no flight riding carts" % level)
	if g == null or boys.is_empty():
		life.queue_free()
		built.queue_free()
		await process_frame
		return
	g.range_visit = false
	g.short_visit = false
	var boy: ClubLife.Walker = boys[0]
	var together := 0  # the most cart boys out in carts at once
	var phases := {}
	var previous := ""
	var at_curb := {}  # cart -> it pulled up at the curb by the bag drop
	var carried := false  # the cart boy had a bag of theirs on his back
	var bags_aboard := true  # every cart reached them with its riders' bags in it
	var in_house := 0  # moments a cart was inside the clubhouse
	var bag_seen := 0  # moments a checked-in golfer had their bag on (they never fetch it)
	var waited := 0.0
	var ridden: Array = []
	var meet_far := 0.0
	var walk_end := Vector3.INF
	var way: Array = FacilityBuilder.rig(house).get("tee_way", [])
	if not way.is_empty():
		walk_end = house.global_transform * (way[way.size() - 1] as Transform3D).origin
	for step in range(24000):
		if not life._groups.has(g) or g.phase == "travel":
			break
		life._spawn_wait = 1e9
		if g.phase != previous:
			previous = g.phase
			phases[g.phase] = true
			print("L%d %d %s" % [level, step, g.phase])
		life._process(0.25)
		if OS.get_environment("BAG_RUN_TRACE") != "":
			var steps: Array = boy.data.get("steps", [])
			var now := "%s %s" % [steps[0]["do"], steps[0].get("kind", steps[0].get("at", ""))] if not steps.is_empty() else "-"
			if now != str(boy.data.get("trace", "")):
				boy.data["trace"] = now
				print("  boy %.1f s: %s at %s" % [step * 0.25, now, str(Vector2(boy.node.global_position.x, boy.node.global_position.z).round())])
		if g.phase == "cart_wait":
			waited = g.timer
			ridden = g.carts.duplicate()
			carried = carried or boys.any(func(b2: ClubLife.Walker) -> bool: return b2.data.has("bag"))
			together = maxi(together, boys.filter(func(b2: ClubLife.Walker) -> bool: return b2.riding and g.carts.any(func(c2: ClubLife.Walker) -> bool: return b2.node.get_parent() == c2.node)).size())
			for k in range(g.golfers.size()):
				var w: ClubLife.Walker = g.golfers[k]
				var bag: Variant = w.data.get("bag")
				if bag != null and is_instance_valid(bag) and (bag as Node3D).visible:
					bag_seen += 1
			for cart: ClubLife.Walker in g.carts:
				var p := cart.node.global_position
				if curb != Vector3.INF and Vector2(p.x - curb.x, p.z - curb.z).length() < 5.5:
					at_curb[cart] = true
				var l := house.global_transform.affine_inverse() * p
				for id in boxes:
					if id != "valet" and (boxes[id]["rect"] as Rect2).has_point(Vector2(l.x, l.z)):
						in_house += 1
				if cart.data.get("delivered", false) and not cart.data.has("checked"):
					cart.data["checked"] = true
					var i: int = g.carts.find(cart)
					var riders := mini(2, g.golfers.size() - i * 2)
					bags_aboard = bags_aboard and (cart.data.get("bags", []) as Array).size() == riders
					if walk_end != Vector3.INF:
						meet_far = maxf(meet_far, Vector2(p.x - walk_end.x, p.z - walk_end.z).length())
	check(phases.has("cart_wait"), "L%d: the flight never waited for its carts out the back: %s" % [level, str(phases.keys())])
	check(not phases.has("bag_pickup"), "L%d: riders went out the front for their own bags" % level)
	check(g.phase in ["tee_queue", "travel"] and g.golfers.all(func(w: ClubLife.Walker) -> bool: return w.riding), "L%d: the flight never got going in its carts: %s" % [level, g.phase])
	check(waited < ClubLife.BAG_RUN_SERVICE_TARGET, "L%d: the cart boy took too long (%.0f s): delivery exceeded its service target" % [level, waited])
	check(ridden.size() == 2 and at_curb.size() == ridden.size(), "L%d: not every cart pulled up at the bag drop (%d of %d)" % [level, at_curb.size(), ridden.size()])
	check(together >= 1 and together <= mini(boys_hired, 2), "L%d: invalid number of drivers on the flight's delivery carts: %d" % [level, together])
	check(carried, "L%d: the cart boy never carried a bag over" % level)
	check(bags_aboard, "L%d: a cart reached its riders without their bags" % level)
	check(in_house == 0, "L%d: a cart drove through the clubhouse (%d moments)" % [level, in_house])
	check(bag_seen == 0, "L%d: a checked-in rider had their bag on them (%d moments)" % [level, bag_seen])
	check(meet_far < 20.0, "L%d: the carts were left %.0f m from the end of the walk" % [level, meet_far])
	for b2: ClubLife.Walker in boys:
		# (riding one of the barn's carts out to wash, or back in, is his own job between runs)
		var on_run := (b2.data.get("steps", []) as Array).any(func(st: Dictionary) -> bool: return str(st.get("kind", "")) in ["curb", "away"] or str(st.get("do", "")) in ["grab", "stow", "hand_over"])
		check(not (b2.riding and on_run) and not b2.data.has("bag") and not b2.data.has("bag2"), "L%d: a cart boy's still in a cart or holding a bag" % level)
	for cart: ClubLife.Walker in ridden:
		check((cart.data.get("cargo", []) as Array).is_empty(), "L%d: bags left riding on a cart's passenger side" % level)
	print("L%d, %d cart boy(s): a four-ball's carts with them after %.0f s" % [level, boys_hired, waited])
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame


func delivery_required_check(life: ClubLife, level: int) -> void:
	var g := life._new_arrival(1)
	g.range_visit = true
	g.short_visit = false
	g.checked_in = true
	life._send_to_collection(g)
	check(g.carts.is_empty() and g.phase == "collect", "L%d: warm-up claimed a self-service cart" % level)
	var boy: ClubLife.Walker = life._cart_boys()[0]
	var wash_prep := life._barn_cart_out(boy)
	var staged: ClubLife.Walker = wash_prep[0]["cart"] if not wash_prep.is_empty() else null
	var staged_at := staged.node.global_position if staged != null else Vector3.ZERO
	if staged != null: boy.data["steps"] = wash_prep
	g.range_visit = false
	life._send_to_collection(g)
	check(g.bag_run and g.phase == "cart_wait", "L%d: post-practice carts were not queued for delivery" % level)
	if staged != null:
		check(boy.data.get("steps", []) == wash_prep, "L%d: a new delivery interrupted the current task" % level)
		check(not staged.node.is_queued_for_deletion() and staged.node.global_position == staged_at, "L%d: current task lost its reserved cart" % level)
	var positions: Array = []
	for c: ClubLife.Walker in g.carts:
		positions.append(c.node.global_position)
	g.timer = ClubLife.BAG_RUN_SERVICE_TARGET + 1.0
	life._step_group(g, 0.1)  # No attendant has moved yet.
	for i in g.carts.size():
		check(not (g.carts[i] as ClubLife.Walker).data.get("delivered", false), "L%d: timeout fabricated cart delivery" % level)
		check((g.carts[i] as ClubLife.Walker).node.global_position == positions[i], "L%d: undelivered cart teleported" % level)
	check(not g.golfers.any(func(w: ClubLife.Walker) -> bool: return w.riding), "L%d: golfer boarded an undelivered cart" % level)
	for w: ClubLife.Walker in g.golfers:
		w.path = [w.node.global_position + Vector3(5, 0, 0)]
	(g.carts[0] as ClubLife.Walker).data["delivered"] = true
	life._step_group(g, 0.1)
	for k in range(mini(2, g.golfers.size())):
		check(g.golfers[k].data.get("to_ride", false), "L%d: delivered riders stayed on a blocked waiting route" % level)
	for cart: ClubLife.Walker in g.carts: cart.data.erase("delivered")
	life._cancel_bag_run(g)
	var staff := life._staff
	life._staff = []
	life._send_to_collection(g)
	check(g.phase == "delivery_request" and g.carts.is_empty(), "L%d: golfer collected a cart without an attendant" % level)
	life._staff = staff
	life._groups.erase(g)
	life._free_group(g)

	# Restore only this test fixture; production workers finish the whole job.
	if staged != null:
		var bay := int(staged.data.get("barn_slot", -1))
		life._pool.erase(staged)
		life._stock.erase(staged)
		life._barn_out.erase(bay)
		life._barn_slot_shown(bay, true)
		staged.node.queue_free()
		boy.data.erase("steps")
		boy.data.erase("watch")
		boy.path.clear()
