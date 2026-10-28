class_name CourseStudio
extends Node3D
const TEE_SIGN = preload("res://scripts/tee_hole_sign.gd")
## Course Studio: paint your own course and play it.
##
## Brushes (TerraBrush-style splat painting + sculpting over PaintedCourse): fairway, green,
## tee box, bunker, water, woods and rough (eraser); raise / lower / smooth / flatten the
## ground; plant single trees; place each hole's tee and pin. Ctrl inverts a brush (erases
## that surface, lowers instead of raising, removes trees). Everything is undoable.
## Course Studio only builds courses: the club's facilities are placed and run in the separate
## Course Manager mode. On the club's own course they show here read-only, so a new fairway
## isn't painted through the clubhouse.
## "Play course" saves and opens it in the real game (course.tscn via PaintedLayout).

const Surface = PaintedCourse.Surface

const MAX_UNDO := 40


## Every tool: label, hotkey, kind, the PaintedCourse surface or sculpt mode, swatch colour
## and its starting brush (radius m, softness 0..1 = 1 - hardness, strength 0..1).
const TOOLS := [
	{"id": "fairway", "label": "Fairway", "key": KEY_1, "kind": "paint", "surface": Surface.FAIRWAY, "color": "7fb04a", "radius": 14.0, "soft": 0.45, "strength": 1.0},
	{"id": "green", "label": "Green", "key": KEY_2, "kind": "paint", "surface": Surface.GREEN, "color": "b4dc74", "radius": 8.0, "soft": 0.3, "strength": 1.0},
	{"id": "teebox", "label": "Tee box", "key": KEY_3, "kind": "paint", "surface": Surface.TEE, "color": "98cf6a", "radius": 4.0, "soft": 0.15, "strength": 1.0},
	{"id": "bunker", "label": "Bunker", "key": KEY_4, "kind": "paint", "surface": Surface.BUNKER, "color": "eadfc0", "radius": 5.0, "soft": 0.3, "strength": 1.0},
	{"id": "water", "label": "Water", "key": KEY_5, "kind": "paint", "surface": Surface.WATER, "color": "3f8fa6", "radius": 12.0, "soft": 0.35, "strength": 1.0},
	{"id": "woods", "label": "Woods", "key": KEY_6, "kind": "paint", "surface": Surface.WOODS, "color": "2f6b33", "radius": 20.0, "soft": 0.5, "strength": 1.0},
	{"id": "rough", "label": "Rough", "key": KEY_7, "kind": "paint", "surface": Surface.ROUGH, "color": "3d6b2f", "radius": 10.0, "soft": 0.5, "strength": 1.0},
	{"id": "tree", "label": "Trees", "key": KEY_8, "kind": "tree", "color": "5d8f3e", "radius": 8.0, "soft": 0.5, "strength": 0.5},
	{"id": "raise", "label": "Raise", "key": KEY_9, "kind": "sculpt", "mode": "raise", "color": "c9a46a", "radius": 20.0, "soft": 0.7, "strength": 0.4},
	{"id": "lower", "label": "Lower", "key": KEY_0, "kind": "sculpt", "mode": "lower", "color": "8f7650", "radius": 20.0, "soft": 0.7, "strength": 0.4},
	{"id": "smooth", "label": "Smooth", "key": KEY_MINUS, "kind": "sculpt", "mode": "smooth", "color": "b9b39a", "radius": 18.0, "soft": 0.6, "strength": 0.6},
	{"id": "flatten", "label": "Flatten", "key": KEY_EQUAL, "kind": "sculpt", "mode": "flatten", "color": "d8d0b0", "radius": 14.0, "soft": 0.4, "strength": 0.6},
	{"id": "place_tee", "label": "Place tee", "key": KEY_T, "kind": "place_tee", "color": "a6e3ff", "radius": 2.0, "soft": 0.0, "strength": 1.0},
	{"id": "place_pin", "label": "Place pin", "key": KEY_P, "kind": "place_pin", "color": "ff6b5b", "radius": 2.0, "soft": 0.0, "strength": 1.0},
	{"id": "bend", "label": "Dogleg bend", "key": KEY_B, "kind": "bend", "color": "f2d27c", "radius": 2.0, "soft": 0.0, "strength": 1.0},
	{"id": "move", "label": "Move green / tee", "key": KEY_M, "kind": "move", "color": "c8d6ff", "radius": 2.0, "soft": 0.0, "strength": 1.0},
]
## Tree tool species groups -> NaturePack ids (one picked at random per tree).
const TREE_KINDS := {
	"Mixed": ["loblolly_pine_A", "longleaf_pine_A", "white_oak_A", "red_maple_A", "sweetgum_A", "tulip_poplar_A"],
	"Pines": ["loblolly_pine_A", "longleaf_pine_A", "eastern_white_pine_A"],
	"Oaks": ["white_oak_A", "live_oak_A"],
	"Maples": ["red_maple_A", "sweetgum_A"],
	"Magnolia": ["southern_magnolia_A"],
	"Dogwood": ["flowering_dogwood_white_A", "flowering_dogwood_pink_A"],
	"Willow": ["weeping_willow_A"],
	"Cypress": ["bald_cypress_A"],
}


var course: PaintedCourse
var path := ""
var tool_index := 0
var tree_kind := "Mixed"
var active_hole := 0
var _brush := {}  # tool id -> {"radius", "soft", "strength"}
var _undo: Array = []
var _redo: Array = []
var _saved_revision := -1

var camera: StudioCamera
var _view: PaintedView
var _mat: ShaderMaterial
var _holes_root: Node3D
var _facilities_root: Node3D
var _dirty_facilities := false
var _cursor := Vector3.ZERO
var _cursor_valid := false

# stroke state
var _stroking := false
var _drag_bend := -1  # index of the bend being dragged (Bend tool), -1 = none
## Move tool drag: {"region", "before" (PaintedCourse), "start" (cell), "offset", "pins", "tees"}
var _move := {}
const BEND_GRAB_M := 14.0
var _stroke_erase := false
var _stroke_before: PaintedCourse
var _stroke_rect := Rect2i()
var _last_dab := Vector2(INF, INF)
var _flatten_target := 0.0
var _rng := RandomNumberGenerator.new()
var _dirty_tex := false
var _dirty_woods := false
var _dirty_markers := false
var _woods_timer := 0.0

# ui
var _ui: CanvasLayer
var _tool_buttons: Array[Button] = []
var _name_edit: LineEdit
var _size_slider: HSlider
var _strength_slider: HSlider
var _soft_slider: HSlider
var _shape_row: HBoxContainer
var _shape_round: Button
var _shape_square: Button
var _holes_box: VBoxContainer
var _issues_box: VBoxContainer
var _tree_row: HBoxContainer
var _status: Label
var _toast: Label
var _toast_t := 0.0
var _dialog: Control
var _play_button: Button
var _hint: Label


