extends SceneTree
## Headless dump of one or more holes' finished 2D features (turf areas, water, bunkers,
## woods, planted trees, rough islands, tee boxes, route) in each hole's own frame
## (origin = back tee, +x = toward the green centre, +y = golfer's right), as JSON for
## tools/plot_hole_features.py:
##   godot --headless --path . --script tools/dump_hole_features.gd -- build/holes.json 12 13 17

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "build/holes.json"
	var layout := CourseBuilder.build(7)
	var out := {}
	for k in range(1, args.size()):
		var n := int(args[k])
		var hole: CourseLayout.Hole = layout.holes[n - 1]
		var gc := hole.green_center
		# CourseBuilder's own frame for this hole (the traced JSON's local metres): every
		# hole runs due north or south, so pick the one that puts route point 1 back on its
		# waypoint, then solve the frame origin from the green centre.
		var spec: Dictionary = CourseBuilder._specs()[n - 1]
		var lg := CourseBuilder._v(spec["green"]["center"])
		var l1 := CourseBuilder._v(spec["route"][1])
		var w1 := Vector2(hole.waypoints[1].x, hole.waypoints[1].z)
		var fwd := Vector2(0, -1)
		var tee := Vector2.ZERO
		var best := INF
		for cand: Vector2 in [Vector2(0, -1), Vector2(0, 1)]:
			var r := Vector2(-cand.y, cand.x)
			var origin: Vector2 = gc - cand * lg.x - r * lg.y
			var err: float = (origin + cand * l1.x + r * l1.y).distance_to(w1)
			if err < best:
				best = err
				fwd = cand
				tee = origin
		var right := Vector2(-fwd.y, fwd.x)
		print("[dump] hole %d frame fit error %.2f m" % [n, best])
		var loc := func(p: Vector2) -> Array:
			var d := p - tee
			return [snappedf(d.dot(fwd), 0.1), snappedf(d.dot(right), 0.1)]
		var poly := func(pts: PackedVector2Array) -> Array:
			var a := []
			for p in pts:
				a.append(loc.call(p))
			return a
		var reach := tee.distance_to(gc) + 160.0
		var near := func(p: Vector2) -> bool:
			return p.distance_to(tee.lerp(gc, 0.5)) < reach
		var h := {"tee_world": [tee.x, tee.y], "fwd": [fwd.x, fwd.y], "water": [], "bunkers": [], "woods": [], "trees": [], "islands": [], "tees": [], "route": [], "heights": []}
		for hz in layout.water_hazards:
			if near.call(hz.center) or near.call(hz.polygon[0]) or near.call(hz.polygon[hz.polygon.size() / 2]):
				h["water"].append({"name": hz.hazard_name, "creek": hz.is_creek, "level": hz.water_level, "poly": poly.call(hz.polygon)})
		for bk in layout.bunkers:
			if near.call(bk.center):
				h["bunkers"].append({"name": bk.feature_name, "poly": poly.call(bk.polygon)})
		for other in layout.holes:
			for w in other.woods:
				if near.call(Excavation.centroid(w)):
					h["woods"].append(poly.call(w))
			for t in other.planted_trees:
				if near.call(t[1]):
					h["trees"].append([t[0]] + loc.call(t[1]))
			for isl in other.rough_islands:
				if near.call(isl[0]):
					h["islands"].append([loc.call(isl[0]), loc.call(isl[1]), isl[2], isl.size() < 4 or bool(isl[3])])
		for tb in hole.tee_boxes:
			h["tees"].append(loc.call(tb[0]))
		for wp in hole.waypoints:
			h["route"].append(loc.call(Vector2(wp.x, wp.z)))
		h["green_center"] = loc.call(gc)
		# Surface grid (for drawing fairway/green/rough) and heights, 4 m cells.
		var grid := []
		var x0 := -60.0
		var x1 := tee.distance_to(gc) + 90.0
		for ax in range(int(x0), int(x1), 4):
			for ay in range(-150, 151, 4):
				var p := tee + fwd * ax + right * ay
				grid.append([ax, ay, int(layout.surface_at(p)), snappedf(layout.height_at(p.x, p.y), 0.01)])
		h["grid"] = grid
		out[str(n)] = h
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[dump] wrote ", out_path)
	for hz in layout.water_hazards: hz.free()
	for bk in layout.bunkers: bk.free()
	quit(0)
