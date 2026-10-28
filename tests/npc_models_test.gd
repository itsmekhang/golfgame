extends SceneTree
func _init() -> void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run() -> void:
	root.size=Vector2i(1200,900)
	var world:=Node3D.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("aabcc8")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color.WHITE
	env.ambient_light_energy=.7
	environment.environment=env
	world.add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-25,0)
	world.add_child(sun)
	var life := ClubLife.new()
	world.add_child(life)
	life.set_process(false)
	var actors:Array=[]
	for i in range(2):
		var walker := life._person("golfer_%s" % ["a","e"][i])
		var p:Node3D=walker.node
		p.position.x=(i-.5)*1.2
		var anim:AnimationPlayer=p.find_child("AnimationPlayer",true,false)
		print("NPC ANIMATIONS ",anim.get_animation_list())
		for name in ["idle","walk","swing","putt","drive","ride"]:
			assert(anim.has_animation(name),"Missing NPC animation "+name)
		actors.append(walker)
	var cam:=Camera3D.new()
	world.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.size=2.5
	cam.position=Vector3(0,1.3,-5)
	cam.look_at(Vector3(0,.9,0))
	for pose in ["idle","walk","swing","putt","drive"]:
		for walker in actors:
			life._play(walker,pose)
			var anim: AnimationPlayer = walker.anim
			anim.play(pose,0.0)
			anim.seek(1.0 if pose == "swing" else .35,true)
			anim.pause()
		for i in range(4):await process_frame
		if not DisplayServer.get_name()=="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/npc_"+pose+".png")
	print("NPC MODELS PASS")
	quit()
