extends SceneTree
var failed:=false
func _init() -> void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failed=true;push_error(message)
func run()->void:
	for level in range(2,5):
		for tier in range(1,4):
			var facilities:=FacilityBuilder.build([{"type":"clubhouse","level":level,"pos":Vector2.ZERO,"rot":.35,"rooms":{"restaurant":tier,"ballroom":tier}}],func(_p:Vector2)->float:return 0.0,false,true)
			root.add_child(facilities)
			var house:Node3D=facilities.get_child(0)
			var life:=ClubLife.new();root.add_child(life);life.set_process(false)
			life.course=PaintedCourse.create("Waiter test",Vector2i(64,64));life.facilities=facilities
			life._rng.seed=1234
			var rig:=FacilityBuilder.rig(house)
			var shelves:MultiMeshInstance3D=house.get_node_or_null("Batch_bar_shelves")
			check(shelves!=null and shelves.multimesh.instance_count>=4,"Supplied bottle shelves missing")
			if shelves!=null:
				var oak:=false;var labels:=false
				var mesh:=shelves.multimesh.mesh
				for surface in range(mesh.get_surface_count()):
					var material:=mesh.surface_get_material(surface)
					oak=oak or material.resource_name=="Dark_Oak"
					labels=labels or (material.resource_name=="Atlas" and material.albedo_texture!=null)
				check(oak and labels,"Dark oak or new bottle textures missing")
				for index in range(shelves.multimesh.instance_count):
					# Compare the cabinet bottom with the room floor: the counter is 1m high.
					var bottom := shelves.multimesh.get_instance_transform(index).origin.y + mesh.get_aabb().position.y
					check(bottom > float(rig["boxes"]["restaurant"]["y"]) + 1.30,"Bottle cabinet lacks clearance above countertop")
			var glasses:MultiMeshInstance3D=house.get_node_or_null("Batch_hanging_glasses")
			check(glasses!=null and glasses.multimesh.instance_count>=20,"Hanging glassware missing")
			var spirits:MultiMeshInstance3D=house.get_node_or_null("Batch_counter_bottles_dark")
			check(spirits!=null and spirits.multimesh.instance_count>=1,"Organized countertop bottles missing")
			check(house.find_children("BAR_SINK*","Node3D",true,false).size()>=1,"Back counter sink missing")
			for pos:Node3D in house.find_children("BAR_POS*","Node3D",true,false):
				var local:=house.global_transform.affine_inverse()*pos.global_transform
				var near_bar:=false
				for sp in ClubLife._spots_for(rig["spots"]["restaurant"],"bartender"):
					var at:Vector3=sp["xf"].origin
					if absf(at.z-local.origin.z)<.7:
						near_bar=true
						check((-local.basis.z).dot(Vector3(0,0,-1))>.9,"POS faces away from bartender aisle")
			for i in range(3):
				var w:=life._person("staff_waiter")
				check(life._room_worker(w,"restaurant",i,"waiter"),"Waiter failed to spawn")
				var start:=w.node.global_position
				var nav:Dictionary=rig["nav"]["restaurant"]
				var grid:AStarGrid2D=nav["astar"]
				var at:=FacilityBuilder._nav_cell(nav,w.data["post"])
				check(nav["labels"][at.y*grid.region.size.x+at.x]==nav["largest"],"Waiter trapped in furniture pocket")
				var distance:=0.0;var destinations:=0
				for tick in range(1800):
					var before:=w.node.global_position
					life._step(w,.1)
					distance+=before.distance_to(w.node.global_position)
					if not w.path.is_empty():destinations+=1
					check(not w.data.get("blocked",false),"Waiter stuck retrying inaccessible table")
					check(absf(w.node.global_position.y-(house.global_transform*Vector3(0,float(w.data["y"]),0)).y)<.08,"Waiter left floor height")
				check(distance>30.0 and destinations>100,"Waiter did not circulate: "+str(distance))
				print("WAITER ",level,"/",tier," #",i," walked ",snappedf(distance,.1),"m")
			if level>=3:
				var tables:=house.find_children("BANQUET_TABLE*","Node3D",true,false)
				var screens:=house.find_children("PROJECTOR_SCREEN*","Node3D",true,false)
				check(screens.size()==1,"Stage projector screen missing")
				if tier>=2:
					check(tables.size()>=(2 if level==3 else 5),"Ballroom still too sparse: "+str(tables.size()))
					for a in range(tables.size()):
						for b in range(a):
							check(tables[a].global_position.distance_to(tables[b].global_position)>=4.2,"Banquet chairs too close")
				print("BALLROOM ",level,"/",tier," tables ",tables.size()," screens ",screens.size())
			life.free();facilities.free()
	print("WAITER AND LAYOUT ","FAIL" if failed else "PASS")
	if not failed and "--preview" in OS.get_cmdline_user_args():
		await preview()
	quit(1 if failed else 0)

func preview()->void:
	root.size=Vector2i(1500,1000)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("aabec8")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,20,0);world.add_child(sun)
	var f:=FacilityBuilder.build([{"type":"clubhouse","level":4,"pos":Vector2.ZERO,"rooms":{"restaurant":3,"ballroom":3}}],func(_p:Vector2)->float:return 0.0,false,true)
	world.add_child(f);FacilityBuilder.set_view(f,FacilityBuilder.View.WALLS_DOWN)
	var house:Node3D=f.get_child(0)
	var camera:=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	for room in ["restaurant","ballroom"]:
		var box:Dictionary=FacilityBuilder.rig(house)["boxes"][room]
		var rect:Rect2=box["rect"]
		var center:=Vector3(rect.get_center().x,float(box["y"])+1,rect.get_center().y)
		camera.size=maxf(rect.size.x,rect.size.y)*1.18
		camera.position=center+Vector3(3,12,-10);camera.look_at(center)
		for frame in range(10):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/"+room+"_redesign.png")
		if room=="restaurant":
			var close:=Vector3(rect.get_center().x,float(box["y"])+1.7,rect.end.y-1.6)
			camera.size=5.7;camera.position=close+Vector3(2.3,2.0,-3.7);camera.look_at(close)
			for frame in range(10):await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/bar_details.png")
	f.free()
	var shelf:Node3D=load("res://assets/facilities/props/bar_bottles.glb").instantiate();world.add_child(shelf);shelf.scale.x=1.73
	camera.size=2.2;camera.position=Vector3(1.4,1.6,-2.5);camera.look_at(Vector3(0,.67,0))
	for frame in range(10):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/dark_oak_bar_shelf.png")
