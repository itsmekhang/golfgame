@tool
extends Control
## Transparent 3D HUD icon. Static mode renders once; optional wind redraws it.
const MODEL = preload("res://assets/flagpin/flagpin_low.tscn")

@export var animate_flag := false:
	set(value):
		animate_flag = value
		_refresh()
@export var flag_color := Color("ed4223"):
	set(value):
		flag_color = value
		_refresh()

var _viewport: SubViewport
var _model: Node3D
var _texture: TextureRect
var _camera: Camera3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "FlagViewport"
	_viewport.size = Vector2i(160, 256)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.gui_disable_input = true
	add_child(_viewport)
	var world := Node3D.new()
	world.name = "Studio"
	_viewport.add_child(world)
	_model = MODEL.instantiate()
	world.add_child(_model)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e8edf5")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.75
	_camera.position = Vector3(2.4, 1.75, 7)
	_camera.look_at(Vector3(0.50, 1.23, 0.0))
	_camera.current = true
	for config in [Vector3(-35, -35, 1.0), Vector3(-10, 135, 0.65)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(config.x, config.y, 0)
		light.light_energy = config.z
		light.shadow_enabled = false
		world.add_child(light)
	_texture = TextureRect.new()
	_texture.name = "RenderedFlag"
	_texture.texture = _viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture)
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_viewport) or not is_instance_valid(_model):
		return
	_model.set("animate_flag", animate_flag)
	_model.set("flag_color", flag_color)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if animate_flag else SubViewport.UPDATE_ONCE

func point_at(world_target: Vector3, game_camera: Camera3D, screen_offset: Vector2 = Vector2.ZERO) -> void:
	## Call when the game camera or target moves. Use in a normal CanvasLayer HUD.
	## Align the pole FOOT, including the image's letterboxing, with the target.
	if not is_instance_valid(_camera) or not is_instance_valid(game_camera):
		return
	visible = not game_camera.is_position_behind(world_target)
	if not visible:
		return
	var source_size := Vector2(_viewport.size)
	var fit := minf(size.x / source_size.x, size.y / source_size.y)
	var padding := (size - source_size * fit) * 0.5
	var foot := padding + _camera.unproject_position(Vector3.ZERO) * fit
	global_position = game_camera.unproject_position(world_target) + screen_offset - foot
