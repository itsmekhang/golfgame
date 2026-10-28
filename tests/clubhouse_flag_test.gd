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
		var built:=FacilityBuilder.build([{"type":"clubhouse","level":level,"pos":Vector2.ZERO}],func(_p:Vector2)->float:return 0.0,false,true)
		root.add_child(built)
		var flags:=built.find_children("AmericanFlag*","Node3D",true,false)
		check(flags.size()==1,"Clubhouse must have exactly one American flag")
		if flags.size()==1:
			var flag=flags[0]
			check(flag.get_script().resource_path=="res://assets/world_flagstick/world_flagstick.gd","Flag does not use pin cloth controller")
			check(flag.fabric_texture!=null,"American flag texture missing")
			check(flag.cloth is SoftBody3D,"Native soft cloth missing")
			check(not flag.get_node("Model").visible,"Duplicate pin pole visible")
			# held by its very edge only (a thread, not a stiff band), and free to go round the pole
			for row in range(13):
				check(flag.cloth.is_point_pinned(row*21),"Hoist edge is unpinned")
				check(not flag.cloth.is_point_pinned(row*21+1),"Hoist is a stiff band, not a thread")
			check(flag.swivel_hoist,"The flag can't go round its pole")
			check(flag.hoist_clearance>=.045,"Hoist does not clear the American flag pole")
			if level==1:
				# the wind round to blow from the other side: the cloth's own hoist (not just its
				# anchor) goes round the pole after it, the fabric streaming out from there
				var eye:=Camera3D.new();root.add_child(eye);eye.global_position=flag.global_position+Vector3(0,8,-12)
				flag.wind_wander=0.0
				flag.wind_velocity=Vector3(-3,0,0)
				for i in range(900):await physics_frame
				var hoist:Vector3=flag.global_transform.affine_inverse()*flag.cloth.get_point_transform(6*21)
				var fly:Vector3=flag.global_transform.affine_inverse()*flag.cloth.get_point_transform(6*21+20)
				check(hoist.x<-.03,"The flag's hoist didn't go round to the downwind side: "+str(hoist))
				check(fly.x<hoist.x-.6,"The flag doesn't stream out downwind of its hoist: "+str(fly))
				eye.queue_free()
		built.queue_free();await process_frame
	var barn:=FacilityBuilder.build([{"type":"cart_barn","level":4,"pos":Vector2.ZERO}],func(_p:Vector2)->float:return 0.0,false,true)
	root.add_child(barn)
	check(barn.find_children("AmericanFlag*","Node3D",true,false).is_empty(),"Extra cart barn flags remain")
	print("CLUBHOUSE FLAG ","FAIL" if failed else "PASS")
	if "--preview" in OS.get_cmdline_user_args():
		root.size=Vector2i(1400,1000)
		var house:=FacilityBuilder.build([{"type":"clubhouse","level":4,"pos":Vector2.ZERO}],func(_p:Vector2)->float:return 0.0,false,true)
		root.add_child(house)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("9bbbd2")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7
		root.add_child(environment)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-25,0);root.add_child(sun)
		var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(160,160);ground.mesh=plane
		var green:=StandardMaterial3D.new();green.albedo_color=Color("337546");ground.material_override=green;root.add_child(ground)
		var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6
		camera.position=Vector3(-1,10,-34);camera.look_at(Vector3(-5,8,-26))
		var flag=house.find_child("AmericanFlag",true,false)
		var initial:Vector3=flag.cloth.get_point_transform(272)
		for frame in range(240):await physics_frame
		var moved:Vector3=flag.cloth.get_point_transform(272)
		check(moved.is_finite() and moved.distance_to(initial)>.01,"American cloth did not respond to wind")
		for row in range(13):
			var expected:Vector3=flag.anchor.global_transform*flag.Grid.point(0,row)*4.0
			# The anchor transform is applied after scaling the local grid point.
			expected=flag.anchor.global_transform*(flag.Grid.point(0,row)*4.0)
			check(flag.cloth.get_point_transform(row*21).distance_to(expected)<.03,"American flag hoist drifted")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/clubhouse_american_flag.png")
		camera.size=105;camera.position=Vector3(70,55,-75);camera.look_at(Vector3(0,0,-4))
		for frame in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/clubhouse_forecourt.png")
	quit(1 if failed else 0)
