class_name GolfLoadingScreen
extends CanvasLayer
## Hole loading screen, broadcast style, in the game's shared look (UITheme): a cinematic
## slideshow of postcard stills of the hole (assets/loading/hole_NN_K.jpg, rendered by
## tools/render_hole_stills.gd) crossfading under a slow pan and zoom, letterboxed, with the
## hole number, name, par, yardage and its Masters scoring record over it, a rotating tip
## and a slim gold progress bar. A hole without stills falls back to the dark studio
## backdrop. When the load is done a pulsing SPACE / TEE OFF prompt appears; the screen fades
## away on its own after a short minimum or at once on Space.
##
## Contract (course.gd): begin_hole() -> await covered -> update_progress() ... ->
## mark_ready() -> await ride_finished. Space can shorten a ready screen; it can never skip
## unfinished work, and the key press never reaches the game underneath.

signal covered
signal ride_finished

@export var minimum_ride_time := 2.6  # seconds a finished load stays up before fading
@export var demo_loop := false  # preview: replays the reveal forever (scenes/ui/cart_loading_demo.tscn)
@export var animation_speed := 1.0

const BACKDROP = preload("res://shaders/inspect_backdrop.gdshader")
const STATS_PATH := "res://data/hole_stats.json"
const FADE_IN := 0.25
const FADE_OUT := 0.4
const TIP_SECONDS := 4.5
const DEMO_LENGTH := 6.0
const STILLS := "res://assets/loading/hole_%02d_%d.jpg"
## Off for Course Studio courses (the stills are of Augusta's holes).
static var stills_enabled := true
## The course on the card (set_course): its name, and whether it is Augusta, the only course
## with hole names, postcard stills and Masters scoring averages.
static var course_title := "Augusta National"
static var augusta := true
const SLIDE_TIME := 3.6  # seconds per still
const SLIDE_FADE := 0.9  # crossfade between stills
const LETTERBOX := 46.0
const TIPS := [
	"Drag the ball in the contact picker to shape the shot: strike it toward the heel or toe to curve it.",
	"Hold Z to scout the landing area before you commit to a club.",
	"Only a perfectly timed second tap reaches the full distance shown by the tracer.",
	"Press C for the overhead view, then pan around the hole with the arrow keys.",
	"Side bets pay out when you finish the round. Keep an eye on them under the scorecard.",
	"The greens run fast and tilt hard. Leave yourself an uphill putt.",
	"Press M to watch your last shot again.",
	"Between rounds, Tab opens the Clubhouse: hunt the stores for better used clubs.",
]

var hole_number := 1
var hole_name := ""
var hole_par := 4
var hole_yards := 0
var elapsed := 0.0
var progress := 0.0

