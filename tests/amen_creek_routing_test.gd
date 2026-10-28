extends SceneTree
var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://amen_creek_test_unused.json")
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func run() -> void:
	var layout := CourseBuilder.build(7)
	var main: WaterHazard
	var side: WaterHazard
	var crossing: WaterHazard
	for hz: WaterHazard in layout.water_hazards:
		if hz.hazard_name == "Golden Creek": main = hz
		if hz.hazard_name == "Azalea Creek": side = hz
		if hz.hazard_name == "Azalea Pond": crossing = hz
	check(main != null and side != null and crossing != null,"Both creeks and opening crossing exist")
	if main == null or side == null or crossing == null:
		quit(1)
		return
	var join := main._stream_path[0]
	check(main.contains(join) and crossing.contains(join),"Hole 12 creek physically joins hole 13 crossing")
	check(main._stream_width <= 5.0,"Hole 12 stays narrower than the broad crossing")
	check(join.x > crossing.bounds.end.x - 15.0,"Hole 12 enters the end of the crossing instead of its side")
	var overlap_samples := 0
	for stream: WaterHazard in [main,side]:
		for z in range(floori(crossing.bounds.position.y),ceili(crossing.bounds.end.y)):
			for x in range(floori(crossing.bounds.position.x),ceili(crossing.bounds.end.x)):
				var p := Vector2(x,z)
				if crossing.contains(p) and stream.contains(p):
					overlap_samples += 1
					check(absf(stream.water_level_at(p)-crossing.water_level) < 0.001,"Full river mouth shares crossing level")
		var visible := Geometry2D.clip_polygons(stream.polygon,crossing.polygon)
		check(visible.size() == 1,"One unbranched visible channel outside the crossing")
	check(overlap_samples > 40,"Check both mouths across their full width")
	check(absf(main.water_level_at(join)-crossing.water_level_at(join)) < 0.001,"Water surfaces meet at the same level")
	var base := layout.base_height_at(join.x,join.y)
	var expected := minf(main.depth_offset(base,join),crossing.depth_offset(base,join))
	check(absf(layout.height_at(join.x,join.y)-(base+expected)) < 0.001,"Junction does not double-excavate a pit")
	var fw := layout.fairways[12]
	var green := layout.greens[12]
	var tee := layout.holes[12].tee
	var edge_samples := 0
	var min_green := INF
	var min_edge := INF
	var max_edge := -INF
	for p in side._stream_path:
		min_green = minf(min_green,green.signed_distance(p))
		var along := p.y-tee.z
		if along > 175 and along < 355:
			edge_samples += 1
			var sd := fw.signed_distance(p)
			min_edge = minf(min_edge,sd)
			max_edge = maxf(max_edge,sd)
			check(sd > 2.5 and sd < 12.0,"Small creek follows the fairway, with room to round corners at %s (%.2f)" % [p,sd])
	check(edge_samples > 50,"Fairway border checked along its length")
	check(min_green > 8.0,"Creek and banks leave the putting surface intact")
	for local_dir in [Vector2(-1,.35).normalized(),Vector2.DOWN,Vector2.RIGHT]:
		var direction := Vector2(-local_dir.y,local_dir.x)
		var target := green.center + direction * (green.radius_at(direction.angle())+10.0)
		var closest := INF
		for p in side._stream_path: closest = minf(closest,p.distance_to(target))
		check(closest < 5.0,"Creek wraps the front and far side of the green")
	for creek: WaterHazard in [main,side]:
		for i in range(1,creek._stream_path.size()):
			var a := creek._stream_path[i-1]
			var b := creek._stream_path[i]
			for step in range(1,5):
				check(creek.contains(a.lerp(b,step/5.0)),"Continuous channel %s between samples %d at %s" % [creek.hazard_name,i,a.lerp(b,step/5.0)])
	print("Fairway clearance ",min_edge,"..",max_edge," m; green clearance ",min_green," m")
	var rectangle := PackedVector2Array([Vector2(0,0),Vector2(20,0),Vector2(20,10),Vector2(0,10)])
	var dense := PackedVector2Array()
	for i in range(4):
		for step in range(100): dense.append(rectangle[i].lerp(rectangle[(i+1)%4],step/100.0))
	var coarse_samples := PropScatter._shoreline_samples(rectangle,3.0,1.0)
	var dense_samples := PropScatter._shoreline_samples(dense,3.0,1.0)
	check(coarse_samples.size() == 20 and dense_samples.size() == 20,"Tracing more bank vertices does not multiply rocks")
	for i in range(mini(coarse_samples.size(),dense_samples.size())):
		check(coarse_samples[i][0].distance_to(dense_samples[i][0]) < 0.001,"Bank props keep consistent spacing")
	print("AMEN CREEK ROUTING: ","PASS" if failures == 0 else "FAIL")
	for hz in layout.water_hazards: hz.free()
	for bunker in layout.bunkers: bunker.free()
	quit(0 if failures == 0 else 1)
