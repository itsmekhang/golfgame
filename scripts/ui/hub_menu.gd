class_name HubMenu
extends CanvasLayer
## The Clubhouse: between-round hub for shopping, inventory, bag management, the putter
## cabinet, objectives and (for admins) the illegal-club sandbox. Built entirely in code as a
## full-screen dark "showroom": a studio backdrop lit in the current store's colour
## (shaders/inspect_backdrop.gdshader), a slim nav bar, glass panels and Bahnschrift display
## type. All rules live in GameState; this file only asks and displays.
##
## course.gd opens it with Tab (or after a round via show_round_summary) and listens to
## tee_off_requested / closed / abandon_requested.

signal tee_off_requested(span: String)
signal closed
signal abandon_requested

# The names date from the old paper-and-ink look; they now hold the dark theme:
# PAPER = panel, PAPER_DARK = raised panel, INK = text, MUTED = secondary text.
const PAPER := Color("13211d")
const PAPER_DARK := Color("1b2d27")
const INK := Color("e9f0ea")
const MUTED := Color("8fa498")
const GREEN := Color("4aa873")
const GOLD := Color("d9b26a")
const RED := Color("e0624f")

var _root: Control
var _panel: PanelContainer
var _content: MarginContainer
var _wallet_label: Label  # header wallet, kept live while the owned course earns
var _header: HBoxContainer
var _footer: Label
var _inspect: Control
var _summary: Control
var _showcase: Control
var _confirm: Control
var _backdrop: ShaderMaterial
var _toast: PanelContainer
var _open := false
var _tab := "shop"
var _store_id := "goodwill"
var _cabinet_selected := -1
var _bag_filter := ""  # "" = All; else a ClubCatalog type id ("driver", "wood", ...)
var _notice_timer := 0.0
var _round_span := "full18"  # "front9" | "back9" | "full18" -- which holes Tee off starts


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	# Dark studio behind the whole clubhouse, lit from above in the current store's colour.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = ShaderMaterial.new()
	_backdrop.shader = INSPECT_BACKDROP
	_backdrop.set_shader_parameter("focus", Vector2(0.5, -0.1))
	_backdrop.set_shader_parameter("glow", 0.5)
	_backdrop.set_shader_parameter("floor_amount", 0.0)
	bg.material = _backdrop
	_root.add_child(bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shell := StyleBoxEmpty.new()
	shell.content_margin_left = 32
	shell.content_margin_right = 32
	shell.content_margin_top = 10
	shell.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", shell)
	_root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)
	_header = HBoxContainer.new()
	_header.custom_minimum_size.y = 50
	_header.add_theme_constant_override("separation", 10)
	vb.add_child(_header)
	var rule := ColorRect.new()
	rule.color = SHOP_LINE
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_content)

	_inspect = _overlay()
	_summary = _overlay()
	_confirm = _overlay()
	_showcase = Control.new()
	_showcase.set_anchors_preset(Control.PRESET_FULL_RECT)
	_showcase.mouse_filter = Control.MOUSE_FILTER_STOP
	_showcase.visible = false
	_root.add_child(_showcase)

	# Notices pop up as a toast at the bottom centre, above everything.
	_toast = PanelContainer.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -26
	_toast.offset_bottom = -26
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_footer = _dlbl(_toast, "", 14, INK, _display_font(600))

	if GameState.current != null:
		GameState.current.changed.connect(_on_state_changed)
		GameState.current.business_ticked.connect(_on_business_ticked)


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			var tw := _toast.create_tween()
			tw.tween_property(_toast, "modulate:a", 0.0, 0.3)
			tw.tween_callback(func(): _footer.text = "")


# ---------------------------------------------------------------- open / close

func is_open() -> bool:
	return _open


func open(tab: String = "") -> void:
	if tab != "":
		_tab = tab
	_open = true
	_root.visible = true
	_refresh()


func close() -> void:
	if _showcase.visible:
		_showcase.visible = false
		return
	if _confirm.visible:
		_confirm.visible = false
		return
	if _inspect.visible:
		_inspect.visible = false
		return
	if _summary.visible:
		_summary.visible = false
		_refresh()
		return
	_open = false
	_root.visible = false
	closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _on_state_changed() -> void:
	if _open and not _summary.visible:
		_refresh()


func _on_business_ticked() -> void:
	if _open and _wallet_label != null and is_instance_valid(_wallet_label):
		_wallet_label.text = _money(_gs().cash)


# ---------------------------------------------------------------- building blocks

static func _box(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _lbl(parent: Node, text: String, size: int = 14, color: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _btn(parent: Node, text: String, cb: Callable, primary: bool = false, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	b.add_theme_font_override("font", _display_font(600))
	b.add_theme_font_size_override("font_size", 14)
	var bg := SHOP_GO if primary else Color(1, 1, 1, 0.06)
	var edge := SHOP_GO.lightened(0.3) if primary else Color(1, 1, 1, 0.13)
	var fg := Color.WHITE if primary else INK
	for st in [["normal", bg, edge], ["hover", bg.lightened(0.14) if primary else Color(1, 1, 1, 0.12), edge.lightened(0.2)], ["pressed", bg.darkened(0.15) if primary else Color(1, 1, 1, 0.04), edge], ["disabled", Color(bg, 0.35) if primary else Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.06)]]:
		var sb := _box(st[1], st[2], 1, 8, 6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _chip(parent: Node, text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(color, color.darkened(0.2), 1, 8, 3))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := _lbl(p, text, 11, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


func _card(parent: Node, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08), 1, 10, margin))
	parent.add_child(p)
	return p


## Club-icon art: the equipment pack's rendered preview PNG when one exists, otherwise
## the flat vector ClubSilhouette. Pinned to top-left of its cell (SHRINK, not FILL) so a
## tall sibling in the same row can't stretch it. Uncollected slots use the same
## preview in grey, preserving the club's shape and detail.
## `force_vector` skips the real equipment-pack photo and always draws the flat vector
## silhouette -- used for wedges in the bag's left-hand slot list, which keeps their
## original cute icon rather than the photo look the rest of the bag uses.
func _silhouette(parent: Node, model: Dictionary, condition: float, sz: Vector2, ghost: bool = false, force_vector: bool = false) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = sz
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrap)
	var preview: Texture2D = null if force_vector else EquipmentPreview.get_texture(str(model.get("id", "")))
	if preview != null:
		var render := TextureRect.new()
		render.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		render.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Without this, TextureRect's default EXPAND_KEEP_SIZE forces its own size to the
		# source image's native pixels (640x560) regardless of the anchors above, which is
		# what was blowing every icon out past its card.
		render.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		render.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		render.texture = preview
		if ghost:
			render.material = EquipmentPreview.get_uncollected_material()
		wrap.add_child(render)
	else:
		var vector := ClubSilhouette.new()
		vector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vector.setup(model, condition, ghost)
		wrap.add_child(vector)
	return wrap


func _overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.015, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(dim)
	_root.add_child(o)
	return o


func _overlay_panel(o: Control, w: float, h: float) -> VBoxContainer:
	for c in o.get_children():
		if c is PanelContainer:
			c.queue_free()
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w * 0.5
	p.offset_right = w * 0.5
	p.offset_top = -h * 0.5
	p.offset_bottom = h * 0.5
	var glass := _box(Color("101c18"), Color(1, 1, 1, 0.1), 1, 16, 22)
	glass.shadow_color = Color(0, 0, 0, 0.5)
	glass.shadow_size = 28
	glass.shadow_offset = Vector2(0, 8)
	p.add_theme_stylebox_override("panel", glass)
	o.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	return vb


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _notice(text: String, error: bool = false) -> void:
	var col := INSPECT_LOSS if error else INSPECT_GAIN
	_footer.text = text
	var sb := _box(Color(0.04, 0.07, 0.06, 0.95), Color(col, 0.5), 1, 12, 0)
	sb.border_width_left = 4
	sb.border_color = Color(col, 0.5)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.reset_size()
	var tw := _toast.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.18)
	tw.tween_method(func(y: float): _toast.offset_top = y; _toast.offset_bottom = y, -6.0, -26.0, 0.28)
	_notice_timer = 4.0


## Condition colour on the dark screens: red through amber to green.
static func _cond_color(c: float) -> Color:
	c = clampf(c, 0.0, 1.0)
	if c < 0.5:
		return INSPECT_LOSS.lerp(Color("ffb648"), c * 2.0)
	return Color("ffb648").lerp(INSPECT_GAIN, (c - 0.5) * 2.0)


static func _money(n: int) -> String:
	return "$%d" % n


func _gs() -> GameState:
	return GameState.current


# ---------------------------------------------------------------- refresh / header

func _refresh() -> void:
	if not _open:
		return
	var gs := _gs()
	_backdrop.set_shader_parameter("accent", _store_accent(_store_id) if _tab == "shop" else GREEN)
	var vs := _root.get_viewport_rect().size
	_backdrop.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_clear(_header)
	var mark := HBoxContainer.new()
	mark.add_theme_constant_override("separation", 10)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(mark)
	_gem(mark, GOLD, 16)
	_dlbl(mark, "CLUBHOUSE", 23, Color.WHITE, _display_font(700, 85, 2))
	var sp0 := Control.new()
	sp0.custom_minimum_size = Vector2(6, 0)
	_header.add_child(sp0)
	var tabs := [["shop", "Shop"], ["bag", "Bag"], ["collection", "Collection"], ["objectives", "Objectives"]]
	if AdminAccess.is_admin():
		tabs.append(["admin", "Admin"])
	for t in tabs:
		var id: String = t[0]
		_nav_tab(_header, t[1], _tab == id, func(): _tab = id; _refresh())
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(sp2)
	if gs != null:
		var wallet := HBoxContainer.new()
		wallet.add_theme_constant_override("separation", 8)
		wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header.add_child(wallet)
		var wl := _eyebrow(wallet, "Wallet")
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cash := _dlbl(wallet, _money(gs.cash), 21, SHOP_PRICE, _display_font(700))
		cash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_wallet_label = cash
	# The round picker is always here. Mid-round, starting a different (or fresh) round
	# abandons the one in progress, so it asks first; Resume goes back to it.
	var in_round := gs != null and gs.round_in_progress
	var span_names := {"front9": "Front 9", "back9": "Back 9", "full18": "Full 18"}
	var seg := PanelContainer.new()
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seg.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 1, 10, 3))
	_header.add_child(seg)
	var seg_row := HBoxContainer.new()
	seg_row.add_theme_constant_override("separation", 2)
	seg.add_child(seg_row)
	for span in [["front9", "Front 9"], ["back9", "Back 9"], ["full18", "Full 18"]]:
		var id: String = span[0]
		_segment(seg_row, span[1], _round_span == id, func(): _round_span = id; _refresh())
	if in_round:
		_header_btn(_header, "New round", func(): _confirm_dialog("Start a new %s round? The round in progress is abandoned: no payout, and the stores won't restock." % span_names.get(_round_span, ""), func(): tee_off_requested.emit(_round_span); _open = false; _root.visible = false), false)
		_header_btn(_header, "Resume", func(): close(), true)
	else:
		_header_btn(_header, "Tee off", func(): tee_off_requested.emit(_round_span); _open = false; _root.visible = false, true)
	var close_btn := PanelContainer.new()
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cb_base := _box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 1, 8, 7)
	var cb_hover := _box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.16), 1, 8, 7)
	close_btn.add_theme_stylebox_override("panel", cb_base)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.tooltip_text = "Close the clubhouse (Esc or Tab)"
	close_btn.mouse_entered.connect(func(): close_btn.add_theme_stylebox_override("panel", cb_hover))
	close_btn.mouse_exited.connect(func(): close_btn.add_theme_stylebox_override("panel", cb_base))
	close_btn.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	_header.add_child(close_btn)
	var close_row := HBoxContainer.new()
	close_row.add_theme_constant_override("separation", 8)
	close_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_btn.add_child(close_row)
	_keycap(close_row, "ESC")
	_dlbl(close_row, "BACK", 12, SHOP_TEXT, _display_font(600, 100, 2))
	_clear(_content)
	if gs == null:
		_lbl(_content, "No save state loaded (GameState autoload missing).", 16, RED)
		return
	match _tab:
		"shop": _build_shop(_content)
		"bag": _build_bag(_content)
		"collection": _build_collection(_content)
		"objectives": _build_objectives(_content)
		"admin": _build_admin(_content)


