class_name Hud
extends CanvasLayer
## Minimal game HUD: hole info, club, lie, distance, power meter, shot result, wind.

var hole_label: Label
var club_label: Label
var lie_label: Label
var dist_label: Label
var result_label: Label
var wind_label: Label
var help_label: Label
var score_label: Label
var power_bar: ProgressBar
var strike_selector: StrikeSelector
var strike_label: Label
var proj_label: Label
var message_label: Label
var minimap_rect: TextureRect
var minimap_label: Label
var minimap_shot_overlay: MinimapShotOverlay
var minimap_focus_overlay: Control
var help_overlay: Control
var fps_label: Label
## Upright flag waypoint and yardage, sliding across the top toward the pin.
var hole_marker: PinIndicator
## Points where the wind blows relative to the current camera facing (Course._update_wind_arrow
## sets its rotation every frame) -- not a fixed world compass, so it turns as the camera does.
var wind_arrow: Control
var _minimap_focus_visible := false
var _minimap_focus_pos := Vector2.ZERO
var _minimap_focus_radius := 0.0
var _message_timer := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	hole_label = _label(vb, 22)
	score_label = _label(vb, 16)
	club_label = _label(vb, 18)
	lie_label = _label(vb, 16)
	dist_label = _label(vb, 16)
	proj_label = _label(vb, 15)
	var wind_row := HBoxContainer.new()
	wind_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_row.add_theme_constant_override("separation", 6)
	vb.add_child(wind_row)
	# Points "up" (away from the golfer, downwind) at rotation 0 -- Course._update_wind_arrow
	# rotates it each frame to the wind's direction relative to wherever the camera is
	# currently facing, not a fixed world compass, so it turns as the camera does.
	wind_arrow = Control.new()
	wind_arrow.custom_minimum_size = Vector2(20, 20)
	wind_arrow.size = Vector2(20, 20)
	wind_arrow.pivot_offset = Vector2(10, 10)
	wind_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_arrow.draw.connect(_draw_wind_arrow)
	wind_row.add_child(wind_arrow)
	wind_label = _label(wind_row, 16)
	wind_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fps_label = _label(vb, 13)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -150
	bottom.offset_bottom = -12
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	result_label = _label(bottom, 16)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_bar = ProgressBar.new()
	power_bar.min_value = 0
	power_bar.max_value = 100
	power_bar.custom_minimum_size = Vector2(440, 26)
	power_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	power_bar.show_percentage = true
	bottom.add_child(power_bar)
	var strike_row := HBoxContainer.new()
	strike_row.alignment = BoxContainer.ALIGNMENT_CENTER
	strike_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike_row.add_theme_constant_override("separation", 12)
	bottom.add_child(strike_row)
	strike_selector = StrikeSelector.new()
	strike_row.add_child(strike_selector)
	strike_label = _label(strike_row, 13)
	strike_label.text = "Strike point: sweet spot\n(drag the ball to shape the shot)"
	strike_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _label(bottom, 12)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	help_label.text = "A/D or right-drag: aim   W/S: club   Drag the ball: strike point   Space/click: swing   C: bird's-eye   R: restart hole   Wheel: zoom"

	var mm_panel := PanelContainer.new()
	mm_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm_panel.anchor_left = 1.0
	mm_panel.anchor_right = 1.0
	mm_panel.offset_left = -166
	mm_panel.offset_right = -16
	mm_panel.offset_top = 16
	mm_panel.offset_bottom = 316
	mm_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mm_panel)
	var mm_vb := VBoxContainer.new()
	mm_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_panel.add_child(mm_vb)
	minimap_label = _label(mm_vb, 13)
	minimap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minimap_rect = TextureRect.new()
	minimap_rect.custom_minimum_size = Vector2(150, 280)
	minimap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mm_vb.add_child(minimap_rect)
	minimap_shot_overlay = MinimapShotOverlay.new()
	minimap_rect.add_child(minimap_shot_overlay)
	minimap_focus_overlay = Control.new()
	minimap_focus_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_focus_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_rect.add_child(minimap_focus_overlay)
	minimap_focus_overlay.draw.connect(_draw_minimap_focus)

	message_label = _label(root, 40)
	message_label.set_anchors_preset(Control.PRESET_CENTER)
	message_label.anchor_left = 0.5
	message_label.anchor_right = 0.5
	message_label.anchor_top = 0.3
	message_label.anchor_bottom = 0.3
	message_label.offset_left = -420
	message_label.offset_right = 420
	message_label.offset_top = -60
	message_label.offset_bottom = 60
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	message_label.visible = false

	hole_marker = PinIndicator.new()
	hole_marker.visible = false
	root.add_child(hole_marker)

	_build_help_overlay(root)


