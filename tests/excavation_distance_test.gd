extends SceneTree
## Compare the accelerated query to the original exhaustive outline scan.

var failures := 0

func reference(shape: Excavation, p: Vector2) -> float:
	var best := INF
	for i in range(shape.polygon.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, shape.polygon[i], shape.polygon[(i + 1) % shape.polygon.size()])
		best = minf(best, q.distance_to(p))
	return -best if Geometry2D.is_point_in_polygon(p, shape.polygon) else best

func compare(shape: Excavation, points: PackedVector2Array) -> void:
	for p in points:
		var expected := reference(shape, p)
		var actual := shape.signed_distance(p)
		if absf(expected - actual) > 0.00001:
			failures += 1
			printerr("Distance changed at %s: %s -> %s" % [p, expected, actual])

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := CourseBuilder.build(7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98123
	var shapes: Array = []
	shapes.append_array(layout.bunkers)
	shapes.append_array(layout.water_hazards)
	var old_usec := 0
	var new_usec := 0
	for shape: Excavation in shapes:
		var points := PackedVector2Array()
		var area := shape.bounds.grow(30.0)
		for i in range(250):
			points.append(Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)))
		for i in range(0, shape.polygon.size(), maxi(1, shape.polygon.size() / 12)):
			points.append(shape.polygon[i])
			points.append(shape.polygon[i].lerp(shape.polygon[(i + 1) % shape.polygon.size()], 0.5))
		compare(shape, points)
		var started := Time.get_ticks_usec()
		for p in points:
			reference(shape, p)
		old_usec += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		for p in points:
			shape.signed_distance(p)
		new_usec += Time.get_ticks_usec() - started
	# Replacing and reversing an outline must rebuild its segment bounds.
	var edited := Excavation.new()
	edited.set_polygon(PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]))
	edited.set_polygon(PackedVector2Array([Vector2(-2, -2), Vector2(0, 5), Vector2(2, -2)]))
	compare(edited, PackedVector2Array([Vector2.ZERO, Vector2(20, 20), Vector2(0, -2)]))
	edited.set_polygon(PackedVector2Array([Vector2.ONE, Vector2.ONE]))
	compare(edited, PackedVector2Array([Vector2.ZERO, Vector2.ONE]))
	edited.free()
	for shape in shapes:
		shape.free()
	print("EXCAVATION DISTANCE: %s (%d failures); exhaustive %.1f ms, grouped %.1f ms" % ["PASS" if failures == 0 else "FAIL", failures, old_usec / 1000.0, new_usec / 1000.0])
	quit(1 if failures else 0)