## Nav bar tab: caps text, white with a gold underline when open.
func _nav_tab(parent: Node, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _display_font(600, 100, 2))
	b.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE if on else SHOP_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.draw.connect(func():
		var y := b.size.y
		if on:
			b.draw_rect(Rect2(8, y - 3, b.size.x - 16, 3), SHOP_PRICE)
		elif b.is_hovered():
			b.draw_rect(Rect2(8, y - 2, b.size.x - 16, 2), Color(1, 1, 1, 0.25)))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## One option inside the nav bar's segmented round picker.
func _segment(parent: Node, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _display_font(600, 100, 1))
	b.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(1, 1, 1, 0.15) if on else (Color(1, 1, 1, 0.06) if state == "hover" else Color(1, 1, 1, 0.0))
		var sb := _box(bg, Color(1, 1, 1, 0.2) if on else Color(1, 1, 1, 0.0), 1, 7, 0)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE if on else SHOP_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Nav bar action ("Tee off", "Resume", "New round"): glowing green when primary.
func _header_btn(parent: Node, text: String, cb: Callable, primary: bool) -> Button:
	var b := _shop_btn(parent, text, cb, "primary" if primary else "secondary")
	b.add_theme_font_override("font", _display_font(700, 100, 2))
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(104 if primary else 0, 38)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


# ---------------------------------------------------------------- shop

## The shop: storefront tabs across the top, a filter/sort bar, then a wrapping shelf of
## trading-card tiles whose display cases are lit in each club's rarity colour
## (shaders/rarity_shine.gdshader). Cards lift and glow on hover; clicking the case inspects.
const SHOP_BG := Color("0f1b17")
const SHOP_PANEL := Color("172520")
const SHOP_CARD := Color(0.075, 0.12, 0.105, 0.92)
const SHOP_CARD_HOVER := Color(0.1, 0.155, 0.135, 0.97)
const SHOP_TEXT := Color("eef2ea")
const SHOP_DIM := Color("93a99c")
const SHOP_PRICE := Color("f2d27c")
const SHOP_LINE := Color(1, 1, 1, 0.09)
const SHOP_GO := Color("3f9264")
const SHOP_CARD_W := 286.0
const SHOP_ART_H := 150.0
const SHOP_TYPES := [["", "All"], ["driver", "Drivers"], ["wood", "Woods"], ["hybrid", "Hybrids"], ["iron_set", "Irons"], ["wedge", "Wedges"], ["putter", "Putters"]]
const SHOP_SORTS := [["featured", "Featured"], ["price_low", "Cheapest"], ["price_high", "Priciest"], ["rarity", "Rarest"], ["condition", "Condition"]]
var _shop_type := ""
var _shop_sort := "featured"


func _build_shop(parent: Node) -> void:
	var gs := _gs()
	if not gs.store_unlocked(_store_id):
		_store_id = "goodwill"
	var store := EconomyConfig.store(_store_id)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	parent.add_child(col)

	# ---- storefronts
	var fronts := HBoxContainer.new()
	fronts.add_theme_constant_override("separation", 10)
	col.add_child(fronts)
	for s in EconomyConfig.stores():
		_storefront_tab(fronts, s)

	# ---- filter / sort bar
	var shown := _shop_listings(gs.listings(_store_id))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	col.add_child(bar)
	for t in SHOP_TYPES:
		var type_id: String = t[0]
		_shop_chip(bar, t[1], _shop_type == type_id, func(): _shop_type = type_id; _refresh())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	var sort_lbl := _eyebrow(bar, "Sort")
	sort_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for s in SHOP_SORTS:
		var sort_id: String = s[0]
		_shop_chip(bar, s[1], _shop_sort == sort_id, func(): _shop_sort = sort_id; _refresh())

	# ---- shelf
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_slim_scrollbar(scroll)
	col.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)  # room for the hover lift and glow
	scroll.add_child(pad)
	var shelf := HFlowContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.alignment = FlowContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override("h_separation", 16)
	shelf.add_theme_constant_override("v_separation", 16)
	pad.add_child(shelf)
	if shown.is_empty():
		var empty := _dlbl(shelf, "Nothing here right now. Play a round and the shelves restock." if gs.listings(_store_id).is_empty() else "No %s on this shelf. Try another filter or store." % _shop_type_label().to_lower(), 16, SHOP_DIM, _display_font(500))
		empty.custom_minimum_size = Vector2(0, 160)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var n := 0
	for l in shown:
		_shelf_card(shelf, store, l, n)
		n += 1

	var rc := EconomyConfig.reserve_cfg()
	var foot := _dlbl(col, "Restocks after every completed round   ·   Hold a find for %d more rounds with a %d%% deposit (counts toward the price)%s" % [int(rc.get("extra_rounds", 2)), int(float(rc.get("deposit_fraction", 0.1)) * 100.0), "   ·   One haggle per listing" if gs.store_haggles(_store_id) else ""], 11, Color(SHOP_DIM, 0.8), _display_font(400, 100, 1))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _shop_type_label() -> String:
	for t in SHOP_TYPES:
		if t[0] == _shop_type:
			return t[1]
	return "clubs"


## Filter by club type, then sort. "Featured" keeps the store's own shelf order.
func _shop_listings(all: Array) -> Array:
	var out: Array = []
	for l in all:
		if _shop_type == "" or str(ClubCatalog.model(str(l["model_id"])).get("type", "")) == _shop_type:
			out.append(l)
	match _shop_sort:
		"price_low":
			out.sort_custom(func(a, b): return int(a["price"]) < int(b["price"]))
		"price_high":
			out.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]))
		"condition":
			out.sort_custom(func(a, b): return float(a["condition"]) > float(b["condition"]))
		"rarity":
			out.sort_custom(func(a, b): return EconomyConfig.rarity_rank(str(ClubCatalog.model(str(a["model_id"])).get("rarity", ""))) > EconomyConfig.rarity_rank(str(ClubCatalog.model(str(b["model_id"])).get("rarity", ""))))
	return out


## Store colour from economy.json ("accent"), falling back to the hub green.
func _store_accent(store_id: String) -> Color:
	var hex := str(EconomyConfig.store(store_id).get("accent", ""))
	return Color(hex) if hex != "" else GREEN


## Rounded letter tile (store initials).
func _badge(parent: Node, letter: String, bg: Color, diameter: int, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(bg, bg.lightened(0.2), 1, int(diameter * 0.28), 0))
	var l := _dlbl(p, letter.to_upper(), int(diameter * 0.5), fg, _display_font(700))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


## Small rounded label (ribbons, status tags).
func _pill(parent: Node, text: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(bg, bg, 0, 6, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _dlbl(p, text, 10, fg, _display_font(700, 100, 1))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


## Filter/sort toggle: plain caps text, filled glass when on.
func _shop_chip(parent: Node, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _display_font(600, 100, 1))
	b.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(1, 1, 1, 0.13) if on else (Color(1, 1, 1, 0.06) if state == "hover" else Color(1, 1, 1, 0.0))
		var sb := _box(bg, Color(1, 1, 1, 0.22) if on else Color(1, 1, 1, 0.0), 1, 8, 0)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE if on else SHOP_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Dark showroom button: "primary" (green go), "secondary" (glass) or "ghost".
func _shop_btn(parent: Node, text: String, cb: Callable, kind: String = "secondary", enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	b.add_theme_font_override("font", _display_font(700 if kind == "primary" else 600, 100, 1))
	b.add_theme_font_size_override("font_size", 14 if kind == "primary" else 12)
	var bg := SHOP_GO if kind == "primary" else (Color(1, 1, 1, 0.06) if kind == "secondary" else Color(1, 1, 1, 0.0))
	var edge := SHOP_GO.lightened(0.3) if kind == "primary" else (SHOP_LINE if kind == "secondary" else Color(1, 1, 1, 0.0))
	var pad := 9 if kind == "primary" else 6
	var normal := _box(bg, edge, 1, 9, pad)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	if kind == "primary":
		normal.border_width_top = 2
		normal.shadow_color = Color(SHOP_GO, 0.3)
		normal.shadow_size = 8
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = bg.lightened(0.14) if kind == "primary" else Color(1, 1, 1, 0.12)
	hover.border_color = edge.lightened(0.25) if kind == "primary" else Color(1, 1, 1, 0.18)
	if kind == "primary":
		hover.shadow_color = Color(SHOP_GO.lightened(0.2), 0.6)
		hover.shadow_size = 16
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = bg.darkened(0.15) if kind == "primary" else Color(1, 1, 1, 0.04)
	var disabled := _box(Color(1, 1, 1, 0.03), SHOP_LINE, 1, 9, pad)
	disabled.content_margin_left = 14
	disabled.content_margin_right = 14
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE if kind == "primary" else SHOP_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(SHOP_DIM, 0.6))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Text-only action under a shelf card ("HOLD $2", "HAGGLE", "INSPECT").
func _link_btn(parent: Node, text: String, cb: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	b.add_theme_font_override("font", _display_font(600, 100, 1))
	b.add_theme_font_size_override("font_size", 11)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := _box(Color(1, 1, 1, 0.07) if state == "hover" else Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 0, 6, 0)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", SHOP_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(SHOP_DIM, 0.35))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Thin dark scrollbar for the showroom lists.
func _slim_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	var track := _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.0), 0, 3, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := _box(Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0), 0, 3, 0)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = Color(1, 1, 1, 0.38)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hi)


