extends SceneTree
## The club's other customers (Grand clubhouse): golfers in off the course up on the bar's stools
## or in the lounge's chairs, bags stood by them, then out of the front door to their cars; a gym
## member in by the front door onto a machine, then home; people in for the range alone, home
## after it without going out on the course; the bar TVs playing the user's clip and video; the
## golf pros at the simulator's screen, the office desk and the sofa; and a golfer swinging along
## the line of the shot, whatever they were last watching.
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
	var c := PaintedCourse.create("Guest test", Vector2i(400, 400))
	for points in [[Vector2(60, 20), Vector2(60, -70)], [Vector2(-20, -30), Vector2(-20, -120)], [Vector2(-110, -55), Vector2(-110, -145)]]:
		c.holes.append({"tee": points[0], "pin": points[1], "par": 3, "bends": [], "curve": false})
		c.paint(PaintedCourse.Surface.GREEN, points[1], 9, 1, 1)
		c.paint(PaintedCourse.Surface.TEE, points[0], 5, 1, 1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 130), "rot": 0.0}, "cart_barn": {"pos": Vector2(-15, 130), "rot": 0.0}, "driving_range": {"pos": Vector2(100, 115), "rot": 0.0}}
	b.built = {"clubhouse": 4, "cart_barn": 4, "parking_lot": 4, "driving_range": 4}
	b.rooms = {"pro_shop": 1, "restaurant": 1, "lounge": 2, "spa_fitness": 1, "simulator": 1, "office": 1}
	b.staff = {"shop_clerk": 1, "cart_attendant": 1, "range_attendant": 1, "chef": 1, "trainer": 1, "golf_pro": 3}
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
	var spots: Dictionary = FacilityBuilder.rig(house)["spots"]
	var count := func(room: String, prefix: String) -> int:
		return (spots.get(room, []) as Array).filter(func(sp: Dictionary) -> bool: return str(sp["role"]).begins_with(prefix)).size()
	check(count.call("restaurant", "guest_bar") >= 8, "No stools for golfers at the bar: %d" % count.call("restaurant", "guest_bar"))
	check(count.call("lounge", "guest_seat") >= 3, "No seats for golfers in the lounge: %d" % count.call("lounge", "guest_seat"))
	check(count.call("spa_fitness", "guest_gym") >= 6, "No machines for members in the gym: %d" % count.call("spa_fitness", "guest_gym"))
	check(house.find_children("TvClip", "MeshInstance3D", true, false).size() == 1, "The bar TV isn't playing the clip")
	check(house.find_children("TvVideo", "MeshInstance3D", true, false).size() == 1, "The other bar TV isn't playing the video")
	# the golf pros: one at the simulator's screen, one at the office desk, one on the sofa, sat
	var pro_spots := {}
	for room in ["simulator", "office"]:
		for sp: Dictionary in spots.get(room, []):
			if str(sp["role"]).begins_with("golf_pro"):
				pro_spots[str(sp["role"])] = house.global_transform * (sp["xf"] as Transform3D).origin
	check(pro_spots.has("golf_pro") and pro_spots.has("golf_pro_desk") and pro_spots.has("golf_pro_sit"), "The pros' places are missing: %s" % str(pro_spots.keys()))
	var placed := {}
	for p in life._staff:
		if str(p.data.get("role", "")) != "golf_pro":
			continue
		for job in pro_spots:
			if p.node.global_position.distance_to(pro_spots[job]) < 0.7:
				placed[job] = p.anim.current_animation if p.anim != null else ""
	check(placed.size() == 3, "The three pros aren't each at their place: %s" % str(placed))
	# in the order they were hired: the office desk, the bay's screen, the sofa (user)
	var order: Array = []
	for p in life._staff:
		if str(p.data.get("role", "")) == "golf_pro":
			for job in pro_spots:
				if p.node.global_position.distance_to(pro_spots[job]) < 0.7:
					order.append(job)
	check(order == ["golf_pro_desk", "golf_pro", "golf_pro_sit"], "The pros aren't posted in hiring order: %s" % str(order))
	check(placed.get("golf_pro_desk", "") == "type_sit" and placed.get("golf_pro_sit", "") == "sit", "The pros at the desk and on the sofa aren't sitting: %s" % str(placed))
	check(b.room_working("restaurant") and b.room_working("lounge") and b.room_working("spa_fitness"), "The rooms aren't open")

	# the 19th hole: a flight in off the course, up the back walk to the bar
	var g := life._new_arrival(0)
	g.car.path.clear()
	g.car.node.global_position = g.parking_path[g.parking_path.size() - 1]
	var back: Vector2 = life._clubhouse_back()
	for k in range(g.golfers.size()):
		var w = g.golfers[k]
		w.node.visible = true
		w.path.clear()
		w.node.global_position = Vector3(back.x + k * 0.8, 0, back.y)
	check(life._to_places(g, "restaurant", ["guest_bar"], true), "The flight couldn't get to the bar")
	var seated_ok := false
	var left_by_front := false
	for step in range(6000):
		if not life._groups.has(g):
			break
		life._step_group(g, 0.25)
		if g.phase == "at_place" and not seated_ok:
			seated_ok = true
			for w in g.golfers:
				var place: Dictionary = w.data.get("place", {})
				var xf: Transform3D = place.get("xf", Transform3D())
				check(w.node.global_position.distance_to(xf.origin) < 0.05, "A golfer isn't on their stool")
				check(w.anim == null or w.anim.current_animation == "sit", "A golfer at the bar isn't sitting: " + str(w.anim.current_animation if w.anim else ""))
				# no clubs in the clubhouse: their bag with the valet, outside
				var stand = w.data.get("bag_down")
				var held_in := false
				if stand != null and is_instance_valid(stand):
					var sl: Vector3 = house.global_transform.affine_inverse() * (stand as Node3D).global_position
					for id in FacilityBuilder.rig(house)["boxes"]:
						held_in = held_in or (id != "valet" and (FacilityBuilder.rig(house)["boxes"][id]["rect"] as Rect2).has_point(Vector2(sl.x, sl.z)))
				check(stand != null and is_instance_valid(stand) and not held_in and not (w.data["bag"] as Node3D).visible, "A golfer at the bar has their bag with them, not with the valet outside")
			check(life._guest_places.size() == g.golfers.size(), "The stools taken aren't kept: %d" % life._guest_places.size())
		if g.phase == "return_parking":
			left_by_front = true
	check(seated_ok, "The flight never sat down at the bar")
	check(left_by_front, "The flight never went out to the car park after the bar")
	# and a pair in the lounge sit together, not across the room from each other
	var pair := life._new_arrival(0)
	while pair.golfers.size() > 2:
		pair.golfers.pop_back().node.queue_free()
	check(life._to_places(pair, "lounge", ["guest_seat"], true), "A pair couldn't sit down in the lounge")
	if pair.golfers.size() == 2:
		var p0: Vector3 = pair.golfers[0].data["place"]["xf"].origin
		var p1: Vector3 = pair.golfers[1].data["place"]["xf"].origin
		check(p0.distance_to(p1) <= 2.6, "The pair sat apart in the lounge: %.1f m" % p0.distance_to(p1))
	life._groups.erase(pair)
	life._free_group(pair)
	check(life._guest_places.is_empty(), "Stools still held after the flight left: %d" % life._guest_places.size())

	# a gym member: by car, in by the front door, onto a machine, then home
	var m := life._new_arrival(-1, "gym")
	check(m != null and m.golfers.size() == 1 and not m.golfers[0].data.has("bag"), "The gym member came wrong (or with a golf bag)")
	var worked := false
	var phases := {}
	for step in range(9000):
		if m == null or not life._groups.has(m):
			break
		life._step_group(m, 0.25)
		phases[m.phase] = true
		if m.phase == "at_place" and not worked:
			worked = true
			var place: Dictionary = m.golfers[0].data.get("place", {})
			check(str(place.get("use", "")).begins_with("guest_gym") and str(place.get("key", "")).begins_with("spa_fitness/"), "The member isn't on a gym machine: " + str(place.get("key", "")))
	check(worked, "The gym member never worked out (phases: %s)" % str(phases.keys()))
	check(not phases.has("shop_walk") and not phases.has("tee_queue") and phases.has("leave"), "The gym member didn't go straight to the gym and home: %s" % str(phases.keys()))

	# in for the range alone: checked in, a bucket hit, home -- never out on the course
	var r := life._new_arrival(-1, "range")
	check(r != null and r.golfers.size() <= 2 and r.range_visit and r.carts.is_empty(), "The range visitor came wrong")
	phases = {}
	var range_inv := (built.get_node("driving_range") as Node3D).global_transform.affine_inverse()
	var on_mat := 0  # moments a bag stood on its golfer's mat (1.5 m square round the ball)
	var bucket := -1  # the fewest balls any of them hit before packing up
	for step in range(12000):
		if r == null or not life._groups.has(r):
			break
		life._step_group(r, 0.25)
		phases[r.phase] = true
		for w in r.golfers:
			var stand = w.data.get("bag_down")
			if r.phase == "range_practice" and stand != null and is_instance_valid(stand):
				var off: Vector3 = range_inv * (stand as Node3D).global_position - range_inv * (w.data["range_ball"] as Vector3)
				if absf(off.x) < 0.85 and absf(off.z) < 0.85:
					on_mat += 1
				for bay: Transform3D in FacilityBuilder.rig(built.get_node("driving_range"))["range_bays"]:  # nor on any other bay's
					var off2: Vector3 = range_inv * (stand as Node3D).global_position - bay.origin
					if absf(off2.x) < 0.8 and absf(off2.z) < 0.8:
						on_mat += 1
			if w.data.get("range_step", "") == "pack" and w.data.has("range_hit"):
				bucket = int(w.data["range_hit"]) if bucket < 0 else mini(bucket, int(w.data["range_hit"]))
	check(phases.has("range_practice") and phases.has("leave") and not phases.has("tee_queue") and not phases.has("play"), "The range visitor didn't practise and go home: %s" % str(phases.keys()))
	check(on_mat == 0, "A range golfer's bag stood on the hitting mat (%d moments)" % on_mat)
	check(bucket == ClubLife.RANGE_BALLS, "Range golfers packed up after %d balls, not %d" % [bucket, ClubLife.RANGE_BALLS])
	# off the walk maps, a route's own height never puts anyone under the ground
	var rise := Vector2(150, 150)
	for i in range(c.height.size()):
		c.height[i] = 2.5  # the course rises 2.5 m round the plots
	check(absf(life._surface_y(rise, 0.0) - c.drawn_height_at(rise)) < 0.01, "Stood under the ground off the walkway: %.2f, the ground %.2f" % [life._surface_y(rise, 0.0), c.drawn_height_at(rise)])
	for i in range(c.height.size()):
		c.height[i] = 0.0
	# a golfer still turned to watch a flight-mate's ball swings along the line of their own shot
	var f := life._new_arrival(0)
	f.car.path.clear()
	var hitter: ClubLife.Walker = f.golfers[0]
	hitter.node.visible = true
	f.turn = 0
	f.stop = 0
	f.ball_positions[0] = Vector2(60, 20)
	hitter.data["watch"] = Vector2(200, 200)  # the last ball they watched, way off to the side
	life._shot(f)
	for i in range(40):
		life._step(hitter, 0.05)
	var aim: Vector2 = (life._target(f) - Vector2(60, 20)).normalized()
	var swing: Vector3 = -hitter.node.global_basis.x  # the swing plays toward local -X
	check(Vector2(swing.x, swing.z).normalized().dot(aim) > 0.99, "The golfer swings off the line: %s, not %s" % [Vector2(swing.x, swing.z).normalized(), aim])
	life._groups.erase(f)
	life._free_group(f)
	print("GUEST VISITS: ", "FAIL" if failed else "PASS")
	life.clear()
	quit(1 if failed else 0)
