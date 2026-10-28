extends SceneTree
## Integration checks shared by the wood and driver tests. Uses actual catalog assets.
const Equipment = preload("res://assets/openfairway_equipment/scripts/equipment_assets.gd")
var failures := 0

func family() -> String:
	return ""

## Driver/fairway ship a full texture set per component; the hybrid asset only
## textures its face material (the rest are solid PBR values), so it has fewer
## roughness-mapped surfaces to find.
func min_textured_roughness() -> int:
	return 1 if family() == "hybrid" else 2

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://selected_head_swap_test_unused.json")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func meshes(node: Node, suffix: String = "") -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and str(node.name).ends_with(suffix):
		result.append(node)
	for child in node.get_children():
		result.append_array(meshes(child, suffix))
	return result

func model_transform(node: Node3D, ancestor: Node3D = null) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current is Node3D and current != ancestor:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func selected_root(node: Node) -> Node3D:
	if node is Node3D and node.has_meta("ofg_head_source"):
		return node
	for child in node.get_children():
		var found := selected_root(child)
		if found != null:
			return found
	return null

## A painted decal over the head keeps its own textured, alpha-blended material (the opaque
## condition shader would turn it solid) and an instance-local copy that fades with wear.
func check_decal(head: MeshInstance3D, surface: int, id: String) -> void:
	var source := head.mesh.surface_get_material(surface) as BaseMaterial3D
	var paint := head.get_surface_override_material(surface) as BaseMaterial3D
	check(source != null and source.albedo_texture != null and source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, id + " decal is a textured transparent layer")
	check(paint != null and paint != source and not Equipment.is_condition_material(paint), id + " decal keeps its own instance material")
	if paint != null:
		check(is_equal_approx(paint.albedo_color.a, lerpf(Equipment.DECAL_WORN_ALPHA, 1.0, 0.6)), id + " decal paint follows condition")


func check_material(head: MeshInstance3D, surface: int, id: String) -> void:
	var source := head.mesh.surface_get_material(surface) as BaseMaterial3D
	var worn := head.get_surface_override_material(surface) as ShaderMaterial
	check(source != null and Equipment.is_condition_material(worn), id + " has authored wear material")
	if source == null or worn == null:
		return
	check(worn.get_shader_parameter("use_orm") == false, id + " avoids the original atlas")
	check(is_equal_approx(float(worn.get_shader_parameter("condition")), 0.6), id + " condition retained")
	check(worn.get_shader_parameter("base_color").is_equal_approx(source.albedo_color), id + " color retained")
	check(is_equal_approx(float(worn.get_shader_parameter("constant_roughness")), source.roughness), id + " roughness factor retained")
	check(is_equal_approx(float(worn.get_shader_parameter("constant_metallic")), source.metallic), id + " metallic factor retained")
	check(is_equal_approx(float(worn.get_shader_parameter("constant_clearcoat")), source.clearcoat if source.clearcoat_enabled else 0.0), id + " clearcoat retained")
	check(worn.shader == (Equipment.DOUBLE_SIDED_CONDITION_SHADER if source.cull_mode == BaseMaterial3D.CULL_DISABLED else Equipment.CONDITION_SHADER), id + " culling retained")
	if source.albedo_texture != null:
		check(worn.get_shader_parameter("albedo_tex") == source.albedo_texture, id + " color texture retained")
	if source.normal_enabled:
		check(worn.get_shader_parameter("normal_tex") == source.normal_texture, id + " normal texture retained")
		check(is_equal_approx(float(worn.get_shader_parameter("normal_strength")), source.normal_scale), id + " normal scale retained")
	if source.roughness_texture != null:
		check(worn.get_shader_parameter("use_roughness_texture") == true, id + " roughness mapping enabled")
		check(worn.get_shader_parameter("roughness_tex") == source.roughness_texture, id + " roughness texture retained")
		check(worn.get_shader_parameter("roughness_channel") == Equipment._texture_channel_mask(source.roughness_texture_channel), id + " roughness channel retained")
	if source.metallic_texture != null:
		check(worn.get_shader_parameter("use_metallic_texture") == true, id + " metallic mapping enabled")
		check(worn.get_shader_parameter("metallic_tex") == source.metallic_texture, id + " metallic texture retained")
		check(worn.get_shader_parameter("metallic_channel") == Equipment._texture_channel_mask(source.metallic_texture_channel), id + " metallic channel retained")

