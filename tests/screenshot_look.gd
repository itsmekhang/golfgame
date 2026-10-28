extends SceneTree
## Compares GolfLook variants from one course load (windowed, ~5 min to load):
##   godot --path . --resolution 1600x900 --script tests/screenshot_look.gd -- build/look 1:tee 13:green
## Every view in the args is captured once per variant in VARIANTS (plus "classic", the old
## flat look), as <prefix>_<variant>_<hole>_<view>.png. Views: tee | green | high | ball.
## Uses a throwaway save (never the player's).

const VARIANTS := {
	"look": {},
}

var course: Node3D


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_screenshot_look_unused.json")
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


func snap(path: String, frames: int = 40) -> void:
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[look] wrote ", path)


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
	var prefix := args[0] if args.size() > 0 else "build/look"
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await wait_ready()
	var env: Environment = (course.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = course.get_node("Sun")
	var classic := env.duplicate() as Environment
	classic.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	classic.ssao_enabled = false
	classic.glow_enabled = false
	classic.adjustment_enabled = false
	classic.fog_density = 0.00025
	classic.fog_aerial_perspective = 0.0
	var names: Array = VARIANTS.keys()
	if OS.get_environment("LOOK_CLASSIC") == "1":
		names.append("classic")
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
		match view:
			"green":
				var p := cup - fwd * 40.0
				aim(ground(p) + Vector3.UP * 1.7, ground(cup) + Vector3.UP * 0.5)
			"high":
				aim(ground(tee - fwd * 60.0) + Vector3.UP * 70.0, ground(tee.lerp(cup, 0.62)))
			"ball":
				var b: Vector3 = course.ball.global_position
				var side := Vector3(-fwd.y, 0.0, fwd.x)
				aim(b + side * 3.2 + Vector3(-fwd.x, 0.0, -fwd.y) * 1.5 + Vector3.UP * 1.1, b + Vector3.UP * 0.8)
			"turf":
				# low over the fairway 60 m out, looking along it toward the rough edge
				var p := tee + fwd * 60.0
				var right2 := Vector2(-fwd.y, fwd.x)
				aim(ground(p) + Vector3.UP * 1.4, ground(p + fwd * 12.0 + right2 * 9.0) + Vector3.UP * 0.1)
			"rough":
				# standing in the rough beside the fairway, looking back across it
				var right2 := Vector2(-fwd.y, fwd.x)
				var p := tee + fwd * 90.0
				for step in range(40):
					p += right2 * 1.0
					if course.layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH:
						break
				p += right2 * 6.0
				aim(ground(p) + Vector3.UP * 1.5, ground(p + fwd * 10.0 - right2 * 8.0) + Vector3.UP * 0.1)
		course.hud.visible = view == "tee"
		for vname in names:
			if vname == "classic":
				(course.get_node("WorldEnvironment") as WorldEnvironment).environment = classic
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				sun.directional_shadow_max_distance = 90.0
				sun.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
				sun.light_energy = 1.35
				sun.light_color = Color(1.0, 0.98, 0.94)
			else:
				(course.get_node("WorldEnvironment") as WorldEnvironment).environment = env
				GolfLook.apply(env, sun, VARIANTS[vname])
			await snap("%s_%s_%d_%s.png" % [prefix, vname, n, view])
		course.hud.visible = true
	quit(0)
