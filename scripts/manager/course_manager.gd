class_name CourseManager
extends Node3D
## Course Manager mode (start menu > Course Manager): run a golf club on one of your Course
## Studio courses. It is its own mode -- Course Studio only builds courses. Buy the deed (gated
## by GameState.manager_status), choose the club's course, place facilities on a 3D view of it,
## build and upgrade them, fit out the clubhouse rooms, hire staff, set the green fee and read
## the books, live while the club earns in real time. Placing: press Place on a facility, hover
## open rough (the ring turns green), click; Q / E (or R / Shift+R, or the Turn buttons) turn it,
## Esc cancels. A placed facility turns where it stands from its card. V (or the view
## buttons) lifts the roof off and drops the walls, like a dollhouse, to see inside; click a
## room to open it on the Rooms tab. Rules and money all go through GameState.

const ROTATE_DEG := 15.0
const TABS := [["club", "Club"], ["facilities", "Facilities"], ["rooms", "Rooms"], ["staff", "Staff"], ["books", "Books"]]
const VIEWS := [[FacilityBuilder.View.EXTERIOR, "Building"], [FacilityBuilder.View.ROOF_OFF, "Roof off"], [FacilityBuilder.View.WALLS_DOWN, "Walls down"]]
const AMBER := Color("ffb648")
const SIDE_W := 440

var course: PaintedCourse
var camera: StudioCamera
var _view: PaintedView
var _mat: ShaderMaterial
var _facilities_root: Node3D
var _ghost: Node3D
var _placing := ""  # facility id being placed or moved ("" = not placing)
var _place_rot := 0.0
var _place_ok := false
var _loaded_path := ""
var _cursor := Vector3.ZERO
var _cursor_valid := false
var _tab := "club"
var _view_mode: int = FacilityBuilder.View.EXTERIOR
var _view_buttons: Array = []
var _room_sel := ""  # the room picked in the cutaway (Rooms tab shows it first)
var _built: Node3D  # the facilities FacilityBuilder made (children: one node per facility)
var _fac_sig := ""  # what the facilities were last built from, so a hire doesn't rebuild them
var _pad_sig := ""  # the placements the ground was last graded for
var _parked := -1.0  # the share of the parking lot's stalls with a car in them
var _clubs_todo := false  # the pro shop's club stands still being filled, a model a frame
var _life: ClubLife  # the staff at work and the golfers out playing
## Set (with `loaded`) once the course, its buildings and the people are up and the loading
## screen has gone.
signal loaded
var is_loaded := false

var _ui: CanvasLayer
var _side_wrap: MarginContainer
var _side_toggle: Button
var _side_open := true
var _side: VBoxContainer
var _tabs_row: HBoxContainer
var _title: Label
var _clock: Label
var _wallet: Label
var _status: Button
var _hint: Label
var _hint_panel: PanelContainer
var _toast: Label
var _toast_t := 0.0
var _live := {}
const SIM_STEP := 1.0 / 30.0
const SIM_SPEEDS := [0.0, 1.0, 2.0, 4.0, 8.0]
const TRAFFIC_MODES := ["normal", "quiet", "rush", "daily"]
var simulation_speed := 1.0
var _simulation_remainder := 0.0
var _effective_speed := 1.0
var _sim_stats: Label
var _speed_option: OptionButton
var _traffic_option: OptionButton
var _stats_wait := 0.0
var _cursor_mouse := Vector2.INF
var _cursor_camera := Transform3D.IDENTITY
var _cursor_dirty := true


func _ready() -> void:
	_build_world()
	_build_ui()
	var gs := GameState.current
	gs.refresh_business()
	gs.changed.connect(_on_changed)
	gs.business_ticked.connect(_on_tick)
	# a loading screen while the course, its buildings and the people come up (none headless:
	# tests load in one go)
	var screen: ManagerLoadingScreen = null
	if DisplayServer.get_name() != "headless":
		screen = ManagerLoadingScreen.new()
		add_child(screen)
		screen.set_club("", gs.business.clock_text() if gs.business.owned else "", [])
		await screen.covered
		screen.update_progress(0.08, "Opening the course…")
		await get_tree().process_frame
	if _open_course():
		if screen != null:
			screen.set_club(course.course_name, gs.business.clock_text(), _club_tiles())
			screen.update_progress(0.45, "Laying out the grounds…")
			await get_tree().process_frame
		_draw_course()
		if screen != null:
			# each building raised in its own frame (build() then takes them as they are), so the
			# bar moves building by building
			var items := _facility_items()
			var ground := func(p: Vector2) -> float: return course.height_at(p)
			for n in range(items.size()):
				var id := str(items[n]["type"])
				screen.update_progress(0.55 + 0.3 * n / maxf(items.size(), 1), "Raising the %s…" % _facility_name(id).to_lower())
				await get_tree().process_frame
				FacilityBuilder.prebuild(items[n], ground, false, true)
			screen.update_progress(0.88, "Calling in the staff…")
			await get_tree().process_frame
		_furnish_course()
	_refresh()
	if screen != null:
		screen.mark_ready()
		await screen.ride_finished
		screen.queue_free()
	if not gs.offline_report.is_empty() and gs.business.owned:
		var net := int(gs.offline_report.get("net", 0))
		_show_toast("While you were away (%s) your club %s $%d" % [_duration(int(gs.offline_report.get("seconds", 0))), "made" if net >= 0 else "lost", absi(net)], 5.0)
		gs.offline_report = {}
	is_loaded = true
	gs.begin_manager_simulation()
	loaded.emit()


## The club's numbers for the loading screen: what's built, who's hired, its rating.
func _club_tiles() -> Array:
	var b := GameState.current.business
	if not b.owned:
		return []
	var built := 0
	for id in b.built:
		built += 1 if int(b.built[id]) > 0 else 0
	var hired := 0
	for role in b.staff:
		hired += int(b.staff[role])
	return [["Holes", str(course.holes.size())], ["Facilities", str(built)], ["Staff", str(hired)], ["Rating", "★ %.1f" % float(b.rates()["stars"])]]


# ================================================================ world

func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
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
	GolfLook.apply(e, sun, {"fog_density": 0.00006, "fog_aerial": 0.0, "shadow_distance": 900.0, "sun_pitch": -48.0, "ambient_energy": 1.0, "sky_contribution": 0.6, "exposure": 1.05, "ssao_radius": 3.0})
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_view = PaintedView.new()
	_view.name = "View"
	_view.visible = false
	add_child(_view)
	_mat = _view.material
	_mat.set_shader_parameter("brush_pos", Vector3(0, -10000, 0))
	_facilities_root = Node3D.new()
	_facilities_root.name = "Facilities"
	add_child(_facilities_root)
	_life = ClubLife.new()
	_life.name = "ClubLife"
	add_child(_life)
	_life.set_process(false)
	camera = StudioCamera.new()
	camera.ground_height = func(p: Vector2) -> float: return course.height_at(p) if course != null else 0.0
	add_child(camera)
	camera.make_current()


