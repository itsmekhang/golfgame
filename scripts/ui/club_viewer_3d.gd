class_name ClubViewer3D
extends SubViewportContainer
## Interactive 3D inspector for one piece of equipment, the stage of the Clubhouse's
## full-screen Inspect view: drag to orbit (with a little inertia on release), scroll for a
## smooth zoom, double-click to glide back to the opening angle, and a gentle turntable spin
## while idle that stops the instant the player takes over. It opens with a short spin-in.
## Irons hold their rear view until dragged, keeping the cavity and back finish on display.
## set_accent() adds a rim light in the club's rarity colour that follows the camera, so the
## silhouette always carries an edge of colour against the dark studio. Built on the
## same OFGEquipmentAssets adapter (and the same drag/zoom feel) as the equipment pack's
## own demo inspection scene.
##
## Self-contained: the caller just adds this Control, sizes it, and calls show_model().
## Camera framing is computed from the loaded model's own mesh bounds, so it frames any
## club correctly regardless of its individual length or proportions.

const OFGEquipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")

var _viewport: SubViewport
var _cam: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: DirectionalLight3D  # rarity-coloured edge light, rides with the camera
var _kick_light: DirectionalLight3D  # cool white edge from the other side
var _environment: Environment
static var _equipment_studio_sky: Sky
var _light_from_camera := false
var _stage: Node3D
var _club: Node3D
var _center := Vector3.ZERO
var _radius := 0.2
var _yaw := 0.0
var _pitch := -0.22
var _zoom := 1.0
var _dragging := false
var _spin := true  # auto-turntable while idle; stops the moment the player drags
var _zoom_goal := 1.0  # scroll eases _zoom toward this
var _yaw_vel := 0.0  # radians/s left over from a drag, decays after release
var _pitch_vel := 0.0
var _home := Vector3(0.0, -0.22, 1.0)  # opening yaw, pitch, zoom (double-click returns here)
var _intro := 0.0  # seconds left of the opening spin-in

const INTRO_TIME := 0.7
const INTRO_YAW := 0.9  # radians the club turns in by
const INTRO_ZOOM := 0.3  # starts this much further out
const INERTIA_DAMP := 4.5  # 1/s
const ZOOM_EASE := 12.0  # 1/s


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	add_child(_viewport)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("ece7d6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.72, 0.66)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	_environment = env
	_viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	key.light_color = Color("fff3e0")
	key.shadow_enabled = false
	_viewport.add_child(key)
	_key_light = key
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.82, 0.87, 1.0)
	_viewport.add_child(fill)
	_fill_light = fill
	_rim_light = DirectionalLight3D.new()
	_rim_light.light_energy = 0.0
	_rim_light.light_specular = 1.6
	_viewport.add_child(_rim_light)
	_kick_light = DirectionalLight3D.new()
	_kick_light.light_energy = 0.0
	_kick_light.light_color = Color(0.86, 0.92, 1.0)
	_kick_light.light_specular = 1.2
	_viewport.add_child(_kick_light)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.001
	_cam.far = 50.0
	_viewport.add_child(_cam)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	resized.connect(_update_camera)


## Loads (or replaces) the displayed club. `allow_admin` lets the sandbox items render
## here too -- inspecting one isn't itself a gameplay action, so the caller decides
## whether the dialog is reachable at all. `start_yaw` lets the caller pick a sensible
## opening angle for other clubs (e.g. putters read better face-on). Irons open at a
## rear three-quarter angle matching their preview pictures. Returns false if the pack has no
## asset for this id, so the caller can fall back to the flat preview image.
func show_model(model_id: String, condition: float, allow_admin: bool, start_yaw: float = 0.0) -> bool:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()
	_club = OFGEquipment.create_club(model_id, condition, allow_admin)
	if _club == null:
		return false
	_stage.add_child(_club)
	# Metal finishes need something soft to reflect. Share one small studio sky
	# between metal club inspectors; this has no effect on the course renderer.
	var model_type := str(ClubCatalog.model(model_id).get("type", ""))
	var wood_or_driver := model_type in ["wood", "driver"]
	var studio_view := model_type in ["putter", "wedge", "iron_set", "driver", "wood"]
	_viewport.msaa_3d = Viewport.MSAA_4X if wood_or_driver else Viewport.MSAA_DISABLED
	_environment.sky = _get_equipment_studio_sky() if studio_view else null
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if studio_view else Environment.REFLECTION_SOURCE_BG
	_environment.ambient_light_color = Color(0.83, 0.86, 0.88) if studio_view else Color(0.74, 0.72, 0.66)
	_fit_camera()
	var rear_view := EquipmentPreview.prefers_back_view(model_id)
	# Godot keeps the GLB's authored custom properties in its "extras" dictionary.
	var presentation := _presentation_settings(_club)
	# Start woods and drivers with both the face and carbon crown visible.
	var opening_yaw := 2.45 if wood_or_driver and is_zero_approx(start_yaw) else start_yaw
	_yaw = float(presentation.get("rear_view_yaw", 0.67)) if rear_view else opening_yaw
	_pitch = float(presentation.get("rear_view_pitch", -0.42)) if rear_view else (-0.38 if wood_or_driver else -0.22)
	_light_from_camera = rear_view and presentation.has("rear_view_pitch")
	_fill_light.rotation_degrees = Vector3(-20, 150, 0)
	_zoom = 1.0
	_zoom_goal = 1.0
	_home = Vector3(_yaw, _pitch, _zoom)
	_dragging = false
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	_spin = not rear_view
	_intro = INTRO_TIME if _spin else 0.0
	_update_camera()
	return true


