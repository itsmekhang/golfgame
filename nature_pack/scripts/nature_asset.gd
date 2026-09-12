@tool
extends Node3D
## Flexible foliage: four damped contact springs, nonblocking canopies, ball drag.
@export var asset_id: String = ""
@export var use_wind: bool = true
@export var contact_response_enabled: bool = true
@export_flags_3d_physics var interactor_collision_mask: int = 1
@export_range(1.0, 100.0) var spring_stiffness: float = 42.0
@export_range(0.5, 30.0) var spring_damping: float = 8.5
@export var contact_radius: float = 0.75
@export var max_bend: float = 0.48
@export var ball_drag_enabled: bool = true
@export var ball_drag_per_second: float = 2.2
@export var lod_near_distance: float = 18.0
@export var lod_far_distance: float = 65.0
@export var max_distance: float = 450.0
const LEAF_SHADER = preload("res://nature_pack/shaders/leaves_contact.gdshader")
const BRANCH_SHADER = preload("res://nature_pack/shaders/branches_contact.gdshader")
const WATER_SHADER = preload("res://nature_pack/shaders/water.gdshader")
static var _records: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _area: Area3D
var _proxies: Array = []
var _centers: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _offsets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _speeds: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _radii: Array[float] = [0.75, 0.75, 0.75, 0.75]
var _ids: Array[int] = [0, 0, 0, 0]
var _last_positions: Dictionary = {}
var _height: float = 1.0
var _bounds: AABB
var _category: String = ""

func _ready() -> void:
    if _records.is_empty():
        var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://nature_pack/catalog.json"))
        for record in data["assets"]: _records[String(record["id"])] = record
    if not _records.has(asset_id): return
    var record: Dictionary = _records[asset_id]
    var lo: Array = record["bounds_min"]
    var dims: Array = record["dimensions_m"]
    _bounds = AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(dims[0], dims[1], dims[2]))
    _height = maxf(_bounds.size.y, 0.1)
    _category = record["category"]
    _proxies = record.get("foliage_proxies", [])
    _configure_materials()
    if Engine.is_editor_hint():
        set_physics_process(false)
        return
    if contact_response_enabled and _category in ["trees", "palms", "shrubs", "grasses", "groundcover"]:
        _area = Area3D.new()
        _area.name = "SoftFoliageContact"
        _area.collision_layer = 0
        _area.collision_mask = interactor_collision_mask
        _area.monitorable = false
        var collider := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = _bounds.size.max(Vector3(0.1, 0.1, 0.1)) + Vector3.ONE * 0.25
        collider.shape = box
        collider.position = _bounds.get_center()
        _area.add_child(collider)
        add_child(_area)
    else: set_physics_process(false)

func _configure_materials() -> void:
    var leaf := ShaderMaterial.new()
    leaf.shader = LEAF_SHADER
    var branch := ShaderMaterial.new()
    branch.shader = BRANCH_SHADER
    branch.set_shader_parameter("is_leaf_surface", false)
    var world_height := _height * absf(global_basis.get_scale().y)
    for mat in [leaf, branch]:
        mat.set_shader_parameter("plant_height", world_height)
        mat.set_shader_parameter("root_lock_height", world_height * 0.32 if _category == "trees" else 0.02)
        mat.set_shader_parameter("wind_strength", (0.045 if _category == "trees" else 0.022) if use_wind else 0.0)
        _materials.append(mat)
    var water := ShaderMaterial.new()
    water.shader = WATER_SHADER
    for child in get_children():
        if String(child.name).begins_with("LOD"):
            _configure_meshes(child, int(String(child.name).trim_prefix("LOD")), has_node("LOD1"), leaf, branch, water)

func _configure_meshes(node: Node, level: int, has_lods: bool, leaf: Material, branch: Material, water: Material) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if has_lods:
            mi.visibility_range_begin = 0.0 if level == 0 else (lod_near_distance if level == 1 else lod_far_distance)
            mi.visibility_range_end = lod_near_distance if level == 0 else (lod_far_distance if level == 1 else max_distance)
            mi.visibility_range_begin_margin = 0.0
            mi.visibility_range_end_margin = 0.0
        mi.extra_cull_margin = max_bend + 0.2
        if mi.mesh:
            for surface in range(mi.mesh.get_surface_count()):
                var original := mi.mesh.surface_get_material(surface)
                if original == null: continue
                var name_lower := original.resource_name.to_lower()
                if name_lower in ["leaves", "petals", "grass"]: mi.set_surface_override_material(surface, leaf)
                elif name_lower == "bark" and _category in ["trees", "palms", "shrubs"]: mi.set_surface_override_material(surface, branch)
                elif name_lower == "water": mi.set_surface_override_material(surface, water)
    for child in node.get_children(): _configure_meshes(child, level, has_lods, leaf, branch, water)

