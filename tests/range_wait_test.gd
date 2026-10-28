extends SceneTree
## Nobody waits by the driving range while one of its bays is free, nobody holds a bay they're
## not on their way to or at, and nobody on foot crosses in front of the bays (the hitting side):
## flights and range visitors coming and going at levels 3 and 4. Those in for the range alone
## never go into the clubhouse; everyone fills a bucket at the ball dispenser, carries it over
## and sets it down by their mat to hit from.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_range_wait_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [1, 2, 3, 4]:
		await scenario(level)
	print("RANGE WAIT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func scenario(level: int) -> void:
	var c := PaintedCourse.create("Range wait", Vector2i(400, 400))
	# (the hole off to the side of the range's field)
	c.holes.append({"tee": Vector2(150, 20), "pin": Vector2(150, -70), "par": 3, "bends": [], "curve": false})
	c.paint(PaintedCourse.Surface.GREEN, Vector2(150, -70), 9, 1, 1)
	c.paint(PaintedCourse.Surface.TEE, Vector2(150, 20), 5, 1, 1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}, "driving_range": {"pos": Vector2(40, 115), "rot": 0.0}}
	b.built = {"clubhouse": 1, "parking_lot": 2, "driving_range": level}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "range_attendant": 1}
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
	var fac := built.get_node("driving_range") as Node3D
	var rig := FacilityBuilder.rig(fac)
	var total: int = (rig.get("range_bays", []) as Array).size() + (rig.get("range_bays_up", []) as Array).size()
	var line_z := INF  # the bays' front (the range's XZ): the hitting side is beyond it (-Z)
	for bay: Transform3D in rig.get("range_bays", []):
		line_z = minf(line_z, bay.origin.z)
	var inv := fac.global_transform.affine_inverse()
	var waited := 0.0  # seconds someone waited with a bay free
	var worst_wait := 0.0
	var stuck := {}  # walker -> seconds holding a bay, blocked
	var worst_stuck := 0.0
	var floating := {}
	var fence_crossings := {}
	var in_front := {}  # who walked out in front of the bays (on foot, on the ground)
	var practised := 0
	var spawned := 0
	var clubhouse_visits := 0  # range-only visitors seen checking in
	var carried := {}  # who walked with a bucket in hand
	var no_bucket := 0  # moments someone was hitting without their bucket set down by them
	for step in range(9600):
		life._spawn_wait = 1e9
		if step % 120 == 0 and spawned < 9:
			var g := life._new_arrival(0, "range" if spawned % 3 == 2 else "")
			if g != null:
				g.range_visit = true
				g.short_visit = false
				spawned += 1
		life._process(0.25)
		var held := 0
		var waiting := 0
		for g: ClubLife.Group in life._groups:
			for w: ClubLife.Walker in g.golfers:
				if w.data.has("range_bay"):
					held += 1
					if w.data.get("blocked", false) and w.path.is_empty():
						stuck[w] = float(stuck.get(w, 0.0)) + 0.25
						worst_stuck = maxf(worst_stuck, stuck[w])
					else:
						stuck.erase(w)
				if w.data.get("range_step", "") == "wait":
					waiting += 1
				if w.data.get("range_step", "") == "hit":
					practised = maxi(practised, 1)
					var down: Variant = w.data.get("bucket_down")
					if down == null or not is_instance_valid(down) or (down as Node3D).global_position.distance_to(w.node.global_position) > 2.5:
						no_bucket += 1
				if w.data.has("bucket") and w.anim != null and w.anim.current_animation == "carry":
					carried[w] = true
			if g.visit == "range" and g.phase in ["shop_front", "lobby", "shop_walk", "check_in", "bag_pickup"]:
				clubhouse_visits += 1
		var people: Array = []
		for g: ClubLife.Group in life._groups:
			people.append_array(g.golfers)
		people.append_array(life._staff.filter(func(p: ClubLife.Walker) -> bool: return not p.data.get("vehicle", false) and not p.riding))
		for w: ClubLife.Walker in people:
			if not w.node.visible or w.riding:
				continue
			var l: Vector3 = inv * w.node.global_position
			if level == 1 and not w.path.is_empty() and absf(l.x) < 34 and absf(l.z) < 18:
				if l.y > 0.3: floating[w] = true
				if absf(absf(l.x)-26.0) < 0.3 and l.z < -1.8 and l.z > -12.7: fence_crossings[w] = true
			if l.y < 1.0 and l.z < line_z - 1.2 and l.z > line_z - ClubLife.RANGE_FIELD_WALK and absf(l.x) < FacilityBuilder.footprint("driving_range").x * 0.5:
				if not in_front.has(w) and OS.get_environment("RANGE_TRACE") != "":
					var phase := ""
					for g: ClubLife.Group in life._groups:
						if g.golfers.has(w):
							phase = g.phase
					var end: Vector3 = inv * (w.path[w.path.size() - 1] as Vector3) if not w.path.is_empty() else l
					print("  in front: %s %s step %s at %s heading %s, %d points, region %s" % [phase if phase != "" else "staff " + str(w.data.get("role", "")), str(w.data.get("pick", "")), str(w.data.get("range_step", "")), str(Vector2(l.x, l.z).round()), str(Vector2(end.x, end.z).round()), w.path.size(), str(w.data.get("walk_region", {}).get("nav", {}).get("cell", "-"))])
				in_front[w] = true
		if waiting > 0 and held < total:
			waited += 0.25
			worst_wait = maxf(worst_wait, waited)
		else:
			waited = 0.0
	print("L%d: %d flights in, %d bays; longest wait with a bay free %.0f s, longest held while stuck %.0f s, %d walked in front, %d carried a bucket" % [level, spawned, total, worst_wait, worst_stuck, in_front.size(), carried.size()])
	check(floating.is_empty(), "Ground-floor range walkers floated")
	check(fence_crossings.is_empty(), "Range walkers crossed a side fence")
	check(practised > 0, "L%d: nobody practised" % level)
	check(clubhouse_visits == 0, "L%d: someone in for the range alone went in to check in (%d moments)" % [level, clubhouse_visits])
	check(carried.size() >= 3, "L%d: only %d golfers carried a bucket over from the dispenser" % [level, carried.size()])
	check(no_bucket == 0, "L%d: someone hit without their bucket by them (%d moments)" % [level, no_bucket])
	check(worst_wait <= 4.0, "L%d: someone waited %.0f s by the range with a bay free" % [level, worst_wait])
	check(worst_stuck <= 25.0, "L%d: someone held a bay %.0f s while stuck on the way to it" % [level, worst_stuck])
	check(in_front.is_empty(), "L%d: %d people walked out in front of the bays" % [level, in_front.size()])
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
