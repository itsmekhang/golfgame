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
	check(workers.size() == 3 and not life._line.has(null),"Fixture does not have three attendants and a full ready line")
	var head := life._line_head()
	for i in workers.size():
		var p: ClubLife.Walker = workers[i]
		p.node.global_position = Vector3(head.x - 5.0 - i * 2.0,0,head.y + 2.0)
		p.path.clear()
		p.wait = 0.0
	for c: ClubLife.Walker in life._line: c.data["washed_at"] = life._clock
	var saw_wash := false
	var most_cleaning := 0
	var needless_drives := 0
	var clubhouse_idle := 0
	var wall_hose_users := {}
	var barn := built.get_node("cart_barn") as Node3D
	check(life._wall_reels(barn).size() == 3 and life._wall_hooks(barn).size() == 3, "Barn does not have three wall reels and hooks")
	var bad_hose := false
	for tick in range(4500):
		life._spawn_wait = 1e9
		life._process(0.1)
		var cleaning := 0
		for p: ClubLife.Walker in workers:
			if p.data.has("wash_cart"): cleaning += 1
			if p.data.has("wash_cart"): saw_wash = true
			if p.data.has("hose"):
				wall_hose_users[p] = true
				var hose: Dictionary = p.data["hose"]
				var real_outlet := false
				for reel: Transform3D in life._wall_reels(barn):
					if (barn.global_transform * reel.origin).distance_to(hose["outlet"]) < 0.01: real_outlet = true
				bad_hose = bad_hose or not real_outlet or hose.get("rest") == null or hose["rest"].get_parent() != barn or hose["rest"].visible
			var steps: Array = p.data.get("steps",[])
			if tick > 2000 and steps.is_empty() and not p.riding and Vector2(p.node.global_position.x,p.node.global_position.z).distance_to(head) < 15.0:
				clubhouse_idle += 1
			if not steps.is_empty() and steps[0].get("do") == "drive" and steps[0].get("kind") != "yard": needless_drives += 1
		most_cleaning = maxi(most_cleaning, cleaning)
		if tick % 100 == 0: await process_frame
	check(wall_hose_users.size() == 3 and not bad_hose, "Not all attendants collected a hose from an actual wall-mounted reel")
	check(life.find_child("WashBayReel", true, false) == null, "Portable reels are still spawned beside wash carts")
	check(most_cleaning == 3, "Three attendants never cleaned separate carts together")
	check(needless_drives == 0, "Attendants drove to the clubhouse with a full line and no customer jobs")
	for worker: ClubLife.Walker in workers:
		check(int(worker.data.get("completed_washes", 0)) >= 1, "An attendant never completed their own wash-and-return cycle")
	check(saw_wash,"No attendant returned from the clubhouse to wash")
	check(not life._bay_washed.is_empty(),"No barn wash-and-return cycle completed")
	check(clubhouse_idle == 0,"Free attendants are still waiting by the clubhouse cart line")
	var targets := {}
	for p: ClubLife.Walker in workers:
		var home := life._home_steps(p)
		if home.is_empty():
			p.node.global_position += Vector3(12,0,0)
			home = life._home_steps(p)
		check(not home.is_empty(),"An attendant stops returning while still far from the barn waiting point")
		if not home.is_empty(): targets[home[0]["to"]] = true
	check(targets.size() == 3,"Attendants share one waiting point in the barn traffic lane")
	for worker: ClubLife.Walker in workers:
		life._release_wash(worker)
		worker.riding = false
		worker.data.erase("cart_move")
	for cart: ClubLife.Walker in life._pool: cart.data.erase("job")
	life._barn_returns.clear()
	for i in life._line.size(): life._line[i] = null
	var p: ClubLife.Walker = workers[0]
	p.data["steps"] = [{"do":"walk","to":Vector2.ZERO,"return_to_barn":true}]
	p.path = [Vector3.ZERO]
	var active: ClubLife.Walker = workers[1]
	var work: Array = [{"do":"wash","cart":life._pool[0]}]
	active.data["steps"] = work
	active.data["wash_cart"] = life._pool[0]
	life._pool[0].data.erase("barn_return_slot")
	life._line[0] = null
	life._wake_returning_attendants()
	check((p.data["steps"] as Array).is_empty() and p.path.is_empty(),"A new line gap does not wake an attendant returning to the barn")
	check(active.data["steps"] == work and active.data.has("wash_cart"),"Low cart stock interrupted washing despite a free returning attendant")
	print("BARN RETURN: wash=",saw_wash," concurrent=",most_cleaning," wall hose users=",wall_hose_users.size()," unneeded trips=",needless_drives," completed=",life._bay_washed.size()," clubhouse idle moments=",clubhouse_idle)
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
	print("ATTENDANT BARN RETURN: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
