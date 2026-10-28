extends SceneTree
var failed:=false
func _init() -> void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func check(ok:bool,msg:String) -> void:
	if not ok:failed=true;push_error(msg)
func run() -> void:
	var life:=ClubLife.new()
	root.add_child(life);life.set_process(false)
	life.course=PaintedCourse.create("Contact test",Vector2i(160,160))
	var worst:=0.0
	for look in ClubLife.LOOKS:
		var w:=life._person("golfer_"+look)
		var sk:Skeleton3D=w.node.find_child("Skeleton3D",true,false)
		for putt in [false,true]:
			var clip:="putt" if putt else "swing"
			var impact:=ClubLife.PUTT_IMPACT if putt else ClubLife.SWING_IMPACT
			for i in range(8):
				var aim:=Vector2.from_angle(i*TAU/8.0)
				var ball:=Vector3(10,.045,10)
				life._address_ball(w,ball,aim,putt)
				w.anim.play(clip,0);w.anim.seek(impact,true)
				w.data["held_club"].visible=true
				life._update_held_club(w)
				var hand:=sk.global_transform*sk.get_bone_global_pose(sk.find_bone(w.data.get("grip_bone", "hand.L")))
				var head:=hand*(w.data["club_grip"] as Node3D).transform*ClubLife.CLUB_HEAD_LOCAL
				var club:=hand*(w.data["club_grip"] as Node3D).transform
				var away:Vector3=-w.node.global_basis.z
				check(club.basis.x.normalized().dot(away)>.5,"Club toe points toward body")
				check(club.basis.z.normalized().dot(Vector3(aim.x,0,aim.y))>.8,"Club face points away from target")
				worst=maxf(worst,head.distance_to(ball))
				check(head.distance_to(ball)<.005,"Club misses ball: "+look+" "+clip+" "+str(head))
				var feet:=Vector2(w.node.position.x,w.node.position.z)
				check(feet.distance_to(Vector2(ball.x,ball.z))>.6,"Golfer stands on ball")
		w.node.queue_free()
	life.course.paint(PaintedCourse.Surface.GREEN,Vector2.ZERO,10,1,1)
	life.course.paint(PaintedCourse.Surface.WATER,Vector2(11,0),3,1,1)
	for p in [Vector2.ZERO,Vector2(8,0),Vector2(-6,5)]:
		var park:=life._bag_parking_spot(p)
		check(park!=Vector2.INF,"No fringe bag position")
		check(life._bag_ground_clear(park),"Bag stand overlaps green or hazard")
	print("NPC CONTACT ","FAIL" if failed else "PASS","; worst error ",worst," m; all 12 looks, full swings and putts, eight directions; fringe bags checked")
	if "--preview" in OS.get_cmdline_user_args() and not failed:
		root.size=Vector2i(1400,1000)
		var env:=WorldEnvironment.new()
		env.environment=Environment.new()
		env.environment.background_mode=Environment.BG_COLOR
		env.environment.background_color=Color("aabcc8")
		env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color.WHITE
		env.environment.ambient_light_energy=.7
		root.add_child(env)
		var sun:=DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-50,-25,0);root.add_child(sun)
		var ground:=MeshInstance3D.new()
		var plane:=PlaneMesh.new();plane.size=Vector2(12,12);ground.mesh=plane
		var turf:=StandardMaterial3D.new();turf.albedo_color=Color("387742");ground.material_override=turf;root.add_child(ground)
		var actors:=[]
		for i in range(2):
			var walker:=life._person("golfer_"+["a","e"][i])
			var point:=Vector3((i-.5)*1.8,.045,-.4)
			life._address_ball(walker,point,Vector2.LEFT,false)
			walker.data["held_club"].visible=true
			var ball:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.045;sphere.height=.09;ball.mesh=sphere
			root.add_child(ball);ball.position=point;actors.append(walker)
		var camera:=Camera3D.new();root.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.8
		camera.position=Vector3(-2.5,2.2,-5);camera.look_at(Vector3(0,.85,0))
		for pose in ["address","backswing","impact","finish","putt"]:
			for walker in actors:
				if pose=="putt":life._address_ball(walker,walker.data["shot_ball"],Vector2.LEFT,true)
				walker.anim.play("putt" if pose=="putt" else "swing",0)
				walker.anim.seek({"address":0.0,"backswing":.85,"impact":ClubLife.SWING_IMPACT,"finish":2.4,"putt":ClubLife.PUTT_IMPACT}[pose],true);walker.anim.pause()
				life._update_held_club(walker)
			for frame in range(4):await process_frame
			if pose=="impact":
				for walker in actors:
					var tip:Vector3=(walker.data["club_grip"] as Node3D).global_transform*ClubLife.CLUB_HEAD_LOCAL
					check(tip.distance_to(walker.data["shot_ball"])<.005,"Rendered club attachment misses ball")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/npc_contact_"+pose+".png")
	quit(1 if failed else 0)
