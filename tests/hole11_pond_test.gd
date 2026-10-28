extends SceneTree
var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://hole11_pond_test_unused.json")
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ",label)
func closest(p: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best := polygon[0]
	for i in range(polygon.size()):
		var q := Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()])
		if p.distance_squared_to(q) < p.distance_squared_to(best): best = q
	return best
func run() -> void:
	var layout := CourseBuilder.build(7)
	var pond: WaterHazard
	var creek: WaterHazard
	for w: WaterHazard in layout.water_hazards:
		if w.hazard_name == "White Pond": pond = w
		if w.hazard_name == "White Creek": creek = w
	check(pond != null and creek != null,"Pond and creek exist")
	if pond == null or creek == null: quit(1); return
	check(not Geometry2D.triangulate_polygon(pond.polygon).is_empty(),"Pond outline renders")
	check(Geometry2D.intersect_polygons(pond.polygon,creek.polygon).is_empty(),"Pond is separate from creek")
	var green := layout.greens[10]
	var min_green := INF
	var max_green := 0.0
	for degrees in range(-165,-49,5):
		var dir := Vector2.from_angle(deg_to_rad(degrees)+green.radial_rotation)
		var p := green.center+dir*green.radius_at(dir.angle())
		p -= dir*green.signed_distance(p)
		var q := closest(p,pond.polygon)
		var gap := p.distance_to(q)
		min_green = minf(min_green,gap)
		max_green = maxf(max_green,gap)
		check(gap > 0.8 and gap < 4.0,"Narrow fringe along left green at %d degrees (%.2f m)" % [degrees,gap])
		check(layout.hazard_at(p.lerp(q,.5)) == null,"Green-pond bank is playable")
	var min_pond_creek := INF
	var bank := Vector2.ZERO
	for p in pond.polygon:
		var q := closest(p,creek.polygon)
		if p.distance_to(q) < min_pond_creek:
			min_pond_creek = p.distance_to(q)
			bank = p.lerp(q,.5)
	check(min_pond_creek > 0.75 and min_pond_creek < 1.25,"Narrow pond-creek dam (%.2f m)" % min_pond_creek)
	check(layout.hazard_at(bank) == null,"Pond and creek retain a dry divider")
	check(layout.height_at(bank.x,bank.y) > minf(pond.water_level,creek.water_level_at(bank)),"Bank is above water")
	var min_back := INF
	for p in creek.polygon: min_back = minf(min_back,green.signed_distance(p))
	check(min_back > 0.8 and min_back < 4.0,"Thin green-creek bank (%.2f m)" % min_back)
	var hull := Geometry2D.convex_hull(pond.polygon)
	var inset := absf(Excavation.signed_area(hull))-pond.area_m2()
	check(inset > 35.0,"Kidney has an inward-curving shoreline")
	if DisplayServer.get_name() != "headless": await check_bank_material(layout,bank,pond,green)
	print("Gaps: green-pond ",min_green,"..",max_green," pond-creek ",min_pond_creek," green-creek ",min_back,"; kidney inset ",inset)
	print("HOLE 11 POND: ","PASS" if failures == 0 else "FAIL")
	for w in layout.water_hazards: w.free()
	for b in layout.bunkers: b.free()
	quit(0 if failures == 0 else 1)

func check_bank_material(layout: CourseLayout, bank: Vector2, pond: WaterHazard, green: GreenArea) -> void:
	layout.bounds = pond.bounds.merge(green.bounds).grow(10.0)
	layout.build_cache()
	layout.build_feature_mask()
	var mat := TerrainBuilder.terrain_material(layout)
	check(mat.get_shader_parameter("greenside_bank_enabled") == true,"First-cut bank material enabled")
	var texture := Image.create(2,2,false,Image.FORMAT_RGB8)
	texture.fill(Color.RED)
	mat.set_shader_parameter("first_cut_texture",ImageTexture.create_from_image(texture))
	mat.set_shader_parameter("first_cut_tint",Color.WHITE)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,768)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	viewport.add_child(env)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24,24)
	mesh.mesh = plane
	mesh.position = Vector3(bank.x,0,bank.y)
	mesh.material_override = mat
	viewport.add_child(mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	viewport.add_child(camera)
	camera.position = Vector3(bank.x,50,bank.y)
	camera.look_at(Vector3(bank.x,0,bank.y),Vector3(0,0,-1))
	for frame in range(10): await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.save_png("res://build/hole11-dam-material-check.png")
	var color := pixels.get_pixel(384,384)
	print("Bank test pixel ",color)
	check(color.r > color.g+0.2 and color.r > color.b+0.2,"Narrow dam visibly uses first-cut grass")
