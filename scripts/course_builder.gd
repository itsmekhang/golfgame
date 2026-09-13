class_name CourseBuilder
extends RefCounted
## Builds the 18-hole course "Augusta National" from the traced Augusta blueprints in
## `assets/course/augusta_traced.json` (written by tools/trace_augusta.py from the
## Augusta_Claude_Handoff spec and the hole paintings).
##
## Every hole is authored in its own local frame: origin = back tee, +x = direction
## of play, +y = golfer's right, metres. The routing lays the front nine in a band of
## parallel corridors (alternating north/south so each tee is a short walk from the
## previous green) and the back nine in a second band north of it, running back west.
## Corridors are packed to each hole's real lateral extent plus a belt of trees, so a
## sweeping dogleg gets the room it needs and a straight par 3 does not waste any.
##
## The seed only affects the rolling terrain and small jitter; everything else is
## authored (no random generators run on this course).

const DATA_PATH := "res://assets/course/augusta_traced.json"
const COURSE_NAME := "Augusta National"
const BAND_DEPTH := 640.0  # north-south extent of each nine (longest hole + walks)
const BAND_GAP := 120.0  # woods between the two nines
const MARGIN := 90.0  # terrain around the holes
const TREE_BELT := 55.0  # woods between neighbouring holes' outermost features
const NORTH := Vector2(0.0, -1.0)

static var _data: Dictionary = {}
static var last_report: String = ""


static func _specs() -> Array:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		assert(f != null, "missing " + DATA_PATH)
		_data = JSON.parse_string(f.get_as_text())
	return _data["holes"]


## Name / par / yardage of hole `i` without building the course (loading screen).
static func hole_info(i: int) -> Dictionary:
	var h: Dictionary = _specs()[i]
	return {"name": h["name"], "par": int(h["par"]), "yd": int(h["yards"])}


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(_v(p))
	return out


