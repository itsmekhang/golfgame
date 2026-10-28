extends SceneTree
func _init()->void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run()->void:
	root.size=Vector2i(1400,1000)
	var life:=ClubLife.new();root.add_child(life);life.set_process(false)
	life.course=PaintedCourse.create("Swing review",Vector2i(64,64))
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b0c6d6")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7
	root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-25,0);root.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(10,10);ground.mesh=plane
	var turf:=StandardMaterial3D.new();turf.albedo_color=Color("387742");ground.material_override=turf;root.add_child(ground)
	var actors:=[]
	for i in range(2):
		var w:=life._person("golfer_"+["a","e"][i])
		var ball:=Vector3((i-.5)*1.5,.045,-.78)
		life._address_ball(w,ball,Vector2.LEFT,false)
		w.data["held_club"].visible=true;actors.append(w)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.8
	for phase in [["release",1.30],["follow",1.55],["settle",1.80],["finish",2.4]]:
		for w in actors:
			w.anim.play("swing",0);w.anim.seek(phase[1],true);w.anim.pause();life._update_held_club(w)
		for view in [["front",Vector3(0,1.6,-6)],["back",Vector3(0,1.6,6)],["side",Vector3(-5,2,-2)]]:
			camera.position=view[1];camera.look_at(Vector3(0,1,0))
			for frame in range(4):await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/swing_"+phase[0]+"_"+view[0]+".png")
	quit()
