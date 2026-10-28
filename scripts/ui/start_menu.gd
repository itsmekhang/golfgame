class_name StartMenu
extends Control
## Title screen: a slow cinematic slideshow of in-game stills of Augusta (the loading-screen
## postcards, assets/loading/hole_NN_K.jpg) behind a dark-glass menu in the shared UITheme
## style. Play Augusta (front / back / full), the Course Studio, your own courses, quit.

const STILLS := "res://assets/loading/hole_%02d_%d.jpg"
const SLIDE_TIME := 7.0
const FADE_TIME := 1.6
const ROUND_SPANS := [["Full 18", "full18"], ["Front 9", "front9"], ["Back 9", "back9"]]

var _slides: Array = []  # [Texture2D, hole number]
var _order: Array = []
var _layer_a: TextureRect
var _layer_b: TextureRect
var _slide_i := 0
var _slide_t := 0.0
var _caption: Label
var _main: VBoxContainer
var _sub: VBoxContainer
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	GameLaunch.from_menu = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_slides()
	_build_ui()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)


func _load_slides() -> void:
	for n in range(1, 19):
		for k in range(1, 4):
			var path := STILLS % [n, k]
			if ResourceLoader.exists(path):
				_slides.append([path, n])
	_order = range(_slides.size())
	_order.shuffle()


func _texture(i: int) -> Texture2D:
	if _slides.is_empty():
		return null
	return load(_slides[_order[i % _order.size()]][0])


func _hole_of(i: int) -> int:
	return _slides[_order[i % _order.size()]][1] if not _slides.is_empty() else 0


func _process(delta: float) -> void:
	if _slides.is_empty():
		return
	_slide_t += delta
	_ken_burns(_layer_a, _slide_t)
	if _slide_t > SLIDE_TIME:
		# crossfade to the next still
		var k := clampf((_slide_t - SLIDE_TIME) / FADE_TIME, 0.0, 1.0)
		_layer_b.modulate.a = k
		_ken_burns(_layer_b, _slide_t - SLIDE_TIME)
		if k >= 1.0:
			_slide_i += 1
			var tmp := _layer_a
			_layer_a = _layer_b
			_layer_b = tmp
			_layer_a.move_to_front()
			_layer_b.modulate.a = 0.0
			_layer_b.texture = _texture(_slide_i + 1)
			_slide_t = FADE_TIME
			_layer_a.get_parent().move_child(_layer_b, 0)
			_layer_a.get_parent().move_child(_layer_a, 1)
			_update_caption()


## Slow push-in with a drift that changes per slide.
func _ken_burns(layer: TextureRect, t: float) -> void:
	var k := clampf(t / (SLIDE_TIME + FADE_TIME * 2.0), 0.0, 1.0)
	var dirs := [Vector2(-1, -0.4), Vector2(1, -0.2), Vector2(-0.6, 0.5), Vector2(0.8, 0.4)]
	var d: Vector2 = dirs[(_slide_i + (0 if layer == _layer_a else 1)) % dirs.size()]
	layer.pivot_offset = layer.size * 0.5
	layer.scale = Vector2.ONE * lerpf(1.04, 1.12, k)
	layer.position = d * 18.0 * (k - 0.5)


func _update_caption() -> void:
	var n := _hole_of(_slide_i)
	if n > 0:
		var info := CourseBuilder.hole_info(n - 1)
		_caption.text = "HOLE %d  ·  %s  ·  PAR %d" % [n, String(info["name"]).to_upper(), int(info["par"])]


# ================================================================ UI

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var slides := Control.new()
	slides.set_anchors_preset(Control.PRESET_FULL_RECT)
	slides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slides)
	for i in range(2):
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slides.add_child(tr)
		if i == 0:
			_layer_b = tr
		else:
			_layer_a = tr
	_layer_a.texture = _texture(0)
	_layer_b.texture = _texture(1)
	_layer_b.modulate.a = 0.0

	# left-side shade so the menu reads, plus a soft vignette at the bottom
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.0, 0.03, 0.02, 0.88), Color(0.0, 0.03, 0.02, 0.45), Color(0.0, 0.03, 0.02, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.66
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var vgrad := Gradient.new()
	vgrad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0.02, 0.015, 0.7)])
	var vt := GradientTexture2D.new()
	vt.gradient = vgrad
	vt.fill_from = Vector2(0, 0)
	vt.fill_to = Vector2(0, 1)
	var bottom := TextureRect.new()
	bottom.texture = vt
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -220
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 92
	col.offset_right = 600
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	UITheme.eyebrow(col, "OpenFairway Golf", UITheme.GOLD, true)
	UITheme.label(col, "FAIRWAY", 92, UITheme.TEXT, 800, 85, 8, true)
	UITheme.label(col, "Augusta National  ·  Course Studio  ·  Collect the clubs", 15, Color(1, 1, 1, 0.72), 500, 100, 1, true)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 34)
	col.add_child(gap)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	col.add_child(_main)
	_sub = VBoxContainer.new()
	_sub.add_theme_constant_override("separation", 10)
	_sub.visible = false
	col.add_child(_sub)
	_build_main()

	_caption = UITheme.label(self, "", 12, Color(1, 1, 1, 0.7), 600, 100, 3, true)
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caption.offset_right = -40
	_caption.offset_top = -46
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_update_caption()
	var foot := UITheme.label(self, "Esc during a round  ·  main menu", 11, Color(1, 1, 1, 0.45), 500, 100, 1, true)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 92
	foot.offset_top = -46

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _menu_button(parent: Node, text: String, sub: String, primary: bool, action: Callable) -> Button:
	var b := MenuKit.button(parent, "", "primary" if primary else "ghost", 18)
	b.custom_minimum_size = Vector2(420, 64)
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -22
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	b.add_child(row)
	UITheme.label(row, text, 19, Color.WHITE, 700, 100, 1)
	if sub != "":
		UITheme.label(row, sub, 12, Color(1, 1, 1, 0.72) if primary else UITheme.DIM, 500)
	b.pressed.connect(action)
	return b