var _root: Control
var _backdrop: ShaderMaterial
var _info: VBoxContainer
var _eyebrow: Label
var _number: Label
var _name: Label
var _name_col: VBoxContainer
var _tiles: HBoxContainer
var _tip_label: Label
var _caption: Label
var _bar: Control
var _status: HBoxContainer
var _status_label: Label
var _go: HBoxContainer
var _slides: Array = []  # Texture2D stills for this hole
var _slide_a: TextureRect
var _slide_b: TextureRect
var _slide_index := 0
var _slide_t := 0.0
var _cinema: Array = []  # overlay nodes shown only with stills
var _info_x := 0.0
var _initial := false
var _goal_progress := 0.0
var _tip_index := 0
var _tip_timer := 0.0
var _exit_elapsed := 0.0
var _can_finish := false
var _departing := false
var _covered := false
var _completed := false
var _skip_requested := false
var _stage_text := ""
static var _stats: Dictionary = {}


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
	_backdrop = ShaderMaterial.new()
	_backdrop.shader = BACKDROP
	_backdrop.set_shader_parameter("accent", UITheme.GO.lightened(0.15))
	_backdrop.set_shader_parameter("glow", 0.55)
	_backdrop.set_shader_parameter("focus", Vector2(0.3, 0.46))
	_backdrop.set_shader_parameter("floor_amount", 0.0)
	bg.material = _backdrop
	_root.add_child(bg)

	# postcard slideshow: two layers crossfading, each drifting under a slow pan and zoom
	_slide_a = _slide_layer()
	_slide_b = _slide_layer()
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = _vignette_shader()
	vignette.material = vm
	_root.add_child(vignette)
	_cinema.append(vignette)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = LETTERBOX
		else:
			bar.offset_top = -LETTERBOX - 34.0
		_root.add_child(bar)
		_cinema.append(bar)

	# hole details, right
	_info = VBoxContainer.new()
	_info.anchor_left = 0.53
	_info.anchor_right = 0.95
	_info.anchor_top = 0.5
	_info.anchor_bottom = 0.5
	_info.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info.add_theme_constant_override("separation", 10)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_info)
	_eyebrow = UITheme.eyebrow(_info, course_title, UITheme.GOLD)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(head)
	var num_col := VBoxContainer.new()
	num_col.add_theme_constant_override("separation", -8)
	num_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(num_col)
	UITheme.eyebrow(num_col, "Hole", UITheme.DIM)
	_number = UITheme.label(num_col, "1", 120, UITheme.GOLD, 700, 78)
	_number.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_number.add_theme_constant_override("shadow_offset_y", 4)
	var name_col := VBoxContainer.new()
	name_col.size_flags_vertical = Control.SIZE_SHRINK_END
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_col)
	_name_col = name_col
	_name = UITheme.label(name_col, "", 44, Color.WHITE, 700, 88)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var accent := ColorRect.new()
	accent.color = UITheme.GOLD
	accent.custom_minimum_size = Vector2(64, 3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(accent)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	name_col.add_child(spacer)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 10)
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_tiles)
	var tip_box := PanelContainer.new()
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := UITheme.glass(16, 12)
	tip_style.border_width_left = 3
	tip_style.border_color = Color(UITheme.GOLD, 0.6)
	tip_box.add_theme_stylebox_override("panel", tip_style)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	_info.add_child(gap)
	_info.add_child(tip_box)
	var tip_col := VBoxContainer.new()
	tip_col.add_theme_constant_override("separation", 4)
	tip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_box.add_child(tip_col)
	UITheme.eyebrow(tip_col, "Tip", UITheme.GOLD)
	_tip_label = UITheme.label(tip_col, "", 15, UITheme.TEXT, 500)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size.x = 380

	# progress bar + status, bottom
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
	_caption = UITheme.label(_root, "", 13, UITheme.DIM, 600, 100, 1)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 48
	_caption.offset_top = -44
	_caption.offset_bottom = -22
	_status = HBoxContainer.new()
	_status.anchor_left = 1.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_right = -48
	_status.offset_top = -46
	_status.offset_bottom = -20
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.alignment = BoxContainer.ALIGNMENT_END
	_status.add_theme_constant_override("separation", 8)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	_status_label = UITheme.label(_status, "LOADING  0%", 13, UITheme.DIM, 600, 100, 2)
	_go = HBoxContainer.new()
	_go.add_theme_constant_override("separation", 8)
	_go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_go.visible = false
	_status.add_child(_go)
	UITheme.keycap(_go, "SPACE", 12)
	UITheme.label(_go, "TEE OFF", 15, UITheme.GOLD, 700, 100, 3)
	_apply_texts()
	_layout()


func _slide_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# The stills are larger than the screen and drift: without mipmaps the fine detail
	# (pine needles, mowing stripes) aliases and crawls as they move.
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate.a = 0.0
	_root.add_child(t)
	return t


static var _vignette: Shader
static func _vignette_shader() -> Shader:
	if _vignette == null:
		_vignette = Shader.new()
		_vignette.code = VIGNETTE_CODE
	return _vignette


const VIGNETTE_CODE := "shader_type canvas_item;\n" \
	+ "void fragment() {\n" \
	+ "	vec2 v = (UV - vec2(0.5)) * vec2(1.0, 1.25);\n" \
	+ "	float edge = smoothstep(0.35, 0.95, length(v)) * 0.55;\n" \
	+ "	float corner = smoothstep(0.35, 1.0, UV.y) * (1.0 - smoothstep(0.1, 0.75, UV.x)) * 0.7;\n" \
	+ "	COLOR = vec4(0.0, 0.02, 0.015, clamp(edge + corner, 0.0, 0.85));\n" \
	+ "}\n"


## Slideshow layout with stills; the large-diagram studio layout without.
func _layout() -> void:
	var cinematic := not _slides.is_empty()
	for n in _cinema:
		n.visible = cinematic
	_slide_a.visible = cinematic
	_slide_b.visible = cinematic
	if cinematic:
		_info.anchor_left = 0.0
		_info.anchor_right = 0.0
		_info.anchor_top = 1.0
		_info.anchor_bottom = 1.0
		_info.offset_left = 56
		_info.offset_right = 660
		_info.offset_top = -LETTERBOX - 60.0
		_info.offset_bottom = -LETTERBOX - 60.0
		_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		_info.anchor_left = 0.08
		_info.anchor_right = 0.6
		_info.anchor_top = 0.5
		_info.anchor_bottom = 0.5
		for side in ["offset_left", "offset_right", "offset_top", "offset_bottom"]:
			_info.set(side, 0.0)
		_info.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info_x = _info.offset_left


