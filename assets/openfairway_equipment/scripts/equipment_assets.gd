class_name OFGEquipmentAssets
extends RefCounted
## Optional visual adapter. The catalog's economy values are never changed here.

const BASE := "res://assets/openfairway_equipment/"
const CONDITION_SHADER = preload("res://assets/openfairway_equipment/shaders/club_condition.gdshader")
const DOUBLE_SIDED_CONDITION_SHADER = preload("res://assets/openfairway_equipment/shaders/club_condition_double_sided.gdshader")
## User-selected meter-scale heads. Each contains multiple meshes and a ShaftSocket
## marker; align that marker to the catalog club's existing shaft at instantiation.
const FAIRWAY_HEAD_SCENE = preload("res://assets/Selected_Club_Heads/Fairway_Wood_Head.glb")
const DRIVER_HEAD_SCENE = preload("res://assets/Selected_Club_Heads/Driver_Head.glb")
const HYBRID_HEAD_SCENE = preload("res://assets/Selected_Club_Heads/Hybrid_Rescue_Head.glb")
## Per-catalog-item shop skins (18 distinct material treatments over the same three
## family meshes above -- same ShaftSocket convention, same geometry, just their own
## crown/face/sole textures matching each club's identity and rarity). Preferred over
## the shared family scene above whenever one exists for the asset id.
const SKIN_HEAD_DIR := "res://assets/Selected_Club_Heads/skins/"
## Clubs whose pack head doesn't match what they are: [skin head to use, tint (white = none)].
## The Utility Iron 2U shipped on the hybrid mesh, so its photo and 3D model read as a hybrid
## next to an iron's name. Its own hollow-body iron head (skins/utility_2u_iron_base.glb: the
## parametric FreeCAD model in Documents/FreeCAD/GolfHead, exported by
## tools/freecad/export_utility_2u_head.py) is authored like the iron skins, so it takes the
## same face flip. The hybrids wear the Sport Hybrid 21 head (Codex's FreeCAD model in
## assets/Sport_Hybrid_21_Head), one livery each (skins/<id>_sport_base.glb, exported by
## tools/freecad/export_sport_hybrid_head.py in the 2U skin's frame, so they take the same flip).
## The drivers with the plain driver silhouette wear the Driver460 head (the parametric FreeCAD
## model in assets/Driver_460_Head, with the Sport Hybrid 21's face-to-hosel joint), one livery
## each (skins/<id>_d460_base.glb, exported by tools/freecad/export_driver_460_head.py in the same
## frame, so they take the same flip), the admin-sandbox Grenade and Persimmon Ghost (oiled wood
## livery) included. The 4-9 iron sets wear the forged iron family (blade, muscle back, cavity back,
## wide-sole cavity back; assets/Iron_Heads, exported by tools/freecad/export_iron_heads.py with art
## from tools/make_iron_textures.py) as skins/<id>_v2_base.glb, one livery per set. The fairway woods
## wear the Driver460's design at a fairway wood's size (assets/Fairway_Wood_V2, exported by
## tools/freecad/export_fairway_head.py with art from tools/make_fairway_textures.py) as skins/<id>_fw_base.glb.
const HEAD_OVERRIDES := {
    "utility_2u": ["utility_2u_v2", Color.WHITE],
    "rescue_rookie": ["rescue_rookie_sport", Color.WHITE],
    "cloudcutter_4h": ["cloudcutter_4h_sport", Color.WHITE],
    "loaner_driver": ["loaner_driver_d460", Color.WHITE],
    "thrift_titan_460": ["thrift_titan_460_d460", Color.WHITE],
    "slice_slayer": ["slice_slayer_d460", Color.WHITE],
    "rocket_boomer_lt": ["rocket_boomer_lt_d460", Color.WHITE],
    "hollow_point_tour": ["hollow_point_tour_d460", Color.WHITE],
    "meteor_xr_proto": ["meteor_xr_proto_d460", Color.WHITE],
    "grenade_driver": ["grenade_driver_d460", Color.WHITE],
    "persimmon_ghost": ["persimmon_ghost_d460", Color.WHITE],
    "loaner_irons": ["loaner_irons_v2", Color.WHITE],
    "thrift_cavity_backs": ["thrift_cavity_backs_v2", Color.WHITE],
    "game_improver_xl": ["game_improver_xl_v2", Color.WHITE],
    "mustard_muscle": ["mustard_muscle_v2", Color.WHITE],
    "blade_runner_forged": ["blade_runner_forged_v2", Color.WHITE],
    "tour_forged_cb": ["tour_forged_cb_v2", Color.WHITE],
    "combo_proto": ["combo_proto_v2", Color.WHITE],
    "loaner_3w": ["loaner_3w_fw", Color.WHITE],
    "loaner_5w": ["loaner_5w_fw", Color.WHITE],
    "garage_3w": ["garage_3w_fw", Color.WHITE],
    "steelhead_classic": ["steelhead_classic_fw", Color.WHITE],
    "tour_spoon": ["tour_spoon_fw", Color.WHITE],
    "lowball_5w": ["lowball_5w_fw", Color.WHITE],
    "heirloom_5w": ["heirloom_5w_fw", Color.WHITE],
}
static var _items: Dictionary = {}
static var _skin_head_cache: Dictionary = {}  # asset_id -> PackedScene or null

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
    var head_scene := head_scene_for_asset(asset_id)
    if head_scene != null:
        _swap_head(club, head_scene, String(item.get("family", "")) == "iron" or HEAD_OVERRIDES.has(asset_id))
    if String(item.get("family", "")) == "putter":
        _seat_putter_shaft(club)
    apply_condition(club, condition_value, asset_id)
    if HEAD_OVERRIDES.has(asset_id) and HEAD_OVERRIDES[asset_id][1] != Color.WHITE:
        _tint_head(club, HEAD_OVERRIDES[asset_id][1])
    # Gameplay and Inspect default to no cast shadows. The thumbnail renderer
    # enables shadows on its own instances with a dedicated studio light.
    for mesh in _find_all_meshes(club):
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return club

