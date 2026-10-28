extends SceneTree
## A parking lot built hard up against another facility on sloping ground: the ground as it's
## drawn stays under the lot's asphalt (and its lines) everywhere it's paved -- the neighbour's
## levelled ground and the slope round it never lift over it and bury the lines -- bar a few
## centimetres right where its paving runs into the neighbour's, within a terrain cell of it.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_parking_grade_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for level in [1, 2, 3, 4]:
		var c := PaintedCourse.create("Lot grade", Vector2i(600, 600))
		for i in range(c.height.size()):
			c.height[i] = float(i % c.size.x) * 0.03 + float(i / c.size.x) * 0.02  # (sloping two ways)
		var lot_at := Vector2(0, 0)
		var lot_fp := FacilityBuilder.footprint("parking_lot")
		var house_fp := FacilityBuilder.footprint("clubhouse")
		# the clubhouse and the cart barn as close beside the lot as their sites allow
		var placements := {"parking_lot": {"pos": lot_at, "rot": 0.0}}
		var lv := {"parking_lot": level, "clubhouse": level, "cart_barn": level}
		for pair in [["clubhouse", Vector2(0, 1)], ["cart_barn", Vector2(1, 0)]]:
			var t: String = pair[0]
			var dir: Vector2 = pair[1]
			var d := 1.0
			while d < 140.0:
				var pl := {}
				for k in placements:
					pl[k] = placements[k].merged({"level": lv[k]})
				if FacilityBuilder.site_problem(c, pl, t, lot_at + dir * d, 0.0, level) == "":
					break
				d += 1.0
			check(d < 140.0, "Could not find an adjacent valid site")
			placements[t] = {"pos": lot_at + dir * d, "rot": 0.0}
		var order := {"clubhouse": placements["clubhouse"], "cart_barn": placements["cart_barn"], "parking_lot": placements["parking_lot"]}
		placements = order
		var levels := {"parking_lot": level, "clubhouse": level, "cart_barn": level}
		FacilityBuilder.grade(c, placements, levels)
		var items: Array = []
		for t in placements:
			items.append({"type": t, "level": level, "pos": placements[t]["pos"], "rot": 0.0})
		var built := FacilityBuilder.build(items, func(p: Vector2) -> float: return c.height_at(p), false, true)
		root.add_child(built)
		var lot := built.get_node("parking_lot") as Node3D
		var floor_y := lot.global_position.y + FacilityBuilder.ground_sink("parking_lot")
		var worst := 0.0
		var join := 0.0  # (within a drawn cell of another facility's paving)
		var where := Vector2.ZERO
		var lot_pad: Dictionary = {}
		for pad: Dictionary in c.pads:
			if (pad["pos"] as Vector2).distance_to(lot_at) < 30.0 and pad.has("field"):
				lot_pad = pad
		check(not lot_pad.is_empty(), "L%d: no pad for the lot" % level)
		# everywhere the lot is paved, on a fine grid: not just its stalls' middles
		var half := lot_fp * 0.5
		var x := -half.x
		while x <= half.x:
			var z := -half.y
			while z <= half.y:
				var q := lot_at + Vector2(x, z)
				if not lot_pad.is_empty() and PaintedCourse.pad_reach(lot_pad, q, true) <= 0.0:
					var over := maxf(c.height_at(q), c.drawn_height_at(q)) - (floor_y + 0.01)  # (over the asphalt's top)
					var near_other := false
					for pad: Dictionary in c.pads:
						if pad != lot_pad and pad.has("field") and PaintedCourse.pad_reach(pad, q, true) < PaintedCourse.FLAT_MARGIN * 2.0:
							near_other = true
					if near_other:
						join = maxf(join, over)
					elif over > worst:
						worst = over
						where = Vector2(x, z)
				z += 0.5
			x += 0.5
		if worst > 0.0 and OS.get_environment("GRADE_TRACE") != "":
			var q0 := lot_at + where
			for dx in [-2.0, 0.0, 2.0]:
				for dz in [-2.0, 0.0, 2.0]:
					var q1 := q0 + Vector2(dx, dz)
					print("   %s raw %.2f h %.3f drawn %.3f" % [str(where + Vector2(dx, dz)), PaintedCourse.pad_reach(lot_pad, q1, true), c.height_at(q1) - floor_y, c.drawn_height_at(q1) - floor_y])
		print("L%d: drawn ground over the lot's asphalt at most %.3f m (%.3f m where it meets a neighbour's paving) at %s (clubhouse %.0f m off, barn %.0f m)" % [level, worst, join, str(where), (placements["clubhouse"]["pos"] as Vector2).y, (placements["cart_barn"]["pos"] as Vector2).x])
		check(worst <= 0.0, "L%d: the ground rises %.2f m over the lot's asphalt" % [level, worst])
		check(join < 0.06, "L%d: the ground rises %.2f m over the lot's asphalt where it meets a neighbour's" % [level, join])
		built.free()
	print("PARKING GRADE: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
