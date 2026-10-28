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
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Return to wash",Vector2i(400,400))
	life.business = CourseBusiness.create()
	life.business.built = {"clubhouse":4,"cart_barn":4}
	life.business.placements = {"clubhouse":{"pos":Vector2(-105,50),"rot":0.0},"cart_barn":{"pos":Vector2(-10,135),"rot":0.0}}
	life.business.staff = {"cart_attendant":3}
	var items: Array = []
	for type in life.business.placements:
		items.append({"type":type,"level":life.business.level(type),"pos":life.business.placements[type]["pos"],"rot":0.0})
	var built := FacilityBuilder.build(items,func(_p):return 0.0,false,true)
	root.add_child(built)
	life.facilities = built
	life.refresh()
	life._rng.seed = 101028
	var workers := life._cart_boys()
	for worker: ClubLife.Walker in workers:
		worker.data["steps"] = []
		worker.path.clear()
		worker.wait = 10.0
	var group := ClubLife.Group.new()
	group.wants_cart = true
	for i in range(4): group.golfers.append(life._person("golfer_a"))
	life._groups.append(group)
	check(life._bag_run(group),"Could not queue two departmental deliveries")
	life._dispatch_cart_department()
	var status := life.cart_department_workload()
	check(status["active"]["delivery"] == 2,"Department did not split two deliveries between employees")
	check(status["active"]["washing"] == 1,"Third employee did not get independent washing work")
	check(life._bag_runs.is_empty(),"Department left assignable deliveries pending")
	var queues: Array = []
	for worker: ClubLife.Walker in workers: queues.append((worker.data["steps"] as Array).duplicate())
	life._dispatch_cart_department()
	for i in workers.size():
		check(workers[i].data["steps"] == queues[i],"Dispatch replaced unfinished employee work")
	# Completion frees only that employee; the other two queues keep their order.
	workers[0].data["steps"] = []
	life._dispatch_cart_department()
	check(workers[1].data["steps"] == queues[1] and workers[2].data["steps"] == queues[2],"One employee's completion changed another employee's job")
	status = life.cart_department_workload()
	check(status["active"]["delivery"] == 1,"Department counted completed work as active")
	print("CART DEPARTMENT DISPATCH: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