func _ready() -> void:
	_rng.randomize()
	for t in TOOLS:
		_brush[t["id"]] = {"radius": t["radius"], "soft": t["soft"], "strength": t["strength"], "square": t["id"] == "teebox"}
	_build_world()
	_build_ui()
	var start := GameLaunch.custom_course
	var loaded: PaintedCourse = PaintedCourse.load_file(start) if start != "" and FileAccess.file_exists(start) else null
	if loaded != null:
		_open(loaded, start)
	else:
		_open(PaintedCourse.starter(_unique_name("My Course")), "")
	_select_tool(0)


# ================================================================ world

func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/golf_sky.gdshader")
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	env_node.environment = e
	add_child(env_node)
	GolfLook.apply(e, sun, {"fog_density": 0.00006, "fog_aerial": 0.0, "shadow_distance": 900.0, "sun_pitch": -52.0, "ambient_energy": 1.0, "sky_contribution": 0.6, "exposure": 1.08, "ssao_radius": 3.0})
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

	_view = PaintedView.new()
	_view.name = "View"
	add_child(_view)
	_mat = _view.material
	_holes_root = Node3D.new()
	_holes_root.name = "Holes"
	add_child(_holes_root)
	_facilities_root = Node3D.new()
	_facilities_root.name = "Facilities"
	add_child(_facilities_root)
	camera = StudioCamera.new()
	camera.ground_height = func(p: Vector2) -> float: return course.height_at(p) if course != null else 0.0
	add_child(camera)
	camera.make_current()


## Fresh grid mesh + textures for the course's canvas.
func _rebuild_terrain_mesh() -> void:
	_view.set_course(course)


func _push_textures() -> void:
	_view.push_textures()


func _process(delta: float) -> void:
	_update_cursor()
	if _dirty_tex:
		_dirty_tex = false
		_push_textures()
	_woods_timer -= delta
	if _dirty_woods and _woods_timer <= 0.0 and not _stroking:
		_dirty_woods = false
		_rebuild_trees()
	if _dirty_markers:
		_dirty_markers = false
		_rebuild_markers()
		_refresh_holes_panel()
	if _dirty_facilities and not _stroking:
		_dirty_facilities = false
		_rebuild_facilities()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_status.text = _status_text()


# ================================================================ cursor + input

func _update_cursor() -> void:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var hit: Variant = _raycast(from, dir)
	_cursor_valid = hit != null
	if _cursor_valid:
		_cursor = hit
	var t: Dictionary = TOOLS[tool_index]
	var b: Dictionary = _brush[t["id"]]
	var over_ui := vp.gui_get_hovered_control() != null
	_mat.set_shader_parameter("brush_pos", _cursor if _cursor_valid and not over_ui else Vector3(0, -10000, 0))
	_mat.set_shader_parameter("brush_radius", float(b["radius"]))
	_mat.set_shader_parameter("brush_hardness", 1.0 - float(b["soft"]))
	var square: bool = t["kind"] == "paint" and bool(b.get("square", false))
	_mat.set_shader_parameter("brush_square", square)
	if square and _cursor_valid:
		_mat.set_shader_parameter("brush_dir", _line_dir(Vector2(_cursor.x, _cursor.z)))
	var c := Color(String(t["color"]))
	if _erase_held() and t["kind"] in ["paint", "tree"]:
		c = UITheme.LOSS
	_mat.set_shader_parameter("brush_color", Color(c.lightened(0.25), 0.95))


## Ray march against the painted height field; returns the hit Vector3 or null.
func _raycast(from: Vector3, dir: Vector3) -> Variant:
	if course == null:
		return null
	var b := course.bounds().grow(-0.5)
	var t := 0.0
	var prev_t := 0.0
	var max_t := 5000.0
	while t < max_t:
		var p := from + dir * t
		var inside := b.has_point(Vector2(p.x, p.z))
		if inside and p.y <= course.height_at(Vector2(p.x, p.z)):
			# refine between prev_t and t
			var lo := prev_t
			var hi := t
			for i in range(16):
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y <= course.height_at(Vector2(q.x, q.z)):
					hi = mid
				else:
					lo = mid
			return from + dir * hi
		prev_t = t
		t += maxf(0.5, t * 0.004)
		if p.y < -200.0:
			break
	return null


func _erase_held() -> bool:
	return Input.is_key_pressed(KEY_CTRL)


