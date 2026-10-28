class_name Hud
extends CanvasLayer

## The Esc overlay's "Main menu" button (course.gd returns to the start menu).
signal main_menu_requested
## Broadcast-style round HUD in the game's shared visual language (UITheme: dark glass,
## Bahnschrift, gold highlights, keycap prompts -- the same as the Clubhouse). Gameplay supplies
## values; this layer owns presentation and motion:
##   scorecard (top left), side bets under it, minimap (top right), club + lie card (bottom
##   left), shot meter with key prompts (bottom centre), ball-contact picker (bottom right),
##   plus the moments a round is made of -- the hole intro card, the shot result card and
##   big callouts (BIRDIE, SPLASH, ...) -- which slide and punch in, then get out of the way.

const PAPER := UITheme.TEXT
const MUTED := UITheme.DIM
const MINT := UITheme.GAIN
const GOLD := UITheme.GOLD
const SOFT := Color("cfdcd3")
const UNDER_PAR := UITheme.LOSS
const POWER_METER = preload("res://scripts/ui/shot_power_meter.gd")
const MINIMAP_MAX_SIZE := Vector2(116, 220)
const MINIMAP_SHADER = preload("res://shaders/minimap_display.gdshader")
## Gap between the bottom cards and the screen edge; the ESC hint and FPS sit inside it.
const BOTTOM_INSET := 38
const SHOT_CARD_ANCHOR := 0.6  # shot result card's centre line, as a share of the screen height
const SHOT_RESULT_SECONDS := 5.0

var hole_label: Label
var club_label: Label
var lie_label: Label
var dist_label: Label
var result_label: Label
var wind_label: Label
var help_label: Control
var score_label: Label
var power_bar: ProgressBar
var strike_selector: StrikeSelector
var strike_label: Label
var proj_label: Label
var message_label: Label
var minimap_rect: TextureRect
var minimap_shot_overlay: MinimapShotOverlay
var minimap_focus_overlay: Control
var help_overlay: Control
var fps_label: Label
var cash_label: Label
var wallet_footer: VBoxContainer
var sandbox_label: Label
var condition_label: Label
var hole_marker: PinIndicator
var wind_arrow: Control
var info_panel: PanelContainer
var minimap_panel: PanelContainer
var shot_panel: PanelContainer
var club_panel: PanelContainer
var contact_panel: PanelContainer
var side_bets_panel: PanelContainer

