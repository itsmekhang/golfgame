class_name WaterHazardGenerator
extends RefCounted
## Randomly places water hazards on a course: ponds hugging the fairway edges
## in the landing zones, and creeks cutting across long holes. Deterministic
## for a given seed. Call before the terrain is built (hazards deform terrain).

const NAMES := ["Heron", "Mallard", "Willow", "Mirror", "Kettle", "Otter", "Reed", "Lily", "Beaver", "Crane", "Mill", "Stone"]

static var last_report: String = ""


## Appends hazards to `layout.water_hazards` and returns the ones added.
static func generate(layout: CourseLayout, seed_v: int, ponds_per_hole: int = 2,
		creek_chance: float = 0.4, min_pond_radius: float = 9.0, max_pond_radius: float = 22.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var added: Array = []
	var names := NAMES.duplicate()
	names.shuffle()
	var name_i := 0

	for hole in layout.holes:
		var length_m := hole.length_yd / ShotSetup.YARDS_PER_METER
		var want := rng.randi_range(1, maxi(1, ponds_per_hole))
		var placed := 0
		var attempts := 0
		while placed < want and attempts < 60:
			attempts += 1
			if length_m < 90.0:
				break
			var along := rng.randf_range(45.0, maxf(60.0, length_m - 40.0))
			var cl := centerline_point(hole, along)
			var p: Vector2 = cl[0]
			var dir: Vector2 = cl[1]
			var nrm := Vector2(-dir.y, dir.x)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var r := rng.randf_range(min_pond_radius, max_pond_radius)
			# Pond edge sits from 4 m inside the fairway edge to 10 m outside it.
			var lateral := hole.fairway_half_width + r + rng.randf_range(-4.0 - r * 0.3, 10.0)
			var c := p + nrm * side * lateral
			var aspect := rng.randf_range(0.7, 1.4)
			var rot := rng.randf_range(0.0, TAU)
			if not _site_ok(layout, c, r * maxf(aspect, 1.0), hole, added):
				continue
			var hz := WaterHazard.make_blob(c, r, rng, aspect, rot)
			hz.hazard_name = "%s Pond" % names[name_i % names.size()]
			name_i += 1
			hz.finalize(layout)
			layout.water_hazards.append(hz)
			added.append(hz)
			placed += 1

		# Creek crossing the fairway on longer holes
		if length_m > 220.0 and rng.randf() < creek_chance:
			for _try in range(15):
				var along := rng.randf_range(80.0, length_m - 70.0)
				var cl := centerline_point(hole, along)
				var p: Vector2 = cl[0]
				var dir: Vector2 = cl[1]
				var nrm := Vector2(-dir.y, dir.x).rotated(rng.randf_range(-0.5, 0.5))
				var half_len := hole.fairway_half_width + rng.randf_range(12.0, 30.0)
				var start := p - nrm * half_len
				var end := p + nrm * half_len
				var width := rng.randf_range(5.0, 9.0)
				if not _creek_ok(layout, start, end, width, hole, added):
					continue
				var hz := WaterHazard.make_creek(start, end, width, rng)
				hz.hazard_name = "%s Creek" % names[name_i % names.size()]
				name_i += 1
				hz.finalize(layout)
				layout.water_hazards.append(hz)
				added.append(hz)
				break

	last_report = "seed %d: %d hazards" % [seed_v, added.size()]
	for hz in added:
		last_report += "\n  %s at (%.0f, %.0f) area %.0f m2 level %.2f" % [hz.hazard_name, hz.center.x, hz.center.y, hz.area_m2(), hz.water_level]
	return added


## Point and direction on the hole centreline `along` metres from the tee.
static func centerline_point(hole: CourseLayout.Hole, along: float) -> Array:
	var pts: Array[Vector2] = [Vector2(hole.tee.x, hole.tee.z)]
	for wp in hole.waypoints:
		pts.append(Vector2(wp.x, wp.z))
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if acc + seg >= along or i == pts.size() - 1:
			var t := clampf((along - acc) / maxf(seg, 0.001), 0.0, 1.0)
			return [a.lerp(b, t), (b - a).normalized()]
		acc += seg
	return [pts[pts.size() - 1], Vector2(0, -1)]


static func _site_ok(layout: CourseLayout, c: Vector2, r: float, hole: CourseLayout.Hole, added: Array) -> bool:
	var b := layout.bounds.grow(-(r + 6.0))
	if not b.has_point(c):
		return false
	if not layout.hazard_site_ok(c, r):
		return false
	for h in layout.holes:
		if c.distance_to(Vector2(h.cup.x, h.cup.z)) < h.green_radius + r + 12.0:
			return false
		if c.distance_to(Vector2(h.tee.x, h.tee.z)) < r + 28.0:
			return false
		if h != hole:
			var fd: Array = layout.fairway_distance(h, c)
			if fd[0] < h.fairway_half_width + r * 0.5:
				return false
	for hz in layout.water_hazards:
		if hz.center.distance_to(c) < r + hz.bounds.size.length() * 0.5 + 6.0:
			return false
	if layout.bunker_near(c, r + 3.0):
		return false
	return true


static func _creek_ok(layout: CourseLayout, start: Vector2, end: Vector2, width: float, hole: CourseLayout.Hole, added: Array) -> bool:
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := start.lerp(end, t)
		if not layout.bounds.grow(-8.0).has_point(p):
			return false
		if not layout.hazard_site_ok(p, width):
			return false
		for h in layout.holes:
			if p.distance_to(Vector2(h.cup.x, h.cup.z)) < h.green_radius + 25.0:
				return false
			if p.distance_to(Vector2(h.tee.x, h.tee.z)) < 45.0:
				return false
		for hz in layout.water_hazards:
			if hz.contains(p) or hz.center.distance_to(p) < hz.bounds.size.length() * 0.5 + 8.0:
				return false
	return true