func _unhandled_input(event: InputEvent) -> void:
	if _dialog != null and is_instance_valid(_dialog) and _dialog.visible:
		return
	if camera.handle_input(event, _cursor if _cursor_valid else null):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z:
			_redo_step() if k.shift_pressed else _undo_step()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			_redo_step()
		elif k.ctrl_pressed and k.keycode == KEY_S:
			_save()
		elif k.keycode == KEY_BRACKETLEFT:
			_scale_brush(1.0 / 1.2)
		elif k.keycode == KEY_BRACKETRIGHT:
			_scale_brush(1.2)
		elif k.keycode == KEY_HOME:
			camera.top_view()
		elif k.keycode == KEY_F:
			_focus_hole(active_hole)
		elif k.keycode == KEY_G:
			var on: bool = not bool(_mat.get_shader_parameter("show_grid"))
			_mat.set_shader_parameter("show_grid", on)
		elif not k.ctrl_pressed:
			for i in range(TOOLS.size()):
				if TOOLS[i]["key"] == k.keycode:
					_select_tool(i)
					break
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_scale_brush(1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _cursor_valid:
				_begin_stroke()
			elif not mb.pressed and _stroking:
				_end_stroke()
			elif not mb.pressed and _drag_bend >= 0:
				_drag_bend = -1
				_dirty_markers = true
			elif not mb.pressed and not _move.is_empty():
				_end_move()
	elif event is InputEventMouseMotion and not _move.is_empty() and _cursor_valid:
		_move_to(Vector2(_cursor.x, _cursor.z))
	elif event is InputEventMouseMotion and _drag_bend >= 0 and _cursor_valid:
		var bends: Array = course.holes[active_hole]["bends"]
		bends[_drag_bend] = Vector2(_cursor.x, _cursor.z)
		course.revision += 1
		_dirty_markers = true
	elif event is InputEventMouseMotion and _stroking and _cursor_valid:
		_stroke_to(Vector2(_cursor.x, _cursor.z))


func _scale_brush(f: float) -> void:
	var b: Dictionary = _brush[TOOLS[tool_index]["id"]]
	b["radius"] = clampf(float(b["radius"]) * f, 1.0, 80.0)
	MenuKit.set_slider(_size_slider, b["radius"])


# ================================================================ strokes

func _begin_stroke() -> void:
	var t: Dictionary = TOOLS[tool_index]
	var p := Vector2(_cursor.x, _cursor.z)
	match String(t["kind"]):
		"place_tee", "place_pin":
			_place_hole_point(String(t["kind"]) == "place_tee", p)
			return
		"bend":
			_bend_at(p)
			return
		"move":
			_begin_move(p)
			return
	_stroking = true
	_stroke_erase = _erase_held()
	_stroke_before = _clone_layers()
	_stroke_rect = Rect2i()
	_last_dab = Vector2(INF, INF)
	_flatten_target = course.height_at(p)
	_dab(p)


func _stroke_to(p: Vector2) -> void:
	var b: Dictionary = _brush[TOOLS[tool_index]["id"]]
	var spacing := maxf(float(b["radius"]) * 0.25, 0.6)
	if TOOLS[tool_index]["kind"] == "tree":
		spacing = maxf(float(b["radius"]) * 0.9, 3.0)
	if not is_finite(_last_dab.x):
		_dab(p)
		return
	var d := _last_dab.distance_to(p)
	if d < spacing:
		return
	var steps := int(d / spacing)
	var from := _last_dab
	for i in range(1, steps + 1):
		_dab(from.lerp(p, float(i) * spacing / d))


func _dab(p: Vector2) -> void:
	_last_dab = p
	var t: Dictionary = TOOLS[tool_index]
	var b: Dictionary = _brush[t["id"]]
	var radius := float(b["radius"])
	var hard := 1.0 - float(b["soft"])
	var strength := float(b["strength"])
	var rect := Rect2i()
	match String(t["kind"]):
		"paint":
			if bool(b.get("square", false)):
				rect = course.paint_box(int(t["surface"]), p, Vector2(radius, radius), _line_dir(p), strength, hard, _stroke_erase)
			else:
				rect = course.paint(int(t["surface"]), p, radius, strength, hard, _stroke_erase)
			# any surface clears woods under it, so the tree preview always follows
			_dirty_woods = true
			_woods_timer = 0.15
			_dirty_markers = true  # hole yardages/issues follow the paint
		"sculpt":
			var mode := String(t["mode"])
			if _stroke_erase and mode == "raise":
				mode = "lower"
			elif _stroke_erase and mode == "lower":
				mode = "raise"
			rect = course.sculpt(mode, p, radius, strength * (0.35 if mode in ["raise", "lower"] else 1.0), hard, _flatten_target)
			_dirty_markers = true
			_dirty_woods = true
		"tree":
			if _stroke_erase:
				course.remove_trees(p, radius)
			else:
				var n := 1 if radius < 6.0 else clampi(int(radius * radius / 60.0 * strength), 1, 12)
				for i in range(n):
					var q := p + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius * (0.0 if n == 1 else 1.0)
					if not course.in_canvas(q) or course.surface_at(q) in [Surface.WATER, Surface.BUNKER, Surface.GREEN, Surface.TEE]:
						continue
					var kinds: Array = TREE_KINDS[tree_kind]
					course.trees.append([kinds[_rng.randi_range(0, kinds.size() - 1)], q])
				course.revision += 1
			_dirty_woods = true
			_woods_timer = 0.0
			var cell := course.brush_rect(p, radius)
			rect = cell
	if rect.size != Vector2i.ZERO:
		_stroke_rect = rect if _stroke_rect.size == Vector2i.ZERO else _stroke_rect.merge(rect)
	_dirty_tex = true


func _end_stroke() -> void:
	_stroking = false
	_dirty_facilities = true  # sculpting may have moved the ground under a building
	if _stroke_rect.size != Vector2i.ZERO:
		_push_undo(_stroke_before.snapshot(_stroke_rect.grow(1).intersection(course.full_rect())))
	_stroke_before = null
	_dirty_woods = true
	_woods_timer = 0.0
	_dirty_markers = true


## A copy of the course's layers (cheap: packed-array copies) to cut undo regions from.
func _clone_layers() -> PaintedCourse:
	var c := PaintedCourse.new()
	c.size = course.size
	c.origin = course.origin
	c.splat_a = course.splat_a.duplicate()
	c.splat_b = course.splat_b.duplicate()
	c.height = course.height.duplicate()
	c.trees = course.trees.duplicate()
	c.holes = course.holes.duplicate(true)
	return c


func _push_undo(snap: Dictionary) -> void:
	_undo.append(snap)
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func _undo_step() -> void:
	if _undo.is_empty():
		_show_toast("Nothing to undo")
		return
	var snap: Dictionary = _undo.pop_back()
	_redo.append(course.canvas_snapshot() if snap.has("canvas_size") else course.snapshot(snap["rect"]))
	course.restore(snap)
	if snap.has("canvas_size"):
		_rebuild_terrain_mesh()
	_after_restore()


func _redo_step() -> void:
	if _redo.is_empty():
		_show_toast("Nothing to redo")
		return
	var snap: Dictionary = _redo.pop_back()
	_undo.append(course.canvas_snapshot() if snap.has("canvas_size") else course.snapshot(snap["rect"]))
	course.restore(snap)
	if snap.has("canvas_size"):
		_rebuild_terrain_mesh()
	_after_restore()


func _after_restore() -> void:
	active_hole = clampi(active_hole, 0, maxi(course.holes.size() - 1, 0))
	_dirty_facilities = true
	_dirty_tex = true
	_dirty_woods = true
	_woods_timer = 0.0
	_dirty_markers = true


# ================================================================ holes

func _place_hole_point(is_tee: bool, p: Vector2) -> void:
	_push_undo(course.snapshot(Rect2i(0, 0, 1, 1)))
	if course.holes.is_empty() or active_hole >= course.holes.size():
		course.holes.append({"tee": p, "pin": p + Vector2(0, -320), "par": 0, "bends": [], "curve": false})
		active_hole = course.holes.size() - 1
	var h: Dictionary = course.holes[active_hole]
	var before := _clone_layers()
	if is_tee:
		h["tee"] = p
		# no tee box under it yet: lay one, squared to the hole
		if course.coverage(Surface.TEE, p) < 0.5:
			var ctl := course.hole_controls(active_hole)
			course.paint_box(Surface.TEE, p, PaintedCourse.TEE_BOX_HALF, ctl[1] - ctl[0], 1.0, 0.9)
			_undo[_undo.size() - 1] = before.snapshot(course.brush_rect(p, 9.0).merge(Rect2i(0, 0, 1, 1)))
		_show_toast("Hole %d tee placed. Now place the pin (P)." % (active_hole + 1))
		_select_tool(_tool_index("place_pin"))
	else:
		h["pin"] = p
		if course.coverage(Surface.GREEN, p) < 0.5:
			course.paint(Surface.GREEN, p, 13.0, 1.0, 0.75)
			course.sculpt("smooth", p, 16.0, 1.0, 0.5)
			_undo[_undo.size() - 1] = before.snapshot(course.brush_rect(p, 18.0).merge(Rect2i(0, 0, 1, 1)))
			_show_toast("Pin placed - a green was laid around it. Shape it with the Green brush.")
		else:
			_show_toast("Hole %d pin placed: par %d, %d yards." % [active_hole + 1, course.hole_par(active_hole), course.hole_yards(active_hole)])
	course.revision += 1
	_dirty_tex = true
	_dirty_markers = true


## Bend tool click: grab the nearest bend of the active hole to drag it, or (Ctrl) delete it;
## clicking away from the bends adds a new one there and starts dragging it.
func _bend_at(p: Vector2) -> void:
	if course.holes.is_empty() or active_hole >= course.holes.size():
		_show_toast("Add a hole first (tee + pin), then bend it.")
		return
	var h: Dictionary = course.holes[active_hole]
	if not h.has("bends"):
		h["bends"] = []
	var bends: Array = h["bends"]
	var nearest := -1
	var best := BEND_GRAB_M
	for k in range(bends.size()):
		var d := (bends[k] as Vector2).distance_to(p)
		if d < best:
			best = d
			nearest = k
	_push_undo(course.snapshot(Rect2i(0, 0, 1, 1)))
	if _erase_held():
		if nearest >= 0:
			bends.remove_at(nearest)
			_show_toast("Bend removed: hole %d is %d yards." % [active_hole + 1, course.hole_yards(active_hole)])
		else:
			_undo.pop_back()
		course.revision += 1
		_dirty_markers = true
		return
	if nearest >= 0:
		_drag_bend = nearest
	else:
		_drag_bend = course.insert_bend(active_hole, p)
		_show_toast("Bend added - drag it to shape the dogleg. Curve smooths it into a sweeping hole.")
	course.revision += 1
	_dirty_markers = true


func _set_square(on: bool) -> void:
	_brush[TOOLS[tool_index]["id"]]["square"] = on
	_shape_round.set_pressed_no_signal(not on)
	_shape_square.set_pressed_no_signal(on)


## Direction square brushes are aligned to: the line of play of the active hole where it
## passes nearest `p` (so a tee box sits square to its hole, round a dogleg too).
func _line_dir(p: Vector2) -> Vector2:
	if course.holes.is_empty() or active_hole >= course.holes.size():
		return Vector2(0, -1)
	var route := course.hole_route(active_hole)
	var best := INF
	var dir := Vector2(0, -1)
	for k in range(1, route.size()):
		var d := Geometry2D.get_closest_point_to_segment(p, route[k - 1], route[k]).distance_to(p)
		if d < best and route[k - 1] != route[k]:
			best = d
			dir = (route[k] - route[k - 1]).normalized()
	return dir


## Move tool: pick up the green / tee box / bunker / pond under `p` (its whole painted
## shape) along with any hole pin or tee standing on it.
func _begin_move(p: Vector2) -> void:
	var region := course.region_at(p)
	if region.is_empty():
		_show_toast("Click a green or tee box (or a bunker or pond) and drag it.")
		return
	var pins: Array = []
	var tees: Array = []
	var cells := {}
	for i in region["cells"]:
		cells[i] = true
	var surface := int(region["surface"])
	for k in range(course.holes.size()):
		var h: Dictionary = course.holes[k]
		if surface == PaintedCourse.Surface.GREEN and cells.has(_cell_index(h["pin"])):
			pins.append([k, h["pin"]])
		if surface == PaintedCourse.Surface.TEE and cells.has(_cell_index(h["tee"])):
			tees.append([k, h["tee"]])
	var c := course.cell_of(p)
	_move = {"region": region, "before": _clone_layers(), "start": Vector2i(int(c.x), int(c.y)), "offset": Vector2i.ZERO, "pins": pins, "tees": tees, "last_rect": region["rect"]}


func _cell_index(world: Vector2) -> int:
	var c := course.cell_of(world)
	var x := int(c.x)
	var z := int(c.y)
	if x < 0 or z < 0 or x >= course.size.x or z >= course.size.y:
		return -1
	return z * course.size.x + x


## Live drag: undo the previous preview from the copy taken at pick-up, then lay the feature
## down at the new offset. Features are small (a green is a few hundred cells), so this is cheap.
func _move_to(p: Vector2) -> void:
	var c := course.cell_of(p)
	var offset := Vector2i(int(c.x), int(c.y)) - (_move["start"] as Vector2i)
	if offset == _move["offset"]:
		return
	var before: PaintedCourse = _move["before"]
	course.copy_layers_from(before, _move["last_rect"])
	_move["last_rect"] = course.move_region(_move["region"], offset)
	_move["offset"] = offset
	var shift := Vector2(offset) * PaintedCourse.CELL
	for e in _move["pins"]:
		course.holes[e[0]]["pin"] = (e[1] as Vector2) + shift
	for e in _move["tees"]:
		course.holes[e[0]]["tee"] = (e[1] as Vector2) + shift
	_dirty_tex = true
	_dirty_markers = true


func _end_move() -> void:
	var move := _move
	_move = {}
	var offset: Vector2i = move["offset"]
	if offset == Vector2i.ZERO:
		return
	var region: Dictionary = move["region"]
	var r: Rect2i = region["rect"]
	var dest := Rect2i(r.position + offset, r.size)
	var surface := int(region["surface"])
	# a moved green gets its putting surface eased level where it lands
	if surface == PaintedCourse.Surface.GREEN:
		var centre := course.world_of(dest.get_center().x, dest.get_center().y)
		course.sculpt("smooth", centre, maxf(dest.size.x, dest.size.y) * 0.5 * PaintedCourse.CELL + 3.0, 0.8, 0.5)
	# single trees can't stand on what was just put down
	var kept: Array = []
	for t in course.trees:
		var s := course.surface_at(t[1])
		if not (s in [PaintedCourse.Surface.GREEN, PaintedCourse.Surface.TEE, PaintedCourse.Surface.BUNKER, PaintedCourse.Surface.WATER] and dest.grow(1).has_point(Vector2i(course.cell_of(t[1])))):
			kept.append(t)
	course.trees = kept
	var touched := r.merge(dest).grow(6).intersection(course.full_rect())
	_push_undo((move["before"] as PaintedCourse).snapshot(touched))
	course.revision += 1
	_dirty_tex = true
	_dirty_woods = true
	_woods_timer = 0.0
	_dirty_markers = true
	var what: String = String(PaintedCourse.SURFACE_NAMES[surface]).to_lower()
	var msg := "Moved the %s %.0f m." % [what if surface != PaintedCourse.Surface.TEE else "tee box", Vector2(offset).length() * PaintedCourse.CELL]
	for e in move["pins"] + move["tees"]:
		msg += "  Hole %d is now %d yd." % [int(e[0]) + 1, course.hole_yards(int(e[0]))]
	_show_toast(msg)


## Dogleg (straight legs, sharp corner) or Curve (smooth spline through the bends).
func _set_curve(i: int, curve: bool) -> void:
	_push_undo(course.snapshot(Rect2i(0, 0, 1, 1)))
	course.holes[i]["curve"] = curve
	course.revision += 1
	_dirty_markers = true


## Paints a fairway along the active hole's line of play, using the Fairway brush's size as
## its half width.
func _lay_fairway(i: int) -> void:
	var before := _clone_layers()
	var rect := course.lay_fairway(i, clampf(float(_brush["fairway"]["radius"]), 8.0, 30.0))
	if rect.size != Vector2i.ZERO:
		_push_undo(before.snapshot(rect.grow(2).intersection(course.full_rect())))
	_dirty_tex = true
	_dirty_woods = true
	_woods_timer = 0.0
	_dirty_markers = true
	_show_toast("Fairway laid along hole %d (%d yd). Touch it up with the Fairway and Rough brushes." % [i + 1, course.hole_yards(i)])


func _add_hole() -> void:
	_push_undo(course.snapshot(Rect2i(0, 0, 1, 1)))
	var p := Vector2(camera.pivot.x, camera.pivot.z)
	course.holes.append({"tee": p + Vector2(0, 150), "pin": p + Vector2(0, -150), "par": 0, "bends": [], "curve": false})
	active_hole = course.holes.size() - 1
	course.revision += 1
	_dirty_markers = true
	_select_tool(_tool_index("place_tee"))
	_show_toast("Hole %d added: click to place its tee (T), then its pin (P)." % (active_hole + 1))


func _delete_hole(i: int) -> void:
	_push_undo(course.snapshot(Rect2i(0, 0, 1, 1)))
	course.holes.remove_at(i)
	active_hole = clampi(active_hole, 0, maxi(course.holes.size() - 1, 0))
	course.revision += 1
	_dirty_markers = true


func _focus_hole(i: int) -> void:
	if i < 0 or i >= course.holes.size():
		return
	active_hole = i
	var h: Dictionary = course.holes[i]
	var mid: Vector2 = (h["tee"] as Vector2).lerp(h["pin"], 0.5)
	var len := (h["tee"] as Vector2).distance_to(h["pin"])
	camera.focus(Vector3(mid.x, course.height_at(mid), mid.y), clampf(len * 1.15, 120.0, 900.0))
	_dirty_markers = true


func _tool_index(id: String) -> int:
	for i in range(TOOLS.size()):
		if TOOLS[i]["id"] == id:
			return i
	return 0


# ================================================================ trees + markers

func _rebuild_trees() -> void:
	_view.rebuild_trees()


func _rebuild_markers() -> void:
	for c in _holes_root.get_children():
		c.queue_free()
	for i in range(course.holes.size()):
		var h: Dictionary = course.holes[i]
		var tee: Vector2 = h["tee"]
		var pin: Vector2 = h["pin"]
		var active := i == active_hole
		var col := UITheme.GOLD if active else Color(1, 1, 1, 0.85)
		# route line, draped over the ground
		var im := ImmediateMesh.new()
		var line := MeshInstance3D.new()
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = col
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.no_depth_test = true
		lm.albedo_color.a = 0.85 if active else 0.5
		im.surface_begin(Mesh.PRIMITIVE_LINES, lm)
		# dashes every 4 m along the line of play (round the doglegs / along the curve)
		var route := course.hole_route(i, 3.0)
		var length := PaintedCourse.route_length(route)
		var n := maxi(int(length / 4.0), 2)
		for k in range(0, n, 2):
			var a := PaintedCourse.route_point(route, length * k / n)
			var bb := PaintedCourse.route_point(route, length * (k + 1) / n)
			im.surface_add_vertex(Vector3(a.x, course.height_at(a) + 0.6, a.y))
			im.surface_add_vertex(Vector3(bb.x, course.height_at(bb) + 0.6, bb.y))
		im.surface_end()
		line.mesh = im
		_holes_root.add_child(line)
		# bend handles: gold discs you can drag with the Bend tool
		for b in h.get("bends", []):
			var bp: Vector2 = b
			var hm := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 2.2 if active else 1.4
			cyl.bottom_radius = cyl.top_radius
			cyl.height = 0.25
			hm.mesh = cyl
			var hmat := StandardMaterial3D.new()
			hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hmat.albedo_color = UITheme.GOLD if active else Color(1, 1, 1, 0.7)
			hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hmat.no_depth_test = true
			hm.material_override = hmat
			hm.position = Vector3(bp.x, course.height_at(bp) + 0.7, bp.y)
			_holes_root.add_child(hm)
		_holes_root.add_child(TEE_SIGN.for_painted(course,i))
		# tee markers, square to the first leg
		var first: Vector2 = route[1] if route.size() > 1 else pin
		var dir := (first - tee).normalized() if first != tee else Vector2(0, -1)
		var right := Vector2(-dir.y, dir.x)
		for s in [-1.0, 1.0]:
			var mp: Vector2 = tee + right * 2.5 * s
			var m := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.7
			m.mesh = sm
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color("2b6cb0") if not active else UITheme.GOLD
			mm.emission_enabled = true
			mm.emission = mm.albedo_color * 0.4
			m.material_override = mm
			m.position = Vector3(mp.x, course.height_at(mp) + 0.3, mp.y)
			_holes_root.add_child(m)
		# flagstick
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 3.2
		pole.mesh = cm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.95, 0.95, 0.92)
		pole.material_override = pm
		var gy := course.height_at(pin)
		pole.position = Vector3(pin.x, gy + 1.6, pin.y)
		_holes_root.add_child(pole)
		var flag := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.4, 0.9)
		flag.mesh = qm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = UITheme.GOLD if active else Color("e8473b")
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		fm.emission_enabled = true
		fm.emission = fm.albedo_color * 0.35
		flag.material_override = fm
		flag.position = Vector3(pin.x + 0.7, gy + 2.7, pin.y)
		_holes_root.add_child(flag)
		# labels (billboards that keep their size)
		for lp in [[tee, "%d  TEE" % (i + 1)], [pin, "%d  PAR %d · %d YD" % [i + 1, course.hole_par(i), course.hole_yards(i)]]]:
			var lbl := Label3D.new()
			lbl.text = lp[1]
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.fixed_size = true
			lbl.pixel_size = 0.0011
			lbl.font = UITheme.font(700, 100, 2)
			lbl.font_size = 22
			lbl.outline_size = 8
			lbl.modulate = col
			lbl.outline_modulate = Color(0, 0, 0, 0.75)
			lbl.no_depth_test = true
			var q: Vector2 = lp[0]
			lbl.position = Vector3(q.x, course.height_at(q) + 5.0, q.y)
			_holes_root.add_child(lbl)


