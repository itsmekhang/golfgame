extends Node3D

@export var catalog_mode: bool = false
const CAMERA_SCRIPT = preload("res://nature_pack/scripts/fly_camera.gd")
var _assets: Dictionary = {}

func _ready() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nature_pack/catalog.json"))
    for record in data["assets"]:
        _assets[record["id"]] = record
    _lighting()
    if catalog_mode:
        _catalog(data["assets"])
    else:
        _showcase()
    _camera()
    _instructions()

func _spawn(id: String, where: Vector3, uniform_scale: float = 1.0, angle: float = 0.0) -> Node3D:
    var path: String = "res://nature_pack/" + String(_assets[id]["scene"])
    var scene := load(path) as PackedScene
    if scene == null:
        push_error("Could not load: " + path)
        return null
    var instance := scene.instantiate() as Node3D
    instance.position = where
    instance.scale = Vector3.ONE * uniform_scale
    instance.rotation.y = angle
    add_child(instance)
    return instance

func _showcase() -> void:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nature_pack/showcase_layout.json"))
    _ground(Vector3(0.0, -0.08, 0.0), Vector2(46.0, 32.0), Color("547A3D"))
    for item in layout["placements"]:
        var p: Array = item["position"]
        _spawn(item["asset"], Vector3(p[0], p[1], p[2]), item["scale"], item["rotation_y"])

func _catalog(records: Array) -> void:
    # A single complete museum-style grid at actual world scale.
    var spacing := 23.0
    _ground(Vector3(69.0, -0.08, 220.0), Vector2(184.0, 506.0), Color("829276"))
    for i in range(records.size()):
        var record: Dictionary = records[i]
        var p := Vector3(float(i % 7) * spacing, 0.0, floorf(float(i) / 7.0) * spacing)
        _spawn(record["id"], p)
        var label := Label3D.new()
        label.text = String(record["id"]).replace("_", " ") + "\n" + str(record["triangles"]) + " triangles"
        label.position = p + Vector3(0.0, 0.4, 8.0)
        label.font_size = 40
        label.pixel_size = 0.017
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.modulate = Color(1.0, 1.0, 0.9)
        add_child(label)

func _ground(where: Vector3, dimensions: Vector2, color: Color) -> void:
    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = dimensions
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 1.0
    plane.material = material
    ground.mesh = plane
    ground.position = where
    add_child(ground)

func _lighting() -> void:
    var world := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("BFD5D8")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("D7E5DA")
    environment.ambient_light_energy = 0.65
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = environment
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
    sun.light_color = Color("FFF1DA")
    sun.light_energy = 1.3
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 160.0
    add_child(sun)

func _camera() -> void:
    var camera := Camera3D.new()
    camera.set_script(CAMERA_SCRIPT)
    camera.position = Vector3(35.0, 27.0, 44.0) if not catalog_mode else Vector3(37.0, 28.0, 51.0)
    camera.far = 1000.0
    camera.fov = 58.0
    add_child(camera)
    camera.look_at(Vector3(0.0, 4.0, 0.0) if not catalog_mode else Vector3(48.0, 5.0, 0.0))
    camera.make_current()

func _instructions() -> void:
    var layer := CanvasLayer.new()
    var label := Label.new()
    label.text = "GOLF NATURE PACK   |   153 assets\nHold right mouse: look   ·   WASD: move   ·   Q/E: down/up   ·   Shift: faster   ·   Esc: release mouse"
    label.position = Vector2(22.0, 18.0)
    label.add_theme_font_size_override("font_size", 18)
    label.add_theme_color_override("font_color", Color("F4F3E9"))
    label.add_theme_color_override("font_shadow_color", Color("203B2B"))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 2)
    layer.add_child(label)
    add_child(layer)