## Open the club's course (if one is chosen) and draw it with the club's facilities.
func _load_course() -> void:
	if _open_course():
		_draw_course()
		_furnish_course()


## Read the club's course and grade its building plots; false when there's none to show.
func _open_course() -> bool:
	var b := GameState.current.business
	var p := b.course_path if b.owned and b.has_course() else ""
	_loaded_path = p
	if p == "":
		course = null
		_view.visible = false
		_rebuild_facilities()
		return false
	course = PaintedCourse.load_file(p)
	if course == null:
		_view.visible = false
		return false
	_clear_trees_under_facilities()
	FacilityBuilder.grade(course, b.placements, b.built)
	_pad_sig = var_to_str([b.placements, b.built])
	return true


func _draw_course() -> void:
	_cursor_dirty = true
	_view.set_course(course)
	ManagerGreenPins.install(_view, course)
	_view.visible = true
	_fac_sig = ""


## The club's buildings, its staff and golfers, and the camera over them.
func _furnish_course() -> void:
	var b := GameState.current.business
	_auto_park()  # the view is up: setting the lot down regrades and rebuilds through _on_changed
	_rebuild_facilities()
	var focus := Vector3(0, course.height_at(Vector2.ZERO), 0)
	if not b.placements.is_empty():
		var c := Vector2.ZERO
		for id in b.placements:
			c += b.placements[id]["pos"]
		c /= b.placements.size()
		focus = Vector3(c.x, course.height_at(c), c.y)
	elif not course.holes.is_empty():
		var t: Vector2 = course.holes[0]["tee"]
		focus = Vector3(t.x, course.height_at(t), t.y)
	camera.pivot = focus
	camera.focus(focus, 260.0)


## Single trees the course planted under a facility don't grow through its roof (this view
## only; the course file is Course Studio's and isn't saved from here).
func _clear_trees_under_facilities() -> void:
	if course == null:
		return
	var b := GameState.current.business
	var pl: Dictionary = b.placements
	# only by what's built on: the open ground of a plot keeps the course's own trees
	course.trees = course.trees.filter(func(t) -> bool:
		for id in pl:
			if FacilityBuilder.built_near(id, b.level(id), pl[id]["pos"], float(pl[id]["rot"]), t[1], 4.0):
				return false
		return true)


## Rebuild the club's buildings from the business -- only when what they're built from changed
## (placements, levels, rooms), so hiring someone doesn't reload the clubhouse. A moved
## facility re-grades the ground first.
func _rebuild_facilities() -> void:
	var b := GameState.current.business
	var sig := var_to_str([_loaded_path, course.course_name if course != null else "", b.placements, b.built, b.rooms, _placing])
	if sig == _fac_sig and (_built != null or course == null or b.placements.is_empty()):
		return
	_fac_sig = sig
	for c in _facilities_root.get_children():
		c.queue_free()
	_built = null
	_clubs_todo = false
	if course == null:
		_wake_life()
		return
	if var_to_str([b.placements, b.built]) != _pad_sig:
		_pad_sig = var_to_str([b.placements, b.built])
		_clear_trees_under_facilities()
		FacilityBuilder.grade(course, b.placements, b.built)
		_view.set_course(course)
		ManagerGreenPins.install(_view, course)
		_cursor_dirty = true
	if b.placements.is_empty():
		_wake_life()
		return
	var ground := func(p: Vector2) -> float: return course.height_at(p)
	_built = FacilityBuilder.build(_facility_items(), ground, false, true)
	_facilities_root.add_child(_built)
	FacilityBuilder.set_view(_built, _view_mode)
	_clubs_todo = true
	_parked = -1.0
	_park_cars(b.rates())
	_wake_life()


## What FacilityBuilder.build() is given for the club's placed facilities.
func _facility_items() -> Array:
	var b := GameState.current.business
	var items: Array = []
	for id in b.placements:
		if id == _placing:
			continue  # the ghost stands in for it while it's being moved
		var pl: Dictionary = b.placements[id]
		items.append({"type": id, "pos": pl["pos"], "rot": pl["rot"], "level": b.level(id), "name": course.course_name, "rooms": b.rooms})
	return items


## The parking lot as full as the course is busy (a few staff cars while it's closed), in
## steps of a tenth so it isn't refilled every tick.
func _park_cars(r: Dictionary) -> void:
	var lot := _facility_node("parking_lot")
	if lot == null:
		return
	var share := 0.1
	if r["open"] and float(r["parking_cap"]) > 0.0:
		share = clampf(float(r["golfers"]) / float(r["parking_cap"]), 0.1, 1.0)
	share = snappedf(share, 0.1)
	if share != _parked:
		_parked = share
		FacilityBuilder.park(lot, share)


## The deed comes with a gravel parking lot: the first time the clubhouse stands on the course,
## set the lot down beside it (moved, turned or removed like any facility after that).
func _auto_park() -> void:
	var gs := GameState.current
	var b := gs.business
	if course == null or b.auto_parked or b.placements.has("parking_lot") or not b.placements.has("clubhouse"):
		return
	var spot := FacilityBuilder.beside(course, _sited(), "parking_lot", "clubhouse", maxi(b.level("parking_lot"), 1))
	if spot.is_empty():
		return
	b.auto_parked = true
	gs.place_facility("parking_lot", spot["pos"], spot["rot"])
	_show_toast("Your gravel parking lot is next to the clubhouse · move or turn it on the Facilities tab", 4.0)


## Point the club's people at the course and buildings as they are now.
func _wake_life() -> void:
	_cursor_dirty = true
	var b := GameState.current.business
	if course == null or not b.owned:
		_life.clear()
		_life.course = null
		return
	if _life.course != course:
		_life.clear()
	_life.course = course
	_life.facilities = _built
	_life.business = b
	_life.refresh()


## The built facility of `type` (null if it isn't up).
func _facility_node(type: String) -> Node3D:
	return _built.get_node_or_null(type) as Node3D if _built != null else null


func _set_view_mode(mode: int) -> void:
	_view_mode = mode
	if _built != null:
		FacilityBuilder.set_view(_built, mode)
	for i in range(_view_buttons.size()):
		(_view_buttons[i] as Button).set_pressed_no_signal(VIEWS[i][0] == mode)


## A click on the course (not placing): inside the clubhouse, open the room under the cursor
## (lifting the roof off first if it's on).
func _click_course(p: Vector3) -> void:
	var house := _facility_node("clubhouse")
	if house == null:
		return
	var b := GameState.current.business
	var pl: Dictionary = b.placements.get("clubhouse", {})
	if pl.is_empty() or not FacilityBuilder.contains("clubhouse", pl["pos"], float(pl["rot"]), Vector2(p.x, p.z)):
		return
	if _view_mode == FacilityBuilder.View.EXTERIOR:
		_set_view_mode(FacilityBuilder.View.ROOF_OFF)
		camera.focus(FacilityBuilder.building_center(house), 75.0)
		return
	var room := FacilityBuilder.room_at(house, p)
	if room == "":
		return
	_room_sel = room
	_tab = "rooms"
	_refresh()
	var t := b.room_tier(room)
	_show_toast("%s · %s" % [_room_name(room), b.tier_name(room, t) if t > 0 else "not fitted out yet"])


