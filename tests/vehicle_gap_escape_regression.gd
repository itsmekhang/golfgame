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

func run() -> void:
	for rotation in [0.0, 0.6]:
		var life := ClubLife.new()
		root.add_child(life)
		life.set_process(false)
		life.course = PaintedCourse.create("Wedged pedestrian",Vector2i(180,180))
		life.business = CourseBusiness.create()
		life._nav = AStarGrid2D.new()
		life._nav.region = Rect2i(0,0,80,80)
		life._nav.offset = Vector2(-80,-80)
		life._nav.cell_size = Vector2(2,2)
		life._nav.update()
		var basis := Basis(Vector3.UP,rotation)
		for x in [-1.25,1.25]:
			var car := actor(life)
			car.node.transform = Transform3D(basis,basis * Vector3(x,0,0))
			car.data = {"vehicle":true,"half":Vector2(1,2.3)}
			life._pool.append(car)
		var person := actor(life)
		person.speed = 1.5
		var goal := basis * Vector3(5,0,0)
		person.path = [goal]
		var route := life._vehicle_escape_route(person,goal)
		check(route.size() >= 2,"Did not route out of the gap before going round the cars")
		var at := person.node.global_position
		for point: Vector3 in route:
			check(life._walk_region_clear(person,at,point),"Escape route crosses a car")
			at = point
		for tick in range(600):
			life._step(person,0.1)
			if tick % 100 == 0: await process_frame
		check(person.node.global_position.distance_to(goal) < 0.6,"Pedestrian stayed wedged between cars")
		print("VEHICLE GAP rotation=",rotation," distance=",person.node.global_position.distance_to(goal))
		life.clear()
		life.queue_free()
		await process_frame
	print("VEHICLE GAP ESCAPE: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