## Putter shafts were modelled to stop exactly at the hosel sleeve's rim, which leaves a
## hairline seam between shaft and head at some angles. Stretch the shaft down its own
## axis (top end fixed, so the grip and head alignment are untouched) until its tip
## seats this far inside the sleeve.
const PUTTER_SHAFT_SEAT := 0.006

static func _seat_putter_shaft(club: Node3D) -> void:
    var shaft := _find_mesh_named(club, "__shaft")
    if shaft == null or shaft.mesh == null:
        return
    var lo := Vector3(0.0, INF, 0.0)
    var hi := Vector3(0.0, -INF, 0.0)
    for s in range(shaft.mesh.get_surface_count()):
        var verts: PackedVector3Array = shaft.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
        for v in verts:
            var p := shaft.transform * v  # shaft's parent space
            if p.y < lo.y:
                lo = p
            if p.y > hi.y:
                hi = p
    var length := hi.distance_to(lo)
    if length < 0.05:
        return
    var axis := (hi - lo) / length
    # Scale by `factor` along `axis` only (I + (factor - 1) * axis axis^T), about the top end.
    var k := (length + PUTTER_SHAFT_SEAT) / length - 1.0
    var stretch := Basis(Vector3.RIGHT + axis * axis.x * k, Vector3.UP + axis * axis.y * k, Vector3.BACK + axis * axis.z * k)
    shaft.transform = Transform3D(stretch, hi - stretch * hi) * shaft.transform

static func head_scene_for_asset(asset_id: String) -> PackedScene:
    if _skin_head_cache.has(asset_id):
        return _skin_head_cache[asset_id]
    var result: PackedScene = null
    var skin_id: String = HEAD_OVERRIDES[asset_id][0] if HEAD_OVERRIDES.has(asset_id) else asset_id
    var skin_path := SKIN_HEAD_DIR + skin_id + "_base.glb"
    if ResourceLoader.exists(skin_path):
        result = load(skin_path) as PackedScene
    else:
        var item: Dictionary = catalog().get(asset_id, {})
        match String(item.get("family", "")):
            "fairway": result = FAIRWAY_HEAD_SCENE
            "driver": result = DRIVER_HEAD_SCENE
            "hybrid": result = HYBRID_HEAD_SCENE
    _skin_head_cache[asset_id] = result
    return result

## Multiply the head's condition materials by `tint` (HEAD_OVERRIDES finishes).
static func _tint_head(club: Node, tint: Color) -> void:
    for mesh: MeshInstance3D in _find_all_meshes(club):
        if not String(mesh.name).ends_with("__head"):
            continue
        for surface in mesh.mesh.get_surface_count():
            var m: Material = mesh.get_surface_override_material(surface)
            if is_condition_material(m):
                var current: Variant = (m as ShaderMaterial).get_shader_parameter("base_color")
                var base: Color = current if current is Color else Color.WHITE
                (m as ShaderMaterial).set_shader_parameter("base_color", Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a))