## Full-screen "how to play" panel, toggled by Escape (see Course._unhandled_input).
func _build_help_overlay(root: Control) -> void:
	help_overlay = Control.new()
	help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	help_overlay.visible = false
	root.add_child(help_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	help_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -260
	panel.offset_bottom = 260
	help_overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := _label(vb, 28)
	title.text = "How to Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var lines := [
		"Objective: get the ball in the hole in as few strokes as possible.",
		"",
		"Aim: A/D, or hold right mouse and drag",
		"Choose club: W/S",
		"Swing: Space or left click to start power, again to lock it",
		"Shape the shot: drag the strike point on the ball widget",
		"Bird's-eye view: C  (arrow keys pan, right-drag to look around, wheel zooms)",
		"Scout the landing spot: hold Z, release to fly back (right-drag to look around)",
		"Mulligan: M  (replay just the last shot, not the whole hole)",
		"Next hole: N, once the ball is at rest",
		"Restart hole: R  (back to the tee)",
		"New terrain seed: J  (a new seed takes longer to generate)",
		"Zoom: mouse wheel",
	]
	for line in lines:
		var l := _label(vb, 16)
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD

	var footer := _label(vb, 14)
	footer.text = "\nPress Esc to close"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func toggle_help() -> void:
	help_overlay.visible = not help_overlay.visible


func is_help_open() -> bool:
	return help_overlay.visible


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


## Show/move the bird's-eye camera's focus circle on the minimap. `local_pos`/`radius_px`
## are in minimap_rect's own local pixel space (see Course._minimap_world_to_local).
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
	if not _minimap_focus_visible:
		return
	minimap_focus_overlay.draw_arc(_minimap_focus_pos, _minimap_focus_radius, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.0, true)


## A simple arrow: points "up" (screen-relative) before wind_arrow.rotation is applied.
## Drawn once in local space; Course._update_wind_arrow does the actual pointing by rotating
## the whole Control around its centred pivot_offset each frame.
func _draw_wind_arrow() -> void:
	var pts := PackedVector2Array([
		Vector2(10, 1), Vector2(16, 11), Vector2(12.5, 11),
		Vector2(12.5, 19), Vector2(7.5, 19), Vector2(7.5, 11), Vector2(4, 11),
	])
	wind_arrow.draw_colored_polygon(pts, Color(0.92, 0.96, 1.0, 0.95))
	var outline := pts.duplicate()
	outline.append(pts[0])
	wind_arrow.draw_polyline(outline, Color(0.05, 0.1, 0.15, 0.7), 1.2, true)


func show_message(text: String, seconds: float = 2.5) -> void:
	message_label.text = text
	message_label.visible = true
	_message_timer = seconds


var _fps_timer := 0.0


func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			message_label.visible = false
	_fps_timer -= delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.25
		var fps := Engine.get_frames_per_second()
		fps_label.text = "FPS: %d" % fps
		fps_label.add_theme_color_override("font_color", Color.WHITE if fps >= 50 else (Color(1, 0.85, 0.2) if fps >= 30 else Color(1, 0.35, 0.3)))
