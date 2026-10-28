class_name Bunker
extends Excavation
## A sand bunker dug into the terrain: irregular polygon, sunken sand floor, and a small
## raised lip on the rim. The lie inside is `CourseLayout.SURFACE_BUNKER`; the terrain
## builder colours it sand.

var depth: float = 0.55  # floor below the rim at the middle
var lip: float = 0.03  # a whisker of turf lip at the edge (no berm: per user, bunkers read as volcanoes)
var rim_level: float = 0.0
var rim_lift: float = 0.0
var kind: String = "greenside"  # or "fairway"


func _init() -> void:
	feature_name = "Bunker"
	shore_width = 2.5


static func make_blob(p_center: Vector2, radius: float, rng: RandomNumberGenerator,
		aspect: float = 1.0, rotation_rad: float = 0.0) -> Bunker:
	var b := Bunker.new()
	b.surface_kind = CourseLayout.SURFACE_BUNKER
	b.set_polygon(Excavation.blob_polygon(p_center, radius, rng, aspect, rotation_rad, 16, 1.2))
	b.center = p_center
	b.depth = clampf(radius * 0.09, 0.35, 0.9)
	return b


static func from_polygon(pts: PackedVector2Array) -> Bunker:
	var b := Bunker.new()
	b.surface_kind = CourseLayout.SURFACE_BUNKER
	b.set_polygon(pts)
	b.depth = clampf(sqrt(b.area_m2() / PI) * 0.09, 0.35, 0.9)
	return b


func finalize(layout: CourseLayout) -> void:
	super.finalize(layout)
	rim_level = outline_levels(layout)["mean"] + rim_lift


## The bunker follows the natural ground: its edge stays at grade (plus a tiny lip, and
## `rim_lift` where a hole asks for a raised rim), and the sand floor sinks below it, levelled
## only gently toward the rim's mean height inside. Levelling the whole rim to that mean
## raised the downhill side into a berm, so bunkers stood up like volcanoes and kicked balls
## away instead of gathering them.
func depth_offset(base_h: float, xz: Vector2) -> float:
	if not bounds.has_point(xz):
		return 0.0
	var sd := signed_distance(xz)
	if sd >= shore_width:
		return 0.0
	var edge := lip + rim_lift
	if sd <= 0.0:
		var inside := -sd
		var level := clampf((rim_level - rim_lift - base_h) * 0.3, -depth * 0.6, depth * 0.6) * smoothstep(0.5, 3.0, inside)
		return edge + level - 0.2 * smoothstep(0.0, 0.8, inside) - depth * smoothstep(0.5, 3.5, inside)
	return edge * (1.0 - smoothstep(0.0, shore_width, sd))


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["kind"] = kind
	return d