## One storefront tab: logo tile, name and a status line. The open store glows in its
## colour; locked stores are dimmed and explain what opens them (tooltip + click).
func _storefront_tab(parent: Node, s: Dictionary) -> void:
	var gs := _gs()
	var sid := str(s["id"])
	var unlocked := gs.store_unlocked(sid)
	var selected := sid == _store_id
	var accent := _store_accent(sid)
	var tab := PanelContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var base := _box(Color(1, 1, 1, 0.035) if unlocked else Color(0, 0, 0, 0.22), Color(1, 1, 1, 0.08) if unlocked else Color(1, 1, 1, 0.04), 1, 12, 10)
	base.content_margin_left = 12
	if selected:
		base = _box(Color(accent.r, accent.g, accent.b, 0.24), accent.lightened(0.15), 1, 12, 10)
		base.content_margin_left = 12
		base.border_width_bottom = 3
		base.shadow_color = Color(accent, 0.35)
		base.shadow_size = 14
	var hover := base.duplicate()
	if not selected and unlocked:
		hover.bg_color = Color(1, 1, 1, 0.07)
		hover.border_color = Color(accent, 0.8)
	tab.add_theme_stylebox_override("panel", base)
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var status := Progression.status(gs, s)
	tab.tooltip_text = str(s.get("tagline", "")) if unlocked else "Locked. " + str(status["summary"])
	tab.mouse_entered.connect(func(): tab.add_theme_stylebox_override("panel", hover))
	tab.mouse_exited.connect(func(): tab.add_theme_stylebox_override("panel", base))
	tab.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if unlocked:
				_store_id = sid
				_refresh()
			else:
				_notice("%s is locked. %s" % [s["name"], status["summary"]], true))
	parent.add_child(tab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(row)
	_badge(row, str(s["name"]).left(1), accent if unlocked else Color(1, 1, 1, 0.08), 34, Color.WHITE if unlocked else Color(SHOP_DIM, 0.6))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_lbl := _dlbl(col, str(s["name"]), 16, Color.WHITE if unlocked else Color(SHOP_DIM, 0.7), _display_font(600))
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var sub := ""
	if not unlocked:
		sub = "LOCKED   ·   HOVER TO SEE HOW"
	else:
		sub = "%d ON THE SHELF" % gs.listings(sid).size()
		if gs.store_haggles(sid):
			var seller_priced := false
			for l in gs.listings(sid):
				if str(l.get("seller", "")) != "":
					seller_priced = true
					break
			sub += "   ·   " + ("HAGGLE" if seller_priced else "OWNER " + str(gs.store_mood(sid).get("name", "")).to_upper())
		else:
			sub += "   ·   FIXED PRICES"
	var sub_lbl := _dlbl(col, sub, 10, Color(1, 1, 1, 0.8) if selected else SHOP_DIM, _display_font(600, 100, 1))
	sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


const RARITY_SHINE = preload("res://shaders/rarity_shine.gdshader")
const SHINE_STRENGTH := {"common": 0.22, "uncommon": 0.42, "rare": 0.52, "epic": 0.62, "legendary": 0.72, "mythic": 0.85}

## Club thumbnail in a display case. With a `rarity` the case takes the rarity colour and a
## matching light (shaders/rarity_shine.gdshader) shines across the art -- grey, green,
## blue, purple, gold, red. Pass "" for a plain backdrop.
func _rarity_art(parent: Node, model: Dictionary, cond: float, sz: Vector2, rarity: String, seed_key: String) -> PanelContainer:
	var art := PanelContainer.new()
	var bg := PAPER_DARK
	if rarity != "":
		# Dark display-case backdrop so the additive light reads as a coloured glow.
		bg = Color("121c19").lerp(EconomyConfig.rarity_color(rarity), 0.2)
	art.add_theme_stylebox_override("panel", _box(bg, bg, 0, 10, 0))
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Clip the club art and its light to the rounded case.
	art.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	parent.add_child(art)
	_silhouette(art, model, cond, sz)
	if rarity != "":
		var light := ColorRect.new()
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = RARITY_SHINE
		mat.set_shader_parameter("tint", EconomyConfig.rarity_color(rarity).lightened(0.15))
		mat.set_shader_parameter("strength", float(SHINE_STRENGTH.get(rarity, 0.4)))
		mat.set_shader_parameter("phase", float(absi(hash(seed_key)) % 1000) / 1000.0)
		light.material = mat
		art.add_child(light)
	return art


## Condition as a five-cell meter plus its grade, for the dark showroom.
func _shop_condition(parent: Node, cond: float) -> void:
	var m := Control.new()
	m.custom_minimum_size = Vector2(44, 6)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := _cond_color(cond)
	m.draw.connect(func():
		var n := 5
		var gap := 2.0
		var cw := (m.size.x - gap * (n - 1)) / n
		for i in range(n):
			var f := clampf(cond * n - i, 0.0, 1.0)
			var r := Rect2(i * (cw + gap), 0, cw, m.size.y)
			m.draw_rect(r, Color(1, 1, 1, 0.1))
			if f > 0.0:
				m.draw_rect(Rect2(r.position, Vector2(cw * f, r.size.y)), col))
	parent.add_child(m)
	var l := _dlbl(parent, EconomyConfig.condition_grade(cond).to_upper(), 11, col, _display_font(600, 100, 1))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## One trading-card tile: lit display case (click to inspect), name, slot and condition, the
## price beside a Buy button, and text actions underneath. Hover lifts the card and lights
## its frame in the club's rarity colour. `order` staggers the shelf's fade-in.
func _shelf_card(parent: Node, store: Dictionary, l: Dictionary, order: int = 0) -> void:
	var gs := _gs()
	var model := ClubCatalog.model(str(l["model_id"]))
	var cond := float(l["condition"])
	var reveals := bool(store.get("reveals_names", false))
	var rarity := str(model.get("rarity", "common"))
	var rcol := EconomyConfig.rarity_color(rarity)
	var lid := str(l["id"])
	var sid := str(store["id"])
	var reserved := bool(l.get("reserved", false))
	var price := int(l["price"])
	var due := price - (int(l.get("deposit", 0)) if reserved else 0)
	var inspect := func(): _show_inspect(model, {"kind": "listing", "store_id": sid, "listing": l})

	var card := PanelContainer.new()
	card.custom_minimum_size.x = SHOP_CARD_W
	var base := _box(SHOP_CARD, Color(rcol, 0.3), 1, 16, 10)
	base.shadow_color = Color(0, 0, 0, 0.4)
	base.shadow_size = 10
	base.shadow_offset = Vector2(0, 4)
	var hover: StyleBoxFlat = base.duplicate()
	hover.bg_color = SHOP_CARD_HOVER
	hover.border_color = rcol.lightened(0.25)
	hover.set_border_width_all(2)
	hover.shadow_color = Color(rcol, 0.5)
	hover.shadow_size = 22
	hover.shadow_offset = Vector2.ZERO
	card.add_theme_stylebox_override("panel", base)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("shelf_card", true)
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)

	# Display case with ribbons laid over its top edge and an Inspect cue on hover.
	var case := _rarity_art(vb, model, cond, Vector2(SHOP_CARD_W - 20, SHOP_ART_H), rarity, lid)
	case.mouse_filter = Control.MOUSE_FILTER_STOP
	case.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var quote := ""
	if str(l.get("seller", "")) != "":
		quote = "%s: “%s”" % [l["seller"], l.get("seller_blurb", "")]
	elif str(model.get("tell", "")) != "":
		quote = "“%s”" % model["tell"]
	case.tooltip_text = quote if quote != "" else "Inspect"
	case.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			inspect.call())
	var over := MarginContainer.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		over.add_theme_constant_override("margin_" + side, 8)
	case.add_child(over)
	var ribbons := HBoxContainer.new()
	ribbons.add_theme_constant_override("separation", 4)
	ribbons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ribbons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(ribbons)
	if reveals:
		_pill(ribbons, rarity.to_upper(), rcol, Color.WHITE)
	match str(l.get("haggled", "")):
		"accepted":
			_pill(ribbons, "DEAL", SHOP_GO, Color.WHITE)
		"refused":
			_pill(ribbons, "NO DEAL", Color(RED, 0.9), Color.WHITE)
	if reserved:
		_pill(ribbons, "ON HOLD · %d" % int(l.get("reserve_rounds_left", 0)), SHOP_PRICE, SHOP_BG)
	var cue := HBoxContainer.new()
	cue.alignment = BoxContainer.ALIGNMENT_END
	cue.size_flags_vertical = Control.SIZE_SHRINK_END
	cue.add_theme_constant_override("separation", 6)
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cue.modulate.a = 0.0
	over.add_child(cue)
	_keycap(cue, "CLICK")
	_dlbl(cue, "INSPECT", 11, Color.WHITE, _display_font(600, 100, 2))

	var title := str(model.get("name", "")) if reveals else ClubSilhouette.shop_label(model)
	var t := _dlbl(vb, title, 18, Color.WHITE, _display_font(700, 92))
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.tooltip_text = title
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	vb.add_child(meta)
	var slot := _dlbl(meta, ("%s   ·   %s" % [ClubCatalog.slot_label(model), _kind_label(model)]).to_upper(), 11, SHOP_DIM, _display_font(600, 100, 1))
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_shop_condition(meta, cond)
	_sheet_rule(vb)

	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	vb.add_child(price_row)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 0)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(pv)
	var sub := ""
	if str(l.get("haggled", "")) == "accepted":
		sub = "WAS " + _money(int(l.get("list_price", price)))
	elif reserved and due != price:
		sub = "%s DUE" % _money(due)
	_eyebrow(pv, sub if sub != "" else "Price")
	_dlbl(pv, _money(price), 30, SHOP_PRICE, _display_font(700))
	var buy := _shop_btn(price_row, "Buy" if gs.cash >= due else "Need %s" % _money(due - gs.cash), func(): _buy(sid, lid), "primary", gs.cash >= due)
	buy.custom_minimum_size = Vector2(112, 42)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 0)
	vb.add_child(links)
	if not reserved:
		var dep := EconomyConfig.reserve_deposit(price)
		var hold := _link_btn(links, "Hold %s" % _money(dep), func(): _reserve(sid, lid), gs.cash >= dep)
		hold.tooltip_text = "Keep it on the shelf for %d more rounds; the deposit counts toward the price." % int(EconomyConfig.reserve_cfg().get("extra_rounds", 2))
	if gs.can_haggle(sid, l):
		_link_btn(links, "Haggle", func(): _haggle_dialog(sid, l))
	var lgap := Control.new()
	lgap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lgap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	links.add_child(lgap)
	_link_btn(links, "Inspect", inspect)

	# Hover: lift, glow, and show the inspect cue. Children forward the events, so check
	# the cursor against the card's own rect before letting go -- unless an overlay (Inspect,
	# haggle, confirm) has opened over it. No z_index: that would draw the card above them.
	var lift := func(on: bool):
		if not on and not _overlay_open() and card.get_global_rect().has_point(card.get_global_mouse_position()):
			return
		if on and _overlay_open():
			return
		card.add_theme_stylebox_override("panel", hover if on else base)
		var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.16)
		tw.tween_property(cue, "modulate:a", 1.0 if on else 0.0, 0.16)
	card.mouse_entered.connect(lift.bind(true))
	card.mouse_exited.connect(lift.bind(false))
	# Shelf fades in card by card.
	card.modulate.a = 0.0
	var fade := card.create_tween()
	fade.tween_interval(0.03 * order)
	fade.tween_property(card, "modulate:a", 1.0, 0.25)


## True while a full-screen overlay (Inspect, a dialog, the showcase, the round summary) is up.
func _overlay_open() -> bool:
	return _inspect.visible or _confirm.visible or _showcase.visible or _summary.visible


## A club's kind for display: its catalog type, except the utility iron, which sits in the
## hybrid slot but is an iron.
static func _kind_label(model: Dictionary) -> String:
	if str(model.get("silhouette", "")) == "hybrid_iron":
		return "Utility iron"
	return ClubCatalog.type_label(str(model.get("type", "")))


static func _odds_word(odds: float) -> String:
	if odds >= 0.6:
		return "likely"
	if odds >= 0.3:
		return "maybe"
	return "long shot"


