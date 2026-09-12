extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.12, 0.15, 0.16)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.8, 0.86, 0.9)
	settings.ambient_light_energy = 0.65
	env.environment = settings
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.31, 0.34, 0.33)
	mat.roughness = 1.0
	ground.material_override = mat
	world.add_child(ground)
	var i := 0
	for variant in ["rounded", "spreading", "upright"]:
		var bush := load("res://assets/vegetation/green_bushes/green_bush_" + variant + ".tscn").instantiate() as MeshInstance3D
		world.add_child(bush)
		bush.position.x = (i - 1) * 2.8
		var label := Label3D.new()
		label.text = variant.capitalize()
		label.position = Vector3(bush.position.x, 0.1, 1.1)
		label.font_size = 52
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
		i += 1
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2.9, 8.0)
	camera.look_at(Vector3(0, 0.65, 0))
	camera.fov = 52
	camera.current = true
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/vegetation/green_bushes/preview.png")
	print("Bush preview saved")
	quit()
