extends SceneTree
## Render the catalog's equipped heads with transparent backgrounds and cast shadows.
## Run with a graphics device (not --headless):
## godot --path . --script tools/render_shop_thumbnails.gd
## Optional user arguments: --models=id,id or --review-angles.
## No player save is loaded or written by this asset-generation tool.

const REVIEW := "res://build/shop-thumbnail-review/"
const SIZE := Vector2i(640, 560)
const HEAD_FRAME_FILL := 0.76  # Leave a clear border around the sole and hosel.
const WEDGE_FRAME_FILL := 0.97  # Wedges render closer/bigger than the rest of the catalog.
const SHADOW_SHADER = preload("res://shaders/shadow_catcher.gdshader")
var viewer: ClubViewer3D
var shadow_floor: MeshInstance3D
var shadow_light: DirectionalLight3D


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://shop_thumbnail_render_unused.json")
	call_deferred("run")


func setup_model(id: String) -> bool:
	if viewer != null:
		viewer.free()
	viewer = ClubViewer3D.new()
	viewer.size = SIZE
	root.add_child(viewer)
	if not viewer.show_model(id, 1.0, true):
		push_error("Cannot render shop model: " + id)
		return false
	viewer._spin = false
	viewer._intro = 0.0  # no opening spin-in: it would turn the shot INTRO_YAW off the yaw set below
	viewer.set_process(false)
	viewer._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewer._viewport.msaa_3d = Viewport.MSAA_4X
	viewer._key_light.shadow_enabled = false
	viewer._fill_light.shadow_enabled = false
	# Keep thumbnails tightly framed on the head, including its authored hosel.
	for mesh in viewer._find_meshes(viewer._club, ""):
		if not String(mesh.name).ends_with("__head"):
			mesh.hide()
		else:
			# Thumbnail lighting is independent of the in-game club shadow setting.
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	shadow_floor = MeshInstance3D.new()
	shadow_floor.mesh = PlaneMesh.new()
	shadow_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = SHADOW_SHADER
	shadow_floor.material_override = shadow_material
	viewer._viewport.add_child(shadow_floor)
	# A rear light casts the visible floor shadow toward the camera. Keep
	# the product lighting separate so every face and finish stays readable.
	shadow_light = DirectionalLight3D.new()
	shadow_light.light_energy = 0.05
	shadow_light.light_specular = 0.0
	shadow_light.shadow_enabled = true
	shadow_light.shadow_bias = 0.00005
	shadow_light.shadow_normal_bias = 0.1
	shadow_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	shadow_light.directional_shadow_max_distance = 1.0
	shadow_light.light_angular_distance = 0.0
	viewer._viewport.add_child(shadow_light)
	viewer._cam.far = 1.0
	# A black transparent clear prevents pale RGB from bleeding into shadow alpha.
	viewer._environment.background_color = Color(0, 0, 0, 0)
	viewer._environment.sky = ClubViewer3D._get_equipment_studio_sky()
	viewer._environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	viewer._environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewer._environment.tonemap_exposure = 0.85
	viewer._environment.ambient_light_energy = 0.8
	viewer._key_light.light_energy = 1.2
	viewer._fill_light.light_energy = 0.65
	viewer._light_from_camera = true
	var kind := str(ClubCatalog.model(id).get("type", ""))
	if str(ClubCatalog.model(id).get("silhouette", "")) == "hybrid_iron":
		kind = "iron_set"  # the utility iron is an iron head: show its back like the iron sets
	match kind:
		"iron_set":
			# Back-led view, closer to eye level so the back face reads clearly instead
			# of the crown/top edge.
			viewer._yaw = 0.32
			viewer._pitch = -0.12
		"wedge":
			# View the grooved striking face from above, including the top edge.
			viewer._yaw = 3.5
			viewer._pitch = -0.48
		"putter":
			viewer._yaw = 0.55
			viewer._pitch = -0.5
		"driver", "wood", "hybrid":
			viewer._yaw = 2.45
			viewer._pitch = -0.42
	viewer._update_camera()
	fit_projected_head()
	return true