# ================================================================ placing

func _begin_placing(id: String) -> void:
	if course == null:
		_show_toast("Choose your club's course first")
		return
	var b := GameState.current.business
	_placing = id
	# a moved facility keeps its facing; a new one starts with its front to the camera (the
	# range hitting away), then turns only when you turn it
	_place_rot = float(b.placements[id]["rot"]) if b.placements.has(id) else _camera_facing(id)
	if _ghost != null:
		_ghost.queue_free()
	var flat := func(_p: Vector2) -> float: return 0.0
	_ghost = FacilityBuilder.build([{"type": id, "pos": Vector2.ZERO, "rot": 0.0, "level": maxi(b.level(id), 1), "name": course.course_name}], flat, false)
	_ghost.visible = false
	add_child(_ghost)
	_rebuild_facilities()
	_hint.text = "Placing the %s · hover open rough, click to set · Q / E turn it · Esc cancels" % _facility_name(id).to_lower()
	_hint_panel.visible = true


func _cancel_placing() -> void:
	_placing = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_mat.set_shader_parameter("brush_pos", Vector3(0, -10000, 0))
	_hint_panel.visible = false
	_rebuild_facilities()


## Where the facility being placed would stand, and whether it may (ring green / red).
func _update_placing() -> void:
	if _placing == "" or _ghost == null:
		return
	var over_ui := get_viewport().gui_get_hovered_control() != null
	_ghost.visible = _cursor_valid and not over_ui
	if not _ghost.visible:
		_mat.set_shader_parameter("brush_pos", Vector3(0, -10000, 0))
		return
	var p := Vector2(_cursor.x, _cursor.z)
	var problem := _site_problem(p, _place_rot)
	_place_ok = problem == ""
	var level := maxi(GameState.current.business.level(_placing), 1)
	var hi := -INF
	for q in FacilityBuilder.samples(_placing, p, _place_rot, 4.0, level):
		hi = maxf(hi, course.height_at(q))
	_ghost.position = Vector3(p.x, hi, p.y)
	_ghost.rotation.y = _place_rot
	# the outline of the site it takes at its level (what it's built on), squared to its front
	var site := FacilityBuilder.site(_placing, level)
	var middle := FacilityBuilder.to_world(p, _place_rot, site.get_center().x, site.get_center().y)
	_mat.set_shader_parameter("brush_pos", Vector3(middle.x, _cursor.y, middle.y))
	_mat.set_shader_parameter("brush_radius", 1.0)
	_mat.set_shader_parameter("brush_hardness", 1.0)
	_mat.set_shader_parameter("brush_square", true)
	_mat.set_shader_parameter("brush_dir", Vector2(-sin(_place_rot), -cos(_place_rot)))
	_mat.set_shader_parameter("brush_box", site.size * 0.5)
	_mat.set_shader_parameter("brush_color", Color(UITheme.GAIN if _place_ok else UITheme.LOSS, 0.95))
	_hint.text = ("Placing the %s · click to set · Q / E turn it · Esc cancels" % _facility_name(_placing).to_lower()) if _place_ok else problem


func _site_problem(p: Vector2, rot: float) -> String:
	return FacilityBuilder.site_problem(course, _sited(_placing), _placing, p, rot, maxi(GameState.current.business.level(_placing), 1))


## Why placed facility `id` can't go up a level where it stands ("" if it can): its next level's
## site (FacilityBuilder.SITES) must be clear, as when it was placed.
func _upgrade_problem(id: String) -> String:
	var b := GameState.current.business
	if course == null or not b.placements.has(id):
		return ""
	var next := b.level(id) + 1
	var pl: Dictionary = b.placements[id]
	var problem := FacilityBuilder.site_problem(course, _sited(id), id, pl["pos"], float(pl["rot"]), next)
	if problem == "":
		return ""
	return "No room for the %s here: %s · move it, or what's in the way, first" % [b.level_name(id, next), problem.to_lower()]


## The club's placed facilities with their levels, so each takes only the site it's built on
## (a planned one: its first level's); all but `except`.
func _sited(except: String = "") -> Dictionary:
	var b := GameState.current.business
	var out := {}
	for id in b.placements:
		if id != except:
			out[id] = {"pos": b.placements[id]["pos"], "rot": b.placements[id]["rot"], "level": maxi(b.level(id), 1)}
	return out


## Set the facility being placed at `p` if the site allows it. Returns whether it was placed.
func _try_place_at(p: Vector2) -> bool:
	var gs := GameState.current
	var problem := _site_problem(p, _place_rot)
	if problem != "":
		_show_toast(problem)
		return false
	var id := _placing
	var moved := gs.business.placements.has(id)
	var others: Dictionary = gs.business.placements.duplicate()
	others.erase(id)
	var warning := FacilityBuilder.range_warning(course, others, p, _place_rot) if id == "driving_range" else ""
	_placing = ""
	gs.place_facility(id, p, _place_rot)
	_clear_trees_under_facilities()
	_cancel_placing()
	if id == "clubhouse":
		_auto_park()
	if warning != "":
		_show_toast("Heads up: " + warning.to_lower(), 4.0)
	else:
		_show_toast("%s the %s%s" % ["Moved" if moved else "Placed", _facility_name(id).to_lower(), "" if gs.business.level(id) > 0 else " · now build it"])
	return true


func _rotate(deg: float) -> void:
	_place_rot = wrapf(_place_rot + deg_to_rad(deg), -PI, PI)


## Facing that shows a new facility's front to the camera (a driving range hits away from it),
## to the nearest ROTATE_DEG.
func _camera_facing(id: String) -> float:
	var back := camera.global_transform.basis.z
	var rot := atan2(-back.x, -back.z) + (PI if id == "driving_range" else 0.0)
	var step := deg_to_rad(ROTATE_DEG)
	return wrapf(roundf(rot / step) * step, -PI, PI)


## Turn a placed facility where it stands, if it still fits there.
func _turn_placed(id: String, deg: float) -> void:
	var gs := GameState.current
	var pl: Dictionary = gs.business.placements.get(id, {})
	if pl.is_empty():
		return
	var rot := wrapf(float(pl["rot"]) + deg_to_rad(deg), -PI, PI)
	var others: Dictionary = gs.business.placements.duplicate()
	others.erase(id)
	var problem := FacilityBuilder.site_problem(course, _sited(id), id, pl["pos"], rot, maxi(gs.business.level(id), 1))
	if problem != "":
		_show_toast("Can't turn it there: " + problem.to_lower())
		return
	gs.place_facility(id, pl["pos"], rot)
	_clear_trees_under_facilities()
	var warning := FacilityBuilder.range_warning(course, others, pl["pos"], rot) if id == "driving_range" else ""
	if warning != "":
		_show_toast("Heads up: " + warning.to_lower(), 4.0)


