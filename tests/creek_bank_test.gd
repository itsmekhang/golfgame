extends SceneTree
var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://creek_bank_test_unused.json")
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func run() -> void:
	var layout := CourseBuilder.build(7)
	var creek_count := 0
	for hz: WaterHazard in layout.water_hazards:
		if not hz.is_creek: continue
		creek_count += 1
		var max_cut := 0.0
		var max_bank_grade := 0.0
		for z in range(int(hz.bounds.position.y),int(hz.bounds.end.y),2):
			for x in range(int(hz.bounds.position.x),int(hz.bounds.end.x),2):
				var p := Vector2(x,z)
				var base := layout.base_height_at(x,z)
				max_cut = maxf(max_cut,-hz.depth_offset(base,p))
				if hz.hazard_name == "Golden Creek" and hz.signed_distance(p) > 0.0 and hz.signed_distance(p) < hz.shore_width:
					var h := []
					for q: Vector2 in [p+Vector2(.5,0),p-Vector2(.5,0),p+Vector2(0,.5),p-Vector2(0,.5)]:
						var bh := layout.base_height_at(q.x,q.y)
						h.append(bh+hz.depth_offset(bh,q))
					max_bank_grade = maxf(max_bank_grade,Vector2(h[0]-h[1],h[2]-h[3]).length())
		check(max_cut < 3.2,"Shallow stream instead of canyon: "+hz.hazard_name)
		if hz.hazard_name == "Golden Creek":
			check(max_cut < 1.6,"Hole 12 creek has no deep trench")
			check(max_bank_grade < 0.4,"Hole 12 bank slope is gradual")
		print(hz.hazard_name," max excavation ",max_cut," bank grade ",max_bank_grade)
	check(creek_count == 4,"All authored creeks checked")
	check(absf(layout.base_height_at(1333.5,-767)-layout.base_height_at(1332.5,-767)) < 0.15,"No abrupt cliff where the creek meets the end of the hole")
	for p in [Vector2(1217,-1043),Vector2(1200,-1035)]:
		check(Landforms.offset(layout.landform_list,p) < 1.0,"Hole 12 back-right bank remains a low rise")
	# Straight behind the green (per user): the backstop and azalea bank -- a rounded hill,
	# not a cliff.
	var bank := Landforms.offset(layout.landform_list,Vector2(1180,-1060))
	check(bank > 1.5 and bank < 3.5,"Hole 12 azalea bank behind the green is a moderate hill (%.2f m)" % bank)
	for hz in layout.water_hazards: hz.free()
	for bunker in layout.bunkers: bunker.free()
	print("CREEK BANK TEST: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