## Rim lighting in the club's rarity colour (plus a neutral kicker opposite), for the dark
## Inspect studio. Bright colours are toned down so a gold rim doesn't swamp the finish.
func set_accent(color: Color) -> void:
	_rim_light.light_color = color.lightened(0.2)
	_rim_light.light_energy = 2.2 / maxf(color.get_luminance() * 1.6 + 0.4, 0.6)
	_kick_light.light_energy = 0.9
	_update_camera()


static func _get_equipment_studio_sky() -> Sky:
	if _equipment_studio_sky == null:
		var material := ProceduralSkyMaterial.new()
		material.sky_top_color = Color(0.64, 0.69, 0.74)
		material.sky_horizon_color = Color(0.96, 0.97, 0.95)
		material.ground_bottom_color = Color(0.20, 0.24, 0.28)
		material.ground_horizon_color = Color(0.76, 0.79, 0.80)
		_equipment_studio_sky = Sky.new()
		_equipment_studio_sky.radiance_size = Sky.RADIANCE_SIZE_128
		_equipment_studio_sky.sky_material = material
	return _equipment_studio_sky


func _presentation_settings(node: Node) -> Dictionary:
	# Imported GLBs may add a scene wrapper above the authored club root.
	var settings: Dictionary = node.get_meta("extras", {})
	if settings.has("rear_view_pitch"):
		return settings
	for child in node.get_children():
		var found := _presentation_settings(child)
		if not found.is_empty():
			return found
	return {}


## Frames the head, not the whole club: a real club is 1m+ long and a few cm wide, so
## fitting the entire length into a square viewport just makes it look like a thin
## sliver. Every model names its head mesh(es) "..__head" (see the pack's README), so
## framing on those alone gives a chunky, product-shot-style close-up of the actual
## interesting/distinguishing part instead. Falls back to the whole model (e.g. the
## standalone headcover prop, which has no "__head" node at all) if that match is empty.
func _fit_camera() -> void:
	var aabb := _combined_aabb(_club, "__head")
	if aabb.size.length() <= 0.0001:
		aabb = _combined_aabb(_club, "")
	if aabb.size.length() <= 0.0001:
		_center = Vector3.ZERO
		_radius = 0.3
		return
	_center = aabb.position + aabb.size * 0.5
	_radius = maxf(aabb.size.length() * 0.5, 0.05)


func _combined_aabb(node: Node3D, name_suffix: String) -> AABB:
	var aabb := AABB()
	var first := true
	for m in _find_meshes(node, name_suffix):
		var box: AABB = m.global_transform * m.get_aabb()
		if bool(m.get_meta("ofg_authored_head", false)):
			# Rotated component boxes can enclose substantial empty space. Fit these
			# multi-part heads to their actual vertices so the close-up stays useful.
			var mesh_transform: Transform3D = m.global_transform
			var vertex_first := true
			for surface in m.mesh.get_surface_count():
				var vertices: PackedVector3Array = m.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var point := mesh_transform * vertex
					if vertex_first:
						box = AABB(point, Vector3.ZERO)
						vertex_first = false
					else:
						box = box.expand(point)
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	return aabb