## Local frame of one hole placed in the world: `to_world(local)`.
class Frame:
	var tee: Vector2
	var dir: Vector2
	var right: Vector2

	func _init(p_tee: Vector2, p_dir: Vector2) -> void:
		tee = p_tee
		dir = p_dir
		right = Vector2(-dir.y, dir.x)

	func to_world(l: Vector2) -> Vector2:
		return tee + dir * l.x + right * l.y

	func to_world3(l: Vector2) -> Vector3:
		var w := to_world(l)
		return Vector3(w.x, 0.0, w.y)

	func poly(a: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in a:
			out.append(to_world(CourseBuilder._v(p)))
		return out

	func rotation() -> float:
		return atan2(dir.y, dir.x)


static func build(seed_v: int, course_name: String = COURSE_NAME) -> CourseLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var layout := CourseLayout.new()
	layout.name_pretty = course_name
	layout.authored_hazards = true
	layout.terrain_seed = seed_v * 7 + 91
	layout.terrain_amplitude = rng.randf_range(0.5, 0.7)
	layout.terrain_frequency = rng.randf_range(0.0035, 0.005)
	layout.terrain_detail = 0.22
	layout.terrain_hills = rng.randf_range(0.4, 0.6)
	layout.noise.seed = layout.terrain_seed
	layout.noise.frequency = layout.terrain_frequency
	layout.random_trees = true

	var specs := _specs()
	var n := specs.size()

	# ---- routing: corridor packing across x, tee placement along z ----
	var extents: Array = []
	for spec in specs:
		extents.append(_local_extent(spec))
	var xc := PackedFloat32Array()
	xc.resize(n)
	var dirs: Array[Vector2] = []
	var edge := 0.0
	for i in range(n):
		var k := i % 9
		var northbound := k % 2 == 0
		var dir := NORTH if northbound else -NORTH
		dirs.append(dir)
		var e: Vector3 = extents[i]  # (across min, across max, along max)
		# world-x offsets of the hole's lateral extent (a southbound hole's right is -x)
		var lo := e.x if northbound else -e.y
		var hi := e.y if northbound else -e.x
		if i == 0:
			xc[i] = -lo
			edge = xc[i] + hi
		elif i < 9:
			xc[i] = edge + TREE_BELT - lo
			edge = xc[i] + hi
		elif i == 9:
			xc[i] = xc[8]  # the back nine starts under the ninth and runs back west
			edge = xc[i] + lo
		else:
			xc[i] = edge - TREE_BELT - hi
			edge = xc[i] + lo

	var tees: Array[Vector2] = []
	var prev_green := Vector2.ZERO
	for i in range(n):
		var k := i % 9
		var band_south := 0.0 if i < 9 else -(BAND_DEPTH + BAND_GAP)
		var band_north := band_south - BAND_DEPTH
		var northbound := k % 2 == 0
		var length: float = extents[i].z
		var tee_z: float
		if northbound:
			var want := band_south - 10.0 if i == 0 or i == 9 else prev_green.y - 35.0
			tee_z = clampf(want, band_north + length + 10.0, band_south - 10.0)
		else:
			var want := prev_green.y + 35.0
			tee_z = clampf(want, band_north + 10.0, band_south - length - 10.0)
		var tee := Vector2(xc[i] + rng.randf_range(-3.0, 3.0), tee_z)
		tees.append(tee)
		var route: Array = specs[i]["route"]
		var frame := Frame.new(tee, dirs[i])
		prev_green = frame.to_world(_v(route[route.size() - 1]))

	# ---- holes ----
	var all_pts: Array[Vector2] = []
	for i in range(n):
		var hole := _make_hole(layout, i, specs[i], Frame.new(tees[i], dirs[i]), rng)
		layout.holes.append(hole)
		all_pts.append_array(layout.feature_points(hole))

	var lo := all_pts[0]
	var hi := all_pts[0]
	for p in all_pts:
		lo = lo.min(p)
		hi = hi.max(p)
	layout.bounds = Rect2(lo - Vector2(MARGIN, MARGIN), hi - lo + Vector2(MARGIN, MARGIN) * 2.0)

	layout.finalize_features()
	last_report = "seed %d: %d holes, %d water features, %d bunkers, %.0f x %.0f m" % [seed_v, layout.holes.size(), layout.water_hazards.size(), layout.bunkers.size(), layout.bounds.size.x, layout.bounds.size.y]
	return layout


## (across min, across max, along max) of everything a hole owns, in its local frame.
static func _local_extent(spec: Dictionary) -> Vector3:
	var pts: Array = []
	pts.append_array(spec["route"])
	for poly in spec["fairway_polys"]:
		pts.append_array(poly)
	pts.append_array(spec["green"]["polygon"])
	for b in spec["bunkers"]:
		pts.append_array(b["polygon"])
	for w in spec["water"]:
		pts.append_array(w["polygon"])
	for t in spec["tees"]:
		var c := _v(t["center"])
		var h := _v(t["half"])
		pts.append([c.x - h.y, c.y - h.x])
		pts.append([c.x + h.y, c.y + h.x])
	var e := Vector3(INF, -INF, -INF)
	for p in pts:
		e.x = minf(e.x, float(p[1]))
		e.y = maxf(e.y, float(p[1]))
		e.z = maxf(e.z, float(p[0]))
	return e


static func _make_hole(layout: CourseLayout, i: int, spec: Dictionary, frame: Frame, rng: RandomNumberGenerator) -> CourseLayout.Hole:
	var hole := CourseLayout.Hole.new()
	hole.index = i
	hole.name = spec["name"]
	hole.par = int(spec["par"])
	hole.green_height = rng.randf_range(0.3, 0.7)
	if i in [2, 5, 8]:
		hole.green_height *= 0.4
	hole.tee_height_offset = -0.5 if i == 1 else 0.0
	if i == 9:
		hole.tee_apron = Vector2(3.0, 22.0)

	# tee boxes (back tee first); the ball starts on the back tee
	for t in spec["tees"]:
		var d := _v(t["dir"])
		var wd := frame.dir * d.x + frame.right * d.y
		hole.tee_boxes.append([frame.to_world(_v(t["center"])), wd.normalized(), _v(t["half"])])

	# routing polyline; the last point is the traced green centre (the cup site)
	var route: Array = spec["route"]
	hole.waypoints = []
	for k in range(route.size()):
		var lp := _v(route[k])
		if k == route.size() - 1:
			lp = _v(spec["green"]["center"])
		hole.waypoints.append(frame.to_world3(lp))
	if not hole.tee_boxes.is_empty():
		var tc: Vector2 = hole.tee_boxes[0][0]
		if tc.distance_to(Vector2(hole.waypoints[0].x, hole.waypoints[0].z)) < 25.0:
			hole.waypoints[0] = Vector3(tc.x, 0.0, tc.y)
	hole.tee = hole.waypoints[0]

	# elevation profile: (metres along the route, proposed height) scaled by CourseLayout.PROFILE_SCALE
	var route_len := 0.0
	for k in range(1, hole.waypoints.size()):
		route_len += (hole.waypoints[k] - hole.waypoints[k - 1]).length()
	hole.profile = PackedVector2Array()
	# Pink Dogwood: keep a gentle descent with one quarter of the original relief.
	for s in spec["profile"]:
		var elevation := float(s[1]) * (0.25 if i == 1 else 1.0)
		if i == 5:
			# Juniper: soften the steep descent from the tee into the green hollow.
			elevation *= 0.45
		# Flowering Peach: halve the final climb into its lower green platform.
		if i == 2 and float(s[0]) >= 0.72:
			elevation = 2.0 + (elevation - 2.0) * 0.5
		# Carolina Cherry: a gradual rise out of the valley into the green and bunkers.
		if i == 8 and float(s[0]) >= 0.7:
			elevation = -10.0 + (elevation + 10.0) * 0.25
		hole.profile.append(Vector2(float(s[0]) * route_len, elevation))

	# mown fairway: half widths left/right of the routing every profile_step metres
	hole.fairway_profile = PackedVector3Array()
	var wsum := 0.0
	var wcount := 0
	for s in spec["fairway_profile"]:
		var l := float(s[1])
		var r := float(s[2])
		if i == 6:
			# Narrow the opening, leaving the annotated left side as playable rough.
			var opening := 1.0 - smoothstep(100.0, 175.0, float(s[0]))
			l = lerpf(l, minf(l, 18.0), opening)
			r = lerpf(r, minf(r, 13.0), opening)
		if i == 10:
			# Bring both wooded edges into the marked opening section.
			var neck := smoothstep(24.0, 48.0, float(s[0])) * (1.0 - smoothstep(145.0, 190.0, float(s[0])))
			l = lerpf(l, minf(l, 21.0), neck)
			r = lerpf(r, minf(r, 21.0), neck)
		hole.fairway_profile.append(Vector3(float(s[0]), l, r))
		if l + r > 2.0:
			wsum += (l + r) * 0.5
			wcount += 1
	hole.fairway_step = float(_data.get("profile_step_m", 4.0))
	hole.fairway_half_width = wsum / maxf(wcount, 1) if wcount > 0 else 16.0

	# green: traced outline as a radial profile around its centroid
	var g: Dictionary = spec["green"]
	hole.green_center = frame.to_world(_v(g["center"]))
	hole.green_radial = PackedFloat32Array()
	var rsum := 0.0
	for r in g["radial"]:
		hole.green_radial.append(float(r))
		rsum += float(r)
	hole.green_rotation = frame.rotation()
	hole.green_radius = rsum / maxf(hole.green_radial.size(), 1)
	hole.green_relief = _v(spec["green_relief"])

	for b in spec["bunkers"]:
		var outline := frame.poly(b["polygon"])
		if i == 1 and String(b["id"]) == "h02_fairway_right":
			var centre := Excavation.centroid(outline)
			for k in range(outline.size()):
				outline[k] = centre + (outline[k] - centre) * sqrt(1.15)
			hole.bunker_rim_lifts[String(b["id"])] = 0.3
		hole.bunker_polys.append([String(b["id"]), String(b["role"]), outline])
	for w in spec["water"]:
		if i == 12 and String(w["name"]) != "h13_water_0":
			continue  # only the tee-side crossing remains; the left channel is authored below
		hole.water_polys.append([String(w["name"]), frame.poly(w["polygon"])])
	for cp in spec.get("creek_paths", []):
		hole.creek_paths.append([frame.poly(cp["path"]), float(cp["width"])])
	if i in [12, 15, 16]:
		hole.extend_creeks = false
	if i == 10:
		# The marked diagonal channel replaces the crescent and its looping extensions.
		hole.water_polys.clear()
		hole.creek_paths.clear()
		hole.extend_creeks = false
		var creek := PackedVector2Array()
		for k in range(13):
			creek.append(frame.to_world(Vector2(370.0, -130.0).lerp(Vector2(560.0, 35.0), k / 12.0)))
		hole.creek_paths.append([creek, 8.0])
		# A separate kidney-shaped pond hugs the front-left of the green,
		# leaving a grassy bank between it and the diagonal creek behind.
		var pond := frame.poly([[414, -37], [418, -48], [430, -52], [442, -47], [452, -39], [460, -33], [470, -29], [478, -25], [481, -21], [475, -20], [467, -18], [458, -15], [449, -15], [436, -19], [424, -26], [417, -31]])
		hole.water_polys.append(["h11_greenside_pond", Excavation.smooth_polygon(pond, 2)])
	if i == 11:
		# Join the two painted fragments along the marked diagonal, without the south spur.
		hole.water_polys.clear()
		hole.creek_paths.clear()
		hole.extend_creeks = false
		hole.creek_paths.append([frame.poly([[15, -125], [72, -42], [94, -24], [115, -4], [139, 22], [180, 53], [210, 71]]), 9.0])
	if i == 16:
		hole.water_polys.clear()
		hole.creek_paths.clear()
	for w in spec["woods"]:
		hole.woods.append(frame.poly(w))
	for isl in spec.get("rough_islands", []):
		if i == 16:
			continue  # remove the two dark cutouts inside the blue-marked right-hand strip
		var a := frame.to_world(Vector2(float(isl[0]), float(isl[1])))
		var b := frame.to_world(Vector2(float(isl[2]), float(isl[3])))
		var radius := float(isl[4])
		if i == 8 and float(isl[1]) < 20.0:
			# Lengthen the left island at its tee end, keeping the far end and width.
			a += (a - b).normalized() * 6.0
		if i == 14 and float(isl[0]) > 400.0:
			# The small island nearest the green moves right and shrinks uniformly.
			var center := (a + b) * 0.5
			a = center + (a - center) * 0.9 + frame.right * 1.0
			b = center + (b - center) * 0.9 + frame.right * 1.0
			radius *= 0.9
		hole.rough_islands.append([a, b, radius])
	hole.painted = frame.poly(spec["painted_extent"])
	if i == 5:
		var tee_local := _v(spec["tees"][0]["center"])
		var opening_dir := (_v(route[1]) - tee_local).normalized()
		var opening_left := Vector2(opening_dir.y, -opening_dir.x)
		for tree in [["white_oak_A", 34, 34], ["red_maple_A", 52, 38], ["river_birch_A", 70, 34]]:
			var p := tee_local + opening_dir * float(tree[1]) + opening_left * float(tree[2])
			hole.planted_trees.append([tree[0], frame.to_world(p)])
	if i == 6:
		hole.planted_trees.append(["white_oak_A", frame.to_world(Vector2(92.0, -37.0))])
	if i == 10:
		var opening_dir := (_v(route[1]) - _v(route[0])).normalized()
		var opening_right := Vector2(-opening_dir.y, opening_dir.x)
		for side in [-1.0, 1.0]:
			for tree in [["white_oak_A", 48, 28], ["red_maple_A", 65, 29], ["loblolly_pine_A", 83, 28], ["white_oak_A", 101, 28], ["red_maple_A", 119, 29], ["loblolly_pine_A", 138, 29], ["loblolly_pine_A", 57, 39], ["white_oak_A", 86, 40], ["red_maple_A", 114, 39], ["loblolly_pine_A", 143, 41]]:
				var p := opening_dir * float(tree[1]) + opening_right * (float(side) * float(tree[2]))
				hole.planted_trees.append([tree[0], frame.to_world(p)])
	if i == 13:
		# Yellow mark: a smooth rough cutout with no automatic island vegetation.
		hole.rough_islands.append([frame.to_world(Vector2(181.0, 66.0)), frame.to_world(Vector2(211.0, 74.0)), 15.0, false])
		# Blue dot: a small group on the opening's right-hand side.
		hole.planted_trees.append(["white_oak_A", frame.to_world(Vector2(61.0, 43.0))])
		hole.planted_trees.append(["red_maple_A", frame.to_world(Vector2(66.0, 49.0))])
		hole.planted_trees.append(["river_birch_A", frame.to_world(Vector2(56.0, 51.0))])
	if i == 16:
		# Yellow: a separate mown opening on the right, with a collar around the pink island.
		hole.fairway_patches.append([frame.to_world(Vector2(22, 54)), frame.to_world(Vector2(132, 54)), 24.0])
		hole.fairway_patches.append([frame.to_world(Vector2(132, 45)), frame.to_world(Vector2(182, 40)), 22.0])
		var island_center := frame.to_world(Vector2(97, 40))
		hole.fairway_patches.append([island_center, island_center, 27.0])
		hole.rough_islands.append([island_center, island_center, 18.0, false])
		for tree in [["white_oak_A", 92, 35], ["red_maple_A", 104, 37], ["river_birch_A", 98, 48], ["eastern_red_cedar_A", 90, 45]]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
		# Red: a loose line of trees to the left of the tee and opening carry.
		for tree in [["loblolly_pine_A", 26, -17], ["white_oak_A", 49, -20], ["red_maple_A", 76, -19], ["longleaf_pine_A", 102, -18], ["river_birch_A", 128, -20], ["white_oak_A", 149, -21]]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 17:
		# Yellow: rough along both sides and across the foot of the marked fairway section.
		for cut in [[288, -140, 180, -137, 25], [180, -137, 123, -109, 25], [123, -109, 110, -32, 19], [268, -12, 111, -19, 25], [111, -19, 62, 13, 9]]:
			hole.rough_islands.append([frame.to_world(Vector2(cut[0], cut[1])), frame.to_world(Vector2(cut[2], cut[3])), float(cut[4]), false])
		# Blue: a small rough island with three individually placed trees.
		var island_center := frame.to_world(Vector2(337, 18))
		hole.rough_islands.append([island_center, island_center, 11.5, false])
		for tree in [["river_birch_A", 333, 14], ["eastern_red_cedar_A", 342, 16], ["red_maple_A", 337, 23]]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	for lf in spec["landforms"]:
		hole.landforms.append({"id": String(lf["id"]), "s0": float(lf["s_range_approx"][0]), "s1": float(lf["s_range_approx"][1])})
	return hole
