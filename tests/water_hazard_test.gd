extends SceneTree
## Headless test for random water hazards, bunkers and ball flagging.
## Run: godot --headless --path . --script tests/water_hazard_test.gd

var _water_hits: Array = []
var _bunker_hits: Array = []


func _init() -> void:
	PhysicsLogger.set_level(PhysicsLogger.Level.INFO)
	var failures := 0

	# 1. Generation is deterministic and respects greens/tees
	var layout := CourseBuilder.build(42)
	print(CourseBuilder.last_report)
	var base_count := layout.water_hazards.size()
	var added := WaterHazardGenerator.generate(layout, 42)
	print(WaterHazardGenerator.last_report)
	if added.is_empty():
		printerr("no hazards generated")
		failures += 1
	var layout2 := CourseBuilder.build(42)
	var added2 := WaterHazardGenerator.generate(layout2, 42)
	if added2.size() != added.size() or (added.size() > 0 and added[0].center != added2[0].center):
		printerr("generation not deterministic for the same seed")
		failures += 1
	var bunkers := BunkerGenerator.generate(layout, 43)
	print(BunkerGenerator.last_report)
	if bunkers.is_empty():
		printerr("no bunkers generated")
		failures += 1
	for hz in layout.water_hazards:
		for hole in layout.holes:
			if hz.contains(Vector2(hole.cup.x, hole.cup.z)) or hz.contains(Vector2(hole.tee.x, hole.tee.z)):
				printerr("hazard %s covers a tee or cup" % hz.hazard_name)
				failures += 1
		var ip: Vector2 = hz.inside_point()
		if not hz.contains(ip):
			printerr("hazard %s has no inside point" % hz.hazard_name)
			failures += 1
		var bed := layout.height_at(ip.x, ip.y)
		if bed >= hz.water_level:
			printerr("hazard %s bed (%.2f) is not below water level (%.2f)" % [hz.hazard_name, bed, hz.water_level])
			failures += 1
		if layout.surface_at(ip) != CourseLayout.SURFACE_WATER:
			printerr("hazard %s centre is not a water lie" % hz.hazard_name)
			failures += 1
	for b in layout.bunkers:
		var ip: Vector2 = b.inside_point()
		if layout.surface_at(ip) != CourseLayout.SURFACE_BUNKER:
			printerr("bunker %s centre is not a sand lie" % b.feature_name)
			failures += 1
		if layout.height_at(ip.x, ip.y) >= b.rim_level:
			printerr("bunker %s floor is not below its rim" % b.feature_name)
			failures += 1
	print("hazards: %d (authored %d + random %d), bunkers: %d" % [layout.water_hazards.size(), base_count, added.size(), layout.bunkers.size()])

	# 2. A ball dropped into a hazard is flagged
	var hz0: WaterHazard = added[0] if added.size() > 0 else layout.water_hazards[0]
	var ball := GolfBall.new()
	ball.layout = layout
	ball.log_level = PhysicsLogger.Level.INFO
	ball.resolve_surface = func(p: Vector3) -> Dictionary:
		var s := layout.surface_at(Vector2(p.x, p.z))
		return {"surface": s, "engine": CourseLayout.engine_surface(s), "source": "test"}
	ball.water_hazard_entered.connect(func(h, p): _water_hits.append([h, p]))
	ball.bunker_entered.connect(func(p, plugged): _bunker_hits.append([p, plugged]))
	root.add_child(ball)
	await process_frame
	var ip0: Vector2 = hz0.inside_point()
	var flagged := false
	for speed in [48.0, 52.0, 56.0, 44.0, 60.0, 40.0]:
		_water_hits.clear()
		ball.place(Vector2(ip0.x, ip0.y + 60.0))
		var dir := Vector3(ip0.x - ball.global_position.x, 0.0, ip0.y - ball.global_position.z).normalized()
		ball.launch(speed, 30.0, 6000.0, 0.0, dir)
		for i in range(60 * 25):
			ball._physics_process(1.0 / 60.0)
			if not ball.is_moving:
				break
		if ball.in_water and _water_hits.size() == 1 and _water_hits[0][0] == hz0:
			flagged = true
			print("ball flagged in %s after %.0f mph lob" % [hz0.hazard_name, speed])
			break
		print("  speed %.0f mph landed at %s lie=%s" % [speed, ball.global_position, CourseLayout.surface_label(ball.current_lie)])
	if not flagged:
		printerr("ball landing in hazard was not flagged")
		failures += 1

	# 3. Bunker detection: pitch into the first generated bunker
	var bk: Bunker = layout.bunkers[0]
	var bip: Vector2 = bk.inside_point()
	var bunker_flagged := false
	for speed in [30.0, 33.0, 27.0, 36.0, 24.0, 40.0]:
		_bunker_hits.clear()
		ball.place(Vector2(bip.x, bip.y + 25.0))
		var dir := Vector3(bip.x - ball.global_position.x, 0.0, bip.y - ball.global_position.z).normalized()
		ball.launch(speed, 35.0, 5000.0, 0.0, dir)
		for i in range(60 * 25):
			ball._physics_process(1.0 / 60.0)
			if not ball.is_moving:
				break
		if ball.in_bunker and _bunker_hits.size() == 1:
			bunker_flagged = true
			print("ball flagged in %s after %.0f mph pitch (plugged=%s)" % [bk.feature_name, speed, str(_bunker_hits[0][1])])
			break
		print("  bunker try %.0f mph -> lie=%s at %s" % [speed, CourseLayout.surface_label(ball.current_lie), ball.global_position])
	if not bunker_flagged:
		printerr("ball landing in bunker was not flagged")
		failures += 1

	if failures == 0:
		print("WATER HAZARD TEST: PASS")
		quit(0)
	else:
		printerr("WATER HAZARD TEST: FAIL (%d)" % failures)
		quit(1)