## `name_suffix`: only match MeshInstance3D nodes whose name ends with this (empty = all).
func _find_meshes(node: Node, name_suffix: String) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (name_suffix.is_empty() or String(node.name).ends_with(name_suffix)):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c, name_suffix))
	return out


func _update_camera() -> void:
	# The spin-in eases out: the club starts turned and a little further away.
	var still := pow(clampf(_intro / INTRO_TIME, 0.0, 1.0), 3.0)
	var offset := Vector3(0, 0, 1)
	offset = Basis(Vector3.RIGHT, _pitch) * offset
	offset = Basis(Vector3.UP, _yaw - INTRO_YAW * still) * offset
	_cam.global_position = _center + offset * (_radius * 3.2)
	_cam.look_at(_center, Vector3.UP)
	# Keep the whole head inside the frame, including narrow or resized panels.
	var aspect := maxf(size.x / maxf(size.y, 1.0), 0.1)
	_cam.size = _radius * 2.5 * _zoom * (1.0 + INTRO_ZOOM * still) / minf(aspect, 1.0)
	if _light_from_camera:
		_fill_light.global_basis = _cam.global_basis
	# Edge lights shine back toward the camera from behind the club: rarity colour from the
	# upper right, a cool kicker from the left.
	_rim_light.global_basis = _cam.global_basis * Basis.from_euler(Vector3(deg_to_rad(-28.0), deg_to_rad(180.0 - 40.0), 0.0))
	_kick_light.global_basis = _cam.global_basis * Basis.from_euler(Vector3(deg_to_rad(-12.0), deg_to_rad(180.0 + 55.0), 0.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_take_over()
				if event.double_click:
					_dragging = false
					_reset_view()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_goal = maxf(0.35, _zoom_goal * 0.88)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_goal = minf(3.2, _zoom_goal * 1.12)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var dyaw: float = -event.relative.x * 0.008
		var dpitch: float = -event.relative.y * 0.007
		_yaw += dyaw
		_pitch = clampf(_pitch + dpitch, -1.3, 1.3)
		# Remember how fast it was moving so a flick keeps turning after release.
		var dt := maxf(get_process_delta_time(), 1.0 / 240.0)
		_yaw_vel = lerpf(_yaw_vel, dyaw / dt, 0.5)
		_pitch_vel = lerpf(_pitch_vel, dpitch / dt, 0.5)
		_update_camera()
		accept_event()


## The player grabbed the club: stop the turntable and fold any unfinished spin-in into the
## real angle so nothing jumps.
func _take_over() -> void:
	if _intro > 0.0:
		var still := pow(_intro / INTRO_TIME, 3.0)
		_yaw -= INTRO_YAW * still
		_zoom *= 1.0 + INTRO_ZOOM * still
		_zoom_goal = _zoom
		_intro = 0.0
	_spin = false
	_yaw_vel = 0.0
	_pitch_vel = 0.0


## Glide back to the opening angle and zoom (the shortest way round).
func _reset_view() -> void:
	var from := Vector3(_yaw, _pitch, _zoom)
	var to := _home
	to.x = from.x + wrapf(_home.x - from.x, -PI, PI)
	_zoom_goal = to.z
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: Vector3):
		_yaw = v.x
		_pitch = v.y
		_zoom = v.z
		_update_camera(), from, to, 0.45)


func _process(delta: float) -> void:
	if _club == null:
		return
	var moved := false
	if _intro > 0.0:
		# A script switching the turntable off has taken the camera: skip the spin-in.
		_intro = maxf(_intro - delta, 0.0) if _spin else 0.0
		moved = true
	if _spin and not _dragging:
		_yaw += delta * 0.25
		moved = true
	if not _dragging and (absf(_yaw_vel) > 0.01 or absf(_pitch_vel) > 0.01):
		_yaw += _yaw_vel * delta
		_pitch = clampf(_pitch + _pitch_vel * delta, -1.3, 1.3)
		var damp := exp(-INERTIA_DAMP * delta)
		_yaw_vel *= damp
		_pitch_vel *= damp
		moved = true
	if not is_equal_approx(_zoom, _zoom_goal):
		_zoom = lerpf(_zoom, _zoom_goal, 1.0 - exp(-ZOOM_EASE * delta))
		if absf(_zoom - _zoom_goal) < 0.002:
			_zoom = _zoom_goal
		moved = true
	if moved:
		_update_camera()
