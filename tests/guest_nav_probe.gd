extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false)
	call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)
func run() -> void:
	var level := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 2
	var c := PaintedCourse.create("Visitor test",Vector2i(400,400))
	for points in [[Vector2(60,20),Vector2(60,-70)],[Vector2(-20,-30),Vector2(-20,-120)],[Vector2(-110,-55),Vector2(-110,-145)]]:
		c.holes.append({"tee":points[0],"pin":points[1],"par":3,"bends":[],"curve":false})
		c.paint(PaintedCourse.Surface.GREEN,points[1],9,1,1)
		c.paint(PaintedCourse.Surface.TEE,points[0],5,1,1)
	c.paint(PaintedCourse.Surface.WATER,Vector2(20,-20),10,1,1)
	c.paint(PaintedCourse.Surface.BUNKER,Vector2(75,-35),7,1,1)
	c.paint(PaintedCourse.Surface.WOODS,Vector2(100,-40),9,1,1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse":{"pos":Vector2(-105,50),"rot":0.0},"parking_lot":{"pos":Vector2(-105,130),"rot":0.0},"cart_barn":{"pos":Vector2(-15,130),"rot":0.0},"driving_range":{"pos":Vector2(100,115),"rot":0.0}}
	b.built = {"clubhouse":level,"cart_barn":level,"parking_lot":level,"driving_range":level}
	b.rooms = {"pro_shop":1}
	b.staff = {"shop_clerk":1,"cart_attendant":1,"range_attendant":1}
	var items: Array = []
	for type in b.placements:
		items.append({"type":type,"level":b.level(type),"pos":b.placements[type]["pos"],"rot":0.0,"rooms":b.rooms})
	var built := FacilityBuilder.build(items,func(_p:Vector2)->float:return 0.0,false,true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	for p in [c.holes[0]["tee"],c.holes[0]["pin"],Vector2(75,-35),Vector2(20,-20),Vector2(100,-40)]:
		check(life._cart_nav.is_point_solid(life._nav_cell_raw(p)),"Cart exclusion missing at "+str(p))
	check(life._route(Vector2(20,-20),Vector2(-40,0),true).is_empty(),"No unsafe route fallback")

	var house: Node3D = built.get_node("clubhouse")
	var nav := life._guest_nav(house)
	var grid: AStarGrid2D = nav["astar"]
	var rig := FacilityBuilder.rig(house)
	print("DOORS ", rig.get("doors"))
	print("SHOP ", rig["boxes"]["pro_shop"])
	print("SPOTS ", rig["spots"].get("pro_shop"))
	var front := life._facility_front("clubhouse")
	var local := house.global_transform.affine_inverse()*Vector3(front.x,0,front.y)
	print("FRONT ", local)
	for x in [-7.0,-5.0,-3.0,0.0,3.0]:
		for z in [15.0,17.0,19.0,21.0,23.0]:
			print("ROUTE ", Vector2(x,z), " ", FacilityBuilder.nav_route(house,"guest",Vector2(local.x,local.z),Vector2(x,z)).size())
	for z in range(25,68):
		var line := ""
		for x in range(-25,25):
			var p := Vector2(x*.4,z*.4)
			var cell := Vector2i(roundi((p.x-grid.offset.x)/.4),roundi((p.y-grid.offset.y)/.4))
			line += "#" if grid.is_point_solid(cell) else "."
		print(z*.4, " ", line)
	quit()
