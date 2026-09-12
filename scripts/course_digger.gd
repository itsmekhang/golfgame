class_name CourseDigger
extends RefCounted
## Build-time digging helpers (not exposed to the player). Used by generators, scripts and
## tests to add or remove bunkers and ponds on a live course; each call re-carves only the
## terrain and grass tiles it touches via `course.rebuild_area()`.

static var _rng := RandomNumberGenerator.new()


static func dig_bunker(course: Node, pos: Vector3, r: float, seed_v: int = 12345) -> Bunker:
	var layout: CourseLayout = course.layout
	_rng.seed = seed_v + layout.bunkers.size()
	var b := Bunker.make_blob(Vector2(pos.x, pos.z), r, _rng, _rng.randf_range(0.8, 1.4), _rng.randf_range(0.0, TAU))
	b.kind = "script"
	b.feature_name = "Bunker %d" % (layout.bunkers.size() + 1)
	b.finalize(layout)
	layout.bunkers.append(b)
	course.rebuild_area(b.bounds.grow(3.0))
	return b


static func dig_water(course: Node, pos: Vector3, r: float, seed_v: int = 12345) -> WaterHazard:
	var layout: CourseLayout = course.layout
	_rng.seed = seed_v + layout.water_hazards.size()
	var hz := WaterHazard.make_blob(Vector2(pos.x, pos.z), r, _rng, _rng.randf_range(0.8, 1.4), _rng.randf_range(0.0, TAU))
	hz.feature_name = "Pond %d" % (layout.water_hazards.size() + 1)
	hz.finalize(layout)
	layout.water_hazards.append(hz)
	course.hazards_root.add_child(hz)
	hz.build_visual()
	course.rebuild_area(hz.bounds.grow(3.0))
	return hz


## Remove the bunker or pond within 4 m of a world position. Returns true if one was removed.
static func remove_at(course: Node, pos: Vector3) -> bool:
	var layout: CourseLayout = course.layout
	var xz := Vector2(pos.x, pos.z)
	for i in range(layout.bunkers.size()):
		var b: Bunker = layout.bunkers[i]
		if b.signed_distance(xz) < 4.0:
			layout.bunkers.remove_at(i)
			course.rebuild_area(b.bounds.grow(3.0))
			return true
	for i in range(layout.water_hazards.size()):
		var hz: WaterHazard = layout.water_hazards[i]
		if hz.signed_distance(xz) < 4.0:
			layout.water_hazards.remove_at(i)
			var rect := hz.bounds.grow(3.0)
			hz.queue_free()
			course.rebuild_area(rect)
			return true
	return false


static func export_features(layout: CourseLayout) -> Dictionary:
	var bunkers := []
	for b in layout.bunkers:
		bunkers.append(b.to_dict())
	var ponds := []
	for hz in layout.water_hazards:
		ponds.append(hz.to_dict())
	return {"bunkers": bunkers, "ponds": ponds}