var _root: Control
var _number_label: Label
var _par_label: Label
var _course_title := "Augusta National"
var _help_eyebrow: Label
var _stroke_label: Label
var _total_label: Label
var _slope_label: Label
var _lie_chip: PanelContainer
var _green_speed_label: Label
var _wind_direction_label: Label
var _power_value: Label
var _power_caption: Label
var _prompts: HBoxContainer
var _flight_label: Label
var _message_panel: PanelContainer
var _map_material: ShaderMaterial
var _map_texture_size := Vector2.ZERO
var _club_preview: TextureRect
var _club_fallback: ClubSilhouette
var _club_preview_key := ""
var _side_bets_box: VBoxContainer
var _side_bets_key := ""
var _shot_phase := -1
var _fast_forward := 1.0  # game speed while the player holds the ball on fast-forward
var _message_timer := 0.0
var _fps_timer := 0.0
var _minimap_focus_visible := false
var _minimap_focus_pos := Vector2.ZERO
var _minimap_focus_radius := 0.0
# broadcast moments
var _intro: Control
var _intro_tween: Tween
var _shot_card: PanelContainer
var _shot_tiles: HBoxContainer
var _shot_tween: Tween
var _shot_timer := 0.0
var _callout: Control
var _callout_title: Label
var _callout_sub: Label
var _callout_streak: ColorRect
var _callout_tween: Tween


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var root := _root

	# ---- scorecard (top left)
	info_panel = _panel(root, Rect2(18, 18, 248, 0))
	info_panel.add_theme_stylebox_override("panel", UITheme.glass(12, 10))
	var info := _column(info_panel, 6)
	var heading := _row(info, 10)
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile_box := UITheme.box(GOLD, GOLD.lightened(0.2), 0, 7, 0)
	tile_box.content_margin_left = 7
	tile_box.content_margin_right = 7
	tile.add_theme_stylebox_override("panel", tile_box)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(tile)
	_number_label = UITheme.label(tile, "01", 26, Color("13201b"), 700, 87)
	_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _column(heading, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hole_label = UITheme.label(title, "", 20, PAPER, 700, 92, 0, true)
	hole_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_par_label = UITheme.eyebrow(title, "PAR 4   ·   445 YDS", SOFT, true)
	var scores := _row(info, 8)
	_stroke_label = _stat(scores, "STROKES", "0")
	score_label = _stat(scores, "TO PAR", "E")
	score_label.add_theme_color_override("font_color", MINT)
	_total_label = _stat(scores, "TOTAL", "0")
	var conditions := _row(info, 10)
	var wind_disc := Control.new()
	wind_disc.custom_minimum_size = Vector2(28, 28)
	wind_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	conditions.add_child(wind_disc)
	wind_disc.draw.connect(func() -> void:
		var c := Vector2(14, 14)
		wind_disc.draw_circle(c, 13, Color(1, 1, 1, 0.06))
		wind_disc.draw_arc(c, 13, 0, TAU, 40, Color(1, 1, 1, 0.3), 1.0, true)
		for k in range(4):
			var a := k * PI * 0.5
			wind_disc.draw_line(c + Vector2.from_angle(a) * 10.5, c + Vector2.from_angle(a) * 13.0, Color(1, 1, 1, 0.35), 1.0, true))
	wind_arrow = Control.new()
	wind_arrow.size = Vector2(20, 20)
	wind_arrow.position = Vector2(4, 4)
	wind_arrow.pivot_offset = Vector2(10, 10)
	wind_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_arrow.draw.connect(_draw_wind_arrow)
	wind_disc.add_child(wind_arrow)
	var wind_text := _column(conditions, 0)
	wind_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wind_label = UITheme.label(wind_text, "0 MPH", 16, PAPER, 700, 100, 0, true)
	_wind_direction_label = UITheme.eyebrow(wind_text, "WIND", MUTED, true)
	var green_text := _column(conditions, 0)
	_green_speed_label = UITheme.label(green_text, "", 16, PAPER, 700, 100, 0, true)
	UITheme.eyebrow(green_text, "GREEN SPEED", MUTED, true)
	wallet_footer = _column(info, 6)
	UITheme.rule(wallet_footer)
	var wallet_row := _row(wallet_footer, 8)
	_cash_icon(wallet_row)
	cash_label = UITheme.label(wallet_row, "0", 18, GOLD, 700, 100, 0, true)
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.keycap(wallet_row, "TAB")
	var clubhouse := UITheme.eyebrow(wallet_row, "CLUBHOUSE", SOFT, true)
	clubhouse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_accent(info_panel, GOLD)

	# ---- side bets, stacked under the scorecard (repositioned in _process)
	side_bets_panel = _panel(root, Rect2(18, 204, 248, 0))
	side_bets_panel.add_theme_stylebox_override("panel", UITheme.glass(12, 9))
	_side_bets_box = _column(side_bets_panel, 4)
	side_bets_panel.visible = false

	# ---- club + lie (bottom left)
	club_panel = _panel(root, Rect2(18, -BOTTOM_INSET, 318, 0), Control.PRESET_BOTTOM_LEFT)
	club_panel.add_theme_stylebox_override("panel", UITheme.glass(14, 12))
	var club_stack := _column(club_panel, 7)
	var club_row := _row(club_stack, 12)
	var club_art := PanelContainer.new()
	club_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_art.custom_minimum_size = Vector2(52, 52)
	club_art.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 1, 9, 2))
	club_row.add_child(club_art)
	_club_preview = TextureRect.new()
	_club_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_club_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_club_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_art.add_child(_club_preview)
	_club_fallback = ClubSilhouette.new()
	_club_fallback.custom_minimum_size = Vector2(48, 48)
	club_art.add_child(_club_fallback)
	var club_text := _column(club_row, 1)
	club_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var club_head := _row(club_text, 6)
	var club_caption := UITheme.eyebrow(club_head, "CLUB", MUTED, true)
	club_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.keycap(club_head, "W")
	UITheme.keycap(club_head, "S")
	club_label = UITheme.label(club_text, "", 21, PAPER, 700, 92, 0, true)
	club_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	condition_label = UITheme.label(club_text, "", 11, SOFT, 600, 100, 1, true)
	condition_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.rule(club_stack)
	var lie_row := _row(club_stack, 12)
	var lie_column := _column(lie_row, 4)
	lie_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lie_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UITheme.eyebrow(lie_column, "LIE", MUTED, true)
	_lie_chip = PanelContainer.new()
	_lie_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lie_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lie_column.add_child(_lie_chip)
	lie_label = UITheme.label(_lie_chip, "TEE", 12, Color("13201b"), 700, 100, 1)
	_slope_label = UITheme.label(lie_column, "", 11, MUTED, 600, 100, 1, true)
	var distance_column := _column(lie_row, 0)
	dist_label = UITheme.label(distance_column, "0", 32, PAPER, 700, 92, 0, true)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var distance_caption := UITheme.eyebrow(distance_column, "SHOT YDS", MUTED, true)
	distance_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	proj_label = UITheme.label(club_stack, "", 12, SOFT, 600, 100, 1, true)
	proj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ---- shot meter (bottom centre): power readout over the meter, key prompts under it
	shot_panel = _panel(root, Rect2(-200, -BOTTOM_INSET, 400, 0), Control.PRESET_CENTER_BOTTOM)
	shot_panel.add_theme_stylebox_override("panel", _content_spacing(6))
	var shot := _column(shot_panel, 6)
	result_label = UITheme.label(shot, "", 13, SOFT, 600, 100, 1, true)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.visible = false
	var power_heading := _row(shot, 8)
	_power_caption = UITheme.eyebrow(power_heading, "SHOT POWER", SOFT, true)
	_power_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_caption.size_flags_vertical = Control.SIZE_SHRINK_END
	_power_value = UITheme.label(power_heading, "0%", 34, PAPER, 700, 87, 0, true)
	_power_value.custom_minimum_size.x = 90
	_power_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	power_bar = POWER_METER.new()
	power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.add_child(power_bar)
	power_bar.value_changed.connect(_update_power_readout)
	_prompts = _row(shot, 6)
	_prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	for p in [["SPACE", "Swing"], ["A", ""], ["D", "Aim"], ["Z", "Scout"], ["C", "Overhead"]]:
		UITheme.keycap(_prompts, p[0])
		if p[1] != "":
			var pl := UITheme.label(_prompts, p[1].to_upper(), 11, SOFT, 600, 100, 1, true)
			pl.custom_minimum_size.x = pl.get_minimum_size().x + 8
	_flight_label = UITheme.label(shot, "", 13, PAPER, 600, 100, 1, true)
	_flight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ---- ball contact (bottom right)
	contact_panel = _panel(root, Rect2(-250, -BOTTOM_INSET, 232, 0), Control.PRESET_BOTTOM_RIGHT)
	contact_panel.add_theme_stylebox_override("panel", UITheme.glass(14, 12))
	var contact := _column(contact_panel, 8)
	UITheme.eyebrow(contact, "BALL CONTACT", MUTED, true)
	var contact_row := _row(contact, 12)
	strike_selector = StrikeSelector.new()
	contact_row.add_child(strike_selector)
	var contact_text := _column(contact_row, 4)
	contact_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strike_label = UITheme.label(contact_text, "SWEET SPOT", 15, MINT, 700, 92, 0, true)
	strike_label.custom_minimum_size.x = 104
	strike_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var drag_row := _row(contact_text, 6)
	UITheme.keycap(drag_row, "DRAG")
	UITheme.label(drag_row, "SHAPE", 11, SOFT, 600, 100, 1, true)

	# ---- minimap (top right)
	minimap_panel = _panel(root, Rect2(-134, 18, 116, 220), Control.PRESET_TOP_RIGHT)
	# Frame drawn outside the map's own bounds (expand margins) so the map keeps its exact
	# size and the shot overlay's coordinates stay unchanged.
	var map_frame := UITheme.glass(0, 0)
	map_frame.set_corner_radius_all(8)
	map_frame.set_expand_margin_all(5)
	minimap_panel.add_theme_stylebox_override("panel", map_frame)
	minimap_rect = TextureRect.new()
	minimap_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_material = ShaderMaterial.new()
	_map_material.shader = MINIMAP_SHADER
	minimap_rect.material = _map_material
	minimap_panel.add_child(minimap_rect)
	minimap_shot_overlay = MinimapShotOverlay.new()
	minimap_rect.add_child(minimap_shot_overlay)
	minimap_focus_overlay = Control.new()
	minimap_focus_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	minimap_focus_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_rect.add_child(minimap_focus_overlay)
	minimap_focus_overlay.draw.connect(_draw_minimap_focus)

	# ---- message banner: hugs its text, grows both ways from its anchor
	_message_panel = _panel(root, Rect2(), Control.PRESET_CENTER)
	_message_panel.anchor_top = 0.24
	_message_panel.anchor_bottom = 0.24
	var banner := UITheme.glass(24, 10)
	banner.set_corner_radius_all(22)
	banner.border_color = Color(GOLD, 0.45)
	_message_panel.add_theme_stylebox_override("panel", banner)
	message_label = UITheme.label(_message_panel, "", 20, PAPER, 700, 100, 0)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_panel.visible = false

	sandbox_label = UITheme.label(root, "", 12, Color("13201b"), 700, 100, 1)
	sandbox_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sandbox_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sandbox_label.offset_top = 20
	sandbox_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sandbox_box := UITheme.box(UITheme.AMBER, UITheme.AMBER.lightened(0.2), 0, 8, 0)
	sandbox_box.content_margin_left = 14
	sandbox_box.content_margin_right = 14
	sandbox_box.content_margin_top = 5
	sandbox_box.content_margin_bottom = 5
	sandbox_label.add_theme_stylebox_override("normal", sandbox_box)
	sandbox_label.visible = false

	# ---- footer: controls hint (centre) and FPS (right)
	var footer := HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.offset_top = -30
	footer.offset_bottom = -10
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 6)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer)
	UITheme.keycap(footer, "ESC")
	UITheme.label(footer, "CONTROLS", 11, SOFT, 600, 100, 2, true)
	help_label = footer
	fps_label = UITheme.label(root, "", 11, Color(1, 1, 1, 0.45), 600, 100, 1)
	fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fps_label.offset_left = -94
	fps_label.offset_right = -20
	fps_label.offset_top = -30
	fps_label.offset_bottom = -10
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hole_marker = PinIndicator.new()
	hole_marker.visible = false
	# Normal canvas stacking: transparent space shows the waypoint, while the
	# actual text and map pixels draw over it. No invisible clipping rectangles.
	hole_marker.z_index = -1
	root.add_child(hole_marker)
	hole_marker.scale = Vector2.ONE * 0.75
	_build_shot_card(root)
	_build_callout(root)
	_build_hole_intro(root)
	_build_help_overlay(root)
	set_shot_phase(0)