## Retain every supplied head component, material and authored meter scale. The
## shortest axis rotation adjusts the supplied 60-degree lie to the original shaft
## without changing the face direction or inheriting the shaft's length scale.
static func _swap_head(club: Node3D, head_scene: PackedScene, flip_iron_face: bool = false) -> void:
    var head := _find_mesh_named(club, "__head")
    if head == null:
        return
    var ferrule := _find_mesh_named(club, "__ferrule")
    var shaft := _find_mesh_named(club, "__shaft")
    if shaft == null:
        return
    var parent := head.get_parent() as Node3D
    var index := head.get_index()
    var replacement := head_scene.instantiate() as Node3D
    var socket := _find_attachment_marker(replacement)
    if socket == null:
        # Muscle-back source exports place the head origin at the hosel mouth
        # instead of adding a separate marker node.
        socket = replacement
    var source := _relative_transform(socket, replacement)
    var target := _relative_transform(shaft, parent)
    var alignment := Basis(Quaternion(source.basis.y.normalized(), target.basis.y.normalized()))
    if flip_iron_face:
        # The supplied iron skins are authored with the strike face on the
        # opposite side from the gameplay iron coordinate convention. Preserve
        # the shaft axis, then rotate the head 180 degrees around that axis.
        alignment = Basis(Quaternion(target.basis.y.normalized(), PI)) * alignment
    replacement.transform = Transform3D(alignment, target.origin - alignment * source.origin)
    replacement.set_meta("ofg_head_source", head_scene.resource_path)
    replacement.set_meta("ofg_iron_face_flipped", flip_iron_face)
    for mesh in _find_all_meshes(replacement):
        mesh.name = String(mesh.name) + "__head"
        mesh.set_meta("ofg_authored_head", true)
    parent.add_child(replacement)
    parent.move_child(replacement, index)
    # club is a freshly instantiated scene not yet in the live tree here, so an
    # immediate free (rather than queue_free) is safe and leaves no stale "__head"
    # node around to double up in apply_condition below or ClubViewer3D's camera fit.
    head.free()
    if ferrule != null:
        ferrule.free()

static func _find_node_named(node: Node, exact_name: String) -> Node3D:
    if node is Node3D and String(node.name) == exact_name:
        return node
    for child in node.get_children():
        var found := _find_node_named(child, exact_name)
        if found != null:
            return found
    return null

static func _find_attachment_marker(node: Node) -> Node3D:
    for marker_name in ["ShaftSocket", "shaft_socket", "socket_mouth", "socket_bottom"]:
        var marker := _find_node_named(node, marker_name)
        if marker != null:
            return marker
    return null

static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current: Node = node
    while current != ancestor and current is Node3D:
        result = current.transform * result
        current = current.get_parent()
    return result

static func is_condition_material(material: Material) -> bool:
    return material is ShaderMaterial and material.shader in [CONDITION_SHADER, DOUBLE_SIDED_CONDITION_SHADER]

static func _texture_channel_mask(channel: int) -> Vector4:
    match channel:
        BaseMaterial3D.TEXTURE_CHANNEL_RED: return Vector4(1, 0, 0, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0, 1, 0, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0, 0, 1, 0)
        BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0, 0, 0, 1)
    return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0)

static func _find_mesh_named(node: Node, suffix: String) -> MeshInstance3D:
    if node is MeshInstance3D and String(node.name).ends_with(suffix):
        return node
    for child in node.get_children():
        var found := _find_mesh_named(child, suffix)
        if found != null:
            return found
    return null

static func _find_all_meshes(node: Node) -> Array:
    var out: Array = []
    if node is MeshInstance3D:
        out.append(node)
    for child in node.get_children():
        out.append_array(_find_all_meshes(child))
    return out

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

## A painted decal laid over a head (the Utility 2U's brand mark on its back): a transparent
## layer that the opaque condition shader would turn solid, so it keeps its own material and
## its paint fades as the club wears instead.
const DECAL_WORN_ALPHA := 0.45

static func is_decal_mesh(mesh: MeshInstance3D) -> bool:
    return String(mesh.name).contains("Decal")

