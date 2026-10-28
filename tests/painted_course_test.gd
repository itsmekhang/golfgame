extends SceneTree
## Course Studio data + game adapter (headless):
##   godot --headless --path . --script tests/painted_course_test.gd
## Paints a starter course, checks the brushes, save/load round trip, and that PaintedLayout
## reads back the painted surfaces as game lies (green at the pin, tee at the tee, sand,
## water, rough) with dug bunkers/water and traced woods.

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		failures += 1
		print("FAIL ", what)


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var c := PaintedCourse.starter("Test Links")
	print("[painted] starter built in %d ms" % (Time.get_ticks_msec() - t0))
	var hole: Dictionary = c.holes[0]
	var pin: Vector2 = hole["pin"]
	var tee: Vector2 = hole["tee"]
	check(c.surface_at(pin) == PaintedCourse.Surface.GREEN, "pin painted on green")
	check(c.surface_at(tee) == PaintedCourse.Surface.TEE, "tee painted")
	# the tee box is a rectangle squared to the line of play: its corners are tee, not rough
	var ctl := c.hole_controls(0)
	var dir := (ctl[1] - ctl[0]).normalized()
	var across := Vector2(-dir.y, dir.x)
	var corners := 0
	for s in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		if c.surface_at(tee + across * 4.0 * s[0] + dir * 5.2 * s[1]) == PaintedCourse.Surface.TEE:
			corners += 1
	check(corners == 4, "square tee box: all four corners are tee (%d)" % corners)
	check(c.surface_at(tee + across * 6.5) != PaintedCourse.Surface.TEE, "tee box stops at its side edge")
	check(c.surface_at(Vector2(10, -40)) == PaintedCourse.Surface.BUNKER, "bunker painted")
	check(c.surface_at(Vector2(-48, -70)) == PaintedCourse.Surface.WATER, "water painted")
	check(c.coverage(PaintedCourse.Surface.WOODS, Vector2(-72, 0)) > 0.5, "woods painted")
	check(c.issues().is_empty(), "starter course has no issues: %s" % [c.issues()])
	check(c.hole_par(0) == 4, "auto par 4 for %d yd" % c.hole_yards(0))
	# eraser + undo
	var probe := Vector2(10, -40)
	var snap := c.snapshot(c.brush_rect(probe, 12.0))
	c.paint(PaintedCourse.Surface.ROUGH, probe, 10.0, 1.0, 0.9)
	check(c.surface_at(probe) == PaintedCourse.Surface.ROUGH, "rough brush erases the bunker")
	c.restore(snap)
	check(c.surface_at(probe) == PaintedCourse.Surface.BUNKER, "undo restores the bunker")
	# sculpt
	var h0 := c.height_at(Vector2(100, 100))
	c.sculpt("raise", Vector2(100, 100), 10.0, 1.0, 0.5)
	check(c.height_at(Vector2(100, 100)) > h0 + 0.2, "raise brush lifts the ground")
	c.sculpt("flatten", Vector2(100, 100), 10.0, 1.0, 0.9, h0)
	check(absf(c.height_at(Vector2(100, 100)) - h0) < 0.05, "flatten brush levels to the target")
	# save / load
	var path := "user://_painted_course_test.course.json"
	check(c.save(path) == OK, "saved")
	var back := PaintedCourse.load_file(path)
	check(back != null and back.splat_a == c.splat_a and back.height == c.height and back.holes.size() == 1, "load round trip")
	DirAccess.remove_absolute(path)
	# game adapter
	t0 = Time.get_ticks_msec()
	var L := PaintedLayout.build(c)
	print("[painted] layout built in %d ms: %d bunkers, %d water, %d woods outlines" % [Time.get_ticks_msec() - t0, L.bunkers.size(), L.water_hazards.size(), L.holes[0].woods.size()])
	check(L.holes.size() == 1 and L.holes[0].par == 4, "one par-4 hole")
	check(L.surface_at(pin) == PhysicsEnums.SurfaceType.GREEN, "layout: green at the pin")
	check(L.surface_at(tee) == CourseLayout.SURFACE_TEE, "layout: tee at the tee")
	check(L.surface_at(Vector2(10, -40)) == CourseLayout.SURFACE_BUNKER, "layout: bunker lie")
	check(L.surface_at(Vector2(-48, -70)) == CourseLayout.SURFACE_WATER, "layout: water lie")
	check(L.surface_at(Vector2(-12, 0)) == PhysicsEnums.SurfaceType.FAIRWAY, "layout: fairway lie")
	check(L.surface_at(Vector2(200, 0)) == PhysicsEnums.SurfaceType.ROUGH, "layout: rough lie")
	var fringe_found := false
	for k in range(40):
		var p := pin + Vector2.from_angle(k * TAU / 40.0) * 14.8
		if L.surface_at(p) == CourseLayout.SURFACE_FRINGE:
			fringe_found = true
	check(fringe_found, "layout: fringe ring around the green")
	check(L.bunkers.size() == 2, "two bunkers traced (%d)" % L.bunkers.size())
	check(L.water_hazards.size() == 1, "one pond traced (%d)" % L.water_hazards.size())
	check(L.holes[0].woods.size() >= 2, "woods traced on both sides (%d)" % L.holes[0].woods.size())
	var sand := Vector2(10, -40)
	check(L.height_at(sand.x, sand.y) < c.height_at(sand) - 0.2, "bunker dug into the ground")
	var pond := Vector2(-48, -70)
	check(L.height_at(pond.x, pond.y) < c.height_at(pond) - 0.4, "pond bed dug")
	L.build_cache(TerrainBuilder.RESOLUTION, false)
	t0 = Time.get_ticks_msec()
	L.ensure_cache_rect(L.bounds)
	print("[painted] cache baked in %d ms" % (Time.get_ticks_msec() - t0))
	check(L.cached_surface(pin) == PhysicsEnums.SurfaceType.GREEN, "cache: green at the pin")
	L.build_feature_mask()
	check(L.lie_surface_at(sand) == CourseLayout.SURFACE_BUNKER, "lie via feature mask: bunker")
	print("DONE %d failures" % failures)
	quit(1 if failures > 0 else 0)