## One offer per listing, in the showroom style: three offer tiles with the new price and
## how likely the seller is to take it. Odds show as a word and a colour, never a number.
func _haggle_dialog(store_id: String, l: Dictionary) -> void:
	var gs := _gs()
	var model := ClubCatalog.model(str(l["model_id"]))
	var store := EconomyConfig.store(store_id)
	var vb := _overlay_panel(_confirm, 560, 380)
	(vb.get_parent() as PanelContainer).add_theme_stylebox_override("panel", _box(SHOP_BG, _store_accent(store_id), 2, 16, 20))
	vb.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	_rarity_art(head, model, float(l["condition"]), Vector2(120, 84), str(model.get("rarity", "common")), str(l["id"]))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_lbl(hv, "MAKE AN OFFER", 11, SHOP_DIM)
	var title := str(model.get("name", "")) if bool(store.get("reveals_names", false)) else ClubSilhouette.shop_label(model)
	_lbl(hv, title, 20, SHOP_TEXT)
	_lbl(hv, "Asking %s" % _money(int(l["price"])), 15, SHOP_PRICE)
	var who := str(l.get("seller", ""))
	if who == "":
		who = "The owner is %s today" % str(gs.store_mood(store_id).get("name", "")).to_lower()
	_lbl(vb, "%s. One offer only. Push too hard and they may pull the listing." % who, 12, SHOP_DIM, true)
	var offers := gs.haggle_offers()
	for i in range(offers.size()):
		var o: Dictionary = offers[i]
		var idx := i
		var offer_price := maxi(1, int(round(float(l["price"]) * (1.0 - float(o.get("discount", 0.1))))))
		var odds := gs.haggle_odds(store_id, l, i)
		var odds_col := SHOP_GO.lightened(0.2) if odds >= 0.6 else (SHOP_PRICE if odds >= 0.3 else Color(RED).lightened(0.25))
		var tile := PanelContainer.new()
		var tb := _box(SHOP_CARD, SHOP_LINE, 1, 10, 10)
		var th := _box(SHOP_CARD_HOVER, odds_col, 1, 10, 10)
		tile.add_theme_stylebox_override("panel", tb)
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.mouse_entered.connect(func(): tile.add_theme_stylebox_override("panel", th))
		tile.mouse_exited.connect(func(): tile.add_theme_stylebox_override("panel", tb))
		tile.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_confirm.visible = false
				_haggle(store_id, str(l["id"]), idx))
		vb.add_child(tile)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(row)
		var lab := _lbl(row, str(o.get("label", "")), 14, SHOP_TEXT)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pl := _lbl(row, _money(offer_price), 18, SHOP_PRICE)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pill(row, _odds_word(odds).to_upper(), odds_col, SHOP_BG)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	_shop_btn(foot, "Never mind", func(): _confirm.visible = false)
	_confirm.visible = true


func _haggle(store_id: String, listing_id: String, offer_index: int) -> void:
	var r := _gs().haggle(store_id, listing_id, offer_index)
	if not r["ok"]:
		_notice(str(r["error"]), true)
	elif r["accepted"]:
		_notice("Deal! It's yours for %s if you buy it now." % _money(int(r["price"])))
	elif r["walked"]:
		_notice("Insulted, the seller pulled the listing.", true)
	else:
		_notice("They wouldn't budge. Still %s." % _money(int(r["price"])), true)


func _buy(store_id: String, listing_id: String) -> void:
	var gs := _gs()
	var l := gs.find_listing(store_id, listing_id)
	var r := gs.buy(store_id, listing_id)
	if not r["ok"]:
		_notice(str(r["error"]), true)
		return
	var inst := gs.get_club(str(r["instance_id"]))
	var msg := "Bought %s for %s." % [inst.display_name(), _money(int(l.get("price", 0)))]
	if inst.is_collectible_putter():
		msg += "  A cabinet putter!"
	if not (r["unlocked"] as Array).is_empty():
		msg += "  Unlocked: %s!" % EconomyConfig.store_name(str(r["unlocked"][0]))
	_notice(msg)
	_inspect.visible = false
	_show_inspect(inst.model(), {"kind": "owned", "instance": inst, "just_bought": true})


func _reserve(store_id: String, listing_id: String) -> void:
	var r := _gs().reserve(store_id, listing_id)
	if r["ok"]:
		_notice("Held for %d more rounds. Deposit %s counts toward the price." % [int(EconomyConfig.reserve_cfg().get("extra_rounds", 2)), _money(int(r["deposit"]))])
	else:
		_notice(str(r["error"]), true)


# ---------------------------------------------------------------- bag / inventory

func _build_bag(parent: Node) -> void:
	var gs := _gs()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	parent.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	var bag := gs.bag_clubs()
	_lbl(left, "Your bag  (%d of %d clubs)" % [bag.size(), EconomyConfig.bag_size()], 18, INK)
	var gate := gs.can_edit_bag()
	if not gate["ok"]:
		_lbl(left, str(gate["error"]), 12, RED, true)
	var lscroll := ScrollContainer.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	var lvb := VBoxContainer.new()
	lvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvb.add_theme_constant_override("separation", 3)
	lscroll.add_child(lvb)
	var keys: Array = []
	for slot in ClubCatalog.bag_order():
		var key: String = "IRONS" if ClubCatalog.iron_set_slots().has(slot) else str(slot)
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		var row := _card(lvb, 6)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 8)
		row.add_child(rh)
		var kl := _lbl(rh, "4-9" if key == "IRONS" else key, 13, MUTED)
		kl.custom_minimum_size = Vector2(36, 0)
		var inst := gs.get_club(gs.equipped_id(key))
		if inst == null:
			var e := _lbl(rh, "empty slot", 13, MUTED)
			e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			continue
		_silhouette(rh, inst.model(), inst.condition, Vector2(56, 44))
		var nl := _lbl(rh, "%s  [%s]" % [inst.display_name(), inst.condition_grade()], 13, EconomyConfig.rarity_color(inst.rarity()).lightened(0.3) if not inst.is_starter() else INK)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var fb := gs.fallback_for_key(key, inst.id)
		if (fb != "" or key == "HY") and not inst.is_starter():
			_btn(rh, "Unequip", func():
				var r := gs.unequip(key)
				if not r["ok"]:
					_notice(str(r["error"]), true), false, gate["ok"])

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	hb.add_child(right)
	_lbl(right, "Everything you own", 18, INK)
	_lbl(right, "Shops pay %d-%d%% of a club's fair used value (model + condition, not what you paid). Loaners stay with the clubhouse.", 12, MUTED, true).text = "Shops pay %d-%d%% of a club's fair used value (model + condition, never what you paid). Loaners stay with the clubhouse." % [int(float(EconomyConfig.data().get("resale", {}).get("rate_min", 0.5)) * 100.0), int(float(EconomyConfig.data().get("resale", {}).get("rate_max", 0.65)) * 100.0)]

	var owned := gs.owned()
	if AdminAccess.is_admin():
		owned.append_array(gs.sandbox_instances())
	if not ClubCatalog.type_order().has(_bag_filter):
		_bag_filter = ""

	# Category filter: a row of chips (All + each club type) with a live count, so a big
	# bag can be narrowed down to just drivers, just putters, and so on at a glance.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	right.add_child(filter_row)
	var counts := {}
	for c in owned:
		counts[c.type()] = int(counts.get(c.type(), 0)) + 1
	_filter_chip(filter_row, "All (%d)" % owned.size(), "")
	for t in ClubCatalog.type_order():
		var n := int(counts.get(t, 0))
		_filter_chip(filter_row, "%s (%d)" % [ClubCatalog.type_label(t), n], t, n == 0)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	scroll.add_child(vb)
	var shown := 0
	for inst in owned:
		if _bag_filter != "" and inst.type() != _bag_filter:
			continue
		_owned_row(vb, inst, gate["ok"])
		shown += 1
	if shown == 0:
		_lbl(vb, "No %s in your inventory yet." % ClubCatalog.type_label(_bag_filter).to_lower(), 13, MUTED)


## One filter chip for the owned-clubs category filter. `type_id` "" means "All".
func _filter_chip(parent: Node, text: String, type_id: String, disabled: bool = false) -> void:
	var active := _bag_filter == type_id
	var b := _btn(parent, text, func(): _bag_filter = type_id; _refresh(), active, not disabled)
	b.add_theme_font_size_override("font_size", 12)


func _owned_row(parent: Node, inst: ClubInstance, can_edit: bool) -> void:
	var gs := _gs()
	var card := _card(parent, 6)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	card.add_child(hb)
	_rarity_art(hb, inst.model(), inst.condition, Vector2(78, 62), str(inst.model().get("rarity", "")), inst.id)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	_lbl(top, inst.display_name(), 14, INK)
	_chip(top, inst.rarity().capitalize(), EconomyConfig.rarity_color(inst.rarity()))
	if inst.is_illegal():
		_chip(top, "ILLEGAL", RED)
	elif inst.is_collectible_putter():
		_chip(top, "Cabinet", GOLD.darkened(0.2))
	if gs.is_equipped(inst.id):
		_chip(top, "Equipped", GREEN)
	var info := "%s (%d%%)  ·  %s" % [inst.condition_grade(), int(round(inst.condition * 100.0)), inst.source_label()]
	if not inst.is_starter():
		info += "  ·  paid %s  ·  fair %s" % [_money(inst.purchase_price), _money(inst.fair_value())]
	info += "  ·  %d round%s" % [inst.rounds_played, "" if inst.rounds_played == 1 else "s"]
	_lbl(vb, info, 12, MUTED, true)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	vb.add_child(brow)
	_btn(brow, "Inspect", func(): _show_inspect(inst.model(), {"kind": "owned", "instance": inst}))
	if gs.is_equipped(inst.id):
		_btn(brow, "Equipped", func(): pass, true, false)
	else:
		_btn(brow, "Equip", func():
			var r := gs.equip(inst.id)
			if r["ok"]:
				_notice("Equipped %s." % inst.display_name())
			else:
				_notice(str(r["error"]), true), true, can_edit)
	var cs := gs.can_sell(inst.id)
	var offer := gs.sell_offer(inst.id)
	if not inst.is_starter() and not inst.is_illegal():
		_btn(brow, "Sell for %s" % _money(offer), func(): _sell_dialog(inst), false, cs["ok"])
		if not cs["ok"] and can_edit:
			_lbl(brow, str(cs["error"]), 11, MUTED)


func _sell_dialog(inst: ClubInstance) -> void:
	var gs := _gs()
	var offer := gs.sell_offer(inst.id)
	var text := "Sell %s for %s?\nFair used value %s  ·  you paid %s.\n%s" % [inst.display_name(), _money(offer), _money(inst.fair_value()), _money(inst.purchase_price), ("It stays in your discovery record, but leaves the cabinet." if inst.is_collectible_putter() else "This can't be undone; shops don't buy back.")]
	if gs.is_equipped(inst.id):
		text += "\nIt's equipped: a replacement will be swapped into the bag."
	_confirm_dialog(text, func():
		var r := gs.sell(inst.id)
		if r["ok"]:
			_notice("Sold %s for %s." % [inst.display_name(), _money(int(r["price"]))])
			_inspect.visible = false
		else:
			_notice(str(r["error"]), true))


func _confirm_dialog(text: String, on_yes: Callable) -> void:
	var vb := _overlay_panel(_confirm, 520, 220)
	_lbl(vb, text, 15, INK, true)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_btn(row, "Cancel", func(): _confirm.visible = false)
	_btn(row, "Confirm", func(): _confirm.visible = false; on_yes.call(), true)
	_confirm.visible = true


# ---------------------------------------------------------------- inspect / compare

## Inspect is a full-screen showroom: a dark studio lit in the club's rarity colour
## (shaders/inspect_backdrop.gdshader), the 3D club large on the left under its name block, and
## a glass spec sheet on the right with segmented stat bars against the equipped club, a
## condition meter, value cards and the actions. Panels slide in and the bars fill on open.
const INSPECT_BACKDROP = preload("res://shaders/inspect_backdrop.gdshader")
const INSPECT_STAGE := 0.6  # share of the screen width the 3D stage takes
const INSPECT_TOP := 150.0  # stage space the name block takes above the club
const INSPECT_FOCUS_Y := 0.54  # where the club sits down the screen (the backdrop halo follows)
const INSPECT_GLOW := {"common": 0.34, "uncommon": 0.46, "rare": 0.56, "epic": 0.64, "legendary": 0.74, "mythic": 0.82}
const INSPECT_GLASS := Color(0.05, 0.085, 0.075, 0.84)
const INSPECT_GAIN := Color("5fd38d")
const INSPECT_LOSS := Color("ff6b5b")
const STAT_BAR_SPAN := 0.25  # a +/-25% modifier fills or empties the bar from its midpoint
const DISPERSION_MAX := 1.5  # degrees of spread at which the accuracy bar is empty

## Display face for the showroom screens (shared with the HUD, see UITheme.font).
static func _display_font(weight: int = 600, width: int = 100, spacing: int = 0) -> Font:
	return UITheme.font(weight, width, spacing)


