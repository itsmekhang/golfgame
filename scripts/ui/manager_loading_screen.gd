class_name ManagerLoadingScreen
extends CanvasLayer
## Course Manager's loading screen, in the hole loading screen's look (GolfLoadingScreen,
## UITheme): the dark studio backdrop with a flag waving on its pin, the club's name (filled in
## once its course is read), the business clock, a row of the club's numbers, a rotating
## manager tip, the stage being loaded and a slim gold progress bar. It fades away on its own
## a moment after the load is done (Space or a click once it's ready); nothing underneath
## takes input while it's up.
##
## Contract (course_manager.gd): add it -> await covered -> update_progress() / set_club() ...
## -> mark_ready() -> await ride_finished.

signal covered
signal ride_finished

@export var minimum_ride_time := 1.2  # seconds a finished load stays up before fading

const BACKDROP = preload("res://shaders/inspect_backdrop.gdshader")
const FADE_IN := 0.25
const FADE_OUT := 0.45
const TIP_SECONDS := 4.5
const TIPS := [
	"Press V, or use the view buttons, to lift the roof off and watch your staff at work.",
	"While placing a building, Q and E turn it. A placed building turns from its card.",
	"A full parking lot caps your golfers: upgrade the lot as the course grows.",
	"Each greenskeeper keeps about four holes in shape. Good turf raises your appeal.",
	"Price the green fee near the fair price. Much higher and the golfers stay away.",
	"The short game area warms up your golfers and draws locals who pay to practise.",
	"A marshal keeps play moving, so more tee times fit into the day.",
	"Time away still earns a share of your takings, for up to four hours.",
	"Rooms and facilities that need staff earn nothing until you hire someone.",
]

var progress := 0.0
var elapsed := 0.0

var _root: Control
var _info: VBoxContainer
var _club: Label
var _clock: Label
var _tiles: HBoxContainer
var _tip_label: Label
var _flag: Control
var _bar: Control
var _caption: Label
var _status_label: Label
var _goal := 0.0
var _tip_index := 0
var _tip_timer := 0.0
var _covered := false
var _ready_to_go := false
var _ready_at := 0.0
var _skip := false
var _leaving := false
var _exit := 0.0
var _done := false
var _info_x := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ShaderMaterial.new()
	backdrop.shader = BACKDROP
	backdrop.set_shader_parameter("accent", UITheme.GO.lightened(0.15))
	backdrop.set_shader_parameter("glow", 0.55)
	backdrop.set_shader_parameter("focus", Vector2(0.72, 0.5))
	backdrop.set_shader_parameter("floor_amount", 0.0)
	bg.material = backdrop
	_root.add_child(bg)

	# a flag on its pin, right, waving
	_flag = Control.new()
	_flag.anchor_left = 0.62
	_flag.anchor_right = 0.92
	_flag.anchor_top = 0.16
	_flag.anchor_bottom = 0.8
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flag.draw.connect(_draw_flag)
	_root.add_child(_flag)

	# the club, left
	_info = VBoxContainer.new()
	_info.anchor_left = 0.08
	_info.anchor_right = 0.58
	_info.anchor_top = 0.5
	_info.anchor_bottom = 0.5
	_info.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info.add_theme_constant_override("separation", 10)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info)
	UITheme.eyebrow(_info, "Course Manager", UITheme.GOLD)
	_club = UITheme.label(_info, "Your golf club", 58, Color.WHITE, 700, 88)
	_club.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_club.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_club.add_theme_constant_override("shadow_offset_y", 4)
	var accent := ColorRect.new()
	accent.color = UITheme.GOLD
	accent.custom_minimum_size = Vector2(64, 3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(accent)
	_clock = UITheme.label(_info, "", 16, UITheme.DIM, 600, 100)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 10)
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_tiles)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	_info.add_child(gap)
	var tip_box := PanelContainer.new()
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := UITheme.glass(16, 12)
	tip_style.border_width_left = 3
	tip_style.border_color = Color(UITheme.GOLD, 0.6)
	tip_box.add_theme_stylebox_override("panel", tip_style)
	_info.add_child(tip_box)
	var tip_col := VBoxContainer.new()
	tip_col.add_theme_constant_override("separation", 4)
	tip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_box.add_child(tip_col)
	UITheme.eyebrow(tip_col, "Tip", UITheme.GOLD)
	_tip_index = randi() % TIPS.size()
	_tip_label = UITheme.label(tip_col, TIPS[_tip_index], 15, UITheme.TEXT, 500)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size.x = 380
	_info_x = _info.offset_left

	# progress bar + stage + status, bottom
	_bar = Control.new()
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.anchor_right = 1.0
	_bar.offset_left = 48
	_bar.offset_right = -48
	_bar.offset_top = -58
	_bar.offset_bottom = -54
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)
	_caption = UITheme.label(_root, "OPENING THE CLUB…", 13, UITheme.DIM, 600, 100, 1)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 48
	_caption.offset_top = -44
	_caption.offset_bottom = -22
	_status_label = UITheme.label(_root, "LOADING  0%", 13, UITheme.DIM, 600, 100, 2)
	_status_label.anchor_left = 1.0
	_status_label.anchor_right = 1.0
	_status_label.anchor_top = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.offset_right = -48
	_status_label.offset_top = -46
	_status_label.offset_bottom = -20
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN


## The club's name (once its course is read), the business clock and its numbers.
func set_club(club_name: String, clock: String, tiles: Array) -> void:
	if club_name != "":
		_club.text = club_name
	_clock.text = clock
	for c in _tiles.get_children():
		_tiles.remove_child(c)
		c.queue_free()
	for t: Array in tiles:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", UITheme.glass(14, 9))
		_tiles.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		UITheme.eyebrow(v, str(t[0]))
		UITheme.label(v, str(t[1]), 24, Color.WHITE, 700, 92)


