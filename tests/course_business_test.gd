extends SceneTree
## Golf course manager: the unlock gate, placing vs building facilities, clubhouse rooms and
## their tiers, staff, the money model, day roll-over, save round-trip (and saves from before
## rooms), time-away earnings, every building model at every level, furnished interiors, the
## cutaway views and the graded building plots.
## Run: godot --headless --path . --script tests/course_business_test.gd

const DIR := "user://_course_business_test/"
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://course_business_test_unused.json")
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)


func run() -> void:
	var gs := GameState.new()
	gs.autosave = false
	gs.save_path = "user://course_business_test_unused.json"
	gs.new_game()
	var price := int(gs.manager_status()["price"])

	# ---- the gate: proven golfer first, then the money
	check(not gs.manager_status()["owned"], "Starts without a course")
	gs.cash = price * 10
	check(not gs.buy_course()["ok"], "Deed refused before the top store is unlocked")
	gs.unlocked.append(str(gs.manager_status()["store_id"]))
	gs.cash = price - 1
	check(not gs.buy_course()["ok"], "Deed refused when the wallet is short")
	gs.cash = price + 600
	check(gs.buy_course()["ok"], "Deed sold to an unlocked golfer with the cash")
	check(gs.cash == 600 and gs.business.owned, "Deed price taken, course owned")
	check(gs.business.closed_reason() != "", "Closed until a course is chosen")

	# ---- a three-hole Studio course with a clubhouse and cart barn placed
	DirAccess.make_dir_recursive_absolute(DIR)
	var c := PaintedCourse.starter("Business Test")
	var h0: Dictionary = c.holes[0]
	for k in range(2):
		c.holes.append({"tee": h0["tee"] + Vector2(60 * (k + 1), 0), "pin": h0["pin"] + Vector2(60 * (k + 1), 0), "par": 0, "bends": [], "curve": false})
	var path := DIR + "business_test.course.json"
	check(c.save(path) == OK, "Course saved")
	check(not gs.place_facility("clubhouse", Vector2(-200, 200), 0.3)["ok"], "Nothing placed before a course is chosen")
	check(gs.set_business_course(path)["ok"], "Course chosen")
	check(gs.business.holes == 3, "Hole count read from the course file")
	check(gs.place_facility("clubhouse", Vector2(-200, 200), 0.3)["ok"] and gs.place_facility("cart_barn", Vector2(-100, 200), 0.0)["ok"], "Facilities placed on the club's course")
	check(gs.business.closed_reason().contains("clubhouse"), "Still closed: clubhouse placed but not built")

	# ---- building: placed first, then paid for
	check(not gs.build_facility("driving_range")["ok"], "Can't build what isn't placed on the course")
	var house_cost := gs.business.next_cost("clubhouse")
	check(gs.build_facility("clubhouse")["ok"] and gs.business.level("clubhouse") == 1, "Clubhouse built")
	check(gs.cash == 600 - house_cost, "Clubhouse cost taken")
	check(gs.business.level_name("clubhouse", 1) == "Serviceable" and gs.business.max_level("clubhouse") == 4, "Four clubhouse levels, named")
	check(not gs.business.rates()["open"], "Waits for manual opening")
	check(gs.set_course_open(true)["ok"], "Owner can open the course")
	check(gs.business.closed_reason() == "", "Open after owner clicks open")

	# ---- rooms: fitted out inside the clubhouse, a tier at a time, opening with its levels
	gs.cash = 0
	check(not gs.build_room("pro_shop")["ok"], "Can't fit out what you can't afford")
	gs.cash = 5000
	check(not gs.build_room("restaurant")["ok"] and gs.business.room_note("restaurant").contains("Expanded"), "The restaurant waits for the Expanded clubhouse")
	check(gs.build_room("pro_shop")["ok"] and gs.business.room_tier("pro_shop") == 1, "Pro shop fitted out")
	check(gs.business.tier_name("pro_shop", 1) == "Small Kiosk", "Tier named")
	check(gs.business.room_note("pro_shop").begins_with("Needs"), "Pro shop idle without a clerk")
	check(gs.business.workplace_note("shop_clerk") == "" and gs.business.workplace_note("chef") != "", "Staff know where they would work")
	var r0 := gs.business.rates()
	check(r0["open"] and r0["golfers"] > 0.0 and r0["shop"] == 0.0, "Golfers come, the unstaffed shop sells nothing")
	check(gs.hire_staff("shop_clerk")["ok"], "Clerk hired")
	var r1 := gs.business.rates()
	check(r1["shop"] > 0.0 and r1["revenue"] > r0["revenue"] and r1["wages"] > r0["wages"], "Staffed shop sells; wages show up")
	gs.cash = 50000
	check(gs.build_facility("clubhouse")["ok"] and gs.build_room("restaurant")["ok"] and gs.build_room("restaurant")["ok"], "Expanded clubhouse; restaurant up to the sports grill")
	check(gs.business.room_tier("restaurant") == 2 and gs.business.rates()["restaurant"] == 0.0, "No chef, no meals")
	gs.hire_staff("chef")
	var r2 := gs.business.rates()
	gs.hire_staff("waiter")
	check(r2["restaurant"] > 0.0 and gs.business.rates()["restaurant"] > r2["restaurant"], "The kitchen serves; a server adds to it")
	check(not gs.build_room("ballroom")["ok"], "Ballroom waits for the Prestige clubhouse")
	gs.build_facility("cart_barn")
	var r3 := gs.business.rates()
	gs.hire_staff("cart_attendant")
	check(r3["carts"] > 0.0 and gs.business.rates()["carts"] > r3["carts"], "Carts rent without an attendant; one rents more")
	for i in range(int(EconomyConfig.staff_role("marshal").get("max", 3))):
		gs.hire_staff("marshal")
	check(not gs.hire_staff("marshal")["ok"], "Staff capped per role")

	# ---- price: a sky-high fee chases golfers away
	gs.set_green_fee(gs.business.clamp_fee(1000))
	var dear := gs.business.rates()
	gs.set_green_fee(3)
	check(dear["golfers"] < gs.business.rates()["golfers"], "Higher fee, fewer golfers")

	# ---- condition follows the greenskeepers; days close into the ledger
	gs.hire_staff("greenskeeper")
	var before_cond := gs.business.condition
	var day_len := float(EconomyConfig.manager_cfg().get("open_hours_per_day", 12))
	var net := gs.business.advance(day_len + 0.5)
	check(gs.business.days.size() == 1 and int(gs.business.days[0]["day"]) == 1, "A full day closes into the ledger")
	check(gs.business.condition > before_cond, "Greenskeeper improves the turf")
	var booked := float(gs.business.days[0]["revenue"]) - float(gs.business.days[0]["costs"]) + float(gs.business.today["revenue"]) - float(gs.business.today["costs"])
	check(absf(booked - net) < 0.01, "Books add up to the net (%.2f vs %.2f)" % [booked, net])

	# ---- real time to dollars
	var cash0 := gs.cash
	var per_hour := float(EconomyConfig.manager_cfg().get("real_seconds_per_hour", 240))
	var expect: float = gs.business.rates()["net"] * 3.0
	var moved := gs._run_business(per_hour * 3.0, 1.0)
	check(gs.cash - cash0 == moved and absf(moved - expect) < 2.0, "Three business hours pay about 3x the hourly net (%d vs %.1f)" % [moved, expect])
	gs.cash = 0
	var losing := CourseBusiness.from_dict(gs.business.to_dict())
	losing.green_fee = 25
	gs.business = losing
	gs._run_business(per_hour * 2.0, 1.0)
	check(gs.cash >= 0, "Wallet never goes negative")
	gs.set_green_fee(3)

	# ---- the testing wallet: always full, the real balance set aside and saved
	gs.cash = 777
	gs.set_unlimited_money(true)
	check(gs.cash == GameState.TEST_MONEY and int(gs.to_dict()["cash"]) == 777, "Unlimited money: full wallet, the save keeps the real balance")
	gs.cash -= 5000
	gs._process(0.0)
	check(gs.cash == GameState.TEST_MONEY, "Unlimited money tops itself back up")
	gs.set_unlimited_money(false)
	check(gs.cash == 777 and not gs.unlimited_money, "Unlimited money off: the real balance is back")

	# ---- save round trip and time away
	gs.cash = 1000
	var d := gs.to_dict()
	var b2 := CourseBusiness.from_dict(d["business"])
	check(b2.owned and b2.course_path == path and b2.level("clubhouse") == 2 and b2.heads("shop_clerk") == 1 and b2.green_fee == 3, "Business survives the save")
	check(b2.room_tier("pro_shop") == 1 and b2.room_tier("restaurant") == 2, "Rooms survive the save")
	check(b2.placements.has("clubhouse") and is_equal_approx(float(b2.placements["clubhouse"]["rot"]), 0.3) and (b2.placements["cart_barn"]["pos"] as Vector2).is_equal_approx(Vector2(-100, 200)), "Placements survive the save")
	var before_rooms := CourseBusiness.from_dict({"owned": true, "built": {"clubhouse": 2, "pro_shop": 3, "restaurant": 1}, "placements": {"pro_shop": [1, 2, 0]}})
	check(before_rooms.level("clubhouse") == 2 and before_rooms.room_tier("pro_shop") == 3 and before_rooms.room_tier("restaurant") == 1 and not before_rooms.placements.has("pro_shop"), "A save from before rooms: the old pro shop and restaurant become clubhouse rooms")
	d["saved_at"] = int(Time.get_unix_time_from_system()) - 3600
	var gs2 := GameState.new()
	gs2.autosave = false
	gs2._apply(gs2._migrate(d.duplicate(true)))
	var away_net := float(gs2.offline_report.get("net", 0))
	var full_hour: float = b2.rates()["net"] * (3600.0 / per_hour)
	check(not gs2.offline_report.is_empty() and away_net > 0.0 and away_net < full_hour * 0.6, "An hour away earns a reduced share (%.0f of %.0f)" % [away_net, full_hour])
	d["saved_at"] = int(Time.get_unix_time_from_system()) - 86400 * 30
	var gs3 := GameState.new()
	gs3.autosave = false
	gs3._apply(gs3._migrate(d.duplicate(true)))
	var cap_h := float(EconomyConfig.manager_cfg().get("offline", {}).get("cap_hours", 4))
	check(float(gs3.offline_report.get("net", 0)) <= full_hour * cap_h * 0.3 + 5.0, "Time away is capped")
	var old := gs.to_dict()
	old.erase("business")
	var gs4 := GameState.new()
	gs4.autosave = false
	gs4._apply(gs4._migrate(old))
	check(not gs4.business.owned, "Old saves load without a course")

	# ---- another course starts its own club; returning restores the previous club
	var c2 := PaintedCourse.starter("Business Test Two")
	var path2 := DIR + "business_test_two.course.json"
	c2.save(path2)
	gs.set_business_course(path2)
	check(gs.business.placements.is_empty() and gs.business.level("clubhouse") == 0, "New course: its own facilities and upgrades")
	# the parking lot: the deed's gravel lot, and parking capping the course
	check(gs.business.level("parking_lot") == 1 and is_equal_approx(gs.business.parking_cap(), 24 * 0.35), "The deed comes with a 24-space lot (8.4 golfers an hour), counted before it's set down")
	gs.business.auto_parked = true
	var cap_street := gs.business.parking_cap()
	check(gs.place_facility("parking_lot", Vector2(-200, 120), 0.3)["ok"] and gs.business.parking_cap() > cap_street and is_equal_approx(gs.business.parking_cap(), 24 * 0.35), "Roadside parking without it; the placed lot's 24 spaces")
	var pr := gs.business.rates()
	check(float(pr["capacity"]) <= float(pr["parking_cap"]) + 1e-4, "The course takes no more golfers than can park")
	gs.unplace_facility("parking_lot")
	gs.unplace_facility("clubhouse")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path2))

	# ---- every building model at every level, plus the footprint helpers
	var flat := func(_p: Vector2) -> float: return 1.5
	for type in FacilityBuilder.FOOTPRINT:
		for lv in range(5):
			var n := FacilityBuilder.build([{"type": type, "pos": Vector2(10, 20), "rot": 0.7, "level": lv, "name": "Test"}], flat, true)
			var fac := n.get_child(0)
			check(n.get_child_count() == 1 and fac.get_child_count() >= 3, "%s level %d builds" % [type, lv])
			if lv > 0:
				var r := FacilityBuilder.rig(fac)
				check(fac.get_node_or_null("Collider") != null and fac.get_node_or_null("Model") != null, "%s level %d: model and collider" % [type, lv])
				check((r["groups"] as Dictionary).has("BASE") and (r["rooms"] as Dictionary).is_empty(), "%s level %d: geometry groups, no interiors in the golf game" % [type, lv])
				# the short game area and the plainer ranges are bare turf and mats: nothing to batch
				if type not in ["short_game", "driving_range"]:
					check(fac.find_children("Batch_*", "MultiMeshInstance3D", false, false).size() > 0, "%s level %d: plantings and carts batched" % [type, lv])
				check(FacilityBuilder.paving(type, lv) != null, "%s level %d: paving mask" % [type, lv])
				if type == "parking_lot":
					var lot := FacilityBuilder.build([{"type": type, "pos": Vector2(10, 20), "rot": 0.7, "level": lv, "name": "Test"}], flat, false, true)
					var lf := lot.get_child(0) as Node3D
					var stalls: Array = FacilityBuilder.rig(lf)["stalls"]
					var spaces: int = (EconomyConfig.facility(type)["levels"] as Array)[lv - 1]["spaces"]
					FacilityBuilder.park(lf, 0.5)
					var parked := 0
					for mmi in lf.get_children():
						if String(mmi.name).begins_with("Batch_parked_"):
							parked += (mmi as MultiMeshInstance3D).multimesh.instance_count
					var ada := FacilityBuilder.ada_stalls(FacilityBuilder.rig(lf))
					var open := spaces - ada.size()
					var in_ada := false
					for i in (FacilityBuilder.rig(lf).get("parked", []) as Array):
						in_ada = in_ada or ada.has(i)
					check(stalls.size() == spaces and ada.size() == [1, 2, 3, 4][lv - 1] and not in_ada, "parking lot level %d: %d stalls (%d spaces), %d accessible (none parked in)" % [lv, stalls.size(), spaces, ada.size()])
					check(parked == mini(roundi(open * 0.5), open - FacilityBuilder.VISITOR_ROOM), "parking lot level %d: half the %d non-accessible stalls parked in, leaving room for arriving golfers (%d)" % [lv, open, parked])
					lot.free()
				if type == "clubhouse":
					check(fac.find_children("Batch_bush_*", "MultiMeshInstance3D", false, false).size() > 0, "clubhouse level %d: shrubs are the woodland bushes" % lv)
			n.free()
	# Course Manager: the clubhouse furnished at its room tiers, real clubs in the shop, the cutaway
	var rooms := {"pro_shop": 2, "lobby": 1, "restaurant": 2, "office": 3}
	var house_root := FacilityBuilder.build([{"type": "clubhouse", "pos": Vector2.ZERO, "rot": 0.0, "level": 2, "name": "Test", "rooms": rooms}], flat, false, true)
	root.add_child(house_root)
	var house := house_root.get_child(0) as Node3D
	var hr := FacilityBuilder.rig(house)
	check((hr["rooms"] as Dictionary).has_all(rooms.keys()) and not (hr["rooms"] as Dictionary).has("locker_rooms"), "Furnished rooms are the built ones, at their tiers")
	check((hr["boxes"] as Dictionary).has("pro_shop") and (hr["boxes"] as Dictionary).has("locker_rooms"), "Every room floor is known, built or not")
	check((hr["spots"] as Dictionary).has("pro_shop") and not (hr["clubs"] as Array).is_empty(), "Staff spots and club stands in the shop")
	var shop_box: Dictionary = hr["boxes"]["pro_shop"]
	var shop_mid: Vector2 = (shop_box["rect"] as Rect2).get_center()
	check(FacilityBuilder.room_at(house, house.global_transform * Vector3(shop_mid.x, 1.0, shop_mid.y)) == "pro_shop", "A point in the shop picks the shop")
	var stands := (hr["clubs"] as Array).size()
	var guard := 0
	while not FacilityBuilder.fill_clubs(house, 2) and guard < 40:
		guard += 1
	var club_meshes := house.get_node("Clubs").find_children("*", "MultiMeshInstance3D", false, false)
	var shown := 0
	for mmi: MultiMeshInstance3D in club_meshes:
		shown = maxi(shown, mmi.multimesh.instance_count)
	check(stands > 0 and not club_meshes.is_empty() and shown > 0, "Real clubs stand in the shop (%d stands, %d club meshes)" % [stands, club_meshes.size()])
	FacilityBuilder.set_view(house_root, FacilityBuilder.View.WALLS_DOWN)
	check(not (hr["groups"]["ROOF"][0] as Node3D).visible and not (hr["groups"]["WALLS_HIGH"][0] as Node3D).visible, "Walls down: roof and upper walls hidden")
	FacilityBuilder.set_view(house_root, FacilityBuilder.View.EXTERIOR)
	check((hr["groups"]["ROOF"][0] as Node3D).visible, "Exterior: roof back on")
	house_root.free()
	# the club's sign: its name, and what kind of club it is below (or above) it
	var signs := {"Pinehurst Country Club": ["Pinehurst", "Country Club", ""], "Augusta National Golf Club": ["Augusta", "National Golf Club", ""],
		"Pebble Beach Golf Links": ["Pebble Beach", "Golf Links", ""], "Riviera CC": ["Riviera", "Country Club", ""],
		"Pinehurst Resort & Country Club": ["Pinehurst", "Resort & Country Club", ""], "The Golf Club of Georgia": ["Georgia", "", "The Golf Club of"],
		"The Country Club": ["The Country Club", "", ""], "The Olympic Club": ["The Olympic Club", "", ""], "Whistling Straits": ["Whistling Straits", "", ""],
		"Augusta National": ["Augusta National", "", ""], "Golf Club": ["Golf Club", "", ""], "Pinecrest Golf Club": ["Pinecrest", "Golf Club", ""]}
	for full in signs:
		var parts := FacilityBuilder.club_name_parts(full)
		var want: Array = signs[full]
		check(parts["name"] == want[0] and parts["under"] == want[1] and parts["over"] == want[2], "Sign for %s: %s" % [full, str(parts)])
	# grading: the plot is flat at its average height and eases back into the course
	var g := PaintedCourse.starter("Grade Test")
	var spot := Vector2(-150, 150)
	FacilityBuilder.grade(g, {"clubhouse": {"pos": spot, "rot": 0.4}})
	var pad_h := g.height_at(spot)
	check(absf(g.height_at(spot + Vector2(20, 10)) - pad_h) < 0.001 and absf(g.height_at(spot + Vector2(-8, -18)) - pad_h) < 0.001, "The staked site is graded flat")
	var far := spot + Vector2(0, (g.pads[0]["half"] as Vector2).length() + float(g.pads[0].get("blend", PaintedCourse.PAD_BLEND)) + 5.0)  # past the pad and its ease
	check(absf(g.height_at(far) - g.raw_height_at(far)) < 0.001 and g.on_pad(spot) and not g.on_pad(far), "Beyond the blend the course is untouched")
	var lawn := FacilityBuilder.to_world(spot, 0.4, -35.0, -27.0)
	var house_xz := FacilityBuilder.to_world(spot, 0.4, 7.5, 18.0)
	check(not g.on_paving(house_xz), "A planned site is all rough")
	FacilityBuilder.grade(g, {"clubhouse": {"pos": spot, "rot": 0.4}}, {"clubhouse": 2})
	# built: only what's built on is the club's ground; its open lawn is the course's own (its
	# trees and rough stay, the ground isn't levelled there)
	check(g.on_paving(house_xz) and g.on_pad(house_xz) and not g.on_pad(lawn) and not g.on_paving(lawn), "A built plot: paved under the clubhouse, rough on its lawn")
	var built_h := float(g.pads[0]["h"])
	var lawn_h := g.height_at(lawn)
	check(absf(lawn_h - built_h) > 0.01 and (lawn_h - built_h) * (g.raw_height_at(lawn) - built_h) > 0.0, "A built plot's lawn is held level: %.2f (levelled ground %.2f, natural %.2f)" % [lawn_h, built_h, g.raw_height_at(lawn)])
	check(PaintedLayout.build(g).in_paving(house_xz), "The layout knows the paving")
	check(FacilityBuilder.contains("clubhouse", Vector2(10, 20), 0.7, Vector2(10, 20)), "Footprint contains its centre")
	check(not FacilityBuilder.contains("clubhouse", Vector2(10, 20), 0.7, Vector2(10, 90)), "Footprint excludes far points")
	var front := FacilityBuilder.to_world(Vector2.ZERO, 0.7, 0.0, -1.0)
	check(front.is_equal_approx(Vector2(-sin(0.7), -cos(0.7))), "Front faces -Z turned by rot")
	check(is_equal_approx(FacilityBuilder.facing(Vector2.ZERO, front * 5.0), 0.7), "facing() points the front at a target")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	gs.free()
	gs2.free()
	gs3.free()
	gs4.free()
	print("COURSE BUSINESS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
