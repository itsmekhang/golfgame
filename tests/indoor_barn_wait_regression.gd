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
	for level in range(1, 5):
		var life := ClubLife.new()
		root.add_child(life)
		life.set_process(false)
		life.course = PaintedCourse.create("Indoor waiting",Vector2i(400,400))
		life.business = CourseBusiness.create()
		life.business.built = {"cart_barn":level}
		life.business.placements = {"cart_barn":{"pos":Vector2(20,30),"rot":0.4}}
		life.business.staff = {"cart_attendant":3}
		var built := FacilityBuilder.build([{"type":"cart_barn","level":level,"pos":Vector2(20,30),"rot":0.4}],func(_p):return 0.0,false,true)
		root.add_child(built)
		life.facilities = built
		life.refresh()
		var barn := life._fac("cart_barn")
		var targets := {}
		for worker: ClubLife.Walker in life._cart_boys():
			worker.node.global_position = barn.global_transform * Vector3(-23,0,-2)
			var steps := life._home_steps(worker)
			check(not steps.is_empty(), "No indoor waiting destination at level %d" % level)
			if steps.is_empty(): continue
			var target: Vector2 = steps[0]["to"]
			var local := barn.global_transform.affine_inverse() * Vector3(target.x,0,target.y)
			check(local.z > [4.0,5.5,6.0,9.0][level-1] + 0.5, "Waiting destination outside barn")
			targets[target] = true
			life._go(worker, target)
			check(not worker.path.is_empty(), "No walking route to indoor waiting spot at level %d" % level)
			worker.node.global_position = Vector3(target.x,0,target.y)
			check(life._home_steps(worker).is_empty(), "Attendant does not settle at indoor waiting spot")
		check(targets.size() == 3, "Idle attendants share a waiting spot")
		print("INDOOR WAIT level=",level," spots=",targets.size())
		life.clear()
		life.queue_free()
		built.queue_free()
		await process_frame
	print("INDOOR BARN WAIT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
