extends SceneTree
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
	var level := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 2
	var c := PaintedCourse.create("Visitor test",Vector2i(400,400))
	for points in [[Vector2(60,20),Vector2(60,-70)],[Vector2(-20,-30),Vector2(-20,-120)],[Vector2(-110,-55),Vector2(-110,-145)]]:
		c.holes.append({"tee":points[0],"pin":points[1],"par":3,"bends":[],"curve":false})
		c.paint(PaintedCourse.Surface.GREEN,points[1],9,1,1)
		c.paint(PaintedCourse.Surface.TEE,points[0],5,1,1)
	c.paint(PaintedCourse.Surface.WATER,Vector2(20,-20),10,1,1)
	c.paint(PaintedCourse.Surface.BUNKER,Vector2(75,-35),7,1,1)
	c.paint(PaintedCourse.Surface.WOODS,Vector2(100,-40),9,1,1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse":{"pos":Vector2(-105,50),"rot":0.0},"parking_lot":{"pos":Vector2(-105,130),"rot":0.0},"cart_barn":{"pos":Vector2(-15,130),"rot":0.0},"driving_range":{"pos":Vector2(100,115),"rot":0.0},"short_game":{"pos":Vector2(-20,60),"rot":0.0}}
	b.built = {"clubhouse":level,"cart_barn":level,"parking_lot":level,"driving_range":level,"short_game":level}
	b.rooms = {"pro_shop":1}
	b.staff = {"shop_clerk":1,"cart_attendant":1,"range_attendant":1}
	var items: Array = []
	for type in b.placements:
		items.append({"type":type,"level":b.level(type),"pos":b.placements[type]["pos"],"rot":0.0,"rooms":b.rooms})
	var built := FacilityBuilder.build(items,func(_p:Vector2)->float:return 0.0,false,true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	for p in [c.holes[0]["tee"],c.holes[0]["pin"],Vector2(75,-35),Vector2(20,-20),Vector2(100,-40)]:
		check(life._cart_nav.is_point_solid(life._nav_cell_raw(p)),"Cart exclusion missing at "+str(p))
	check(life._route(Vector2(20,-20),Vector2(-40,0),true).is_empty(),"No unsafe route fallback")
	# people stand on what's there: the back deck at floor height, the walk on the ground
	var house := built.get_node("clubhouse") as Node3D
	var way: Array = FacilityBuilder.rig(house).get("tee_way",[])
	check(way.size() == 4,"The clubhouse has no way out the back")
	var practice := built.get_node("short_game") as Node3D
	check(FacilityBuilder.rig(practice).get("flags",[]).size() >= 5,"The short game area has no flags")
	check(practice.find_children("Flagstick*","",false,false).size() == FacilityBuilder.rig(practice).get("flags",[]).size(),"Flags missing from the cups")
	if way.size() == 4:
		var deck: Vector3 = house.global_transform * (way[0] as Transform3D).origin
		var walk_end: Vector3 = house.global_transform * (way[3] as Transform3D).origin
		check(absf(life._surface_y(Vector2(deck.x,deck.z)) - deck.y) < 0.06,"Deck height wrong: %.2f, not %.2f" % [life._surface_y(Vector2(deck.x,deck.z)), deck.y])
		check(life._surface_y(Vector2(walk_end.x,walk_end.z)) < 0.12,"Walk end raised: %.2f" % life._surface_y(Vector2(walk_end.x,walk_end.z)))
	# across a cart from one side to the other: round its nose or tail, not through it
	var round_cart: Array = ClubLife._round_box(Vector2(-3.0, 0.2), Vector2(3.0, -0.2), ClubLife.CART_HALF)
	check(round_cart.size() == 2 and absf((round_cart[0] as Vector2).y) > ClubLife.CART_HALF.y, "No way round a cart: " + str(round_cart))
	check(ClubLife._round_box(Vector2(3.0, -2.0), Vector2(3.0, 2.0), ClubLife.CART_HALF).is_empty(), "Detour round a cart that isn't in the way")
	# a plot on a slope: graded flat, and the ground round it eases to it gently (no plinth, no pit)
	var slope := PaintedCourse.create("Slope", Vector2i(240, 240))
	for i in range(slope.height.size()):
		slope.height[i] = float(i % slope.size.x) * 0.02  # rising 2 m every 100 m
	# (a planned clubhouse, turned so its staked site's 84 m run up the slope)
	FacilityBuilder.grade(slope, {"clubhouse": {"pos": Vector2(0, 0), "rot": PI * 0.5}})
	var pad: Dictionary = slope.pads[0]
	check(float(pad["blend"]) > PaintedCourse.PAD_BLEND, "The ground round a plot on a slope isn't eased out further: %.1f" % float(pad["blend"]))
	var steepest := 0.0
	for k in range(60):
		var x := 40.0 + k
		steepest = maxf(steepest, absf(slope.height_at(Vector2(x + 0.5, 0)) - slope.height_at(Vector2(x - 0.5, 0))))
	check(steepest < 0.13, "The ground drops off the plot too steeply: %.2f in 1 m" % steepest)
	check(absf((built.get_node("clubhouse") as Node3D).global_position.y + FacilityBuilder.ground_sink("clubhouse")) < 0.001, "The clubhouse isn't set down into its pad")
	# people and carts stand on the ground as it's drawn: flat where it's flat, down in the sand
	check(absf(c.drawn_height_at(Vector2(150, 150))) < 0.001, "Drawn ground off the flat: %.3f" % c.drawn_height_at(Vector2(150, 150)))
	check(c.drawn_height_at(Vector2(75, -35)) < -0.4, "The bunker isn't dug in: %.2f" % c.drawn_height_at(Vector2(75, -35)))
	# a struck ball: up, down short of its spot, a bounce or two, then rolling out to it
	var ball_from := Vector3(150, 0.045, 150)
	var ball_rest := Vector3(250, 0.045, 150)
	check(life._ball_at(ball_from, ball_rest, 16.0, 1.0).distance_to(ball_rest) < 0.01, "The ball doesn't end up where it was played to")
	check(life._ball_at(ball_from, ball_rest, 16.0, 0.3).y > 8.0, "The ball isn't in the air")
	check(life._ball_at(ball_from, ball_rest, 16.0, 0.69).y > 0.3, "The ball doesn't bounce")
	var roll_out: Vector3 = life._ball_at(ball_from, ball_rest, 16.0, 0.92)
	check(absf(roll_out.y - 0.045) < 0.01 and roll_out.x > 235.0 and roll_out.x < 250.0, "The ball doesn't roll out: " + str(roll_out))
	# the lot: every stall knows whether a car's in it. Arriving golfers take free ones only (not a
	# parked car's, not another golfer's, not an accessible space), near the clubhouse, spaced
	# out while it's quiet; the parked cars never take theirs
	var lot := built.get_node("parking_lot") as Node3D
	var lr := FacilityBuilder.rig(lot)
	var lot_stalls: Array = lr["stalls"]
	var ada := FacilityBuilder.ada_stalls(lr)
	check(ada.size() == level, "Parking lot level %d: %d accessible spaces" % [level, ada.size()])
	FacilityBuilder.park(lot, 0.2)
	var claimed: Array = []
	for k in range(3):
		var g := life._new_arrival(1)
		check(g != null and g.parking_stall >= 0, "An arriving golfer found no space in a lot a fifth full")
		if g == null:
			continue
		check(not (lr["parked"] as Array).has(g.parking_stall) and not ada.has(g.parking_stall) and not claimed.has(g.parking_stall), "A golfer's car took a space that wasn't free: %d" % g.parking_stall)
		check((lr["taken"] as Dictionary).has(g.parking_stall), "A golfer's space isn't marked taken")
		var end: Vector3 = g.parking_path[g.parking_path.size() - 1]
		var bay: Vector3 = lot.global_transform * (lot_stalls[g.parking_stall] as Transform3D).origin
		check(Vector2(end.x - bay.x, end.z - bay.z).length() < 0.05, "A golfer's car isn't driven into its space")
		claimed.append(g.parking_stall)
	var side_by_side := 0
	for i: int in claimed:
		for j in range(lot_stalls.size()):
			var mine: Transform3D = lot_stalls[i]
			var next: Transform3D = lot_stalls[j]
			if j != i and not ada.has(j) and not FacilityBuilder.stall_free(lr, j) and mine.origin.distance_to(next.origin) < 3.2 and mine.basis.z.dot(next.basis.z) > 0.9:
				side_by_side += 1
	check(side_by_side == 0, "Golfers parked beside other cars in a quiet lot: %d" % side_by_side)
	FacilityBuilder.park(lot, 0.6)
	for i: int in lr["parked"]:
		check(not claimed.has(i) and not ada.has(i), "A parked car was put in a golfer's or an accessible space: %d" % i)
	for g in life._groups.duplicate():
		life._free_group(g)
		life._groups.erase(g)
	life._mark_stalls()
	check((lr["taken"] as Dictionary).is_empty(), "Spaces still marked taken after the golfers left")
	FacilityBuilder.park(lot, 0.0)
	# the front door: the house's door on its front (fountain) side, in line with the drive
	var front_door := Vector3.INF
	for d: Transform3D in FacilityBuilder.rig(house).get("doors",[]):
		if absf(d.origin.x) < 1.5 and (front_door == Vector3.INF or d.origin.z < front_door.z):
			front_door = d.origin
	check(front_door != Vector3.INF and front_door.z < (way[0] as Transform3D).origin.z,"The clubhouse has no front door")
	var barn := built.get_node("cart_barn") as Node3D
	check(FacilityBuilder.rig(barn).get("cart_pick",[]).size() >= 3,"The cart barn has no return row")
	check(life._line_slots().size() >= 6 and not life._line.has(null),"No full line of carts behind the clubhouse")
	life._spawn_wait = 1e9
	for visit in ["","range","short"]:
		var range_first: bool = visit == "range"
		var g := life._new_arrival(1)
		g.range_visit = range_first
		g.short_visit = visit == "short"
		var phases := {}
		var previous := ""
		var safe := true
		var through := {}  # samples of someone on foot inside a parked cart of theirs, by phase
		var clubs_in := 0  # moments someone stood in the clubhouse with their bag on (the valet has it)
		var boxes: Dictionary = FacilityBuilder.rig(house)["boxes"]
		var by_front := INF  # nearest anyone came to the front door on the way in to check in
		var by_back := INF  # ... and to the garden door
		var bags_from_car := false
		var bags_loaded := false
		var picked_at := ""  # where the flight got its carts: off the line, or from the barn
		var stacked := 0  # moments two of the flight's balls lay one on top of the other
		var took := 0
		var brought: Array = []  # the carts the cart boy brought round (back at the barn after)
		var stock_before: int = life._stock.size()
		var phase_step := 0
		for step in range(18000):
			if not life._groups.has(g):
				break
			if g.phase != previous:
				phase_step = step
				previous = g.phase
				print("VISITOR ",visit," ",step," ",g.phase," hole ",g.hole," stop ",g.stop)
				phases[g.phase] = true
			if step - phase_step > 2500:
				if OS.get_environment("STUCK_TRACE") != "":
					print("  sit_tight %s ahead %s stop %d groups %s" % [g.sit_tight, life._flight_ahead(g), g.stop, str(life._groups.map(func(o): return "%s/h%d/%s" % [o.phase, o.hole, o.visit]))])
					for w in g.golfers:
						print("  golfer riding %s path %d blocked %s move %s parent %s" % [w.riding, w.path.size(), w.data.get("blocked", false), w.data.has("cart_move"), w.node.get_parent().name])
					for cart in g.carts:
						print("  cart path %d blocked %s target %s yield %s" % [cart.path.size(), cart.data.get("blocked", false), cart.data.get("outdoor_target", "-"), cart.data.get("yield", 0)])
				break
			life._process(.25)  # Include attendant boarding, driving, unloading and restocking.
			var rolling: int = g.flight.get("golfer", -1)  # the one in the air (or rolling) can pass over another
			for i in range(g.balls.size()):
				for j in range(i + 1, g.balls.size()):
					if i != rolling and j != rolling and g.balls[i].visible and g.balls[j].visible and (g.balls[i] as Node3D).global_position.distance_to((g.balls[j] as Node3D).global_position) < 0.12:
						stacked += 1
			if g.phase in ["shop_front","shop_walk"]:
				for w in g.golfers:
					var l: Vector3 = house.global_transform.affine_inverse() * w.node.global_position
					by_front = minf(by_front, Vector2(l.x - front_door.x, l.z - front_door.z).length())
					if way.size() == 4 and g.phase == "shop_walk":  # inside: in from the front, never round the back
						var back_wall: float = (way[0] as Transform3D).origin.z - 0.7
						by_back = minf(by_back, back_wall - l.z)
			if g.phase == "parking_walk" and not bags_from_car:
				bags_from_car = g.golfers.all(func(w: ClubLife.Walker) -> bool: return w.data.has("bag"))
			if g.phase == "cart_wait" and picked_at == "":
				picked_at = "brought"  # the cart boy brought them round, their bags on
				brought = g.carts.duplicate()
			if g.phase == "board" and picked_at == "":
				var slots: Array = life._line_slots()
				var at_line := true
				var at_barn := true
				for cart in g.carts:
					var cp: Vector3 = cart.node.global_position
					at_line = at_line and slots.any(func(xf: Transform3D) -> bool: return Vector2(xf.origin.x - cp.x, xf.origin.z - cp.z).length() < 0.6)
					at_barn = at_barn and FacilityBuilder.contains("cart_barn", b.placements["cart_barn"]["pos"], 0.0, Vector2(cp.x, cp.z))
				picked_at = "line" if at_line else ("barn" if at_barn else "elsewhere")
				took = g.carts.size()
			if g.phase == "tee_queue" and not bags_loaded and g.golfers.all(func(w: ClubLife.Walker) -> bool: return w.riding):
				var in_carts := 0
				for cart in g.carts:
					in_carts += (cart.data.get("bags",[]) as Array).size()
				bags_loaded = in_carts == g.golfers.size() and not g.golfers.any(func(w: ClubLife.Walker) -> bool: return w.data.has("bag"))
			for cart in g.carts:
				if cart.node.visible:
					var p: Vector3 = cart.node.global_position
					if life._yard_at(Vector2(p.x,p.z)) == null and not b.placements.keys().any(func(t: String) -> bool: return FacilityBuilder.contains(t, b.placements[t]["pos"], 0.0, Vector2(p.x,p.z), 2.0 + ClubLife.COURSE_CELL * 1.5)):
						if safe and life._cart_nav.is_point_solid(life._nav_cell_raw(Vector2(p.x,p.z))) and OS.get_environment("STUCK_TRACE") != "":
							print("  excluded: cart at %s in %s, %d points to go" % [str(Vector2(p.x, p.z).round()), g.phase, cart.path.size()])
						safe = safe and not life._cart_nav.is_point_solid(life._nav_cell_raw(Vector2(p.x,p.z)))
			for w in g.golfers:
				if w.riding or not w.node.visible:
					continue
				var bag = w.data.get("bag")
				if bag != null and is_instance_valid(bag) and (bag as Node3D).visible:
					var hl: Vector3 = house.global_transform.affine_inverse() * w.node.global_position
					for id in boxes:
						if id != "valet" and (boxes[id]["rect"] as Rect2).has_point(Vector2(hl.x, hl.z)):
							clubs_in += 1
				for cart in g.carts:
					if cart.node.visible and cart.path.is_empty():
						var l: Vector3 = cart.node.global_transform.affine_inverse() * w.node.global_position
						if absf(l.x) < ClubLife.CART_HALF.x - 0.05 and absf(l.z) < ClubLife.CART_HALF.y - 0.05:
							through[g.phase] = int(through.get(g.phase, 0)) + 1
		check(g.checked_in,"Visitor did not check in: "+g.phase)
		check(stacked == 0,"Balls left lying on top of each other (%d moments)" % stacked)
		check(through.is_empty(),"Golfers walked through a cart: " + str(through))
		check(clubs_in == 0,"Golfers carried their clubs into the clubhouse (%d moments)" % clubs_in)
		check(by_front < 1.6,"Visitors did not check in by the front door (%.1f m from it)" % by_front)
		check(by_back > -0.3,"Visitors went in round the back (%.1f m out past the back wall)" % -by_back)
		check(phases.has("bag_pickup") or phases.has("cart_wait") or phases.has("back_walk") or phases.has("shop_exit"),"Visitors never left the clubhouse")
		check(bags_from_car,"Golfers got out of the car without their bags")
		check(picked_at == "brought" or phases.has("board") and picked_at in ["line", "barn"],"Golfers did not pick their carts up off the line or at the barn: " + picked_at)
		check(visit != "" or picked_at == "brought","The cart boy did not bring the first flight's carts round")
		if brought.is_empty():
			check(life._stock.size() - stock_before == took,"The carts were not left at the barn (%d of %d)" % [life._stock.size() - stock_before, took])
		else:
			var back := brought.filter(func(cart: ClubLife.Walker) -> bool: return life._stock.has(cart) or not is_instance_valid(cart.node))
			check(back.size() == brought.size(),"The carts were not left at the barn (%d of %d)" % [back.size(), brought.size()])
		check(bags_loaded,"Bags not loaded into the carts")
		check(phases.has("through_clubhouse"),"Visitors did not go home through the clubhouse")
		check(safe,"Cart entered excluded ground")
		check(g.scores.size()==3,"Flight did not complete all holes: "+g.phase+str(g.scores))
		check(phases.has("dismount") and phases.has("mount") and phases.has("putt_walk"),"Missing golfing phases")
		check(not range_first or phases.has("range_practice"),"Range visitor never practiced")
		check(visit != "short" or phases.has("short_practice"),"Short game visitor never practised")
		check(not life._groups.has(g),"Visitor did not depart")
		if life._groups.has(g):
			life._groups.erase(g)
			life._free_group(g)
		await process_frame
	# the cart boy: the line down to two carts at its back -- he pulls them up to the front and
	# brings more over from the barn till it's full again
	b.accepting_visitors = false
	life._spawn_wait = 1e9
	var keep := 2
	for i in range(life._line.size()):
		if life._line[i] != null and life._line.count(null) < life._line.size() - keep:
			(life._line[i] as ClubLife.Walker).node.queue_free()
			life._pool.erase(life._line[i])
			life._line[i] = null
	var fetched := false
	for step in range(8000):
		life._process(.25)
		for pc in life._pool:
			fetched = fetched or (pc as ClubLife.Walker).data.get("job", false) and not life._line_slots().any(func(xf: Transform3D) -> bool: return Vector2(xf.origin.x - pc.node.global_position.x, xf.origin.z - pc.node.global_position.z).length() < 1.0)
		if not life._line.has(null) and not life._pool.any(func(pc: ClubLife.Walker) -> bool: return pc.data.has("job")):
			print("CART BOY: line full again after %d s" % int(step * .25))
			break
	check(not life._line.has(null),"The cart boy did not fill the line (%d of %d)" % [life._line.size() - life._line.count(null), life._line.size()])
	check(fetched,"The cart boy never drove a cart over")
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
	print("VISITOR FLOW: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
