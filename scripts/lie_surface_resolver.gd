class_name LieSurfaceResolver
extends RefCounted
## Owns surface precedence (mirrors OpenFairway's LieSurfaceResolver):
##   1. active SurfaceZone override
##   2. CourseLayout surface lookup at the world point
##   3. default surface

var layout: CourseLayout
var default_surface: int = PhysicsEnums.SurfaceType.FAIRWAY
var zones: Array[SurfaceZone] = []


func _init(p_layout: CourseLayout) -> void:
	layout = p_layout


func register_zones(tree: SceneTree) -> void:
	zones.clear()
	for n in tree.get_nodes_in_group("surface_zones"):
		if n is SurfaceZone:
			zones.append(n)


## Returns { "surface": gameplay surface id, "engine": PhysicsEnums.SurfaceType, "source": String }
func resolve(point: Vector3) -> Dictionary:
	for z in zones:
		if z.contains_point(point):
			return {"surface": z.surface_type, "engine": z.surface_type, "source": "zone_override"}
	if layout != null:
		var s := layout.surface_at(Vector2(point.x, point.z))
		return {"surface": s, "engine": CourseLayout.engine_surface(s), "source": "layout_lookup"}
	return {"surface": default_surface, "engine": default_surface, "source": "default"}
