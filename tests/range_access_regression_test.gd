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
	for level in range(1, 5):
		await scenario(level)
	print("RANGE ACCESS REGRESSION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func scenario(level: int) -> void:
	var c := PaintedCourse.create("Range access", Vector2i(400, 400))
	c.holes.append({"tee": Vector2(60, 20), "pin": Vector2(60, -70), "par": 3, "bends": [], "curve": false})
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.course_path = "user://_range_access_course.json"
	for i in range(2): c.holes.append(c.holes[0].duplicate(true))
	c.save(b.course_path)
	b.refresh_course()
	b.built = {"clubhouse": level, "driving_range": level, "parking_lot": level}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "range_attendant": 1}
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 130), "rot": 0.0}, "driving_range": {"pos": Vector2(40, 115), "rot": 0.0}}
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
	var ground: Array = rig.get("range_bays", [])
	var upper: Array = rig.get("range_bays_up", [])
	check(ground.size() == [10, 12, 14, 15][level-1], "Wrong ground bay count at level %d" % level)
	check(upper.size() == [0, 0, 8, 15][level-1], "Wrong upper bay count at level %d" % level)
	var capacity := ground.size()+upper.size()
	# One vacancy admits one member of a four-person course party; never needs four vacancies.
	var held := ClubLife.Group.new()
	for i in range(capacity-1):
		var w := ClubLife.Walker.new()
		w.node = Node3D.new()
		life.add_child(w.node)
		w.data["range_bay"] = i
		held.golfers.append(w)
	life._groups.append(held)
	var party := life._new_group(0, false, 0, 4)
	check(life._start_range(party), "Partial party rejected")
	check(party.golfers.filter(func(w): return w.data.has("range_bay")).size() == 1, "One vacancy must admit exactly one player")
	check(party.golfers.filter(func(w): return w.data.get("range_step", "") == "wait").size() == 3, "Remaining golfers must wait individually")
	held.golfers[0].data.erase("range_bay")
	life._start_range(party)
	check(party.golfers.filter(func(w): return w.data.has("range_bay")).size() == 2, "New vacancy wasn't allocated individually")
	var first: ClubLife.Walker = party.golfers[0]
	var released: int = first.data["range_bay"]
	first.path.clear()
	first.data["range_step"] = "out"
	life._range_golfers(party, 0)
	check(not first.data.has("range_bay"), "Completed player's bay held until whole flight finished")
	life._start_range(party)
	check(party.golfers[2].data.get("range_bay", -1) == released, "Released bay not reused")
	life._groups.erase(held)
	life._free_group(held)
	life._groups.erase(party)
	life._free_group(party)
	# Range-only customers are independent, not course flights.
	var visitor := life._new_arrival(0, "range")
	check(visitor.golfers.size() == 1, "Range-only customer still belongs to a flight")
	var phases := {}
	for tick in range(12000):
		if not life._groups.has(visitor): break
		life._step_group(visitor, 0.25)
		phases[visitor.phase] = true
		if visitor.phase == "range_practice": break
	check(phases.has("range_practice"), "Range visitor failed to reach dispenser")
	# filling the bucket square in front of the machine's chute, not off to its side (user)
	var off := -1.0
	for tick in range(4000):
		if not life._groups.has(visitor) or visitor.golfers[0].data.has("bucket"): break
		life._step_group(visitor, 0.25)
		var w: ClubLife.Walker = visitor.golfers[0]
		if str(w.data.get("range_step", "")) == "dispenser" and w.data.has("range_next"):
			var chute := fac.global_transform * (w.data["range_chute"] as Transform3D).origin
			off = maxf(off, Vector2(w.node.global_position.x - chute.x, w.node.global_position.z - chute.z).length())
	check(off >= 0.0 and off < 0.3, "Range visitor filled the bucket %.2f m off the chute" % off)
	check(not phases.has("check_in") and not phases.has("bag_pickup"), "Range visitor wrongly checked in")
	# The old course-flight cap and single range-party cap must not suppress customers
	# while the range still has vacancies.
	var course_groups: Array = []
	for i in range(ClubLife.MAX_GROUPS):
		var dummy := ClubLife.Group.new()
		dummy.range_visit = false
		life._groups.append(dummy)
		course_groups.append(dummy)
	var before := life._groups.size()
	life._top_up_golfers()
	check(life._groups.size() == before+1, "Course flight cap still suppresses range customers")
	check(life._groups[-1].visit == "range" and life._groups[-1].golfers.size() == 1, "Range demand did not create an independent customer")
	for dummy in course_groups: life._groups.erase(dummy)
	# Left, right and far-net interception, including rotated facilities and upper-floor shots.
	if level == 4:
		for angle in [0.0, 0.71, -1.2]:
			fac.rotation.y = angle
			for height in [0.7, 4.7]:
				for end: Vector3 in [Vector3(-100, 0, -80), Vector3(100, 0, -80), Vector3(0, 0, -320), Vector3(-80, 0, -250)]:
					var from := fac.global_transform * Vector3(0, height, -11)
					var to := fac.global_transform * end
					to.y = 0.045
					var contact := life._range_net_contact(from, to, 20)
					check(not contact.is_empty(), "Missed net contact")
					for i in range(101):
						var p := fac.global_transform.affine_inverse() * life._range_ball_at(from, to, 20, i/100.0, contact)
						var edge := 34.5+7.5*clampf((-p.z-12.0)/33.0, 0, 1)
						check(absf(p.x) <= edge+0.03 and p.z >= -264.46, "Ball escaped enclosure: %s" % p)
		fac.rotation.y = 0
		var clear_from := fac.global_transform * Vector3(0, 0.7, -11)
		check(life._range_net_contact(clear_from, clear_from+Vector3(0, 0, -130), 20).is_empty(), "Straight shot incorrectly intercepted")
	print("RANGE ACCESS level ", level, ": ", ground.size(), "+", upper.size(), " bays; individual allocation and front pickup checked")
	life.clear()
	life.free()
	built.free()
	await process_frame
