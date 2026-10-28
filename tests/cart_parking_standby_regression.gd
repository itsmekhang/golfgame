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
class IdleLife extends ClubLife:
	func _wash_steps(_p: Walker) -> Array:
		return []

func run() -> void:
	var life := IdleLife.new()
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
		worker.node.global_position = Vector3(-35,0,130)
		worker.data.erase("cart_standby")
	life._dispatch_cart_department()
	var standby: ClubLife.Walker
	var homes := 0
	for worker: ClubLife.Walker in workers:
		if worker.data.get("cart_standby",false):
			check(standby == null,"More than one standby attendant")
			standby = worker
		else:
			homes += 1
			check(worker.data["steps"][0].get("return_to_barn",false),"Other idle attendant did not return to barn")
	check(standby != null and homes == 2,"Idle department did not split one standby and two barn attendants")
	var target: Vector2 = standby.data["steps"][0]["to"]
	check(target.distance_to(life._line_head()) < 4.0,"Standby is not beside cart parking")
	life._go(standby,target)
	check(not standby.path.is_empty(),"Standby point is unreachable")
	# Even when the standby employee is last in staff order, delivery goes to them.
	life._staff.erase(standby)
	life._staff.append(standby)
	var group := ClubLife.Group.new()
	group.wants_cart = true
	for i in range(2): group.golfers.append(life._person("golfer_a"))
	life._groups.append(group)
	check(life._bag_run(group),"Could not request delivery")
	life._wake_returning_attendants()
	life._dispatch_cart_department()
	check(standby.data["cart_assignment"]["kind"] == "delivery","Standby did not take bag loading and delivery first")
	check(not standby.data.get("cart_standby",false),"Delivery employee kept idle reservation")
	var replacement := workers.filter(func(w):return w.data.get("cart_standby",false))
	check(replacement.size() == 1,"Another free attendant did not cover standby")
	print("CART PARKING STANDBY: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
