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
	var ready := false
	for tick in range(1600):
		life._spawn_wait = 1e9
		life._process(0.1)
		if workers.filter(func(p): return p.data.has("wash_cart") and not (p.data["wash_cart"] as ClubLife.Walker).data.has("job")).size() >= 2:
			ready = true
			break
		if tick % 100 == 0: await process_frame
	check(ready, "Fixture never reached concurrent downtime cleaning")
	var group := ClubLife.Group.new()
	group.wants_cart = true
	for i in range(2): group.golfers.append(life._person("golfer_a"))
	life._groups.append(group)
	check(life._bag_run(group), "Could not request a cart during cleaning")
	life._wake_returning_attendants()
	for worker: ClubLife.Walker in workers:
		if not worker.riding and not worker.data.has("cart_move"):
			worker.path.clear()
			worker.wait = 0.0
			life._cart_boy(worker)
	check(life._bag_runs.is_empty(), "A cleaning task delayed urgent cart assignment")
	var delivered := false
	var curb_trips := 0
	var elapsed := 0.0
	for tick in range(4500):
		life._clock += 0.1
		life._wake_returning_attendants()
		for worker: ClubLife.Walker in workers:
			if worker.data.has("cart_move"): life._cart_move_step(worker, 0.1)
			else: life._step(worker, 0.1)
			for step: Dictionary in worker.data.get("steps", []):
				if step.get("cart") in group.carts and step.get("kind") in ["curb", "away"]: curb_trips += 1
		for cart: ClubLife.Walker in life._pool: life._step(cart, 0.1)
		for cart: ClubLife.Walker in group.carts: life._step(cart, 0.1)
		if (group.carts[0] as ClubLife.Walker).data.get("delivered", false):
			delivered = true
			elapsed = tick * 0.1
			break
		if tick % 100 == 0: await process_frame
	if not delivered:
		for worker: ClubLife.Walker in workers: print("URGENT WORKER ",worker.node.global_position," riding=",worker.riding," move=",worker.data.has("cart_move")," path=",worker.path.slice(0,3)," steps=",worker.data.get("steps",[]))
		for cart: ClubLife.Walker in group.carts: print("URGENT CART ",cart.node.global_position," path=",cart.path.slice(0,3)," flags=",cart.data)
	check(delivered, "Urgent direct cart delivery did not reach the golfers")
	check(curb_trips == 0, "A flight without bags sent its cart to the front curb")
	print("URGENT CART DELIVERY: delivered=", delivered, " seconds=", elapsed, " front detours=", curb_trips)
	print("URGENT CART DELIVERY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
