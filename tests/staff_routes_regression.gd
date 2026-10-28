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
	life.course = PaintedCourse.create("Staff routes", Vector2i(300, 300))
	life.business = CourseBusiness.create()
	life.business.built = {"clubhouse": 4}
	life.business.rooms = {"valet": 3, "spa_fitness": 3}
	life.business.staff = {"trainer": 1}
	life.business.placements = {"clubhouse": {"pos": Vector2.ZERO, "rot": 0.0}}
	var built := FacilityBuilder.build([{ "type": "clubhouse", "level": 4, "pos": Vector2.ZERO, "rot": 0.0, "rooms": life.business.rooms}], func(_p): return 0.0, false, true)
	root.add_child(built)
	life.facilities = built
	life.refresh()
	var house := built.get_node("clubhouse") as Node3D
	var customer := life._person("golfer_a")
	var cart := life._cart()
	var bag := Node3D.new()
	life.add_child(bag)
	customer.data["bag_down"] = bag
	for yaw in [0.0, PI / 2.0, -0.7]:
		house.rotation.y = yaw
		var origin := house.global_transform * Vector3(-6.65, 0, 2.35)
		customer.node.global_position = origin
		life._valet_enter_clubhouse(customer, 0)
		check(not customer.path.is_empty(), "Valet guest has no clubhouse entry path")
		var from := origin
		for to: Vector3 in customer.path:
			for i in range(maxi(2, ceili(from.distance_to(to) * 8.0))):
				var at := house.global_transform.affine_inverse() * from.lerp(to, float(i) / maxi(2, ceili(from.distance_to(to) * 8.0)))
				check(not Rect2(-4.8, 4.3, 0.8, 4.8).has_point(Vector2(at.x, at.z)), "Valet guest crosses the bag rack")
				check(Vector2(at.x + 5.4, at.z - 3.4).length() > 0.55, "Valet guest crosses the front column")
			from = to
		bag.global_position = house.global_transform * Vector3(-4.45, 0.0, 6.2)
		var goal := life._bag_run_goal({"cart": cart, "at": "bag", "golfer": customer})
		var local := house.global_transform.affine_inverse() * Vector3(goal.x, 0, goal.y)
		check(local.x > -3.7 and absf(local.z - 6.2) < 0.1, "Cart attendant approaches the back of a rotated bag rack")
	house.rotation.y = 0.0
	var trainer: ClubLife.Walker = life._staff.filter(func(p): return p.data.get("role") == "trainer")[0]
	var group := ClubLife.Group.new()
	life._groups.append(group)
	var places := life._free_places("spa_fitness", ClubLife.GYM_USES)
	for index in [0, 3, 6]:
		var guest := life._person("golfer_a")
		guest.data["place"] = places[index]
		life._use_place(guest)
		group.golfers.append(guest)
	trainer.wait = 0.0
	var start := trainer.node.global_position
	var travelled := 0.0
	for tick in range(1800):
		life._clock += 0.1
		life._step(trainer, 0.1)
		travelled += start.distance_to(trainer.node.global_position)
		start = trainer.node.global_position
		if tick % 100 == 0: await process_frame
	check(int(trainer.data.get("trainer_visits", 0)) >= 3, "Trainer never completed visits to exercising guests")
	check((trainer.data.get("trainer_seen", {}) as Dictionary).size() >= 2, "Trainer repeatedly checks only one gym guest")
	check(travelled > 5.0, "Trainer remains at their post")
	print("TRAINER visits=", trainer.data.get("trainer_visits"), " guests=", (trainer.data.get("trainer_seen", {}) as Dictionary).size(), " distance=", travelled)
	for file in ["golfer_a", "golfer_d"]:
		var actor := life._person(file)
		var sk := actor.node.find_child("Skeleton3D", true, false) as Skeleton3D
		var fixed := {}
		var min_gap := INF
		for frame in range(121):
			life._pose_now(actor, "situps")
			actor.anim.seek(actor.anim.get_animation("situps").length * frame / 120.0, true)
			actor.anim.pause()
			for side in ["L", "R"]:
				var foot := sk.get_bone_global_pose(sk.find_bone("foot." + side)).origin
				if frame == 0: fixed[side] = foot
				check(foot.distance_to(fixed[side]) < 0.001, "Crunch feet move off the mat")
				var knee := sk.get_bone_global_pose(sk.find_bone("shin." + side)).origin
				var shoulder := sk.get_bone_global_pose(sk.find_bone("upper_arm." + side)).origin
				min_gap = minf(min_gap, shoulder.z - knee.z)
		check(min_gap > 0.15, "Crunch folds the knees behind the shoulders")
	print("STAFF ROUTES AND CRUNCH: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
