extends SceneTree
## Facility sites (FacilityBuilder.SITES): each level's site holds everything that level is built
## on -- its models' meshes, its paving, the short game area's painted turf -- so facilities can
## stand as close as their sites allow; a site fits its neighbour tight, and an upgrade that would
## run into a neighbour is refused.
## Run: godot --headless --path . --script tests/facility_site_test.gd

const SLACK := 0.25  # a kerb or a gutter a hair over (m)
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_facility_site_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func run() -> void:
	for type in FacilityBuilder.FOOTPRINT:
		for lv in [1, 2, 3, 4]:
			var fp: Vector2 = FacilityBuilder.footprint(type, lv)
			var extent := _built_extent(type, lv)
			var site := FacilityBuilder.site(type, lv).grow(SLACK)
			check(site.encloses(extent), "%s level %d is built past its site: %s, site %s" % [type, lv, extent, FacilityBuilder.site(type, lv)])
			# (the range's top level: its lounge's deck and the safety net out from it over the field)
			check(Rect2(-fp * 0.5, fp).grow(2.5).encloses(FacilityBuilder.site(type, lv)), "%s level %d's site runs off its plot" % [type, lv])
	# the range: as many golfers hit at once as it has bays, more at each level
	var bays: Array = []
	for lv in [1, 2, 3, 4]:
		var range_built := FacilityBuilder.build([{"type": "driving_range", "level": lv, "pos": Vector2.ZERO, "rot": 0.0}], func(_p: Vector2) -> float: return 0.0, false, true)
		bays.append((FacilityBuilder.rig(range_built.get_child(0)).get("range_bays", []) as Array).size())
		range_built.free()
	check(bays == [10, 12, 14, 15], "The range's bays by level: %s" % str(bays))
	# two first-level facilities side by side, as close as their sites let them
	var c := PaintedCourse.create("Site test", Vector2i(400, 400))
	var placed := {"clubhouse": {"pos": Vector2(-40, 0), "rot": 0.0, "level": 1}}
	var spot := FacilityBuilder.beside(c, placed, "cart_barn", "clubhouse", 1)
	check(not spot.is_empty(), "No room beside the clubhouse for the barn")
	if not spot.is_empty():
		var gap: float = (spot["pos"] as Vector2).x - (-40.0)
		var old_gap: float = FacilityBuilder.footprint("clubhouse").x * 0.5 + FacilityBuilder.footprint("cart_barn").x * 0.5
		check(gap < old_gap - 20.0, "The barn still stands a whole plot away: %.1f m (plots: %.1f m)" % [gap, old_gap])
		placed["cart_barn"] = {"pos": spot["pos"], "rot": spot["rot"], "level": 1}
		var others := placed.duplicate()
		others.erase("clubhouse")
		check(FacilityBuilder.site_problem(c, others, "clubhouse", Vector2(-40, 0), 0.0, 1) == "", "The clubhouse no longer fits where it stood")
		check(FacilityBuilder.site_problem(c, others, "clubhouse", Vector2(-40, 0), 0.0, 2).begins_with("Overlaps"), "An Expanded clubhouse is let grow into the barn")
		var unknown := {"cart_barn": {"pos": spot["pos"], "rot": spot["rot"]}}
		check(FacilityBuilder.site_problem(c, unknown, "clubhouse", Vector2(-40, 0), 0.0, 1) != "", "Without levels a site isn't the whole plot")
	print("FACILITY SITES: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


## Where `type` at level `lv` is built (its local XZ): its meshes (not a plot-wide lawn, nor the
## range's field out front), its paving mask, the short game area's turf.
func _built_extent(type: String, lv: int) -> Rect2:
	var fp := FacilityBuilder.footprint(type, lv)
	var items := [{"type": type, "level": lv, "pos": Vector2.ZERO, "rot": 0.0, "name": "Pinehurst Golf Club",
		"rooms": {"pro_shop": 3, "restaurant": 3, "lounge": 3, "office": 3, "simulator": 3, "spa_fitness": 3}}]
	var built := FacilityBuilder.build(items, func(_p: Vector2) -> float: return 0.0, false, true)
	root.add_child(built)
	var fac := built.get_child(0) as Node3D
	var out := Rect2()
	var any := false
	for g in fac.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var b: AABB = gi.global_transform * gi.get_aabb()
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		if b.size == Vector3.ZERO or (r.size.x > fp.x * 0.95 and r.size.y > fp.y * 0.95):
			continue  # (a Label3D's box headless; a lawn over the whole plot)
		if type == "driving_range" and r.position.y < -fp.y * 0.5 - 5.0:
			continue  # the field (yardage boards and its nets, well out)
		out = r if not any else out.merge(r)
		any = true
	built.free()
	var mask := FacilityBuilder.paving(type, lv)
	if mask != null:
		for j in range(mask.get_height()):
			for i in range(mask.get_width()):
				if mask.get_pixel(i, j).r8 > 0:
					var cell := Rect2(-fp.x * 0.5 + i * fp.x / mask.get_width(), -fp.y * 0.5 + j * fp.y / mask.get_height(), fp.x / mask.get_width(), fp.y / mask.get_height())
					out = cell if not any else out.merge(cell)
					any = true
	if type == "short_game":
		var plan: Dictionary = FacilityBuilder.PRACTICE_TURF.get(lv, {})
		var dabs: Array = []
		for gr: Dictionary in plan.get("greens", []):
			for d in FacilityBuilder._green_dabs(gr):
				dabs.append([d[0], float(d[1]) + FacilityBuilder.PRACTICE_COLLAR])
		for bk: Dictionary in plan.get("bunkers", []):
			dabs.append_array(FacilityBuilder._bunker_dabs(bk))
		for d in dabs:
			var rad := float(d[1])
			var r := Rect2((d[0] as Vector2) - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
			out = r if not any else out.merge(r)
			any = true
	return out
