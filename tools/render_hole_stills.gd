extends SceneTree
## Renders the cinematic stills the hole loading screen plays (GolfLoadingScreen): three
## shots per hole -- a raised hero shot from behind the tee, a low shot of the green and
## an aerial from the side -- with the HUD, golfer, ball and aim line hidden. Needs a
## display; run after course changes that should show up on the loading screens:
##   godot --path . --script tools/render_hole_stills.gd [-- 12 13]   (default: all holes)
## Writes assets/loading/hole_NN_K.jpg (K = 1..3); run `godot --headless --import` after.

const OUT := "res://assets/loading/hole_%02d_%d.jpg"
const SIZE := Vector2i(1600, 900)

var course: Node3D


func _init() -> void:
	# frame-paced work shouldn't wait on the display (a sleeping screen paces vsync at a few Hz)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_render_stills_unused.json")
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


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, course.layout.height_at(p.x, p.y), p.y)


## First candidate camera spot standing on mown turf (fairway, first cut, fringe, green or
## tee): shrubs and trees only grow in the rough, so a low camera there never ends up inside
## a bush.
func on_turf(cands: Array) -> Vector2:
	for c: Vector2 in cands:
		if course.layout.hazard_at(c) == null and course.layout.surface_at(c) in [PhysicsEnums.SurfaceType.FAIRWAY, CourseLayout.SURFACE_FIRST_CUT, CourseLayout.SURFACE_FRINGE, PhysicsEnums.SurfaceType.GREEN, CourseLayout.SURFACE_TEE]:
			return c
	return cands[0]


func shoot(from: Vector3, at: Vector3, path: String, fov: float) -> void:
	course.camera.frozen = true
	course.camera.global_position = from
	course.camera.look_at(at, Vector3.UP)
	course.camera.fov = fov
	course.grass_root.view_position = from
	course.grass_root.focus_position = Vector2(at.x, at.z)
	# The course re-shows the golfer, ball and aim line every frame: pause it while shooting.
	course.set_process(false)
	course.set_physics_process(false)
	course.swing_rig.visible = false
	course.ball.visible = false
	for i in range(70):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	course.set_process(true)
	course.set_physics_process(true)
	print("[stills] wrote ", path)


func run() -> void:
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		only.append(int(a))
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await wait_ready()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/loading"))
	for i in range(course.layout.holes.size()):
		var n := i + 1
		if not only.is_empty() and not only.has(n):
			continue
		if course.hole_index != i:
			course.transition_to_hole(i)
			await wait_ready()
		course.hud.visible = false
		course.camera.cull_mask &= ~PerformanceSettings.SHOT_LAYER
		if course.swing_rig != null:
			course.swing_rig.visible = false
		course.ball.visible = false
		var hole: CourseLayout.Hole = course.layout.holes[i]
		var tee := Vector2(hole.tee.x, hole.tee.z)
		var cup := Vector2(hole.cup.x, hole.cup.z)
		var fwd := (cup - tee).normalized()
		var right := Vector2(-fwd.y, fwd.x)
		var length := tee.distance_to(cup)
		var side := -1.0 if n % 2 == 0 else 1.0
		# 1: from just behind the tee box, down the hole between the trees
		await shoot(ground(tee - fwd * 16.0 + right * side * 5.0) + Vector3.UP * 8.0, ground(tee.lerp(cup, 0.5)) + Vector3.UP * 2.0, OUT % [n, 1], 50.0)
		# 2: low over the approach, across the green from its front corner
		var low := on_turf([cup - fwd * 34.0 - right * side * 16.0, cup - fwd * 36.0 - right * side * 8.0, cup - fwd * 40.0, cup - fwd * 30.0 + right * side * 14.0, cup - fwd * 46.0 - right * side * 6.0, cup - fwd * 24.0])
		await shoot(ground(low) + Vector3.UP * 2.6, ground(cup) + Vector3.UP * 1.0, OUT % [n, 2], 46.0)
		# 3: aerial from behind the green, looking back down the hole
		await shoot(ground(cup + fwd * 55.0 + right * side * 30.0) + Vector3.UP * (38.0 + length * 0.04), ground(cup - fwd * minf(length * 0.45, 140.0)), OUT % [n, 3], 52.0)
		course.camera.fov = 60.0
		course.camera.frozen = false
	quit(0)