# ================================================================ open / save / play

func _expand_land() -> void:
	var before := course.canvas_snapshot()
	if not course.expand_land():
		_show_toast("The course is already at the maximum map size")
		return
	_push_undo(before)
	_rebuild_terrain_mesh()
	_after_restore()
	_show_toast("Land expanded to %d × %d m. Your holes stay in place. Save when ready." % [course.size.x, course.size.y])

func _open(c: PaintedCourse, p: String) -> void:
	course = c
	path = p
	var gs := GameState.current
	if gs != null and gs.business.owned and p != "" and gs.business.course_path == p:
		FacilityBuilder.grade(course, gs.business.placements, gs.business.built)  # the club's building plots, levelled
	_undo.clear()
	_redo.clear()
	active_hole = 0
	_rebuild_terrain_mesh()
	_rebuild_trees()
	_rebuild_markers()
	_refresh_holes_panel()
	_dirty_facilities = true
	_name_edit.text = course.course_name
	_saved_revision = course.revision if p != "" else -1
	camera.pivot = Vector3(0, course.height_at(Vector2.ZERO), 0)
	camera.focus(camera.pivot, maxf(course.size.x, course.size.y) * 0.8)
	if not course.holes.is_empty():
		_focus_hole(0)


func _save() -> bool:
	course.course_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else course.course_name
	var target := course.default_path()
	var err := course.save(target)
	if err != OK:
		_show_toast("Couldn't save (%s)" % error_string(err))
		return false
	if path != "" and path != target and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)  # renamed: drop the old file
	var gs := GameState.current
	if gs != null and gs.business.owned and path != "" and gs.business.course_path == path and path != target:
		gs.business.course_path = target  # the club follows its course through a rename
		gs.save()
	path = target
	if gs != null:
		gs.refresh_business()
	_saved_revision = course.revision
	_show_toast("Saved \"%s\"" % course.course_name)
	return true


