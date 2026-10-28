extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n):
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func run() -> void:
	root.size = Vector2i(1440,900)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9aaeb7")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-25,0)
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	root.add_child(camera)
	for level in [2,3,4]:
		for tier in [1,2,3]:
			var built := FacilityBuilder.build([{"type":"clubhouse","level":level,"pos":Vector2.ZERO,"rot":0.0,"rooms":{"restaurant":tier}}],func(_p):return 0.0,false,true)
			root.add_child(built)
			var house := built.get_child(0) as Node3D
			var rig := FacilityBuilder.rig(house)
			var part: Node3D = rig["rooms"]["restaurant"]
			var tables := part.find_children("*HIGH_TABLE*","Node3D",true,false)
			var expected := mini(3,tier) if level == 2 else mini(4,tier+1)
			check(tables.size() == expected,"Wrong upgrade table count L%d T%d: %d" % [level,tier,tables.size()])
			var bar_y := 20.25 if level == 2 else 17.6
			var rect: Rect2 = rig["boxes"]["restaurant"]["rect"]
			var aisle_z := bar_y - 1.54
			var aisle := FacilityBuilder.nav_route(house, "restaurant", Vector2(rect.position.x+0.65,aisle_z), Vector2(rect.end.x-0.65,aisle_z))
			check(not aisle.is_empty(),"Restaurant aisle is not walkable")
			for table: Node3D in tables:
				var depth := table.transform.basis.get_scale().x
				var near_edge := table.position.z + depth/2
				check(bar_y - 0.99 - near_edge >= 1.09,"Table blocks service aisle")
			var seats: Array = rig["spots"]["restaurant"].filter(func(s):return s["role"] == "guest_bar")
			var table_seats := seats.filter(func(s):return (s["xf"] as Transform3D).origin.z < bar_y-1.0)
			check(table_seats.size() == expected*4,"High tables lack four usable stool seats")
			for seat: Dictionary in table_seats:
				var at: Vector3 = (seat["xf"] as Transform3D).origin
				check(at.z + 0.258 < bar_y - 0.99 - 1.09,"Stool projects into bar aisle")
				check(at.z - 0.258 > rect.position.y,"Stool projects through window wall")
				var paired := false
				for other: Dictionary in table_seats:
					var pos: Vector3 = (other["xf"] as Transform3D).origin
					if absf(at.x - pos.x) < 0.01 and absf(at.z - pos.z) > 0.1 and absf(at.z - pos.z) < 1.0:
						paired = true
						check(absf(at.z - pos.z) >= 0.81,"Neighboring table stools are too close")
				check(paired,"Table stool has no same-side partner")
			var stool_batch := house.get_node_or_null("Batch_restaurant_stools") as MultiMeshInstance3D
			check(stool_batch != null,"Supplied stool model is missing")
			if stool_batch != null:
				check(stool_batch.multimesh.instance_count == seats.size(),"Bar/table seat count does not match supplied stools")
				var box := stool_batch.multimesh.mesh.get_aabb()
				check(absf(box.size.y - 1.12) < 0.02,"Supplied stool is incorrectly oriented or scaled")
			for appliance in ["range","sink","prep","fridge_a","oven","table"]:
				check(house.get_node_or_null("Batch_kitchen_"+appliance) != null,"Missing supplied kitchen "+appliance)
			if tier >= 2: check(house.get_node_or_null("Batch_kitchen_fridge_b") != null,"Kitchen upgrade lacks its second fridge")
			if tier >= 2:
				check(house.get_node_or_null("Batch_kitchen_storage") != null,"Kitchen upgrade lacks Altesheim storage")
				check(house.get_node_or_null("Batch_kitchen_potwash") != null,"Kitchen upgrade lacks Altesheim wash station")
			if tier >= 3: check(house.get_node_or_null("Batch_kitchen_rack") != null,"Kitchen upgrade lacks Altesheim tray rack")
			var kitchen: Rect2 = rig["boxes"]["restaurant__kitchen"]["rect"]
			for child: Node in house.get_children():
				if child is MultiMeshInstance3D and str(child.name).begins_with("Batch_kitchen_"):
					var fixture := child as MultiMeshInstance3D
					var bounds := fixture.multimesh.mesh.get_aabb()
					for instance in fixture.multimesh.instance_count:
						var xf := fixture.multimesh.get_instance_transform(instance)
						for x in [bounds.position.x,bounds.end.x]:
							for z in [bounds.position.z,bounds.end.z]:
								var point: Vector3 = xf * Vector3(x,0,z)
								check(kitchen.grow(0.06).has_point(Vector2(point.x,point.z)),"Kitchen fixture crosses wall: "+str(child.name))
						if str(child.name) != "Batch_kitchen_table":
							# backed right up to its wall (the models face -Z, so their back is +Z)
							var back: Vector3 = xf * Vector3(bounds.get_center().x,0,bounds.end.z)
							var to_wall := minf(minf(absf(back.x-kitchen.position.x),absf(kitchen.end.x-back.x)),minf(absf(back.z-kitchen.position.y),absf(kitchen.end.y-back.z)))
							check(to_wall <= 0.04,"Kitchen fixture stands off its wall (%.2f m): %s" % [to_wall,child.name])
			# the chefs get from the kitchen's front (the restaurant side) to every post they work
			var center := kitchen.get_center()
			var chefs: Array = rig["spots"]["restaurant"].filter(func(s):return s["role"] == "chef")
			check(chefs.size() == 3,"Kitchen lacks its three chef posts")
			for chef: Dictionary in chefs:
				var post: Vector3 = (chef["xf"] as Transform3D).origin
				var path := FacilityBuilder.nav_route(house,"restaurant__kitchen",Vector2(center.x,kitchen.position.y+0.8),Vector2(post.x,post.z))
				check(not path.is_empty(),"Kitchen appliances block the way to a chef post at %s" % post)
			print("RESTAURANT L",level," T",tier," tables=",tables.size()," table seats=",table_seats.size())
			if level == 4 and tier in [1,3]:
				FacilityBuilder.set_view(built,FacilityBuilder.View.ROOF_OFF)
				camera.position = Vector3(3,14,27)
				camera.look_at(Vector3(14,0.8,16.7))
				for i in range(10): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/restaurant_high_tables_t%d.png" % tier)
			if level == 4 and tier == 3:
				FacilityBuilder.set_view(built,FacilityBuilder.View.WALLS_DOWN)
				camera.size = 12
				camera.position = Vector3(20,13,17)
				camera.look_at(Vector3(11,1.0,25))
				for i in range(10): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/kitchen_supplied_assets.png")
			built.queue_free()
			await process_frame
	print("RESTAURANT HIGH TABLES: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
