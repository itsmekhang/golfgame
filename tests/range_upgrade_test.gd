extends SceneTree
## The driving range upgraded with golfers at it (user): each level's ball dispenser stands
## somewhere else, so those on their way to it go to the new one -- filling their bucket square
## at its chute, not off at where the old level's stood -- and every one of them has a bay of the
## new level's.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_range_upgrade_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [1, 2, 3]:
		await scenario(level)
	print("RANGE UPGRADE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func build(b: CourseBusiness) -> Node3D:
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": b.level(type), "pos": b.placements[type]["pos"], "rot": 0.0, "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	return built


func scenario(level: int) -> void:
	var c := PaintedCourse.create("Range upgrade", Vector2i(400, 400))
	c.holes.append({"tee": Vector2(60, 20), "pin": Vector2(60, -70), "par": 3, "bends": [], "curve": false})
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.built = {"clubhouse": 1, "driving_range": level, "parking_lot": 1}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "range_attendant": 1}
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 130), "rot": 0.0}, "driving_range": {"pos": Vector2(40, 115), "rot": 0.0}}
	var built := build(b)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	var g := life._new_arrival(0, "range")
	check(g != null, "L%d: no range visitor" % level)
	if g == null:
		return
	var w: ClubLife.Walker = g.golfers[0]
	for tick in range(4000):
		life._spawn_wait = 1e9
		life._process(0.25)
		if str(w.data.get("range_step", "")) == "dispenser":
			break
	check(str(w.data.get("range_step", "")) == "dispenser", "L%d: the visitor never set off for the dispenser" % level)
	# up a level while they're on their way
	b.built["driving_range"] = level + 1
	built.queue_free()
	built = build(b)
	life.facilities = built
	life.refresh()
	var fac := built.get_node("driving_range") as Node3D
	var new_spots: Array = FacilityBuilder.rig(fac).get("dispensers", [])
	check(not new_spots.is_empty(), "L%d: the new range has no dispenser" % (level + 1))
	var off := -1.0
	var bays: int = (FacilityBuilder.rig(fac).get("range_bays", []) as Array).size() + (FacilityBuilder.rig(fac).get("range_bays_up", []) as Array).size()
	for tick in range(6000):
		life._spawn_wait = 1e9
		life._process(0.25)
		if not life._groups.has(g) or w.data.has("bucket"):
			break
		if str(w.data.get("range_step", "")) == "dispenser" and w.data.has("range_next"):
			var chute := fac.global_transform * (w.data["range_chute"] as Transform3D).origin
			off = maxf(off, Vector2(w.node.global_position.x - chute.x, w.node.global_position.z - chute.z).length())
	var nearest := INF
	for xf: Transform3D in new_spots:
		if w.data.has("range_chute"):
			nearest = minf(nearest, (w.data["range_chute"] as Transform3D).origin.distance_to(xf.origin))
	check(w.data.has("bucket"), "L%d -> %d: the visitor never got a bucket" % [level, level + 1])
	check(off >= 0.0 and off < 0.3, "L%d -> %d: they filled their bucket %.2f m off the new dispenser's chute" % [level, level + 1, off])
	check(int(w.data.get("range_bay", -1)) < bays, "L%d -> %d: their bay isn't one of the new range's" % [level, level + 1])
	print("L%d -> L%d: bucket filled %.2f m from the new chute" % [level, level + 1, off])
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
