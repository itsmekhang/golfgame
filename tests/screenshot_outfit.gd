extends SceneTree
## Golfer outfit stills under the course look (needs a display, no course load):
##   godot --path . --resolution 1280x720 --script tests/screenshot_outfit.gd -- build/outfit
## Writes <prefix>_<view>.png for the game camera, face-on, a three-quarter front view, a
## close-up of the head and one mid-swing frame.
var golfer: GolferRig
var cam: Camera3D


func _init() -> void:
	call_deferred("run")


func snap(path: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[outfit] wrote ", path)


func run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "build/outfit"
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/golf_sky.gdshader")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	env_node.environment = e
	root.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	root.add_child(sun)
	GolfLook.apply(e, sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.42, 0.14)
	gm.roughness = 0.95
	ground.material_override = gm
	root.add_child(ground)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0214
	sm.height = 0.0428
	ball.mesh = sm
	ball.position = Vector3(0, 0.0214, 0)
	root.add_child(ball)
	golfer = GolferRig.new()
	root.add_child(golfer)
	cam = Camera3D.new()
	cam.fov = 45
	root.add_child(cam)
	var aim := Vector3(0, 0, -1)
	golfer.show_at_address("loaner_driver", 1.0, Vector3.ZERO, aim)
	var views := {
		"game": [Vector3(-0.6, 1.6, 4.2), Vector3(-0.3, 0.9, -2.0)],
		"faceon": [Vector3(3.4, 1.1, 0.0), Vector3(-0.5, 0.9, 0.0)],
		"front34": [Vector3(2.2, 1.4, -2.4), Vector3(-0.5, 0.95, 0.0)],
		"head": [Vector3(0.35, 1.55, -0.55), Vector3(-0.45, 1.35, 0.0)],
		"back": [Vector3(-3.4, 1.3, 0.6), Vector3(-0.5, 0.95, 0.0)],
	}
	for v in views:
		cam.global_position = views[v][0]
		cam.look_at(views[v][1], Vector3.UP)
		await snap("%s_%s.png" % [out, v])
	golfer._pose_at(golfer.top_time)
	cam.global_position = views["faceon"][0]
	cam.look_at(views["faceon"][1], Vector3.UP)
	await snap("%s_top.png" % out)
	golfer._pose_at(golfer.finish_time)
	cam.global_position = views["front34"][0]
	cam.look_at(views["front34"][1] + Vector3.UP * 0.3, Vector3.UP)
	await snap("%s_finish.png" % out)
	quit()
