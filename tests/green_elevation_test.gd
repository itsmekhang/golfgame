extends SceneTree
## Headless check of the green approach rule (CourseLayout.APPROACH_*): every green must
## meet its fairway without a big step. For each hole it walks the final metres of the
## routing on the finished terrain and reports the green-centre height against the
## fairway 60 m short of it, plus the steepest 5 m grade on that approach.
## Run: godot --headless --path . --script tests/green_elevation_test.gd

const APPROACH := 60.0
const STEP := 5.0
const MAX_STEP_M := 2.6      # green centre vs fairway 60 m short (datum rule 2.0 m + bank/relief)
const MAX_GRADE := 0.09      # steepest 5 m run on the approach (green bank included)


func _route_point_back(hole: CourseLayout.Hole, back: float) -> Vector2:
	# point `back` metres before the green centre, walking the routing polyline backwards
	var wps := hole.waypoints
	var k := wps.size() - 1
	var remaining := back
	while k > 0:
		var a := Vector2(wps[k].x, wps[k].z)
		var b := Vector2(wps[k - 1].x, wps[k - 1].z)
		var seg := a.distance_to(b)
		if remaining <= seg:
			return a + (b - a) * (remaining / maxf(seg, 0.001))
		remaining -= seg
		k -= 1
	return Vector2(wps[0].x, wps[0].z)


func _init() -> void:
	var layout := CourseBuilder.build(7)
	var failures := 0
	print("hole  name                  green_h  fw60   step   maxgrade  datum60  datum_step  raise  lf_green  lf_60")
	for i in range(layout.holes.size()):
		var hole: CourseLayout.Hole = layout.holes[i]
		var gc := Vector2(hole.cup.x, hole.cup.z)
		var hg := layout.base_height_at(gc.x, gc.y)
		var p60 := _route_point_back(hole, APPROACH)
		var h60 := layout.base_height_at(p60.x, p60.y)
		var worst := 0.0
		var prev := layout.base_height_at(p60.x, p60.y)
		var back := APPROACH - STEP
		while back >= 0.0:
			var p := _route_point_back(hole, back)
			var h := layout.base_height_at(p.x, p.y)
			worst = maxf(worst, absf(h - prev) / STEP)
			prev = h
			back -= STEP
		var end_x := hole.profile[hole.profile.size() - 1].x
		var d60 := layout.hole_datum(hole, end_x - APPROACH)
		var dstep := hole.green_h - d60
		var ok := absf(hg - h60) <= MAX_STEP_M and worst <= MAX_GRADE
		if not ok:
			failures += 1
		var lf_g := Landforms.offset_split(layout.landform_list, gc)
		var lf_60 := Landforms.offset_split(layout.landform_list, p60)
		print("%s %2d  %-20s %7.2f %6.2f %6.2f   %5.1f%%   %7.2f  %6.2f   %5.2f  %5.2f    %5.2f" % ["PASS" if ok else "FAIL", i + 1, hole.name, hg, h60, hg - h60, worst * 100.0, d60, dstep, hole.green_height, lf_g.x + lf_g.y, lf_60.x + lf_60.y])
	if failures == 0:
		print("GREEN ELEVATION TEST: PASS")
		quit(0)
	else:
		print("GREEN ELEVATION TEST: FAIL (%d holes)" % failures)
		quit(1)
