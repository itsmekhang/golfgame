extends SceneTree
var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://hole11_opening_test_unused.json")
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)
func run() -> void:
	var layout := CourseBuilder.build(7)
	var hole := layout.holes[10]
	var tee := Vector2(hole.tee.x,hole.tee.z)
	var forward := (Vector2(hole.waypoints[1].x,hole.waypoints[1].z)-tee).normalized()
	var right := Vector2(-forward.y,forward.x)
	for along in [20,35,50,80,140,170]:
		for side in [-10,0,10]:
			var p: Vector2 = tee + forward*along + right*side
			check(layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH, "Rough carry at %d/%d" % [along,side])
	check(layout.surface_at(tee) == CourseLayout.SURFACE_TEE, "Back tee stays mown")
	check(layout.surface_at(hole.tee_boxes[1][0]) == CourseLayout.SURFACE_TEE, "Forward tee stays mown")
	check(layout.surface_at(tee+forward*210) == PhysicsEnums.SurfaceType.FAIRWAY, "Fairway resumes after rough carry")
	var near_sides := [0,0]
	for tree in hole.planted_trees:
		var p: Vector2 = tree[1]
		var offset := p-tee
		var along := offset.dot(forward)
		var side := offset.dot(right)
		check(absf(side) >= 13.9, "Central tee-shot lane stays clear")
		if along < 48:
			near_sides[0 if side < 0 else 1] += 1
			check(layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH, "Close trees stand in rough")
	check(near_sides[0] >= 7 and near_sides[1] >= 7, "Trees close to both sides of tee")
	var tee_height := layout.height_at(tee.x,tee.y)
	var forward_tee: Vector2 = hole.tee_boxes[1][0]
	var forward_height := layout.height_at(forward_tee.x,forward_tee.y)
	check(absf(tee_height+8.5) < 0.01, "Men's tee is the lowered platform")
	check(forward_height > tee_height+4.5 and forward_height < tee_height+5.5, "Women's tee stands well above the men's tee")
	for box in hole.tee_boxes:
		var center: Vector2 = box[0]
		var level := layout.height_at(center.x,center.y)
		for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
			var p: Vector2 = center+offset
			check(absf(layout.height_at(p.x,p.y)-level) < 0.001, "Both tee boxes are level plateaus")
	for along in range(195,470,5):
		var station := Landforms._route_point(hole.waypoints,float(along)/layout.fairways[10].length_m())
		var p: Vector2 = station[0]
		check(layout.height_at(p.x,p.y) > forward_height+5.0, "Both tees sit well below the playing corridor")
	var peak := -INF
	var previous := tee_height
	var max_step := 0.0
	for along in range(0,221,2):
		var p := tee+forward*along
		var height := layout.height_at(p.x,p.y)
		peak = maxf(peak,height-tee_height)
		max_step = maxf(max_step,absf(height-previous))
		previous = height
	check(peak > 14.5 and peak < 16.5, "Opening has a pronounced climb from the low tees to the fairway")
	check(max_step < 0.5, "Tee apron and rough grade blend smoothly")
	var region := Rect2(tee,Vector2.ZERO).expand(tee+forward*160).grow(60)
	var bushes := ForestPlanter._understory_transforms(layout,region,7,func(_p: Vector2) -> bool: return false)
	var bush_count := 0
	for species in bushes:
		for transform: Transform3D in species:
			var p := Vector2(transform.origin.x,transform.origin.z)
			check(absf((p-tee).dot(right)) >= 17.9, "Bushes keep the existing shot opening clear")
			check(layout.surface_at(p) == PhysicsEnums.SurfaceType.ROUGH, "Bushes stand on rough")
			bush_count += 1
	check(bush_count > 200, "Dense authored bushes fill the tee-side forest clearance")
	print("TEE GRADE: peak rise=",peak,"; max 2m height change=",max_step,"; tee-side bushes=",bush_count)
	print("HOLE 11 OPENING: ","PASS" if failures == 0 else "FAIL", "; nearby trees per side=",near_sides,"; planted trees=",hole.planted_trees.size())
	for hazard in layout.water_hazards: hazard.free()
	for bunker in layout.bunkers: bunker.free()
	quit(1 if failures else 0)


