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
	for destination in ["driving_range", "short_game"]:
		await scenario(destination)
	print("CART BEFORE PRACTICE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
func scenario(destination: String) -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Cart before warm-up", Vector2i(500, 500))
	life.course.holes = [{"tee": Vector2(40,-10), "pin": Vector2(40,-100), "par": 3, "bends": [], "curve": false}]
	life.business = CourseBusiness.create()
	life.business.built = {"clubhouse": 4, "cart_barn": 4, "parking_lot": 1, "driving_range": 1, "short_game": 3}
	life.business.rooms = {"pro_shop": 1, "valet": 3}
	life.business.staff = {"cart_attendant": 3, "shop_clerk": 1, "range_attendant": 1}
	life.business.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "cart_barn": {"pos": Vector2(-10, 135), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}, "driving_range": {"pos": Vector2(90,100), "rot": 0.0}, "short_game": {"pos": Vector2(90,10), "rot": 0.0}}
	var items: Array = []
	for type in life.business.placements:
		items.append({"type": type, "level": life.business.level(type), "pos": life.business.placements[type]["pos"], "rot": 0.0, "rooms": life.business.rooms})
	var built := FacilityBuilder.build(items, func(_p): return 0.0, false, true)
	root.add_child(built)
	life.facilities = built
	life.refresh()
	life._rng.seed = 10828
	seed(10828)
	var group := life._new_arrival(1)
	check(group != null and group.wants_cart, "Could not create a cart flight")
	if group == null: return
	group.range_visit = destination == "driving_range"
	group.short_visit = destination == "short_game"
	var phases := {}
	var original_carts: Array = []
	var saw_loaded := false
	var saw_practice := false
	var resumed := false
	var previous := ""
	var late_jobs := 0
	for tick in range(18000):
		life._spawn_wait = 1e9
		life._process(0.1)
		if group.phase != previous:
			previous = group.phase
			print(destination, " ", tick / 10.0, " ", group.phase)
			phases[group.phase] = true
		if group.phase == "practice_park" and not saw_practice:
			saw_practice = true
			original_carts = group.carts.duplicate()
			saw_loaded = not original_carts.is_empty()
			for c: ClubLife.Walker in original_carts:
				saw_loaded = saw_loaded and (c.data.get("bags", []) as Array).size() == mini(2, group.golfers.size() - group.carts.find(c) * 2)
			check(phases.has("cart_wait") and saw_loaded, "Practice began without loaded carts being handed over first")
			check(group.golfers.all(func(w): return w.riding), "A golfer walked to warm-up instead of riding their cart")
		if saw_practice:
			for run: Array in life._bag_runs:
				if run[0] == group: late_jobs += 1
			if group.phase == "range_practice":
				for w: ClubLife.Walker in group.golfers:
					if w.data.get("range_step") == "hit": w.data["range_hit"] = ClubLife.RANGE_BALLS
			if group.phase == "short_practice":
				for w: ClubLife.Walker in group.golfers: w.data["short_left"] = 0
			if group.phase in ["tee_queue", "travel"]:
				resumed = true
				break
		if tick % 100 == 0: await process_frame
	check(saw_practice and resumed, "Flight did not finish warm-up and rejoin the round")
	check(group.carts == original_carts and not group.bag_run and late_jobs == 0, "Warm-up triggered a second cart/bag delivery")
	if resumed:
		check(group.golfers.all(func(w): return w.riding), "Golfers failed to reboard their own carts after practice")
		for c: ClubLife.Walker in group.carts:
			check((c.data.get("bags", []) as Array).size() == mini(2, group.golfers.size() - group.carts.find(c) * 2), "Bags were lost or duplicated when reboarding after warm-up")
	print(destination, " loaded before practice=", saw_loaded, " resumed=", resumed, " late delivery jobs=", late_jobs)
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
