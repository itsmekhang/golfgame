extends SceneTree
## Nobody floats: on sloping ground, with flights and range visitors coming and going (to the
## range's ball dispenser and its bays, back to their cars), everyone on foot off the facilities'
## plots stands on the ground as it's drawn -- not at a facility's floor height carried out over
## ground that falls away from it.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_float_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [2, 3]:
		await scenario(level)
	print("FLOAT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func scenario(level: int) -> void:
	var c := PaintedCourse.create("Float", Vector2i(500, 500))
	for i in range(c.height.size()):
		c.height[i] = float(i % c.size.x) * 0.04 - float(i / c.size.x) * 0.03  # (falling away two ways)
	c.holes.append({"tee": Vector2(170, 20), "pin": Vector2(170, -70), "par": 3, "bends": [], "curve": false})
	c.paint(PaintedCourse.Surface.GREEN, Vector2(170, -70), 9, 1, 1)
	c.paint(PaintedCourse.Surface.TEE, Vector2(170, 20), 5, 1, 1)
	var b := CourseBusiness.create()
	b.accepting_visitors = true
	b.placements = {"clubhouse": {"pos": Vector2(-105, 50), "rot": 0.0}, "parking_lot": {"pos": Vector2(-105, 140), "rot": 0.0}, "driving_range": {"pos": Vector2(40, 115), "rot": 0.0}}
	b.built = {"clubhouse": 1, "parking_lot": 1, "driving_range": level}
	b.rooms = {"pro_shop": 1}
	b.staff = {"shop_clerk": 1, "range_attendant": 1}
	FacilityBuilder.grade(c, b.placements, b.built)
	var items: Array = []
	for type in b.placements:
		items.append({"type": type, "level": b.level(type), "pos": b.placements[type]["pos"], "rot": 0.0, "rooms": b.rooms})
	var built := FacilityBuilder.build(items, func(p: Vector2) -> float: return c.height_at(p), false, true)
	root.add_child(built)
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	life.business = b
	life.facilities = built
	life.refresh()
	var worst := 0.0
	var where := ""
	var spawned := 0
	for step in range(7200):
		life._spawn_wait = 1e9
		if step % 160 == 0 and spawned < 6:
			var g := life._new_arrival(0, "range" if spawned % 2 == 0 else "")
			if g != null:
				g.range_visit = true
				g.short_visit = false
				spawned += 1
		life._process(0.25)
		for g: ClubLife.Group in life._groups:
			for w: ClubLife.Walker in g.golfers:
				if w.riding or not w.node.visible:
					continue
				var p := Vector2(w.node.global_position.x, w.node.global_position.z)
				var on_plot := false
				for t in b.placements:
					on_plot = on_plot or FacilityBuilder.contains(t, b.placements[t]["pos"], 0.0, p, 0.5)
				if on_plot:
					continue
				var up := w.node.global_position.y - c.drawn_height_at(p)
				if up > worst:
					worst = up
					where = "%s in %s (%s)" % [str(p.round()), g.phase, str(w.data.get("range_step", ""))]
	print("L%d: %d in; highest anyone stood off the plots over the ground %.2f m at %s" % [level, spawned, worst, where])
	check(worst < 0.15, "L%d: someone floated %.2f m over the ground at %s" % [level, worst, where])
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
