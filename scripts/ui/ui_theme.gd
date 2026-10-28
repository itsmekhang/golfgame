class_name UITheme
extends RefCounted
## One visual language for every screen: the Clubhouse showroom and the on-course HUD share
## these colours, the Bahnschrift display face and the dark-glass panels, so a round and the
## menus read as one game. Code-built UI only; nothing here touches game rules.

# ---- palette
const GLASS := Color(0.035, 0.065, 0.055, 0.72)  # HUD panel over the 3D scene
const GLASS_SOLID := Color(0.05, 0.085, 0.075, 0.9)  # panels that must hide what's behind
const GLASS_EDGE := Color(1, 1, 1, 0.1)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color("eef2ea")
const DIM := Color("93a99c")
const GOLD := Color("f2d27c")  # prices, cash, highlights
const GO := Color("3f9264")  # primary action green
const GAIN := Color("5fd38d")  # better / under par / good contact
const LOSS := Color("ff6b5b")  # worse / penalties
const AMBER := Color("ffb648")
const SHADOW := Color(0.0, 0.015, 0.01, 0.85)  # text outline over the scene

static var _fonts := {}


## Display face: Windows' Bahnschrift (a DIN-style variable font) at the given weight and
## width, falling back to Segoe UI / Arial elsewhere. Cached per combination.
static func font(weight: int = 600, width: int = 100, spacing: int = 0) -> Font:
	var key := "%d/%d/%d" % [weight, width, spacing]
	if not _fonts.has(key):
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		sys.font_weight = weight
		sys.font_stretch = width
		var fv := FontVariation.new()
		fv.base_font = sys
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
		fv.spacing_glyph = spacing
		_fonts[key] = fv
	return _fonts[key]


## Rounded flat box.
static func box(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## The dark-glass HUD panel.
static func glass(pad_x: int, pad_y: int, solid: bool = false) -> StyleBoxFlat:
	var sb := box(GLASS_SOLID if solid else GLASS, GLASS_EDGE, 1, 12, 0)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 4)
	return sb


## Label in the display face. `outline` adds a soft dark edge for text floating over the scene.
static func label(parent: Node, text: String, size: int, color: Color, weight: int = 600, width: int = 100, spacing: int = 0, outline: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font(weight, width, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", SHADOW)
		l.add_theme_constant_override("outline_size", 4 if size >= 18 else 3)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


## Small spaced-out caps heading ("WIND", "SHOT POWER").
static func eyebrow(parent: Node, text: String, color: Color = DIM, outline: bool = false) -> Label:
	return label(parent, text.to_upper(), 11, color, 600, 100, 2, outline)


## A keyboard / mouse hint drawn as a keycap.
static func keycap(parent: Node, key: String, size: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.32), 1, 5, 0)
	sb.border_width_bottom = 2
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label(p, key, size, TEXT, 600, 100, 1)
	parent.add_child(p)
	return p


## Small rounded tag (ribbons, lie chips).
static func pill(parent: Node, text: String, bg: Color, fg: Color, size: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(bg, bg, 0, 6, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(p, text, size, fg, 700, 100, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


## Hairline rule.
static func rule(parent: Node) -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Colour for a lie/surface name, so the lie chip reads at a glance.
static func lie_color(surface: int) -> Color:
	match surface:
		PhysicsEnums.SurfaceType.FAIRWAY, PhysicsEnums.SurfaceType.FAIRWAY_SOFT:
			return Color("6fd18a")
		PhysicsEnums.SurfaceType.GREEN, CourseLayout.SURFACE_FRINGE:
			return Color("8ef0b4")
		CourseLayout.SURFACE_TEE:
			return Color("a6e3ff")
		CourseLayout.SURFACE_BUNKER, PhysicsEnums.SurfaceType.BUNKER:
			return Color("f0d39a")
		CourseLayout.SURFACE_WATER:
			return Color("7fb6ff")
		CourseLayout.SURFACE_FIRST_CUT:
			return Color("b6d77a")
	return Color("c9b977")  # rough, tree patch, pine straw
