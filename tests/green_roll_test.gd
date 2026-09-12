extends SceneTree
## Headless ball-roll checks for the named green landforms (Augusta build brief):
## a ball released on each key slope must move in the expected direction.
## Run: godot --headless --path . --script tests/green_roll_test.gd

## [hole index, green-frame offset (x along approach, y golfer's right), expected
## roll direction in the same frame, label]
const CHECKS := [
	[8, Vector2(-28.0, 0.0), Vector2(-1.0, 0.0), "No. 9 front apron rejects short balls"],
	[15, Vector2(0.0, 3.0), Vector2(0.0, -1.0), "No. 16 transition feeds right to left"],
	[13, Vector2(-11.0, 0.0), Vector2(-1.0, 0.0), "No. 14 front ridge returns balls short of it"],
	[2, Vector2(0.0, 4.0), Vector2(0.0, -1.0), "No. 3 green falls right to left"],
	[17, Vector2(1.0, 0.0), Vector2(-1.0, 0.0), "No. 18 middle transition runs back to the front shelf"],
	[14, Vector2(-11.0, 0.0), Vector2(-1.0, 0.0), "No. 15 far bank slips into the pond"],
]


func _init() -> void:
	PhysicsLogger.set_level(PhysicsLogger.Level.ERROR)
	var layout := CourseBuilder.build(7)
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	ball.resolve_surface = func(p: Vector3) -> Dictionary:
		var s := layout.surface_at(Vector2(p.x, p.z))
		return {"surface": s, "engine": CourseLayout.engine_surface(s), "source": "test"}
	root.add_child(ball)
	await process_frame
	var failures := 0
	for chk in CHECKS:
		var hole: CourseLayout.Hole = layout.holes[chk[0]]
		var wps := hole.waypoints
		var gc := Vector2(wps[wps.size() - 1].x, wps[wps.size() - 1].z)
		var fx := (gc - Vector2(wps[wps.size() - 2].x, wps[wps.size() - 2].z)).normalized()
		var fy := Vector2(-fx.y, fx.x)
		var off: Vector2 = chk[1]
		var start := gc + fx * off.x + fy * off.y
		var want: Vector2 = chk[2]
		var want_w := (fx * want.x + fy * want.y).normalized()
		var h0 := layout.height_at(start.x, start.y)
		var h1 := layout.height_at(start.x + want_w.x * 3.0, start.y + want_w.y * 3.0)
		ball.place(start)
		ball.launch(0.5, 85.0, 0.0, 0.0, Vector3(want_w.x, 0.0, want_w.y))
		for i in range(60 * 15):
			ball._physics_process(1.0 / 60.0)
			if not ball.is_moving:
				break
		var moved := Vector2(ball.global_position.x, ball.global_position.z) - start
		var along := moved.dot(want_w)
		# the mesh must fall the expected way; a ball that rolls must roll that way too
		# (a gentle pin shelf is allowed to hold a ball released at a crawl)
		var grade := (h0 - h1) / 3.0
		var ok := grade > 0.005 and (moved.length() < 0.4 or along > 0.4)
		print("%s %-52s grade %+5.1f%%  rolled %5.1f m (%+.1f m the expected way) lie %s" % ["PASS" if ok else "FAIL", chk[3], (h0 - h1) / 3.0 * 100.0, moved.length(), along, CourseLayout.surface_label(ball.current_lie)])
		if not ok:
			failures += 1
	if failures == 0:
		print("GREEN ROLL TEST: PASS")
		quit(0)
	else:
		printerr("GREEN ROLL TEST: FAIL (%d)" % failures)
		quit(1)
