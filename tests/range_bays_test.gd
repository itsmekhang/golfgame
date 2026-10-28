extends SceneTree
## The driving range's bays: as many practise at once as it has bays -- the ground's first, then
## up the stair to its lounge's (levels 3 and 4) -- each golfer on their own mat's floor (never
## lifted to the lounge's over the bays below it), their bag stood off every mat, every shot's
## ball left lying out on the range till they're done, then down and home.
## Run: godot --headless --path . --script tests/range_bays_test.gd

var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_range_bays_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [3, 4]:
		scenario(level)
	print("RANGE BAYS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func scenario(level: int) -> void:
	var c := PaintedCourse.create("Range bays", Vector2i(400, 400))
	c.holes.append({"tee": Vector2(60, 20), "pin": Vector2(60, -70), "par": 3, "bends": [], "curve": false})
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 130), "rot": 0.0}, "driving_range": {"pos": Vector2(40, 115), "rot": 0.0}}
	b.built = {"clubhouse": 1, "parking_lot": 1, "driving_range": level}
	b.rooms = {"pro_shop": 1}
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
	check(upper.size() == (8 if level == 3 else 15), "Level %d's lounge bays: %d" % [level, upper.size()])
	check((rig.get("range_stairs", []) as Array).size() == (rig.get("range_stair_tops", []) as Array).size() and not (rig.get("range_stairs", []) as Array).is_empty(), "Level %d's stairs up aren't marked" % level)
	check(rig["nav"].has("upper"), "Level %d's lounge has no walking grid" % level)
	# every ground bay taken: the next ones in go up to the lounge
	var held := ClubLife.Group.new()
	for i in range(ground.size()):
		var holder := ClubLife.Walker.new()
		holder.node = Node3D.new()
		life.add_child(holder.node)
		holder.data["range_bay"] = i
		held.golfers.append(holder)
	life._groups.append(held)
	var r = life._new_arrival(-1, "range")
	life._groups.append(r)
	var inv := fac.global_transform.affine_inverse()
	var floor_up: float = (upper[0] as Transform3D).origin.y
	var up_hits := 0  # strokes played from the lounge, on its floor
	var off_floor := 0  # moments someone hitting stood off their mat's floor
	var on_mat := 0
	var most_balls := 0
	var phases := {}
	for step in range(16000):
		if not life._groups.has(r):
			break
		life._step_group(r, 0.25)
		phases[r.phase] = true
		for w in r.golfers:
			most_balls = maxi(most_balls, (w.data.get("range_balls", []) as Array).size())
		if r.phase == "range_practice":
			for w in r.golfers:
				if not w.data.has("range_ball"):
					continue
				var feet: Vector3 = inv * w.node.global_position
				var ball: Vector3 = inv * (w.data["range_ball"] as Vector3)
				if w.data.get("range_step", "") == "hit" and absf(feet.y - (ball.y - 0.125)) > 0.25:
					off_floor += 1  # (hitting: on their mat's floor)
				if ball.y > floor_up - 0.5 and w.anim != null and w.anim.current_animation == "swing":
					up_hits += 1
				var stand = w.data.get("bag_down")
				if stand != null and is_instance_valid(stand):
					var sp: Vector3 = inv * (stand as Node3D).global_position
					for bay: Transform3D in ground + upper:
						if absf(sp.x - bay.origin.x) < 0.8 and absf(sp.z - bay.origin.z) < 0.8 and absf(sp.y - bay.origin.y) < 1.0:
							on_mat += 1
	check(phases.has("range_practice") and phases.has("leave"), "Level %d: the lounge golfers didn't practise and go home: %s" % [level, str(phases.keys())])
	check(up_hits > 0, "Level %d: nobody hit from the lounge with the ground's bays full" % level)
	check(off_floor == 0, "Level %d: a golfer stood off their mat's floor while hitting (%d moments)" % [level, off_floor])
	check(on_mat == 0, "Level %d: a bag stood on a mat (%d moments)" % [level, on_mat])
	check(most_balls == ClubLife.RANGE_BALLS, "Level %d: a golfer's range balls didn't all stay out till they were done (%d at most)" % [level, most_balls])
	life._groups.erase(held)
	life.clear()
	life.free()
	built.free()