func foliage_drag_at(world_position: Vector3) -> float:
    var local := to_local(world_position)
    if not _bounds.grow(0.12).has_point(local): return 0.0
    if _proxies.is_empty(): return 0.65
    var density := 0.0
    for proxy in _proxies:
        var center := Vector3(proxy[0], proxy[1], proxy[2])
        var radius := maxf(float(proxy[3]), 0.01)
        density = maxf(density, clampf(1.0 - local.distance_to(center) / radius, 0.0, 1.0))
    return density

func _physics_process(delta: float) -> void:
    if Engine.is_editor_hint() or _area == null: return
    for i in range(4): _targets[i] = Vector3.ZERO
    var bodies: Array[Node3D] = _area.get_overlapping_bodies()
    for candidate in get_tree().get_nodes_in_group("foliage_interactors"):
        var actor := candidate as Node3D
        if actor != null and not bodies.has(actor) and _bounds.grow(0.8).has_point(to_local(actor.global_position)): bodies.append(actor)
    var active_ids: Array[int] = []
    for body in bodies:
        if is_ancestor_of(body) or not (body is RigidBody3D or body is CharacterBody3D or body.is_in_group("foliage_interactors")): continue
        var id := body.get_instance_id()
        var position_now := body.global_position
        var velocity := Vector3.ZERO
        if body is RigidBody3D: velocity = (body as RigidBody3D).linear_velocity
        elif body is CharacterBody3D: velocity = (body as CharacterBody3D).velocity
        elif _last_positions.has(id): velocity = (position_now - Vector3(_last_positions[id])) / maxf(delta, 0.0001)
        _last_positions[id] = position_now
        active_ids.append(id)
        var slot := _ids.find(id)
        if slot < 0:
            slot = _ids.find(0)
            if slot < 0: continue
            _ids[slot] = id
        _centers[slot] = position_now + (Vector3.UP * 0.7 if body is CharacterBody3D else Vector3.ZERO)
        _radii[slot] = contact_radius * (1.7 if body is CharacterBody3D else 1.0)
        var direction := velocity.normalized()
        if direction.length_squared() < 0.01: direction = (position_now - global_position).normalized()
        _targets[slot] = direction * minf(max_bend, 0.06 + velocity.length() * 0.065)
        var density := foliage_drag_at(position_now)
        if ball_drag_enabled and body is RigidBody3D and not (body as RigidBody3D).freeze and density > 0.0:
            var rb := body as RigidBody3D
            rb.apply_central_force(-velocity * rb.mass * ball_drag_per_second * density)
    for id in _last_positions.keys():
        if not active_ids.has(int(id)): _last_positions.erase(id)
    var steps := maxi(1, int(ceil(delta / (1.0 / 120.0))))
    var dt := delta / float(steps)
    for i in range(4):
        for substep in range(steps):
            _speeds[i] += ((_targets[i] - _offsets[i]) * spring_stiffness - _speeds[i] * spring_damping) * dt
            _offsets[i] = (_offsets[i] + _speeds[i] * dt).limit_length(max_bend * 1.3)
        if not active_ids.has(_ids[i]) and _offsets[i].length_squared() < 0.000001 and _speeds[i].length_squared() < 0.000001: _ids[i] = 0
        for mat in _materials:
            mat.set_shader_parameter("contact_" + str(i), Vector4(_centers[i].x, _centers[i].y, _centers[i].z, _radii[i]))
            mat.set_shader_parameter("flex_" + str(i), _offsets[i])

func poke(world_position: Vector3, world_velocity: Vector3, radius: float = 0.75, slot: int = 0) -> void:
    slot = clampi(slot, 0, 3)
    _centers[slot] = world_position
    _radii[slot] = maxf(radius, 0.05)
    _speeds[slot] += world_velocity.limit_length(12.0) * 0.12
