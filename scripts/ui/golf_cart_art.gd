class_name GolfCartArt
extends Control
## Vector illustration shared by the live animation and the preview exporter.
## No particle spawns, sprite sheets, shaders or 3D viewport are needed.

const WalkRig = preload("res://scripts/ui/golf_walk_rig.gd")

const BoardRig = preload("res://scripts/ui/golf_boarding_rig.gd")

const DESIGN_SIZE := Vector2(1280, 720)
const PAPER := Color("f4f3e8")
const INK := Color("193b32")
const MUTED := Color("73857a")
const GREEN := Color("2e6950")
const GOLD := Color("cfa765")
const SKIN := Color("cb946b")
const BOOT := Color("263d35")
const WALK_END := BoardRig.WALK_END
const HOP_END := BoardRig.SETTLED
const DRIVE_START := BoardRig.DRIVE_START
const TORSO_POINTS := [Vector2(-15, 0), Vector2(-13, -38), Vector2(-3, -45), Vector2(12, -41), Vector2(17, -7), Vector2(14, 2)]

var elapsed := 0.0
var departure := -1.0
var progress := -1.0
var ready_to_play := false
var initial_load := false
var hole_number := 2
var hole_name := "Pink Dogwood"
var hole_par := 5
var hole_yards := 585
var stage_text := "Your next fairway awaits."
var commands: Array = []
var _origin := Vector2.ZERO
var _rotation := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var scale_factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var offset := (size - DESIGN_SIZE * scale_factor) * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_set_transform(offset, 0.0, Vector2.ONE * scale_factor)
	for command: Dictionary in build_commands():
		var color := Color(command["color"])
		match command["kind"]:
			"polygon":
				draw_colored_polygon(_vectors(command["points"]), color)
			"line":
				draw_polyline(_vectors(command["points"]), color, command["width"], true)
			"text":
				var font := ThemeDB.fallback_font
				var text_value: String = command["text"]
				var font_size: int = command["size"]
				var at := Vector2(command["x"], command["y"])
				if command.get("center", false):
					at.x -= font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
				draw_string(font, at, text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO)