static func _fade_decal(mesh_node: MeshInstance3D, value: float) -> void:
    for surface in mesh_node.mesh.get_surface_count():
        var material := mesh_node.get_surface_override_material(surface) as BaseMaterial3D
        if material == null:
            var original := mesh_node.get_active_material(surface) as BaseMaterial3D
            if original == null:
                continue
            material = original.duplicate() as BaseMaterial3D  # instance-local, like the wear materials
            mesh_node.set_surface_override_material(surface, material)
        var tint := material.albedo_color
        tint.a = lerpf(DECAL_WORN_ALPHA, 1.0, value)
        material.albedo_color = tint

static func _apply_recursive(node: Node, item: Dictionary, value: float) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        var node_name := String(mesh_node.name)
        var is_head := node_name.ends_with("__head")
        var authored_head := is_head and bool(mesh_node.get_meta("ofg_authored_head", false))
        var is_grip := node_name.ends_with("__grip") or node_name.ends_with("__ferrule")
        var is_shaft := node_name.ends_with("__shaft")
        if is_head and is_decal_mesh(mesh_node):
            _fade_decal(mesh_node, value)
        elif is_head or is_grip or is_shaft:
            for surface in mesh_node.mesh.get_surface_count():
                var current := mesh_node.get_surface_override_material(surface)
                if is_condition_material(current):
                    current.set_shader_parameter("condition", value)
                    continue
                var original := mesh_node.get_active_material(surface) as BaseMaterial3D
                if original == null:
                    continue
                var material := ShaderMaterial.new()
                material.resource_local_to_scene = true
                material.shader = DOUBLE_SIDED_CONDITION_SHADER if authored_head and original.cull_mode == BaseMaterial3D.CULL_DISABLED else CONDITION_SHADER
                material.set_shader_parameter("condition", value)
                # Godot remaps the glTF material's selected texCoord into UV on
                # import, including the iron/wedge atlases authored on TEXCOORD_1.
                # Sample the same UV as the imported BaseMaterial3D; forcing UV2
                # here instead samples the empty part of those atlases.
                if is_head and not authored_head and ResourceLoader.exists(BASE + "textures/" + String(item["id"]) + "/ofg_" + String(item["id"]) + "_albedo.png"):
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
                    # Custom heads retain their own PBR materials and UV layout.
                    # Condition wear still applies without borrowing the old atlas.
                    material.set_shader_parameter("use_orm", false)
                    material.set_shader_parameter("base_color", original.albedo_color)
                    material.set_shader_parameter("constant_roughness", original.roughness)
                    material.set_shader_parameter("constant_metallic", original.metallic)
                    if original.albedo_texture != null:
                        material.set_shader_parameter("albedo_tex", original.albedo_texture)
                    if original.normal_texture != null:
                        material.set_shader_parameter("normal_tex", original.normal_texture)
                    material.set_shader_parameter("normal_strength", 0.4 if is_grip else 0.0)
                    if authored_head:
                        if original.roughness_texture != null:
                            material.set_shader_parameter("roughness_tex", original.roughness_texture)
                            material.set_shader_parameter("use_roughness_texture", true)
                            material.set_shader_parameter("roughness_channel", _texture_channel_mask(original.roughness_texture_channel))
                        if original.metallic_texture != null:
                            material.set_shader_parameter("metallic_tex", original.metallic_texture)
                            material.set_shader_parameter("use_metallic_texture", true)
                            material.set_shader_parameter("metallic_channel", _texture_channel_mask(original.metallic_texture_channel))
                        material.set_shader_parameter("normal_strength", original.normal_scale if original.normal_enabled else 0.0)
                        material.set_shader_parameter("constant_specular", original.metallic_specular)
                        material.set_shader_parameter("constant_clearcoat", original.clearcoat if original.clearcoat_enabled else 0.0)
                        material.set_shader_parameter("constant_clearcoat_roughness", original.clearcoat_roughness)
                    material.set_shader_parameter("wear_tex", load(BASE + "textures/shared/ofg_grip_wear.png"))
                    # A grip/shaft never wears like metal (kept at 0); a texture-less head
                    # (custom sculpt) still uses the item's own chip/corrosion amounts.
                    material.set_shader_parameter("chip_strength", float(item.get("chip_strength", 0.0)) if is_head else 0.0)
                    material.set_shader_parameter("corrosion_strength", float(item.get("corrosion_strength", 0.0)) if is_head else 0.0)
                    if is_head:
                        var ox2: Array = item.get("oxidation_color", [0.38, 0.16, 0.055])
                        material.set_shader_parameter("oxidation_color", Vector3(float(ox2[0]), float(ox2[1]), float(ox2[2])))
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