# ================================================================ input + frame

func _unhandled_input(event: InputEvent) -> void:
	if camera.handle_input(event, _cursor if _cursor_valid else null):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if _placing != "" and k.keycode == KEY_ESCAPE:
			_cancel_placing()
		elif _placing != "" and k.keycode == KEY_R:
			_rotate(-ROTATE_DEG if k.shift_pressed else ROTATE_DEG)
		elif _placing != "" and k.keycode in [KEY_Q, KEY_E]:
			_rotate(ROTATE_DEG if k.keycode == KEY_Q else -ROTATE_DEG)
		elif k.keycode == KEY_H:
			_set_side_open(not _side_open)
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_HOME:
			camera.top_view()
		elif k.keycode == KEY_V and _placing == "":
			_set_view_mode((_view_mode + 1) % VIEWS.size())
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _cursor_valid:
			if _placing != "":
				_try_place_at(Vector2(_cursor.x, _cursor.z))
			else:
				_click_course(_cursor)


func _exit_tree() -> void:
	if is_loaded and GameState.current != null:
		GameState.current.end_manager_simulation()


func set_simulation_speed(speed: float) -> void:
	if not SIM_SPEEDS.has(speed): return
	simulation_speed = speed
	_effective_speed = speed
	_simulation_remainder = 0.0
	if _life != null: _life.set_animation_speed(speed)
	if _speed_option != null: _speed_option.select(SIM_SPEEDS.find(speed))


func set_traffic_mode(mode: String) -> void:
	if not TRAFFIC_MODES.has(mode): return
	GameState.current.business.traffic_mode = mode
	if _life != null: _life._spawn_wait = 0.0
	if _traffic_option != null: _traffic_option.select(TRAFFIC_MODES.find(mode))
	GameState.current.save()
	_on_tick()


## Bound both the stride and work per rendered frame. Busy fast-forward slows down
## gracefully instead of skipping collision checks or jumping vehicles through people.
func _advance_simulation(delta: float) -> float:
	if _life == null or _life.course == null or simulation_speed <= 0.0: return 0.0
	_simulation_remainder += minf(delta, 0.25) * simulation_speed
	var start := Time.get_ticks_usec()
	var advanced := 0.0
	var steps := 0
	while _simulation_remainder + 0.000001 >= SIM_STEP and steps < 12:
		_life._process(SIM_STEP)
		_simulation_remainder -= SIM_STEP
		advanced += SIM_STEP
		steps += 1
		if Time.get_ticks_usec() - start >= 10000: break
	var limited := _simulation_remainder >= SIM_STEP
	if limited: _simulation_remainder = fmod(_simulation_remainder, SIM_STEP)
	var actual := minf(simulation_speed, advanced / maxf(delta, 0.001)) if limited else simulation_speed
	_effective_speed = lerpf(_effective_speed, actual, 0.15)
	_life.set_animation_speed(_effective_speed)
	GameState.current.advance_manager_simulation(advanced)
	return advanced


func _process(delta: float) -> void:
	if is_loaded:
		_advance_simulation(delta)
		if _clock != null and GameState.current.business.owned:
			_clock.text = GameState.current.business.clock_text()
	_stats_wait -= delta
	if _sim_stats != null and _stats_wait <= 0.0:
		_stats_wait = 0.5
		var count := _life.golfer_count() if _life != null else 0
		_sim_stats.text = "%d FPS | %d golfers%s" % [Engine.get_frames_per_second(), count,
			" | %.1fx actual" % _effective_speed if simulation_speed > 0.0 and _effective_speed < simulation_speed * 0.85 else ""]
	if course != null:
		var mp := get_viewport().get_mouse_position()
		if _cursor_dirty or mp != _cursor_mouse or camera.global_transform != _cursor_camera:
			_cursor_dirty = false
			_cursor_mouse = mp
			_cursor_camera = camera.global_transform
			var hit: Variant = _raycast(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
			_cursor_valid = hit != null
			if _cursor_valid: _cursor = hit
		_update_placing()
	if _clubs_todo:
		var house := _facility_node("clubhouse")
		_clubs_todo = house != null and not FacilityBuilder.fill_clubs(house, 1)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)


## Ray march against the course's height field; the hit Vector3 or null.
func _raycast(from: Vector3, dir: Vector3) -> Variant:
	var b := course.bounds().grow(-0.5)
	var t := 0.0
	var prev_t := 0.0
	while t < 5000.0:
		var p := from + dir * t
		if b.has_point(Vector2(p.x, p.z)) and p.y <= course.height_at(Vector2(p.x, p.z)):
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


func _on_changed() -> void:
	var b := GameState.current.business
	if (b.course_path if b.owned and b.has_course() else "") != _loaded_path:
		_load_course()
	_rebuild_facilities()
	_wake_life()
	_refresh()


# ================================================================ UI frame