static func _vectors(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for value in values:
		points.append(Vector2(value[0], value[1]))
	return points

func _point(point: Vector2) -> Array:
	var transformed := point.rotated(_rotation) + _origin
	return [transformed.x, transformed.y]

func _poly(points: Array, color: Color) -> void:
	var output: Array = []
	for point in points:
		output.append(_point(point))
	commands.append({"kind": "polygon", "points": output, "color": "#" + color.to_html()})

func _line(points: Array, color: Color, width: float = 3.0) -> void:
	var output: Array = []
	for point in points:
		output.append(_point(point))
	commands.append({"kind": "line", "points": output, "color": "#" + color.to_html(), "width": width})

func _ellipse(center: Vector2, radius: Vector2, color: Color, segments: int = 40) -> void:
	var points: Array = []
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_poly(points, color)

func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var points: Array = []
	var centers := [rect.position + Vector2(radius, radius), Vector2(rect.end.x - radius, rect.position.y + radius), rect.end - Vector2(radius, radius), Vector2(rect.position.x + radius, rect.end.y - radius)]
	for corner in range(4):
		for i in range(7):
			var angle := PI + corner * PI * 0.5 + i * PI / 12.0
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	_poly(points, color)

func _text(text_value: String, at: Vector2, font_size: int, color: Color, centered: bool = true) -> void:
	commands.append({"kind": "text", "text": text_value, "x": at.x, "y": at.y, "size": font_size, "color": "#" + color.to_html(), "center": centered})

static func smooth_step(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _limb(points: Array, color: Color, width: float) -> void:
	_line(points, color, width)
	for point: Vector2 in points:
		_ellipse(point, Vector2.ONE * width * 0.5, color, 12)

func pose() -> Dictionary:
	var walk := clampf(elapsed / WALK_END, 0.0, 1.0)
	var hop := clampf((elapsed - WALK_END) / (HOP_END - WALK_END), 0.0, 1.0)
	var drive := maxf(elapsed - DRIVE_START, 0.0)
	var depart := 0.0 if departure < 0.0 else pow(clampf(departure, 0.0, 1.0), 1.75) * 1040.0
	return {"walk": walk, "hop": hop, "drive": drive, "depart": depart,
		"cart_x": 730.0 + sin(minf(drive, 1.0) * PI * 0.5) * 35.0 + depart,
		"cart_y": 493.0 + (sin(drive * 14.0) * 1.1 if drive > 0.0 else 0.0)}

func build_commands() -> Array:
	commands = []
	_origin = Vector2.ZERO
	_rotation = 0.0
	var current := pose()
	var drive: float = current["drive"]
	_background(drive)
	# Soft ground shadow anchors the cart and changes as it leaves the screen.
	_ellipse(Vector2(current["cart_x"], 502), Vector2(150, 12), Color("263d3520"))
	var joints := _boarding_pose(current)
	# While approaching from screen-left, the cart stays in the foreground.
	if elapsed < WALK_END:
		_golfer(joints)
		_origin = Vector2(current["cart_x"], current["cart_y"])
		_cart_back(drive)
	else:
		# At the open driver entrance the rear bench sits behind the driver.
		_origin = Vector2(current["cart_x"], current["cart_y"])
		_cart_back(drive)
		_golfer(joints)
	_origin = Vector2(current["cart_x"], current["cart_y"])
	_cart_body(drive)
	_cart_front(drive)
	_origin = Vector2.ZERO
	_title_and_progress()
	return commands

func _background(drive: float) -> void:
	_round_rect(Rect2(0, 0, 1280, 720), 0.0, PAPER)
	# Very pale sun, soft cloud banks and distant tree lines.
	_ellipse(Vector2(990, 236), Vector2.ONE * 39.0, Color("eee4c5"))
	for cloud: Vector3 in [Vector3(285, 276, 1.0), Vector3(940, 304, 0.7), Vector3(1090, 364, 0.5)]:
		var cx := cloud.x - fmod(drive * 7.0, 30.0)
		_ellipse(Vector2(cx, cloud.y), Vector2(46, 10) * cloud.z, Color("ffffff80"))
		_ellipse(Vector2(cx - 12 * cloud.z, cloud.y - 10 * cloud.z), Vector2(20, 15) * cloud.z, Color("ffffff80"))
	# Organic layered rolling hills; all remain inside the 1280x720 safe composition.
	_ellipse(Vector2(438, 446), Vector2(300, 83), Color("dce5d6"))
	_ellipse(Vector2(865, 454), Vector2(290, 68), Color("d1dfcd"))
	_ellipse(Vector2(716, 474), Vector2(450, 43), Color("bed2b5"))
	_ellipse(Vector2(662, 507), Vector2(505, 18), Color("dee5d6"))
	# A subtly curved cart path, drawn as a wide stroked line.
	_line([Vector2(160, 497), Vector2(410, 492), Vector2(690, 502), Vector2(1117, 494)], Color("e9dfc7"), 23.0)
	_line([Vector2(162, 503), Vector2(410, 498), Vector2(690, 508), Vector2(1118, 500)], Color("ded2b6"), 2.0)
	for i in range(7):
		var x := 190.0 + fposmod(i * 151.0 - drive * 92.0, 960.0)
		_line([Vector2(x, 498), Vector2(x + 22, 498)], Color("f7f0df"), 2.0)
	# Background flag and two trees establish the destination.
	var flag_x := 1004.0 - fmod(drive * 13.0, 44.0)
	_ellipse(Vector2(flag_x, 460), Vector2(65, 14), Color("91b08b"))
	_line([Vector2(flag_x, 456), Vector2(flag_x, 358)], Color("526b58"), 3.0)
	_poly([Vector2(flag_x, 358), Vector2(flag_x + 34, 366), Vector2(flag_x + 4, 384), Vector2(flag_x, 382)], Color("cc775e"))
	for tree: Vector3 in [Vector3(216, 457, 0.9), Vector3(1083, 455, 0.75)]:
		var tx := tree.x - fmod(drive * 11.0, 32.0)
		_line([Vector2(tx, tree.y), Vector2(tx, tree.y - 70 * tree.z)], Color("8b9d85"), 5 * tree.z)
		_ellipse(Vector2(tx - 14 * tree.z, tree.y - 65 * tree.z), Vector2(27, 32) * tree.z, Color("b0c6ab"))
		_ellipse(Vector2(tx + 12 * tree.z, tree.y - 87 * tree.z), Vector2(26, 35) * tree.z, Color("bed0b7"))
		_ellipse(Vector2(tx + 28 * tree.z, tree.y - 63 * tree.z), Vector2(23, 29) * tree.z, Color("a8c0a1"))
	# Sparse moving tufts, with a fixed count for the whole animation.
	for i in range(10):
		var x := 185.0 + fposmod(i * 97.0 - drive * 112.0, 950.0)
		var y := 523.0 + sin(i * 2.7) * 4.0
		_line([Vector2(x - 4, y - 3), Vector2(x, y), Vector2(x + 4, y - 5)], Color("afc0a3"), 2.0)

func _outlined_poly(points: Array, color: Color, width: float = 2.0) -> void:
	_poly(points, color)
	var border := points.duplicate()
	border.append(points[0])
	_line(border, INK, width)

func _cart_back(drive: float) -> void:
	# Rear luggage rack and golf bag, on the far side of the boarding path.
	_line([Vector2(-139, -23), Vector2(-114, -23), Vector2(-100, -48)], INK, 5)
	_rotation = -0.10
	_round_rect(Rect2(-135, -113, 28, 91), 7, Color("b58452"))
	_round_rect(Rect2(-137, -112, 32, 8), 3, GOLD)
	_round_rect(Rect2(-134, -76, 26, 9), 3, Color("dfbd83"))
	for i in range(3):
		var x := -131.0 + i * 10.0
		_line([Vector2(x, -107), Vector2(x + 1, -149 - i * 4)], Color("7d918a"), 3)
		_round_rect(Rect2(x - 7, -155 - i * 4, 17, 8), 3, Color("bbc9c0"))
	_rotation = 0.0
	# Far roof posts and faint windscreen, always behind the driver.
	_line([Vector2(-94, -158), Vector2(-81, -48)], INK, 5)
	_poly([Vector2(77, -153), Vector2(100, -67), Vector2(80, -57), Vector2(61, -153)], Color("d6e5d670"))
	# One rear bench. The backrest sits behind the pelvis, never across the legs.
	_line([Vector2(-50, -44), Vector2(-45, -18)], INK, 5)
	_line([Vector2(13, -44), Vector2(18, -18)], INK, 5)
	_outlined_poly([Vector2(-64, -87), Vector2(-54, -88), Vector2(-46, -80), Vector2(-38, -54), Vector2(-41, -46), Vector2(-51, -46), Vector2(-56, -55)], Color("d8bd92"))
	_outlined_poly([Vector2(-45, -51), Vector2(13, -51), Vector2(23, -47), Vector2(23, -40), Vector2(-44, -40), Vector2(-50, -44)], Color("f0dfba"))
	_line([Vector2(-43, -48), Vector2(14, -48)], Color("fff2d7"), 2)
	# Slanted steering column and wheel: the driver's right hand reaches this.
	_line([Vector2(76, -19), Vector2(45, -69)], INK, 5)
	_line([Vector2(30, -65), Vector2(62, -76)], INK, 5)
	if drive > 0.0:
		for i in range(3):
			var x := -150.0 - fposmod(drive * 73.0 + i * 20.0, 64.0)
			_line([Vector2(x, -4 - i * 6), Vector2(x + 12, -4 - i * 6)], Color("c4b79660"), 3)

func _wheel_arch(center: Vector2) -> Array:
	var points: Array = []
	for index in range(13):
		var angle := lerpf(-0.4, -PI + 0.4, index / 12.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * 32.0)
	return points

func _cart_body(drive: float) -> void:
	# Continuous low chassis with an open central footwell, like the references.
	_outlined_poly([Vector2(-129, -20), Vector2(132, -20), Vector2(132, -10), Vector2(-129, -10)], INK)
	_outlined_poly([Vector2(-126, -20), Vector2(-117, -39), Vector2(-107, -48), Vector2(-43, -48), Vector2(-35, -40), Vector2(-35, -19)] + _wheel_arch(Vector2(-90, -7)), Color("438d82"))
	_line([Vector2(-108, -43), Vector2(-51, -43)], Color("7fb2a1"), 3)
	# Front hood slopes forward; its inner edge leaves room for feet on the floor.
	_outlined_poly([Vector2(59, -20), Vector2(79, -57), Vector2(94, -52), Vector2(113, -40), Vector2(134, -24), Vector2(134, -18)] + _wheel_arch(Vector2(95, -7)), Color("438d82"))
	_line([Vector2(83, -52), Vector2(105, -39), Vector2(123, -26)], Color("93c1ae"), 3)
	_round_rect(Rect2(-33, -19, 91, 7), 2, Color("ccbda0"))
	_round_rect(Rect2(126, -32, 12, 8), 3, Color("fff1c9"))
	_round_rect(Rect2(-135, -22, 16, 11), 3, INK)
	_round_rect(Rect2(127, -22, 16, 11), 3, INK)
	# Near-side bodywork and wheels remain in front of the walking/boarding rig.
	for x: float in [-90.0, 95.0]:
		var center := Vector2(x, -7)
		_ellipse(center, Vector2.ONE * 27, INK)
		_ellipse(center, Vector2.ONE * 23, BOOT)
		_ellipse(center, Vector2.ONE * 17, Color("ded7c0"))
		_ellipse(center, Vector2.ONE * 12, Color("9baba0"))
		for i in range(4):
			var angle := drive * 6.5 + i * PI * 0.5
			_line([center + Vector2(cos(angle), sin(angle)) * 6, center + Vector2(cos(angle), sin(angle)) * 13], Color("fbf4df"), 2)
		_ellipse(center, Vector2.ONE * 5, INK, 16)
	_ellipse(Vector2(-52, -32), Vector2(7, 6), GOLD, 20)

func _cart_front(_drive: float) -> void:
	# Only the outside windscreen post and roof belong in front of the driver.
	_line([Vector2(73, -157), Vector2(101, -46)], INK, 5)
	_outlined_poly([Vector2(-128, -159), Vector2(-124, -164), Vector2(-98, -170), Vector2(-43, -174), Vector2(48, -173), Vector2(102, -168), Vector2(124, -162), Vector2(127, -156), Vector2(-127, -156)], Color("eee4c9"))
	_line([Vector2(-120, -156), Vector2(122, -156)], GREEN, 5)
	_line([Vector2(-115, -164), Vector2(-76, -168), Vector2(42, -168), Vector2(102, -164)], Color("fff6df"), 2)

func _boarding_pose(current: Dictionary) -> Dictionary:
	return BoardRig.sample(elapsed, Vector2(current["cart_x"], current["cart_y"]))

static func torso_outline(joints: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in TORSO_POINTS:
		points.append((joints["hip"] as Vector2) + point.rotated(joints["lean"]))
	return points

func _shoe(ankle: Vector2, roll: float, color: Color) -> void:
	var points: Array = []
	for point: Vector2 in WalkRig.SHOE_POINTS:
		points.append(ankle + point.rotated(roll))
	_poly(points, color)

func _golfer(joints: Dictionary) -> void:
	_origin = Vector2.ZERO
	_rotation = 0.0
	var hip: Vector2 = joints["hip"]
	var shadow := 1.0 - BoardRig.blend(elapsed, BoardRig.FOOT_ON_STEP, BoardRig.SIT_END)
	if shadow > 0.0:
		_ellipse(Vector2(hip.x, 503), Vector2(21, 4), Color(0.15, 0.24, 0.21, 0.11 * shadow), 24)
	_limb([joints["far_hip"], joints["far_knee"], joints["far_ankle"]], Color("a69372"), 11)
	_shoe(joints["far_ankle"], joints["far_roll"], Color("ecebdb"))
	_limb([joints["near_hip"], joints["near_knee"], joints["near_ankle"]], Color("c0ad88"), 12)
	_shoe(joints["near_ankle"], joints["near_roll"], Color("fffbed"))
	_limb([joints["far_shoulder"], joints["far_elbow"], joints["far_hand"]], Color("b78260"), 9)
	_rigid_torso_and_head(hip, joints["lean"])
	_limb([joints["near_shoulder"], joints["near_elbow"]], GREEN, 12)
	_limb([joints["near_elbow"], joints["near_hand"]], SKIN, 9)

func _rigid_torso_and_head(hip: Vector2, lean: float) -> void:
	# Every point stays the same distance from the hip: rotation, never squash.
	_origin = hip
	_rotation = lean
	var shoulder := Vector2(2, -38)
	_poly(TORSO_POINTS, GREEN)
	_poly([shoulder + Vector2(-5, -7), shoulder + Vector2(0, 2), shoulder + Vector2(7, -5), shoulder + Vector2(3, -9)], Color("faf4df"))
	_line([Vector2(-12, 0), Vector2(14, 0)], Color("705f46"), 3)
	_round_rect(Rect2(shoulder + Vector2(1, -16), Vector2(11, 13)), 3, SKIN)
	var head := shoulder + Vector2(7, -25)
	_ellipse(head, Vector2(13, 16), SKIN, 32)
	_ellipse(head + Vector2(-10, 2), Vector2(4, 5), Color("bc825f"), 16)
	_poly([head + Vector2(10, -1), head + Vector2(18, 4), head + Vector2(11, 6)], SKIN)
	_ellipse(head + Vector2(7, -3), Vector2.ONE * 1.5, INK, 12)
	_line([head + Vector2(6, 9), head + Vector2(11, 8)], Color("9d674a"), 1.5)
	_round_rect(Rect2(head + Vector2(-15, -17), Vector2(29, 12)), 6, Color("fffae8"))
	_round_rect(Rect2(head + Vector2(-3, -8), Vector2(29, 5)), 2, Color("e2d5b6"))
	_line([head + Vector2(-10, -8), head + Vector2(0, -8)], GREEN, 3)

	_origin = Vector2.ZERO
	_rotation = 0.0

func _title_and_progress() -> void:
	# Minimal club mark.
	_line([Vector2(516, 48), Vector2(516, 65)], GREEN, 2)
	_poly([Vector2(516, 48), Vector2(532, 52), Vector2(516, 57)], GOLD)
	_ellipse(Vector2(516, 68), Vector2(9, 2), Color("bfccb8"), 20)
	_text("A Z A L E A   H I L L S", Vector2(657, 62), 17, INK)
	_text("A great round starts here." if initial_load else "On to the next hole.", Vector2(640, 135), 38, INK)
	_text("HEADING TO HOLE %02d" % hole_number, Vector2(640, 180), 13, MUTED)
	_text(hole_name, Vector2(640, 216), 25, GREEN)
	_text("PAR %d    ·    %d YD" % [hole_par, hole_yards], Vector2(640, 245), 14, MUTED)
	var caption := "Your next fairway awaits."
	if elapsed < WALK_END:
		caption = "Time for the next tee."
	elif elapsed < BoardRig.FOOT_ON_STEP:
		caption = "Step aboard."
	elif elapsed < HOP_END:
		caption = "Take a seat."
	elif elapsed < DRIVE_START:
		caption = "All set."
	else:
		caption = "See you on the tee."
	_text(caption, Vector2(640, 575), 22, INK)
	_round_rect(Rect2(500, 601, 280, 4), 2, Color("dce3d4"))
	if progress >= 0.0:
		_round_rect(Rect2(500, 601, maxf(4.0, 280.0 * clampf(progress, 0, 1)), 4), 2, GREEN)
	else:
		var x := 500.0 + (sin(elapsed * 1.8 - PI * 0.5) + 1.0) * 100.0
		_round_rect(Rect2(x, 601, 80, 4), 2, GREEN)
	_text("Ready for the tee" if ready_to_play else stage_text, Vector2(640, 632), 13, MUTED)
	if ready_to_play:
		_text("SPACE TO CONTINUE", Vector2(640, 685), 11, MUTED)
