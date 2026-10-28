extends SceneTree

var failed := false

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func run() -> void:
	for level in range(1, 5):
		for tier in range(1, 4):
			var facilities := FacilityBuilder.build([{"type": "clubhouse", "level": level, "pos": Vector2.ZERO, "rooms": {"pro_shop": tier}}], func(_p: Vector2) -> float: return 0.0, false, true)
			var house := facilities.get_child(0)
			check(house.get_node_or_null("Batch_mannequin_m") != null, "Male mannequin missing")
			check(house.get_node_or_null("Batch_mannequin_f") != null, "Female mannequin missing")
			var shirts := 0
			for child in house.get_children():
				if str(child.name).begins_with("Batch_SHIRT_"):
					shirts += child.multimesh.instance_count
					check(child.multimesh.mesh.get_aabb().size.y > .84, "Hanging shirt lost its mesh or scale")
			check(shirts >= 6, "Hanging shirt and polo display missing")
			for kind in ["SPORT", "CANVAS", "ADIDAS", "TRAINER", "NIKE", "CLASSIC", "KNIT"]:
				var shoe: MultiMeshInstance3D = house.get_node_or_null("Batch_SHOE_" + kind)
				check(shoe != null, "Shoe style missing: " + kind)
				if shoe != null:
					var mesh := shoe.multimesh.mesh
					check(mesh.get_aabb().size.x < .38, "Shoe pair exceeds its shelf")
					for surface in range(mesh.get_surface_count()):
						check(mesh.surface_get_material(surface).albedo_texture != null, "Shoe has no embedded texture")
			for child in house.get_children():
				check(not str(child.name).begins_with("Batch_bag_stand"), "Legged bag remains in pro shop")
			var club_count: int = FacilityBuilder.rig(house)["clubs"].size()
			check(club_count >= 24, "Club racks or filled bags missing")
			var room: MeshInstance3D = FacilityBuilder.rig(house)["rooms"]["pro_shop"]
			var carpet := false
			for i in range(room.mesh.get_surface_count()):
				var material := room.mesh.surface_get_material(i)
				check(material.resource_name != "patio_brick", "Brick rug remains in pro shop")
				carpet = carpet or material.resource_name == "carpet"
			if tier >= 2:
				check(carpet, "Carpet missing from upgraded shop")
			facilities.free()
	print("PRO SHOP: ", "FAIL" if failed else "PASS", " (all four clubhouse levels, all three shop tiers)")
	if failed or not "--preview" in OS.get_cmdline_user_args():
		quit(1 if failed else 0)
		return
	root.size = Vector2i(1500, 1100)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("aabec8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e0e8f0")
	env.ambient_light_energy = .65
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_energy = .9
	sun.shadow_enabled = true
	world.add_child(sun)
	var facilities := FacilityBuilder.build([{"type": "clubhouse", "level": 4, "pos": Vector2.ZERO, "rooms": {"pro_shop": 3,"office":3,"restaurant":3,"ballroom":3,"members_lounge":3}}], func(_p: Vector2) -> float: return 0.0, false, true)
	world.add_child(facilities)
	while not FacilityBuilder.fill_clubs(facilities.get_child(0), 2):
		await process_frame
	FacilityBuilder.set_view(facilities, FacilityBuilder.View.WALLS_DOWN)
	var box: Dictionary = FacilityBuilder.rig(facilities.get_child(0))["boxes"]["pro_shop"]
	var rect: Rect2 = box["rect"]
	var center := Vector3(rect.get_center().x, 1.0, rect.get_center().y)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(rect.size.x, rect.size.y) * 1.2
	camera.position = center + Vector3(8, 8, 6)
	camera.look_at(center)
	for i in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/pro_shop_game.png")
	for room_id in ["office","restaurant","ballroom"]:
		var room_box: Dictionary = FacilityBuilder.rig(facilities.get_child(0))["boxes"].get(room_id,{})
		if room_box.is_empty(): continue
		var room_rect: Rect2 = room_box["rect"]
		var room_center := Vector3(room_rect.get_center().x,float(room_box["y"])+1,room_rect.get_center().y)
		camera.size=maxf(room_rect.size.x,room_rect.size.y)*1.3
		camera.position=room_center+Vector3(3,12,7)
		camera.look_at(room_center)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/Codex/2026-10-23/ths/outputs/pro_shop/"+room_id+"_layout.png")
	print("PRO SHOP PREVIEW SAVED")
	quit()
