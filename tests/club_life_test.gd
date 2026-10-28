extends SceneTree
## Course Manager's people: hired staff show up at their workplaces (room posts, the cart
## barn, out on the course, the marshal in a cart), golfers come while the club is open, walk
## with bags slung or ride in carts, take their shots and move on hole to hole, and leave.
## Run: godot --headless --path . --script tests/club_life_test.gd

const DIR := "user://_club_life_test/"
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://club_life_test_unused.json")
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)


func run() -> void:
	await process_frame
	var gs: GameState = GameState.current
	gs.autosave = false
	gs.new_game()
	gs.unlocked.append(str(gs.manager_status()["store_id"]))
	gs.cash = 1000000
	gs.buy_course()
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "life.course.json"
	var c := PaintedCourse.starter("Life Test")
	var h0: Dictionary = c.holes[0]
	for k in range(2):
		c.holes.append({"tee": h0["pin"] + Vector2(30 + 40 * k, -20), "pin": h0["tee"] + Vector2(50 + 40 * k, 40), "par": 0, "bends": [], "curve": false})
	c.save(path)
	gs.set_business_course(path)
	gs.place_facility("clubhouse", Vector2(-200, 200), 0.0)
	gs.place_facility("cart_barn", Vector2(-100, 200), 0.0)
	gs.build_facility("clubhouse")
	gs.build_facility("clubhouse")
	gs.build_facility("cart_barn")
	gs.build_room("pro_shop")
	gs.build_room("restaurant")
	for role in ["shop_clerk", "chef", "greenskeeper", "marshal", "cart_attendant", "trainer"]:
		gs.hire_staff(role)
	gs.set_course_open(true)
	var b := gs.business
	check(b.rates()["open"], "Club open")
	var items: Array = []
	for t in b.placements:
		items.append({"type": t, "pos": b.placements[t]["pos"], "rot": b.placements[t]["rot"], "level": b.level(t), "name": "Life", "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(p: Vector2) -> float: return c.height_at(p), false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.course = c
	life.facilities = built
	life.business = b
	life.refresh()
	finished_golfers_check(life)
	# clerk, chef, greenskeeper, attendant, and the marshal's cart; no trainer (no spa yet)
	check(life.staff_count() == 5, "Staff at their workplaces (%d)" % life.staff_count())
	var house := built.get_node("clubhouse") as Node3D
	var shop: Rect2 = FacilityBuilder.rig(house)["boxes"]["pro_shop"]["rect"]
	var clerk_in_shop := false
	for w in life._staff:
		var local := house.global_transform.affine_inverse() * (w as ClubLife.Walker).node.global_position
		if shop.grow(0.5).has_point(Vector2(local.x, local.z)):
			clerk_in_shop = true
	check(clerk_in_shop, "The clerk is in the pro shop")
	# golfers: one group on foot (bags slung), one riding
	var walkers: ClubLife.Group = life._new_group(0, false, 0)
	var riders: ClubLife.Group = life._new_group(1, false, 1)
	check(walkers != null and riders != null and riders.carts.size() >= 1, "A group on foot and one in carts")
	var slung := 0
	for w in walkers.golfers:
		for attachment in (w as ClubLife.Walker).node.find_children("*", "BoneAttachment3D", true, false):
			if attachment.name != "HeldGolfClub": slung += 1
	check(slung == walkers.golfers.size(), "Walking golfers carry their bags")
	check((riders.golfers[0] as ClubLife.Walker).riding and (riders.carts[0] as ClubLife.Walker).node.get_child_count() >= 3, "Riders sit in the cart, bags in the back")
	var swung := false
	var putted := false
	var start_stop := walkers.stop
	var start_hole := walkers.hole
	var moved_on := false
	var crowded_tee := 0  # moments a flight had two golfers on its tee at once
	var teed := false
	var bag_at := {}  # walker -> where their bag stands, while it's set down
	var opened := {}  # "flight:hole" -> its opening tee shot seen
	var contested := 0  # opening tee shots with another flight still on the hole
	var early := 0  # ... taken while someone ahead is still inside shot range
	var shared_tee := 0  # moments two flights stood on one tee box
	var pickups := 0  # bags picked up standing at them
	var far_pickups := 0  # ... and from further off (the bag would jump to them)
	for i in range(6000):  # ten minutes in 0.1 s steps
		life._process(0.1)
		for g in life._groups:
			if g.stop == 0 and not g.stops.is_empty() and g.phase in ["step_up", "play", "step_off"]:
				teed = true
				var tee: Vector2 = g.stops[0]
				var on_tee := 0
				for w in g.golfers:
					var p := (w as ClubLife.Walker).node.global_position
					if not (w as ClubLife.Walker).riding and Vector2(p.x, p.z).distance_to(tee) < 2.5:
						on_tee += 1
				if on_tee > 1:
					crowded_tee += 1
			for w in g.golfers:
				var a := (w as ClubLife.Walker).anim
				if a != null and a.current_animation == "swing":
					swung = true
				if a != null and a.current_animation == "putt":
					putted = true
		if life._groups.has(walkers) and (walkers.hole != start_hole or walkers.stop != start_stop):
			moved_on = true
		for g in life._groups:
			var played := 0
			for s in g.strokes:
				played += s
			var key := "%d:%d" % [g.get_instance_id(), g.hole]
			if g.stop == 0 and played == 1 and not opened.has(key):
				opened[key] = true  # this flight's opening tee shot on the hole
				for other in life._groups:
					if other != g and other.hole == g.hole and other.hole_reserved:
						contested += 1
						if other.stop > g.stop and life._in_reach(g, other, g.stops[0], life._target(g)):
							early += 1
		for h in range(c.holes.size()):
			var tee: Vector2 = c.holes[h]["tee"]
			var on_box := 0
			for g in life._groups:
				for w in g.golfers:
					var p := (w as ClubLife.Walker).node.global_position
					if not (w as ClubLife.Walker).riding and (w as ClubLife.Walker).node.visible and Vector2(p.x, p.z).distance_to(tee) < 8.0:
						on_box += 1
						break
			if on_box > 1:
				shared_tee += 1
		if life._groups.has(walkers):
			for w in walkers.golfers:
				var wk := w as ClubLife.Walker
				var stand: Variant = wk.data.get("bag_down")
				if stand != null and is_instance_valid(stand):
					bag_at[wk] = (stand as Node3D).global_position
				elif bag_at.has(wk):
					var at: Vector3 = bag_at[wk]
					if Vector2(wk.node.global_position.x, wk.node.global_position.z).distance_to(Vector2(at.x, at.z)) > 1.6:
						far_pickups += 1
					else:
						pickups += 1
					bag_at.erase(wk)
	check(swung and putted, "Golfers swing and putt (%s, %s)" % [swung, putted])
	check(teed and crowded_tee == 0, "One golfer of a flight on the tee at a time (%d crowded moments)" % crowded_tee)
	check(moved_on, "Groups move on down the holes")
	print("TEE: %d opening tee shots with a flight ahead, %d early, %d moments of a shared tee box" % [contested, early, shared_tee])
	check(early == 0, "A flight teed off while the one ahead was still inside shot range (%d)" % early)
	check(shared_tee == 0, "Two flights on one tee box (%d moments)" % shared_tee)
	check(pickups > 0 and far_pickups == 0, "Walkers go back to their bags to pick them up (%d at the bag, %d from afar)" % [pickups, far_pickups])
	check(not life._groups.has(walkers) or walkers.hole > start_hole, "Groups play on and leave")
	check(life._groups.size() <= ClubLife.MAX_GROUPS, "Never more than the cap on the course")
	# marshals keep play moving: golfers walk and drive a tenth quicker for each one hired
	var slow: float = life._marshal_pace()
	b.staff["marshal"] = int(b.staff.get("marshal", 0)) + 1
	check(is_equal_approx(life._marshal_pace(), slow + 0.1), "Another marshal didn't quicken play: %.2f -> %.2f" % [slow, life._marshal_pace()])
	b.staff["marshal"] = int(b.staff["marshal"]) - 1
	life.queue_free()
	built.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("CLUB LIFE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func finished_golfers_check(life: ClubLife) -> void:
	var g := ClubLife.Group.new()
	var pin: Vector2 = life.course.holes[0]["pin"]
	g.stops = [life.course.holes[0]["tee"], pin]
	g.stop = 1
	g.ball_positions = [pin, pin, pin + Vector2(0.65, 0)]
	g.holed = [true, true, false]
	g.strokes = [4, 5, 3]
	for k in range(3):
		var w := ClubLife.Walker.new()
		w.node = Node3D.new()
		life.add_child(w.node)
		w.node.global_position = Vector3(pin.x + k * 2, 0, pin.y + 4)
		g.golfers.append(w)
	var first := life._ball_spot(g, 0)
	var second := life._ball_spot(g, 1)
	check(first.distance_to(pin) > 2.0 and second.distance_to(pin) > 2.0, "Finished golfers crowd the cup")
	check(first.distance_to(second) > 1.0, "Finished golfers have the same waiting spot")
	life._ready_up(g)
	check(g.turn == 2 and g.phase == "ready", "Holed-out golfers were given another turn")
	check(g.strokes == [4, 5, 3], "Completed scores changed while waiting")
	for w: ClubLife.Walker in g.golfers:
		w.node.queue_free()
