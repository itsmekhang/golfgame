class_name PinIndicator
extends Control
## Horizon-inspired waypoint: an upright flag emblem with live yardage, in the shared HUD
## palette (UITheme: green glass disc, gold accent, Bahnschrift numerals).
## Canvas drawing is cached until the displayed distance changes.

const DESIGN_SIZE := Vector2(116, 118)
const SYMBOL_CENTER := Vector2(58, 36)
const ACCENT := UITheme.GOLD

var _font: Font = UITheme.font(700, 92)
var _distance := "0"

func _init() -> void:
	custom_minimum_size = DESIGN_SIZE
	size = DESIGN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_distance(yards: float) -> void:
	var label := "%.1f" % maxf(yards, 0.0) if yards < 10.0 else "%.0f" % yards
	if label != _distance:
		_distance = label
		queue_redraw()

func _ellipse(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(64):
		var angle := TAU * i / 64.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radii)
	return points

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var line := points.duplicate()
	line.append(points[0])
	return line

func _draw() -> void:
	# Fine white rim and restrained colour accent stay legible over sky and trees.
	draw_circle(SYMBOL_CENTER + Vector2(0, 2), 33, Color(0, 0, 0, 0.16), true, -1, true)
	var disc := _ellipse(SYMBOL_CENTER, Vector2(31, 31))
	var shades := PackedColorArray()
	for point in disc:
		shades.append(Color("1d3a30").lerp(Color("0b1713"), (point.y - 5) / 62.0))
	draw_polygon(disc, shades)
	draw_arc(SYMBOL_CENTER, 31, 0, TAU, 96, Color(1, 1, 1, 0.88), 1.4, true)
	draw_arc(SYMBOL_CENTER, 34, deg_to_rad(22), deg_to_rad(145), 40, ACCENT, 2.6, true)
	draw_arc(SYMBOL_CENTER, 28, deg_to_rad(205), deg_to_rad(310), 32, Color(1, 1, 1, 0.12), 1.0, true)

	# An inset cup, brushed pole and softly folded ivory flag give the symbol depth.
	var cup := _ellipse(Vector2(53, 58), Vector2(12, 3.4))
	draw_colored_polygon(cup, Color("0c151d"))
	draw_polyline(_closed(cup), Color("8a9fad"), 1.0, true)
	draw_line(Vector2(47, 15), Vector2(47, 59), Color("12202d"), 4.5, true)
	draw_line(Vector2(47, 15), Vector2(47, 59), Color("aebdc9"), 2.6, true)
	draw_line(Vector2(46.4, 15), Vector2(46.4, 58), Color("f4f8fa"), 1.0, true)
	draw_circle(Vector2(47, 14), 2.2, Color("eef3f7"), true, -1, true)

	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	const FOLDS := 24
	for i in range(FOLDS + 1):
		var t := float(i) / FOLDS
		var crest := 20.0 - sin(t * TAU) * 3.2
		upper.append(Vector2(48 + t * 29, crest))
		lower.append(Vector2(48 + t * 29, crest + 17.5 - t * 1.5))
	for i in range(FOLDS):
		var shade := 0.85 + 0.14 * cos(float(i) / FOLDS * TAU + 0.5)
		var cloth := PackedVector2Array([upper[i], upper[i + 1], lower[i + 1], lower[i]])
		draw_polygon(cloth, PackedColorArray([Color(shade, shade, shade), Color(shade, shade, shade), Color(shade * 0.83, shade * 0.88, shade * 0.94), Color(shade * 0.83, shade * 0.88, shade * 0.94)]))
		var hem := PackedVector2Array([lower[i] - Vector2(0, 2.2), lower[i + 1] - Vector2(0, 2.2), lower[i + 1], lower[i]])
		draw_colored_polygon(hem, ACCENT.darkened((1.0 - shade) * 1.5))
	draw_polyline(upper, Color("ffffff"), 1.0, true)
	draw_polyline(lower, Color(0, 0, 0, 0.22), 1.0, true)
	draw_line(upper[-1], lower[-1], Color("d7e0e7"), 1.0, true)

	draw_line(Vector2(58, 72), Vector2(58, 78), Color(1, 1, 1, 0.65), 1.0, true)
	var number_width := _font.get_string_size(_distance, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var unit_width := _font.get_string_size("yd", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var text_x := (DESIGN_SIZE.x - number_width - unit_width - 5) * 0.5
	draw_string_outline(_font, Vector2(text_x, 102), _distance, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 2, Color(0.01, 0.025, 0.018, 0.85))
	draw_string_outline(_font, Vector2(text_x + number_width + 5, 101), "yd", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 2, Color.WHITE)
	draw_string(_font, Vector2(text_x, 102), _distance, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(_font, Vector2(text_x + number_width + 5, 101), "yd", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