func _play() -> void:
	var problems := course.issues()
	if not problems.is_empty():
		_show_toast(problems[0])
		return
	if not _save():
		return
	GameLaunch.play_custom(path, true)
	get_tree().change_scene_to_file(GameLaunch.COURSE_SCENE)


func _to_menu() -> void:
	if course.revision != _saved_revision:
		_save()
	get_tree().change_scene_to_file(GameLaunch.MENU_SCENE)


func _unique_name(base: String) -> String:
	var taken := {}
	for e in PaintedCourse.list_saved():
		taken[String(e["name"]).to_lower()] = true
	if not taken.has(base.to_lower()):
		return base
	for i in range(2, 100):
		var n := "%s %d" % [base, i]
		if not taken.has(n.to_lower()):
			return n
	return base


# ================================================================ the club's facilities (read-only)

## On the club's own course, its placed facilities at their built level (first level while
## only planned), so the course can be reshaped around them. Placing them is Course Manager's job.
func _rebuild_facilities() -> void:
	for c in _facilities_root.get_children():
		c.queue_free()
	var gs := GameState.current
	if course == null or gs == null or not gs.business.owned or path == "" or gs.business.course_path != path:
		return
	var items: Array = []
	for t in gs.business.placements:
		var pl: Dictionary = gs.business.placements[t]
		items.append({"type": t, "pos": pl["pos"], "rot": pl["rot"], "level": maxi(gs.business.level(t), 1), "name": course.course_name})
	if items.is_empty():
		return
	var ground := func(p: Vector2) -> float: return course.height_at(p)
	_facilities_root.add_child(FacilityBuilder.build(items, ground, false))


