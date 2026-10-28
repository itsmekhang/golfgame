extends SceneTree
## Course Manager screenshots: a throwaway club (never the player's save or courses) on the
## starter course with every facility placed and built to `level`, rooms fitted out and staff
## hired, captured from a few angles and in the cutaway views.
## Run (needs a display): godot --path . --script tests/manager_screenshot.gd -- <out_dir> [level] [golf]
## "golf" walks out onto the course instead and captures the buildings from the golf game.

const DIR := "user://_manager_screenshot/"


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_manager_screenshot_unused.json")
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var level := int(args[1]) if args.size() > 1 else 2
	await process_frame
	var gs: GameState = GameState.current
	gs.autosave = false
	gs.new_game()
	gs.unlocked.append(str(gs.manager_status()["store_id"]))
	gs.cash = 10000000
	gs.buy_course()
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "shot.course.json"
	var c := PaintedCourse.starter("Pinecrest Golf Club")
	var h0: Dictionary = c.holes[0]
	for k in range(2):  # three holes, so the club opens and golfers come
		c.holes.append({"tee": h0["pin"] + Vector2(30 + 40 * k, -20), "pin": h0["tee"] + Vector2(50 + 40 * k, 40), "par": 0, "bends": [], "curve": false})
	c.save(path)
	gs.set_business_course(path)
	# find open rough for each facility, nearest the first tee first
	var tee: Vector2 = c.holes[0]["tee"]
	var placed := {}
	for type in ["clubhouse", "cart_barn", "driving_range", "short_game"]:
		var best := Vector2.INF
		for r in range(60, 280, 10):
			for k in range(24):
				var p := tee + Vector2.from_angle(k * TAU / 24.0) * r
				var rot := FacilityBuilder.default_facing(c, type, p)
				if FacilityBuilder.site_problem(c, placed, type, p, rot) == "":
					best = p
					break
			if best != Vector2.INF:
				break
		if best == Vector2.INF:
			print("[shot] no site for ", type)
			continue
		var rot := FacilityBuilder.default_facing(c, type, best)
		gs.place_facility(type, best, rot)
		placed[type] = {"pos": best, "rot": rot}
		for i in range(level):
			gs.build_facility(type)
	for rm in EconomyConfig.manager_cfg().get("rooms", []):
		for i in range(int(OS.get_environment("SHOT_TIER")) if OS.get_environment("SHOT_TIER") != "" else 2):
			gs.build_room(str(rm["id"]))
	for s in EconomyConfig.manager_cfg().get("staff", []):
		gs.hire_staff(str(s["id"]))
	if args.size() > 2 and args[2] == "golf":
		await _golf_shots(out, level, path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
		quit()
		return
	var mgr: CourseManager = load("res://scenes/course_manager.tscn").instantiate()
	root.add_child(mgr)
	current_scene = mgr
	if not mgr.is_loaded:
		await mgr.loaded  # past the loading screen
	for i in range(30):
		await process_frame
	# the deed's parking lot went down beside the clubhouse; bring it up to the same level
	for i in range(level - 1):
		gs.build_facility("parking_lot")
	for i in range(10):
		await process_frame
	var house: Vector2 = gs.business.placements["clubhouse"]["pos"]
	var house_rot := float(gs.business.placements["clubhouse"]["rot"])
	var hp := Vector3(house.x, mgr.course.height_at(house), house.y)
	var house_node := mgr._facility_node("clubhouse")
	var mid := FacilityBuilder.building_center(house_node) if house_node != null else hp
	var shots := [["overview", hp, 0.6, -40.0, 260.0, FacilityBuilder.View.EXTERIOR],
		["clubhouse", hp, house_rot + PI + 0.5, -28.0, 95.0, FacilityBuilder.View.EXTERIOR],
		["roof_off", mid, house_rot + PI + 0.3, -52.0, 62.0, FacilityBuilder.View.ROOF_OFF],
		["walls_down", mid, house_rot + PI + 0.3, -60.0, 48.0, FacilityBuilder.View.WALLS_DOWN]]
	for t in ["cart_barn", "driving_range", "parking_lot", "short_game"]:
		if gs.business.placements.has(t):
			var q: Vector2 = gs.business.placements[t]["pos"]
			var steep: bool = t == "short_game"  # its turf is flat: look down on it, over any neighbour
			shots.append([t, Vector3(q.x, mgr.course.height_at(q), q.y), float(gs.business.placements[t]["rot"]) + PI + 0.5, -62.0 if steep else -32.0, 58.0 if steep else 80.0, FacilityBuilder.View.EXTERIOR])
	# down at the clubhouse's front: where its base, steps and porch meet the ground
	var front_node := mgr._facility_node("clubhouse")
	if front_node != null:
		var door := mgr._life._front_door(front_node)
		if door != Vector2.INF:
			var at: Vector3 = front_node.global_transform * Vector3(door.x - 6.0, 0.0, door.y - 5.0)
			shots.append(["clubhouse_base", at, house_rot + PI + 0.7, -7.0, 13.0, FacilityBuilder.View.EXTERIOR])
	# down at a plot's edge, where its paving meets the course's ground
	for t in ["parking_lot", "cart_barn"]:
		if gs.business.placements.has(t):
			var q: Vector2 = gs.business.placements[t]["pos"]
			var rot := float(gs.business.placements[t]["rot"])
			var corner := q + (FacilityBuilder.footprint(t) * Vector2(0.5, -0.5) + Vector2(-6.0, 6.0)).rotated(-rot)
			shots.append([t + "_edge", Vector3(corner.x, mgr.course.height_at(corner), corner.y), rot + PI + 0.9, -9.0, 9.0, FacilityBuilder.View.EXTERIOR])
	var house_node2 := mgr._facility_node("clubhouse")
	var boxes: Dictionary = FacilityBuilder.rig(house_node2).get("boxes", {}) if house_node2 != null else {}
	if boxes.has("pro_shop"):
		var sc: Vector2 = (boxes["pro_shop"]["rect"] as Rect2).get_center()
		var shop := house_node2.global_transform * Vector3(sc.x, float(boxes["pro_shop"]["y"]), sc.y)
		shots.append(["pro_shop", shop, house_rot + PI + 0.4, -50.0, 20.0, FacilityBuilder.View.WALLS_DOWN])
		shots.append(["pro_shop_close", shop, house_rot + PI + 0.9, -32.0, 9.0, FacilityBuilder.View.WALLS_DOWN])
	if boxes.has("restaurant"):
		var rc: Vector2 = (boxes["restaurant"]["rect"] as Rect2).get_center()
		var rest := house_node2.global_transform * Vector3(rc.x, float(boxes["restaurant"]["y"]), rc.y)
		shots.append(["restaurant", rest, house_rot + PI - 0.4, -50.0, 22.0, FacilityBuilder.View.WALLS_DOWN])
	if boxes.has("office"):
		var oc: Vector2 = (boxes["office"]["rect"] as Rect2).get_center()
		shots.append(["office", house_node2.global_transform * Vector3(oc.x, float(boxes["office"]["y"]), oc.y), house_rot + 0.6, -40.0, 8.0, FacilityBuilder.View.WALLS_DOWN])
	# the desks and the bar from the customer's side: the computers and the till on them
	if house_node2 != null:
		var spots: Dictionary = FacilityBuilder.rig(house_node2).get("spots", {})
		for room in spots:
			for sp: Dictionary in spots[room]:
				if str(sp["role"]) in ["receptionist", "shop_clerk", "bartender"]:
					var post: Transform3D = house_node2.global_transform * (sp["xf"] as Transform3D)
					var yaw := atan2(post.basis.z.x, post.basis.z.z)
					shots.append(["desk_" + str(sp["role"]), post.origin + Vector3(0, 1.0, 0), yaw + PI, -58.0, 5.5, FacilityBuilder.View.WALLS_DOWN])
					break
		var tub := house_node2.find_child("Batch_jacuzzi", false, false) as MultiMeshInstance3D
		if tub != null and tub.multimesh.instance_count > 0:
			shots.append(["jacuzzi", tub.global_transform * tub.multimesh.get_instance_transform(0).origin, house_rot + PI + 0.9, -38.0, 7.5, FacilityBuilder.View.WALLS_DOWN])
	for room in ["ballroom", "lounge"]:
		if boxes.has(room):
			var bc: Vector2 = (boxes[room]["rect"] as Rect2).get_center()
			shots.append([room, house_node2.global_transform * Vector3(bc.x, float(boxes[room]["y"]), bc.y), house_rot + PI + 0.3, -55.0, 20.0, FacilityBuilder.View.ROOF_OFF])
	if boxes.has("locker_rooms"):
		var lc: Vector2 = (boxes["locker_rooms"]["rect"] as Rect2).get_center()
		var lockers := house_node2.global_transform * Vector3(lc.x, float(boxes["locker_rooms"]["y"]), lc.y)
		shots.append(["lockers", lockers, house_rot + PI + 0.5, -52.0, 16.0, FacilityBuilder.View.WALLS_DOWN])
		shots.append(["lockers_back", lockers, house_rot + 0.35, -42.0, 11.0, FacilityBuilder.View.WALLS_DOWN])
	if boxes.has("spa_fitness"):
		var gc: Vector2 = (boxes["spa_fitness"]["rect"] as Rect2).get_center()
		var gym := house_node2.global_transform * Vector3(gc.x, float(boxes["spa_fitness"]["y"]), gc.y)
		shots.append(["spa", gym, house_rot + PI + 0.4, -48.0, 15.0, FacilityBuilder.View.WALLS_DOWN])
		shots.append(["gym_close", gym + house_node2.global_transform.basis * Vector3(0, 0, 2.5), house_rot + PI - 0.7, -30.0, 8.0, FacilityBuilder.View.WALLS_DOWN])
	var practice := mgr._facility_node("short_game")
	if practice != null and not FacilityBuilder.rig(practice).get("flags", []).is_empty():
		var flag: Transform3D = FacilityBuilder.rig(practice).get("flags")[0]
		shots.append(["practice_flag", practice.global_transform * flag.origin + Vector3(0, 2.1, 0), float(gs.business.placements["short_game"]["rot"]) + PI + 0.7, -6.0, 3.6, FacilityBuilder.View.EXTERIOR])
	if house_node2 != null:
		# out the back: the deck, the steps and the walk to the course; the monument out front
		shots.append(["back_walk", house_node2.global_transform * Vector3(0, 0, 30.0), house_rot + 0.6, -24.0, 34.0, FacilityBuilder.View.EXTERIOR])
		var way: Array = FacilityBuilder.rig(house_node2).get("tee_way", [])
		if not way.is_empty():
			shots.append(["back_steps", house_node2.global_transform * (way[1] as Transform3D).origin, house_rot + 0.9, -18.0, 10.0, FacilityBuilder.View.EXTERIOR])
		# the line of carts behind the clubhouse, and its head by the end of the walk
		var line_slots: Array = mgr._life._line_slots()
		if not line_slots.is_empty():
			var lc := Vector3.ZERO
			for xf: Transform3D in line_slots:
				lc += xf.origin / line_slots.size()
			shots.append(["cart_line", lc, house_rot + 0.7, -40.0, 24.0, FacilityBuilder.View.EXTERIOR])
			shots.append(["cart_line_head", (line_slots[0] as Transform3D).origin, house_rot + 1.3, -22.0, 9.0, FacilityBuilder.View.EXTERIOR])
		var sign: Node3D = FacilityBuilder.rig(house_node2).get("sign")
		if sign != null:
			shots.append(["monument", sign.global_position, house_rot + PI + 0.3, -8.0, 9.0, FacilityBuilder.View.EXTERIOR])
	# the golf ball displays: the three busiest clusters of ball packs, seen from in front
	var cells := {}
	if house_node2 != null:
		for mmi in house_node2.find_children("Batch_BALLPACK_*", "MultiMeshInstance3D", false, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var xf := (mmi as Node3D).global_transform * mm.get_instance_transform(i)
				var cell: Array = cells.get_or_add(Vector2i(floori(xf.origin.x / 1.5), floori(xf.origin.z / 1.5)), [Vector3.ZERO, Vector3.ZERO, 0])
				cell[0] += xf.origin
				cell[1] += -xf.basis.z  # a pack's front faces its -Z
				cell[2] += 1
		var keys := cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return cells[a][2] > cells[b][2])
		for k in range(mini(3, keys.size())):
			var cell: Array = cells[keys[k]]
			var f: Vector3 = cell[1]
			shots.append(["balls_%d" % k, cell[0] / cell[2] - f.normalized() * 1.4 + Vector3(0, 0.5, 0), atan2(f.x, f.z), -32.0, 3.8, FacilityBuilder.View.WALLS_DOWN])
	for i in range(200):  # let the golfers get going
		await process_frame
	mgr._life._new_group(0, false, 0)  # make sure there's a group on foot and one riding
	var seated: ClubLife.Group = mgr._life._new_group(1, false, 1)
	for i in range(30):
		await process_frame
	var walking: Node3D = null
	var riding: Node3D = null
	for g in mgr._life._groups:
		if g.carts.is_empty() and walking == null:
			walking = (g.golfers[0] as ClubLife.Walker).node
		elif not g.carts.is_empty() and riding == null:
			riding = (g.carts[0] as ClubLife.Walker).node
	print("[shot] groups %d, golfers %d, staff %d" % [mgr._life._groups.size(), mgr._life.golfer_count(), mgr._life.staff_count()])
	if walking != null:
		shots.push_front(["golfers", walking, 0.8, -16.0, 7.0, FacilityBuilder.View.EXTERIOR])
		for g in mgr._life._groups:
			if g.carts.is_empty() and (g.golfers[0] as ClubLife.Walker).node == walking:
				for w in g.golfers:
					mgr._life._bag_down(w)  # their bags stood on their legs, as at a shot
		shots.push_front(["bag_down", walking, 2.0, -14.0, 4.5, FacilityBuilder.View.EXTERIOR])
	if riding != null:
		shots.append(["cart", riding, 2.2, -24.0, 12.0, FacilityBuilder.View.EXTERIOR])
	if seated != null and not seated.carts.is_empty():
		shots.push_front(["riders", (seated.carts[0] as ClubLife.Walker).node, 2.6, -18.0, 6.5, FacilityBuilder.View.EXTERIOR])
	var only := OS.get_environment("SHOT_ONLY").split(",", false)  # just these shots, when given
	for s in shots:
		if not only.is_empty() and not only.has(str(s[0])):
			continue
		if s[1] is Node3D:
			s[1] = (s[1] as Node3D).global_position
		mgr._set_view_mode(s[5])
		var cam := mgr.camera
		cam.pivot = s[1]
		cam._goal_pivot = s[1]
		cam.yaw = float(s[2])
		cam._goal_yaw = cam.yaw
		cam.pitch = deg_to_rad(float(s[3]))
		cam._goal_pitch = cam.pitch
		cam.distance = float(s[4])
		cam._goal_distance = cam.distance
		for i in range(40):
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join("mgr_l%d_%s.png" % [level, s[0]]))
		print("[shot] ", s[0])
	mgr.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	quit()


