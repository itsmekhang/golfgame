class_name RoughArea
extends CourseArea
## The rough: everything that is not mown turf, sand or water. Defined as the complement
## of the other areas, so its signed distance is minus the closest turf/hazard distance
## (positive deep inside a fairway, negative out in the long grass).

var layout: CourseLayout


func setup(p_layout: CourseLayout) -> void:
	layout = p_layout
	kind = PhysicsEnums.SurfaceType.ROUGH
	area_name = "Rough"
	bounds = layout.bounds


func signed_distance(p: Vector2) -> float:
	# distance to the nearest mown turf (fairway / first cut / green / fringe / tee)
	var best := layout.turf_signed_distance(p)
	for hz in layout.water_hazards:
		if hz.bounds.grow(4.0).has_point(p):
			best = minf(best, hz.signed_distance(p))
	for b in layout.bunkers:
		if b.bounds.grow(4.0).has_point(p):
			best = minf(best, b.signed_distance(p))
	return -best
