extends SceneTree
## Start menu + Course Studio stills (needs a display, no course load):
##   godot --path . --resolution 1600x900 --script tests/screenshot_studio.gd -- build/studio
## Writes <prefix>_menu.png, <prefix>_menu_play.png, <prefix>_studio.png (sample hole, angled),
## <prefix>_studio_top.png (map view) and <prefix>_studio_paint.png (mid-stroke brush ring).

var out := "build/studio"


func _init() -> void:
	call_deferred("run")


func snap(name: String, frames: int = 30) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, name])
	print("[studio] wrote %s_%s.png" % [out, name])


func run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	var menu: StartMenu = load("res://scenes/start_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await snap("menu", 120)
	menu._show_spans()
	await snap("menu_play", 20)
	menu.queue_free()
	await process_frame

	GameLaunch.custom_course = ""
	var studio: CourseStudio = load("res://scenes/course_studio.tscn").instantiate()
	root.add_child(studio)
	current_scene = studio
	await snap("studio", 90)
	studio.camera.top_view()
	await snap("studio_top", 60)
	# a stroke in progress: the green brush over the approach
	studio.camera._goal_pitch = deg_to_rad(-50.0)
	studio.camera._goal_distance = 160.0
	var pin: Vector2 = studio.course.holes[0]["pin"]
	studio.camera.focus(Vector3(pin.x, studio.course.height_at(pin), pin.y + 20.0))
	studio._select_tool(studio._tool_index("bunker"))
	await snap("studio_paint", 60)
	# close on the tee: the rectangular tee box squared to the hole, Move tool selected
	var tee: Vector2 = studio.course.holes[0]["tee"]
	studio.camera._goal_pitch = deg_to_rad(-62.0)
	studio.camera._goal_distance = 70.0
	studio.camera.focus(Vector3(tee.x, studio.course.height_at(tee), tee.y - 12.0))
	studio._select_tool(studio._tool_index("move"))
	await snap("studio_tee", 60)
	studio._show_new_dialog()
	await snap("studio_new", 10)
	quit()
