extends SceneTree
## Headless test of the build-time digging helpers: digs a bunker and a pond on Willow Creek, checks the lie,
## the terrain carve, the local tile rebuild and removal.
## Run: godot --headless --path . --script tests/dig_test.gd

func _init() -> void:
	var inst = (load("res://scenes/course.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	for i in range(600):
		await process_frame
		if inst.ball != null and inst.hud != null and inst.active_region.size != Vector2.ZERO:
			break
	await process_frame
	var failures := 0
	var layout: CourseLayout = inst.layout
	# a spot in the rough beside hole 1's fairway
	var hole: CourseLayout.Hole = layout.holes[0]
	var spot := Vector3(hole.tee.x + 45.0, 0.0, hole.tee.z - 120.0)
	spot.y = layout.height_at(spot.x, spot.z)
	var before_h := spot.y
	var before_s := layout.cached_surface(Vector2(spot.x, spot.z))
	print("spot surface before: ", CourseLayout.surface_label(before_s))
	var tiles_before: int = inst.terrain_root.get_child_count() if inst.terrain_root != null else 0

	var b := CourseDigger.dig_bunker(inst, spot, 7.0)
	var after_s := layout.cached_surface(Vector2(spot.x, spot.z))
	var after_h := layout.height_at(spot.x, spot.z)
	var tiles_after: int = inst.terrain_root.get_child_count() if inst.terrain_root != null else 0
	print("bunker: surface=%s  height %.2f -> %.2f  tiles %d -> %d" % [CourseLayout.surface_label(after_s), before_h, after_h, tiles_before, tiles_after])
	if after_s != CourseLayout.SURFACE_BUNKER:
		printerr("dug bunker is not a bunker lie")
		failures += 1
	if after_h > before_h - 0.2:
		printerr("bunker did not carve the terrain")
		failures += 1
	await process_frame
	if inst.terrain_root != null and inst.terrain_root.get_child_count() != tiles_before:
		printerr("tile count changed after rebuild")
		failures += 1

	var spot2 := Vector3(hole.tee.x - 60.0, 0.0, hole.tee.z - 200.0)
	spot2.y = layout.height_at(spot2.x, spot2.z)
	var hz := CourseDigger.dig_water(inst, spot2, 12.0)
	var s2 := layout.cached_surface(Vector2(spot2.x, spot2.z))
	print("pond: surface=%s level %.2f bed %.2f" % [CourseLayout.surface_label(s2), hz.water_level, layout.height_at(spot2.x, spot2.z)])
	if s2 != CourseLayout.SURFACE_WATER or layout.height_at(spot2.x, spot2.z) >= hz.water_level:
		printerr("dug pond is wrong")
		failures += 1
	if hz.get_node_or_null("WaterSurface") == null:
		printerr("pond has no water mesh")
		failures += 1

	# ball dropped into the fresh pond is flagged
	var ball: GolfBall = inst.ball
	ball.skip_obstacles = true  # the pond sits in the fill forest beside hole 1; this tests water, not trees
	var hits := []
	ball.water_hazard_entered.connect(func(h, p): hits.append(h))
	var pond_c: Vector2 = hz.inside_point()
	for speed in [40.0, 36.0, 44.0, 32.0, 48.0, 28.0]:
		hits.clear()
		ball.place(Vector2(pond_c.x, pond_c.y + 40.0))
		var dir := Vector3(pond_c.x - ball.global_position.x, 0.0, pond_c.y - ball.global_position.z).normalized()
		ball.launch(speed, 32.0, 5000.0, 0.0, dir)
		for i in range(60 * 20):
			ball._physics_process(1.0 / 60.0)
			if not ball.is_moving:
				break
		print("lob %.0f mph -> lie %s, hits %d" % [speed, CourseLayout.surface_label(ball.current_lie), hits.size()])
		if hits.size() == 1 and hits[0] == hz:
			break
	if hits.size() != 1 or hits[0] != hz:
		printerr("ball not flagged in the hand-dug pond")
		failures += 1

	if not CourseDigger.remove_at(inst, spot):
		printerr("remove_at failed")
		failures += 1
	if layout.cached_surface(Vector2(spot.x, spot.z)) == CourseLayout.SURFACE_BUNKER:
		printerr("bunker still present after removal")
		failures += 1
	var exp := CourseDigger.export_features(layout)
	print("export: %d bunkers, %d ponds" % [exp["bunkers"].size(), exp["ponds"].size()])

	if failures == 0:
		print("DIG TEST: PASS")
		quit(0)
	else:
		printerr("DIG TEST: FAIL (%d)" % failures)
		quit(1)