func fit_projected_head() -> void:
	var points: Array[Vector3] = []
	var ground_y := INF
	for mesh in viewer._find_meshes(viewer._club, "__head"):
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = mesh.global_transform * vertex
				points.append(point)
				ground_y = minf(ground_y, point.y)
	# The transparent receiver sits below every sole vertex. Fit the complete
	# head AND its projected shadow so neither can run into the image borders.
	ground_y -= 0.003
	viewer._key_light.rotation = Vector3(deg_to_rad(-50.0), viewer._yaw - 1.15, 0.0)
	shadow_light.rotation = Vector3(deg_to_rad(-58.0), viewer._yaw + PI + 0.65, 0.0)
	var light_ray := -shadow_light.global_basis.z
	var floor_low := Vector2(INF, INF)
	var floor_high := Vector2(-INF, -INF)
	var shadow_points: Array[Vector3] = []
	for point in points:
		var shadow := point + light_ray * ((ground_y - point.y) / light_ray.y)
		shadow_points.append(shadow)
		floor_low = floor_low.min(Vector2(shadow.x, shadow.z))
		floor_high = floor_high.max(Vector2(shadow.x, shadow.z))
	var floor_midpoint := (floor_low + floor_high) * 0.5
	shadow_floor.position = Vector3(floor_midpoint.x, ground_y, floor_midpoint.y)
	shadow_floor.mesh.size = floor_high - floor_low + Vector2.ONE * 0.08
	points.append_array(shadow_points)
	var right := viewer._cam.global_basis.x
	var up := viewer._cam.global_basis.y
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		var projected := Vector2(point.dot(right), point.dot(up))
		low = low.min(projected)
		high = high.max(projected)
	var midpoint := (low + high) * 0.5
	viewer._cam.global_position += right * (midpoint.x - viewer._cam.global_position.dot(right)) + up * (midpoint.y - viewer._cam.global_position.dot(up))
	var extent := high - low
	var viewport_size := viewer._viewport.size
	var aspect := float(viewport_size.x) / viewport_size.y
	var kind := str(ClubCatalog.model(str(viewer._club.get_meta("ofg_asset_id"))).get("type", ""))
	var frame_fill := WEDGE_FRAME_FILL if kind == "wedge" else HEAD_FRAME_FILL
	viewer._cam.size = maxf(extent.y, extent.x / aspect) / frame_fill


func capture(path: String) -> bool:
	# Give the sky reflection and shader pipelines time to finish before readback.
	for frame in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewer._viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		push_error("Empty shop render: " + path)
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := picture.save_png(path)
	if error != OK:
		push_error("Cannot save shop render: " + path)
		return false
	print("RENDERED ", path)
	return true


func output_path(model: Dictionary) -> String:
	var id := str(model.id)
	match str(model.get("type", "")):
		"iron_set": return EquipmentPreview.IRON_SHOP_PREVIEWS + "ofg_" + id + "_base_back.png"
		"wedge": return EquipmentPreview.WEDGE_SHOP_PREVIEWS + "ofg_" + id + "_base_back.png"
		"putter": return EquipmentPreview.BASE + "ofg_" + id + ".png"
	return EquipmentPreview.SELECTED_HEAD_PREVIEWS + "ofg_" + id + ".png"


func run() -> void:
	root.content_scale_size = SIZE
	root.size = SIZE
	var ids: PackedStringArray = []
	var review := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			ids = arg.trim_prefix("--models=").split(",")
		review = review or arg == "--review-angles"
	if review:
		for id in ["loaner_irons", "loaner_pw", "loaner_putter"]:
			if not setup_model(id):
				quit(1)
				return
			for yaw in [0.4, 1.3, 2.45, 3.5, 4.5, 5.6]:
				viewer._yaw = yaw
				viewer._pitch = -0.4
				viewer._update_camera()
				fit_projected_head()
				if not await capture(REVIEW + "%s_yaw_%.2f.png" % [id, yaw]):
					quit(1)
					return
	else:
		var count := 0
		for model: Dictionary in ClubCatalog.models():
			if not ids.is_empty() and str(model.id) not in ids:
				continue
			if not setup_model(str(model.id)) or not await capture(output_path(model)):
				quit(1)
				return
			count += 1
			if str(model.get("type", "")) == "iron_set":
				viewer._pitch = -0.85
				viewer._update_camera()
				fit_projected_head()
				if not await capture(output_path(model).replace("_back.png", "_top.png")):
					quit(1)
					return
		print("SHOP THUMBNAILS: PASS (", count, " models)")
	viewer.free()
	quit(0)
