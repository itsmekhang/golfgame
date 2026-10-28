class_name TeeArea
extends CourseArea
## Tee box: a rounded rectangle aligned with the first shot's direction.

var center: Vector2 = Vector2.ZERO
var half: Vector2 = Vector2(4.0, 5.0)  # across, along
var dir: Vector2 = Vector2(0.0, -1.0)  # direction of play
var corner: float = 1.5
var additional_boxes: Array[TeeArea] = []


func setup(p_center: Vector2, p_dir: Vector2, p_hole: int, p_half: Vector2 = Vector2(4.0, 5.0)) -> void:
	center = p_center
	dir = p_dir.normalized() if p_dir != Vector2.ZERO else Vector2(0.0, -1.0)
	hole_index = p_hole
	half = p_half
	kind = CourseLayout.SURFACE_TEE
	var r := half.length() + corner + 2.0
	bounds = Rect2(center - Vector2.ONE * r, Vector2.ONE * r * 2.0)


func add_box(p_center: Vector2, p_dir: Vector2, p_half: Vector2) -> void:
	var box := TeeArea.new()
	box.setup(p_center, p_dir, hole_index, p_half)
	additional_boxes.append(box)
	bounds = bounds.merge(box.bounds)


func signed_distance(p: Vector2) -> float:
	var sd := box_signed_distance(p)
	for box in additional_boxes:
		sd = minf(sd, box.signed_distance(p))
	return sd


## Distance to this individual platform, without the other tee boxes.
func box_signed_distance(p: Vector2) -> float:
	var v := p - center
	var right := Vector2(-dir.y, dir.x)
	var local := Vector2(v.dot(right), v.dot(dir))
	var q := local.abs() - half + Vector2.ONE * corner
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner
