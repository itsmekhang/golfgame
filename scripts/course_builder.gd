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
## Shared by hole 11's own creek, the hole11<->12 bridge, and Golden Creek: a
## uniform width across the whole connected system avoids the wedge-shaped
## gap that appears where two independently-built stream polygons of
## DIFFERENT widths meet at a shared endpoint (see the i==10/11 creek blocks).
const WHITE_GOLD_WIDTH := 7.5
## Hole 2's tee-side extension: route distance, left width, right width (metres).
## Tapers toward the tee and blends into the existing dogleg fairway.
const HOLE_2_OPENING := [
	Vector3(44, 0, 0), Vector3(56, 11, 0), Vector3(72, 19, 3),
	Vector3(96, 38, 5), Vector3(116, 34, 7), Vector3(150, 29, 12),
	Vector3(176, 24, 17), Vector3(204, 24, 27), Vector3(236, 22, 46),
	Vector3(264, 0, 0),
]

## Holly's wooded carry opens into a narrow landing fairway, then the green approach.
## Distances follow the dogleg route; remaining values are left/right half widths.
const HOLE_18_FAIRWAY := [
	Vector3(0,0,0), Vector3(170,0,0), Vector3(184,9,10),
	Vector3(200,12,13), Vector3(235,13,14), Vector3(265,15,17),
	Vector3(288,18,22), Vector3(310,30,38), Vector3(340,50,58),
	Vector3(375,60,65), Vector3(500,60,65),
]

static func _hole18_widths(along: float) -> Vector2:
	for k in range(1, HOLE_18_FAIRWAY.size()):
		var a: Vector3 = HOLE_18_FAIRWAY[k - 1]
		var b: Vector3 = HOLE_18_FAIRWAY[k]
		if along <= b.x:
			var width := a.lerp(b, smoothstep(a.x, b.x, along))
			return Vector2(width.y, width.z)
	return Vector2(60,65)

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
		# Hole 11 played in reverse, per user request, so its creek crossing lands
		# next to hole 12's instead of at the far end of the hole. Pivoting the
		# frame around the tee alone would swing the green out past the tee to a
		# brand new, unbuilt spot (tried it: green ended up 470 m south into empty
		# terrain) -- what "turn the hole around" actually means is tee and green
		# trade places over the SAME physical corridor, so the new frame starts
		# at the old green, heads the opposite way, and lands back near the old
		# tee. `tees[i]`/`dirs[i]` themselves are untouched (they're also used
		# above for tee placement and next-hole spacing via prev_green), so no
		# other hole's position shifts -- only hole 11's own geometry is rebuilt
		# on this reversed frame.
		var hole_frame := Frame.new(tees[i], dirs[i])
		if i == 10:
			var old_green := hole_frame.to_world(_v(specs[i]["green"]["center"]))
			# Scooted further back over three rounds (per user: "theres hella
			# land behind the hole 11 tee box"; then "scoot hole 11 back a
			# little bit more"; then "just a tinnie tiny bit more"). Hole 11's
			# own creek is a straight line, and this shift only translates the
			# whole hole -- never rotates it -- so there is one shift distance
			# where that line passes almost exactly through Golden Creek's own
			# endpoint (solved directly: distance from the two creeks' meeting
			# point drops to ~0.0015 m at 156.16, versus 7.3 m at the previous
			# 145). Landing on it means the two creeks can simply continue
			# into one another with no artificial connector segment at all --
			# see _connect_white_gold().
			old_green += Vector2(0, 156.16)
			hole_frame = Frame.new(old_green, -dirs[i])
		var hole := _make_hole(layout, i, specs[i], hole_frame, rng)
		layout.holes.append(hole)
	_shape_amen_creeks(layout, Frame.new(tees[12], dirs[12]))
	_connect_white_gold(layout)
	for hole in layout.holes:
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


## Hole 12 feeds the opening crossing on 13; the smaller 13 channel follows the
## actual mown boundary and wraps the green's front/right, as in the hole diagram.
static func _shape_amen_creeks(layout: CourseLayout, frame13: Frame) -> void:
	var hole12 := layout.holes[11]
	var hole13 := layout.holes[12]
	var crossing: PackedVector2Array = hole13.water_polys[0][1]
	# Golden Bell enters the end of the broad crossing through the wooded
	# strip, rather than branching off its fairway-side bank.
	var corner := crossing[0]
	var crossing_axis := PackedVector2Array()
	for offset in [Vector2(7,25),Vector2(-4,8),Vector2(-23,-3),Vector2(-43,-8),Vector2(-65,-20),Vector2(-77,-22)]:
		crossing_axis.append(corner + offset)
	var widths := PackedFloat32Array([5.0,12.0,18.0,16.0,18.0,16.0])
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(crossing_axis.size()):
		var tangent := (crossing_axis[mini(i+1,crossing_axis.size()-1)] - crossing_axis[maxi(i-1,0)]).normalized()
		var side := Vector2(-tangent.y,tangent.x) * widths[i] * 0.5
		left.append(crossing_axis[i]+side)
		right.append(crossing_axis[i]-side)
	for i in range(right.size()-1,-1,-1): left.append(right[i])
	crossing = Excavation.smooth_polygon(left, 2)
	hole13.water_polys[0][1] = crossing
	var old: PackedVector2Array = hole12.creek_paths[0][0]
	var join := crossing_axis[0].lerp(crossing_axis[1],0.6)
	var keep := old[1]
	var connected := PackedVector2Array([
		join, crossing_axis[0] + Vector2(10,16),
		Vector2(lerpf(join.x, keep.x, 0.6), join.y + 65),
		Vector2(keep.x - 40, keep.y + 25), old[2]])
	for i in range(3, old.size()): connected.append(old[i])
	hole12.creek_paths[0] = [_smooth_creek_path(connected), 5.0, true]
	# Query the same fairway/green shapes used by the terrain instead of drawing
	# a diagonal across the fairway from sparse approximate image coordinates.
	layout._build_turf_areas()
	var fw := layout.fairways[12]
	var green := layout.greens[12]
	var path := PackedVector2Array()
	for along in range(165, 371, 5):
		var edge := 0.0
		var found := false
		for across in range(0, 220, 2):
			if fw.signed_distance(frame13.to_world(Vector2(along, across))) < 0.0:
				edge = float(across)
				found = true
				break
		if not found: continue
		var lo := edge - 2.0
		var hi := edge
		for iteration in range(10):
			var mid := (lo + hi) * 0.5
			if fw.signed_distance(frame13.to_world(Vector2(along, mid))) < 0.0:
				hi = mid
			else:
				lo = mid
		path.append(frame13.to_world(Vector2(along, (lo + hi) * 0.5 - 5.5)))
	for degrees in range(160, -1, -8):
		var angle := deg_to_rad(float(degrees))
		var direction := frame13.dir * cos(angle) + frame13.right * sin(angle)
		path.append(green.center + direction * (green.radius_at(direction.angle()) + 10.0))
	path = _smooth_creek_path(path)
	# Smoothing across a sharp fairway-width change can clip the mown corner.
	# Project that short section back outside the actual boundary.
	for i in range(path.size()):
		if (path[i] - frame13.tee).dot(frame13.dir) < 165.0: continue
		if green.signed_distance(path[i]) < 20.0: continue
		for iteration in range(8):
			var sd := fw.signed_distance(path[i])
			if sd >= 4.5: break
			var p := path[i]
			var normal := Vector2(fw.signed_distance(p + Vector2(.5,0))-fw.signed_distance(p-Vector2(.5,0)), fw.signed_distance(p+Vector2(0,.5))-fw.signed_distance(p-Vector2(0,.5))).normalized()
			path[i] += normal * (4.6-sd)
	hole13.creek_paths = [[path, 3.5, true]]


## Hole 11's own diagonal creek and hole 12's Golden Creek land close together
## near hole 11's tee. Every join tried before this landed a visible defect --
## a hand-authored bridge segment (whether long, or short after hole 11 was
## scooted back) left a gap at its seam even with matching widths, because
## make_stream() builds each creek_paths entry as its own independent polygon
## and Excavation.smooth_polygon() rounds off the end caps regardless of what
## meets them there; an artificial connector built to close that gap instead
## then turned sharply enough (make_stream() offsets each point by a fixed
## width along its local normal) that its polygon self-intersected -- not
## just a cosmetic sliver, but enough that Geometry2D.triangulate_polygon()
## silently produced zero triangles for the whole hazard, which is why the
## creek stopped rendering at all. Hole 11's shift was tuned (see the i == 10
## block above) so its own straight creek line now passes almost exactly
## through Golden Creek's endpoint -- this just finds that point by
## projecting the endpoint onto the creek's own segments and trims everything
## before it, so the two creeks simply continue into one another with no
## artificial connector, and nothing left to self-intersect.
static func _connect_white_gold(layout: CourseLayout) -> void:
	var hole11 := layout.holes[10]
	var hole12 := layout.holes[11]
	var h11_creek: PackedVector2Array = hole11.creek_paths[0][0]
	var golden: PackedVector2Array = hole12.creek_paths[0][0]
	var p0 := golden[golden.size() - 1]
	var best_i := 0
	var best_t := 0.0
	var best_d := INF
	for k in range(h11_creek.size() - 1):
		var a := h11_creek[k]
		var b := h11_creek[k + 1]
		var ab := b - a
		var t := clampf((p0 - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p0.distance_to(a.lerp(b, t))
		if d < best_d:
			best_d = d
			best_i = k
			best_t = t
	var join_point := h11_creek[best_i].lerp(h11_creek[best_i + 1], best_t)
	var merged := PackedVector2Array()
	for k in range(maxi(0, golden.size() - 6), golden.size()):
		merged.append(golden[k])
	if p0.distance_to(join_point) > 0.5:
		merged.append(join_point)
	for k in range(best_i + 1, h11_creek.size()):
		merged.append(h11_creek[k])
	hole11.creek_paths[0] = [_smooth_creek_path(merged), WHITE_GOLD_WIDTH, true]


## Golden Bell's green setting, from the Masters render and course map: the Hogan bridge
## (three arches) crosses the creek to the front-left of the green, a second stone bridge
## sits where the creek runs off to the right -- right over the seam between Golden Creek and
## White Creek -- with trees closing in behind it so the water disappears into the woods
## instead of visibly ending. Behind the green the two back bunkers sit on a backstop that
## rises into a pine-straw bank planted with azaleas and dogwoods (landforms
## h12_rear_backstop / h12_azalea_bank), and tall trees ring the back and left of the green.
## All positions are in the hole's local frame (metres from the tee, + = golfer's right).
static func _dress_golden_bell(hole: CourseLayout.Hole, frame: Frame) -> void:
	# Bridges: [centre, creek direction, span, width, arches]. Each crosses at right angles.
	# Second bridge: just past the green's right side (per user's mark), not out at the seam.
	for br in [[Vector2(105.5, -13.0), Vector2(0.718, 0.696), 13.0, 2.6, 3], [Vector2(142.0, 24.0), Vector2(0.78, 0.625), 12.0, 2.4, 1]]:
		var c: Vector2 = br[0]
		var across: Vector2 = Vector2(br[1].y, -br[1].x)
		var half: float = float(br[2]) * 0.5
		hole.bridges.append([frame.to_world(c - across * half), frame.to_world(c + across * half), float(br[3]), int(br[4])])
	# Woods swallowing the creek downstream of the second bridge, both banks, so its run-off
	# disappears into the trees right behind the green (per user's red mark).
	var run := Vector2(0.78, 0.625)
	var run_bank := Vector2(0.625, -0.78)
	var run_species := ["loblolly_pine_A", "white_oak_A", "loblolly_pine_A", "sweetgum_A", "red_maple_A", "loblolly_pine_A", "tulip_poplar_A"]
	var r := 0
	for along in [9.0, 14.0, 19.0, 24.0, 30.0, 36.0, 42.0, 49.0, 56.0, 63.0, 70.0, 77.0, 84.0]:
		for side in [-1.0, 1.0]:
			for off in [5.5, 10.5, 16.0]:
				var stagger := 2.5 if off > 8.0 else 0.0
				var p: Vector2 = Vector2(142.0, 24.0) + run * (along + stagger) + run_bank * (side * off)
				hole.planted_trees.append([run_species[r % run_species.size()], frame.to_world(p)])
				r += 1
	# Fill the marked dry strip from the tee-side bridge entrance toward the woods.
	# Stagger the trunks across the bank, leaving the bridge and creek open.
	for tree in [
		["loblolly_pine_A", 137, 36], ["white_oak_A", 129, 38],
		["sweetgum_A", 133, 45], ["loblolly_pine_A", 124, 45],
		["red_maple_A", 128, 53], ["loblolly_pine_A", 119, 52],
		["white_oak_A", 122, 61], ["loblolly_pine_A", 114, 60],
	]:
		hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	# Further woods along the creek out to its seam with White Creek: both banks, staggered.
	var down := Vector2(0.764, 0.645)
	var bank := Vector2(0.645, -0.764)
	var far_species := ["loblolly_pine_A", "white_oak_A", "sweetgum_A", "loblolly_pine_A", "red_maple_A", "tulip_poplar_A"]
	var k := 0
	for along in [9.0, 16.0, 23.0, 30.0, 38.0, 46.0, 55.0, 64.0, 74.0]:
		for side in [-1.0, 1.0]:
			for off in [8.0, 14.0]:
				var stagger := 3.5 if off > 10.0 else 0.0
				var p: Vector2 = Vector2(212.5, 73.5) + down * (along + stagger) + bank * (side * off)
				hole.planted_trees.append([far_species[k % far_species.size()], frame.to_world(p)])
				k += 1
	for p in [Vector2(203.0, 82.0), Vector2(201.0, 75.0), Vector2(223.0, 66.0), Vector2(226.0, 73.0), Vector2(97.0, -4.0), Vector2(113.0, -23.0)]:
		hole.planted_shrubs.append(["azalea_pink_A" if int(p.x) % 2 == 0 else "azalea_white_A", frame.to_world(p)])
	# Tall trees round the back and left of the green.
	var ring := [
		["loblolly_pine_A", 190, -42], ["white_oak_A", 196, -30], ["loblolly_pine_A", 190, -18],
		["longleaf_pine_A", 196, -6], ["loblolly_pine_A", 190, 6], ["white_oak_A", 196, 18],
		["loblolly_pine_A", 190, 30], ["tulip_poplar_A", 204, -36], ["loblolly_pine_A", 208, -22],
		["sweetgum_A", 204, -9], ["loblolly_pine_A", 208, 4], ["longleaf_pine_A", 204, 17],
		["loblolly_pine_A", 208, 30], ["eastern_white_pine_A", 216, -14], ["loblolly_pine_A", 216, 10],
		["loblolly_pine_A", 168, -36], ["white_oak_A", 156, -32], ["loblolly_pine_A", 144, -30],
		["red_maple_A", 132, -31], ["loblolly_pine_A", 122, -33], ["sweetgum_A", 176, -46],
		["loblolly_pine_A", 162, -46], ["white_oak_A", 148, -44], ["loblolly_pine_A", 134, -45],
	]
	for t in ring:
		hole.planted_trees.append([t[0], frame.to_world(Vector2(t[1], t[2]))])
	# Flowering dogwoods standing on the bank in front of the pines.
	for t in [["flowering_dogwood_white_A", 178, -27], ["flowering_dogwood_pink_A", 181, -12], ["flowering_dogwood_white_A", 179, 11], ["flowering_dogwood_pink_A", 182, 25]]:
		hole.planted_trees.append([t[0], frame.to_world(Vector2(t[1], t[2]))])
	# The azalea bank: loose clumps across the face of the hill above the back bunkers,
	# on bare pine straw.
	var azaleas := ["azalea_pink_A", "azalea_red_A", "azalea_white_A", "azalea_pink_A", "rhododendron_A", "azalea_red_A"]
	var n := 0
	for row in [[167.0, 3.4], [172.0, 0.0], [177.0, 1.7]]:
		var y := -32.0 + float(row[1])
		while y <= 32.0:
			hole.planted_shrubs.append([azaleas[n % azaleas.size()], frame.to_world(Vector2(float(row[0]) + float(n % 3) * 0.8, y))])
			n += 1
			y += 3.6
	for c in [Vector2(176, -24), Vector2(176, -8), Vector2(176, 8), Vector2(176, 24), Vector2(186, -16), Vector2(186, 0), Vector2(186, 16)]:
		hole.straw_beds.append([frame.to_world(c), 9.0])


const APPROACH_MAX_RISE := 1.0  # metres the datum may climb over the last 60 m into a green
const APPROACH_SPAN := 280.0  # metres over which a steeper finish is reshaped


## No green sits up on a plateau: where the hole's profile climbs more than APPROACH_MAX_RISE
## over the last 60 m, the last APPROACH_SPAN metres become a smooth curve (cubic Hermite from
## the existing grade to level at the green) that does its climbing earlier, down the fairway.
## The green's own height is unchanged, so the next hole's datum -- and every hole after it --
## stays where it was.
static func _ease_green_approach(hole: CourseLayout.Hole) -> void:
	var prof := hole.profile
	var n := prof.size()
	if n < 2:
		return
	var xe := prof[n - 1].x
	var ye := prof[n - 1].y
	if ye - _profile_lerp(prof, xe - 60.0) <= APPROACH_MAX_RISE:
		return
	var span := minf(APPROACH_SPAN, xe * 0.65)
	var xa := xe - span
	var ya := _profile_lerp(prof, xa)
	var m0 := (_profile_lerp(prof, xa) - _profile_lerp(prof, xa - 20.0)) / 20.0
	var out := PackedVector2Array()
	for p in prof:
		if p.x < xa - 1.0:
			out.append(p)
	var steps := int(span / 20.0)
	for k in range(steps + 1):
		var t := float(k) / steps
		var t2 := t * t
		var t3 := t2 * t
		var y := (2.0 * t3 - 3.0 * t2 + 1.0) * ya + (t3 - 2.0 * t2 + t) * span * m0 + (-2.0 * t3 + 3.0 * t2) * ye
		out.append(Vector2(xa + span * t, y))
	hole.profile = out


static func _profile_lerp(prof: PackedVector2Array, x: float) -> float:
	if x <= prof[0].x:
		return prof[0].y
	for k in range(1, prof.size()):
		if x <= prof[k].x:
			return lerpf(prof[k - 1].y, prof[k].y, (x - prof[k - 1].x) / maxf(prof[k].x - prof[k - 1].x, 0.001))
	return prof[prof.size() - 1].y


static func _smooth_creek_path(path: PackedVector2Array) -> PackedVector2Array:
	for pass_index in range(2):
		var smooth := PackedVector2Array([path[0]])
		for i in range(1, path.size()):
			smooth.append(path[i - 1].lerp(path[i], 0.25))
			smooth.append(path[i - 1].lerp(path[i], 0.75))
		smooth.append(path[-1])
		path = smooth
	return path


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
	hole.green_height = rng.randf_range(0.3, 0.7) * 0.6  # a gentle crown, never a table
	if i in [2, 5, 8, 12]:
		hole.green_height *= 0.4
	hole.tee_height_offset = -0.5 if i == 1 else 0.0
	if i == 9:
		# Start the back nine on a lower shared hillside, not hole 9's high datum
		# with an isolated sunken tee. The gentle 10/11 profiles below then meet
		# across the wooded gap without a steep compensating bank beside hole 10.
		hole.tee_datum_offset = -16.0
		hole.tee_apron = Vector2(3.0, 60.0)
	if i == 7:
		# Yellow Jasmine: Pampas' green came down 2.5 m (the i == 6 profile tweak below); keep
		# this tee -- and so holes 8-18 -- on their original datum.
		hole.tee_datum_offset = 2.5
	if i == 13:
		# Chinese Fir: Azalea's green came down 3 m (the i == 12 profile tweak below); keep
		# this tee -- and so holes 14-18 -- on their original datum.
		hole.tee_datum_offset = 3.0
	if i == 10:
		# Two low, level platforms: men's tee lowest, women's tee above it,
		# with the rough carry climbing toward the higher landing fairway.
		hole.tee_apron = Vector2(6.0, 45.0)
		hole.opening_grade_length = 220.0

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
		# Pampas: the last 100 m climbed 5 m into a green and five bunkers already set on a
		# raised platform, so the whole complex sat on a plateau (per user). Ease the end of
		# the climb by 2.5 m (8 -> 5.5); hole 8's tee_datum_offset keeps holes 8-18 in place.
		if i == 6 and float(s[0]) >= 0.85:
			elevation = {0.9: 4.5, 1.0: 5.5}.get(float(s[0]), elevation)
		# Yellow Jasmine: this hole's +22m climb was the single biggest contributor to
		# holes 9-10 sitting on a high plateau, which then dropped so hard into hole 11
		# that the creek between them read as a canyon. Halve the climb here so the
		# whole downstream chain (9's tee/green, 10's tee/green) comes down with it.
		if i == 7:
			elevation *= 0.5
		# These opposite-running holes share a hillside. Keep both gently downhill;
		# their original combined drop created a 30m+ cross-slope across the woods.
		if i in [9, 10]:
			elevation *= 0.2
		# Azalea: the last 35 m climbed 3 m into a green already raised on a bank, so it sat
		# 4+ m above the approach. Even a third of that read as perched; the green now sits
		# level with its approach (no climb, no raised bank in the landforms).
		if i == 12 and float(s[0]) >= 0.93:
			elevation = -4.0
		# Carolina Cherry: a gradual rise out of the valley into the green and bunkers.
		if i == 8 and float(s[0]) >= 0.7:
			elevation = -10.0 + (elevation + 10.0) * 0.25
		hole.profile.append(Vector2(float(s[0]) * route_len, elevation))
	if i == 10:
		# Shape the opening in the current direction of play. Keep the men's
		# platform 16.5 m below the shared datum, then the women's 5 m higher (raised
		# from 1.3 m per user, so it stands a third of the way up the bank).
		# This puts the landing fairway about 15.5 m above the back tee (it was
		# 10.5 m; per user, the tees needed to sit clearly below the fairway).
		# Spread the climb to the landing fairway over the full rough carry.
		# Retain the approach/green datum: reversing and re-zeroing the whole
		# profile raised the tees and also shifted every subsequent hole.
		hole.profile[0] = Vector2(0.0, -16.5)
		hole.profile[1] = Vector2(route_len * 0.232, -11.5)
		hole.profile[2] = Vector2(hole.opening_grade_length, -0.8)
		# Spread the climb across the carry: without this midpoint the 14 m rise bunched
		# into one wall (the steepest 2 m now rises about 0.4 m).
		hole.profile.insert(2, Vector2((hole.profile[1].x + hole.opening_grade_length) * 0.5, -6.2))

	if i != 10:
		_ease_green_approach(hole)

	# mown fairway: half widths left/right of the routing every profile_step metres
	hole.fairway_profile = PackedVector3Array()
	var wsum := 0.0
	var wcount := 0
	for s in spec["fairway_profile"]:
		var l := float(s[1])
		var r := float(s[2])
		if i == 1:
			var along := hole.fairway_profile.size() * float(_data.get("profile_step_m", 4.0))
			for k in range(1, HOLE_2_OPENING.size()):
				var a: Vector3 = HOLE_2_OPENING[k - 1]
				var b: Vector3 = HOLE_2_OPENING[k]
				if along >= a.x and along <= b.x:
					var width := a.lerp(b, smoothstep(a.x, b.x, along))
					l = maxf(l, width.y)
					r = maxf(r, width.z)
					break
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
			# A rough carry directly ahead of the tee; the mown landing corridor
			# opens gradually farther down the hole. Tee boxes stay independently mown.
			var opening_fairway := smoothstep(175.0, 205.0, float(s[0]))
			l *= opening_fairway
			r *= opening_fairway
		if i == 17:
			var along := hole.fairway_profile.size() * float(_data.get("profile_step_m", 4.0))
			var width := _hole18_widths(along)
			l = minf(l, width.x)
			r = minf(r, width.y)
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
		if i == 9 and String(b["id"]) == "h10_fairway_branching":
			# Place the branching bunker toward the left of the fairway.
			# Follow the local dogleg segment for the lateral offset.
			var seg_a := hole.waypoints[3]
			var seg_b := hole.waypoints[4]
			var seg_fwd := Vector2(seg_b.x - seg_a.x, seg_b.z - seg_a.z).normalized()
			var seg_right := Vector2(-seg_fwd.y, seg_fwd.x)
			var shift := seg_right * 3.0
			for k in range(outline.size()):
				outline[k] += shift
		hole.bunker_polys.append([String(b["id"]), String(b["role"]), outline])
	if i == 12:
		# Three small traps around the opening fairway, on the tee side of
		# the broad crossing: two woodland-side and one creek-side.
		# Keep the forward tee and a continuous grass route between them clear.
		var opening_bunkers := [
			["h13_opening_woodland_near", [[41, 48], [43, 47], [46, 48], [47, 50], [46, 52], [46, 54], [43, 55], [41, 53], [40, 50]]],
			["h13_opening_woodland_far", [[43, 57], [46, 57], [48, 59], [49, 62], [47, 64], [44, 65], [42, 63], [42, 60]]],
			["h13_opening_creek_side", [[60, 66], [63, 66], [64, 69], [64, 72], [62, 75], [59, 75], [58, 73], [59, 70], [58, 68]]],
		]
		for entry in opening_bunkers:
			hole.bunker_polys.append([entry[0], "fairway", Excavation.smooth_polygon(frame.poly(entry[1]), 2)])
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
		for k in range(97):
			var local := Vector2(370.0,-130.0).lerp(Vector2(560.0,35.0),k/96.0)
			# Ease the back bank toward the green while preserving the creek's
			# endpoints and the existing connection to hole 12.
			local.y += 8.0*smoothstep(482.0,496.0,local.x)*(1.0-smoothstep(510.0,535.0,local.x))
			creek.append(frame.to_world(local))
		# Follow the grade between holes 10/11 instead of excavating the entire
		# diagonal down to its lowest bank (which created a deep artificial trench).
		hole.creek_paths.append([creek, WHITE_GOLD_WIDTH, true])
		# Kidney-shaped pond: the near bank follows the full left-hand putting
		# edge with a narrow fringe; the far bank has two lobes and an inlet.
		var pond_green := GreenArea.new()
		pond_green.setup_radial(hole.green_center,hole.green_radial,hole.green_rotation,i)
		var pond := PackedVector2Array()
		for along in range(454,477,2):
			var lo := -65.0
			var hi := -5.0
			for iteration in range(16):
				var mid := (lo+hi)*0.5
				if pond_green.signed_distance(frame.to_world(Vector2(along,mid))) > 2.3:
					lo = mid
				else:
					hi = mid
			pond.append(frame.to_world(Vector2(along,(lo+hi)*0.5)))
		# Round both joins with the green-side bank. The creek-side shoulder
		# turns inward before the former pointed tip, preserving its dry bank.
		var outer_bank := [[478,-18.8],[479,-20],[479.3,-21.7],[479,-23.4],[478,-25.2],[476.5,-27.4],[475,-30],[473,-33],[469,-36],[466,-36],[462,-33],[459,-35],[457,-43],[453,-49],[449,-49],[445,-44],[442,-37],[442,-28],[444,-20],[446,-15],[448,-12],[450,-10.8],[452,-10.5]]
		for point in outer_bank:
			var local := _v(point)
			# A metre-wide separator at the creek: a bank, not a landing strip.
			if local.x >= 449.0 and local.y < -20.0:
				local += Vector2(0.65,-0.76)*0.85
			pond.append(frame.to_world(local))
		hole.water_polys.append(["h11_greenside_pond", Excavation.smooth_polygon(pond, 2)])
		# Per user annotation: the strip of rough on the green's right side
		# (roughly where the fairway already widens back out a bit further
		# along) should be fairway too, not just past the green.
		hole.fairway_patches.append([hole.green_center + frame.dir * -15.0 + frame.right * 20.0, hole.green_center + frame.dir * 25.0 + frame.right * 20.0, 38.0])
		# Per user: the creek banks round the green are mown first cut -- the far bank from
		# the water to the treeline (rough on the left, the fairway lobe on the right) and
		# the dry wedge between the pond's west tip and the creek. Outlines follow the
		# creek's own centreline above (local metres), ending where the far-bank fairway
		# and its first cut end.
		for zone in [
			["h11_far_bank_woods", [[419.5, -87.0], [421.5, -85.3], [423.4, -83.6], [425.4, -81.9], [427.4, -80.2], [429.4, -78.4], [431.4, -76.7], [433.3, -75.0], [435.3, -73.3], [437.3, -71.6], [439.3, -69.8], [441.2, -68.1], [443.2, -66.4], [445.2, -64.7], [447.2, -63.0], [449.2, -61.2], [451.1, -59.5], [453.1, -57.8], [455.1, -56.1], [457.1, -54.4], [459.1, -52.7], [461.0, -50.9], [463.0, -49.2], [465.0, -47.5], [467.0, -45.8], [469.0, -44.1], [470.9, -42.3], [472.9, -40.6], [474.9, -38.9], [476.9, -37.2], [478.9, -35.5], [480.8, -33.8], [482.8, -32.0], [484.8, -29.5], [486.8, -26.4], [488.8, -23.1], [499.1, -29.2], [497.0, -32.8], [494.5, -36.5], [491.6, -40.1], [488.8, -42.7], [486.7, -44.5], [484.7, -46.2], [482.8, -48.0], [480.8, -49.7], [478.8, -51.4], [476.8, -53.1], [474.8, -54.8], [472.9, -56.6], [470.9, -58.3], [468.9, -60.0], [466.9, -61.7], [465.0, -63.4], [463.0, -65.2], [461.0, -66.9], [459.0, -68.6], [457.0, -70.3], [455.1, -72.0], [453.1, -73.7], [451.1, -75.5], [449.1, -77.2], [447.1, -78.9], [445.2, -80.6], [443.2, -82.3], [441.2, -84.1], [439.2, -85.8], [437.2, -87.5], [435.3, -89.2], [433.3, -90.9], [431.3, -92.7], [429.3, -94.4], [427.3, -96.1]]],
			["h11_far_bank_fairway", [[488.8, -23.1], [490.7, -19.7], [492.7, -16.6], [494.7, -13.9], [496.7, -12.0], [498.6, -10.3], [500.6, -8.6], [502.6, -6.8], [504.6, -5.1], [506.6, -3.4], [508.5, -1.7], [510.5, 0.0], [512.5, 1.5], [514.5, 2.8], [516.5, 3.9], [518.4, 4.8], [520.4, 5.6], [522.4, 6.4], [524.4, 7.2], [526.4, 8.0], [528.3, 8.9], [530.3, 10.0], [532.3, 11.2], [537.5, 3.6], [535.9, 0.3], [534.6, -3.6], [532.8, -6.8], [531.2, -9.6], [529.7, -12.3], [528.4, -14.1], [527.3, -15.2], [526.5, -16.1], [525.9, -16.6], [525.4, -16.9], [524.7, -17.4], [523.3, -18.7], [521.3, -20.4], [519.3, -22.1], [517.2, -23.7], [514.6, -24.7], [512.0, -25.7], [510.1, -26.7], [509.2, -26.5], [506.8, -26.2], [502.6, -26.9], [496.7, -27.8]]],
			["h11_pond_creek_wedge", [[435.3, -73.3], [437.3, -71.6], [439.3, -69.8], [441.2, -68.1], [443.2, -66.4], [445.2, -64.7], [447.2, -63.0], [449.2, -61.2], [451.1, -59.5], [453.1, -57.8], [455.1, -56.1], [457.1, -54.4], [459.1, -52.7], [461.0, -50.9], [463.0, -49.2], [465.0, -47.5], [467.0, -45.8], [469.0, -44.1], [470.9, -42.3], [472.9, -40.6], [474.9, -38.9], [476.9, -37.2], [478.9, -35.5], [480.8, -33.8], [482.8, -32.0], [473.3, -23.1], [472.2, -24.0], [470.3, -25.7], [468.4, -27.4], [466.4, -29.1], [464.4, -30.8], [462.4, -32.5], [460.4, -34.2], [458.5, -36.0], [456.5, -37.7], [454.5, -39.4], [452.5, -41.1], [450.5, -42.8], [448.6, -44.6], [446.6, -46.3], [447.2, -51.0], [445.2, -52.7], [443.3, -54.5], [441.3, -56.2], [439.3, -57.9], [437.3, -59.6], [435.3, -61.3], [433.4, -63.0], [431.4, -64.8], [429.4, -66.5]]],
		]:
			hole.first_cut_zones.append(frame.poly(zone[1]))
		# The join to hole 12's Golden Creek is built in _connect_white_gold(),
		# after every hole's own creek shape exists -- see that function for why
		# a separately-built bridge segment (tried twice: a long diagonal, then
		# a short one after this hole was scooted back) can never close the gap.
	if i == 11:
		# Join the two painted fragments along the marked diagonal, without the south spur.
		hole.water_polys.clear()
		hole.creek_paths.clear()
		hole.extend_creeks = false
		# make_stream() offsets the path left/right by half its width using each
		# point's local direction; the original trace's first leg alone ran 100 m
		# between two points with nothing in between, and the extra points added
		# for the hole12/13 join made that corner sharp enough that the offset
		# bands crossed themselves -- the water polygon actually reached ~78 m
		# wide at that corner (measured directly), which is what read as "way too
		# wide" and, where it self-intersected, as bare ground instead of water.
		# Fixed by resampling the whole path every ~15 m (no long unsupported
		# spans left to kink) and narrowing it -- the hole 12 crossing is the
		# smaller creek, not a 9 m river.
		var golden_creek_local := [[15, -125], [72, -42], [94, -24], [115, -4], [139, 22], [180, 53], [210, 71]]
		var golden_creek_world := PackedVector2Array()
		golden_creek_world.append(frame.to_world(_v(golden_creek_local[0])))
		for gi in range(golden_creek_local.size() - 1):
			var ga: Vector2 = _v(golden_creek_local[gi])
			var gb: Vector2 = _v(golden_creek_local[gi + 1])
			var gsteps := maxi(1, roundi(ga.distance_to(gb) / 15.0))
			for gk in range(1, gsteps + 1):
				golden_creek_world.append(frame.to_world(ga.lerp(gb, float(gk) / gsteps)))
		hole.creek_paths.append([golden_creek_world, WHITE_GOLD_WIDTH])
		_dress_golden_bell(hole, frame)
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
			a += (a - b).normalized() * 25.0
		if i == 8 and float(isl[1]) >= 20.0:
			# The right island sat well short of the right-side treeline, leaving a
			# fairway gap between the two -- widen it until it merges into the rough.
			radius = 30.0
		if i == 14 and float(isl[0]) > 400.0:
			# The small island nearest the green moves right and shrinks uniformly.
			var center := (a + b) * 0.5
			a = center + (a - center) * 0.9 + frame.right * 1.0
			b = center + (b - center) * 0.9 + frame.right * 1.0
			radius *= 0.9
		hole.rough_islands.append([a, b, radius])
	if i == 8:
		# The right side of the landing area runs generously wide (60+ m) before the
		# dogleg pinches in -- cut the outer band of that width back to rough instead
		# of leaving it all cut fairway, no automatic tree/shrub cover in the cut.
		hole.rough_islands.append([Vector2(1591.72, -229.43), Vector2(1604.03, -278.34), 18.0, false])
		# A tighter dogleg left: a proper tree-covered rough patch (not a bare cut)
		# along the still-wide early stretch of the right side, before the existing
		# cut above takes over -- closes the open-fairway gap between the tee and
		# where the right island now reaches.
		hole.rough_islands.append([Vector2(1572.31, -174.55), Vector2(1583.60, -206.22), 22.0])
	hole.painted = frame.poly(spec["painted_extent"])
	if i == 4:
		# Magnolia: fill the marked rough along the opening's left edge,
		# with a rounded shoulder that joins the existing landing fairway.
		hole.fairway_patches.append([frame.to_world(Vector2(110, 8)), frame.to_world(Vector2(166, 10)), 25.0])
		# Continue the left edge through the rough gap up to the fairway bunkers.
		hole.fairway_patches.append([frame.to_world(Vector2(158, 10)), frame.to_world(Vector2(238, 22)), 25.0])
	if i == 5:
		var tee_local := _v(spec["tees"][0]["center"])
		var opening_dir := (_v(route[1]) - tee_local).normalized()
		var opening_left := Vector2(opening_dir.y, -opening_dir.x)
		for tree in [["white_oak_A", 34, 34], ["red_maple_A", 52, 38], ["river_birch_A", 70, 34]]:
			var p := tee_local + opening_dir * float(tree[1]) + opening_left * float(tree[2])
			hole.planted_trees.append([tree[0], frame.to_world(p)])
	if i == 1:
		# Tree belt in the right rough, filled toward the fairway and the tee.
		# Individually placed trees share the normal instancing and distance tiers.
		for tree in [
			["loblolly_pine_A", 30, 110], ["white_oak_A", 45, 100],
			["loblolly_pine_A", 58, 119], ["red_maple_A", 72, 96],
			["white_oak_A", 84, 111], ["loblolly_pine_A", 96, 91],
			["loblolly_pine_A", 105, 125], ["red_maple_A", 112, 109],
			["white_oak_A", 125, 102], ["loblolly_pine_A", 136, 120],
			["red_maple_A", 149, 115], ["loblolly_pine_A", 160, 138],
			["white_oak_A", 176, 154], ["loblolly_pine_A", 187, 174],
			["loblolly_pine_A", 49, 64], ["white_oak_A", 50, 73],
			["loblolly_pine_A", 59, 66], ["red_maple_A", 58, 76],
			["loblolly_pine_A", 59, 86], ["white_oak_A", 71, 66],
			["loblolly_pine_A", 69, 85], ["red_maple_A", 80, 77],
			["loblolly_pine_A", 78, 86], ["white_oak_A", 78, 105],
			["loblolly_pine_A", 90, 84], ["red_maple_A", 89, 96],
			["loblolly_pine_A", 99, 104], ["white_oak_A", 99, 114],
			["loblolly_pine_A", 110, 95], ["red_maple_A", 120, 124],
			["loblolly_pine_A", 127, 116], ["white_oak_A", 130, 133],
			["loblolly_pine_A", 141, 146], ["red_maple_A", 147, 125],
			["loblolly_pine_A", 147, 134], ["white_oak_A", 149, 145],
			["loblolly_pine_A", 158, 155], ["red_maple_A", 168, 136],
			["loblolly_pine_A", 171, 144], ["white_oak_A", 178, 165],
		]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 6:
		hole.planted_trees.append(["white_oak_A", frame.to_world(Vector2(92.0, -37.0))])
		# Both flanks were thin right down to the tee, with a wide bare gap before the
		# treeline started. Two dense staggered rows hugging the traced fairway edge on
		# each side, plus trees close to the tee box itself, close that gap all the way out.
		for tree in [
			["loblolly_pine_A", 8, -28], ["white_oak_A", 15, -26],
			["loblolly_pine_A", 20, -22], ["white_oak_A", 20, -30],
			["red_maple_A", 30, -22], ["loblolly_pine_A", 30, -30],
			["white_oak_A", 40, -22], ["red_maple_A", 40, -30],
			["loblolly_pine_A", 50, -22], ["white_oak_A", 50, -30],
			["red_maple_A", 60, -23], ["loblolly_pine_A", 60, -31],
			["white_oak_A", 70, -23], ["red_maple_A", 70, -31],
			["loblolly_pine_A", 80, -23], ["white_oak_A", 80, -31],
			["red_maple_A", 90, -23], ["loblolly_pine_A", 90, -31],
			["white_oak_A", 100, -23], ["red_maple_A", 100, -31],
			["loblolly_pine_A", 110, -25], ["white_oak_A", 110, -33],
			["red_maple_A", 120, -30], ["loblolly_pine_A", 120, -38],
			["white_oak_A", 130, -35], ["red_maple_A", 130, -43],
			["loblolly_pine_A", 140, -46], ["white_oak_A", 140, -51],
			["red_maple_A", 150, -52], ["loblolly_pine_A", 150, -60],
			["white_oak_A", 160, -62], ["red_maple_A", 160, -66],
		]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
		for tree in [
			["white_oak_A", 8, 24], ["loblolly_pine_A", 15, 22],
			["loblolly_pine_A", 20, 17], ["white_oak_A", 20, 25],
			["red_maple_A", 30, 17], ["loblolly_pine_A", 30, 25],
			["white_oak_A", 40, 17], ["red_maple_A", 40, 25],
			["loblolly_pine_A", 50, 17], ["white_oak_A", 50, 25],
			["red_maple_A", 60, 17], ["loblolly_pine_A", 60, 25],
			["white_oak_A", 70, 18], ["red_maple_A", 70, 26],
			["loblolly_pine_A", 80, 17], ["white_oak_A", 80, 25],
			["red_maple_A", 90, 17], ["loblolly_pine_A", 90, 25],
			["white_oak_A", 100, 17], ["red_maple_A", 100, 25],
			["loblolly_pine_A", 110, 18], ["white_oak_A", 110, 26],
			["red_maple_A", 120, 22], ["loblolly_pine_A", 120, 30],
			["white_oak_A", 130, 27], ["red_maple_A", 130, 35],
			["loblolly_pine_A", 140, 33], ["white_oak_A", 140, 41],
			["red_maple_A", 150, 39], ["loblolly_pine_A", 150, 47],
			["white_oak_A", 160, 44], ["red_maple_A", 160, 52],
		]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 10:
		var opening_dir := (_v(route[1]) - _v(route[0])).normalized()
		var opening_right := Vector2(-opening_dir.y, opening_dir.x)
		for side in [-1.0, 1.0]:
			# Close the bare gap beside the back tee and taper into the existing
			# wooded neck, leaving a clear central launch lane between the crowns.
			for tree in [
				["loblolly_pine_A", 8, 14], ["white_oak_A", 20, 15],
				["loblolly_pine_A", 33, 17], ["red_maple_A", 46, 19],
				["loblolly_pine_A", 60, 21], ["white_oak_A", 74, 23],
				["loblolly_pine_A", 88, 25],
				["white_oak_A", 10, 25], ["loblolly_pine_A", 24, 26],
				["red_maple_A", 38, 28], ["loblolly_pine_A", 51, 39],
			]:
				var p := _v(route[0]) + opening_dir * float(tree[1]) + opening_right * (float(side) * float(tree[2]))
				hole.planted_trees.append([tree[0], frame.to_world(p)])
			for tree in [["white_oak_A", 48, 28], ["red_maple_A", 65, 29], ["loblolly_pine_A", 83, 28], ["white_oak_A", 101, 28], ["red_maple_A", 119, 29], ["loblolly_pine_A", 138, 29], ["loblolly_pine_A", 57, 39], ["white_oak_A", 86, 40], ["red_maple_A", 114, 39], ["loblolly_pine_A", 143, 41]]:
				var p := opening_dir * float(tree[1]) + opening_right * (float(side) * float(tree[2]))
				hole.planted_trees.append([tree[0], frame.to_world(p)])
		# Stagger two denser rows behind the established edge. Keep every new
		# trunk outside that edge, so density increases without narrowing the lane.
		for side in [-1.0, 1.0]:
			for row in range(2):
				for step in range(13):
					var along := 2.0 + step * 12.0 + row * 5.0
					var across := 25.0 + along * 0.09 + row * 10.0
					var p := frame.to_world(_v(route[0]) + opening_dir * along + opening_right * (side * across))
					var clear := true
					for existing in hole.planted_trees:
						if p.distance_to(existing[1]) < 7.0:
							clear = false
							break
					if clear:
						var species: String = ["loblolly_pine_A", "white_oak_A", "red_maple_A"][(step + row) % 3]
						hole.planted_trees.append([species, p])
		# Continuous understory behind the tee-shot corridor, including the area
		# excluded by the general forest's broad tee clearance.
		for side in [-1.0, 1.0]:
			for row in range(3):
				for step in range(43):
					var along := step * 3.6 + row * 1.2
					var across := 18.0 + along * 0.085 + row * 5.0
					hole.planted_bushes.append(frame.to_world(_v(route[0]) + opening_dir * along + opening_right * (side * across)))
	if i == 13:
		# Yellow mark: a smooth rough cutout with no automatic island vegetation.
		hole.rough_islands.append([frame.to_world(Vector2(181.0, 66.0)), frame.to_world(Vector2(211.0, 74.0)), 15.0, false])
		# Fill out the marked group on the opening's right-hand side.
		hole.planted_trees.append(["white_oak_A", frame.to_world(Vector2(61.0, 43.0))])
		hole.planted_trees.append(["red_maple_A", frame.to_world(Vector2(66.0, 49.0))])
		hole.planted_trees.append(["river_birch_A", frame.to_world(Vector2(56.0, 51.0))])
		for tree in [
			["red_maple_A", 53, 43], ["eastern_red_cedar_A", 61, 56],
			["white_oak_A", 71, 42], ["river_birch_A", 74, 51],
			["red_maple_A", 69, 59], ["eastern_red_cedar_A", 53, 59],
			["white_oak_A", 78, 59],
		]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 14:
		# The marked right-side tee corridor catches slices, following the
		# widening fairway edge into the existing woods.
		var opening_dir := (_v(route[1]) - _v(route[0])).normalized()
		var opening_right := Vector2(-opening_dir.y, opening_dir.x)
		var species := ["loblolly_pine_A", "white_oak_A", "red_maple_A"]
		# Close the right-side gap beside the tee and double the along-row density.
		var stations := [Vector2(-12,8), Vector2(0,8), Vector2(12,9),
			Vector2(24,11), Vector2(36,14), Vector2(48,17), Vector2(60,20),
			Vector2(72,23), Vector2(84,25), Vector2(96,28), Vector2(108,36),
			Vector2(120,53), Vector2(128,62)]
		for row in range(3):
			for step in range(stations.size() * 2 - 1):
				var index := step / 2
				var station: Vector2 = stations[index]
				if step % 2 == 1:
					station = station.lerp(stations[index + 1],0.5)
				station += Vector2(row * 2.0,row * 6.0)
				var p := _v(route[0]) + opening_dir * station.x + opening_right * station.y
				var tree_species: String = species[(step + row) % species.size()]
				if row == 0 and station.x < 55.0:
					tree_species = "loblolly_pine_A" if step % 2 == 0 else "longleaf_pine_A"
				hole.planted_trees.append([tree_species,frame.to_world(p)])
		# Continue the reference diagram's woodland around the back of the tee.
		# The inner arc leaves room behind the tee markers and joins the right belt.
		var rear_arc := [Vector2(-24,-15), Vector2(-27,-5), Vector2(-25,6),
			Vector2(-20,15), Vector2(-9,19), Vector2(1,22),
			Vector2(-34,-17), Vector2(-37,-5), Vector2(-34,8),
			Vector2(-29,20), Vector2(-18,28), Vector2(-5,31)]
		for step in range(rear_arc.size()):
			var station: Vector2 = rear_arc[step]
			var p := _v(route[0]) + opening_dir * station.x + opening_right * station.y
			hole.planted_trees.append([species[(step + 1) % species.size()], frame.to_world(p)])
	if i == 15:
		# Small circular tree island in the marked fairway beside the pond's near end.
		var island_center := frame.to_world(Vector2(32, 27))
		hole.rough_islands.append([island_center, island_center, 7.5, false, true])
		for tree in [["river_birch_A", 28, 24], ["eastern_red_cedar_A", 35, 24],
			["flowering_dogwood_white_A", 30, 30], ["river_birch_A", 36, 30]]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 16:
		# Yellow: a separate mown opening on the right.
		hole.fairway_patches.append([frame.to_world(Vector2(22, 54)), frame.to_world(Vector2(132, 54)), 24.0])
		hole.fairway_patches.append([frame.to_world(Vector2(132, 45)), frame.to_world(Vector2(182, 40)), 22.0])
		# The two tree islands in the right half of the fairway, placed from the Masters hole
		# map (hole-map-17.jpg at 0.116 m/px from the back tee; its forward tee lands within
		# 1.5 m of ours): rough all round, a stand of trees inside, mown fairway either side.
		# The old island 97 m out -- straight in front of the tee, open fairway on the map --
		# is gone. Outer capsules are treeless rough; the inner ones are the tree stands.
		# Both are tree island: rough straight off the fairway, no first cut.
		for isl in [[140, 45, 184, 45, 14.0], [180, 44, 188, 44, 17.0], [234, 46, 340, 47, 17.0], [292, 52, 318, 52, 15.0]]:
			hole.rough_islands.append([frame.to_world(Vector2(isl[0], isl[1])), frame.to_world(Vector2(isl[2], isl[3])), float(isl[4]), false, true])
		for isl in [[147, 45, 181, 46, 9.0], [236, 44, 264, 47, 10.0], [289, 43, 338, 46, 11.0]]:
			hole.rough_islands.append([frame.to_world(Vector2(isl[0], isl[1])), frame.to_world(Vector2(isl[2], isl[3])), float(isl[4])])
		for tree in [
			# lower island (132-196 m) and the lone tree short of it
			["white_oak_A", 185, 34], ["loblolly_pine_A", 182, 43], ["red_maple_A", 179, 52],
			["sweetgum_A", 172, 37], ["white_oak_A", 168, 47], ["loblolly_pine_A", 167, 56],
			["red_maple_A", 163, 41], ["white_oak_A", 161, 52], ["loblolly_pine_A", 144, 43],
			["sweetgum_A", 142, 51], ["white_oak_A", 121, 50],
			# upper island (231-346 m): a stand at each end round a pine-straw bed
			["white_oak_A", 339, 37], ["loblolly_pine_A", 338, 47], ["red_maple_A", 324, 33],
			["white_oak_A", 322, 43], ["sweetgum_A", 317, 54], ["loblolly_pine_A", 304, 33],
			["white_oak_A", 304, 44], ["red_maple_A", 301, 55], ["loblolly_pine_A", 290, 37],
			["sweetgum_A", 288, 49], ["white_oak_A", 264, 37], ["loblolly_pine_A", 265, 49],
			["red_maple_A", 254, 56], ["white_oak_A", 251, 40], ["loblolly_pine_A", 247, 49],
			["sweetgum_A", 237, 33], ["white_oak_A", 235, 44], ["loblolly_pine_A", 226, 40],
		]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
		# The reference diagram's curved tree belt hugs the right of the back
		# tee and ends beside the forward tee, with an open lane straight ahead.
		var opening_dir := (_v(route[1]) - _v(route[0])).normalized()
		var opening_right := Vector2(-opening_dir.y, opening_dir.x)
		var belt := [Vector2(-10,13), Vector2(20,16), Vector2(44,25), Vector2(75,36)]
		for segment in range(1, belt.size()):
			var a: Vector2 = _v(route[0]) + opening_dir * belt[segment - 1].x + opening_right * belt[segment - 1].y
			var b: Vector2 = _v(route[0]) + opening_dir * belt[segment].x + opening_right * belt[segment].y
			hole.rough_islands.append([frame.to_world(a), frame.to_world(b), 8.0, false, true])
		var slice_species := ["loblolly_pine_A", "white_oak_A", "red_maple_A"]
		var stations := [Vector2(-10,7), Vector2(0,7.5), Vector2(10,8),
			Vector2(20,10), Vector2(30,13), Vector2(40,17),
			Vector2(50,21), Vector2(60,25), Vector2(68,28)]
		for row in range(3):
			for step in range(stations.size() * 2 - 1):
				var index := step / 2
				var station: Vector2 = stations[index]
				if step % 2 == 1:
					station = station.lerp(stations[index + 1],0.5)
				station += Vector2(row * 1.7,row * 6.0)
				var p := _v(route[0]) + opening_dir * station.x + opening_right * station.y
				var tree_species: String = slice_species[(step + row) % slice_species.size()]
				if row == 0 and station.x < 45.0:
					tree_species = "loblolly_pine_A" if step % 2 == 0 else "longleaf_pine_A"
				hole.planted_trees.append([tree_species,frame.to_world(p)])
		# Red: a loose line of trees to the left of the tee and opening carry.
		for tree in [["loblolly_pine_A", 26, -17], ["white_oak_A", 49, -20], ["red_maple_A", 76, -19], ["longleaf_pine_A", 102, -18], ["river_birch_A", 128, -20], ["white_oak_A", 149, -21]]:
			hole.planted_trees.append([tree[0], frame.to_world(Vector2(tree[1], tree[2]))])
	if i == 17:
		# Dense borders follow both sides of the real diagram's narrow chute.
		# The left belt starts past the tee; the right belt reaches beside it.
		var species := ["loblolly_pine_A", "white_oak_A", "sweetgum_A", "red_maple_A"]
		for side in [-1.0, 1.0]:
			for row in range(3):
				for station in range(50 if side < 0.0 else 6, 294, 11):
					var along := float(station) + row * 3.5
					var remaining := along
					var point := Vector2.ZERO
					var tangent := Vector2.RIGHT
					for segment in range(1, route.size()):
						var a := _v(route[segment - 1])
						var b := _v(route[segment])
						var length := a.distance_to(b)
						if remaining <= length:
							tangent = (b - a).normalized()
							point = a + tangent * remaining
							break
						remaining -= length
					var widths := _hole18_widths(along)
					var fairway_edge := widths.x if side < 0.0 else widths.y
					var chute_edge := lerpf(14.0,19.0,smoothstep(0.0,100.0,along))
					var across := maxf(chute_edge, fairway_edge + 7.0) + row * 9.0 + sin(along * 0.17 + row) * 1.2
					var p := frame.to_world(point + Vector2(-tangent.y,tangent.x) * side * across)
					var clear := true
					for bunker in hole.bunker_polys:
						if p.distance_to(Excavation.centroid(bunker[2])) < 20.0:
							clear = false
							break
					if clear:
						hole.planted_trees.append([species[(station + row) % species.size()],p])
		# Wrap the right-hand woodland behind the back tee, as in the reference.
		for tree in [["loblolly_pine_A",-20,-7], ["white_oak_A",-23,4],
			["loblolly_pine_A",-18,15], ["red_maple_A",-7,20],
			["white_oak_A",-27,17], ["loblolly_pine_A",-13,29]]:
			hole.planted_trees.append([tree[0],frame.to_world(Vector2(tree[1],tree[2]))])
		# A slightly larger island, aligned with the right-hand greenside bunker.
		var island_center := frame.to_world(Vector2(337,-1))
		hole.rough_islands.append([island_center,island_center,14.0,false,true])
		for tree in [["river_birch_A",331,-6], ["eastern_red_cedar_A",343,-6],
			["red_maple_A",338,6], ["river_birch_A",330,4],
			["flowering_dogwood_white_A",345,3], ["eastern_red_cedar_A",337,-1]]:
			hole.planted_trees.append([tree[0],frame.to_world(Vector2(tree[1],tree[2]))])
	for lf in spec["landforms"]:
		hole.landforms.append({"id": String(lf["id"]), "s0": float(lf["s_range_approx"][0]), "s1": float(lf["s_range_approx"][1])})
	return hole
