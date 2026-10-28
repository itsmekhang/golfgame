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
	life._rng.seed=419
	seed(419)
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

	c.save("user://_flight_queue_test.course.json"); b.owned=true; b.holes=3; b.course_path="user://_flight_queue_test.course.json"
	var flights:=[]
	var walkers:=0
	var riders:=0
	for i in range(4):
		var g:=life._new_arrival()
		g.range_visit=false;g.short_visit=false;g.checked_in=true
		check(g.golfers.size()<=4,"Flight exceeds four golfers")
		if g.wants_cart:riders+=1
		else:walkers+=1
		g.car.node.visible=false;g.car.path.clear()
		for k in range(g.golfers.size()):
			var w=g.golfers[k]
			if w.riding:life._unseat(w,g.carts[k/2],k%2)
			w.node.visible=true
			w.node.position=Vector3(-15+i*4,0,165+k)
			life._valet_take(w)  # These visitors have checked in; their bags are at the front drop.
		life._send_to_collection(g)
		flights.append(g)
	check(walkers>0 and riders>0,"Arrivals lack walking/cart mix")
	var checked_queue:=false
	var practice_waiters := {}
	var practice_backlog := false
	var tee_starts := {}
	var last_start := -1.0
	life._spawn_wait = 1e9
	for step in range(22000):
		if life._groups.is_empty() or flights.all(func(g: ClubLife.Group) -> bool: return g.scores.size() == 3):break
		b.hours += 0.25 / float(EconomyConfig.manager_cfg().get("real_seconds_per_hour",240))
		life._process(.25)  # Include the attendants who deliver each flight's carts.
		var reservations:={}
		var parked:=[]
		for g in life._groups:
			if g.wait_practice: practice_waiters[g]=true
			if g.hole == 0 and g.queue_hole == 0 and g.phase == "tee_queue" and life._tee_rank(g) >= 1: practice_backlog = true
			if g.tee_started and not tee_starts.has(g):
				check(last_start<0 or b.hours-last_start>=ClubLife.TEE_INTERVAL-0.00001,"Flights teed off closer than their tee interval")
				last_start=b.hours;tee_starts[g]=true
			var unhit_visible:=0
			for k in range(g.balls.size()):
				if k<g.strokes.size() and g.strokes[k]==0 and g.balls[k].visible:unhit_visible+=1
			check(unhit_visible<=1,"More than one golfer has teed a ball before hitting")
			if g.phase in ["tee_queue", "tee_ready"]:check(unhit_visible==0,"Waiting flight already has a ball on the tee")
			if g.hole_reserved and g.stop == 0:
				reservations[g.hole]=reservations.get(g.hole,0)+1
			if g.phase=="tee_queue" and not life._moving(g.golfers) and not life._moving(g.carts):
				checked_queue=true
				var tee:Vector2=g.stops[0]
				for w in g.golfers:
					var off:=Vector2(w.node.global_position.x,w.node.global_position.z).distance_to(tee)
					check(off>9,"Waiting flight enters tee area (%.1f m)" % off)
					if g.queue_hole==g.hole:  # (once it has gone to its place in line)
						check(off<24.0+6.0*g.queue_rank,"Waiting flight stands too far back from the tee (%.1f m, %d in line ahead)" % [off,g.queue_rank])
			for cart in g.carts:
				if cart.node.visible and cart.path.is_empty():
					var p:=Vector2(cart.node.global_position.x,cart.node.global_position.z)
					for other in parked:check(not cart_overlap(cart,other),"Parked carts overlap")
					parked.append(cart)
		for hole in reservations:check(reservations[hole]<=1,"Two active flights occupy the same tee area")
		if failed:break
		if step%1000==0:
			print("QUEUE STEP ", step, ": ", flights.map(func(g: ClubLife.Group) -> Array: return [g.phase, g.hole, g.stop, g.scores.size()]))
			await process_frame
	# A flight need not visit practice when deliveries space arrivals far enough apart.
	# The deterministic practice/queue-order case is in update_regression_test.gd.
	if practice_backlog: check(not practice_waiters.is_empty(),"A backed-up tee queue never offered practice")
	check(tee_starts.size()==flights.size(),"Not every flight received a tee time")
	print("Practice waiting flights: ",practice_waiters.size(),"; tee starts: ",tee_starts.size())
	check(checked_queue,"No queued flight was exercised")
	for g in flights:check(g.scores.size()==3,"Queued flight did not finish all holes: "+g.phase)
	print("FLIGHT QUEUE: ","FAIL" if failed else "PASS","; walking ",walkers," cart ",riders)
	life.clear();quit(1 if failed else 0)

func cart_overlap(a:ClubLife.Walker,b:ClubLife.Walker)->bool:
	var ca:=Vector2(a.node.global_position.x,a.node.global_position.z)
	var cb:=Vector2(b.node.global_position.x,b.node.global_position.z)
	var ax:=Vector2(a.node.global_basis.x.x,a.node.global_basis.x.z).normalized()
	var az:=Vector2(a.node.global_basis.z.x,a.node.global_basis.z.z).normalized()
	var bx:=Vector2(b.node.global_basis.x.x,b.node.global_basis.x.z).normalized()
	var bz:=Vector2(b.node.global_basis.z.x,b.node.global_basis.z.z).normalized()
	for axis:Vector2 in [ax,az,bx,bz]:
		var ar:=absf(axis.dot(ax))*ClubLife.CART_HALF.x+absf(axis.dot(az))*ClubLife.CART_HALF.y
		var br:=absf(axis.dot(bx))*ClubLife.CART_HALF.x+absf(axis.dot(bz))*ClubLife.CART_HALF.y
		if absf((ca-cb).dot(axis))>=ar+br+.1:return false
	return true
