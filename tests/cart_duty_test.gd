extends SceneTree
## All cart attendants share roles, finish current jobs, and prioritize bags/delivery,
## compaction, replenishment, then cleaning. Carts must always have a driver and stay outside.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_cart_duty_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for boys in [1, 2, 3]:
		await scenario(2, boys)
	for level in [1, 3, 4]:
		await scenario(level, 1)  # (their cart paths round the side: no cart in the clubhouse)
	print("CART DUTY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func scenario(level: int, hired: int) -> void:
	var c := PaintedCourse.create("Cart duty", Vector2i(400, 400))
	for points in [[Vector2(60, 20), Vector2(60, -70)], [Vector2(-20, -30), Vector2(-20, -120)]]:
		c.holes.append({"tee": points[0], "pin": points[1], "par": 3, "bends": [], "curve": false})
		c.paint(PaintedCourse.Surface.GREEN, points[1], 9, 1, 1)
		c.paint(PaintedCourse.Surface.TEE, points[0], 5, 1, 1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}, "cart_barn": {"pos": Vector2(-10, 135), "rot": 0.0}}
	b.built = {"clubhouse": level, "cart_barn": 1, "parking_lot": 1}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "cart_attendant": hired}
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": b.level(type), "pos": b.placements[type]["pos"], "rot": 0.0, "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	var house := built.get_node("clubhouse") as Node3D
	var boxes: Dictionary = FacilityBuilder.rig(house)["boxes"]
	var boys: Array = life._cart_boys()
	check(boys.size() == hired, "%d cart boys, not %d" % [boys.size(), hired])
	var did := {}  # boy -> {"run", "stock", "wash"}
	var last := {}
	var routed := {}  # cart -> its way's length last moment
	var manned := {}  # cart -> someone sat in it last moment
	var unmanned := 0
	var inside := 0
	var front_home := 0  # moments the front man (two or more) stood idle by the line
	var front_idle := 0
	var spawned := 0
	var active_jobs := {}
	for step in range(14000):
		life._spawn_wait = 1e9
		if step % 1000 == 0 and spawned < 4:
			var g := life._new_arrival(1)
			if g != null:
				g.range_visit = false
				g.short_visit = false
				spawned += 1
		for p: ClubLife.Walker in boys:
			active_jobs[p] = p.data.get("steps", [])
		life._process(0.25)
		for p: ClubLife.Walker in boys:
			var previous: Array = active_jobs[p]
			if not previous.is_empty():
				check(previous == p.data.get("steps", []), "An attendant abandoned an unfinished job")
		for k in range(boys.size()):
			var p: ClubLife.Walker = boys[k]
			var jobs: Dictionary = did.get_or_add(k, {})
			if p.data.has("wash_cart"):
				jobs["wash"] = true
			for s: Dictionary in p.data.get("steps", []):
				if str(s.get("kind", "")) == "curb":
					jobs["run"] = true
				elif str(s.get("kind", "")) in ["fetch", "up"]:
					jobs["stock"] = true
			if hired >= 2 and k == 0 and (p.data.get("steps", []) as Array).is_empty() and not p.riding:
				front_idle += 1
				var head := life._line_head()
				if head != Vector2.INF and Vector2(p.node.global_position.x, p.node.global_position.z).distance_to(head) < 6.0:
					front_home += 1
		var carts: Array = life._pool.duplicate()
		for g: ClubLife.Group in life._groups:
			for cc in g.carts:
				if not carts.has(cc):
					carts.append(cc)
		for cc: ClubLife.Walker in carts:
			if not is_instance_valid(cc.node) or not cc.node.visible:
				continue
			var p := cc.node.global_position
			var key := cc.node.get_instance_id()
			if last.has(key):
				var moved := (last[key] as Vector3).distance_to(p)
				# (driven along a way with no one in it, then or the moment before: one pulling up with
				# its riders, who then get out and it's squared up in its spot, isn't)
				if moved > 0.05 and moved < 3.0 and int(routed.get(key, 0)) > 0 and not manned.get(key, false) and not life._manned(cc):
					unmanned += 1
					print("  unmanned: %.2f m at %s" % [moved, str(Vector2(p.x, p.z).round())])
			routed[key] = cc.path.size()
			manned[key] = life._manned(cc)
			last[key] = p
			var l := house.global_transform.affine_inverse() * p
			for id in boxes:
				if id != "valet" and (boxes[id]["rect"] as Rect2).has_point(Vector2(l.x, l.z)):
					inside += 1
	print("L%d, %d cart boy(s): %s; front man idle by the line %d of %d" % [level, hired, str(did), front_home, front_idle])
	check(unmanned == 0, "L%d, %d boys: a cart drove itself (%d moments)" % [level, hired, unmanned])
	check(inside == 0, "L%d, %d boys: a cart went into the clubhouse (%d moments)" % [level, hired, inside])
	var total := {}
	for k in range(boys.size()):
		check(life._runs_bags(boys[k]) and life._cart_duty(boys[k]) == "all", "An attendant is restricted to a fixed role")
		for kind in did.get(k, {}): total[kind] = true
	check(total.has("run"), "Attendants never delivered a flight's bags and carts")
	check(total.has("stock"), "Attendants never rearranged or replenished the cart line")
	check(total.has("wash"), "Attendants never cleaned after the higher priorities")
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