## The postcard stills for hole `n`: imported textures, or the raw JPEGs straight after a
## render (before the editor has imported them).
static func _load_stills(n: int) -> Array:
	var out: Array = []
	for k in range(1, 4):
		var path := STILLS % [n, k]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				out.append(tex)
				continue
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				img.generate_mipmaps()
				out.append(ImageTexture.create_from_image(img))
	return out


## Slow push-in for slide `i` at local time `t` (0 at its start): each still drifts its own way.
## Driven by wall-clock time, so a frame the course build stalls doesn't make it lurch.
func _ken_burns(layer: TextureRect, i: int, t: float) -> void:
	var k := smoothstep(0.0, 1.0, clampf(t / (SLIDE_TIME + SLIDE_FADE * 2.0), 0.0, 1.0))
	var dirs := [Vector2(-1, -0.4), Vector2(1, -0.2), Vector2(-0.6, 0.5), Vector2(0.8, 0.4)]
	var d: Vector2 = dirs[i % dirs.size()]
	layer.pivot_offset = layer.size * 0.5
	layer.scale = Vector2.ONE * lerpf(1.02, 1.07, k)
	layer.position = d * 10.0 * (k - 0.5)


## Which course the card is for (statics, so they hold for every hole's loading screen).
static func set_course(title: String, is_augusta: bool) -> void:
	course_title = title
	augusta = is_augusta
	stills_enabled = is_augusta


## Hole details for the screen; `initial` marks the first load of a session.
func begin_hole(number: int, title: String, par_value: int, yards: int, initial: bool = false) -> void:
	hole_number = number
	hole_name = title
	hole_par = par_value
	hole_yards = yards
	_initial = initial
	progress = 0.0
	_stage_text = "Getting the course ready…" if initial else "Heading to the tee…"
	_tip_index = (number * 3) % TIPS.size()
	_slides = _load_stills(number) if stills_enabled else []
	_slide_index = 0
	_slide_t = 0.0
	if _slide_a != null:
		_slide_a.texture = _slides[0] if not _slides.is_empty() else null
		_slide_a.modulate.a = 1.0 if not _slides.is_empty() else 0.0
		_slide_a.set_meta("slide", 0)
		_slide_a.set_meta("t0", Time.get_ticks_msec() / 1000.0)
		_slide_b.modulate.a = 0.0
		_layout()
	_apply_texts()


func update_progress(value: float, caption: String = "") -> void:
	_goal_progress = maxf(_goal_progress, clampf(value, 0.0, 1.0))
	if caption != "":
		_stage_text = caption
		if _caption != null:
			_caption.text = caption.to_upper()


func mark_ready() -> void:
	_can_finish = true
	_goal_progress = 1.0


func is_ready_to_finish() -> bool:
	return _can_finish


func _apply_texts() -> void:
	if _number == null:
		return
	_number.text = str(hole_number)
	_name.text = hole_name
	_name_col.visible = hole_name != ""  # Course Studio holes have no names
	var where := "FIRST TEE" if _initial else ""
	if augusta and not (_initial and hole_number == 1):  # a back-nine round starts on 10
		where = "THE BACK NINE" if hole_number >= 10 else "THE FRONT NINE"
	_eyebrow.text = course_title.to_upper() + ("   ·   " + where if where != "" else "")
	_caption.text = _stage_text.to_upper()
	_tip_label.text = TIPS[_tip_index % TIPS.size()]
	for c in _tiles.get_children():
		_tiles.remove_child(c)
		c.queue_free()
	_tile("Par", str(hole_par))
	_tile("Yards", str(hole_yards))
	var st := _hole_stats(hole_number) if augusta else {}  # Masters averages are Augusta's
	if not st.is_empty():
		_tile("Scoring avg", "%.2f" % float(st["average"]))


func _tile(caption: String, value: String) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.glass(14, 9))
	_tiles.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	UITheme.eyebrow(v, caption)
	UITheme.label(v, value, 24, Color.WHITE, 700, 92)


