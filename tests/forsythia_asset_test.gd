extends SceneTree
## Verify the imported asset through the same transform/batching path as the course.
var failures := 0

func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://forsythia_asset_test_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func run() -> void:
	var inst := preload("res://assets/foliage_bushes/forsythia_02.glb").instantiate()
	var found := ForestPlanter._find_first_mesh_xform(inst)
	var mesh: Mesh = found[0]
	var local: Transform3D = found[1]
	var bounds := local * mesh.get_aabb()
	check(absf(bounds.position.y) < 0.002, "Bush stems must reach their planting point")
	check(bounds.size.y > 1.3 and bounds.size.y < 1.45, "Source height preserved in metres")
	check(bounds.size.x > 1.0 and bounds.size.x < 1.15, "Source canopy width preserved")
	check(mesh.get_surface_count() == 4, "All bark, branches, flowers and buds survive batching")
	var triangles := 0
	var flowers_found := false
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var mat := mesh.surface_get_material(surface) as BaseMaterial3D
		check(mat != null and mat.albedo_texture != null, "Every surface has its source color texture")
		if mat == null or mat.resource_name != "Forsythia_Flower01":
			continue
		flowers_found = true
		check(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Flowers use depth-writing cutouts")
		check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "Petals visible from both sides")
		var image := mat.albedo_texture.get_image()
		if image.is_compressed():
			image.decompress()
		var clear := 0
		var opaque := 0
		for y in range(0, image.get_height(), 16):
			for x in range(0, image.get_width(), 16):
				var alpha := image.get_pixel(x, y).a
				clear += int(alpha < 0.1)
				opaque += int(alpha > 0.9)
		check(clear > 100 and opaque > 100, "PNG retains both transparent background and solid petals")
	check(flowers_found, "Flower material exists")
	check(triangles >= 15000 and triangles <= 30000, "Detailed plant stays within its 30k triangle budget")
	var stage := Node3D.new()
	root.add_child(stage)
	var planted := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.3), Vector3(52, 7, -21))
	VegetationBatches.add_batches(stage, "bush_test", mesh, [planted * local], null, false, 90, 32)
	var batch := stage.get_child(0) as MultiMeshInstance3D
	# The headless dummy renderer does not store MultiMesh instance transforms.
	# Run with a display as well to exercise the GPU-backed batching check.
	if DisplayServer.get_name() != "headless":
		var actual := batch.global_transform * batch.multimesh.get_instance_transform(0)
		check(actual.is_equal_approx(planted * local), "Batch tiling preserves planting, yaw and size")
	print("Forsythia: bounds=", bounds, " triangles=", triangles, " failures=", failures)
	inst.free()
	stage.free()
	quit(0 if failures == 0 else 1)
