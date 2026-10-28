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
	var group := ClubLife.Group.new()
	group.wants_cart = true
	for i in range(4): group.golfers.append(life._person("golfer_a"))
	life._groups.append(group)
	check(life._bag_run(group),"Could not reserve two delivery carts")
	var first: ClubLife.Walker = group.carts[0]
	var second: ClubLife.Walker = group.carts[1]
	workers[0].data["steps"] = [{"do":"drive","kind":"curb","cart":first,"index":0}]
	workers[1].data["steps"] = [{"do":"drive","kind":"curb","cart":second,"index":1}]
	life._cart_boy(workers[0])
	check(first.data.get("front_cart_route",false) and not first.path.is_empty(),"First bag cart did not enter reserved approach")
	var waiting_at := second.node.global_position
	for tick in range(400):
		life._cart_boy(workers[1])
		life._step(second,0.1)
	check(second.node.global_position == waiting_at and second.path.is_empty(),"Waiting bag cart entered the occupied shared approach")
	check(not workers[1].data["steps"][0].has("set"),"Waiting trip was marked started")
	# Arrival at the curb and the loading pause must retain the route reservation.
	first.path.clear()
	check(not life._claim_front_cart_route(second),"Loading cart released the approach too early")
	workers[0].data["steps"] = [{"do":"hand_over","group":group,"index":0}]
	life._cart_boy(workers[0])
	check(not first.data.has("front_cart_route"),"Delivered cart did not release the approach")
	life._cart_boy(workers[1])
	check(second.data.get("front_cart_route",false) and not second.path.is_empty(),"Queued cart never resumed after departure")
	life._cancel_bag_run(group)
	check(not second.data.has("front_cart_route"),"Cancellation leaked a route reservation")
	print("FRONT BAG CART ROUTE: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
