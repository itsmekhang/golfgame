class_name ShotPowerMeter
extends ProgressBar
## Segmented power meter in the shared HUD style (UITheme): a dark-glass track of cells that
## light up along a fixed red -> amber -> green scale as power rises, quarter marks, a gold
## full-power notch, and a glowing cursor riding the leading edge.

const COLOR_STOPS := [0.0, 0.08, 0.32, 0.60, 0.82, 1.0]
const POWER_COLORS := [
	Color(1.0, 0.345, 0.369, 0.0), Color("ff585e"), Color("ffa348"),
	Color("ffe16a"), Color("a4ef57"), Color("36e58c"),
]
const CELLS := 32
const GAP := 2.0


func _init() -> void:
	min_value = 0
	max_value = 100
	step = 0.01
	show_percentage = false
	custom_minimum_size = Vector2(360, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	value_changed.connect(func(_power: float) -> void: queue_redraw())


static func accent_color(power: float) -> Color:
	if power <= 0.0:
		return Color("dfedf2")
	var fraction := clampf(power / 100.0, 0.0, 1.0)
	for i in range(1, COLOR_STOPS.size()):
		if fraction <= COLOR_STOPS[i]:
			var blend := inverse_lerp(COLOR_STOPS[i - 1], COLOR_STOPS[i], fraction)
			var color: Color = POWER_COLORS[i - 1].lerp(POWER_COLORS[i], blend)
			color.a = 1.0
			return color
	return POWER_COLORS[-1]


func _draw() -> void:
	var fraction := clampf(float(value / max_value), 0.0, 1.0)
	# glass track
	draw_style_box(UITheme.box(Color(0.02, 0.04, 0.035, 0.62), Color(1, 1, 1, 0.16), 1, 8, 0), Rect2(Vector2.ZERO, size))
	var inner := Rect2(Vector2(5, 5), size - Vector2(10, 10))
	var cw := (inner.size.x - GAP * (CELLS - 1)) / CELLS
	var lit := fraction * CELLS
	for i in range(CELLS):
		var r := Rect2(inner.position.x + i * (cw + GAP), inner.position.y, cw, inner.size.y)
		draw_rect(r, Color(1, 1, 1, 0.07))
		var f := clampf(lit - i, 0.0, 1.0)
		if f > 0.0:
			# Each cell takes the scale's colour at its own position, so low power shows only red.
			var col := accent_color((i + 0.5) / CELLS * 100.0)
			draw_rect(Rect2(r.position, Vector2(cw * f, r.size.y)), col)
			draw_rect(Rect2(r.position, Vector2(cw * f, 2.0)), Color(1, 1, 1, 0.35))
	for mark in [0.25, 0.5, 0.75]:
		var x: float = roundf(inner.position.x + inner.size.x * mark)
		draw_line(Vector2(x, 1), Vector2(x, 4), Color(1, 1, 1, 0.55), 1.0, true)
		draw_line(Vector2(x, size.y - 4), Vector2(x, size.y - 1), Color(1, 1, 1, 0.55), 1.0, true)
	# full-power notch
	var end_x := inner.end.x + 2.0
	draw_line(Vector2(end_x, 2), Vector2(end_x, size.y - 2), UITheme.GOLD, 2.0, true)
	if value > 0.0:
		var x := inner.position.x + inner.size.x * fraction
		var glow := accent_color(value)
		draw_rect(Rect2(x - 5.0, 0.0, 10.0, size.y), Color(glow, 0.25))
		draw_line(Vector2(x, -3), Vector2(x, size.y + 3), Color(0.01, 0.04, 0.03, 0.85), 5.0, true)
		draw_line(Vector2(x, -3), Vector2(x, size.y + 3), Color.WHITE, 2.5, true)
