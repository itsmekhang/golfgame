extends "res://tools/render_shop_thumbnails.gd"
## GPU regression check: mint condition shading must match the imported skin.
## Also validates the loaded shop PNGs and captures the real shop cards for review.

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func read_view() -> Image:
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	return viewer._viewport.get_texture().get_image()


func compare_skin(id: String) -> void:
	if not setup_model(id):
		check(false, "Cannot load skin " + id)
		return
	var shaded := await read_view()
	for mesh in viewer._find_meshes(viewer._club, "__head"):
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, null)
	var imported := await read_view()
	var total_error := 0.0
	var samples := 0
	for y in range(0, imported.get_height(), 4):
		for x in range(0, imported.get_width(), 4):
			var expected := imported.get_pixel(x, y)
			if expected.a < 0.98:
				continue
			var actual := shaded.get_pixel(x, y)
			total_error += (absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b)) / 3.0
			samples += 1
	var error := total_error / maxf(samples, 1)
	check(samples > 500 and error < 0.035, "%s condition shader differs from imported skin (mean error %.5f)" % [id, error])
	print("SKIN_RENDER ", id, " error=", snappedf(error, 0.00001))


func check_thumbnail(id: String) -> void:
	var texture := EquipmentPreview.get_texture(id)
	check(texture != null, "Missing thumbnail " + id)
	if texture == null:
		return
	var picture := texture.get_image()
	if picture.is_compressed():
		picture.decompress()
	check(picture.get_pixel(0, 0).a < 0.01, "Thumbnail background must be transparent: " + id)
	var opaque := 0
	var brightness := 0.0
	var shadow_pixels := 0
	var low := picture.get_size()
	var high := Vector2i.ZERO
	for y in range(0, picture.get_height(), 4):
		for x in range(0, picture.get_width(), 4):
			var pixel := picture.get_pixel(x, y)
			if pixel.a > 0.01:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
			if pixel.a > 0.98:
				opaque += 1
				brightness += (pixel.r + pixel.g + pixel.b) / 3.0
			elif pixel.a > 0.03 and pixel.a < 0.9 and maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.1:
				shadow_pixels += 1
	var margin := Vector2i(Vector2(picture.get_size()) * 0.10)
	check(low.x >= margin.x and low.y >= margin.y and high.x < picture.get_width() - margin.x and high.y < picture.get_height() - margin.y, "Thumbnail head and shadow must have padding on every edge: " + id)
	check(shadow_pixels > 50, "Thumbnail must contain a visible transparent cast shadow: " + id)
	check(opaque > 500, "Thumbnail has too little visible geometry: " + id)
	check(brightness / maxf(opaque, 1) < 0.94, "Thumbnail is washed out: " + id)


func snap(path: String) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "Cannot save " + path)


func run() -> void:
	var review_output := REVIEW
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="):
			review_output = arg.trim_prefix("--review-output=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(review_output)
	root.content_scale_size = SIZE
	root.size = SIZE
	var skins := 0
	for model: Dictionary in ClubCatalog.models():
		check_thumbnail(str(model.id))
		if str(model.get("type", "")) in ["iron_set", "wedge"]:
			await compare_skin(str(model.id))
			skins += 1
	if viewer != null:
		viewer.free()
		viewer = null
	root.content_scale_size = Vector2i(1280, 960)
	root.size = Vector2i(1280, 960)
	var backdrop := ColorRect.new()
	backdrop.color = HubMenu.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var hub := HubMenu.new()
	root.add_child(hub)
	var models := ClubCatalog.models()
	for page in range(ceili(models.size() / 12.0)):
		var grid := Control.new()
		root.add_child(grid)
		for index in range(page * 12, mini((page + 1) * 12, models.size())):
			var local_index := index % 12
			var model: Dictionary = models[index]
			var cell := VBoxContainer.new()
			cell.position = Vector2(24 + local_index % 4 * 314, 24 + local_index / 4 * 310)
			grid.add_child(cell)
			var label := Label.new()
			label.text = str(model.name)
			label.add_theme_font_size_override("font_size", 16)
			label.add_theme_color_override("font_color", HubMenu.INK)
			cell.add_child(label)
			hub._silhouette(cell, model, 1.0, Vector2(286, 252))
		await snap(review_output + "catalog_%d.png" % (page + 1))
		grid.free()
	# Use private unsaved store stock to exercise the actual iron listing cards.
	var listings: Array = []
	for model: Dictionary in models:
		if str(model.get("type", "")) == "iron_set":
			listings.append({"id": "review_" + str(model.id), "model_id": str(model.id), "condition": 1.0, "price": 50, "seller": "", "reserved": false})
	GameState.current.stores["goodwill"]["listings"] = listings
	hub.open("shop")
	await snap(review_output + "iron_shop.png")
	print("SHOP RENDER CHECK: ", "PASS" if failures == 0 else "FAIL", " (", models.size(), " thumbnails, ", skins, " skin comparisons; ", failures, " failures)")
	quit(0 if failures == 0 else 1)
