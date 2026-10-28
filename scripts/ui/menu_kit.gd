class_name MenuKit
extends RefCounted
## Buttons, sliders and panels for the start menu and the Course Studio, built on UITheme so
## they match the HUD and the Clubhouse (dark glass, Bahnschrift, green primary action).


## A flat button: `style` "primary" (green), "ghost" (glass), "danger" (red: confirms a
## delete) or "tool" (toggle, accent edge).
static func button(parent: Node, text: String, style: String = "ghost", size: int = 15, accent: Color = UITheme.GO) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", UITheme.font(650, 100, 1))
	b.add_theme_font_size_override("font_size", size)
	var solid := style in ["primary", "danger"]
	var tint := UITheme.LOSS.darkened(0.3) if style == "danger" else UITheme.GO
	var base := tint if solid else Color(1, 1, 1, 0.06)
	var edge := tint.lightened(0.25) if solid else Color(1, 1, 1, 0.12)
	var normal := UITheme.box(base, edge, 1, 9, 0)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base.lightened(0.12) if solid else Color(1, 1, 1, 0.13)
	hover.border_color = edge.lightened(0.2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base.darkened(0.15) if solid else Color(accent, 0.28)
	pressed.border_color = accent.lightened(0.15)
	if style == "tool":
		b.toggle_mode = true
		pressed.border_width_left = 4
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(base, base.a * 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UITheme.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", UITheme.DIM)
	parent.add_child(b)
	return b


## A glass panel with a VBox inside; returns the VBox.
static func panel(parent: Node, pad_x: int = 16, pad_y: int = 14, solid: bool = false, sep: int = 8) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.glass(pad_x, pad_y, solid))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	p.add_child(v)
	return v


## Labelled horizontal slider with a live value readout; `fmt` formats the value.
static func slider(parent: Node, title: String, lo: float, hi: float, value: float, step: float, fmt: String, on_change: Callable) -> HSlider:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var t := UITheme.eyebrow(row, title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label(row, fmt % value, 12, UITheme.TEXT, 600)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(150, 18)
	s.focus_mode = Control.FOCUS_NONE
	var track := UITheme.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := UITheme.box(UITheme.GO.lightened(0.15), Color(0, 0, 0, 0), 0, 3, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % v
		on_change.call(v))
	col.add_child(s)
	s.set_meta("readout", val)
	s.set_meta("fmt", fmt)
	return s


## Set a slider made by slider() without re-firing its callback.
static func set_slider(s: HSlider, v: float) -> void:
	s.set_value_no_signal(v)
	(s.get_meta("readout") as Label).text = String(s.get_meta("fmt")) % v


## Colour chip for a tool row.
static func swatch(parent: Node, c: Color, sz: int = 14) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.box(c, c.lightened(0.3), 1, 4, 0))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	return p