func _dlbl(parent: Node, text: String, size: int, color: Color, font: Font) -> Label:
	var l := _lbl(parent, text, size, color)
	l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Small spaced-out caps heading ("PERFORMANCE", "ASKING").
func _eyebrow(parent: Node, text: String, color: Color = SHOP_DIM) -> Label:
	return _dlbl(parent, text.to_upper(), 11, color, _display_font(600, 100, 2))


## A keyboard/mouse hint drawn as a keycap.
func _keycap(parent: Node, key: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.24), 1, 5, 0)
	sb.border_width_bottom = 2
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlbl(p, key, 10, SHOP_TEXT, _display_font(600, 100, 1))
	parent.add_child(p)
	return p


## Rarity gem: a small glowing diamond.
func _gem(parent: Node, color: Color, sz: float = 12.0) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(sz, sz)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.draw.connect(func():
		var c := g.size * 0.5
		for layer in [[1.0, Color(color, 0.25)], [0.62, color.lightened(0.25)]]:
			var r: float = sz * 0.5 * float(layer[0])
			g.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), layer[1]))
	parent.add_child(g)
	return g


## Fades a control in (and slides it by `from`) when the screen opens. Anchored controls only:
## a container would put the offsets straight back.
func _intro(c: Control, from: Vector2, delay: float, time: float = 0.42) -> void:
	var to_l := c.offset_left
	var to_r := c.offset_right
	var to_t := c.offset_top
	var to_b := c.offset_bottom
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, time * 0.8).set_delay(delay)
	tw.tween_method(func(k: float):
		c.offset_left = to_l + from.x * (1.0 - k)
		c.offset_right = to_r + from.x * (1.0 - k)
		c.offset_top = to_t + from.y * (1.0 - k)
		c.offset_bottom = to_b + from.y * (1.0 - k), 0.0, 1.0, time).set_delay(delay)


## Animates a drawn meter's "t" meta 0 -> 1 after `delay`.
func _fill_in(c: Control, delay: float, time: float = 0.6) -> void:
	c.set_meta("t", 0.0)
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float): c.set_meta("t", v); c.queue_redraw(), 0.0, 1.0, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Bar position for a modifier: stock sits at the midpoint; dispersion (lower is better) runs
## the other way, full at zero spread.
static func _stat_fill(v: float, key: String) -> float:
	if key == "dispersion_deg":
		return clampf(1.0 - v / DISPERSION_MAX, 0.03, 1.0)
	return clampf(0.5 + (v - 1.0) / STAT_BAR_SPAN * 0.5, 0.03, 1.0)


## One spec-sheet bar in ten segments: this club in white, the gain or loss against the
## equipped club in green or red, and a tick where the equipped club sits (`ref` < 0: none).
func _stat_bar(parent: Node, fill: float, ref: float, delay: float) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(120, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		var t: float = bar.get_meta("t", 1.0)
		var w := bar.size.x
		var h := 6.0
		var y := (bar.size.y - h) * 0.5
		var segs := 10
		var gap := 2.0
		var span := func(s: float, e: float, c: Color):
			for i in range(segs):
				var x0 := maxf(w * s, w * i / segs + (gap * 0.5 if i > 0 else 0.0))
				var x1 := minf(w * e, w * (i + 1) / segs - (gap * 0.5 if i < segs - 1 else 0.0))
				if x1 > x0:
					bar.draw_rect(Rect2(x0, y, x1 - x0, h), c)
		span.call(0.0, 1.0, Color(1, 1, 1, 0.08))
		var a := fill * t
		var b := ref * t if ref >= 0.0 else a
		span.call(0.0, minf(a, b), Color(SHOP_TEXT, 0.92))
		if a > b:
			span.call(b, a, INSPECT_GAIN)
		elif a < b:
			span.call(a, b, Color(INSPECT_LOSS, 0.8))
		if ref >= 0.0:
			bar.draw_rect(Rect2(w * b - 1.0, y - 4.0, 2.0, h + 8.0), Color(1, 1, 1, 0.95)))
	parent.add_child(bar)
	_fill_in(bar, delay)
	return bar


## A small up/down arrow plus the difference against the equipped club.
func _stat_delta(parent: Node, a: float, b: float, key: String, higher_is_better: bool) -> void:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(52, 0)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	if is_nan(b) or is_equal_approx(a, b):
		return
	var better := a > b if higher_is_better else a < b
	var col := INSPECT_GAIN if better else INSPECT_LOSS
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(8, 8)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func():
		var s := arrow.size
		var pts := PackedVector2Array([Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x * 0.5, 0)]) if better else PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x * 0.5, s.y)])
		arrow.draw_colored_polygon(pts, col))
	box.add_child(arrow)
	var diff := (("+" if a > b else "-") + _fmt_stat(absf(a - b), key)) if key == "dispersion_deg" else ("%+d" % int(round((a - b) * 100.0)))
	_dlbl(box, diff, 13, col, _display_font(600))


## Spec-sheet value: modifiers as a signed percent, spread in degrees to the hundredth.
static func _fmt_stat(v: float, key: String) -> String:
	if key == "dispersion_deg":
		return ("%.2f" % v).rstrip("0").trim_suffix(".") + "°"
	return _fmt_mod(v, key).to_upper()