# ================================================================ UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# ---- top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.glass(14, 8))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 12
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	MenuKit.button(bar, "‹  Menu", "ghost", 14).pressed.connect(_to_menu)
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 0)
	bar.add_child(title_col)
	UITheme.eyebrow(title_col, "Course Studio", UITheme.GOLD)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_edit.add_theme_font_override("font", UITheme.font(700, 100))
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.add_theme_color_override("font_color", UITheme.TEXT)
	var ne := UITheme.box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 0, 6, 2)
	_name_edit.add_theme_stylebox_override("normal", ne)
	var nf := UITheme.box(Color(1, 1, 1, 0.08), UITheme.GO, 1, 6, 2)
	_name_edit.add_theme_stylebox_override("focus", nf)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _name_edit.release_focus())
	title_col.add_child(_name_edit)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(10, 0)
	bar.add_child(sep)
	MenuKit.button(bar, "New", "ghost", 14).pressed.connect(_show_new_dialog)
	MenuKit.button(bar, "Open", "ghost", 14).pressed.connect(_show_open_dialog)
	MenuKit.button(bar, "Save", "ghost", 14).pressed.connect(_save)
	MenuKit.button(bar, "Expand land", "ghost", 14).pressed.connect(_expand_land)
	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(10, 0)
	bar.add_child(sep2)
	MenuKit.button(bar, "Undo", "ghost", 14).pressed.connect(_undo_step)
	MenuKit.button(bar, "Redo", "ghost", 14).pressed.connect(_redo_step)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)
	_status = UITheme.label(bar, "", 12, UITheme.DIM, 500)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play_button = MenuKit.button(bar, "▶  Play course", "primary", 15)
	_play_button.pressed.connect(_play)

	# ---- tool palette (left)
	var left_wrap := MarginContainer.new()
	left_wrap.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_wrap.offset_left = 14
	left_wrap.offset_top = 84
	left_wrap.offset_bottom = -14
	left_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_wrap)
	var tools := MenuKit.panel(left_wrap, 10, 10, false, 2)
	tools.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var group_titles := {0: "Paint", 7: "Plant", 8: "Shape", 12: "Holes"}
	for i in range(TOOLS.size()):
		if group_titles.has(i):
			if i > 0:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 2)
				tools.add_child(gap)
			UITheme.eyebrow(tools, group_titles[i])
		var t: Dictionary = TOOLS[i]
		var b := MenuKit.button(tools, "", "tool", 13, Color(String(t["color"])))
		b.custom_minimum_size = Vector2(178, 26)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -8
		row.add_theme_constant_override("separation", 8)
		b.add_child(row)
		MenuKit.swatch(row, Color(String(t["color"])))
		var l := UITheme.label(row, String(t["label"]), 13, UITheme.TEXT, 600)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.keycap(row, OS.get_keycode_string(int(t["key"])), 9)
		var idx := i
		b.pressed.connect(func() -> void: _select_tool(idx))
		_tool_buttons.append(b)
		if t["id"] == "tree":
			_tree_row = HBoxContainer.new()
			_tree_row.add_theme_constant_override("separation", 4)
			tools.add_child(_tree_row)
			var opt := OptionButton.new()
			opt.focus_mode = Control.FOCUS_NONE
			opt.add_theme_font_override("font", UITheme.font(600))
			opt.add_theme_font_size_override("font_size", 12)
			for kname in TREE_KINDS.keys():
				opt.add_item(kname)
			opt.item_selected.connect(func(k: int) -> void: tree_kind = opt.get_item_text(k))
			opt.custom_minimum_size = Vector2(178, 0)
			_tree_row.add_child(opt)

	# ---- brush bar (bottom centre)
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UITheme.glass(18, 10))
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -14
	root.add_child(bottom)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 6)
	bottom.add_child(bcol)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 22)
	bcol.add_child(brow)
	_size_slider = MenuKit.slider(brow, "Brush size", 1.0, 80.0, 10.0, 0.5, "%.1f m", func(v: float) -> void: _brush[TOOLS[tool_index]["id"]]["radius"] = v)
	_strength_slider = MenuKit.slider(brow, "Strength", 0.05, 1.0, 1.0, 0.05, "%.2f", func(v: float) -> void: _brush[TOOLS[tool_index]["id"]]["strength"] = v)
	_soft_slider = MenuKit.slider(brow, "Softness", 0.0, 0.95, 0.5, 0.05, "%.2f", func(v: float) -> void: _brush[TOOLS[tool_index]["id"]]["soft"] = v)
	# brush shape: round, or square (squared to the hole's line of play) -- tee boxes default square
	var shape_col := VBoxContainer.new()
	shape_col.add_theme_constant_override("separation", 2)
	brow.add_child(shape_col)
	UITheme.eyebrow(shape_col, "Shape")
	_shape_row = HBoxContainer.new()
	_shape_row.add_theme_constant_override("separation", 3)
	shape_col.add_child(_shape_row)
	_shape_round = MenuKit.button(_shape_row, "Round", "tool", 12, UITheme.GOLD)
	_shape_square = MenuKit.button(_shape_row, "Square", "tool", 12, UITheme.GOLD)
	for btn in [_shape_round, _shape_square]:
		btn.custom_minimum_size = Vector2(66, 24)
	_shape_round.pressed.connect(func() -> void: _set_square(false))
	_shape_square.pressed.connect(func() -> void: _set_square(true))
	_hint = UITheme.label(bcol, "", 11, UITheme.DIM, 500)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ---- holes + checks (right)
	var right_wrap := MarginContainer.new()
	right_wrap.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_wrap.offset_right = -14
	right_wrap.offset_top = 84
	right_wrap.offset_bottom = -14
	right_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right_wrap)
	var rp := MenuKit.panel(right_wrap, 14, 12, false, 6)
	rp.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rp.custom_minimum_size = Vector2(250, 0)
	UITheme.eyebrow(rp, "Holes")
	_holes_box = VBoxContainer.new()
	_holes_box.add_theme_constant_override("separation", 4)
	rp.add_child(_holes_box)
	MenuKit.button(rp, "+  Add hole", "ghost", 13).pressed.connect(_add_hole)
	UITheme.rule(rp)
	UITheme.eyebrow(rp, "Course check")
	_issues_box = VBoxContainer.new()
	_issues_box.add_theme_constant_override("separation", 3)
	rp.add_child(_issues_box)
	UITheme.rule(rp)
	var help := UITheme.label(rp, "LMB paint · Ctrl erase\nRMB orbit · MMB pan · Wheel zoom\nWASD move · Q/E turn · Home map view\n[ ] or Ctrl+Wheel brush size\nCtrl+Z undo · Ctrl+S save · G grid", 11, UITheme.DIM, 500)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF

	# ---- toast
	_toast = UITheme.label(root, "", 15, UITheme.TEXT, 600, 100, 0, true)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_bottom = -118
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0


