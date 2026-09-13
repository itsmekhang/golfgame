extends SceneTree

var failed := false

func _init() -> void:
	call_deferred('run')

func run() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(0, 0, 128, 64)
	var heights := PackedFloat32Array()
	heights.resize(65 * 65)
	for z in range(65):
		for x in range(65):
			heights[z * 65 + x] = 2.0 if x < 10 else 0.0
	layout.rendered_terrain.register_tile(Vector2i.ZERO, Vector2.ZERO, 1.0, 65, 65, heights)
	roll_case(layout, Vector2(9.97, 10.25), Vector3.RIGHT, 2.0, 30, 'Down a bunker lip onto its floor')
	roll_case(layout, Vector2(10.04, 10.25), Vector3.LEFT, 2.0, 25, 'Rolling into the foot of a bank')
	for z in range(65):
		for x in range(65):
			heights[z * 65 + x] = 2.0 if x >= 21 and z >= 21 else 0.0
	layout.rendered_terrain.register_tile(Vector2i.ZERO, Vector2.ZERO, 1.0, 65, 65, heights)
	roll_case(layout, Vector2(20.46, 20.46), Vector3(1, 0, 1).normalized(), 1.0, 30, 'Crossing a concave triangle diagonal')
	# Different mesh resolutions share a tile boundary; the sphere can straddle both.
	heights.fill(0.0)
	layout.rendered_terrain.register_tile(Vector2i.ZERO, Vector2.ZERO, 1.0, 65, 65, heights)
	var coarse := PackedFloat32Array()
	coarse.resize(33 * 33)
	coarse.fill(0.02)
	layout.rendered_terrain.register_tile(Vector2i(1, 0), Vector2(64, 0), 2.0, 33, 33, coarse)
	roll_case(layout, Vector2(63.94, 10.3), Vector3.RIGHT, 1.0, 30, 'Crossing a fine/coarse terrain seam')
	real_bunker_cases()
	print('ROLLING GROUND CONTACT: ', 'FAIL' if failed else 'PASS')
	quit(1 if failed else 0)

func roll_case(layout: CourseLayout, start: Vector2, direction: Vector3, speed: float, steps: int, label: String) -> void:
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	ball.log_level = PhysicsLogger.Level.OFF
	root.add_child(ball)
	ball.set_physics_process(false)
	ball.place(start)
	ball.putt(speed, direction)
	var clearance := INF
	var maximum_clearance := 0.0
	for step in range(steps):
		ball._step(GolfBall.DT)
		var gap := mesh_distance(layout.rendered_terrain, ball.position) - BallPhysics.RADIUS
		clearance = minf(clearance, gap)
		maximum_clearance = maxf(maximum_clearance, gap)
	if clearance < -0.0002:
		failed = true
		push_error('%s: sphere penetrates mesh by %.2f mm' % [label, -clearance * 1000.0])
	elif maximum_clearance > 0.003:
		failed = true
		push_error('%s: ball floats %.2f mm above the mesh' % [label, maximum_clearance * 1000.0])
	else:
		print('PASS ', label, ': minimum clearance %.2f mm' % (clearance * 1000.0))
	ball.free()

func real_bunker_cases() -> void:
	var layout := CourseBuilder.build(7)
	layout.rendered_terrain.origin = layout.bounds.position
	var tested := 0
	for index in [1, 8, 17]:
		var wanted: String = layout.holes[index].bunker_polys[0][0]
		var target := Excavation.centroid(layout.holes[index].bunker_polys[0][2])
		for bunker: Bunker in layout.bunkers:
			if bunker.center.distance_to(target) > 0.001:
				continue
			var rect := bunker.bounds.grow(4.0)
			var low := (rect.position - layout.bounds.position) / TerrainBuilder.TILE
			var high := (rect.end - layout.bounds.position) / TerrainBuilder.TILE
			for tz in range(int(floor(low.y)), int(floor(high.y)) + 1):
				for tx in range(int(floor(low.x)), int(floor(high.x)) + 1):
					var tile := TerrainBuilder.build_tile(layout, tx, tz, StandardMaterial3D.new())
					tile.free()
			var edge: Vector2 = bunker.polygon[bunker.polygon.size() / 4]
			var outward := (edge - bunker.center).normalized()
			roll_case(layout, edge + outward * 2.0, Vector3(-outward.x, 0, -outward.y), 6.0, 120, 'Actual mesh: ' + wanted)
			tested += 1
	if tested != 3:
		failed = true
		push_error('Did not exercise all three real bunker meshes')

## Independent check against the nearby mesh faces and their edges, not just the
## terrain height directly below the centre of the ball.
func mesh_distance(contact: TerrainContact, p: Vector3) -> float:
	var closest := INF
	for tile: Dictionary in contact.tiles.values():
		var start: Vector2 = tile.start
		var cell: float = tile.cell
		var width: int = tile.width
		var depth: int = tile.depth
		var box := Rect2(start, Vector2(width - 1, depth - 1) * cell)
		if not box.grow(0.05).has_point(Vector2(p.x, p.z)):
			continue
		var ix := int(floor((p.x - start.x) / cell))
		var iz := int(floor((p.z - start.y) / cell))
		var h: PackedFloat32Array = tile.heights
		for z in range(maxi(0, iz - 1), mini(depth - 2, iz + 1) + 1):
			for x in range(maxi(0, ix - 1), mini(width - 2, ix + 1) + 1):
				var a := Vector3(start.x + x * cell, h[z * width + x], start.y + z * cell)
				var b := Vector3(a.x + cell, h[z * width + x + 1], a.z)
				var c := Vector3(a.x, h[(z + 1) * width + x], a.z + cell)
				var d := Vector3(b.x, h[(z + 1) * width + x + 1], c.z)
				closest = minf(closest, triangle_distance(p, a, b, c))
				closest = minf(closest, triangle_distance(p, b, d, c))
	return closest

func triangle_distance(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a).normalized()
	var signed_plane := (p - a).dot(normal)
	var projected := p - normal * signed_plane
	var outline := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var closest := absf(signed_plane) if Geometry2D.is_point_in_polygon(Vector2(projected.x, projected.z), outline) else INF
	for edge in [[a, b], [b, c], [c, a]]:
		var v: Vector3 = edge[1] - edge[0]
		var t := clampf((p - edge[0]).dot(v) / v.length_squared(), 0.0, 1.0)
		closest = minf(closest, p.distance_to(edge[0] + v * t))
	return closest
