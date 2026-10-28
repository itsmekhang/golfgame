class_name ClubSwingRig
extends Node3D
## Animates the currently equipped club's real 3D model through a backswing,
## downswing/impact and follow-through near the ball -- no golfer model; the
## club pivots on its own from an invisible point roughly where the player's
## hands would be at address. Uses OFGEquipmentAssets.create_club(), the same
## adapter the Inspect-mode viewer uses, so the club shown here is the exact
## model (including the Selected_Club_Heads driver/fairway/hybrid swaps).
##
## Geometry: every catalog club model has a "..__grip_anchor" (or, failing
## that, "..__grip") marker roughly where the hands sit on the grip. The club
## is parented under `_pivot` at local position -grip_local, so the grip sits
## exactly on the pivot; the rig root is then placed at
## `ball_pos + rig_basis * (grip_local + address_offset)`, which leaves a small
## visual clearance behind the ball at address/impact.
## Swinging is then just animating the pivot's local X rotation -- a horizontal
## axis perpendicular to the aim direction -- through back, down and through.

const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")

const BACK_ANGLE_DEG := 100.0     # backswing: how far up and back the club travels
const THROUGH_ANGLE_DEG := 100.0  # follow-through: how far past impact it continues
const BACKSWING_TIME := 0.22
const DOWNSWING_TIME := 0.10      # address(back) -> impact: the fast part of a real swing
const THROUGH_TIME := 0.20
# A putting stroke is a short, gentle rock of the shoulders, not a full swing;
# using the same ~100 degree arc for a two-foot putt would look absurd.
const PUTT_BACK_ANGLE_DEG := 14.0
const PUTT_THROUGH_ANGLE_DEG := 16.0
const PUTT_BACKSWING_TIME := 0.18
const PUTT_DOWNSWING_TIME := 0.14
const PUTT_THROUGH_TIME := 0.16

# The visual club is deliberately a little below and behind the ball at address.
# Imported iron and wedge heads have a deeper rear shell than the old stock meshes;
# placing their pivot exactly at the ball centre lets that shell intersect the ball
# from the play camera. These are local rig coordinates: +Z is back toward the
# camera because the rig's -Z axis follows the aim direction.
# The driver's sits as low as the turf clubs' (its sole on the ground under a ball resting on the tee box:
# 4.5 cm down, the golfer stood off it had the driver's sole and their heels ~2.5 cm into the ground),
# further back for its bigger head.
const ADDRESS_DISPLAY_OFFSET := Vector3(0.0, -0.020, 0.085)
# Lift the clubs played from turf by 2.5 cm and bring them 3.5 cm closer to the
# ball than the original display offset, while retaining some face clearance.
const TURF_ADDRESS_DISPLAY_OFFSET := Vector3(0.0, -0.020, 0.050)
# Give putter soles another centimetre of clearance above the turf.
const PUTTER_ADDRESS_DISPLAY_OFFSET := Vector3(0.0, -0.010, 0.050)

var _pivot: Node3D
var _club: Node3D
var _asset_id := ""
var _grip_local := Vector3.ZERO
var _address_offset := ADDRESS_DISPLAY_OFFSET
var _tween: Tween
## Swings and putts are played by the animated golfer (GolferRig) holding the club; this rig's
## own club-only stroke is the fallback when the golfer (or its putting clip) is missing.
var _golfer: GolferRig
var _golfer_mode := false
var _family := ""


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	if GolferRig.available():
		_golfer = GolferRig.new()
		_golfer.name = "Golfer"
		add_child(_golfer)


static func _find_suffix(node: Node, suffix: String) -> Node3D:
	if node is Node3D and String(node.name).ends_with(suffix):
		return node
	for child in node.get_children():
		var found := _find_suffix(child, suffix)
		if found != null:
			return found
	return null


static func _origin_relative_to(node: Node3D, ancestor: Node3D) -> Vector3:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result.origin


func _clear_club() -> void:
	if _club != null:
		_club.free()
		_club = null
	_asset_id = ""


## Swaps in a new club model when the asset id changes; a no-op otherwise (called
## every frame while idle, so switching clubs mid-aim shows the new one at once).
func _ensure_club(asset_id: String, condition: float) -> bool:
	if asset_id == _asset_id and _club != null:
		return true
	_clear_club()
	if asset_id.is_empty():
		return false
	var club := Equipment.create_club(asset_id, condition, AdminAccess.is_admin())
	if club == null:
		return false
	var grip := _find_suffix(club, "__grip_anchor")
	if grip == null:
		grip = _find_suffix(club, "__grip")
	if grip == null:
		club.free()
		return false
	_pivot.add_child(club)
	_grip_local = _origin_relative_to(grip, club)
	club.position = -_grip_local
	_club = club
	_asset_id = asset_id
	var family := str(Equipment.catalog().get(asset_id, {}).get("family", ""))
	_family = family
	_address_offset = TURF_ADDRESS_DISPLAY_OFFSET if family in ["iron", "wedge", "fairway", "hybrid"] else ADDRESS_DISPLAY_OFFSET
	if family == "putter":
		_address_offset = PUTTER_ADDRESS_DISPLAY_OFFSET
	return true


## Rest pose: club hanging at address, facing `aim`, head just behind `ball_pos`. Call every
## frame while a shot has not been committed; it tracks aim and club changes and
## follows the ball to a new lie between shots. Hides itself if no visual model is
## available for the equipped club (e.g. the plain stock bag with no save file).
func show_at_address(asset_id: String, condition: float, ball_pos: Vector3, aim: Vector3, distance_yd: float = INF) -> void:
	if not _ensure_club(asset_id, condition):
		hide_club()
		return
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_pivot.rotation = Vector3.ZERO
	var forward := Vector3(aim.x, 0.0, aim.z)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	basis = Basis.looking_at(forward, Vector3.UP)
	global_position = ball_pos + basis * (_grip_local + _address_offset)
	_golfer_mode = _golfer != null and (_family != "putter" or _golfer.has_clip("putt"))
	_pivot.visible = not _golfer_mode
	if _golfer != null:
		_golfer.visible = _golfer_mode
	if _golfer_mode:
		# the club head rests where this rig would have put its own club head
		_golfer.show_at_address(asset_id, condition, ball_pos + basis * _address_offset, forward, distance_yd)


func hide_club() -> void:
	visible = false
	if _tween != null and _tween.is_valid():
		_tween.kill()


## Plays backswing -> downswing -> impact -> follow-through, calling `on_impact`
## the instant the club reaches the ball (address angle) on the way down, then
## hides itself once follow-through finishes. Does not move or reposition the
## rig itself; call show_at_address() beforehand to set it up at the ball.
func swing(on_impact: Callable, is_putt: bool = false) -> void:
	if _club == null:
		on_impact.call()
		return
	if _golfer_mode:
		_golfer.swing(on_impact)
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var back := PUTT_BACK_ANGLE_DEG if is_putt else BACK_ANGLE_DEG
	var through := PUTT_THROUGH_ANGLE_DEG if is_putt else THROUGH_ANGLE_DEG
	var t_back := PUTT_BACKSWING_TIME if is_putt else BACKSWING_TIME
	var t_down := PUTT_DOWNSWING_TIME if is_putt else DOWNSWING_TIME
	var t_through := PUTT_THROUGH_TIME if is_putt else THROUGH_TIME
	_tween = create_tween()
	_tween.tween_property(_pivot, "rotation:x", deg_to_rad(-back), t_back)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_pivot, "rotation:x", 0.0, t_down)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(on_impact)
	_tween.tween_property(_pivot, "rotation:x", deg_to_rad(through), t_through)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(hide_club)
