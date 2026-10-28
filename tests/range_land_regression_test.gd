extends SceneTree
## Regression checks for expanded course data and full-size parking-lot grading.
var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	var c := PaintedCourse.create("Expansion regression", Vector2i(80, 60))
	for z in range(c.size.y):
		for x in range(c.size.x):
			var idx := z * c.size.x + x
			c.height[idx] = x * 0.12 + z * 0.08
			c.splat_a[idx * 4] = (x * 3 + z) % 256
			c.splat_b[idx * 4 + 1] = (x + z * 2) % 256
	c.holes = [{"tee": Vector2(-12, 18), "pin": Vector2(15, -20), "par": 3, "bends": [Vector2(2, 0)], "curve": true}]
	c.trees = [["white_oak_A", Vector2(-20, 10)]]
	var before := c.canvas_snapshot()
	var old_origin := c.origin
	var old_height := c.raw_height_at(Vector2(3.2, -4.6))
	check(c.expand_land(20), "Map expansion succeeds")
	check(c.size == Vector2i(120, 100) and c.origin == old_origin - Vector2(20, 20), "Map grows evenly")
	check(is_equal_approx(c.raw_height_at(Vector2(3.2, -4.6)), old_height), "World elevation stays put")
	check(c.holes == before["holes"] and c.trees == before["trees"], "Holes, bends and trees stay put")
	var kept := true
	for z in range(60):
		for x in range(80):
			var old_idx := z * 80 + x
			var new_idx := (z + 20) * 120 + x + 20
			kept = kept and c.height[new_idx] == before["h"][old_idx]
			for channel in range(4):
				kept = kept and c.splat_a[new_idx * 4 + channel] == before["a"][old_idx * 4 + channel]
				kept = kept and c.splat_b[new_idx * 4 + channel] == before["b"][old_idx * 4 + channel]
	check(kept, "Every original paint and height cell is preserved")
	check(c.surface_at(Vector2(55, 45)) == PaintedCourse.Surface.ROUGH, "Added land is rough")
	check(is_equal_approx(c.raw_height_at(Vector2(39.5, 0)), c.raw_height_at(Vector2(40.5, 0))), "No height seam at old boundary")
	var after := c.canvas_snapshot()
	c.restore(before)
	check(c.size == Vector2i(80, 60) and c.height == before["h"], "Expansion can be undone")
	c.restore(after)
	var loaded := PaintedCourse.from_dict(c.to_dict())
	check(loaded.size == c.size and loaded.origin == c.origin and loaded.height == c.height and loaded.holes == c.holes, "Expanded course saves and reloads")
	check(not c.expand_land(0) and not c.expand_land(-1), "Invalid expansion sizes leave the map alone")

	var g := PaintedCourse.create("Parking grade", Vector2i(300, 200))
	for z in range(g.size.y):
		for x in range(g.size.x):
			g.height[z * g.size.x + x] = x * 0.13 + sin(z * 0.1) * 2.0
	check(FacilityBuilder.footprint("parking_lot") == Vector2(66, 48), "Parking footprint matches the Blender asset")
	for angle in [0.0, 0.55, 1.2]:
		FacilityBuilder.grade(g, {"parking_lot": {"pos": Vector2.ZERO, "rot": angle}}, {"parking_lot": 4})
		var flat := g.height_at(Vector2.ZERO)
		var uniform := true
		for p in FacilityBuilder.samples("parking_lot", Vector2.ZERO, angle, 2.0):
			uniform = uniform and absf(g.height_at(p) - flat) < 0.001
		check(uniform, "Entire rotated parking lot sits on flat ground")
		var hm := g.height_image()
		for local in [Vector2(-33, -24), Vector2(33, -24), Vector2(-33, 24), Vector2(33, 24)]:
			var w := FacilityBuilder.to_world(Vector2.ZERO, angle, local.x, local.y)
			var cell := g.cell_of(w)
			check(absf(hm.get_pixel(int(cell.x), int(cell.y)).r - flat) < 0.001, "Rendered terrain is flat at parking corners")
	var left := {"pos": Vector2.ZERO, "rot": 0.0, "half": Vector2(10, 10), "h": 3.0}
	var right := {"pos": Vector2(24, 0), "rot": 0.0, "half": Vector2(10, 10), "h": 7.0}
	for order in [[left, right], [right, left]]:
		g.pads = order
		check(is_equal_approx(g.height_at(Vector2(9, 0)), 3.0) and is_equal_approx(g.height_at(Vector2(15, 0)), 7.0), "Neighbouring blend never tilts either flat pad")
	print("RANGE / LAND REGRESSION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
