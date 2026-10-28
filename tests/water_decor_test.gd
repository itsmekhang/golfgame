extends SceneTree
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://water_decor_test_unused.json")
	call_deferred("run")
func run() -> void:
	var layout := CourseLayout.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var pond := WaterHazard.make_blob(Vector2.ZERO, 20, rng)
	pond.water_level = 3.0
	var creek := WaterHazard.make_creek(Vector2(50,0), Vector2(50,100), 7, rng)
	layout.water_hazards.append(pond)
	layout.water_hazards.append(creek)
	var decor := PropScatter.decorate(layout)
	var count := 0
	for batch in decor.get_children():
		assert(String(batch.name).begins_with("lily_pads_"), "Only lily pads decorate water")
		for i in range(batch.multimesh.instance_count):
			# The dummy headless renderer does not retain MultiMesh transforms.
			if DisplayServer.get_name() != "headless":
				var p: Vector3 = batch.position + batch.multimesh.get_instance_transform(i).origin
				assert(pond.contains(Vector2(p.x,p.z)), "Lily pads float inside the pond")
				assert(is_equal_approx(p.y,3.02), "Lily pads sit at water height")
			count += 1
	assert(count > 0, "Keep the lily pads")
	var creek_decor := PropScatter.decorate(layout,11,creek.bounds)
	assert(creek_decor.get_child_count() == 0, "Creek banks stay clear")
	print("WATER DECOR PASS: ",count," lily pads retained; no shoreline plants")
	decor.free()
	creek_decor.free()
	pond.free()
	creek.free()
	quit()
