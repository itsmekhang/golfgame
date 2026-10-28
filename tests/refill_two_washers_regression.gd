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
	var refill := life._new_barn_cart()
	check(refill != null, "Could not create refill fixture")
	refill.data["job"] = true
	life._line[0] = refill
	check(not life._barn_transfer_busy(), "A refill waiting for its driver still blocks barn washing")
	var refill_start := refill.node.global_position
	var wash := life._cart_job(workers[1])
	check(not wash.is_empty() and workers[1].data.has("wash_cart"), "Second attendant did not start washing during refill")
	var cart: ClubLife.Walker = workers[1].data.get("wash_cart")
	# Finish extraction safely, leaving this attendant washing at the apron.
	cart.data.erase("job")
	var spot: Vector2 = cart.data["parking_target"]
	life._settle_in_row(cart, spot)
	cart.data.erase("lead_out")
	cart.data.erase("lead_reverse")
	workers[1].data["steps"] = life._clean_cart_steps(workers[1], cart)
	check(not (workers[1].data["steps"] as Array).is_empty(), "First washer could not claim a hose")
	var help := life._cart_job(workers[2])
	check(not help.is_empty() and workers[2].data.has("wash_cart"), "Third attendant stood idle during refill and washing")
	check(workers[2].data.get("wash_cart") != cart, "Both washers claimed the same cart")
	check(refill.node.global_position == refill_start and refill.data.has("job"), "Test accidentally finished the refill before assigning both washers")
	check(life._barn_transfer_busy(), "A real wash-cart extraction must still protect garage maneuvers")
	print("REFILL WITH TWO WASHERS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
