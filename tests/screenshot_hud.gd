extends SceneTree
## Windowed stills of the round HUD over a course still, without loading the course:
##   godot --path . --script tests/screenshot_hud.gd -- build/hud [background.png]
## Writes <prefix>_aim.png, _power.png, _intro.png, _result.png, _callout.png, _help.png.

var hud: Hud


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_hud_unused.json")
	call_deferred("run")


func snap(path: String, frames: int = 20) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[hud] wrote ", path)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/hud"
	var bg_path := args[1] if args.size() > 1 else "res://build/holes_r2_12_at_85_14_3.png"
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var img := Image.load_from_file(ProjectSettings.globalize_path(bg_path)) if FileAccess.file_exists(bg_path) else null
	if img != null:
		bg.texture = ImageTexture.create_from_image(img)
	root.add_child(bg)
	hud = Hud.new()
	root.add_child(hud)
	hud.set_hole(12, "Golden Bell", 3, 155)
	hud.set_score(0, 2, -1, 0, 0)
	hud.set_conditions(7, "W", 9.5)
	hud.cash_label.text = "260"
	hud.set_club("Daddy's 7 Iron", "7I", "Fair", "")
	hud.set_lie("Tee", 0.0, CourseLayout.SURFACE_TEE)
	hud.set_distance(0)
	hud.set_prediction(151, 158, false)
	hud.set_side_bets([{"text": "Make 2 birdies or better", "reward": 20, "status": ""}, {"text": "Par or better on every par 3", "reward": 16, "status": "won"}, {"text": "Birdie a par 5", "reward": 12, "status": "lost"}])
	var map := Image.create(220, 440, false, Image.FORMAT_RGBA8)
	map.fill(Color("3c6a3a"))
	hud.set_minimap_texture(ImageTexture.create_from_image(map))
	hud.hole_marker.visible = true
	hud.hole_marker.position = Vector2(600, 250)
	hud.hole_marker.set_distance(156)
	await snap(prefix + "_aim.png")
	hud.set_shot_phase(1)
	hud.power_bar.value = 82
	await snap(prefix + "_power.png", 4)
	hud.set_shot_phase(0)
	hud.power_bar.value = 0
	hud.show_hole_intro(12, "Golden Bell", 3, 155, "Wind 7 mph: helping, right-to-left")
	await snap(prefix + "_intro.png", 50)
	hud.set_lie("Green", 1.2, PhysicsEnums.SurfaceType.GREEN)
	hud.set_distance(149)
	hud.show_shot_result(147, 149, 78, 8.4, "Green", PhysicsEnums.SurfaceType.GREEN)
	await snap(prefix + "_result.png", 40)
	hud.show_callout("Birdie", "In the hole   ·   2 strokes   ·   -1", "great")
	await snap(prefix + "_callout.png", 30)
	hud.toggle_help()
	await snap(prefix + "_help.png", 10)
	quit(0)