## Condition as a 20-cell meter shading red to green, lit up to the club's condition.
func _condition_meter(parent: Node, cond: float, delay: float) -> void:
	var m := Control.new()
	m.custom_minimum_size = Vector2(0, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.draw.connect(func():
		var t: float = m.get_meta("t", 1.0)
		var n := 20
		var gap := 3.0
		var cw := (m.size.x - gap * (n - 1)) / n
		var lit := clampf(cond, 0.0, 1.0) * t * n
		for i in range(n):
			var r := Rect2(i * (cw + gap), 0, cw, m.size.y)
			m.draw_rect(r, Color(1, 1, 1, 0.07))
			var f := clampf(lit - i, 0.0, 1.0)
			if f > 0.0:
				m.draw_rect(Rect2(r.position, Vector2(cw * f, r.size.y)), _cond_color(float(i + 1) / n)))
	parent.add_child(m)
	_fill_in(m, delay, 0.8)


## Thin rule across the spec sheet.
func _sheet_rule(parent: Node) -> void:
	var r := ColorRect.new()
	r.color = SHOP_LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


## Section heading: caps eyebrow on the left, an optional note on the right.
func _sheet_head(parent: Node, title: String, note: String = "", note_color: Color = SHOP_DIM) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	_eyebrow(row, title, SHOP_TEXT)
	if note != "":
		var n := _dlbl(row, note.to_upper(), 11, note_color, _display_font(600, 100, 1))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


## Quote block with a coloured edge (the club's tell, a seller's line).
func _quote_block(parent: Node, heading: String, text: String, edge: Color) -> void:
	var p := PanelContainer.new()
	var sb := _box(Color(1, 1, 1, 0.035), edge, 0, 8, 10)
	sb.border_width_left = 3
	sb.content_margin_left = 12
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	_eyebrow(v, heading, edge.lightened(0.25))
	var l := _lbl(v, text, 13, Color(SHOP_TEXT, 0.82), true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Value tile: caps label over a big number.
func _value_tile(parent: Node, label: String, value: String, color: Color, size: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.04), SHOP_LINE, 1, 10, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	_eyebrow(v, label)
	_dlbl(v, value, size, color, _display_font(700, 100))
	return p


## Big showroom action button: "primary" glows green, otherwise glass.
func _inspect_btn(parent: Node, text: String, cb: Callable, primary: bool, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	b.add_theme_font_override("font", _display_font(700, 100, 2))
	b.add_theme_font_size_override("font_size", 16 if primary else 14)
	var bg := SHOP_GO if primary else Color(1, 1, 1, 0.06)
	var edge := SHOP_GO.lightened(0.3) if primary else Color(1, 1, 1, 0.16)
	var normal := _box(bg, edge, 1, 10, 10)
	normal.border_width_top = 2 if primary else 1
	if primary:
		normal.shadow_color = Color(SHOP_GO, 0.35)
		normal.shadow_size = 10
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = bg.lightened(0.14) if primary else Color(1, 1, 1, 0.12)
	hover.border_color = edge.lightened(0.25)
	hover.shadow_color = Color(SHOP_GO.lightened(0.2), 0.6) if primary else Color(1, 1, 1, 0.06)
	hover.shadow_size = 18 if primary else 8
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.03), SHOP_LINE, 1, 10, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE if primary else SHOP_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(SHOP_DIM, 0.55))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## ctx.kind: "listing" {store_id, listing} | "owned" {instance, just_bought?} | "preview" {listing}
func _show_inspect(model: Dictionary, ctx: Dictionary) -> void:
	var gs := _gs()
	# Drop every hover lift on the shelf under the overlay.
	for c in _content.find_children("*", "PanelContainer", true, false):
		if c.has_meta("shelf_card"):
			c.mouse_exited.emit()
	var kind := str(ctx.get("kind", "owned"))
	var inst: ClubInstance = ctx.get("instance", null)
	var listing: Dictionary = ctx.get("listing", {})
	var cond := inst.condition if inst != null else float(listing.get("condition", 0.7))
	var rarity := str(model.get("rarity", "common"))
	var rcol := EconomyConfig.rarity_color(rarity)
	var is_putter := ClubCatalog.is_putter(model)
	_clear(_inspect)

	# ---- studio backdrop
	var view_size := _root.get_viewport_rect().size
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var bm := ShaderMaterial.new()
	bm.shader = INSPECT_BACKDROP
	bm.set_shader_parameter("accent", rcol)
	bm.set_shader_parameter("glow", float(INSPECT_GLOW.get(rarity, 0.5)))
	bm.set_shader_parameter("aspect", view_size.x / maxf(view_size.y, 1.0))
	bm.set_shader_parameter("focus", Vector2(INSPECT_STAGE * 0.5, INSPECT_FOCUS_Y))
	backdrop.material = bm
	_inspect.add_child(backdrop)

	# ---- 3D stage
	var stage := Control.new()
	stage.anchor_right = INSPECT_STAGE
	stage.anchor_bottom = 1.0
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.add_child(stage)
	var watermark := _dlbl(stage, _kind_label(model).to_upper(), 210, Color(1, 1, 1, 0.035), _display_font(700, 75))
	watermark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watermark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	watermark.clip_text = true
	var viewer := ClubViewer3D.new()
	viewer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Runs past the bottom of the screen so the club sits at INSPECT_FOCUS_Y while its
	# shaft carries on up out of frame.
	viewer.offset_left = 24
	viewer.offset_bottom = view_size.y * (INSPECT_FOCUS_Y - 0.5) * 2.0
	stage.add_child(viewer)
	var top_fade := TextureRect.new()
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = Gradient.new()
	fade_tex.gradient.set_color(0, Color(0.01, 0.02, 0.018, 0.85))
	fade_tex.gradient.set_color(1, Color(0.01, 0.02, 0.018, 0.0))
	fade_tex.fill_from = Vector2(0, 0)
	fade_tex.fill_to = Vector2(0, 1)
	top_fade.texture = fade_tex
	top_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_fade.stretch_mode = TextureRect.STRETCH_SCALE
	top_fade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_fade.offset_bottom = INSPECT_TOP + 40.0
	top_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.add_child(top_fade)
	var start_yaw := PI if is_putter else 0.0
	var has_3d := viewer.show_model(str(model.get("id", "")), cond, AdminAccess.is_admin(), start_yaw)
	if has_3d:
		viewer.set_accent(rcol)
	else:
		viewer.queue_free()
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.offset_top = INSPECT_TOP
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(center)
		_silhouette(center, model, cond, Vector2(520, 400))

	# ---- name block (top-left, over the stage)
	var title := VBoxContainer.new()
	title.anchor_right = INSPECT_STAGE
	title.offset_left = 40
	title.offset_top = 26
	title.offset_right = -24
	title.add_theme_constant_override("separation", 4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.add_child(title)
	var crumbs := {"shop": "Shop", "bag": "Bag", "collection": "Collection", "objectives": "Objectives", "admin": "Catalog"}
	var crumb_where := str(crumbs.get(_tab, "Clubhouse"))
	if kind == "listing":
		crumb_where = EconomyConfig.store_name(str(ctx.get("store_id", "")))
	_eyebrow(title, "Clubhouse   /   %s   /   Inspect" % crumb_where, Color(SHOP_DIM, 0.8))
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(tag_row)
	_gem(tag_row, rcol)
	_dlbl(tag_row, "%s   ·   %s" % [rarity.to_upper(), _kind_label(model).to_upper()], 13, rcol.lightened(0.3), _display_font(700, 100, 3))
	# A store that hides brand names keeps it hidden here too: the same label as its card.
	var shown_name := str(model.get("name", ""))
	if kind == "listing" and not bool(EconomyConfig.store(str(ctx.get("store_id", ""))).get("reveals_names", false)):
		shown_name = ClubSilhouette.shop_label(model)
	var name_lbl := _dlbl(title, shown_name, 44, Color.WHITE, _display_font(700, 85))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	name_lbl.add_theme_constant_override("shadow_offset_x", 0)
	name_lbl.add_theme_constant_override("shadow_offset_y", 3)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 8)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(under)
	var accent_bar := ColorRect.new()
	accent_bar.color = rcol.lightened(0.15)
	accent_bar.custom_minimum_size = Vector2(56, 3)
	accent_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(accent_bar)
	if bool(ctx.get("just_bought", false)):
		_pill(under, "JUST BOUGHT", SHOP_PRICE, SHOP_BG)
	if inst != null and gs.is_equipped(inst.id):
		_pill(under, "EQUIPPED", SHOP_GO, Color.WHITE)
	if ClubCatalog.is_collectible_putter(model):
		_pill(under, "CABINET PIECE", GOLD, SHOP_BG)
	if ClubCatalog.is_illegal(model):
		_pill(under, "ILLEGAL", RED, Color.WHITE)
	if str(model.get("feel", "")) != "":
		_dlbl(under, str(model["feel"]), 13, SHOP_DIM, _display_font(400))
	_intro(title, Vector2(-36, 0), 0.0)

	# ---- control hints (bottom-left)
	if has_3d:
		var hints := HBoxContainer.new()
		hints.anchor_top = 1.0
		hints.anchor_bottom = 1.0
		hints.offset_left = 40
		hints.offset_top = -44
		hints.offset_bottom = -20
		hints.add_theme_constant_override("separation", 8)
		hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inspect.add_child(hints)
		for h in [["DRAG", "Rotate"], ["SCROLL", "Zoom"], ["DOUBLE-CLICK", "Reset view"]]:
			_keycap(hints, h[0])
			var hl := _dlbl(hints, h[1], 12, SHOP_DIM, _display_font(400))
			hl.custom_minimum_size.x = hl.get_minimum_size().x + 10

	# ---- close (top-right)
	var close_btn := PanelContainer.new()
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -150
	close_btn.offset_right = -28
	close_btn.offset_top = 22
	close_btn.offset_bottom = 54
	close_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var cb_base := _box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 1, 8, 6)
	var cb_hover := _box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.16), 1, 8, 6)
	close_btn.add_theme_stylebox_override("panel", cb_base)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.mouse_entered.connect(func(): close_btn.add_theme_stylebox_override("panel", cb_hover))
	close_btn.mouse_exited.connect(func(): close_btn.add_theme_stylebox_override("panel", cb_base))
	close_btn.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_inspect.visible = false)
	_inspect.add_child(close_btn)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	close_row.add_theme_constant_override("separation", 8)
	close_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_btn.add_child(close_row)
	_keycap(close_row, "ESC")
	_dlbl(close_row, "CLOSE", 13, SHOP_TEXT, _display_font(600, 100, 2))
	if kind == "listing":
		var wallet := HBoxContainer.new()
		wallet.anchor_left = 1.0
		wallet.anchor_right = 1.0
		wallet.offset_left = -420
		wallet.offset_right = -170
		wallet.offset_top = 22
		wallet.offset_bottom = 54
		wallet.alignment = BoxContainer.ALIGNMENT_END
		wallet.add_theme_constant_override("separation", 8)
		wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inspect.add_child(wallet)
		_eyebrow(wallet, "Wallet")
		_dlbl(wallet, _money(gs.cash), 20, SHOP_PRICE, _display_font(700))

	# ---- spec sheet (right)
	var panel := PanelContainer.new()
	panel.anchor_left = INSPECT_STAGE
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 4
	panel.offset_right = -28
	panel.offset_top = 70
	panel.offset_bottom = -24
	var glass := _box(INSPECT_GLASS, Color(1, 1, 1, 0.09), 1, 18, 22)
	glass.shadow_color = Color(0, 0, 0, 0.5)
	glass.shadow_size = 28
	glass.shadow_offset = Vector2(0, 8)
	panel.add_theme_stylebox_override("panel", glass)
	_inspect.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(scroll)
	var sheet := VBoxContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("separation", 14)
	scroll.add_child(sheet)
	# Rarity edge along the top of the glass (drawn over the panel, outside its margins).
	var edge := ColorRect.new()
	edge.color = rcol
	edge.anchor_left = INSPECT_STAGE
	edge.anchor_right = 1.0
	edge.offset_left = 4 + 18
	edge.offset_right = -28 - 18
	edge.offset_top = 70
	edge.offset_bottom = 73
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect.add_child(edge)

	# About
	var desc := _lbl(sheet, str(model.get("desc", "")), 15, Color(SHOP_TEXT, 0.94), true)
	desc.add_theme_constant_override("line_spacing", 2)
	if str(model.get("tell", "")) != "":
		_quote_block(sheet, "Look closer", str(model["tell"]), rcol)
	_sheet_rule(sheet)

	# Performance vs the equipped club
	var equipped := gs.equipped_for_model(model)
	var same := equipped != null and inst != null and equipped.id == inst.id
	var vs_note := "Equipped" if same else ("vs " + equipped.display_name() if equipped != null else "Slot empty")
	_sheet_head(sheet, "Performance", vs_note)
	var mods: Dictionary = model.get("mods", {})
	var emods: Dictionary = equipped.model().get("mods", {}) if equipped != null and not same else {}
	var rows := [["Forgiveness", "forgiveness", true], ["Control", "control", true]] if is_putter else [["Distance", "distance", true], ["Forgiveness", "forgiveness", true], ["Spin", "spin", true], ["Control", "control", true], ["Accuracy", "dispersion_deg", false]]
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 7)
	sheet.add_child(stats)
	for i in range(rows.size()):
		var r: Array = rows[i]
		var key: String = r[1]
		var stock := 0.0 if key == "dispersion_deg" else 1.0
		var a := float(mods.get(key, stock))
		var b := float(emods.get(key, stock)) if not emods.is_empty() else NAN
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(row)
		var nl := _dlbl(row, r[0], 14, Color(SHOP_TEXT, 0.78), _display_font(500))
		nl.custom_minimum_size.x = 92
		_stat_bar(row, _stat_fill(a, key), -1.0 if is_nan(b) else _stat_fill(b, key), 0.3 + 0.07 * i)
		var vl := _dlbl(row, _fmt_stat(a, key), 15, Color.WHITE, _display_font(700))
		vl.custom_minimum_size.x = 54
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stat_delta(row, a, b, key, r[2])
	if not emods.is_empty():
		var legend := HBoxContainer.new()
		legend.add_theme_constant_override("separation", 6)
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(legend)
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.95)
		tick.custom_minimum_size = Vector2(2, 12)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(tick)
		_dlbl(legend, "Equipped club   ·   arrows show the difference", 11, SHOP_DIM, _display_font(400, 100, 1))
	if is_putter:
		_lbl(sheet, "Putters differ in feel and forgiveness only. No putter makes a putt go in by itself.", 12, SHOP_DIM, true)
	_sheet_rule(sheet)

	# Condition
	var grade_col := _cond_color(cond)
	_sheet_head(sheet, "Condition", "%s   ·   %d%%" % [EconomyConfig.condition_grade(cond), int(round(cond * 100.0))], grade_col)
	_condition_meter(sheet, cond, 0.35)
	if equipped != null and not same:
		_dlbl(sheet, "Your equipped %s is at %d%%" % [equipped.display_name(), int(round(equipped.condition * 100.0))], 12, SHOP_DIM, _display_font(400))
	_sheet_rule(sheet)

	# Value
	var fair := EconomyConfig.fair_value(model, cond)
	_sheet_head(sheet, "Value")
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	sheet.add_child(tiles)
	if kind == "listing":
		var price := int(listing.get("price", 0))
		_value_tile(tiles, "Asking", _money(price), SHOP_PRICE, 32)
		_value_tile(tiles, "Fair value", _money(fair), SHOP_TEXT, 24)
		var verdict := ["FAIR PRICE", Color(1, 1, 1, 0.14), SHOP_TEXT]
		if fair > 0 and price < fair * 0.8:
			verdict = ["GREAT PRICE", INSPECT_GAIN, SHOP_BG]
		elif fair > 0 and price > fair * 1.3:
			verdict = ["OVERPRICED", INSPECT_LOSS, SHOP_BG]
		var vrow := HBoxContainer.new()
		vrow.add_theme_constant_override("separation", 6)
		sheet.add_child(vrow)
		_pill(vrow, verdict[0], verdict[1], verdict[2])
		if str(listing.get("haggled", "")) == "accepted":
			_pill(vrow, "DEAL · WAS %s" % _money(int(listing.get("list_price", price))), SHOP_GO, Color.WHITE)
		if bool(listing.get("reserved", false)):
			_pill(vrow, "ON HOLD · %d ROUNDS · %s DUE" % [int(listing.get("reserve_rounds_left", 0)), _money(price - int(listing.get("deposit", 0)))], SHOP_PRICE, SHOP_BG)
		if str(listing.get("seller", "")) != "":
			_quote_block(sheet, "Seller  ·  " + str(listing["seller"]), "“%s”" % listing.get("seller_blurb", ""), SHOP_PRICE.darkened(0.15))
		if str(listing.get("provenance", "")) != "":
			_lbl(sheet, str(listing["provenance"]), 12, SHOP_DIM, true)
	elif inst != null:
		if not inst.is_starter():
			_value_tile(tiles, "Paid", _money(inst.purchase_price), SHOP_TEXT)
		_value_tile(tiles, "Worth now", _money(fair), SHOP_PRICE)
		if not inst.is_starter() and not inst.is_illegal():
			_value_tile(tiles, "Shops offer", _money(inst.resale_offer()), SHOP_TEXT)
		var hist := "Found at %s   ·   %d round%s   ·   %d stroke%s" % [inst.source_label(), inst.rounds_played, "" if inst.rounds_played == 1 else "s", inst.strokes, "" if inst.strokes == 1 else "s"]
		var hl := _lbl(sheet, hist, 12, SHOP_DIM, true)
		hl.add_theme_font_override("font", _display_font(400))
		if inst.provenance != "":
			_lbl(sheet, inst.provenance, 12, SHOP_DIM, true)
	else:
		_value_tile(tiles, "Fair value at %d%%" % int(round(cond * 100.0)), _money(fair), SHOP_PRICE)

	# ---- actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	if kind == "listing":
		var sid := str(ctx.get("store_id", ""))
		var lid := str(listing.get("id", ""))
		var due := int(listing.get("price", 0)) - (int(listing.get("deposit", 0)) if bool(listing.get("reserved", false)) else 0)
		if not bool(listing.get("reserved", false)):
			var dep := EconomyConfig.reserve_deposit(int(listing.get("price", 0)))
			var hold := _inspect_btn(actions, "Hold  %s" % _money(dep), func(): _reserve(sid, lid); _inspect.visible = false, false, gs.cash >= dep)
			hold.custom_minimum_size.x = 130
			hold.tooltip_text = "Keep it on the shelf for %d more rounds; the deposit counts toward the price." % int(EconomyConfig.reserve_cfg().get("extra_rounds", 2))
		var buy := _inspect_btn(actions, ("Buy  ·  %s" % _money(due)) if gs.cash >= due else "Need %s more" % _money(due - gs.cash), func(): _buy(sid, lid), true, gs.cash >= due)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif inst != null:
		var can_edit: bool = gs.can_edit_bag()["ok"]
		if not inst.is_starter() and not inst.is_illegal():
			var sell := _inspect_btn(actions, "Sell  %s" % _money(inst.resale_offer()), func(): _sell_dialog(inst), false, gs.can_sell(inst.id)["ok"])
			sell.custom_minimum_size.x = 140
		if gs.is_equipped(inst.id):
			var eq := _inspect_btn(actions, "Equipped", func(): pass, true, false)
			eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			var eq := _inspect_btn(actions, "Equip", func():
				var r := gs.equip(inst.id)
				if r["ok"]:
					_notice("Equipped %s." % inst.display_name())
					_inspect.visible = false
				else:
					_notice(str(r["error"]), true), true, can_edit and (not inst.is_illegal() or AdminAccess.is_admin()))
			eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if actions.get_child_count() > 0:
		_sheet_rule(col)
		col.add_child(actions)
	else:
		actions.queue_free()
	_intro(panel, Vector2(48, 0), 0.06, 0.5)
	_intro(edge, Vector2(48, 0), 0.06, 0.5)
	_inspect.visible = true


