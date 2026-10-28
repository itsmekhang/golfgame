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

func actor(life: ClubLife) -> ClubLife.Walker:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	return w

func reset(car: ClubLife.Walker, person: ClubLife.Walker) -> void:
	car.node.transform = Transform3D.IDENTITY
	car.path = [Vector3(0, 0, -20)]
	car.speed = 5
	car.data = {"vehicle": true, "half": Vector2(1, 2), "pace": 1.0, "lane": 0.0}
	person.node.transform = Transform3D.IDENTITY
	person.data.clear()
	person.path.clear()
	person.node.position = Vector3(0, 0, -2.2)

func run() -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Traffic contact", Vector2i(180, 180))
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
	reset(car, person)
	for tick in range(350): life._step(car, 0.1)
	check(car.node.position == Vector3.ZERO and car.path == [Vector3(0, 0, -20)], "Car crept or rerouted against a pedestrian after waiting 20 seconds")
	check(car.data.get("pedestrian_stopped", false), "Contact did not register a complete stop")
	person.path = [Vector3(4, 0, -2.2)]
	for tick in range(100):
		life._step(car, 0.1)
		life._step(person, 0.1)
	check(person.node.position.x > 2.0, "Pedestrian could not sidestep into open space")
	check(car.node.position.z < -2.0, "Car never resumed after pedestrian cleared it")
	reset(car, person)
	for tick in range(100):
		life._step(car, 0.1)
		life._step(person, 0.1)
	check(absf(person.node.position.x) > 1.0 and car.node.position.z < -3.0, "Waiting golfer refuses to clear their own approaching cart")
	reset(car, person)
	car.path = [Vector3(20, 0, 0)]
	person.node.position = Vector3(2.4, 0, 0.2)
	for tick in range(120):
		life._step(car, 0.1)
		life._step(person, 0.1)
	check(person.node.position.z > 2.1 and car.node.position.x > 3.0, "Pedestrian sidestep used the width instead of a turning car's rotated body")
	reset(car, person)
	person.node.position = Vector3.ZERO
	person.path = [Vector3(4, 0, 0)]
	for tick in range(80):
		life._step(car, 0.1)
		life._step(person, 0.1)
	check(person.node.position.x > 2.0, "A pedestrian overlapping the car's center could not escape")
	reset(car, person)
	person.node.position = Vector3(0, 0, -8)
	car.speed = 20
	life._step(car, 1.0)
	check(car.node.position == Vector3.ZERO and car.path.size() == 1, "Large movement step tunneled through a pedestrian or consumed its waypoint")
	reset(car, person)
	person.node.position = Vector3(0, 0, 6)
	car.path = [Vector3(0, 0, 20)]
	car.data["reverse"] = 1
	car.speed = 20
	life._step(car, 1.0)
	check(car.node.position == Vector3.ZERO and car.path.size() == 1, "Reversing car backed through a pedestrian")
	reset(car, person)
	person.node.position = Vector3(2.1, 0, 0)
	var turning := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	check(not life._vehicle_people_clear(car, car.node.global_transform, turning), "Car's rotating body clipped a pedestrian")
	person.node.position = Vector3(1.6, 0, 0)
	check(life._walker_vehicle_clear(person, person.node.position, Vector3(1.6, 0, -5)), "Clear route beside a car was blocked by an oversized body")
	check(not life._walker_vehicle_clear(person, Vector3(2, 0, 0), Vector3(-2, 0, 0)), "Pedestrian walked through a car body")
	reset(car, person)
	person.node.position = Vector3(0, 0, -5)
	car.data["pedestrian_stopped"] = true
	life._go(person, Vector2(0, 5))
	check(person.path.size() > 2, "A stopped car was omitted from pedestrian rerouting")
	for tick in range(200):
		life._step(car, 0.1)
		life._step(person, 0.1)
	check(Vector2(person.node.position.x, person.node.position.z).distance_to(Vector2(0, 5)) < 0.8, "Car and walker still deadlock while trying to pass")
	reset(car, person)
	var other_cart := actor(life)
	person.riding = true
	person.data["cart_move"] = {"cart": other_cart}
	check(not life._vehicle_people_clear(car, car.node.global_transform, car.node.global_transform), "Cart ignored a pedestrian climbing into another vehicle")
	person.riding = false
	person.data.erase("cart_move")
	other_cart.node.queue_free()
	print("TRAFFIC CONTACT: permanent stop, side escape, overlap escape, resume, long strides, reversing, and turns checked")
	# Mesh bounds use the body center, exclude hidden geometry, and exclude riders.
	var model := actor(life)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 1, 4)
	body.mesh = mesh
	body.position = Vector3(3, 0.5, 1)
	model.node.add_child(body)
	var rider := Node3D.new()
	rider.add_to_group("club_people")
	model.node.add_child(rider)
	var accessory := MeshInstance3D.new()
	var oversized := BoxMesh.new()
	oversized.size = Vector3.ONE * 40
	accessory.mesh = oversized
	rider.add_child(accessory)
	var hidden := MeshInstance3D.new()
	hidden.mesh = oversized
	hidden.visible = false
	model.node.add_child(hidden)
	model.node.rotation.y = 0.7
	check(life._footprint(model).is_equal_approx(Vector2(1, 2)), "Rider or hidden mesh enlarged the car collision")
	check(life._vehicle_frame(model).origin.is_equal_approx(model.node.global_transform * Vector3(3, 0, 1)), "Collision uses the root pivot instead of the actual body center")
	print("CAR BOUNDS: actual centered mesh rectangle; riders and hidden meshes excluded")
	g.car = null
	g.golfers.clear()
	car.node.queue_free()
	person.node.queue_free()
	model.node.queue_free()
	life._groups.clear()
	await process_frame
	for level in range(1, 5):
		var built := FacilityBuilder.build([{"type": "parking_lot", "level": level, "pos": Vector2.ZERO, "rot": 0.4}], func(_p: Vector2) -> float: return 0.0, false, true)
		root.add_child(built)
		life.facilities = built
		var lot := built.get_child(0) as Node3D
		FacilityBuilder.park(lot, 0.3)
		var rig := FacilityBuilder.rig(lot)
		var parked := life._vehicles()
		check(parked.size() == rig["parked"].size(), "L%d ambient parked cars missing collision bodies" % level)
		var walker := actor(life)
		var empty_reachable := false
		life._grounds_nav = {}
		for i in range(rig["stalls"].size()):
			if not FacilityBuilder.stall_free(rig, i): continue
			var stall: Transform3D = rig["stalls"][i]
			var at := lot.global_transform * stall.origin
			var mouth := lot.global_transform * FacilityBuilder.stall_mouth(stall)
			var route := life._grounds_path(Vector2(mouth.x, mouth.z), Vector2(at.x, at.z))
			if route.is_empty(): continue
			walker.node.global_position = mouth
			walker.data["walk_region"] = {"nav": life._grounds_nav, "xf": Transform3D.IDENTITY}
			var last := mouth
			var clear := true
			for p: Vector3 in route:
				clear = clear and life._walk_region_clear(walker, last, p)
				last = p
			empty_reachable = empty_reachable or clear and Vector2(last.x, last.z).distance_to(Vector2(at.x, at.z)) < 0.7
			if empty_reachable: break
		check(empty_reachable, "L%d empty stalls remain phantom obstacles" % level)
		if not parked.is_empty():
			var actual: ClubLife.Walker = parked[0]
			var center := life._vehicle_frame(actual).origin
			var across := life._vehicle_frame(actual).basis.x.normalized() * 4
			check(not life._walker_vehicle_clear(walker, center - across, center + across), "L%d walker crossed a visible parked car" % level)
		FacilityBuilder.park(lot, 0.6)
		check(life._vehicles().size() == rig["parked"].size(), "L%d parking refresh left missing or stale collision bodies" % level)
		print("PARKING CLEARANCE L%d: occupied cars blocked; empty stalls reachable; refreshed bodies match visible cars" % level)
		walker.node.queue_free()
		built.queue_free()
		life.facilities = null
		life._grounds_nav = {}
		await process_frame
	life.queue_free()
	await process_frame
	print("TRAFFIC CONTACT REGRESSION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
