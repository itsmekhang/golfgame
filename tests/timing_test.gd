extends SceneTree
## Headless build-time profile: godot --headless --path . --script tests/timing_test.gd -- <course>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var course := args[0] if args.size() > 0 else "procedural"
	var t0 := Time.get_ticks_msec()
	var inst = (load("res://scenes/course.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	for i in range(600):
		await process_frame
		if inst.ball != null and inst.hud != null and inst.active_region.size != Vector2.ZERO:
			break
	print("[timing] %s total incl. loading frames: %d ms" % [course, Time.get_ticks_msec() - t0])
	quit(0)