static func _fmt_mod(v: float, key: String) -> String:
	if key == "dispersion_deg":
		return "%.1f°" % v
	var pct := int(round((v - 1.0) * 100.0))
	return "%+d%%" % pct if pct != 0 else "stock"


# ---------------------------------------------------------------- collection

func _build_collection(parent: Node) -> void:
	var gs := _gs()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	parent.add_child(vb)
	var seven := ClubCatalog.collectible_putters()
	var owned_n := gs.owned_collectible_count()
	var disc_n := 0
	for m in seven:
		if gs.is_discovered(str(m["id"])):
			disc_n += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	_lbl(head, "Putter Cabinet", 22, INK)
	_lbl(head, "%d of %d owned  ·  %d ever discovered" % [owned_n, seven.size(), disc_n], 14, MUTED)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_btn(head, "Showcase view", func(): _show_showcase())
	if gs.completion_reward_earned:
		var banner := PanelContainer.new()
		banner.add_theme_stylebox_override("panel", _box(GOLD, GOLD.darkened(0.3), 2, 8, 8))
		vb.add_child(banner)
		var cr := EconomyConfig.completion_reward()
		_lbl(banner, "%s earned after round %d: %s" % [cr.get("name", "Completion reward"), gs.completion_reward_round, cr.get("description", "")], 13, SHOP_BG, true)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 8)
	vb.add_child(cab)
	for i in range(seven.size()):
		_cabinet_slot(cab, seven[i], i, Vector2(140, 108), gs.completion_reward_earned)
	if _cabinet_selected >= 0 and _cabinet_selected < seven.size():
		var m: Dictionary = seven[_cabinet_selected]
		var det := _card(vb, 10)
		var dh := HBoxContainer.new()
		dh.add_theme_constant_override("separation", 12)
		det.add_child(dh)
		var dv := VBoxContainer.new()
		dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dh.add_child(dv)
		var inst := gs.owned_instance_of_model(str(m["id"]))
		var disc := gs.discovery(str(m["id"]))
		var t := HBoxContainer.new()
		t.add_theme_constant_override("separation", 8)
		dv.add_child(t)
		_lbl(t, str(m["name"]) if not disc.is_empty() else "???", 18, INK)
		_chip(t, str(m["rarity"]).capitalize(), EconomyConfig.rarity_color(str(m["rarity"])))
		if inst != null:
			_lbl(dv, "%s  ·  Found at %s for %s  ·  Condition %s (%d%%)  ·  %d round%s played" % [m.get("feel", ""), inst.source_label(), _money(inst.purchase_price), inst.condition_grade(), int(round(inst.condition * 100.0)), inst.rounds_played, "" if inst.rounds_played == 1 else "s"], 13, MUTED, true)
			_lbl(dv, str(m.get("desc", "")), 13, INK, true)
			var br := HBoxContainer.new()
			dv.add_child(br)
			_btn(br, "Inspect", func(): _show_inspect(m, {"kind": "owned", "instance": inst}))
		elif not disc.is_empty():
			_lbl(dv, "Discovered once at %s for %s, then sold. The record stands; the cabinet slot doesn't." % [EconomyConfig.store_name(str(disc.get("store", ""))), _money(int(disc.get("price", 0)))], 13, MUTED, true)
			_lbl(dv, str(m.get("desc", "")), 13, INK, true)
		else:
			_lbl(dv, "Never found. %s. Every store can turn one up." % ClubSilhouette.label_for(str(m.get("silhouette", ""))), 13, MUTED, true)
	else:
		_lbl(vb, "Click a slot to see where you found it. Missing putters use grey previews; every store has a chance at every one.", 12, MUTED, true)

	# Broader catalog
	_lbl(vb, "The rest of the catalog", 18, INK)
	var prog := gs.catalog_progress()
	var line := ""
	for t in ClubCatalog.type_order():
		if t == "putter":
			continue
		var p: Dictionary = prog[t]
		line += "%s %d/%d owned (%d seen)    " % [ClubCatalog.type_label(t) + "s", p["owned"], p["total"], p["discovered"]]
	_lbl(vb, line, 13, MUTED, true)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for t in ClubCatalog.type_order():
		if t == "putter":
			continue
		for m in ClubCatalog.lootable_models():
			if str(m["type"]) != t:
				continue
			var mid := str(m["id"])
			var owned := gs.owns_model(mid)
			var seen := gs.is_discovered(mid)
			var c := _card(grid, 5)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ch := HBoxContainer.new()
			ch.add_theme_constant_override("separation", 6)
			c.add_child(ch)
			_silhouette(ch, m, 1.0, Vector2(54, 42), not owned)
			var cv := VBoxContainer.new()
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ch.add_child(cv)
			_lbl(cv, str(m["name"]) if seen else "???  (%s)" % ClubCatalog.type_label(t), 12, INK if seen else MUTED)
			_lbl(cv, ("Owned" if owned else ("Discovered, sold" if seen else "Undiscovered")) + "  ·  " + str(m["rarity"]).capitalize(), 11, EconomyConfig.rarity_color(str(m["rarity"])).lightened(0.3) if seen else MUTED)


func _cabinet_slot(parent: Node, m: Dictionary, index: int, sz: Vector2, gold: bool) -> void:
	var gs := _gs()
	var mid := str(m["id"])
	var inst := gs.owned_instance_of_model(mid)
	var seen := gs.is_discovered(mid)
	var slot := PanelContainer.new()
	var frame_col := GOLD if gold else (Color(1, 1, 1, 0.55) if _cabinet_selected == index else Color(1, 1, 1, 0.12))
	slot.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03) if inst == null else Color(1, 1, 1, 0.07), frame_col, 2 if _cabinet_selected == index or gold else 1, 10, 6))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	slot.add_child(v)
	var sil := _silhouette(v, m, inst.condition if inst != null else 1.0, sz, inst == null)
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_txt := str(m["name"]) if seen else "???"
	var nl := _lbl(v, name_txt, 12, INK if inst != null else MUTED)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st := "Owned" if inst != null else ("Sold" if seen else str(m["rarity"]).capitalize())
	var sl := _lbl(v, st, 11, EconomyConfig.rarity_color(str(m["rarity"])).lightened(0.3))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_cabinet_selected = index
			_refresh())


## Clean full-screen cabinet for screenshots: paper background, seven frames, a plaque.
func _show_showcase() -> void:
	var gs := _gs()
	_clear(_showcase)
	var complete_now := gs.putter_collection_complete()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bm := ShaderMaterial.new()
	bm.shader = INSPECT_BACKDROP
	bm.set_shader_parameter("accent", GOLD if complete_now else GREEN)
	bm.set_shader_parameter("focus", Vector2(0.5, 0.5))
	bm.set_shader_parameter("glow", 0.55)
	var svs := _root.get_viewport_rect().size
	bm.set_shader_parameter("aspect", svs.x / maxf(svs.y, 1.0))
	bm.set_shader_parameter("floor_amount", 0.0)
	bg.material = bm
	_showcase.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 60
	vb.offset_right = -60
	vb.offset_top = 40
	vb.offset_bottom = -30
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_showcase.add_child(vb)
	var complete := gs.putter_collection_complete()
	var title := _dlbl(vb, "THE CABINET" if not complete else "THE GOLD CABINET", 44, Color.WHITE, _display_font(700, 85, 4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _lbl(vb, "%d of %d collectible putters" % [gs.owned_collectible_count(), ClubCatalog.collectible_putters().size()], 16, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.3), GOLD if complete else Color(1, 1, 1, 0.14), 2, 16, 18))
	vb.add_child(frame)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	frame.add_child(cab)
	var seven := ClubCatalog.collectible_putters()
	for i in range(seven.size()):
		var m: Dictionary = seven[i]
		var inst := gs.owned_instance_of_model(str(m["id"]))
		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.07) if inst != null else Color(1, 1, 1, 0.025), GOLD if complete else Color(1, 1, 1, 0.14), 1, 10, 8))
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cab.add_child(slot)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		slot.add_child(v)
		_silhouette(v, m, inst.condition if inst != null else 1.0, Vector2(140, 130), inst == null)
		var nl := _lbl(v, str(m["name"]) if inst != null else "?", 13, INK if inst != null else MUTED)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var rl := _lbl(v, str(m["rarity"]).capitalize(), 11, EconomyConfig.rarity_color(str(m["rarity"])).lightened(0.3))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if inst != null:
			var fl := _lbl(v, "%s · %s" % [inst.source_label(), _money(inst.purchase_price)], 10, MUTED)
			fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", _box(GOLD if complete else Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.15), 1, 8, 10))
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(plaque)
	var best := gs.best_round
	var ptxt := "%d rounds played" % gs.rounds_completed
	if not best.is_empty():
		ptxt += "   ·   best round %d (%+d)" % [int(best.get("total", 0)), int(best.get("rel_par", 0))]
	if complete:
		ptxt = "COLLECTION COMPLETE   ·   " + ptxt
	_lbl(plaque, ptxt, 14, SHOP_BG if complete else INK)
	var hint := _lbl(vb, "Esc or click to return", 12, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_showcase.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_showcase.visible = false)
	_showcase.visible = true


# ---------------------------------------------------------------- objectives