func _select_tool(i: int) -> void:
	tool_index = i
	for k in range(_tool_buttons.size()):
		_tool_buttons[k].set_pressed_no_signal(k == i)
	var t: Dictionary = TOOLS[i]
	var b: Dictionary = _brush[t["id"]]
	MenuKit.set_slider(_size_slider, b["radius"])
	MenuKit.set_slider(_strength_slider, b["strength"])
	MenuKit.set_slider(_soft_slider, b["soft"])
	var kind := String(t["kind"])
	var placing := kind in ["place_tee", "place_pin", "bend", "move"]
	_size_slider.get_parent().visible = not placing
	_strength_slider.get_parent().visible = not placing
	_soft_slider.get_parent().visible = not placing
	_shape_row.get_parent().visible = kind == "paint"
	_shape_round.set_pressed_no_signal(not bool(b.get("square", false)))
	_shape_square.set_pressed_no_signal(bool(b.get("square", false)))
	match kind:
		"paint":
			_hint.text = "Paint %s · hold Ctrl to erase it" % String(t["label"]).to_lower() if t["surface"] != Surface.ROUGH else "Paint rough over anything to clear it"
		"tree":
			_hint.text = "Click or drag to plant trees · Ctrl removes trees under the brush"
		"sculpt":
			_hint.text = {"raise": "Drag to raise the ground · Ctrl lowers", "lower": "Drag to lower the ground · Ctrl raises", "smooth": "Drag to smooth bumps and ridges", "flatten": "Levels to the height where the stroke starts"}[t["mode"]]
		"place_tee":
			_hint.text = "Click to place hole %d's tee" % (mini(active_hole, course.holes.size()) + 1 if course != null else 1)
		"place_pin":
			_hint.text = "Click to place hole %d's pin (a green is laid if none is there)" % (active_hole + 1)
		"bend":
			_hint.text = "Click the hole's line to add a dogleg bend and drag it · drag a gold bend to move it · Ctrl-click removes it"
		"move":
			_hint.text = "Drag a green or tee box (or a bunker / pond) to move it - its pin or tee comes along"



