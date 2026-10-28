extends SceneTree
## Windowed stills of chosen holes from fixed cameras, for checking course edits by eye:
##   godot --path . --script tests/screenshot_holes.gd -- build/holes 12:tee 12:high 13:green
## Each arg is <hole number>:<view>. Views:
##   tee      the normal tee camera
##   overhead the game's overhead camera
##   high     a raised three-quarter view down the hole from behind the tee
##   green    low view of the green from 40 m short, at golfer height
##   side     the green from the side (90 degrees to the line of play), low
##   top      straight down over the whole hole
##   at,<along>,<right>,<height>[,<look_along>,<look_right>]   from that point of the tee-to-cup
##            frame, looking at the cup (or at the given point)
##   fly      fire a full shot from the tee: snaps <prefix>_<n>_fly.png mid-flight and
##            <prefix>_<n>_rest.png once the ball stops (normal game cameras, HUD on)
## Uses a throwaway save (never the player's).

var course: Node3D


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_holes_unused.json")
	call_deferred("run")


func wait_ready() -> void:
	for i in range(4000):
		await process_frame
		if course.ball != null and course.hud != null and course.active_region.size != Vector2.ZERO and course._loading_screen == null and not course._transitioning:
			break
		if i % 10 == 0 and course._loading_screen != null:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
	await process_frame


func snap(path: String, frames: int = 50) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[holes] wrote ", path)


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, course.layout.height_at(p.x, p.y), p.y)


func aim(from: Vector3, at: Vector3) -> void:
	course.camera.frozen = true
	course.camera.global_position = from
	course.camera.look_at(at, Vector3.UP)
	course.grass_root.view_position = from
	course.grass_root.focus_position = Vector2(at.x, at.z)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "build/holes"
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await wait_ready()
	var hud: CanvasLayer = course.hud
	for k in range(1, args.size()):
		var parts: PackedStringArray = args[k].split(":")
		var n := int(parts[0])
		var view := parts[1] if parts.size() > 1 else "tee"
		var i := n - 1
		if course.hole_index != i:
			course.transition_to_hole(i)
			await wait_ready()
		course.camera.frozen = false
		course.camera.mode = OrbitCamera.Mode.AIM
		var hole: CourseLayout.Hole = course.layout.holes[i]
		var tee := Vector2(hole.tee.x, hole.tee.z)
		var cup := Vector2(hole.cup.x, hole.cup.z)
		var fwd := (cup - tee).normalized()
		var right := Vector2(-fwd.y, fwd.x)
		match view:
			"overhead":
				course.camera.mode = OrbitCamera.Mode.OVERHEAD
			"high":
				var from := ground(tee - fwd * 60.0) + Vector3.UP * 70.0
				aim(from, ground(tee.lerp(cup, 0.62)))
			"green":
				var p := cup - fwd * 40.0
				aim(ground(p) + Vector3.UP * 1.7, ground(cup) + Vector3.UP * 0.5)
			"side":
				var p := cup + right * 45.0
				aim(ground(p) + Vector3.UP * 2.0, ground(cup) + Vector3.UP * 0.5)
			"top":
				var mid := tee.lerp(cup, 0.5)
				var span := tee.distance_to(cup)
				var from := ground(mid) + Vector3.UP * (span * 1.05 + 40.0)
				course.camera.frozen = true
				course.camera.global_position = from
				course.camera.look_at(ground(mid), Vector3(fwd.x, 0.0, fwd.y))
			"fly":
				hud.visible = true
				course.skip_swing_animation = true
				course._fire_shot(100.0, Vector2.ZERO)
				await snap("%s_%d_fly.png" % [prefix, n], 75)
				for frame_i in range(1200):
					await process_frame
					if course.phase == course.SwingPhase.IDLE:
						break
				await snap("%s_%d_rest.png" % [prefix, n], 30)
				continue
			_:
				if view.begins_with("at,"):
					var v := view.split(",")
					var p := tee + fwd * float(v[1]) + right * float(v[2])
					var look := cup
					if v.size() > 5:
						look = tee + fwd * float(v[4]) + right * float(v[5])
					aim(ground(p) + Vector3.UP * float(v[3]), ground(look) + Vector3.UP * 0.5)
		hud.visible = view == "tee" or view == "overhead"
		await snap("%s_%d_%s.png" % [prefix, n, view.replace(",", "_")])
		hud.visible = true
	quit(0)
