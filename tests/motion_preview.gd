extends SceneTree
const OUT := "C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/update/"
var camera: Camera3D
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave=false)
	call_deferred("run")
func shot(name: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position=eye;camera.look_at(target)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
func run() -> void:
	root.size=Vector2i(1200,900)
	var env:=WorldEnvironment.new();var e:=Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color("a3bbc6")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.8
	env.environment=e;root.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-35,0);sun.light_energy=1.3;root.add_child(sun)
	camera=Camera3D.new();root.add_child(camera)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor.mesh=plane;root.add_child(floor)
	var life:=ClubLife.new();root.add_child(life);life.set_process(false)
	var cart:Node3D=load("res://assets/facilities/props/golf_cart.glb").instantiate();root.add_child(cart)
	var boy:=life._person("staff_cart_attendant")
	for hood in [false,true]:
		boy.node.position=Vector3(0,0,-1.73) if hood else Vector3(-1.16,0,0)
		boy.node.look_at(Vector3(0,0,-1.0) if hood else Vector3.ZERO)
		var clip:="wipe_hood" if hood else "wipe"
		boy.anim.play(clip);boy.anim.seek(.55,true);boy.anim.pause();life._rag_on(boy,hood)
		await shot(clip,Vector3(-3.6,2.7,-4),Vector3(-.3,.9,-.4))
		life._rag_off(boy)
	boy.node.queue_free();cart.queue_free();await process_frame
	for gid in ["bench_flat","bench_incline"]:
		var model:=MeshInstance3D.new();model.mesh=FacilityBuilder.bench_split(gid)[0];root.add_child(model)
		var w:=life._person("golfer_a");w.data["rack_bar_gid"]=gid;life._gym_hold(w,"bar")
		w.anim.play("bench_incline" if gid=="bench_incline" else "bench");w.anim.seek(1.2,true);w.anim.pause();life._gym_follow(w)
		await shot(gid+"_fit",Vector3(2.8,2.1,-3),Vector3(0,.65,0))
		life._gym_off(w);w.node.queue_free();model.queue_free();await process_frame
	print("MOTION PREVIEWS DONE");quit()
