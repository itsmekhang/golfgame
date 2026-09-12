class_name BunkerGenerator
extends RefCounted
## Digs bunkers around a course: greenside bunkers hugging each green and fairway
## bunkers in the driving landing zone. Deterministic per seed. Skips water hazards,
## tees, and existing bunkers. Call before the terrain cache is built.

static var last_report: String = ""


static func generate(layout: CourseLayout, seed_v: int, greenside_max: int = 3, fairway_chance: float = 0.7) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var added: Array = []
	for hole in layout.holes:
		var cup := Vector2(hole.cup.x, hole.cup.z)
		var tee := Vector2(hole.tee.x, hole.tee.z)
		var length_m := hole.length_yd / ShotSetup.YARDS_PER_METER
		# direction of approach into the green
		var prev: Vector3 = hole.waypoints[hole.waypoints.size() - 2] if hole.waypoints.size() >= 2 else hole.tee
		var approach := (cup - Vector2(prev.x, prev.z)).normalized()

		# Greenside: 1..greenside_max, biased to the front-left/front-right and sides
		var n := rng.randi_range(1, maxi(1, greenside_max))
		var used_angles: Array[float] = []
		for k in range(n):
			for _try in range(12):
				var ang := atan2(approach.y, approach.x) + PI + rng.randf_range(-1.2, 1.2)  # around the front
				if rng.randf() < 0.35:
					ang = atan2(approach.y, approach.x) + (PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5) + rng.randf_range(-0.4, 0.4)
				var clash := false
				for a in used_angles:
					if absf(angle_difference(a, ang)) < 0.8:
						clash = true
				if clash:
					continue
				var r := rng.randf_range(3.5, 6.5)
				var dist := hole.green_radius + r + rng.randf_range(1.0, 4.0)
				var c := cup + Vector2(cos(ang), sin(ang)) * dist
				if not _site_ok(layout, c, r, hole):
					continue
				var b := Bunker.make_blob(c, r, rng, rng.randf_range(0.7, 1.5), ang)
				b.kind = "greenside"
				b.feature_name = "%s greenside bunker %d" % [hole.name, k + 1]
				b.finalize(layout)
				layout.bunkers.append(b)
				added.append(b)
				used_angles.append(ang)
				break

		# Fairway bunker in the landing zone of par 4/5
		if hole.par >= 4 and length_m > 250.0 and rng.randf() < fairway_chance:
			for _try in range(12):
				var along := rng.randf_range(200.0, minf(260.0, length_m - 60.0))
				var cl := WaterHazardGenerator.centerline_point(hole, along)
				var p: Vector2 = cl[0]
				var dir: Vector2 = cl[1]
				var nrm := Vector2(-dir.y, dir.x)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var r := rng.randf_range(5.0, 9.0)
				var c := p + nrm * side * (hole.fairway_half_width + r * rng.randf_range(0.2, 0.8))
				if not _site_ok(layout, c, r, hole):
					continue
				var b := Bunker.make_blob(c, r, rng, rng.randf_range(1.2, 2.0), atan2(dir.y, dir.x))
				b.kind = "fairway"
				b.feature_name = "%s fairway bunker" % hole.name
				b.finalize(layout)
				layout.bunkers.append(b)
				added.append(b)
				break
	last_report = "seed %d: %d bunkers" % [seed_v, added.size()]
	return added


static func _site_ok(layout: CourseLayout, c: Vector2, r: float, hole: CourseLayout.Hole) -> bool:
	if not layout.bounds.grow(-(r + 5.0)).has_point(c):
		return false
	if not layout.hazard_site_ok(c, r):
		return false
	if layout.hazard_near(c, r + 3.0):
		return false
	for b in layout.bunkers:
		if b.center.distance_to(c) < r + sqrt(b.area_m2() / PI) + 2.0:
			return false
	for h in layout.holes:
		if c.distance_to(Vector2(h.tee.x, h.tee.z)) < r + 15.0:
			return false
		if c.distance_to(Vector2(h.cup.x, h.cup.z)) < h.green_radius + r * 0.6:
			return false
		if h != hole:
			var fd: Array = layout.fairway_distance(h, c)
			if fd[0] < h.fairway_half_width + r:
				return false
	return true