func _set_side_open(open: bool) -> void:
	_side_open = open
	if _side_wrap == null or _side_toggle == null: return
	_side_wrap.visible = open
	_side_toggle.text = "‹ Hide panel" if open else "› Show panel"
	_side_toggle.tooltip_text = "Hide the club panel (H)" if open else "Show the club panel (H)"
	_side_toggle.position.x = 14 + SIDE_W + 6 if open else 14
	_side_toggle.size = Vector2(126, 38)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# top bar: back, mode + club name, clock, status, wallet
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.glass(14, 8))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 12
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	top.add_child(bar)
	MenuKit.button(bar, "‹  Menu", "ghost", 14).pressed.connect(func() -> void: get_tree().change_scene_to_file(GameLaunch.MENU_SCENE))
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 0)
	bar.add_child(title_col)
	UITheme.eyebrow(title_col, "Course Manager", UITheme.GOLD)
	_title = UITheme.label(title_col, "", 19, UITheme.TEXT, 700)
	_status = MenuKit.button(bar, "CLOSED", "ghost", 11)
	_status.tooltip_text = "Open or close the course to new arrivals. Groups already playing finish their rounds."
	_status.pressed.connect(func() -> void:
		var opening := not bool(GameState.current.business.rates()["open"])
		_result(GameState.current.set_course_open(opening), "Course open — visitors are arriving" if opening else "Course closed — existing groups will finish"))
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clock = UITheme.label(bar, "", 14, UITheme.DIM, 600)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)
	var wl := UITheme.eyebrow(bar, "Wallet")
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wallet = UITheme.label(bar, "", 21, UITheme.GOLD, 700)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if AdminAccess.is_admin():
		# testing: a full wallet (the real balance comes back when it's off)
		var money := MenuKit.button(bar, "∞ $", "tool", 13, UITheme.GOLD)
		money.tooltip_text = "Unlimited money for testing (admin). Your real balance comes back when you turn it off."
		money.set_pressed_no_signal(GameState.current.unlimited_money)
		money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		money.pressed.connect(func() -> void:
			var gs := GameState.current
			gs.set_unlimited_money(not gs.unlimited_money)
			money.set_pressed_no_signal(gs.unlimited_money)
			_show_toast("Unlimited money on" if gs.unlimited_money else "Unlimited money off: your real balance is back"))
	# side panel: tabs over a scrolling page
	var side_wrap := MarginContainer.new()
	_side_wrap = side_wrap
	side_wrap.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side_wrap.offset_left = 14
	side_wrap.offset_top = 84
	side_wrap.offset_bottom = -14
	side_wrap.custom_minimum_size = Vector2(SIDE_W, 0)
	root.add_child(side_wrap)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.glass(14, 12))
	side_wrap.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	_tabs_row = HBoxContainer.new()
	_tabs_row.add_theme_constant_override("separation", 4)
	pv.add_child(_tabs_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 10)
	scroll.add_child(_side)
	_side_toggle = MenuKit.button(root, "‹ Hide panel", "ghost", 13)
	_side_toggle.name = "ToggleClubPanel"
	_side_toggle.offset_top = 84
	_side_toggle.pressed.connect(func() -> void: _set_side_open(not _side_open))
	_set_side_open(_side_open)
	# placing hint (bottom centre) and toast
	_hint_panel = PanelContainer.new()
	_hint_panel.add_theme_stylebox_override("panel", UITheme.glass(18, 10))
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.offset_bottom = -14
	_hint_panel.visible = false
	root.add_child(_hint_panel)
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 10)
	_hint_panel.add_child(hint_row)
	_hint = UITheme.label(hint_row, "", 13, UITheme.TEXT, 600)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button(hint_row, "‹ Turn", func() -> void: _rotate(ROTATE_DEG))
	_button(hint_row, "Turn ›", func() -> void: _rotate(-ROTATE_DEG))
	# the cutaway: whole building / roof off / walls down (V cycles)
	var views := PanelContainer.new()
	views.add_theme_stylebox_override("panel", UITheme.glass(10, 8))
	views.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	views.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	views.grow_vertical = Control.GROW_DIRECTION_BEGIN
	views.offset_right = -14
	views.offset_bottom = -14
	root.add_child(views)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 4)
	views.add_child(vrow)
	UITheme.eyebrow(vrow, "View  V").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for v in VIEWS:
		var mode: int = v[0]
		var vb := MenuKit.button(vrow, v[1], "tool", 13, UITheme.GOLD)
		vb.set_pressed_no_signal(mode == _view_mode)
		vb.pressed.connect(func() -> void: _set_view_mode(mode))
		_view_buttons.append(vb)
	_build_simulation_controls(root)
	_toast = UITheme.label(root, "", 15, UITheme.TEXT, 600, 100, 0, true)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_bottom = -78
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0


func _build_simulation_controls(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "SimulationControls"
	panel.add_theme_stylebox_override("panel", UITheme.glass(12, 10))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -14
	panel.offset_bottom = -70
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	UITheme.label(row, "Speed", 13, UITheme.TEXT).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed_option = OptionButton.new()
	_speed_option.name = "SimulationSpeed"
	_speed_option.focus_mode = Control.FOCUS_NONE
	for title in ["Pause", "1x", "2x", "4x", "8x"]: _speed_option.add_item(title)
	_speed_option.select(1)
	_speed_option.tooltip_text = "Speed up people, carts, the club clock and earnings together. Camera controls keep their normal speed."
	row.add_child(_speed_option)
	_speed_option.item_selected.connect(func(index: int) -> void: set_simulation_speed(SIM_SPEEDS[index]))
	UITheme.label(row, "Traffic", 13, UITheme.TEXT).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_traffic_option = OptionButton.new()
	_traffic_option.name = "TrafficMode"
	_traffic_option.focus_mode = Control.FOCUS_NONE
	for title in ["Normal", "Quiet", "Rush hour", "Daily cycle"]: _traffic_option.add_item(title)
	_traffic_option.select(maxi(TRAFFIC_MODES.find(GameState.current.business.traffic_mode), 0))
	_traffic_option.tooltip_text = "Daily cycle: morning and afternoon rushes, a quiet lunch period and a quieter evening. Existing visitors finish their visits."
	row.add_child(_traffic_option)
	_traffic_option.item_selected.connect(func(index: int) -> void: set_traffic_mode(TRAFFIC_MODES[index]))
	_sim_stats = UITheme.label(column, "", 12, UITheme.DIM)
	_sim_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _show_toast(text: String, seconds: float = 2.6) -> void:
	_toast.text = text
	_toast_t = seconds
	_toast.modulate.a = 1.0


func _refresh() -> void:
	var gs := GameState.current
	var b := gs.business
	_title.text = (b.course_name if b.has_course() else "No course chosen") if b.owned else "Not yet a course owner"
	for c in _tabs_row.get_children():
		c.queue_free()
	for c in _side.get_children():
		c.queue_free()
	_live.clear()
	if not b.owned:
		_status.visible = false
		_clock.text = ""
		_build_locked(_side)
		_on_tick()
		return
	_status.visible = true
	for t in TABS:
		var id: String = t[0]
		var tb := MenuKit.button(_tabs_row, t[1], "tool", 13, UITheme.GOLD)
		tb.set_pressed_no_signal(_tab == id)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(func() -> void: _tab = id; _refresh())
	match _tab:
		"club": _build_club(_side)
		"facilities": _build_facilities(_side)
		"rooms": _build_rooms(_side)
		"staff": _build_staff(_side)
		"books": _build_books(_side)
	_on_tick()


## Live numbers every business tick, without rebuilding the page.
func _on_tick() -> void:
	var gs := GameState.current
	var b := gs.business
	_wallet.text = "$%d" % gs.cash
	if not b.owned:
		return
	var r := b.rates()
	_park_cars(r)
	_status.text = "OPEN" if r["open"] else "CLOSED"
	var sb := UITheme.box(UITheme.GO if r["open"] else UITheme.LOSS.darkened(0.2), Color(0, 0, 0, 0), 0, 6, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_status.add_theme_stylebox_override("normal", sb)
	_status.add_theme_stylebox_override("hover", sb)
	_status.add_theme_stylebox_override("pressed", sb)
	_clock.text = b.clock_text()
	if _traffic_option != null: _traffic_option.select(maxi(TRAFFIC_MODES.find(b.traffic_mode), 0))
	if not is_instance_valid(_live.get("net")):
		return
	(_live["reason"] as Label).text = str(r["reason"])
	(_live["reason"] as Label).visible = str(r["reason"]) != ""
	var stars := int(round(float(r["stars"])))
	(_live["stars"] as Label).text = "★".repeat(stars) + "☆".repeat(5 - stars) + "  %.1f" % float(r["stars"])
	(_live["turf"] as Label).text = "Turf %d%% · staff can hold %d%%%s" % [int(round(b.condition * 100.0)), int(round(b.condition_target() * 100.0)),
		" · parking full: upgrade the lot" if r["open"] and float(r["parking_cap"]) < float(r["course_capacity"]) and float(r["golfers"]) >= float(r["parking_cap"]) - 0.01 else ""]
	(_live["golfers"] as Label).text = "%.1f" % (float(r["golfers"]) + float(r["range_golfers"]) + float(r["practice_golfers"]))
	(_live["revenue"] as Label).text = _money(r["revenue"])
	(_live["costs"] as Label).text = _money(r["costs"])
	var net_l: Label = _live["net"]
	net_l.text = _money(r["net"])
	net_l.add_theme_color_override("font_color", UITheme.GAIN if float(r["net"]) >= 0.0 else UITheme.LOSS)
	var t: Dictionary = b.today
	(_live["today"] as Label).text = "Today: %d visitors · takings %s · costs %s · profit %s" % [int(t["visitors"]), _money(t["revenue"]), _money(t["costs"]), _money(float(t["revenue"]) - float(t["costs"]))]


# ================================================================ pages

func _card(parent: Node, title: String = "") -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.08), 1, 10, 10))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	if title != "":
		UITheme.eyebrow(v, title, UITheme.GOLD)
	return v


