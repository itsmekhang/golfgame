extends SceneTree
var failed := false

class Frame extends CourseManager:
	func _ready() -> void:
		set_process(false)
		camera = StudioCamera.new()
		add_child(camera)
		_build_ui()

func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("263d36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.7
	var before := 0
	var after := 0
	for i in range(FacilityBuilder.CARS.size()):
		var v: String = FacilityBuilder.CARS[i]
		var source := FacilityBuilder._first_mesh("res://assets/facilities/props/cars/car_%s.glb" % v)
		var lite := FacilityBuilder.car_mesh(v)
		check(lite != null, v + " failed to load")
		check(source.get_aabb().position.distance_to(lite.get_aabb().position) < 0.04 and source.get_aabb().end.distance_to(lite.get_aabb().end) < 0.04, v + " changed its vehicle clearance")
		for s in range(source.get_surface_count()): before += source.surface_get_array_index_len(s) / 3
		for s in range(lite.get_surface_count()): after += lite.surface_get_array_index_len(s) / 3
		var model := MeshInstance3D.new()
		model.mesh = lite
		model.position = Vector3((i % 5) * 3.1, 0, (i / 5) * 6)
		model.set_instance_shader_parameter("paint", Color("a3bcc8") if i % 2 == 0 else Color("883333"))
		world.add_child(model)
	check(after < before * 0.65, "Runtime cars did not reduce geometry")
	print("CAR DETAIL: ", before, " -> ", after, " triangles")
	var frame := Frame.new()
	root.add_child(frame)
	frame._tab = "staff"
	UITheme.label(frame._side, "Club panel", 22, UITheme.TEXT)
	UITheme.label(frame._side, "Club · Facilities · Rooms · Staff · Books", 14, UITheme.TEXT)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(21, 19, -21)
	camera.look_at(Vector3(6, 0, 3))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	camera.current = true
	for tick in range(40): await process_frame
	check(frame._side_wrap.visible, "Panel starts closed")
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/hud_cars_open.png")
	frame._side_toggle.pressed.emit()
	check(not frame._side_wrap.visible and frame._side_toggle.visible, "Hidden panel has no reopen button")
	check(frame._side_toggle.text.contains("Show"), "Reopen label is unclear")
	for tick in range(3): await process_frame
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/hud_cars_closed.png")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_H
	frame._unhandled_input(key)
	check(frame._side_wrap.visible and frame._tab == "staff", "H did not restore the same tab")
	print("HUD AND CAR QUALITY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
