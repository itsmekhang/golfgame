extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(-64, -64, 128, 128)
	layout.mask_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	layout.mask_texture = ImageTexture.create_from_image(layout.mask_image)
	layout.sdf_texture = ImageTexture.create_from_image(layout.mask_image)
	var material := StandardMaterial3D.new()
	TurfShells.attach(material, layout)
	assert(material.next_pass == null, "Base terrain still submits distant shells")
	var tile := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(64, 64)
	tile.mesh = mesh
	TurfShells.add_to_tile(tile, material)
	var shell := tile.get_node("TurfShells") as MeshInstance3D
	assert(shell.mesh == tile.mesh, "Shells must reuse terrain geometry")
	assert(shell.layers == PerformanceSettings.DETAIL_LAYER, "Shells must stay out of the minimap")
	assert(shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert(shell.visibility_range_end >= Vector2(32, 32).length() + TurfShells.MAX_DISTANCE)
	assert(shell.visibility_range_end < 90.0, "Far-away shells must be culled")
	var slices := 0
	var slice := shell.material_override
	while slice != null:
		slices += 1
		slice = slice.next_pass
	assert(slices == TurfShells.SHELLS, "Near turf quality changed")
	tile.free()
	print("TURF SHELL CULLING: PASS")
	quit()