func _text(parent: Node, text: String, size: int = 13, color: Color = UITheme.DIM) -> Label:
	var l := UITheme.label(parent, text, size, color, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIDE_W - 60, 0)
	return l


func _row(parent: Node, gap: int = 8) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", gap)
	parent.add_child(r)
	return r


func _spacer(parent: Node) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)


func _button(parent: Node, text: String, cb: Callable, style: String = "ghost", enabled: bool = true) -> Button:
	var b := MenuKit.button(parent, text, style, 13)
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


static func _money(v: float) -> String:
	return ("-" if v < -0.005 else "") + "$%.2f" % absf(v)


static func _duration(secs: int) -> String:
	if secs >= 86400:
		return "%d day%s" % [secs / 86400, "" if secs < 172800 else "s"]
	if secs >= 3600:
		return "%d h %d min" % [secs / 3600, (secs % 3600) / 60]
	return "%d min" % maxi(secs / 60, 1)


func _facility_name(id: String) -> String:
	return str(EconomyConfig.facility(id).get("name", id))


func _room_name(id: String) -> String:
	return str(EconomyConfig.room(id).get("name", id))


func _result(res: Dictionary, ok_text: String) -> void:
	_show_toast(ok_text if res["ok"] else str(res["error"]))


func _build_locked(parent: Node) -> void:
	var gs := GameState.current
	var st := gs.manager_status()
	var v := _card(parent, "Golf course ownership")
	UITheme.label(v, "Own your own golf club", 24, Color.WHITE, 700)
	_text(v, "Buy a course deed and run one of your Course Studio courses as a business. Place and build a clubhouse, a driving range and a cart barn, grow the clubhouse from a cottage to a grand shingle-style club and fit out its pro shop, restaurant, ballroom and more, hire staff and set the green fee. The club earns in real time, even while you're out playing, into the same wallet you buy clubs with.")
	_text(v, "The deed is only sold to proven golfers. You'll need:", 13, UITheme.TEXT)
	for req in [[st["store_ok"], "Unlock %s by playing your way up the stores" % st["store_name"]], [st["cash_ok"], "$%d for the deed (you have $%d)" % [int(st["price"]), gs.cash]]]:
		var r := _row(v, 10)
		UITheme.pill(r, "DONE" if req[0] else "TO DO", UITheme.GO if req[0] else Color(1, 1, 1, 0.12), Color.WHITE, 10)
		_text(r, req[1], 13, UITheme.TEXT if not req[0] else UITheme.DIM).custom_minimum_size = Vector2(SIDE_W - 140, 0)
	_button(v, "Buy the deed  ·  $%d" % int(st["price"]), func() -> void:
		_result(gs.buy_course(), "You own a golf club. Now choose which of your courses it runs on."), "primary", bool(st["can_buy"]))


func _expand_land() -> void:
	if course == null or _loaded_path == "":
		return
	# Work on a fresh copy; a failed save must not change the live course.
	var expanded := PaintedCourse.load_file(_loaded_path)
	if expanded == null or not expanded.expand_land():
		_show_toast("The course cannot be expanded further")
		return
	var err := expanded.save(_loaded_path)
	if err != OK:
		_show_toast("Could not save the expanded course")
		return
	_load_course()
	_refresh()
	_show_toast("Land expanded to %d × %d m. Your holes and facilities stay in place." % [course.size.x, course.size.y])


func _build_club(parent: Node) -> void:
	var gs := GameState.current
	var b := gs.business
	var v := _card(parent, "Your club")
	_live["reason"] = UITheme.label(v, "", 13, AMBER, 600)
	var line := _row(v, 14)
	_live["stars"] = UITheme.label(line, "", 15, UITheme.GOLD, 600)
	_live["turf"] = UITheme.label(line, "", 13, UITheme.DIM, 500)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for k in [["golfers", "Golfers / hr"], ["revenue", "Takings / hr"], ["costs", "Costs / hr"], ["net", "Profit / hr"]]:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 0)
		grid.add_child(c)
		UITheme.eyebrow(c, k[1])
		_live[k[0]] = UITheme.label(c, "", 21, Color.WHITE, 700)
	_live["today"] = _text(v, "")
	var per_hour := float(EconomyConfig.manager_cfg().get("real_seconds_per_hour", 240))
	_text(v, "At 1x, one business hour = %d real minutes. The speed control advances activity and the books together; Pause stops both while you are here." % int(round(per_hour / 60.0)), 11)
	# the course
	var cv := _card(parent, "The course")
	_text(cv, "Your club runs on one of your Course Studio courses (at least %d holes). Each course saves its own buildings, upgrade levels, rooms and hired staff. A new course starts fresh; returning restores its progress." % int(EconomyConfig.manager_cfg().get("min_holes", 3)))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", 14)
	cv.add_child(opt)
	opt.add_item("Choose a course…")
	opt.set_item_metadata(0, "")
	var sel := 0
	for e in PaintedCourse.list_saved():
		opt.add_item("%s  ·  %d hole%s" % [e["name"], e["holes"], "" if int(e["holes"]) == 1 else "s"])
		opt.set_item_metadata(opt.item_count - 1, str(e["path"]))
		if str(e["path"]) == b.course_path:
			sel = opt.item_count - 1
	opt.select(sel)
	opt.item_selected.connect(func(i: int) -> void:
		var p := str(opt.get_item_metadata(i))
		if p != "" and p != b.course_path:
			_result(gs.set_business_course(p), "Your club now runs on this course")
			_load_course())
	var actions := _row(cv)
	var has := b.has_course()
	_button(actions, "Play it", func() -> void:
		GameLaunch.play_custom(b.course_path, false, GameLaunch.MANAGER_SCENE)
		get_tree().change_scene_to_file(GameLaunch.COURSE_SCENE), "ghost", has)
	_button(actions, "Edit in Course Studio", func() -> void:
		GameLaunch.custom_course = b.course_path
		get_tree().change_scene_to_file(GameLaunch.STUDIO_SCENE), "ghost", has)
	if course != null:
		_text(cv, "Land: %d × %d m. Expand to add 200 m of rough on each edge." % [course.size.x, course.size.y])
		_button(cv, "Expand land", _expand_land, "ghost", maxi(course.size.x, course.size.y) < PaintedCourse.MAX_CANVAS_CELLS)
	# green fee
	var fv := _card(parent, "Green fee")
	var r0 := b.rates()
	var fr := _row(fv, 10)
	_button(fr, "-", func() -> void: gs.set_green_fee(b.green_fee - 1), "ghost", b.green_fee > b.clamp_fee(-999))
	var fee := UITheme.label(fr, "$%d" % b.green_fee, 24, UITheme.GOLD, 700)
	fee.custom_minimum_size = Vector2(56, 0)
	fee.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(fr, "+", func() -> void: gs.set_green_fee(b.green_fee + 1), "ghost", b.green_fee < b.clamp_fee(999))
	var pf := clampf(1.5 - 0.5 * b.green_fee / maxf(float(r0["fair_fee"]), 0.01), 0.05, 1.3)
	_text(fv, "Fair price for your club right now is about %s; at this fee demand runs at %d%%." % [_money(r0["fair_fee"]), int(round(pf * 100.0))])
	var progress := _card(parent, "Manager progress")
	_text(progress, "Start the business again or remove its ownership. Your wallet, golf equipment, player progress and saved course maps stay intact. Purchases are not refunded.")
	_button(progress, "Reset business…", func() -> void: _confirm_manager_reset(true))
	_button(progress, "Delete manager progress…", func() -> void: _confirm_manager_reset(false))


