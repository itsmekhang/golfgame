extends SceneTree
## Golfer tuning stage (needs a display): poses GolferRig at address, top, impact and finish
## for a driver, an iron set and a wedge, face-on and down the line, plus extra driver finish
## frames.  godot --path . --resolution 640x640 --script tests/screenshot_golfer.gd -- build/golfer
var golfer: GolferRig
var cam: Camera3D
func _init() -> void:
	call_deferred("run")
func snap(path: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.8, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.5, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0214
	sm.height = 0.0428
	ball.mesh = sm
	ball.position = Vector3(0, 0.0214, 0)
	root.add_child(ball)
	golfer = GolferRig.new()
	root.add_child(golfer)
	cam = Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	print("impact %.3f finish %.3f forward %s target %s" % [golfer.impact_time, golfer.finish_time, golfer._forward, golfer._target_dir])
	var aim := Vector3(0, 0, -1)  # play toward -Z; golfer stands on the -X side facing +X
	for shot in [["loaner_driver", INF], ["loaner_irons", INF], ["loaner_pw", INF], ["loaner_putter", INF], ["loaner_pw", 25.0], ["loaner_pw", 8.0]]:
		var id: String = shot[0] if shot[1] == INF else "%s_%s" % [shot[0], golfer.clip_for(shot[0], shot[1])]
		golfer.show_at_address(shot[0], 1.0, Vector3(0, 0, 0.0), aim, shot[1])
		print(id, " clip ", golfer._clip, " impact ", golfer.club_impact_time, " finish ", golfer.finish_time)
		var top_t := golfer.impact_time - 0.27
		var frames := [["address", 0.0], ["top", golfer.top_time], ["down", (golfer.top_time + golfer.club_impact_time) * 0.5], ["late", golfer.club_impact_time - 0.04], ["impact", golfer.club_impact_time], ["finish", golfer.finish_time]]
		for frame in frames:
			golfer._pose_at(frame[1])
			# face-on: in front of the golfer (golfer at -X facing +X), looking back at them
			cam.global_position = Vector3(3.6, 1.0, 0.0)
			cam.look_at(Vector3(-0.5, 0.85, 0.0), Vector3.UP)
			await snap("%s_%s_%s_face.png" % [out, id, frame[0]])
			# down the line: behind the ball, looking toward the target
			cam.global_position = Vector3(-0.45, 1.3, 3.8)
			cam.look_at(Vector3(-0.45, 0.8, 0.0), Vector3.UP)
			await snap("%s_%s_%s_dtl.png" % [out, id, frame[0]])
	quit()
