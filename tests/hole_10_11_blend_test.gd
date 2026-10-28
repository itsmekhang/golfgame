extends SceneTree
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://hole_10_11_blend_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var layout := CourseBuilder.build(7)
	# Previously these shoulders were depressed 14 m below the blended hillside.
	for p in [Vector2(1476.328, -944.826), Vector2(1395.827, -791.832)]:
		var natural := layout._raw_height(p.x, p.y)
		var ground := layout.base_height_at(p.x, p.y)
		check(absf(ground - natural) < 1.0, "Boundary shoulder follows surrounding grade")
	# Across the former large bowl, ground should rise steadily toward hole 10.
	var previous := layout.base_height_at(1400, -945)
	var worst_reverse := 0.0
	for x in range(1402, 1561, 2):
		var h := layout.base_height_at(x, -945)
		worst_reverse = maxf(worst_reverse, previous - h)
		previous = h
	check(worst_reverse < 0.25, "No compensating hollow beside hole 10")
	var worst_cross_grade := 0.0
	for z in range(-1070, -789, 10):
		for x in range(1380, 1549, 2):
			var rise := layout.base_height_at(x + 2, z) - layout.base_height_at(x, z)
			worst_cross_grade = maxf(worst_cross_grade, absf(rise) / 2.0)
	# The deeper tee valley adds five metres of relief at this shoulder.
	# Bound the resulting slope to 15 degrees rather than the former 20% grade.
	check(worst_cross_grade < tan(deg_to_rad(15.0)), "Left rough blends into the deeper tee valley below 15 degrees")
	var tee := layout.tees[9].center
	var tee_h := layout.height_at(tee.x, tee.y)
	check(absf(layout.height_at(tee.x + 1, tee.y) - tee_h) < 0.001, "Hole 10 tee stays level")
	var creek: WaterHazard
	var pond: WaterHazard
	for hz in layout.water_hazards:
		if hz.hazard_name == "White Creek": creek = hz
		if hz.hazard_name == "White Pond": pond = hz
	check(creek != null and pond != null, "Hole 11 keeps its creek and pond")
	if creek == null or pond == null:
		quit(1)
		return
	var deepest_cut := 0.0
	var level_min := INF
	var level_max := -INF
	var samples := 0
	for z in range(int(creek.bounds.position.y), int(creek.bounds.end.y), 2):
		for x in range(int(creek.bounds.position.x), int(creek.bounds.end.x), 2):
			var p := Vector2(x, z)
			if creek.signed_distance(p) > -1.0: continue
			var base := layout.base_height_at(x, z)
			var bed := base + creek.depth_offset(base, p)
			var level := creek.water_level_at(p)
			deepest_cut = maxf(deepest_cut, base - bed)
			level_min = minf(level_min, level)
			level_max = maxf(level_max, level)
			samples += 1
			check(bed < level, "Creek bed stays below local water")
	# The softened 10/11 hillside has roughly two metres of stream fall.
	check(samples > 100 and level_max - level_min > 1.0, "Creek follows the hillside elevation")
	check(deepest_cut < 4.0, "Creek stays shallow instead of carving a canyon")
	check(pond.water_level_at(pond.center) == pond.water_level_at(pond.polygon[0]), "Pond stays level")
	root.add_child(creek)
	creek.build_visual()
	var faces := creek._mesh.mesh.get_faces()
	var worst_mesh_error := 0.0
	for i in range(0, faces.size(), 3):
		var center: Vector3 = (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		worst_mesh_error = maxf(worst_mesh_error, absf(center.y - creek.water_level_at(Vector2(center.x, center.z))))
	check(worst_mesh_error < 0.15, "Visible creek agrees with splash height between vertices")
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	root.add_child(ball)
	for p in [creek._flow_path[3], creek._flow_path[-4]]:
		ball.place(p)
		ball.global_position = Vector3(p.x, creek.water_level_at(p) + 0.2, p.y)
		ball.launch(1, 80, 0, 0, Vector3.FORWARD)
		ball.velocity = Vector3(0, -1, 0)
		for step in range(60):
			ball._step(GolfBall.DT)
			if ball.in_water: break
		check(ball.in_water and ball.last_hazard == creek, "Falling ball detects the sloped stream")
		check(absf(ball.global_position.y - (creek.water_level_at(p) - BallPhysics.RADIUS * 0.5)) < 0.0001, "Ball splashes at local creek height")
	ball.free()
	print("Creek samples=", samples, " max cut=", deepest_cut, " level range=", level_max-level_min, " mesh error=", worst_mesh_error, " reverse grade=", worst_reverse, " cross grade=", worst_cross_grade)
	print("HOLE 10/11 BLEND: ", "PASS" if failures == 0 else "FAIL")
	for hz in layout.water_hazards: hz.free()
	for bunker in layout.bunkers: bunker.free()
	quit(0 if failures == 0 else 1)