func update_progress(value: float, caption: String = "") -> void:
	_goal = maxf(_goal, clampf(value, 0.0, 1.0))
	if caption != "" and _caption != null:
		_caption.text = caption.to_upper()


func mark_ready() -> void:
	_goal = 1.0
	_ready_to_go = true
	_ready_at = elapsed


func _process(delta: float) -> void:
	if _done:
		return
	var step := minf(delta, 0.1)
	elapsed += step
	if not _covered:
		_root.modulate.a = minf(elapsed / FADE_IN, 1.0)
		if elapsed >= FADE_IN:
			_covered = true
			covered.emit()
	_info.modulate.a = clampf((elapsed - 0.1) / 0.4, 0.0, 1.0)
	var w := _info.offset_right - _info.offset_left
	_info.offset_left = _info_x + lerpf(40.0, 0.0, ease(clampf((elapsed - 0.1) / 0.5, 0.0, 1.0), 0.3))
	_info.offset_right = _info.offset_left + w
	progress = move_toward(progress, _goal, step * 1.5)
	_bar.queue_redraw()
	_flag.queue_redraw()
	_status_label.text = "WELCOME BACK" if _ready_to_go and progress >= 0.999 else "LOADING  %d%%" % roundi(progress * 100.0)
	if _ready_to_go and progress >= 0.999:
		_status_label.add_theme_color_override("font_color", UITheme.GOLD)
	_tip_timer += step
	if _tip_timer >= TIP_SECONDS:
		_tip_timer = 0.0
		_tip_index += 1
		_tip_label.text = TIPS[_tip_index % TIPS.size()]
	if _ready_to_go and not _leaving and progress >= 0.999 and (elapsed - _ready_at >= minimum_ride_time or _skip):
		_leaving = true
	if _leaving:
		_exit += step
		var k := clampf(_exit / FADE_OUT, 0.0, 1.0)
		_root.modulate.a = 1.0 - k
		_root.pivot_offset = _root.size * 0.5
		_root.scale = Vector2.ONE * (1.0 + 0.03 * k)
		if k >= 1.0:
			_done = true
			ride_finished.emit()


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08))
	var fill := w * clampf(progress, 0.0, 1.0)
	if fill > 0.0:
		_bar.draw_rect(Rect2(0, 0, fill, h), UITheme.GOLD)
		_bar.draw_rect(Rect2(fill - 30.0, -3.0, 30.0, h + 6.0), Color(UITheme.GOLD, 0.18))
		_bar.draw_circle(Vector2(fill, h * 0.5), 4.0, Color.WHITE, true, -1.0, true)


## A pin in its cup on a sliver of green, the flag rippling in the breeze.
func _draw_flag() -> void:
	var s := _flag.size
	var h := minf(s.y, s.x * 1.4)
	var base := Vector2(s.x * 0.42, s.y * 0.92)
	var top := base - Vector2(0, h * 0.86)
	# the green and the cup
	var green := PackedVector2Array()
	for i in range(48):
		var a := TAU * i / 48.0
		green.append(base + Vector2(cos(a) * h * 0.42, sin(a) * h * 0.06))
	_flag.draw_colored_polygon(green, Color(UITheme.GO, 0.18))
	_flag.draw_polyline(green + PackedVector2Array([green[0]]), Color(UITheme.GO.lightened(0.3), 0.35), 1.5, true)
	var cup := PackedVector2Array()
	for i in range(24):
		var a := TAU * i / 24.0
		cup.append(base + Vector2(cos(a) * h * 0.035, sin(a) * h * 0.012))
	_flag.draw_colored_polygon(cup, Color(0, 0, 0, 0.55))
	# the pin
	_flag.draw_line(base, top, Color(1, 1, 1, 0.85), maxf(2.0, h * 0.008), true)
	# the flag: a strip off the top of the pin, a travelling ripple growing toward the fly
	var fw := h * 0.36
	var fh := h * 0.2
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var n := 18
	for i in range(n + 1):
		var u := float(i) / n
		var wave := sin(u * 7.0 - elapsed * 4.2) * h * 0.022 * u + sin(u * 13.0 - elapsed * 6.3) * h * 0.007 * u
		var droop := u * u * h * 0.02
		upper.append(top + Vector2(u * fw, wave + droop))
		lower.append(top + Vector2(u * fw * 0.97, fh + wave * 1.15 + droop * 1.3))
	var poly := upper.duplicate()
	for i in range(n, -1, -1):
		poly.append(lower[i])
	_flag.draw_colored_polygon(poly, UITheme.GOLD)
	# a soft shade down each ripple
	for i in range(n):
		var u := float(i) / n
		var shade := 0.5 + 0.5 * sin(u * 7.0 - elapsed * 4.2 + 1.2)
		var quad := PackedVector2Array([upper[i], upper[i + 1], lower[i + 1], lower[i]])
		_flag.draw_colored_polygon(quad, Color(0, 0, 0, 0.16 * shade))
	_flag.draw_circle(top, maxf(2.5, h * 0.01), Color.WHITE, true, -1.0, true)


func _input(event: InputEvent) -> void:
	if _done:
		return
	if _ready_to_go and ((event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE)
			or (event is InputEventMouseButton and event.pressed)):
		_skip = true
	# nothing reaches the manager underneath while the screen is up
	get_viewport().set_input_as_handled()
