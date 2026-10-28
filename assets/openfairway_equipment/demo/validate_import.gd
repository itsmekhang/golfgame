extends SceneTree
const Assets = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")

func _initialize() -> void:
    call_deferred("_run_checks")

func _run_checks() -> void:
    var count := 0
    var errors: Array[String] = []
    for id: String in Assets.catalog():
        var club := Assets.create_club(id, 1.0, true)
        if club == null:
            errors.append(id + ": instantiate failed")
            continue
        root.add_child(club)
        var meshes := club.find_children("*", "MeshInstance3D", true, false)
        if meshes.size() < 3: errors.append(id + ": head/shaft/grip missing")
        var head: MeshInstance3D
        for m: MeshInstance3D in meshes:
            if String(m.name).ends_with("__head"): head = m
        if head == null:
            errors.append(id + ": named head missing")
        else:
            var material := head.get_surface_override_material(0) as ShaderMaterial
            if material == null:
                errors.append(id + ": condition material missing")
            else:
                Assets.apply_condition(club, 0.22, id)
                if not is_equal_approx(float(material.get_shader_parameter("condition")), 0.22): errors.append(id + ": condition did not update")
                Assets.apply_condition(club, 1.0, id)
            var bounds := head.get_aabb()
            if bounds.size.x < 0.07 or bounds.size.x > 0.16: errors.append(id + ": head scale is wrong")
        club.free()
        await process_frame
        count += 1
    var first := Assets.create_club("scotty_grail", 0.2)
    var second := Assets.create_club("scotty_grail", 1.0)
    if first != null and second != null:
        root.add_child(first)
        root.add_child(second)
        Assets.apply_condition(first, 0.05)
        var first_head: MeshInstance3D = first.find_children("*__head", "MeshInstance3D", true, false)[0]
        var second_head: MeshInstance3D = second.find_children("*__head", "MeshInstance3D", true, false)[0]
        var first_material := first_head.get_surface_override_material(0) as ShaderMaterial
        var second_material := second_head.get_surface_override_material(0) as ShaderMaterial
        if first_material == second_material or not is_equal_approx(float(second_material.get_shader_parameter("condition")), 1.0): errors.append("Instance condition leaked")
        first.free()
        second.free()
        await process_frame
    var cover := load("res://assets/openfairway_equipment/models/props/ofg_grail_headcover.glb") as PackedScene
    if cover == null: errors.append("Headcover could not load")
    if count != 45: errors.append("Not all 45 items were checked")
    print("OFG_IMPORT_CHECK ", JSON.stringify({"items_instantiated": count, "errors": errors}))
    quit(0 if errors.is_empty() else 1)