# ---------------------------------------------------------------- building blocks

## Retain the layout padding without drawing a background, border or shadow.
func _content_spacing(padding: int = 4) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(padding)
	return style


func _panel(parent: Node, rect: Rect2, anchor: int = Control.PRESET_TOP_LEFT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	panel.set_anchors_preset(anchor)
	panel.offset_left = rect.position.x
	panel.offset_top = rect.position.y
	panel.offset_right = rect.end.x
	panel.offset_bottom = rect.end.y
	# Cards hug their content, so let them grow away from the screen edge they're pinned to.
	if anchor in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]:
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif anchor == Control.PRESET_CENTER:
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	if anchor in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif anchor in [Control.PRESET_CENTER, Control.PRESET_CENTER_BOTTOM]:
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", _content_spacing())
	return panel


## A thin coloured bar along the top edge of a card (broadcast-graphics accent).
func _accent(card: Control, color: Color) -> void:
	var bar := ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_bottom = 2
	bar.top_level = false
	card.add_child(bar)
	# PanelContainer would lay the bar out like content; keep it a decoration instead.
	card.sort_children.connect(func() -> void:
		bar.position = Vector2(12, 0)
		bar.size = Vector2(maxf(card.size.x - 24, 0.0), 2))


func _column(parent: Node, gap: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", gap)
	parent.add_child(column)
	return column


func _row(parent: Node, gap: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row


func _stat(parent: Node, caption: String, value: String) -> Label:
	var column := _column(parent, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.eyebrow(column, caption, MUTED, true)
	return UITheme.label(column, value, 22, PAPER, 700, 92, 0, true)


## Small gold coin with a $ mark, standing in for the cash amount next to it.
func _cash_icon(parent: Node) -> void:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void:
		var c := icon.size * 0.5
		icon.draw_circle(c, 9.5, GOLD.darkened(0.25), true, -1.0, true)
		icon.draw_circle(c, 8.0, GOLD, true, -1.0, true)
		var f := UITheme.font(700)
		var w := f.get_string_size("$", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		icon.draw_string(f, c + Vector2(-w * 0.5, 4.5), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("13201b")))
	parent.add_child(icon)


# ---------------------------------------------------------------- broadcast moments

## Shot result card: stat tiles that slide up over the meter when the ball stops.
func _build_shot_card(root: Control) -> void:
	# Centred on a line just below the middle of the screen, clear of the bottom HUD row.
	_shot_card = _panel(root, Rect2(), Control.PRESET_CENTER)
	_shot_card.anchor_top = SHOT_CARD_ANCHOR
	_shot_card.anchor_bottom = SHOT_CARD_ANCHOR
	_shot_card.add_theme_stylebox_override("panel", UITheme.glass(14, 10))
	var col := _column(_shot_card, 6)
	_shot_tiles = _row(col, 18)
	_shot_card.visible = false


## rows: [[caption, value, unit, color]]; `tag`/`tag_color`: the lie chip at the end.
func _fill_shot_card(rows: Array, tag: String, tag_color: Color) -> void:
	for c in _shot_tiles.get_children():
		_shot_tiles.remove_child(c)
		c.queue_free()
	for r in rows:
		var tile := _column(_shot_tiles, 0)
		UITheme.eyebrow(tile, r[0], MUTED)
		var vrow := _row(tile, 3)
		UITheme.label(vrow, r[1], 26, r[3], 700, 87)
		var unit := UITheme.label(vrow, r[2], 12, SOFT, 600, 100, 1)
		unit.size_flags_vertical = Control.SIZE_SHRINK_END
	if tag != "":
		var tcol := _column(_shot_tiles, 4)
		tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.eyebrow(tcol, "LIE", MUTED)
		UITheme.pill(tcol, tag.to_upper(), tag_color, Color("13201b"), 11)


func show_shot_result(carry_yd: float, total_yd: float, apex_ft: float, to_pin_yd: float, lie_name: String, lie_surface: int) -> void:
	if _shot_card == null:
		return
	var to_pin := "%.1f" % to_pin_yd if to_pin_yd < 10.0 else "%.0f" % to_pin_yd
	_fill_shot_card([
		["Carry", "%.0f" % carry_yd, "YDS", PAPER],
		["Total", "%.0f" % total_yd, "YDS", PAPER],
		["Apex", "%.0f" % apex_ft, "FT", PAPER],
		["To pin", to_pin, "YDS", GOLD],
	], lie_name, UITheme.lie_color(lie_surface))
	_reveal_shot_card()


## A hazard or penalty result: one big line in the card instead of the stats.
func show_shot_penalty(title: String, detail: String) -> void:
	if _shot_card == null:
		return
	for c in _shot_tiles.get_children():
		_shot_tiles.remove_child(c)
		c.queue_free()
	var col := _column(_shot_tiles, 0)
	UITheme.eyebrow(col, detail, MUTED)
	UITheme.label(col, title.to_upper(), 24, UNDER_PAR, 700, 87)
	_reveal_shot_card()


func clear_shot_result() -> void:
	_shot_timer = 0.0
	if _shot_card != null and _shot_card.visible:
		_hide_shot_card()


func _reveal_shot_card() -> void:
	# Zero-width rect: the card re-centres on its anchor at its new content width
	# (reset_size() would keep the left edge and grow it to the right).
	_shot_card.offset_left = 0
	_shot_card.offset_right = 0
	_shot_card.visible = true
	_shot_timer = SHOT_RESULT_SECONDS
	if _shot_tween != null:
		_shot_tween.kill()
	_shot_card.modulate.a = 0.0
	var y := 0.0
	_shot_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shot_tween.tween_property(_shot_card, "modulate:a", 1.0, 0.25)
	_shot_tween.tween_method(func(v: float): _shot_card.offset_top = v; _shot_card.offset_bottom = v, y + 24.0, y, 0.35)


func _hide_shot_card() -> void:
	if _shot_tween != null:
		_shot_tween.kill()
	_shot_tween = create_tween()
	_shot_tween.tween_property(_shot_card, "modulate:a", 0.0, 0.3)
	_shot_tween.tween_callback(func(): _shot_card.visible = false)


## Big centred callout (BIRDIE, SPLASH, ...) behind a light streak.
func _build_callout(root: Control) -> void:
	_callout = Control.new()
	_callout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.visible = false
	root.add_child(_callout)
	_callout_streak = ColorRect.new()
	_callout_streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_streak.anchor_left = 0.0
	_callout_streak.anchor_right = 1.0
	_callout_streak.anchor_top = 0.3
	_callout_streak.anchor_bottom = 0.3
	_callout_streak.offset_top = -46
	_callout_streak.offset_bottom = 50
	var streak_mat := ShaderMaterial.new()
	streak_mat.shader = _streak_shader()
	_callout_streak.material = streak_mat
	_callout.add_child(_callout_streak)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.3
	box.anchor_bottom = 0.3
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout.add_child(box)
	_callout_title = UITheme.label(box, "", 64, GOLD, 700, 80, 4, true)
	_callout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout_title.add_theme_constant_override("outline_size", 8)
	_callout_sub = UITheme.label(box, "", 16, PAPER, 600, 100, 3, true)
	_callout_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static var _streak: Shader
static func _streak_shader() -> Shader:
	if _streak == null:
		_streak = Shader.new()
		_streak.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.95, 0.82, 0.49, 1.0);
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = abs(UV.y - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.0, 1.0, x)) * (1.0 - smoothstep(0.35, 1.0, y));
	float core = (1.0 - smoothstep(0.0, 0.7, x)) * exp(-pow(y * 6.0, 2.0));
	COLOR = vec4(mix(vec3(0.0, 0.03, 0.02), tint.rgb, core * 0.9), a * 0.55 + core * 0.35);
}"""
	return _streak


## tone: "great" (gold), "good" (green), "bad" (red) or "info" (white).
func show_callout(title: String, subtitle: String = "", tone: String = "info", seconds: float = 2.4) -> void:
	if _callout == null:
		return
	var col: Color = {"great": GOLD, "good": MINT, "bad": UNDER_PAR}.get(tone, PAPER)
	_callout_title.text = title.to_upper()
	_callout_title.add_theme_color_override("font_color", col)
	_callout_sub.text = subtitle.to_upper()
	_callout_sub.visible = subtitle != ""
	(_callout_streak.material as ShaderMaterial).set_shader_parameter("tint", col)
	_callout.visible = true
	if _callout_tween != null:
		_callout_tween.kill()
	_callout.modulate.a = 0.0
	_callout_title.pivot_offset = _callout_title.size * 0.5
	_callout_title.scale = Vector2.ONE * 1.35
	_callout_tween = create_tween()
	_callout_tween.set_parallel()
	_callout_tween.tween_property(_callout, "modulate:a", 1.0, 0.16)
	_callout_tween.tween_property(_callout_title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_callout_tween.chain().tween_interval(seconds)
	_callout_tween.chain().tween_property(_callout, "modulate:a", 0.0, 0.35)
	_callout_tween.chain().tween_callback(func(): _callout.visible = false)


## Broadcast hole intro: big hole number, name, par and yardage, and the wind, sliding in
## from the left at the tee and out again a few seconds later.
func _build_hole_intro(root: Control) -> void:
	_intro = PanelContainer.new()
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.anchor_top = 0.54
	_intro.anchor_bottom = 0.54
	_intro.grow_vertical = Control.GROW_DIRECTION_BOTH
	_intro.offset_left = 18
	var sb := UITheme.glass(22, 16)
	sb.border_width_left = 4
	sb.border_color = GOLD
	_intro.add_theme_stylebox_override("panel", sb)
	_intro.visible = false
	root.add_child(_intro)


func show_hole_intro(number: int, title: String, par: int, yards: int, wind_text: String) -> void:
	if _intro == null:
		return
	for c in _intro.get_children():
		_intro.remove_child(c)
		c.queue_free()
	var row := _row(_intro, 16)
	var num_col := _column(row, -4)
	UITheme.eyebrow(num_col, "HOLE", GOLD)
	UITheme.label(num_col, "%d" % number, 64, GOLD, 700, 80)
	var text := _column(row, 2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if title != "":
		UITheme.label(text, title, 30, PAPER, 700, 92)
		UITheme.label(text, "PAR %d   ·   %d YARDS" % [par, yards], 13, SOFT, 600, 100, 2)
	else:  # Course Studio holes have no names: par leads
		UITheme.label(text, "PAR %d" % par, 30, PAPER, 700, 92)
		UITheme.label(text, "%d YARDS" % yards, 13, SOFT, 600, 100, 2)
	if wind_text != "":
		UITheme.label(text, wind_text, 13, MUTED, 600, 100, 1)
	_intro.offset_top = 0
	_intro.offset_bottom = 0
	_intro.visible = true
	if _intro_tween != null:
		_intro_tween.kill()
	_intro.modulate.a = 0.0
	var x := 18.0
	_intro.offset_left = x - 60.0
	_intro_tween = create_tween()
	_intro_tween.set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_intro, "modulate:a", 1.0, 0.3)
	_intro_tween.tween_property(_intro, "offset_left", x, 0.45)
	_intro_tween.chain().tween_interval(3.6)
	_intro_tween.chain().tween_property(_intro, "modulate:a", 0.0, 0.4)
	_intro_tween.chain().tween_callback(func(): _intro.visible = false)


# ---------------------------------------------------------------- data in

## rows: [{text, reward, status}] from SideBets.rows(); empty hides the card.
func set_side_bets(rows: Array) -> void:
	var key := str(rows)
	if key == _side_bets_key:
		return
	_side_bets_key = key
	side_bets_panel.visible = not rows.is_empty()
	for c in _side_bets_box.get_children():
		_side_bets_box.remove_child(c)
		c.queue_free()
	if rows.is_empty():
		return
	UITheme.eyebrow(_side_bets_box, "SIDE BETS", GOLD, true)
	for r in rows:
		var row := _row(_side_bets_box, 7)
		var st := str(r.get("status", ""))
		var mark := Control.new()
		mark.custom_minimum_size = Vector2(12, 12)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(func() -> void:
			var c := mark.size * 0.5
			if st == SideBets.WON:
				mark.draw_circle(c, 6, MINT, true, -1.0, true)
				mark.draw_polyline(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(-1, 2.5), c + Vector2(3.5, -2.5)]), Color("13201b"), 1.6, true)
			elif st == SideBets.LOST:
				mark.draw_circle(c, 6, Color(UNDER_PAR, 0.85), true, -1.0, true)
				mark.draw_line(c + Vector2(-2.5, -2.5), c + Vector2(2.5, 2.5), Color("13201b"), 1.6, true)
				mark.draw_line(c + Vector2(2.5, -2.5), c + Vector2(-2.5, 2.5), Color("13201b"), 1.6, true)
			else:
				mark.draw_arc(c, 5, 0, TAU, 24, Color(1, 1, 1, 0.5), 1.4, true))
		row.add_child(mark)
		var text := UITheme.label(row, str(r.get("text", "")), 12, MUTED if st == SideBets.LOST else PAPER, 500, 100, 0, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.label(row, "$%d" % int(r.get("reward", 0)), 12, GOLD if st != SideBets.LOST else MUTED, 700, 100, 0, true)


## The course being played, for the controls overlay (Augusta or a Course Studio course).
func set_course_title(title: String) -> void:
	_course_title = title
	if _help_eyebrow != null:
		_help_eyebrow.text = (title + "   /   Controls").to_upper()  # eyebrows are all caps


func set_hole(number: int, title: String, par: int, yards: int) -> void:
	_number_label.text = "%02d" % number
	hole_label.text = title
	hole_label.visible = title != ""  # Course Studio holes have no names
	_par_label.text = "PAR %d   ·   %d YDS" % [par, yards]


## Match the control bounds to the displayed map, including narrow straight holes.
func set_minimap_texture(map: Texture2D) -> void:
	if minimap_rect.texture != map:
		minimap_rect.texture = map
	var texture_size := map.get_size()
	if texture_size == _map_texture_size or texture_size.x <= 0 or texture_size.y <= 0:
		return
	_map_texture_size = texture_size
	var display_size := texture_size * minf(MINIMAP_MAX_SIZE.x / texture_size.x, MINIMAP_MAX_SIZE.y / texture_size.y)
	minimap_rect.custom_minimum_size = display_size
	minimap_panel.offset_left = -18 - display_size.x
	minimap_panel.offset_right = -18
	minimap_panel.offset_bottom = 18 + display_size.y
	_map_material.set_shader_parameter("display_size", display_size)


func set_score(strokes: int, total: int, relative: int, _water: int, _bunkers: int) -> void:
	_stroke_label.text = str(strokes)
	score_label.text = "E" if relative == 0 else "%+d" % relative
	# Scoreboard convention: red under par, green at even, plain over.
	score_label.add_theme_color_override("font_color", UNDER_PAR if relative < 0 else (MINT if relative == 0 else PAPER))
	_total_label.text = str(total)


func set_club(title: String, short_name: String = "", condition: String = "", model_id: String = "") -> void:
	club_label.text = title
	club_label.tooltip_text = title
	condition_label.text = (short_name + ("   ·   " + condition if not condition.is_empty() else "")).to_upper()
	condition_label.visible = not condition_label.text.is_empty()
	_set_club_preview(model_id, short_name)


func _set_club_preview(model_id: String, short_name: String) -> void:
	var slot := short_name.to_upper()
	var key := model_id + "/" + slot
	if key == _club_preview_key:
		return
	_club_preview_key = key
	# Stock bags/tools have no instance id; find the matching loaner by bag slot.
	if model_id.is_empty():
		for starter in ClubCatalog.starter_models():
			if ClubCatalog.slots_for_model(starter).has(slot):
				model_id = str(starter.id)
				break
	_club_preview.texture = EquipmentPreview.get_texture(model_id)
	_club_preview.visible = _club_preview.texture != null
	_club_fallback.visible = not _club_preview.visible
	if _club_fallback.visible:
		var model := ClubCatalog.model(model_id)
		if model.is_empty():
			var shape := "iron"
			match slot:
				"DR": shape = "driver"
				"3W", "5W": shape = "wood"
				"HY": shape = "hybrid"
				"PW", "GW", "SW", "LW": shape = "wedge"
				"PT": shape = "putter_blade"
			model = {"silhouette": shape}
		_club_fallback.setup(model)


func set_lie(title: String, slope_degrees: float, surface: int) -> void:
	lie_label.text = title.to_upper()
	var col := UITheme.lie_color(surface)
	var sb := UITheme.box(col, col.lightened(0.2), 0, 6, 0)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_lie_chip.add_theme_stylebox_override("panel", sb)
	_slope_label.text = "SLOPE  %.1f°" % slope_degrees


func set_distance(yards: float) -> void:
	if yards <= 0.05:
		dist_label.text = "0"
	else:
		dist_label.text = "%.1f" % yards if yards < 10 else "%.0f" % yards


func set_conditions(mph: float, direction: String, green_feet: float) -> void:
	wind_label.text = "%.0f MPH" % mph
	_wind_direction_label.text = "WIND  " + direction.to_upper()
	_green_speed_label.text = "%s FT" % String.num(green_feet, 1)


## `total` < 0: the preview stopped at the first bounce (full swings), so only carry is known.
## `putt_feet` >= 0: a putt, whose preview only shows the line, so show the distance to the cup.
func set_prediction(carry: float, total: float, in_water: bool, putt_feet: float = -1.0) -> void:
	var dist := "%.0f CARRY" % carry if total < 0.0 else "%.0f CARRY   ·   %.0f TOTAL" % [carry, total]
	if putt_feet >= 0.0:
		proj_label.text = "PUTT   %.0f FT TO THE CUP%s" % [putt_feet, "   ·   WATER" if in_water else ""]
	else:
		proj_label.text = "FULL SHOT   %s%s" % [dist, "   ·   WATER" if in_water else ""]
	proj_label.add_theme_color_override("font_color", UNDER_PAR if in_water else SOFT)
	var strike := strike_selector.describe()
	strike_label.text = strike.to_upper()
	strike_label.add_theme_color_override("font_color", MINT if strike.to_lower().contains("sweet") else UITheme.AMBER)


## `speed` > 1 while the ball is being fast-forwarded; the in-flight readout says so.
func set_fast_forward(speed: float) -> void:
	_fast_forward = speed
	_update_power_readout(power_bar.value)


func _update_power_readout(value: float) -> void:
	var live := "%.0f× FAST" % _fast_forward if _fast_forward > 1.0 else "LIVE"
	_power_value.text = live if _shot_phase == 2 else "%d%%" % roundi(value)
	var color := Color("91e5dc") if _shot_phase == 2 else POWER_METER.accent_color(value)
	_power_value.add_theme_color_override("font_color", color)


func set_shot_phase(phase: int) -> void:
	if phase == _shot_phase:
		return
	_shot_phase = phase
	_power_caption.text = "BALL TRACKING" if phase == 2 else "SHOT POWER"
	_update_power_readout(power_bar.value)
	_prompts.visible = phase != 2
	_flight_label.visible = phase == 2
	power_bar.self_modulate.a = 0.28 if phase == 2 else 1.0
	if phase == 1:
		clear_shot_result()
	if phase != 0 and _intro.visible:
		# The swing has started: the hole intro gets out of the way at once.
		if _intro_tween != null:
			_intro_tween.kill()
		_intro_tween = create_tween()
		_intro_tween.tween_property(_intro, "modulate:a", 0.0, 0.2)
		_intro_tween.tween_callback(func(): _intro.visible = false)


func set_flight(mph: float, height_feet: float, rolling: bool, yards: float) -> void:
	set_distance(yards)
	_flight_label.text = "%.0f MPH   ·   %.0f FT HIGH   ·   %s" % [mph, maxf(height_feet, 0.0), "ROLLING" if rolling else "IN FLIGHT"]


# ---------------------------------------------------------------- help overlay

func _build_help_overlay(root: Control) -> void:
	help_overlay = Control.new()
	help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	help_overlay.visible = false
	root.add_child(help_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.015, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_overlay.add_child(dim)
	var panel := _panel(help_overlay, Rect2(-340, 0, 680, 0), Control.PRESET_CENTER)
	var sb := UITheme.glass(28, 24, true)
	sb.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	var column := _column(panel, 16)
	_help_eyebrow = UITheme.eyebrow(column, _course_title + "   /   Controls", GOLD)
	UITheme.label(column, "Make your next shot count.", 30, PAPER, 700, 92)
	UITheme.label(column, "Aim, pick a club, then tap twice: once to start the power, once to strike.", 14, SOFT, 500)
	UITheme.rule(column)
	var sections := _row(column, 32)
	var shot := _column(sections, 10)
	shot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.eyebrow(shot, "Your shot", MINT)
	for binding in [["A / D", "Aim left / right"], ["W / S", "Change club"], ["SPACE", "Start power / hit"], ["DRAG BALL", "Choose the contact point"], ["HOLD SPACE", "Fast-forward a moving ball"], ["M", "Replay your last shot"]]:
		_help_binding(shot, binding[0], binding[1])
	var camera := _column(sections, 10)
	camera.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.eyebrow(camera, "Look around", MINT)
	for binding in [["C", "Overhead view"], ["ARROWS", "Pan in overhead view"], ["HOLD Z", "Scout the landing area"], ["RMB DRAG", "Look around / aim"], ["WHEEL", "Zoom the camera"]]:
		_help_binding(camera, binding[0], binding[1])
	UITheme.rule(column)
	var round_row := _row(column, 8)
	for b in [["TAB", "Clubhouse"], ["N", "Next hole"], ["R", "Restart hole"], ["J", "New terrain seed"]]:
		UITheme.keycap(round_row, b[0])
		var l := UITheme.label(round_row, b[1].to_upper(), 12, SOFT, 600, 100, 1)
		l.custom_minimum_size.x = l.get_minimum_size().x + 12
	var back := _row(column, 8)
	UITheme.keycap(back, "ESC")
	UITheme.label(back, "BACK TO THE COURSE", 12, GOLD, 700, 100, 2)
	var back_fill := Control.new()
	back_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(back_fill)
	back.mouse_filter = Control.MOUSE_FILTER_PASS
	MenuKit.button(back, GameLaunch.exit_label(), "ghost", 13).pressed.connect(func() -> void: main_menu_requested.emit())


func _help_binding(parent: Node, key: String, description: String) -> void:
	var row := _row(parent, 10)
	var cap_box := _row(row, 0)
	cap_box.custom_minimum_size.x = 92
	UITheme.keycap(cap_box, key)
	UITheme.label(row, description, 14, PAPER, 500)


func toggle_help() -> void:
	help_overlay.visible = not help_overlay.visible


func is_help_open() -> bool:
	return help_overlay.visible


# ---------------------------------------------------------------- minimap / wind / messages

func set_minimap_focus(local_pos: Vector2, radius_px: float) -> void:
	_minimap_focus_visible = true
	_minimap_focus_pos = local_pos
	_minimap_focus_radius = radius_px
	minimap_focus_overlay.queue_redraw()


func hide_minimap_focus() -> void:
	if _minimap_focus_visible:
		_minimap_focus_visible = false
		minimap_focus_overlay.queue_redraw()


func _draw_minimap_focus() -> void:
	if _minimap_focus_visible:
		minimap_focus_overlay.draw_arc(_minimap_focus_pos, _minimap_focus_radius, 0, TAU, 40, Color(GOLD, 0.95), 1.5, true)


func _draw_wind_arrow() -> void:
	var pts := PackedVector2Array([Vector2(10, 1), Vector2(16, 11), Vector2(12, 10), Vector2(12, 19), Vector2(8, 19), Vector2(8, 10), Vector2(4, 11)])
	wind_arrow.draw_colored_polygon(pts, GOLD)


const MESSAGE_MAX_WIDTH := 560.0

func show_message(text: String, seconds: float = 2.5) -> void:
	message_label.text = text
	# Short banners hug their text; long ones wrap at a fixed width instead of running wide.
	var font := message_label.get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, message_label.get_theme_font_size("font_size")).x
	var wrap := width > MESSAGE_MAX_WIDTH
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	message_label.custom_minimum_size.x = MESSAGE_MAX_WIDTH if wrap else 0.0
	for side in ["offset_left", "offset_right", "offset_top", "offset_bottom"]:
		_message_panel.set(side, 0.0)  # re-centre on the anchor at the new text size
	_message_panel.visible = true
	_message_panel.modulate.a = 0.0
	create_tween().tween_property(_message_panel, "modulate:a", 1.0, 0.18)
	_message_timer = seconds


func _process(delta: float) -> void:
	result_label.visible = not result_label.text.is_empty()
	# The pin waypoint normally sits under the HUD so lettering stays on top, but the opaque
	# minimap would swallow it at the right edge -- there it draws over the map instead.
	if hole_marker.visible:
		var marker_rect := Rect2(hole_marker.global_position, hole_marker.size * hole_marker.scale)
		hole_marker.z_index = 1 if marker_rect.intersects(minimap_panel.get_global_rect().grow(4)) else -1
	if side_bets_panel.visible:
		# Stack under the info card at its width; height clamps to the rows' minimum.
		side_bets_panel.offset_top = info_panel.position.y + info_panel.size.y + 10
		side_bets_panel.size = Vector2(info_panel.size.x, 0)
	if _message_timer > 0:
		_message_timer -= delta
		if _message_timer <= 0:
			var tw := create_tween()
			tw.tween_property(_message_panel, "modulate:a", 0.0, 0.25)
			tw.tween_callback(func(): _message_panel.visible = false)
	if _shot_timer > 0.0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_hide_shot_card()
	_fps_timer -= delta
	if _fps_timer <= 0:
		_fps_timer = 0.5
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