## The club's buildings from the golf game: roof on, walls solid, no staff.
func _golf_shots(out: String, level: int, path: String) -> void:
	GameLaunch.play_custom(path)
	var inst = load("res://scenes/course.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in range(3000):
		await process_frame
		if inst.ball != null and inst.hud != null and inst.active_region.size != Vector2.ZERO and inst._loading_screen == null:
			break
		if i % 10 == 0 and inst._loading_screen != null:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
	var b := GameState.current.business
	for t in b.placements:
		var q: Vector2 = b.placements[t]["pos"]
		var rot := float(b.placements[t]["rot"])
		var front := Vector2(-sin(rot), -cos(rot))
		var side := Vector2(front.y, -front.x)
		# SHOT_NEAR=1: stand right at the plot's edge, eye height, to see the turf against the lawn
		var near := OS.get_environment("SHOT_NEAR") == "1"
		var eye2 := q + front * (FacilityBuilder.footprint(t).y * 0.5 + (4.0 if near else 45.0)) + side * (6.0 if near else 25.0)
		var at := Vector3(q.x, inst.layout.height_at(q.x, q.y) + (1.0 if near else 4.0), q.y)
		inst.camera.frozen = true
		inst.camera.global_position = Vector3(eye2.x, inst.layout.height_at(eye2.x, eye2.y) + (1.7 if near else 9.0), eye2.y)
		inst.camera.look_at(at, Vector3.UP)
		inst.grass_root.focus_position = eye2
		for i in range(90):
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out.path_join("golf_l%d_%s.png" % [level, t]))
		print("[shot] golf ", t)
	inst.queue_free()
	await process_frame
