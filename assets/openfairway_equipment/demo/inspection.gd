extends Node3D

const Assets = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")
const COLORS := {"loaner": Color("a2aba7"), "common": Color("d0d4cb"), "uncommon": Color("79c49b"), "rare": Color("8db9e9"), "epic": Color("c1a7e0"), "legendary": Color("e9c575"), "mythic": Color("ef9583")}
var camera: Camera3D
var pivot: Node3D
var club: Node3D
var current_id := "scotty_grail"
var item_list: ItemList
var title_label: Label
var info_label: Label
var condition_text: Label
var condition_slider: HSlider
var family_filter: OptionButton
var admin_toggle: CheckBox
var full_toggle: CheckBox
var rotate_toggle: CheckBox
var visible_ids: Array[String] = []
var yaw := 0.0
var pitch := -0.2
var zoom := 1.0
var dragging := false

func _ready() -> void:
    _world()
    _ui()
    _populate()
    _select_id(current_id)

func _world() -> void:
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("13231e")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.7
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("788d9a")
    sky_material.sky_horizon_color = Color("d8d3b8")
    sky_material.ground_horizon_color = Color("bac0ae")
    sky_material.ground_bottom_color = Color("33463b")
    sky.sky_material = sky_material
    env.sky = sky
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.environment = env
    add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42, -35, 0)
    light.light_color = Color("fff0d8")
    light.light_energy = 1.6
    add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-25, 150, 0)
    fill.light_color = Color("bddcf5")
    fill.light_energy = 0.8
    add_child(fill)
    pivot = Node3D.new()
    add_child(pivot)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.001
    camera.far = 100.0
    camera.current = true
    add_child(camera)

func _label(parent: Node, value: String, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = value
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label

func _ui() -> void:
    var canvas := CanvasLayer.new()
    add_child(canvas)
    var panel := PanelContainer.new()
    panel.position = Vector2(24, 24)
    panel.size = Vector2(326, 852)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("24372e")
    style.set_corner_radius_all(12)
    style.content_margin_left = 20
    style.content_margin_right = 20
    style.content_margin_top = 18
    style.content_margin_bottom = 18
    panel.add_theme_stylebox_override("panel", style)
    canvas.add_child(panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 11)
    panel.add_child(column)
    _label(column, "O P E N F A I R W A Y", 14, Color("d8c995"))
    _label(column, "Equipment atelier", 26, Color("f2f0df"))
    _label(column, "45 clubs · 7 collectible putters", 14, Color("b4c3b4"))
    family_filter = OptionButton.new()
    for f in ["All equipment", "Putters", "Drivers", "Fairway woods", "Hybrids", "Iron sets", "Wedges"]:
        family_filter.add_item(f)
    family_filter.item_selected.connect(func(_index: int): _populate())
    column.add_child(family_filter)
    admin_toggle = CheckBox.new()
    admin_toggle.text = "Show developer equipment"
    admin_toggle.toggled.connect(func(_value: bool): _populate())
    column.add_child(admin_toggle)
    item_list = ItemList.new()
    item_list.custom_minimum_size = Vector2(286, 540)
    item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    item_list.add_theme_font_size_override("font_size", 15)
    item_list.item_selected.connect(_selected)
    column.add_child(item_list)
    _label(column, "Drag to rotate · Scroll to zoom", 13, Color("b4c3b4"))
    var details := VBoxContainer.new()
    details.position = Vector2(394, 38)
    canvas.add_child(details)
    title_label = _label(details, "", 34, Color("f4f0dc"))
    info_label = _label(details, "", 16, Color("c3cdbd"))
    var controls := VBoxContainer.new()
    controls.position = Vector2(420, 728)
    controls.custom_minimum_size = Vector2(580, 0)
    canvas.add_child(controls)
    condition_text = _label(controls, "Condition · Mint", 18, Color("e4dfcb"))
    condition_slider = HSlider.new()
    condition_slider.min_value = 0.0
    condition_slider.max_value = 1.0
    condition_slider.step = 0.01
    condition_slider.value = 1.0
    condition_slider.custom_minimum_size = Vector2(580, 32)
    condition_slider.value_changed.connect(_condition_changed)
    controls.add_child(condition_slider)
    var row := HBoxContainer.new()
    controls.add_child(row)
    full_toggle = CheckBox.new()
    full_toggle.text = "Full club"
    full_toggle.toggled.connect(func(_v: bool): zoom = 1.0; _camera())
    row.add_child(full_toggle)
    rotate_toggle = CheckBox.new()
    rotate_toggle.text = "Turntable"
    row.add_child(rotate_toggle)
    var reset := Button.new()
    reset.text = "Reset view"
    reset.pressed.connect(func(): yaw = 0; pitch = -0.2; zoom = 1; _camera())
    row.add_child(reset)

func _populate() -> void:
    item_list.clear()
    visible_ids.clear()
    var families := ["", "putter", "driver", "fairway", "hybrid", "iron", "wedge"]
    var chosen: String = families[family_filter.selected]
    for id: String in Assets.catalog():
        var item: Dictionary = Assets.catalog()[id]
        if item["admin_only"] and not admin_toggle.button_pressed: continue
        if chosen != "" and item["family"] != chosen: continue
        visible_ids.append(id)
        var index := item_list.add_item(String(item["display_name"]))
        item_list.set_item_custom_fg_color(index, COLORS[item["rarity"]])
        if id == current_id: item_list.select(index)

func _selected(index: int) -> void:
    _select_id(visible_ids[index])

func _select_id(id: String) -> void:
    if club != null:
        pivot.remove_child(club)
        club.queue_free()
    current_id = id
    club = Assets.create_club(id, condition_slider.value, admin_toggle.button_pressed)
    if club == null: return
    pivot.add_child(club)
    var item: Dictionary = Assets.catalog()[id]
    title_label.text = String(item["display_name"])
    info_label.text = String(item["rarity"]).capitalize() + "  /  " + String(item["family"]).capitalize() + "  /  " + str(item["total_triangles"]) + " triangles"
    title_label.add_theme_color_override("font_color", COLORS[item["rarity"]])
    yaw = PI if item["family"] == "putter" else 0.0
    pitch = -0.2
    zoom = 1.0
    _camera()

func _condition_changed(value: float) -> void:
    condition_text.text = "Condition · " + Assets.condition_label(value) + "  " + str(roundi(value * 100)) + "%"
    if club != null: Assets.apply_condition(club, value, current_id)

func _camera() -> void:
    var full := full_toggle != null and full_toggle.button_pressed
    var target := Vector3(-0.16, 0.49, 0) if full else Vector3(0, 0.04, 0.01)
    var offset := Vector3(0.20, 0.14, -0.26)
    offset = Basis(Vector3.RIGHT, pitch) * offset
    offset = Basis(Vector3.UP, yaw) * offset
    camera.position = target + offset.normalized() * (2.0 if full else 0.40)
    camera.look_at(target)
    camera.size = (1.33 if full else 0.25) * zoom
    camera.h_offset = -camera.size * 0.18

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(0.40, zoom * 0.90); _camera()
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(2.6, zoom * 1.1); _camera()
    if event is InputEventMouseMotion and dragging:
        yaw -= event.relative.x * 0.009
        pitch = clampf(pitch - event.relative.y * 0.008, -0.6, 0.5)
        _camera()

func _process(delta: float) -> void:
    if rotate_toggle != null and rotate_toggle.button_pressed:
        yaw += delta * 0.32
        _camera()