func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()


func _build_main() -> void:
	_clear(_main)
	_main.visible = true
	_sub.visible = false
	_menu_button(_main, "Play Augusta", "18 holes traced from the real course", true, _show_spans)
	_menu_button(_main, "Course Studio", "Paint fairways, greens, bunkers, water and woods", false, func() -> void: _go_studio(""))
	_menu_button(_main, "My Courses", "Play a course you built", false, _show_courses)
	_menu_button(_main, "Course Manager", _manager_caption(), false, func() -> void: _transition(GameLaunch.MANAGER_SCENE))
	_menu_button(_main, "Quit", "", false, func() -> void: get_tree().quit())


## Course Manager's line on the menu: the club and whether it's open, or what unlocks it.
func _manager_caption() -> String:
	var gs := GameState.current
	if gs == null:
		return "Run your own golf club"
	if gs.business.owned:
		gs.refresh_business()
		var reason := gs.business.closed_reason()
		return "%s  ·  %s" % [gs.business.course_name if gs.business.has_course() else "No course chosen", "open" if reason == "" else "closed"]
	var st := gs.manager_status()
	return "Run your own golf club  ·  %s" % ("ready to buy" if st["can_buy"] else "unlocks with %s" % st["store_name"])


func _show_spans() -> void:
	_clear(_sub)
	_main.visible = false
	_sub.visible = true
	UITheme.eyebrow(_sub, "Augusta National  ·  choose a round", UITheme.GOLD, true)
	for s in ROUND_SPANS:
		var span: String = s[1]
		_menu_button(_sub, s[0], {"full18": "Tea Olive to Holly", "front9": "Holes 1-9", "back9": "Holes 10-18 · Amen Corner"}[span], span == "full18", func() -> void: _go_augusta(span))
	_menu_button(_sub, "‹  Back", "", false, _build_main)


func _show_courses() -> void:
	_clear(_sub)
	_main.visible = false
	_sub.visible = true
	UITheme.eyebrow(_sub, "My Courses", UITheme.GOLD, true)
	var saved := PaintedCourse.list_saved()
	if saved.is_empty():
		var l := UITheme.label(_sub, "Nothing built yet. Open the Course Studio to paint your first hole.", 14, UITheme.DIM, 500, 100, 0, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
	else:
		# every course, newest first; five rows show, the rest scroll
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, mini(saved.size(), 5) * 68 - 8)
		_sub.add_child(scroll)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		for e in saved:
			_course_row(list, e)
	_menu_button(_sub, "‹  Back", "", false, _build_main)


## One saved course: play it, edit it in the studio, or delete it (asks first, in the row).
func _course_row(list: VBoxContainer, e: Dictionary) -> void:
	var p := String(e["path"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	list.add_child(row)
	var b := _menu_button(row, String(e["name"]), "%d hole%s" % [e["holes"], "" if e["holes"] == 1 else "s"], false, func() -> void: _go_custom(p))
	b.custom_minimum_size = Vector2(320, 60)
	var edit := MenuKit.button(row, "Edit", "ghost", 14)
	edit.custom_minimum_size = Vector2(76, 60)
	edit.pressed.connect(func() -> void: _go_studio(p))
	var del := MenuKit.button(row, "Delete", "ghost", 14)
	del.custom_minimum_size = Vector2(86, 60)
	del.pressed.connect(func() -> void: _confirm_delete(row, e))


func _confirm_delete(row: HBoxContainer, e: Dictionary) -> void:
	for c in row.get_children():
		c.queue_free()
	var p := String(e["path"])
	var l := UITheme.label(row, delete_prompt(String(e["name"]), p), 13, UITheme.TEXT, 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(314, 60)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var yes := MenuKit.button(row, "Delete", "danger", 14)
	yes.custom_minimum_size = Vector2(86, 60)
	yes.pressed.connect(func() -> void:
		if PaintedCourse.delete_saved(p) != OK:
			push_warning("Couldn't delete %s" % p)
		_show_courses())
	var no := MenuKit.button(row, "Keep", "ghost", 14)
	no.custom_minimum_size = Vector2(76, 60)
	no.pressed.connect(_show_courses)


## The question asked before a course file is deleted (shared with the Course Studio).
static func delete_prompt(course_name: String, path: String) -> String:
	var text := "Delete \"%s\" for good? This can't be undone." % course_name
	var gs := GameState.current
	if gs != null and gs.business.owned and gs.business.course_path == path:
		text += " It's your club's course: the club closes until you choose another."
	return text


func _transition(scene: String) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


func _go_augusta(span: String) -> void:
	GameLaunch.play_augusta(span)
	_transition(GameLaunch.COURSE_SCENE)


func _go_custom(path: String) -> void:
	GameLaunch.play_custom(path)
	_transition(GameLaunch.COURSE_SCENE)


func _go_studio(path: String) -> void:
	GameLaunch.custom_course = path
	_transition(GameLaunch.STUDIO_SCENE)
