extends Node3D
const FLY_CAMERA = preload("res://nature_pack/scripts/fly_camera.gd")
const WALKER = preload("res://nature_pack/scripts/demo_walker.gd")
var _ball: RigidBody3D

func _ready() -> void:
    var ground := StaticBody3D.new()
    var floor_shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(20.0, 0.2, 14.0)
    floor_shape.shape = box
    floor_shape.position.y = -0.1
    ground.add_child(floor_shape)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(20.0, 14.0)
    var turf := StandardMaterial3D.new()
    turf.albedo_color = Color("64834B")
    plane.material = turf
    floor_mesh.mesh = plane
    ground.add_child(floor_mesh)
    add_child(ground)
    for item in [["azalea_pink_A", Vector3.ZERO], ["wax_myrtle_A", Vector3(3.0, 0.0, -2.0)]]:
        var scene := load("res://nature_pack/scenes/shrubs/" + String(item[0]) + ".tscn") as PackedScene
        var bush := scene.instantiate() as Node3D
        bush.position = item[1]
        add_child(bush)
    var player := CharacterBody3D.new()
    player.set_script(WALKER)
    player.position = Vector3(-3.0, 0.0, 0.9)
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.22
    capsule.height = 1.65
    var collision := CollisionShape3D.new()
    collision.shape = capsule
    collision.position.y = 0.825
    player.add_child(collision)
    var body_mesh := MeshInstance3D.new()
    var visible_capsule := CapsuleMesh.new()
    visible_capsule.radius = capsule.radius
    visible_capsule.height = capsule.height
    var blue := StandardMaterial3D.new()
    blue.albedo_color = Color("4E84AD")
    visible_capsule.material = blue
    body_mesh.mesh = visible_capsule
    body_mesh.position.y = 0.825
    player.add_child(body_mesh)
    add_child(player)
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color("CCDAD8")
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color("E2E9DD")
    settings.ambient_light_energy = 0.65
    environment.environment = settings
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
    sun.light_energy = 1.1
    sun.shadow_enabled = true
    add_child(sun)
    var camera := Camera3D.new()
    camera.set_script(FLY_CAMERA)
    camera.position = Vector3(2.8, 2.0, 4.3)
    add_child(camera)
    camera.look_at(Vector3(0.0, 0.65, 0.0))
    camera.make_current()
    var layer := CanvasLayer.new()
    var label := Label.new()
    label.position = Vector2(20.0, 16.0)
    label.text = "FLEXIBLE LEAVES\nSpace: shoot ball through bush   ·   Arrow keys: walk through foliage\nRight mouse + WASD: move camera   ·   Q/E: down/up   ·   Esc: release mouse"
    label.add_theme_font_size_override("font_size", 18)
    label.add_theme_color_override("font_shadow_color", Color.BLACK)
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    layer.add_child(label)
    add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
        _shoot()

func _shoot() -> void:
    if is_instance_valid(_ball): _ball.queue_free()
    _ball = RigidBody3D.new()
    _ball.name = "GolfBall"
    _ball.mass = 0.0459
    _ball.continuous_cd = true
    _ball.position = Vector3(-3.0, 0.85, 0.0)
    var shape := SphereShape3D.new()
    shape.radius = 0.02135
    var collision := CollisionShape3D.new()
    collision.shape = shape
    _ball.add_child(collision)
    var mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = shape.radius
    sphere.height = shape.radius * 2.0
    sphere.radial_segments = 24
    sphere.rings = 12
    mesh.mesh = sphere
    var white := StandardMaterial3D.new()
    white.albedo_color = Color(0.97, 0.97, 0.94)
    mesh.material_override = white
    _ball.add_child(mesh)
    add_child(_ball)
    _ball.linear_velocity = Vector3(7.0, 1.5, 0.0)