func _refresh_holes_panel() -> void:
	for c in _holes_box.get_children():
		c.queue_free()
	if course.holes.is_empty():
		UITheme.label(_holes_box, "No holes yet.", 12, UITheme.DIM, 500)
	for i in range(course.holes.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_holes_box.add_child(row)
		var b := MenuKit.button(row, "", "tool", 13, UITheme.GOLD)
		b.set_pressed_no_signal(i == active_hole)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 10
		inner.offset_right = -8
		b.add_child(inner)
		var n := UITheme.label(inner, "%d" % (i + 1), 15, UITheme.GOLD if i == active_hole else UITheme.TEXT, 700)
		n.custom_minimum_size = Vector2(22, 0)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var d := UITheme.label(inner, "Par %d · %d yd" % [course.hole_par(i), course.hole_yards(i)], 13, UITheme.TEXT, 600)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var idx := i
		b.pressed.connect(func() -> void:
			_focus_hole(idx)
			_refresh_holes_panel())
		var x := MenuKit.button(row, "✕", "ghost", 12)
		x.custom_minimum_size = Vector2(30, 30)
		x.pressed.connect(func() -> void: _delete_hole(idx))
		if i != active_hole:
			continue
		# the active hole's shape: dogleg / curve, its bends, and an automatic fairway
		var shape := HBoxContainer.new()
		shape.add_theme_constant_override("separation", 4)
		_holes_box.add_child(shape)
		var curve := course.hole_is_curve(i)
		var dog := MenuKit.button(shape, "Dogleg", "tool", 12, UITheme.GOLD)
		dog.set_pressed_no_signal(not curve)
		dog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dog.pressed.connect(func() -> void: _set_curve(idx, false))
		var cur := MenuKit.button(shape, "Curve", "tool", 12, UITheme.GOLD)
		cur.set_pressed_no_signal(curve)
		cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cur.pressed.connect(func() -> void: _set_curve(idx, true))
		var bend := MenuKit.button(shape, "+ Bend", "ghost", 12)
		bend.pressed.connect(func() -> void: _select_tool(_tool_index("bend")))
		var nb: int = (course.holes[i].get("bends", []) as Array).size()
		var info := UITheme.label(_holes_box, ("%d bend%s · drag them with the Bend tool (B), Ctrl-click removes" % [nb, "" if nb == 1 else "s"]) if nb > 0 else "Straight hole · add a bend (B) for a dogleg", 11, UITheme.DIM, 500)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(220, 0)
		MenuKit.button(_holes_box, "Lay fairway along this hole", "ghost", 12).pressed.connect(func() -> void: _lay_fairway(idx))
	for c in _issues_box.get_children():
		c.queue_free()
	var problems := course.issues()
	if problems.is_empty():
		UITheme.label(_issues_box, "✓  Ready to play", 13, UITheme.GAIN, 650)
	for p in problems:
		var l := UITheme.label(_issues_box, "•  " + p, 12, UITheme.AMBER, 550)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(220, 0)
	_play_button.disabled = not problems.is_empty()


func _status_text() -> String:
	var s := ""
	if _cursor_valid:
		var p := Vector2(_cursor.x, _cursor.z)
		s = "%s · %.1f m" % [PaintedCourse.SURFACE_NAMES[course.surface_at(p)], _cursor.y]
		if course.coverage(Surface.WOODS, p) > 0.5:
			s += " · woods"
	if course.revision != _saved_revision:
		s += "   ·  unsaved"
	return s


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.0
	_toast.modulate.a = 1.0


# ---- dialogs

func _close_dialog() -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _dialog_frame(title: String) -> VBoxContainer:
	_close_dialog()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(shade)
	_dialog = shade
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var v := MenuKit.panel(center, 26, 22, true, 10)
	v.custom_minimum_size = Vector2(460, 0)
	UITheme.label(v, title, 24, UITheme.TEXT, 700)
	return v


func _show_open_dialog() -> void:
	var v := _dialog_frame("Open a course")
	var saved := PaintedCourse.list_saved()
	if saved.is_empty():
		UITheme.label(v, "No saved courses yet.", 13, UITheme.DIM, 500)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(saved.size(), 6) * 46)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for e in saved:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		var b := MenuKit.button(row, "%s   ·   %d hole%s" % [e["name"], e["holes"], "" if e["holes"] == 1 else "s"], "ghost", 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p := String(e["path"])
		b.pressed.connect(func() -> void:
			var c := PaintedCourse.load_file(p)
			_close_dialog()
			if c != null:
				_open(c, p)
				_show_toast("Opened \"%s\"" % c.course_name)
			else:
				_show_toast("Couldn't read that course file"))
		var del := MenuKit.button(row, "Delete", "ghost", 13)
		del.pressed.connect(func() -> void: _confirm_delete(row, e))
	MenuKit.button(v, "Cancel", "ghost", 14).pressed.connect(_close_dialog)


## Ask in the row, then delete the course file for good. If it was the course open in the
## editor, that keeps going as an unsaved course (Save writes it back).
func _confirm_delete(row: HBoxContainer, e: Dictionary) -> void:
	for c in row.get_children():
		c.queue_free()
	var p := String(e["path"])
	var l := UITheme.label(row, StartMenu.delete_prompt(String(e["name"]), p), 13, UITheme.TEXT, 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(240, 0)
	MenuKit.button(row, "Delete", "danger", 13).pressed.connect(func() -> void:
		if PaintedCourse.delete_saved(p) != OK:
			_show_toast("Couldn't delete that course file")
		elif p == path:
			path = ""
			_saved_revision = -1
			_show_toast("Deleted \"%s\" (still open here: Save to keep it)" % e["name"])
		else:
			_show_toast("Deleted \"%s\"" % e["name"])
		_show_open_dialog())
	MenuKit.button(row, "Keep", "ghost", 13).pressed.connect(_show_open_dialog)


func _show_new_dialog() -> void:
	var v := _dialog_frame("New course")
	UITheme.label(v, "Start from a sample hole, or a blank canvas of rolling rough.", 13, UITheme.DIM, 500)
	for opt in [["Sample hole · 1,200 m", "starter", Vector2i(1200, 1200)], ["Blank · small (400 m)", "blank", Vector2i(400, 400)], ["Blank · medium (600 m)", "blank", Vector2i(600, 600)], ["Blank · large (1,200 m)", "blank", Vector2i(1200, 1200)], ["Blank · full course (2,000 m)", "blank", Vector2i(2000, 2000)]]:
		var b := MenuKit.button(v, opt[0], "ghost", 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var kind: String = opt[1]
		var sz: Vector2i = opt[2]
		b.pressed.connect(func() -> void:
			if course.revision != _saved_revision and path != "":
				_save()
			var name := _unique_name("My Course")
			var c := PaintedCourse.starter(name) if kind == "starter" else _blank(name, sz)
			_close_dialog()
			_open(c, ""))
	MenuKit.button(v, "Cancel", "ghost", 14).pressed.connect(_close_dialog)


func _blank(n: String, sz: Vector2i) -> PaintedCourse:
	var c := PaintedCourse.create(n, sz)
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.004
	noise.fractal_octaves = 3
	for z in range(sz.y):
		for x in range(sz.x):
			c.height[z * sz.x + x] = noise.get_noise_2d(x, z) * 3.0
	return c
