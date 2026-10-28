extends "res://tests/traffic_contact_regression.gd"

func run() -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Pedestrian flow", Vector2i(180, 180))
	life.business = CourseBusiness.create()
	life._nav = AStarGrid2D.new()
	life._nav.region = Rect2i(0, 0, 40, 40)
	life._nav.offset = Vector2(-80, -80)
	life._nav.cell_size = Vector2.ONE * ClubLife.COURSE_CELL
	life._nav.update()
	life._cart_nav = life._nav
	var car := actor(life)
	var person := actor(life)
	var g := ClubLife.Group.new()
	g.car = car
	g.golfers = [person]
	life._groups = [g]
	# Direct task routes do not have outdoor_target, unlike routes made with _go.
	for crossing in [false, true]:
		reset(car, person)
		person.node.position = Vector3(0, 0, -4)
		var destination := Vector3(7, 0, -4) if crossing else Vector3(0, 0, 8)
		person.path = [destination]
		var yielded := false
		var waited := false
		for tick in range(400):
			life._step(car, 0.05)
			life._step(person, 0.05)
			if person.data.has("pedestrian_yield"):
				yielded = true
				check(not person.path.is_empty(), "Yield was mistaken for task completion")
				var state: Dictionary = person.data["pedestrian_yield"]
				check(state["route"].back() == destination, "Yield discarded the walker destination")
				if person.node.position.distance_to(state["aside"]) < 0.15: waited = true
		check(yielded, "Direct-route walker did not yield")
		check(waited, "Walker did not wait outside the cart lane")
		check(person.node.position.distance_to(destination) < 0.2, "Direct-route walker failed to resume its original task")
		check(car.node.position.z < -19, "Cart remained stuck against a walking pedestrian")
	# A group must not reserve the same passing place or keep the cart stopped forever.
	reset(car, person)
	g.golfers = [person]
	for i in range(3): g.golfers.append(actor(life))
	for i in range(4):
		var member: ClubLife.Walker = g.golfers[i]
		member.node.position = Vector3(0, 0, -4 - i * 0.9)
		member.path = [Vector3(0, 0, 8 + i)]
	for tick in range(600):
		life._step(car, 0.05)
		for member: ClubLife.Walker in g.golfers: life._step(member, 0.05)
	check(car.node.position.z < -19, "Cart stayed stuck against a group of walkers")
	for i in range(4):
		check(g.golfers[i].path.is_empty() and g.golfers[i].node.position.distance_to(Vector3(0, 0, 8 + i)) < 0.6, "Group member lost its destination after yielding")
	for member: ClubLife.Walker in g.golfers.slice(1): member.node.queue_free()
	g.golfers = [person]
	# A task reassignment during yielding must win over the saved route.
	reset(car, person)
	person.path = [Vector3(0, 0, 8)]
	life._step(car, 0.1)
	life._step(person, 0.1)
	check(person.data.has("pedestrian_yield"), "Reassignment setup never yielded")
	var reassigned := Vector3(10, 0, -2.2)
	person.path = [reassigned]
	life._pedestrian_yield_step(person)
	check(not person.data.has("pedestrian_yield") and person.path == [reassigned], "Yield overwrote a newly assigned job")
	# Cancelling the vehicle job releases a pedestrian who was waiting for it.
	reset(car, person)
	person.path = [Vector3(0, 0, 8)]
	life._step(car, 0.1)
	life._step(person, 0.1)
	car.path.clear()
	life._pedestrian_yield_step(person)
	check(not person.data.has("pedestrian_yield") and person.path == [Vector3(0, 0, 8)], "Cancelled cart task stranded its pedestrian")
	# A car queued behind other traffic must not strand a person in its passing place.
	reset(car, person)
	person.path = [Vector3(0, 0, 8)]
	life._step(car, 0.1)
	life._step(person, 0.1)
	for tick in range(400): life._step(person, 0.05)
	check(person.node.position.distance_to(Vector3(0, 0, 8)) < 0.3 and person.path.is_empty(), "Queued car stranded its yielding pedestrian")
	# A different car occupies the passing place after it has been selected.
	reset(car, person)
	person.path = [Vector3(0, 0, 8)]
	life._step(car, 0.1)
	life._step(person, 0.1)
	var obstruction := actor(life)
	obstruction.data = {"vehicle":true,"half":Vector2(0.6,0.6)}
	obstruction.node.position = person.data["pedestrian_yield"]["aside"]
	g.carts = [obstruction]
	for tick in range(700): life._step(person, 0.05)
	check(person.path.is_empty() and person.node.position.distance_to(Vector3(0, 0, 8)) < 0.3, "Occupied passing place froze its pedestrian")
	g.carts.clear()
	obstruction.node.queue_free()
	life.queue_free()
	await process_frame
	print("PEDESTRIAN FLOW: head-on, crossing, task preservation, reassignment and cancelled cart checked")
	await super.run()