func run() -> void:
	var wanted := family()
	var model_type := "wood" if wanted == "fairway" else ("iron_set" if wanted == "iron" else wanted)
	var head_scene: PackedScene
	match wanted:
		"driver": head_scene = Equipment.DRIVER_HEAD_SCENE
		"fairway": head_scene = Equipment.FAIRWAY_HEAD_SCENE
		"hybrid": head_scene = Equipment.HYBRID_HEAD_SCENE
		"iron": head_scene = Equipment.head_scene_for_asset("loaner_irons")
		"wedge": head_scene = Equipment.head_scene_for_asset("loaner_pw")
	if head_scene == null:
		head_scene = Equipment.head_scene_for_asset("loaner_pw" if wanted == "wedge" else "loaner_irons" if wanted == "iron" else "")
	check(head_scene != null, wanted + " family head scene resolves")
	if head_scene == null:
		quit(1)
	var reference := head_scene.instantiate() as Node3D
	var reference_meshes: Dictionary = {}
	for mesh in meshes(reference):
		reference_meshes[str(mesh.name)] = mesh
	check(reference_meshes.size() > 0, "supplied family components imported")
	var expected := 0
	for model: Dictionary in ClubCatalog.models():
		if str(model.get("type", "")) == model_type:
			expected += 1
			check(str(Equipment.catalog().get(str(model.id), {}).get("family", "")) == wanted, str(model.id) + " has a matching equipment asset")
	var checked := 0
	var first_id := ""
	for item: Dictionary in Equipment.catalog().values():
		if str(item.get("family", "")) != wanted:
			continue
		var id := str(item.id)
		var preview := EquipmentPreview.get_texture(id)
		var expected_preview := "res://assets/Selected_Iron_Heads/shop_thumbnails/512/ofg_" + id + "_base_back.png" if wanted == "iron" else ("res://assets/Selected_Wedge_Heads/shop_thumbnails/512/ofg_" + id + "_base_back.png" if wanted == "wedge" else "res://assets/Selected_Club_Heads/previews/ofg_" + id + ".png")
		check(preview != null and preview.resource_path == expected_preview, id + " uses the replacement thumbnail")
		if first_id.is_empty(): first_id = id
		var item_head_scene := Equipment.head_scene_for_asset(id)
		var item_reference := item_head_scene.instantiate() as Node3D
		var item_reference_meshes: Dictionary = {}
		for mesh in meshes(item_reference):
			item_reference_meshes[str(mesh.name)] = mesh
		var original := (load(str(item.model)) as PackedScene).instantiate() as Node3D
		var club := Equipment.create_club(id, 0.6, true)
		check(club != null, id + " loads")
		if club == null:
			original.free()
			continue
		root.add_child(club)
		await process_frame
		var fitted := selected_root(club)
		check(fitted != null, id + " uses the selected download")
		if fitted == null:
			club.queue_free()
			original.free()
			continue
		check(str(fitted.get_meta("ofg_head_source")) == item_head_scene.resource_path, id + " selected source path matches")
		if wanted == "iron":
			check(bool(fitted.get_meta("ofg_iron_face_flipped", false)), id + " applies iron face orientation correction")
		check(fitted.basis.get_scale().is_equal_approx(Vector3.ONE), id + " authored meter scale retained")
		var heads := meshes(club, "__head")
		check(heads.size() == item_reference_meshes.size(), id + " includes every head component")
		check(meshes(club).size() == heads.size() + 2, id + " has only the new head, shaft and grip")
		check(meshes(club, "__ferrule").is_empty(), id + " removed original ferrule")
		for suffix in ["__shaft", "__grip"]:
			var current := meshes(club, suffix)
			var before := meshes(original, suffix)
			check(current.size() == 1 and before.size() == 1, id + " retains " + suffix)
			if current.size() == 1 and before.size() == 1:
				check(current[0].mesh == before[0].mesh and current[0].global_transform.is_equal_approx(model_transform(before[0])), id + " original geometry and transform for " + suffix)
		var socket: Node3D = Equipment._find_attachment_marker(fitted)
		if socket == null and wanted == "iron":
			socket = fitted
		var shaft := meshes(club, "__shaft")[0]
		check(socket != null, id + " contains attachment marker")
		if socket != null:
			check(socket.global_position.distance_to(shaft.global_position) < 0.000001, id + " socket position matches shaft")
			check(socket.global_basis.y.normalized().distance_to(shaft.global_basis.y.normalized()) < 0.000001, id + " socket axis matches shaft")
		var textured_roughness := 0
		for head in heads:
			check(bool(head.get_meta("ofg_authored_head", false)), id + " keeps authored finish")
			var source_name := str(head.name).trim_suffix("__head")
			check(item_reference_meshes.has(source_name), id + " preserves source component name")
			if item_reference_meshes.has(source_name):
				var source_mesh: MeshInstance3D = item_reference_meshes[source_name]
				check(head.mesh == source_mesh.mesh, id + " source mesh buffers retained")
				if wanted != "iron":
					check(model_transform(head, fitted).is_equal_approx(model_transform(source_mesh, item_reference)), id + " relative component placement retained")
			for surface in head.mesh.get_surface_count():
				if Equipment.is_decal_mesh(head):
					check_decal(head, surface, id)
					continue
				check_material(head, surface, id)
				var material := head.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and material.roughness_texture != null: textured_roughness += 1
		if id != "persimmon_ghost" and wanted not in ["iron", "wedge"]:
			check(textured_roughness >= min_textured_roughness(), id + " crown and face roughness maps present")
		Equipment.apply_condition(club, 0.25)
		for head in heads:
			for surface in head.mesh.get_surface_count():
				if Equipment.is_decal_mesh(head):
					var paint := head.get_surface_override_material(surface) as BaseMaterial3D
					check(paint != null and is_equal_approx(paint.albedo_color.a, lerpf(Equipment.DECAL_WORN_ALPHA, 1.0, 0.25)), id + " decal paint fades with wear")
					continue
				var material := head.get_surface_override_material(surface) as ShaderMaterial
				check(is_equal_approx(float(material.get_shader_parameter("condition")), 0.25), id + " every component receives wear updates")
		print("CHECKED ", id, ": selected head, all components, original shaft/grip, fitting and PBR/wear")
		club.queue_free()
		original.queue_free()
		item_reference.queue_free()
		await process_frame
		await process_frame
		checked += 1
	check(checked == expected and checked > 0, "entire " + model_type + " catalog covered")
	var first := Equipment.create_club(first_id, 0.2)
	var second := Equipment.create_club(first_id, 1.0)
	Equipment.apply_condition(first, 0.0)
	var first_heads := meshes(first, "__head")
	var second_heads := meshes(second, "__head")
	for i in second_heads.size():
		if Equipment.is_decal_mesh(second_heads[i]):
			continue
		var a := first_heads[i].get_surface_override_material(0) as ShaderMaterial
		var b := second_heads[i].get_surface_override_material(0) as ShaderMaterial
		check(a != b and is_equal_approx(float(b.get_shader_parameter("condition")), 1.0), "wear remains instance-local")
	first.queue_free()
	second.queue_free()
	reference.queue_free()
	await process_frame
	await process_frame
	print(wanted.to_upper(), " HEAD SWAP TEST: ", "PASS" if failures == 0 else "FAIL", " (", checked, " models; ", failures, " failures)")
	quit(0 if failures == 0 else 1)