func _build_objectives(parent: Node) -> void:
	var gs := _gs()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	parent.add_child(vb)
	_lbl(vb, "Next up: " + Progression.next_objective(gs), 16, GREEN, true)
	var rc := EconomyConfig.round_cfg()
	_lbl(vb, "A round is the first %d holes. Finishing one pays about $%d plus small bonuses for pars, score and milestones. Mulligans and restarts still pay, but that round can't qualify for an unlock or a personal best. Skipping a hole abandons the round. Every round also rolls three side bets (shown on the course HUD) that pay extra when you finish." % [EconomyConfig.holes_per_round(), int(round(float(rc.get("base_payout_per_9", 35)) * EconomyConfig.holes_per_round() / 9.0))], 12, MUTED, true)
	for s in EconomyConfig.stores():
		var st := Progression.status(gs, s)
		var card := _card(vb, 8)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		cv.add_child(row)
		_lbl(row, str(st["name"]), 16, INK)
		_chip(row, "Unlocked" if st["unlocked"] else "Locked", GREEN if st["unlocked"] else MUTED)
		for line in st["lines"]:
			_lbl(cv, "  " + str(line), 13, INK if not st["unlocked"] else MUTED, true)
	var stats := _card(vb, 8)
	var sv := VBoxContainer.new()
	stats.add_child(sv)
	var best := gs.best_round
	_lbl(sv, "Rounds completed: %d     Sandbox rounds: %d     Best round: %s" % [gs.rounds_completed, gs.sandbox_rounds, ("%d (%+d)" % [int(best.get("total", 0)), int(best.get("rel_par", 0))]) if not best.is_empty() else "-"], 13, INK)
	_lbl(sv, "Purchases: %d     Sales: %d     Cash: %s" % [gs.purchases.size(), gs.sales.size(), _money(gs.cash)], 13, INK)


# ---------------------------------------------------------------- admin sandbox

## Every catalog model (starters, loot, illegal, collectible putters), grouped by type, with
## one click into the real inspect dialog -- 3D viewer, stats, condition -- at Mint condition,
## and one click to wear it: GameState.admin_equip() equips an owned copy if the player has
## one, else spawns a Mint admin copy, no purchase/loot/unlock required.
func _build_admin_browser(vb: Node) -> void:
	var gs := _gs()
	_lbl(vb, "Browse All Clubs (testing)", 20, INK)
	_lbl(vb, "Every model in the catalog. Inspect opens the real inspect dialog at Mint condition. Equip wears it immediately -- your own copy if you have one, else a Mint admin copy -- no purchase, loot or unlock required.", 12, MUTED, true)
	var types := ClubCatalog.type_order()
	for t in types:
		var of_type: Array = []
		for m in ClubCatalog.models():
			if str(m.get("type", "")) == t:
				of_type.append(m)
		if of_type.is_empty():
			continue
		_lbl(vb, "%s  (%d)" % [ClubCatalog.type_label(t) + "s", of_type.size()], 15, INK)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 6)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(grid)
		for m in of_type:
			var c := _card(grid, 5)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ch := HBoxContainer.new()
			ch.add_theme_constant_override("separation", 6)
			c.add_child(ch)
			_silhouette(ch, m, 1.0, Vector2(54, 42))
			var cv := VBoxContainer.new()
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ch.add_child(cv)
			_lbl(cv, str(m.get("name", "")), 12, INK)
			var tags := str(m.get("rarity", "")).capitalize()
			if ClubCatalog.is_starter(m):
				tags += "  ·  Starter"
			if ClubCatalog.is_illegal(m):
				tags += "  ·  Illegal"
			_lbl(cv, tags, 11, EconomyConfig.rarity_color(str(m.get("rarity", ""))).lightened(0.3))
			var mid := str(m.get("id", ""))
			var cur := gs.equipped_for_model(m)
			var eq := cur != null and cur.model_id == mid
			var br := HBoxContainer.new()
			br.add_theme_constant_override("separation", 6)
			cv.add_child(br)
			_btn(br, "Inspect", func(): _show_inspect(m, {"kind": "preview", "listing": {"condition": 1.0}}))
			_btn(br, "Equipped" if eq else "Equip", func():
				var r := gs.admin_equip(mid)
				if r["ok"]:
					_notice("Equipped " + str(m.get("name", "")) + ".")
				else:
					_notice(str(r["error"]), true), true, not eq and gs.can_edit_bag()["ok"])
	vb.add_child(HSeparator.new())


func _build_admin(parent: Node) -> void:
	var gs := _gs()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_lbl(vb, "Admin cheats", 20, GREEN)
	_lbl(vb, "These change your real save: cash, store unlocks and owned clubs.", 12, MUTED, true)
	var cheats := HBoxContainer.new()
	cheats.add_theme_constant_override("separation", 6)
	vb.add_child(cheats)
	for amount in [100, 1000, 10000]:
		var a: int = amount
		_btn(cheats, "+$%d" % a, func(): gs.admin_add_cash(a); _notice("Added $%d." % a), true)
	_btn(cheats, "Unlock every store", func(): gs.admin_unlock_all_stores(); _notice("Every store unlocked."), true)
	_btn(cheats, "Restock shops", func(): gs.admin_restock(); _notice("Every shop restocked."), true)
	_btn(cheats, "Own every club", func():
		var r := gs.admin_grant_all_clubs()
		_notice("Granted %d clubs (Mint). Equip them from the Bag tab." % int(r.get("granted", 0))), true, gs.can_edit_bag()["ok"])
	_btn(cheats, "Everything", func():
		gs.admin_add_cash(10000)
		gs.admin_unlock_all_stores()
		var r := gs.admin_grant_all_clubs()
		_notice("+$10000, every store unlocked, %d clubs granted." % int(r.get("granted", 0))), true)
	_build_admin_browser(vb)
	_lbl(vb, "Illegal Clubs (admin sandbox)", 20, RED)
	_lbl(vb, "These never appear in shops, loot, resale, trading or the collection. Swinging one turns the round into a sandbox round: no money, no unlock progress, no restock, no records. Admin is on for every launch (project setting golf/admin_always_on); set GOLF_ADMIN=0 to play without it.", 12, MUTED, true)
	_btn(vb, "Grant & Equip All", func():
		gs.grant_and_equip_all_sandbox()
		_notice("Every illegal club granted and equipped."), true, gs.can_edit_bag()["ok"])
	for m in ClubCatalog.illegal_models():
		var mid := str(m["id"])
		var card := _card(vb, 8)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		card.add_child(hb)
		_silhouette(hb, m, 1.0, Vector2(110, 88))
		var cv := VBoxContainer.new()
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(cv)
		_lbl(cv, str(m["name"]), 16, INK)
		_lbl(cv, str(m.get("desc", "")), 12, MUTED, true)
		var have: ClubInstance = null
		for inst in gs.sandbox_instances():
			if inst.model_id == mid:
				have = inst
		var br := HBoxContainer.new()
		br.add_theme_constant_override("separation", 6)
		cv.add_child(br)
		if have == null:
			_btn(br, "Grant", func():
				var r := gs.grant_sandbox(mid)
				_notice("Granted." if r["ok"] else str(r["error"]), not r["ok"]), true)
		else:
			var eq := gs.is_equipped(have.id)
			_btn(br, "Equipped" if eq else "Equip", func():
				var r := gs.equip(have.id)
				if not r["ok"]:
					_notice(str(r["error"]), true), true, not eq and gs.can_edit_bag()["ok"])
			_btn(br, "Remove", func(): gs.remove_sandbox(have.id); _notice("Removed from the sandbox."))
	_lbl(vb, "Unlimited money (testing)", 20, RED)
	_lbl(vb, "The wallet stays full while this is on, for trying out shops, clubs and the Course Manager. Your real balance ($%d) is set aside and comes back when you turn it off; anything bought meanwhile is kept." % (gs._real_cash if gs.unlimited_money else gs.cash), 12, MUTED, true)
	_btn(vb, "Turn off unlimited money" if gs.unlimited_money else "Turn on unlimited money", func():
		gs.set_unlimited_money(not gs.unlimited_money)
		_notice("Unlimited money on." if gs.unlimited_money else "Unlimited money off: your real balance is back."), true)
	_lbl(vb, "Save file: %s" % ProjectSettings.globalize_path(gs.save_path), 11, MUTED, true)
	_btn(vb, "Reset save (new game)", func(): _confirm_dialog("Wipe the save and start over with $%d and the loaner bag?" % EconomyConfig.starting_cash(), func(): gs.new_game(); _notice("New game started.")))


# ---------------------------------------------------------------- round summary

func show_round_summary(summary: Dictionary, result: Dictionary) -> void:
	_open = true
	_root.visible = true
	_tab = "shop"
	_refresh()
	var vb := _overlay_panel(_summary, 760, 600)
	var sandbox := bool(summary.get("sandbox", false))
	var complete := bool(summary.get("complete", false))
	var title := "Round complete"
	if sandbox:
		title = "Sandbox round"
	elif not complete:
		title = "Round not completed"
	if summary.get("already_processed", false):
		title += " (already recorded)"
	_lbl(vb, title, 28, INK)
	var total := int(summary.get("total", result.get("total", 0)))
	var rel := int(summary.get("rel_par", result.get("rel_par", 0)))
	_lbl(vb, "%d strokes  (%+d)" % [total, rel] + ("   ·   new personal best!" if summary.get("new_best", false) else ""), 20, GREEN if rel <= 0 else INK)
	var holes: Array = summary.get("hole_strokes", result.get("hole_strokes", []))
	var pars: Array = summary.get("pars", result.get("pars", []))
	var start_hole := int(summary.get("start_hole", result.get("start_hole", 0)))
	if not holes.is_empty():
		var g := GridContainer.new()
		g.columns = holes.size() + 1
		g.add_theme_constant_override("h_separation", 10)
		vb.add_child(g)
		_lbl(g, "Hole", 12, MUTED)
		for i in range(holes.size()):
			_lbl(g, str(start_hole + i + 1), 12, MUTED)
		_lbl(g, "Par", 12, MUTED)
		for p in pars:
			_lbl(g, str(p), 12, MUTED)
		_lbl(g, "You", 12, INK)
		for i in range(holes.size()):
			var s := int(holes[i])
			var d := s - int(pars[i]) if i < pars.size() else 0
			_lbl(g, str(s) if s >= 0 else "-", 12, GREEN if d < 0 else (INK if d == 0 else RED))
	var bets: Array = summary.get("side_bets", [])
	if not bets.is_empty():
		_lbl(vb, "Side bets", 15, INK)
		for b in bets:
			var won: bool = b["status"] == SideBets.WON
			_lbl(vb, "   %s  %s   %s" % ["✓" if won else "✗", b["text"], ("+" + _money(int(b["reward"]))) if won else "missed"], 13, GREEN if won else MUTED)
	var breakdown: Array = summary.get("breakdown", [])
	if not breakdown.is_empty():
		_lbl(vb, "Money", 15, INK)
		for b in breakdown:
			_lbl(vb, "   %s   %s" % [_money(int(b[1])), b[0]], 13, INK)
		_lbl(vb, "   Earned %s   ·   cash now %s" % [_money(int(summary.get("payout", 0))), _money(int(summary.get("cash_after", _gs().cash)))], 15, GREEN)
	for n in summary.get("notes", []):
		_lbl(vb, str(n), 12, RED, true)
	var un: Array = summary.get("unlocked_now", [])
	for sid in un:
		_lbl(vb, "NEW LOCATION UNLOCKED: %s" % EconomyConfig.store_name(str(sid)), 16, GOLD)
	for q in summary.get("qualifying", []):
		_lbl(vb, str(q), 12, MUTED, true)
	if summary.get("restocked", false):
		_lbl(vb, "Every store has restocked. Your next shopping stop: %s." % EconomyConfig.store_name(_best_store()), 13, GREEN, true)
	if summary.has("next_objective"):
		_lbl(vb, "Next: " + str(summary["next_objective"]), 13, INK, true)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_btn(row, "Tee off again", func(): _summary.visible = false; tee_off_requested.emit(_round_span); _open = false; _root.visible = false)
	_btn(row, "Go shopping", func(): _summary.visible = false; _tab = "shop"; _refresh(), true)
	_summary.visible = true


func _best_store() -> String:
	var best := "goodwill"
	for s in EconomyConfig.stores():
		if _gs().store_unlocked(str(s["id"])):
			best = str(s["id"])
	return best
