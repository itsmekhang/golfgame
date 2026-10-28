class_name OFGEquipmentAssets
extends RefCounted
## Optional visual adapter. The catalog's economy values are never changed here.

const BASE := "res://assets/openfairway_equipment/"
const CONDITION_SHADER = preload("res://assets/openfairway_equipment/shaders/club_condition.gdshader")
static var _items: Dictionary = {}

static func catalog() -> Dictionary:
    if _items.is_empty():
        var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "catalog.json"))
        for item: Dictionary in parsed.get("items", []):
            _items[String(item["id"])] = item
    return _items

static func create_club(asset_id: String, condition_value: float = 1.0, allow_admin: bool = false) -> Node3D:
    var item: Dictionary = catalog().get(asset_id, {})
    if item.is_empty() or (item.get("admin_only", false) and not allow_admin):
        push_warning("Equipment asset is missing or developer-only: " + asset_id)
        return null
    var scene := load(String(item["model"])) as PackedScene
    if scene == null:
        return null
    var club := scene.instantiate() as Node3D
    club.set_meta("ofg_asset_id", asset_id)
    apply_condition(club, condition_value, asset_id)
    return club

static func apply_condition(root: Node, condition_value: float, asset_id: String = "") -> void:
    var id := asset_id
    if id.is_empty():
        id = String(root.get_meta("ofg_asset_id", ""))
    var item: Dictionary = catalog().get(id, {})
    if item.is_empty():
        return
    var value := clampf(condition_value, 0.0, 1.0)
    root.set_meta("ofg_asset_id", id)
    root.set_meta("ofg_condition", value)
    _apply_recursive(root, item, value)

static func _apply_recursive(node: Node, item: Dictionary, value: float) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var node_name := String(mesh_node.name)
        var is_head := node_name.ends_with("__head")
        var is_grip := node_name.ends_with("__grip") or node_name.ends_with("__ferrule")
        var is_shaft := node_name.ends_with("__shaft")
        if is_head or is_grip or is_shaft:
            for surface in mesh_node.mesh.get_surface_count():
                var current := mesh_node.get_surface_override_material(surface)
                if current is ShaderMaterial and current.shader == CONDITION_SHADER:
                    current.set_shader_parameter("condition", value)
                    continue
                var original := mesh_node.get_active_material(surface) as BaseMaterial3D
                if original == null:
                    continue
                var material := ShaderMaterial.new()
                material.resource_local_to_scene = true
                material.shader = CONDITION_SHADER
                material.set_shader_parameter("condition", value)
                if is_head:
                    var prefix := BASE + "textures/" + String(item["id"]) + "/ofg_" + String(item["id"])
                    material.set_shader_parameter("albedo_tex", load(prefix + "_albedo.png"))
                    material.set_shader_parameter("orm_tex", load(prefix + "_orm.png"))
                    material.set_shader_parameter("normal_tex", load(prefix + "_normal.png"))
                    material.set_shader_parameter("wear_tex", load(String(item["wear_texture"])))
                    material.set_shader_parameter("chip_strength", float(item["chip_strength"]))
                    material.set_shader_parameter("corrosion_strength", float(item["corrosion_strength"]))
                    var ox: Array = item["oxidation_color"]
                    material.set_shader_parameter("oxidation_color", Vector3(float(ox[0]), float(ox[1]), float(ox[2])))
                else:
                    material.set_shader_parameter("use_orm", false)
                    material.set_shader_parameter("base_color", original.albedo_color)
                    material.set_shader_parameter("constant_roughness", original.roughness)
                    material.set_shader_parameter("constant_metallic", original.metallic)
                    if original.albedo_texture != null:
                        material.set_shader_parameter("albedo_tex", original.albedo_texture)
                    if original.normal_texture != null:
                        material.set_shader_parameter("normal_tex", original.normal_texture)
                    material.set_shader_parameter("normal_strength", 0.4 if is_grip else 0.0)
                    material.set_shader_parameter("wear_tex", load(BASE + "textures/shared/ofg_grip_wear.png"))
                    material.set_shader_parameter("chip_strength", 0.0)
                    material.set_shader_parameter("corrosion_strength", 0.0)
                mesh_node.set_surface_override_material(surface, material)
    for child in node.get_children():
        _apply_recursive(child, item, value)

static func condition_label(value: float) -> String:
    if value >= 0.94: return "Mint"
    if value >= 0.82: return "Excellent"
    if value >= 0.62: return "Good"
    if value >= 0.42: return "Fair"
    if value >= 0.22: return "Worn"
    return "Poor"