static func _hole_stats(number: int) -> Dictionary:
	if _stats.is_empty() and FileAccess.file_exists(STATS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(STATS_PATH))
		_stats = parsed if parsed is Dictionary else {"holes": {}}
	return _stats.get("holes", {}).get(str(number), {})


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.08))
	var fill := w * clampf(progress, 0.0, 1.0)
	if fill > 0.0:
		_bar.draw_rect(Rect2(0, 0, fill, h), UITheme.GOLD)
		_bar.draw_rect(Rect2(fill - 30.0, -3.0, 30.0, h + 6.0), Color(UITheme.GOLD, 0.18))
		_bar.draw_circle(Vector2(fill, h * 0.5), 4.0, Color.WHITE, true, -1.0, true)


func _process(delta: float) -> void:
	if _completed:
		return
	var step := minf(delta, 0.1) * animation_speed
	elapsed += step
	var t := elapsed
	if demo_loop:
		t = fmod(elapsed, DEMO_LENGTH)
		_root.modulate.a = 1.0
	# fade in, then tell the game the screen is covered
	if not demo_loop and not _covered:
		_root.modulate.a = minf(elapsed / FADE_IN, 1.0)
		if elapsed >= FADE_IN:
			_covered = true
			covered.emit()
	# hole details slide in, the diagram draws itself, then the shots trace across it
	_info.modulate.a = clampf((t - 0.1) / 0.4, 0.0, 1.0)
	var info_w := _info.offset_right - _info.offset_left
	_info.offset_left = _info_x + lerpf(40.0, 0.0, ease(clampf((t - 0.1) / 0.5, 0.0, 1.0), 0.3))
	_info.offset_right = _info.offset_left + info_w
	_advance_slides(step)
	progress = move_toward(progress, 1.0 if demo_loop else _goal_progress, delta * 1.2)
	_bar.queue_redraw()
	var ready_now := _can_finish or demo_loop
	_go.visible = ready_now
	_status_label.visible = not ready_now
	_status_label.text = "LOADING   %d%%" % roundi(progress * 100.0)
	if ready_now:
		_go.modulate.a = 0.65 + 0.35 * sin(elapsed * 4.0)
	_tip_timer += step
	if _tip_timer >= TIP_SECONDS:
		_tip_timer = 0.0
		_tip_index += 1
		_tip_label.text = TIPS[_tip_index % TIPS.size()]
	if demo_loop:
		return
	if _can_finish and not _departing and (elapsed >= minimum_ride_time or _skip_requested):
		_departing = true
	if _departing:
		_exit_elapsed += step
		var k := clampf(_exit_elapsed / FADE_OUT, 0.0, 1.0)
		_root.modulate.a = 1.0 - k
		_root.pivot_offset = _root.size * 0.5
		_root.scale = Vector2.ONE * (1.0 + 0.03 * k)
		if k >= 1.0:
			_completed = true
			ride_finished.emit()


## Crossfade to the next still every SLIDE_TIME seconds; both layers keep drifting.
func _advance_slides(step: float) -> void:
	if _slides.is_empty():
		return
	_slide_t += step
	var n := _slides.size()
	if n > 1 and _slide_t >= SLIDE_TIME:
		# the incoming still goes on the hidden layer and fades up over the current one
		var incoming := _slide_b if _slide_a.modulate.a >= _slide_b.modulate.a else _slide_a
		var outgoing := _slide_a if incoming == _slide_b else _slide_b
		if incoming.modulate.a <= 0.001:
			_slide_index = (_slide_index + 1) % n
			incoming.texture = _slides[_slide_index]
			incoming.set_meta("slide", _slide_index)
			incoming.set_meta("t0", Time.get_ticks_msec() / 1000.0)
			outgoing.move_to_front()
			incoming.move_to_front()
			_move_overlays_front()
		var f := clampf((_slide_t - SLIDE_TIME) / SLIDE_FADE, 0.0, 1.0)
		incoming.modulate.a = f
		if f >= 1.0:
			outgoing.modulate.a = 0.0
			_slide_t = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for layer in [_slide_a, _slide_b]:
		if layer.modulate.a > 0.0:
			_ken_burns(layer, int(layer.get_meta("slide", 0)), now - float(layer.get_meta("t0", now)))


## Keep the overlays and text above the slide layers after one is moved to the front.
func _move_overlays_front() -> void:
	for n in _cinema:
		n.move_to_front()
	for n in [_info, _bar, _caption, _status]:
		n.move_to_front()


func _input(event: InputEvent) -> void:
	if _completed or demo_loop:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		# Space can shorten a ready screen; it can never skip unfinished work.
		if _can_finish:
			_skip_requested = true
	# The same press must not also hit a golf shot or change clubs underneath.
	get_viewport().set_input_as_handled()