func _confirm_manager_reset(keep_deed: bool) -> void:
	_cancel_placing()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Reset business?" if keep_deed else "Delete manager progress?"
	dialog.dialog_text = "Clear facilities, room upgrades, staff, fees and business records. " + ("Keep your deed and selected course." if keep_deed else "Remove the deed and selected course from manager mode; you will need to buy a deed again.") + "\nYour wallet, equipment, player progress and course maps are kept. No purchases are refunded. This cannot be undone."
	dialog.ok_button_text = "Reset business" if keep_deed else "Delete manager progress"
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get_label().custom_minimum_size.x = 480
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		GameState.current.reset_manager_progress(keep_deed)
		_load_course()
		_refresh()
		_show_toast("Business reset" if keep_deed else "Manager progress deleted")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(540, 240))


func _build_facilities(parent: Node) -> void:
	var gs := GameState.current
	var b := gs.business
	if not b.has_course():
		_text(parent, "Choose your club's course on the Club tab first.", 14, AMBER)
		return
	for f in EconomyConfig.manager_cfg().get("facilities", []):
		var id := str(f["id"])
		var lv := b.level(id)
		var placed := b.placements.has(id)
		var v := _card(parent)
		var head := _row(v, 8)
		UITheme.label(head, str(f.get("name", id)), 16, UITheme.TEXT, 700)
		UITheme.pill(head, ("LEVEL %d / %d" % [lv, b.max_level(id)]) if lv > 0 else ("PLACED" if placed else "NOT PLACED"), UITheme.GO if lv > 0 else (UITheme.GOLD.darkened(0.4) if placed else Color(1, 1, 1, 0.12)), Color.WHITE, 10)
		if lv > 0:
			UITheme.label(head, b.level_name(id, lv), 13, UITheme.GOLD, 600)
		_text(v, str(f.get("blurb", "")), 12)
		var note := b.facility_note(id)
		if lv > 0 and note != "":
			_text(v, note, 12, AMBER)
		var levels: Array = f.get("levels", [])
		var show := mini(lv, levels.size()) if lv > 0 else 1
		_text(v, ("Now: " if lv > 0 else "%s: " % b.level_name(id, 1)) + _effects(levels[show - 1]), 12, UITheme.TEXT)
		if lv > 0 and lv < levels.size():
			_text(v, "Next, %s: %s" % [b.level_name(id, lv + 1), _effects(levels[lv])], 12, UITheme.DIM)
		if id == "clubhouse" and lv < levels.size():
			var opens: Array = []
			for rm in EconomyConfig.manager_cfg().get("rooms", []):
				if int(rm.get("min_level", 1)) == lv + 1:
					opens.append(str(rm.get("name", "")).to_lower())
			if not opens.is_empty():
				_text(v, "Level %d makes room for: %s" % [lv + 1, ", ".join(opens)], 12, UITheme.DIM)
		var actions := _row(v, 6)
		_button(actions, "Move" if placed else "Place", func() -> void: _begin_placing(id), "ghost" if placed else "primary")
		var cost := b.next_cost(id)
		if cost >= 0:
			var why := b.can_build(id)
			_button(actions, ("Build" if lv == 0 else "Upgrade") + "  ·  $%d" % cost, func() -> void:
				var cramped := _upgrade_problem(id)
				if cramped != "":
					_show_toast(cramped, 4.0)
					return
				_result(gs.build_facility(id), ("%s built" % f.get("name", id)) if lv == 0 else ("%s upgraded: %s" % [f.get("name", id), b.level_name(id, lv + 1)])), "primary" if placed else "ghost", why == "" and gs.cash >= cost)
		else:
			UITheme.label(actions, "Top level", 12, UITheme.DIM, 600)
		if placed:
			var turn := _row(v, 6)
			UITheme.label(turn, "Facing %d°" % posmod(roundi(rad_to_deg(float(b.placements[id]["rot"]))), 360), 12, UITheme.DIM, 600)
			_button(turn, "‹ Turn", func() -> void: _turn_placed(id, ROTATE_DEG))
			_button(turn, "Turn ›", func() -> void: _turn_placed(id, -ROTATE_DEG))
			_spacer(actions)
			_button(actions, "Remove", func() -> void:
				gs.unplace_facility(id)
				_show_toast("Took the %s off the course%s" % [_facility_name(id).to_lower(), " (its level is kept)" if lv > 0 else ""]))


