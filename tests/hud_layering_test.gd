extends SceneTree
## Pixel checks for a waypoint behind floating text and the opaque map pixels.
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://hud_layering_test_unused.json")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed = true
		push_error(label)

func capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func changed(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("HUD LAYERING: requires a graphical renderer")
		quit(1)
		return
	var backdrop := ColorRect.new()
	backdrop.color = Color("688596")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var hud := Hud.new()
	root.add_child(hud)
	hud.set_hole(1, "Tea Olive", 4, 445)
	hud.set_score(1, 0, 0, 0, 0)
	hud.set_conditions(4, "NE", 9.5)
	hud.cash_label.text = "60"
	hud.set_club("Loaner Driver", "DR")
	hud.set_lie("Tee", 0, CourseLayout.SURFACE_TEE)
	hud.set_distance(441)
	hud.set_prediction(231, 233, false)
	var map := Image.create(220, 440, false, Image.FORMAT_RGBA8)
	map.fill(Color("4c7443"))
	hud.set_minimap_texture(ImageTexture.create_from_image(map))
	await capture()
	check(hud.info_panel.size.x <= 256 and hud.info_panel.size.y <= 180, "Score, weather and wallet fit in one compact block")
	check(hud.minimap_panel.size.is_equal_approx(Vector2(110, 220)), "Map bounds fit the image without invisible side gutters")
	var marker := hud.hole_marker
	var center := hud.hole_label.global_position + Vector2(42, hud.hole_label.size.y * 0.5)
	marker.global_position = center - PinIndicator.SYMBOL_CENTER * marker.scale
	marker.visible = false
	var text_only := await capture()
	marker.visible = true
	var behind_text := await capture()
	var showing_through := 0
	var text_on_top := 0
	for y in range(int(center.y - 18), int(center.y + 18)):
		for x in range(int(center.x - 20), int(center.x + 20)):
			var before := text_only.get_pixel(x, y)
			var after := behind_text.get_pixel(x, y)
			if changed(before, after):
				showing_through += 1
			elif before.r > 0.87 and before.g > 0.87 and before.b > 0.82:
				text_on_top += 1
	check(showing_through > 250, "Waypoint remains visible in transparent HUD space")
	check(text_on_top > 20, "Opaque HUD lettering draws over the waypoint")
	var map_rect := hud.minimap_rect.get_global_rect()
	center = Vector2(map_rect.position.x, 75)
	marker.global_position = center - PinIndicator.SYMBOL_CENTER * marker.scale
	marker.visible = false
	var map_only := await capture()
	marker.visible = true
	var behind_map := await capture()
	var outside_visible := 0
	var over_map := 0
	for y in range(60, 90):
		for x in range(int(center.x - 18), int(center.x + 18)):
			if x < center.x - 3 and changed(map_only.get_pixel(x, y), behind_map.get_pixel(x, y)):
				outside_visible += 1
			elif x > center.x + 3 and changed(map_only.get_pixel(x, y), behind_map.get_pixel(x, y)):
				over_map += 1
	check(outside_visible > 200, "Waypoint is visible immediately outside the actual map")
	check(over_map > 200, "Waypoint draws over the minimap so it can reach the right edge")
	print("HUD LAYERING: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
