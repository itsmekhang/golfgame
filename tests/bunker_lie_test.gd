extends SceneTree
## Sand-edge lies while placing, rolling and stopping; mask edits and precedence.
## --headless --path . --script tests/bunker_lie_test.gd [-- --benchmark]

var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://bunker_lie_test_unused.json")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed = true
		push_error(label)

func run() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(-64, -64, 128, 128)
	layout.terrain_amplitude = 0.0
	layout.terrain_detail = 0.0
	var hole := CourseLayout.Hole.new()
	hole.index = 0
	hole.tee = Vector3(-40, 0, 0)
	hole.waypoints = [hole.tee, Vector3(40, 0, 0)]
	hole.green_radius = 5.0
	hole.fairway_half_width = 9.0
	layout.holes.append(hole)
	var bunker := Bunker.from_polygon(PackedVector2Array([
		Vector2(0.35, -3.35), Vector2(8.35, -3.35),
		Vector2(8.35, 3.65), Vector2(0.35, 3.65)]))
	layout.bunkers.append(bunker)
	var resolver := LieSurfaceResolver.new(layout)
	check(resolver.resolve(Vector3(4, 0, 0)).surface == CourseLayout.SURFACE_BUNKER,
		"Layouts without a rendered mask retain the geometric sand lie")
	layout.build_feature_mask()
	var grass_points := [Vector2(0.25, 0), Vector2(8.45, 0), Vector2(4, -3.45), Vector2(4, 3.75)]
	var sand_points := [Vector2(0.45, 0), Vector2(8.25, 0), Vector2(4, -3.25), Vector2(4, 3.55)]
	for index in range(4):
		var outside: Vector2 = grass_points[index]
		var inside: Vector2 = sand_points[index]
		check(resolver.resolve(Vector3(outside.x, 0, outside.y)).surface == PhysicsEnums.SurfaceType.FAIRWAY,
			"Grass 10 cm beyond sand edge %d is a fairway shot" % index)
		check(resolver.resolve(Vector3(inside.x, 0, inside.y)).surface == CourseLayout.SURFACE_BUNKER,
			"Sand 10 cm inside edge %d remains a bunker shot" % index)
	for point in [Vector2(-40, 0), Vector2(40, 0), Vector2(0, 30), Vector2(20, 0)]:
		check(layout.lie_surface_at(point) == layout.surface_at(point),
			"Tee, green, rough and fairway classification preserved at %s" % point)
	# Flat rendered contact tile isolates lie changes from slope and collision behavior.
	var heights := PackedFloat32Array()
	heights.resize(65 * 65)
	heights.fill(0.0)
	layout.rendered_terrain.register_tile(Vector2i.ZERO, Vector2.ZERO, 1.0, 65, 65, heights)
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	ball.log_level = PhysicsLogger.Level.OFF
	ball.resolve_surface = resolver.resolve
	root.add_child(ball)
	ball.set_physics_process(false)
	ball.place(Vector2(8.25, 1))
	check(ball.in_bunker and ball.current_lie == CourseLayout.SURFACE_BUNKER, "Placement in visible sand has a bunker lie")
	ball.putt(3.0, Vector3.RIGHT)
	for step in range(12):
		ball._step(GolfBall.DT)
	check(ball.position.x > 8.45 and ball.current_lie == PhysicsEnums.SurfaceType.FAIRWAY,
		"Rolling out of sand changes the lie immediately on grass")
	ball._finish_rest()
	check(not ball.in_bunker and ball.current_surface == PhysicsEnums.SurfaceType.FAIRWAY,
		"Stopping on the grass clears the bunker flag and sand physics")
	ball.putt(3.0, Vector3.LEFT)
	for step in range(12):
		ball._step(GolfBall.DT)
	check(ball.current_lie == CourseLayout.SURFACE_BUNKER, "Rolling back into sand restores bunker physics")
	ball._finish_rest()
	check(ball.in_bunker, "Resting in sand retains the bunker flag")
	ball.free()
	# Area overrides and water still win over sand.
	var zone := SurfaceZone.new()
	zone.surface_type = PhysicsEnums.SurfaceType.GREEN
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	zone.add_child(shape)
	root.add_child(zone)
	zone.position = Vector3(4, 0, 0)
	resolver.register_zones(self)
	check(resolver.resolve(Vector3(4, 0, 0)).source == "zone_override", "Explicit surface zones still override the sand mask")
	resolver.zones.clear()
	zone.free()
	var water := WaterHazard.new()
	water.set_polygon(PackedVector2Array([Vector2(3, -1), Vector2(5, -1), Vector2(5, 1), Vector2(3, 1)]))
	layout.water_hazards.append(water)
	check(resolver.resolve(Vector3(4, 0, 0)).surface == CourseLayout.SURFACE_WATER, "Water keeps priority over sand")
	layout.water_hazards.clear()
	water.free()
	# Reuse the same resolver as live rebuild_area(), so no stale private mask persists.
	layout.bunkers.clear()
	layout.update_feature_mask_rect(bunker.bounds)
	check(resolver.resolve(Vector3(4, 0, 0)).surface == PhysicsEnums.SurfaceType.FAIRWAY, "Removing a bunker immediately restores the grass lie")
	layout.bunkers.append(bunker)
	layout.update_feature_mask_rect(bunker.bounds)
	check(resolver.resolve(Vector3(4, 0, 0)).surface == CourseLayout.SURFACE_BUNKER, "Adding the bunker back immediately restores its sand lie")
	bunker.free()
	if "--benchmark" in OS.get_cmdline_user_args():
		benchmark_course()
	print("BUNKER LIE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func benchmark_course() -> void:
	var layout := CourseBuilder.build(7)
	layout.build_feature_mask()
	var points: Array[Vector2] = []
	var interiors_ok := true
	for bunker: Bunker in layout.bunkers:
		var inside := bunker.inside_point()
		if bunker.signed_distance(inside) < -1.0 and layout.hazard_at(inside) == null:
			interiors_ok = interiors_ok and layout.lie_surface_at(inside) == CourseLayout.SURFACE_BUNKER
		points.append(inside)
		for index in range(0, bunker.polygon.size(), maxi(1, bunker.polygon.size() / 8)):
			var a := bunker.polygon[index]
			var b := bunker.polygon[(index + 1) % bunker.polygon.size()]
			var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
			points.append((a + b) * 0.5 + normal * 0.1)
			points.append((a + b) * 0.5 - normal * 0.1)
	for hole in layout.holes:
		points.append(Vector2(hole.tee.x, hole.tee.z))
		points.append(Vector2(hole.cup.x, hole.cup.z))
	check(interiors_ok, "Sand interiors remain correct across all %d course bunkers" % layout.bunkers.size())
	# Same representative points and call count, alternating order to reduce bias.
	var geometric: Array[float] = []
	var visible: Array[float] = []
	var count := 12000
	for round_index in range(4):
		for use_visible in ([false, true] if round_index % 2 == 0 else [true, false]):
			var started := Time.get_ticks_usec()
			for index in range(count):
				var point := points[index % points.size()]
				if use_visible:
					layout.lie_surface_at(point)
				else:
					layout.surface_at(point)
			var per_lookup := float(Time.get_ticks_usec() - started) / count
			(visible if use_visible else geometric).append(per_lookup)
	geometric.sort()
	visible.sort()
	print("Lie lookup benchmark: geometry %.2f us, visible-edge %.2f us; %.4f ms per 120-Hz step" % [
		(geometric[1] + geometric[2]) * 0.5, (visible[1] + visible[2]) * 0.5, (visible[1] + visible[2]) * 0.0005])
	for excavation in layout.bunkers + layout.water_hazards:
		excavation.free()
