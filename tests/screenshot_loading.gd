extends SceneTree
## Windowed stills of the hole loading screen for one hole, without loading the 3D course:
##   godot --path . --script tests/screenshot_loading.gd -- build/loading 12
## Writes <prefix>_<n>_a.png (drawing in), _b.png (shots tracing), _c.png (ready to tee off).

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_loading_unused.json")
	call_deferred("run")


func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[loading] wrote ", path)


func wait(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		await process_frame


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/loading"
	var holes: Array = []
	for k in range(1, args.size()):
		holes.append(int(args[k]))
	if holes.is_empty():
		holes = [12]
	var layout := CourseBuilder.build(7)
	for n in holes:
		var overlay: GolfLoadingScreen = load("res://scenes/ui/golf_loading_screen.tscn").instantiate()
		root.add_child(overlay)
		var info := CourseBuilder.hole_info(n - 1)
		overlay.begin_hole(n, str(info["name"]), int(info["par"]), int(info["yd"]))
		overlay.update_progress(0.35, "Shaping the terrain…")
		await wait(0.9)
		await snap("%s_%d_a.png" % [prefix, n])
		overlay.update_progress(0.7, "Planting the woods…")
		await wait(1.6)
		await snap("%s_%d_b.png" % [prefix, n])
		overlay.minimum_ride_time = 999.0
		overlay.mark_ready()
		await wait(1.6)
		await snap("%s_%d_c.png" % [prefix, n])
		overlay.queue_free()
		await process_frame
	for hz in layout.water_hazards: hz.free()
	for bk in layout.bunkers: bk.free()
	quit(0)
