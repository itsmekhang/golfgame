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
	var abandoned: Array = []
	for i in range(3):
		var worker: ClubLife.Walker = workers[i]
		var cart := life._cart()
		life._pool.append(cart)
		cart.data["barn_slot"] = i
		life._barn_out[i] = cart
		life._barn_slot_shown(i, false)
		cart.data["washing"] = true
		cart.data["washed_at"] = life._clock
		worker.data["wash_cart"] = cart
		worker.data["steps"] = [{"do":"wash","cart":cart}]
		worker.path.clear()
		abandoned.append(cart)
	# Two requested deliveries should interrupt two cleaners, preserving the third.
	life._bag_runs = [[null,0],[null,1]]
	life._wake_returning_attendants()
	check(not workers[0].data.has("wash_cart") and not workers[1].data.has("wash_cart"), "Delivery workers did not release their carts")
	check(workers[2].data.get("wash_cart") == abandoned[2], "The remaining attendant's washing was interrupted")
	check(life._stock.has(abandoned[0]) and life._stock.has(abandoned[1]), "Interrupted carts were not available for takeover")
	life._bag_runs.clear()
	life._release_wash(workers[2])
	# An older unwashed cart must not jump ahead of interrupted work.
	var older := life._cart()
	life._pool.append(older)
	life._stock.push_front(older)
	older.data["washed_at"] = -1e9
	for i in range(2):
		var steps := life._wash_steps(workers[2])
		var claimed: ClubLife.Walker = workers[2].data.get("wash_cart")
		check(claimed == abandoned[i], "Remaining attendant did not take the interrupted carts first")
		check(steps.any(func(s): return s.get("do") == "repark"), "Takeover omitted putting the cart back in the barn")
		life._release_wash(workers[2])
		life._stock.erase(claimed)
	print("WASH HANDOFF: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

