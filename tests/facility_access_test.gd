extends SceneTree
var failed:=false
func _init()->void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failed=true;push_error(message)
func run()->void:
	for level in range(1,5):
		var built:=FacilityBuilder.build([{"type":"clubhouse","level":level,"pos":Vector2.ZERO,"rooms":{"lobby":3,"pro_shop":3,"restaurant":3,"ballroom":3}}],func(_p:Vector2)->float:return 0.0,false,true)
		root.add_child(built)
		var house:=built.get_child(0) as Node3D
		var life:=ClubLife.new();root.add_child(life);life.set_process(false)
		life.course=PaintedCourse.create("Access test",Vector2i(160,160));life.facilities=built
		var rig:=FacilityBuilder.rig(house)
		var group:=ClubLife.Group.new()
		var door:=life._front_door(house)
		for k in range(4):
			var w:=life._person("golfer_"+["a","e","b","f"][k]);group.golfers.append(w)
			w.node.position=Vector3(door.x+(k-1.5)*.2,.6,door.y-2.2)
		check(life._inside_guest(group,true),"No lobby to pro shop path at level "+str(level))
		for k in range(4):
			var w:ClubLife.Walker=group.golfers[k]
			var from:=w.node.global_position
			var unsafe:=0
			for point:Vector3 in w.path:
				if not life._walk_region_clear(w,from,Vector3(point.x,from.y,point.z)):
					unsafe+=1
					if k==0:print("UNSAFE LEG ",level," ",from," -> ",point)
				from=Vector3(point.x,from.y,point.z)
			check(unsafe==0,"Doorway route clips solid wall: level "+str(level)+" player "+str(k)+" legs "+str(unsafe))
		print("ACCESS level ",level," front ",door," route ",group.golfers[0].path)
		for tick in range(2400):
			if not life._moving(group.golfers):break
			for w:ClubLife.Walker in group.golfers:
				var before:=w.node.global_position
				life._step(w,.05)
				check(life._walk_region_clear(w,before,w.node.global_position),"Moving golfer clipped corridor at level "+str(level))
		check(not life._moving(group.golfers),"Flight did not finish walking into the shop")
		var leaves:Array=rig.get("door_leaves",[])
		check(leaves.size()>=2,"No hinged clubhouse doors at level "+str(level))
		if not leaves.is_empty():
			var leaf:MeshInstance3D=leaves[0]
			leaf.set_process(false)
			group.golfers[0].node.global_position=leaf.global_position+Vector3(0,0,1)
			for tick in range(30):leaf.call("_process",.025)
			check(float(leaf.get("opening"))>.99,"Door did not open before golfer reached it")
			check(not leaf.transform.is_equal_approx(leaf.get("closed")),"Door leaf does not move about hinge")
			for w:ClubLife.Walker in group.golfers:w.node.visible=false
			for tick in range(100):leaf.call("_process",.025)
			check(float(leaf.get("opening"))<.01,"Door did not close after the flight passed")
		life.queue_free();built.queue_free();await process_frame
	for level in range(1,5):
		var built:=FacilityBuilder.build([{"type":"cart_barn","level":level,"pos":Vector2.ZERO}],func(_p:Vector2)->float:return 0.0,false,true);root.add_child(built)
		await process_frame
		var barn:=built.get_child(0) as Node3D
		var carts:MultiMeshInstance3D=barn.get_node_or_null("Batch_cart")
		check(carts!=null,"No indoor carts in barn")
		var raw:Node3D=load("res://assets/facilities/cart_barn_l%d.gltf"%level).instantiate();root.add_child(raw)
		for marker:Node3D in raw.find_children("CART_*","Node3D",true,false):
			if FacilityBuilder._kind(marker.name)=="CART":check(marker.global_position.z>3.9,"Cart stored outside main garage")
		raw.queue_free()
		check(barn.find_children("COL_canopy*","",true,false).is_empty(),"Exterior cart canopy remains")
		print("BARN level ",level," indoor carts ",carts.multimesh.instance_count if carts!=null else 0)
		built.queue_free();await process_frame
	for level in range(1,5):
		var built:=FacilityBuilder.build([{"type":"driving_range","level":level,"pos":Vector2.ZERO}],func(_p:Vector2)->float:return 0.0,false,true);root.add_child(built)
		check(built.find_children("Batch_bag_*","",true,false).is_empty(),"Unoccupied range bays still have bags")
		built.queue_free();await process_frame
	var course:=PaintedCourse.create("Cups test",Vector2i(64,64))
	course.holes=[{"tee":Vector2(0,15),"pin":Vector2(0,-15),"par":3},{"tee":Vector2(-15,15),"pin":Vector2(-15,-15),"par":3}]
	var view:=PaintedView.new();root.add_child(view);view.set_course(course);ManagerGreenPins.install(view,course)
	check(view.find_children("CupLiner","",true,false).size()==2,"Greens do not have cup liners")
	check(view.find_children("Flagpin*","",true,false).size()==2,"Greens do not have flagpins")
	check(view.terrain.mesh is ArrayMesh,"Cup openings missing from green mesh")
	print("FACILITY ACCESS ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