static func _effects(l: Dictionary) -> String:
	var bits: Array = []
	if l.has("spend"):
		bits.append("%s per golfer" % _money(l["spend"]))
	if l.has("events"):
		bits.append("events bring in up to %s/hr" % _money(l["events"]))
	if l.has("members"):
		bits.append("memberships up to %s/hr" % _money(l["members"]))
	if l.has("lessons"):
		bits.append("lessons up to %s/hr" % _money(l["lessons"]))
	if l.has("capacity"):
		bits.append("+%d%% tee times" % int(round(float(l["capacity"]) * 100.0)))
	if l.has("spaces"):
		bits.append("%d parking spaces (up to %.1f golfers/hr)" % [int(l["spaces"]), float(l["spaces"]) * float(EconomyConfig.manager_cfg().get("golfers_per_space_hour", 0.35))])
	if l.has("range_golfers"):
		bits.append("%.1f range golfers/hr at %s a bucket" % [float(l["range_golfers"]), _money(l["bucket"])])
	if l.has("practice_golfers"):
		bits.append("%.1f practising golfers/hr at %s each" % [float(l["practice_golfers"]), _money(l["practice_fee"])])
	if l.has("cart_share"):
		bits.append("%d%% ride at %s" % [int(round(float(l["cart_share"]) * 100.0)), _money(l["cart_fee"])])
	if l.has("fair_fee"):
		bits.append("+%s fair green fee" % _money(l["fair_fee"]))
	if l.has("appeal"):
		bits.append("+%d appeal" % int(round(float(l["appeal"]) * 100.0)))
	bits.append("upkeep %s/hr" % _money(l.get("upkeep", 0.0)))
	return ", ".join(bits)


func _build_rooms(parent: Node) -> void:
	var gs := GameState.current
	var b := gs.business
	if b.level("clubhouse") == 0:
		_text(parent, "Build the clubhouse on the Facilities tab first: its rooms are fitted out here.", 14, AMBER)
		return
	_text(parent, "Lift the roof off (V) and click a room to open it here. A bigger clubhouse makes room for more.", 12)
	var rooms: Array = EconomyConfig.manager_cfg().get("rooms", []).duplicate()
	rooms.sort_custom(func(x, y) -> bool: return str(x["id"]) == _room_sel and str(y["id"]) != _room_sel)
	for rm in rooms:
		var id := str(rm["id"])
		var t := b.room_tier(id)
		var open := b.room_open(id)
		var v := _card(parent)
		if id == _room_sel:
			(v.get_parent() as PanelContainer).add_theme_stylebox_override("panel", UITheme.box(Color(1, 0.85, 0.4, 0.07), UITheme.GOLD, 1, 10, 10))
		var head := _row(v, 8)
		UITheme.label(head, str(rm.get("name", id)), 16, UITheme.TEXT if open else UITheme.DIM, 700)
		var tiers: Array = rm.get("tiers", [])
		UITheme.pill(head, ("TIER %d / %d" % [t, tiers.size()]) if t > 0 else ("EMPTY" if open else "LOCKED"), UITheme.GO if t > 0 else Color(1, 1, 1, 0.12), Color.WHITE, 10)
		if t > 0:
			UITheme.label(head, b.tier_name(id, t), 13, UITheme.GOLD, 600)
		_text(v, str(rm.get("blurb", "")), 12)
		if not open:
			_text(v, "Opens with the %s clubhouse (level %d)." % [b.level_name("clubhouse", int(rm.get("min_level", 1))), int(rm.get("min_level", 1))], 12, AMBER)
			continue
		var note := b.room_note(id)
		if t > 0 and note != "":
			_text(v, note, 12, AMBER)
		if t > 0:
			_text(v, "Now: " + _effects(tiers[t - 1]), 12, UITheme.TEXT)
		if t < tiers.size():
			_text(v, "%s %s: %s" % ["Next," if t > 0 else "Fit out as", b.tier_name(id, t + 1), _effects(tiers[t])], 12, UITheme.DIM)
		var roles: Array = []
		for k in ["staff", "crew"]:
			for role in (rm[k] if rm.get(k) is Array else [rm.get(k, "")]):
				if str(role) != "":
					roles.append(("needs " if k == "staff" else "helped by ") + str(EconomyConfig.staff_role(str(role)).get("name", role)).to_lower() + "s")
		if not roles.is_empty():
			_text(v, "Staff: " + ", ".join(roles), 11)
		var actions := _row(v, 6)
		var cost := b.room_next_cost(id)
		if cost >= 0:
			_button(actions, ("Fit out" if t == 0 else "Upgrade") + "  ·  $%d" % cost, func() -> void:
				_result(gs.build_room(id), "%s: %s" % [str(rm.get("name", id)), b.tier_name(id, t + 1)]), "primary", b.can_build_room(id) == "" and gs.cash >= cost)
		else:
			UITheme.label(actions, "Top tier", 12, UITheme.DIM, 600)


func _build_staff(parent: Node) -> void:
	var gs := GameState.current
	var b := gs.business
	for s in EconomyConfig.manager_cfg().get("staff", []):
		var role := str(s["id"])
		var n := b.heads(role)
		var v := _card(parent)
		var head := _row(v, 8)
		UITheme.label(head, str(s.get("name", role)), 16, UITheme.TEXT, 700)
		UITheme.pill(head, "%d / %d" % [n, int(s.get("max", 3))], UITheme.GO if n > 0 else Color(1, 1, 1, 0.12), Color.WHITE, 10)
		_spacer(head)
		_button(head, "Let go", func() -> void: gs.let_go_staff(role), "ghost", n > 0)
		_button(head, "Hire", func() -> void:
			var res := gs.hire_staff(role)
			if not res["ok"]:
				_show_toast(str(res["error"])), "primary", b.can_hire(role) == "")
		_text(v, "%s a business hour each. %s" % [_money(float(s.get("wage", 0.0))), s.get("blurb", "")], 12)
		var where := b.workplace_note(role)
		if where != "":
			_text(v, where, 11, AMBER)


func _build_books(parent: Node) -> void:
	var b := GameState.current.business
	var v := _card(parent, "Recent days")
	if b.days.is_empty():
		_text(v, "No full business day yet: a day is %d business hours." % int(EconomyConfig.manager_cfg().get("open_hours_per_day", 12)))
	for i in range(b.days.size() - 1, -1, -1):
		var d: Dictionary = b.days[i]
		var profit := float(d["revenue"]) - float(d["costs"])
		var r := _row(v, 8)
		UITheme.label(r, "Day %d" % int(d["day"]), 14, UITheme.TEXT, 700)
		UITheme.label(r, "%d visitors" % int(d["visitors"]), 13, UITheme.DIM, 500)
		_spacer(r)
		UITheme.label(r, _money(profit), 14, UITheme.GAIN if profit >= 0.0 else UITheme.LOSS, 700)
		_text(v, "takings %s · costs %s" % [_money(d["revenue"]), _money(d["costs"])], 12)
	var lv := _card(parent, "Since you bought it")
	_text(lv, "%d visitors · takings %s · costs %s · profit %s" % [int(b.lifetime["visitors"]), _money(b.lifetime["revenue"]), _money(b.lifetime["costs"]), _money(float(b.lifetime["revenue"]) - float(b.lifetime["costs"]))], 13, UITheme.TEXT)
