class_name FacilityBuilder
extends RefCounted
## The course-manager facilities (clubhouse, cart barn, driving range) in 3D. Shared by the
## golf game (roof on, no interiors, walls block the ball on PropScatter.OBSTACLE_LAYER), Course
## Studio's read-only preview and Course Manager (rooms furnished at their tiers, the cutaway
## views, staff spots). Each level is a Blender model -- tools/blender/build_facilities.py builds
## assets/facilities/<type>_l<level>.gltf -- whose named parts this fills in:
##   BASE / WALLS_HIGH / ROOF   the geometry groups; the cutaway hides ROOF, then WALLS_HIGH
##   ROOM_<id>_T<k>             a clubhouse room's furniture at tier k (only the built tier stays)
##   ROOMBOX_<id>               the room's floor rectangle (picking a room, walking about in it)
##   SIGN                       where the club's name goes;   COL_*  box colliders
##   markers                    CART (the club cart), BAG (one of the club's golf bags),
##                              HEDGE_A/B/C (hedge tiles), PLANT_<nature pack id> (the shrubs --
##                              boxwood, azalea, hydrangea -- are the woodland's big bushes), CLUB_<family>
##                              (a real club from the equipment catalog, grip down), CAP_<colour>
##                              (the club cap, tinted), RACK_A/B (the clothes racks), FOLD_A/B
##                              (piles of folded shirts), BALLPACK_<pack> (a box of golf balls),
##                              DUMBBELL_RACK (the gym's dumbbell rack),
##                              MANNEQUIN_M/F (the dressed mannequins), AUTO (a parking stall:
##                              park() fills a share of them with cars) and SPOT[_<role>] (where a
##                              member of staff stands; a role keeps it for that job)
## Next to each model, <type>_l<level>_paving.png says where its plot is built on (paving, floors,
## decks, beds); the rest of the plot is the course's own rough, grass and all (grade()); and
## <type>_l<level>_walk.png how high people stand on it (walk_height()).
## Props are batched into one MultiMesh per kind per facility. In Course Manager each room (and
## the cart barn's / range's yard) also gets a walkable grid traced from its furniture, so the
## staff walk round the tables and counters rather than through them (nav_route()).
##
## Local frame: the plot is centred on the facility's position; its front (entrance; the
## driving range's hitting direction) faces -Z and x runs across it; yaw `rot` turns that frame
## like any Node3D, so the front points along (-sin rot, -cos rot) in world XZ. The plot is the
## same at every level, so an upgrade never pushes it into its neighbour, and grade() levels the
## ground under it. Level 0 is a staked-out "planned" site.

const FOOTPRINT := {
	"clubhouse": Vector2(88, 84),  # (wide enough for L4's cart path past its spa wing)
	"cart_barn": Vector2(60, 48),
	"driving_range": Vector2(70, 26),
	"parking_lot": Vector2(66, 48),
	"short_game": Vector2(50, 36),
}
## What a facility claims on the course at each level, 1 to 4 (local XZ, the front -Z): what that
## level is built on -- its buildings, paving, beds and props, the short game area's painted turf
## -- and a metre round it (the barn: room in front for carts backing out of its row), within
## its plot. Facilities may stand this close; an upgrade needs its next level's site clear.
## (tests/facility_site_test.gd checks the models still fit.)
const SITES := {
	"clubhouse": [Rect2(-10.5, -42, 30.3, 84), Rect2(-37, -42, 76.2, 84), Rect2(-31.5, -42, 70.5, 84), Rect2(-41, -42, 84.4, 90)],  # (out to their cart paths round the side)
	"cart_barn": [Rect2(-7, -6, 17, 19.5), Rect2(-13.5, -6, 27.5, 22.5), Rect2(-15.5, -5.5, 39, 23), Rect2(-7.5, -1.5, 31.5, 24)],
	"driving_range": [Rect2(-30.5, -13.5, 57.5, 12.5), Rect2(-31.5, -13.5, 57.6, 26.5), Rect2(-35, -14, 60.5, 27), Rect2(-35, -15.5, 70, 28.5)],
	"parking_lot": [Rect2(-33, -24, 58, 34.5), Rect2(-33, -24, 57.5, 43), Rect2(-33, -24, 66, 44), Rect2(-34, -24, 68, 44)],
	"short_game": [Rect2(-13.5, -10, 24.5, 18), Rect2(-19.5, -11.5, 41.5, 24), Rect2(-22, -12.5, 47, 25.5), Rect2(-25, -12, 50, 28)],
}
## How far a facility sits down into its pad: the models' own ground is 0.03 m up and their
## paving 0.04 m thick above that, so their paving ends up a centimetre proud of the grass.
const GROUND_SINK := 0.06
const YARD := 0.9144
## Keep the terrain's 2 m mesh cells flat past the kerbs, including rotated plots.
const PAD_MARGIN := 3.0
const MODEL := "res://assets/facilities/%s_l%d.gltf"
const CART_SCENE := "res://assets/facilities/props/golf_cart.glb"
const HEDGE_SCENE := "res://assets/facilities/props/hedge_tiles.glb"
const BAG_SCENE := "res://assets/facilities/props/bags/golf_bag_%s.glb"
const CAP_SCENE := "res://assets/facilities/props/golf_cap.glb"
const RACK_SCENE := "res://assets/facilities/props/clothes_rack_%s.glb"
const MANNEQUIN_SCENE := "res://assets/facilities/props/store_mannequin_%s.glb"
const SHIRT_SCENE := "res://assets/facilities/props/hanging_%s.glb"
const SHOE_SCENE := "res://assets/facilities/props/shoe_%s.glb"
const FOLD_SCENE := "res://assets/facilities/props/folded_pile_%s.glb"
## The spa gym's dumbbell rack (tools/blender/import_dumbbells.py, from the user's model).
const DUMBBELL_SCENE := "res://assets/facilities/props/dumbbell_rack.glb"
## The office's and pro shop's iMac and the bar's till (tools/blender/import_office_props.py).
const IMAC_SCENE := "res://assets/facilities/props/imac.glb"
const POS_SCENE := "res://assets/facilities/props/pos_terminal.glb"
## The day spa's hot tub and massage tables (tools/blender/import_spa_props.py).
const JACUZZI_SCENE := "res://assets/facilities/props/jacuzzi.glb"
const FOUNTAIN_SCENE := "res://assets/facilities/props/fountain.glb"  # the Grand's forecourt fountain (tools/blender/import_fountain.py)
const STREET_LAMP_SCENE := "res://assets/facilities/props/street_lamp.glb"  # the user's lamp post (tools/blender/import_street_lamp.py; STREET_LAMP markers)
const FOUNTAIN_WATER := "res://shaders/fountain_water.gdshader"  # its running water (_fountain_water)
const CANNON_SCENE := "res://assets/facilities/props/cannon.glb"  # the user's, on the clubhouse lawn (tools/blender/import_cannon.py; CANNON markers)
const PALM_SCENE := "res://assets/facilities/props/palm_%s.glb"  # the user's palms (a, b, c) along the drives (tools/blender/import_palms.py; PALM_A/B/C markers)
## The lots' accessible spaces: the sign at the head, the symbol painted by the aisle (tools/blender/build_ada_sign.py)
const ADA_SIGN_SCENE := "res://assets/facilities/props/ada_sign.glb"
const ADA_PAINT_SCENE := "res://assets/facilities/props/ada_paint.glb"
## The bar TV's golf: the user's video (tools/blender/import_tv_video.py --out ... tv_golf.ogv:
## Theora, 480 x 270, no sound); without it, the user's GIF clip (tools/blender/import_tv_clip.py:
## its frame sheet and how it's laid out), played on the screen by shaders/tv_screen.gdshader.
const TV_GOLF := "res://assets/facilities/props/tv_golf.ogv"
const TV_CLIP := {"frames": "res://assets/facilities/props/tv_clip.jpg", "count": 152, "cols": 12, "rows": 13, "fps": 100.0 / 7.0}
## The other bar TV's video (the user's, tools/blender/import_tv_video.py: Theora, 480 x 270, no sound).
const TV_VIDEO := "res://assets/facilities/props/tv_video.ogv"
const TV_SHADER := "res://shaders/tv_screen.gdshader"  # (both TVs' pictures)
const MASSAGE_SCENE := "res://assets/facilities/props/massage_table.glb"
## The short game area's cups take the course's own flagstick, cloth and all, cut down to a
## practice pin (PRACTICE_FLAG_SCALE of it: a shorter pole, a smaller flag) in practice-green
## colours; always the real cloth, however far the camera -- switching to the waving stand-in and
## back as the manager's camera came and went, they snapped from one to the other and started
## flat again (user) -- a short game area's few small pins are cheap enough.
const FLAGSTICK_SCENE := "res://assets/world_flagstick/world_flagstick.tscn"
const PRACTICE_FLAGS := [Color("f2c230"), Color("d23b2f"), Color("f4f4ef"), Color("2f5fb3")]
const PRACTICE_FLAG_SIM := 1.0e6
const PRACTICE_FLAG_SCALE := 0.28
## The short game area's turf, by level, in its plot's frame (x across, z back; metres): greens
## (the putting green first; "chip" marks the chipping green the mats aim at) and bunkers, each
## an ellipse ("c" centre, "r" half sizes, "rot") that grade() paints onto the course with the
## course's own brushes -- a green as overlapping dabs inside a fairway collar, so it comes out
## an organic shape rather than a disc; a bunker as a curved run of dabs, dug like the course's
## -- and the cups, as fractions of their green's half sizes.
const PRACTICE_TURF := {
	1: {"greens": [{"c": Vector2(0.0, -0.5), "r": Vector2(9.5, 6.5), "rot": 0.0, "seed": 1,
			"cups": [Vector2(-0.55, -0.3), Vector2(-0.2, 0.45), Vector2(0.25, -0.5), Vector2(0.58, 0.1), Vector2(0.05, 0.0)]}],
		"bunkers": []},
	2: {"greens": [{"c": Vector2(-9.0, -2.0), "r": Vector2(10.0, 7.0), "rot": 0.08, "seed": 2,
			"cups": [Vector2(-0.55, -0.25), Vector2(-0.25, 0.5), Vector2(0.15, -0.5), Vector2(0.55, 0.1), Vector2(0.0, 0.0), Vector2(-0.45, 0.12)]},
		{"c": Vector2(13.0, 5.5), "r": Vector2(6.5, 5.0), "rot": -0.15, "seed": 5, "chip": true,
			"cups": [Vector2(-0.4, -0.15), Vector2(0.25, 0.3), Vector2(0.45, -0.35)]}],
		"bunkers": [{"c": Vector2(13.0, -3.0), "r": Vector2(3.6, 1.6), "rot": 0.0, "seed": 3}]},
	3: {"greens": [{"c": Vector2(-9.5, -1.5), "r": Vector2(11.5, 8.0), "rot": -0.06, "seed": 3,
			"cups": [Vector2(-0.58, -0.28), Vector2(-0.3, 0.52), Vector2(0.07, -0.55), Vector2(0.47, 0.18), Vector2(0.55, -0.28),
				Vector2(-0.05, 0.05), Vector2(-0.55, 0.3), Vector2(0.3, -0.12)]},
		{"c": Vector2(14.0, 5.5), "r": Vector2(7.5, 5.5), "rot": -0.12, "seed": 7, "chip": true,
			"cups": [Vector2(-0.43, -0.18), Vector2(0.05, 0.36), Vector2(0.43, -0.29), Vector2(-0.08, -0.44)]}],
		"bunkers": [{"c": Vector2(14.0, -3.6), "r": Vector2(4.0, 1.7), "rot": 0.05, "seed": 4},
			{"c": Vector2(22.6, 6.0), "r": Vector2(3.4, 1.6), "rot": PI * 0.5, "seed": 6}]},
	4: {"greens": [{"c": Vector2(-10.0, -1.0), "r": Vector2(12.5, 9.0), "rot": 0.05, "seed": 4,
			"cups": [Vector2(-0.55, -0.28), Vector2(-0.32, 0.5), Vector2(-0.05, -0.55), Vector2(0.32, 0.29), Vector2(0.58, -0.2),
				Vector2(-0.1, 0.07), Vector2(-0.5, 0.32), Vector2(0.3, -0.3), Vector2(0.56, 0.22)]},
		{"c": Vector2(14.5, 5.0), "r": Vector2(8.0, 6.0), "rot": -0.1, "seed": 9, "chip": true,
			"cups": [Vector2(-0.45, -0.2), Vector2(0.0, 0.43), Vector2(0.45, -0.27), Vector2(-0.1, -0.47), Vector2(0.5, 0.25)]}],
		"bunkers": [{"c": Vector2(14.5, -4.4), "r": Vector2(4.6, 1.8), "rot": 0.0, "seed": 5},
			{"c": Vector2(23.0, 5.0), "r": Vector2(3.8, 1.5), "rot": PI * 0.5, "seed": 8},
			{"c": Vector2(4.6, 12.6), "r": Vector2(2.6, 1.5), "rot": 0.4, "seed": 2}]},
}
## A green's fairway collar is this much wider than the green.
const PRACTICE_COLLAR := 1.4
## The gym's machines (tools/blender/import_gym.py; GYM_<id> markers), and how wide a berth
## people give each (m).
const GYM_SCENE := "res://assets/facilities/props/gym/gym_%s.glb"
const BENCH_RACKS := ["bench_flat", "bench_incline"]  # the bench-press racks, a barbell on each
const TOILET_SCENE := "res://assets/facilities/props/toilet.glb"  # the user's (tools/blender/import_toilet.py; TOILET markers)
const GYM_BLOCK := {"treadmill": 1.0, "elliptical": 0.95, "spin_bike": 0.65, "cable_station": 0.8, "plate_tree": 0.4,
	"preacher_curl": 0.7, "bench_flat": 1.1, "bench_incline": 1.1, "bench_adjustable": 1.1, "gym_ball": 0.35,
	"kettlebell": 0.15, "mat": 0.0}
## The pro shop's golf ball packs (tools/blender/build_ball_packs.py): sleeves and dozen boxes.
const BALLPACK_SCENE := "res://assets/facilities/props/ball_packs/ball_%s.glb"
## The parked cars (tools/blender/import_cars.py, from the user's car pack).
const CAR_SCENE := "res://assets/facilities/props/cars/lite/car_%s.glb"
const CARS := ["sedan", "suv", "hatchback", "wagon", "minivan", "pickup", "compact", "coupe", "offroad", "sport"]
## The paints the cars come in (sRGB): white, black, silver and grey most (as on any road), then
## the colours; "" keeps the model's own. Every car model in every one (shaders/car_paint.gdshader).
const CAR_PAINTS := ["f2f2ef", "f2f2ef", "f2f2ef", "111214", "111214", "111214", "b9bcc0", "b9bcc0", "6b7076", "4a4e54",
		"", "", "a3171c", "5a1a20", "1b2a4a", "2a5aa8", "1f4d33", "c8b68e", "d8c9a8", "e6c21a", "d0641c", "1d6f74", "7a8a5a"]
const CAR_PAINT_SHADER := "res://shaders/car_paint.gdshader"
static var _car_meshes := {}
## How many of a lot's stalls park() always leaves free, for golfers arriving by car in Course
## Manager (ClubLife: a car a group, up to its MAX_GROUPS) -- wherever they choose to park.
const VISITOR_ROOM := 8
## A lot's stalls (tools/blender/build_facilities.py): how deep, and the aisle they open onto.
const STALL_D := 5.4
const LOT_AISLE := 6.6
## fm_lib.CAP_COLS: navy, white, red, green, black, tan, sky (brightened: the cap's own fabric
## texture is mid grey)
const CAP_COLOURS := [Color("3a4a78"), Color("ffffff"), Color("d4404a"), Color("47a05b"), Color("2c2f33"), Color("f0d4a0"), Color("a8e0ff")]
## Walkable grids: cell size (m) indoors and in the yards, and the band of heights (above the
## floor) whose geometry blocks a person.
const NAV_CELL := 0.25
const NAV_YARD_CELL := 0.5
const NAV_LOW := 0.15
const NAV_HIGH := 1.9
## The club's golf bags; a BAG marker picks one by where it stands.
const BAGS := ["cart_navy", "tour_green", "cart_charcoal", "tour_navy", "cart_red", "tour_white", "cart_white", "tour_black"]
const RANGE_BAGS := ["range_stand_grey", "range_stand_olive", "range_stand_sky"]
## The golfers' own bags, full of clubs (carried, or strapped on a cart).
const PLAYER_BAGS := ["carry_navy", "carry_green", "carry_red", "carry_black"]
## In the golf game the plantings, hedges, carts and bags stop drawing past this (m).
const PROP_RANGE_GOLF := 140.0
## Where a level's plot is built on (tools/blender/build_facilities.py paving_mask()): 255 on
## paving, floors, decks and beds, over the footprint, row 0 along the front.
const PAVING := "res://assets/facilities/%s_l%d_paving.png"
## How high people stand across a level's plot (build_facilities.py walk_map(); L8 on the paving
## mask's grid): 0 = the course's own ground, else the floor, deck, step or paving WALK_STEP m a
## level above the facility's origin.
const WALK := "res://assets/facilities/%s_l%d_walk.png"
const WALK_STEP := 0.02
## Shrub markers are planted with the woodland's big bushes (ForestPlanter.FOREST_BUSHES): a
## marker at scale 1 is SHRUB_WIDTH across, and none is narrower than SHRUB_MIN.
const SHRUBS := ["boxwood", "azalea", "hydrangea"]
const SHRUB_WIDTH := 2.6
const SHRUB_MIN := 1.3
## The cutaway: the whole building, the roof lifted off, the walls dropped to waist height.
enum View { EXTERIOR, ROOF_OFF, WALLS_DOWN }

const WOOD := Color("9a7350")
const WHITE := Color("f4f4ef")
const DARK := Color("1f2622")
const RED := Color("c9483c")
const GOLD := Color("f2d27c")
const TARGET_GREEN := Color("72c25c")
const TAPE := Color("ff8a2a")
const SIGN_INK := Color("1f3a2a")

static var _mats := {}
static var _scenes := {}  # path -> PackedScene
static var _script_face: Font = null  # the club sign's lettering (_script_font)
static var _titling_face: Font = null  # ... and its "Country Club" line (_titling_font)
static var _meshes := {}  # key -> Mesh (props, hedge tiles)
static var _club_parts := {}  # catalog asset id -> [[Mesh, Transform3D], ...] standing grip down
static var _club_ids := {}  # family -> playable catalog ids
static var _paving := {}  # path -> Image (null when missing)
static var _fields := {}  # "type:level" -> its built-on field (_built_field)
## How far round a plot its built-on field reaches (m): past the widest ease round it.
const FIELD_REACH := 34.0
static var _walk := {}  # path -> Image (null when missing)
static var _prebuilt := {}  # build() item key -> its facility, built ahead (prebuild)
static var _bushes := {}  # FOREST_BUSHES index -> [Mesh, Transform3D to 1 m across, base at 0]


static func footprint(type: String, level: int = 0) -> Vector2:
	if type == "clubhouse" and level == 4:
		return Vector2(88, 96)
	return FOOTPRINT.get(type, Vector2(12, 10))


## `type`'s site at `level` (SITES; a planned one stakes out its first level's), in its local XZ;
## the whole plot when `level` is -1 (not known).
static func site(type: String, level: int = -1) -> Rect2:
	var sites: Array = SITES.get(type, [])
	if level < 0 or sites.is_empty():
		var fp := footprint(type)
		return Rect2(-fp * 0.5, fp)
	return sites[clampi(level, 1, sites.size()) - 1]


## World XZ of local (x, z) for a facility at `pos` turned by `rot`.
static func to_world(pos: Vector2, rot: float, x: float, z: float) -> Vector2:
	var c := cos(rot)
	var s := sin(rot)
	return pos + Vector2(x * c + z * s, -x * s + z * c)


## World XZ points on a `step`-metre grid over the site at `level` (the plot at -1), edges included.
static func samples(type: String, pos: Vector2, rot: float, step: float = 2.0, level: int = -1) -> PackedVector2Array:
	var r := site(type, level)
	var out := PackedVector2Array()
	var nx := maxi(int(ceil(r.size.x / step)), 1)
	var nz := maxi(int(ceil(r.size.y / step)), 1)
	for i in range(nx + 1):
		for k in range(nz + 1):
			out.append(to_world(pos, rot, r.position.x + r.size.x * i / nx, r.position.y + r.size.y * k / nz))
	return out


## Whether world point `p` is inside the site at `level` (the plot at -1) grown by `grow` metres.
static func contains(type: String, pos: Vector2, rot: float, p: Vector2, grow: float = 0.0, level: int = -1) -> bool:
	var d := p - pos
	var c := cos(rot)
	var s := sin(rot)
	var l := Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	var r := site(type, level).grow(grow)
	return l.x >= r.position.x and l.x <= r.end.x and l.y >= r.position.y and l.y <= r.end.y


## Facing the world point `target` (the front toward it).
static func facing(pos: Vector2, target: Vector2) -> float:
	var d := target - pos
	return atan2(-d.x, -d.y) if d.length_squared() > 0.01 else 0.0


## Why `type` (its site at `level`; -1: the whole plot) can't stand on `course` at `pos` turned
## by `rot` ("" if it can): it needs open rough on the canvas -- no turf, sand, water or woods
## under it -- clear of the club's other facilities (`placements`: type -> {"pos", "rot", and
## their "level" if it's known}) and of every tee and pin.
static func site_problem(course: PaintedCourse, placements: Dictionary, type: String, pos: Vector2, rot: float, level: int = -1) -> String:
	for q in samples(type, pos, rot, 4.0, level):
		if not course.in_canvas(q):
			return "Too close to the edge of the map"
		var s := course.surface_at(q, false)  # the course as painted: the club's own practice turf moves with it
		if s == PaintedCourse.Surface.ROUGH and course.coverage(PaintedCourse.Surface.WOODS, q) > 0.5:
			return "Woods in the way: clear them in Course Studio, or pick open rough"
		if s != PaintedCourse.Surface.ROUGH:
			return "Needs open rough: it can't sit on the %s" % PaintedCourse.SURFACE_NAMES[s].to_lower()
		for other in placements:
			var o: Dictionary = placements[other]
			if other != type and contains(other, o["pos"], float(o["rot"]), q, 1.5, int(o.get("level", -1))):
				return "Overlaps the %s" % str(EconomyConfig.facility(other).get("name", other)).to_lower()
	# (and the other way round: a small neighbour can slip between a big site's samples)
	for other in placements:
		var o: Dictionary = placements[other]
		if other == type:
			continue
		for q in samples(other, o["pos"], float(o["rot"]), 4.0, int(o.get("level", -1))):
			if contains(type, pos, rot, q, 1.5, level):
				return "Overlaps the %s" % str(EconomyConfig.facility(other).get("name", other)).to_lower()
	for h in course.holes:
		for k in ["tee", "pin"]:
			if contains(type, pos, rot, h[k], 4.0, level):
				return "Too close to a tee or pin"
	return ""


## A driving range needs a clear field in front: a warning (it doesn't block placing) when it
## would hit off the map, across the course or over another facility; "" when it's clear.
static func range_warning(course: PaintedCourse, placements: Dictionary, pos: Vector2, rot: float) -> String:
	var front := footprint("driving_range").y * 0.5
	var length := 250.0 * YARD
	for k in range(1, 13):
		var z := -front - length * k / 12.0
		for x in [-16.0, 0.0, 16.0]:
			var q := to_world(pos, rot, x, z)
			if not course.in_canvas(q):
				return "The range's field runs off the map: R turns it"
			if course.surface_at(q) in [PaintedCourse.Surface.FAIRWAY, PaintedCourse.Surface.GREEN, PaintedCourse.Surface.TEE]:
				return "The range hits across your course: R turns it"
			for other in placements:
				var o: Dictionary = placements[other]
				if other != "driving_range" and contains(other, o["pos"], float(o["rot"]), q, 2.0):
					return "The range hits over the %s: R turns it" % str(EconomyConfig.facility(other).get("name", other)).to_lower()
	return ""


## A new facility faces the course's nearest tee (the clubhouse greets the first hole); the
## driving range hits away from it.
static func default_facing(course: PaintedCourse, type: String, p: Vector2) -> float:
	var best := INF
	var target := p + Vector2(0, -1)
	for h in course.holes:
		var d := p.distance_to(h["tee"])
		if d < best:
			best = d
			target = h["tee"]
	var rot := facing(p, target)
	return wrapf(rot + PI, -PI, PI) if type == "driving_range" else rot


## Level the ground under every placed facility: each plot becomes a flat pad at the average
## height of the ground it covers (cut and fill), eased back into the course round its edge
## (PaintedCourse.pads). `levels` (type -> built level) brings each level's paving mask, so the
## course's rough grows on the rest of the plot (PaintedCourse.on_paving). Call before the
## course's terrain, layout or view is built from it.
static func grade(course: PaintedCourse, placements: Dictionary, levels: Dictionary = {}) -> void:
	var pads: Array = []
	for type in placements:
		var pl: Dictionary = placements[type]
		var lv := int(levels.get(type, 0))
		var built_mask := paving(type, lv)
		if built_mask != null:
			pads.append(_built_pad(course, type, lv, built_mask, pl["pos"], float(pl["rot"])))
			continue
		# planned: its first level's site is levelled (a neighbour may stand close by: only what's
		# staked out, not the whole plot)
		var sum := 0.0
		var n := 0
		for q in samples(type, pl["pos"], float(pl["rot"]), 4.0, 1):
			sum += course.raw_height_at(q)
			n += 1
		var h := sum / maxi(n, 1)
		# the further the flat pad is from the ground round it (above it or below), the more
		# gently that ground eases up or down to it: a gentle rise, not a plinth or a pit
		var off := 0.0
		for q in samples(type, pl["pos"], float(pl["rot"]), 12.0, 1):
			off = maxf(off, absf(course.raw_height_at(q) - h))
		var staked := site(type, 1)
		var middle := to_world(pl["pos"], float(pl["rot"]), staked.get_center().x, staked.get_center().y)
		var pad := {"pos": middle, "rot": float(pl["rot"]), "half": staked.size * 0.5 + Vector2.ONE * PAD_MARGIN, "h": h,
			"foot": staked.size * 0.5, "blend": clampf(off * 22.0, PaintedCourse.PAD_BLEND, 32.0)}
		var mask := paving(type, int(levels.get(type, 0)))
		if mask != null:
			pad["mask"] = mask
		pads.append(pad)
	course.pads = pads
	_practice_turf(course, placements, levels)


## How far `type` sits down into its pad (every facility alike, for now: GROUND_SINK).
static func ground_sink(_type: String) -> float:
	return GROUND_SINK


## Whether world point `p` is on (or within `grow` m of) what facility `type` at level `lv`,
## placed at `pos` turned by `rot`, is built on -- its paving, floors, decks and beds; the whole
## plot while it's only planned (no model to say).
static func built_near(type: String, lv: int, pos: Vector2, rot: float, p: Vector2, grow: float) -> bool:
	var mask := paving(type, lv)
	if mask == null:
		return contains(type, pos, rot, p, grow)
	return PaintedCourse.pad_reach({"pos": pos, "rot": rot, "field": _built_field(type, lv, mask)}, p) <= grow


## A built facility's pad: only what it's built on is levelled (paving, floors, decks, beds --
## its mask -- and a metre round), at the course's average height there; the open ground of the
## plot stays the course's own, easing to the levelled ground over a distance that grows with
## how far that's above or below it (a gentle rise, not a plinth or a pit).
static func _built_pad(course: PaintedCourse, type: String, lv: int, mask: Image, pos: Vector2, rot: float) -> Dictionary:
	var field := _built_field(type, lv, mask)
	var built: PackedVector2Array = field["built"]
	var c := cos(rot)
	var s := sin(rot)
	var heights := PackedFloat32Array()
	var sum := 0.0
	for k in range(0, built.size(), 2):  # every other cell is plenty
		var q := built[k]
		var hh := course.raw_height_at(pos + Vector2(q.x * c + q.y * s, -q.x * s + q.y * c))
		heights.append(hh)
		sum += hh
	var h := sum / heights.size() if not heights.is_empty() else course.raw_height_at(pos)
	var off := 0.0
	for hh in heights:
		off = maxf(off, absf(hh - h))
	return {"pos": pos, "rot": rot, "half": footprint(type, lv) * 0.5 + Vector2.ONE * PAD_MARGIN, "foot": footprint(type, lv) * 0.5,
		"h": h, "blend": clampf(off * 22.0, 6.0, 32.0), "mask": mask, "field": field}


## Where a facility at level `lv` is built on, as distances: a 1 m grid in the plot's own frame
## over the plot and FIELD_REACH round it, each cell how far it is (m) from the nearest built-on
## cell (the mask's paving, floors, decks, beds); with those cells' centres and the one nearest
## their middle (where to read the levelled ground's height). Worked out once per facility and
## level: it doesn't depend on where the plot is.
static func _built_field(type: String, lv: int, mask: Image) -> Dictionary:
	var key := "%s:%d" % [type, lv]
	if _fields.has(key):
		return _fields[key]
	var foot := footprint(type, lv) * 0.5
	var origin := -foot - Vector2.ONE * FIELD_REACH
	var n := Vector2i(int(ceil((foot.x + FIELD_REACH) * 2.0)) + 1, int(ceil((foot.y + FIELD_REACH) * 2.0)) + 1)
	var dist := PackedFloat32Array()
	dist.resize(n.x * n.y)
	dist.fill(1.0e6)
	var built := PackedVector2Array()
	var middle := Vector2.ZERO
	for j in range(n.y):
		for i in range(n.x):
			var q := origin + Vector2(i, j)
			if absf(q.x) > foot.x or absf(q.y) > foot.y:
				continue
			for o: Vector2 in [Vector2.ZERO, Vector2(0.35, 0.35), Vector2(-0.35, 0.35), Vector2(0.35, -0.35), Vector2(-0.35, -0.35)]:
				if PaintedCourse._paved(mask, foot, q + o):
					dist[j * n.x + i] = 0.0
					built.append(q)
					middle += q
					break
	# two sweeps of a chamfer distance: a cell along 1 m, across 1.414 m
	const DIAG := 1.4142
	for j in range(n.y):
		for i in range(n.x):
			var k := j * n.x + i
			var d := dist[k]
			if i > 0:
				d = minf(d, dist[k - 1] + 1.0)
			if j > 0:
				d = minf(d, dist[k - n.x] + 1.0)
				if i > 0:
					d = minf(d, dist[k - n.x - 1] + DIAG)
				if i < n.x - 1:
					d = minf(d, dist[k - n.x + 1] + DIAG)
			dist[k] = d
	for j in range(n.y - 1, -1, -1):
		for i in range(n.x - 1, -1, -1):
			var k := j * n.x + i
			var d := dist[k]
			if i < n.x - 1:
				d = minf(d, dist[k + 1] + 1.0)
			if j < n.y - 1:
				d = minf(d, dist[k + n.x] + 1.0)
				if i < n.x - 1:
					d = minf(d, dist[k + n.x + 1] + DIAG)
				if i > 0:
					d = minf(d, dist[k + n.x - 1] + DIAG)
			dist[k] = d
	var anchor := Vector2.INF
	if not built.is_empty():
		middle /= built.size()
		for q in built:
			if anchor == Vector2.INF or q.distance_squared_to(middle) < anchor.distance_squared_to(middle):
				anchor = q
	var f := {"dist": dist, "origin": origin, "n": n, "built": built, "anchor": anchor}
	_fields[key] = f
	return f


## Paint the built short game area's greens, collars and bunkers onto the course's practice
## turf (PaintedCourse.turf_a: never saved) with the course's own brushes -- collars first, the
## greens over them, then the bunkers -- so they look, play and dig like the course's own.
static func _practice_turf(course: PaintedCourse, placements: Dictionary, levels: Dictionary) -> void:
	course.clear_turf()
	if not placements.has("short_game"):
		return
	var plan: Dictionary = PRACTICE_TURF.get(int(levels.get("short_game", 0)), {})
	if plan.is_empty():
		return
	var pl: Dictionary = placements["short_game"]
	var at := func(p: Vector2) -> Vector2: return to_world(pl["pos"], float(pl["rot"]), p.x, p.y)
	for g: Dictionary in plan["greens"]:
		for d in _green_dabs(g):
			course.paint_turf(PaintedCourse.Surface.FAIRWAY, at.call(d[0]), float(d[1]) + PRACTICE_COLLAR, 0.6)
	for g: Dictionary in plan["greens"]:
		for d in _green_dabs(g):
			course.paint_turf(PaintedCourse.Surface.GREEN, at.call(d[0]), float(d[1]), 0.7)
	for b: Dictionary in plan["bunkers"]:
		for d in _bunker_dabs(b):
			course.paint_turf(PaintedCourse.Surface.BUNKER, at.call(d[0]), float(d[1]), 0.8)


## A green as brush dabs ([centre, radius] in the plot's frame): a big one in the middle and a
## ring of seven, each set in and sized by the ellipse's reach that way and nudged by the seed,
## so the edge wanders like a hand-painted green.
static func _green_dabs(g: Dictionary) -> Array:
	var c: Vector2 = g["c"]
	var r: Vector2 = g["r"]
	var rot := float(g.get("rot", 0.0))
	var seed := int(g.get("seed", 0))
	var dabs := [[c, minf(r.x, r.y) * 0.8]]
	for k in range(7):
		var a := TAU * k / 7.0 + 0.4 * sin(seed * 1.7 + k * 2.3)
		var edge := Vector2(cos(a) * r.x, sin(a) * r.y)
		var f := 0.5 + 0.1 * sin(seed * 3.1 + k * 1.3)
		dabs.append([c + (edge * f).rotated(rot), edge.length() * (0.5 + 0.08 * cos(seed * 2.9 + k * 0.7))])
	return dabs


## A bunker as a curved run of four dabs along its length: a kidney, not an oval.
static func _bunker_dabs(b: Dictionary) -> Array:
	var c: Vector2 = b["c"]
	var r: Vector2 = b["r"]
	var rot := float(b.get("rot", 0.0))
	var seed := int(b.get("seed", 0))
	var dabs := []
	for k in range(4):
		var t := -0.6 + k * 0.4
		var p := Vector2(t * r.x, (0.35 - 1.2 * t * t) * r.y * 0.6)
		dabs.append([c + p.rotated(rot), r.y * (0.95 + 0.15 * sin(seed * 2.1 + k * 1.9))])
	return dabs


## A level's paving mask (PAVING; L8), or null for a planned site or a missing file.
static func paving(type: String, lv: int) -> Image:
	var path := PAVING % [type, lv]
	if not _paving.has(path):
		var img: Image = null
		if lv > 0 and ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			img = tex.get_image() if tex != null else null
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_L8)
		_paving[path] = img
	return _paving[path]


## How high (above `fac`'s origin) people stand at facility-local XZ point `p` -- on a floor,
## deck, step, porch or paving -- or NAN where it's the course's own ground (or no walk map).
static func walk_height(fac: Node3D, p: Vector2) -> float:
	var r := rig(fac)
	return walk_floor(str(r.get("type", "")), int(r.get("level", 0)), p)


## walk_height for a `type` facility at level `lv` (its walk map, the top floor where there are two).
static func walk_floor(type: String, lv: int, p: Vector2) -> float:
	var path := WALK % [type, lv]
	if not _walk.has(path):
		var img: Image = null
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			img = tex.get_image() if tex != null else null
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_L8)
		_walk[path] = img
	var img: Image = _walk[path]
	if img == null:
		return NAN
	var fp := footprint(type, lv)
	var i := floori((p.x / fp.x + 0.5) * img.get_width())
	var j := floori((p.y / fp.y + 0.5) * img.get_height())
	if i < 0 or j < 0 or i >= img.get_width() or j >= img.get_height():
		return NAN
	var v := img.get_pixel(i, j).r8
	return v * WALK_STEP if v > 0 else NAN


## items: [{"type", "pos": Vector2, "rot": float, "level": int (0 = planned), "name": the club's
## name for the sign, "rooms": {room id: tier}}]. `height_at(Vector2) -> float` is the ground
## under a world XZ point (flat across a graded plot). `colliders`: walls block the ball (the
## golf game). `interiors`: furnish the clubhouse rooms at their built tiers and keep the room
## outlines, staff spots and club stands (Course Manager); without, the rooms are left out.
static func build(items: Array, height_at: Callable, colliders: bool, interiors: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Facilities"
	for it in items:
		var key := var_to_str([it, colliders, interiors])
		var made: Node3D = _prebuilt.get(key)
		_prebuilt.erase(key)
		root.add_child(made if made != null else _build_one(it, height_at, colliders, interiors))
	for n: Node in _prebuilt.values():  # built ahead for something that changed since
		n.free()
	_prebuilt.clear()
	return root


## Build one facility of a coming build() ahead of it (a loading screen spreading the work over
## frames): build() takes it as it is when its item is the same.
static func prebuild(it: Dictionary, height_at: Callable, colliders: bool, interiors: bool = false) -> void:
	var key := var_to_str([it, colliders, interiors])
	if not _prebuilt.has(key):
		_prebuilt[key] = _build_one(it, height_at, colliders, interiors)


## A facility's parts for Course Manager: {"type", "level", "groups": {BASE/WALLS_HIGH/ROOF: [nodes]},
## "rooms": {id: furniture node}, "boxes": {id: {"rect": Rect2 local XZ, "y"}}, "spots": {room id
## ("" outdoors): [Transform3D local]}, "sign", "clubs": club stands still to fill, "stalls":
## parking stalls [Transform3D local]}.
static func rig(fac: Node) -> Dictionary:
	return fac.get_meta("rig", {}) if fac != null else {}


static func _build_one(it: Dictionary, height_at: Callable, colliders: bool, interiors: bool) -> Node3D:
	var type := str(it["type"])
	var pos: Vector2 = it["pos"]
	var rot := float(it.get("rot", 0.0))
	var lv := int(it.get("level", 1))
	var node := Node3D.new()
	node.name = type
	# at its levelled ground's height (read where it's built on: the plot's middle may be its
	# own open ground), down into it so its paving lies just proud of the grass
	var ground := pos
	var built_mask := paving(type, lv)
	if built_mask != null:
		var anchor: Vector2 = _built_field(type, lv, built_mask)["anchor"]
		if anchor != Vector2.INF:
			ground = pos + Vector2(anchor.x * cos(rot) + anchor.y * sin(rot), -anchor.x * sin(rot) + anchor.y * cos(rot))
	var y := float(height_at.call(ground)) - ground_sink(type)
	node.position = Vector3(pos.x, y, pos.y)
	node.rotation.y = rot
	var ctx := {"node": node, "body": null, "pos": pos, "rot": rot, "floor": y, "height_at": height_at}
	var path := MODEL % [type, lv]
	if lv <= 0 or not ResourceLoader.exists(path):
		_planned(ctx, type)
		return node
	if colliders:
		var body := StaticBody3D.new()
		body.name = "Collider"
		body.collision_layer = PropScatter.OBSTACLE_LAYER
		body.collision_mask = 0
		node.add_child(body)
		ctx["body"] = body
	var model := _scene(path).instantiate() as Node3D
	model.name = "Model"
	node.add_child(model)
	_crisp(model)
	var r := {"type": type, "level": lv, "groups": {}, "rooms": {}, "boxes": {}, "spots": {}, "clubs": [], "sign": null, "club_root": null,
		"blockers": {}, "nav": {}, "stalls": []}
	var batches := {}
	var rooms: Dictionary = it.get("rooms", {})
	r["room_tiers"] = rooms.duplicate()
	var title := str(it.get("name", ""))
	for part in model.get_children():
		_take(part, ctx, r, batches, interiors, rooms, title)
	_emit_batches(node, batches, interiors)
	_flags(ctx, r, lv)
	if interiors:
		_build_nav(r)
	if type == "driving_range":
		_range_field(ctx, lv)
	_drape(ctx, r)
	_valet_station_details(ctx, r)
	_practice_signs(ctx, r, lv)
	node.set_meta("rig", r)
	return node


## What stands on a plot's open ground -- off what's built on, which was levelled -- down (or up)
## onto the course's own ground as it rises and falls there: the model's ground-level parts
## (fences, lamps, posts), its batched props (hedges, shrubs, trees), the flag and the club's
## sign. On the levelled ground that's no move at all, so the buildings and paving stay put.
static func _drape(ctx: Dictionary, r: Dictionary) -> void:
	var node: Node3D = ctx["node"]
	var height_at: Callable = ctx["height_at"]
	var half := footprint(str(r["type"])) * 0.5 + Vector2.ONE
	var n := Vector2i(int(ceil(half.x * 2.0)) + 1, int(ceil(half.y * 2.0)) + 1)
	var level := node.position.y + ground_sink(str(r["type"]))  # the levelled ground's height
	var lift := PackedFloat32Array()
	lift.resize(n.x * n.y)
	var most := 0.0
	for j in range(n.y):
		for i in range(n.x):
			var w := node.transform * Vector3(i - half.x, 0.0, j - half.y)
			var v := float(height_at.call(Vector2(w.x, w.z))) - level
			lift[j * n.x + i] = v
			most = maxf(most, absf(v))
	if most < 0.01:
		return  # level all over
	var lift_at := func(x: float, z: float) -> float:
		var gx := clampf(x + half.x, 0.0, n.x - 1.001)
		var gz := clampf(z + half.y, 0.0, n.y - 1.001)
		var i := int(gx)
		var j := int(gz)
		var k := j * n.x + i
		return lerpf(lerpf(lift[k], lift[k + 1], gx - i), lerpf(lift[k + n.x], lift[k + n.x + 1], gx - i), gz - j)
	# the model's ground-level parts, vertex by vertex (a fence bends over the ground it crosses)
	for part in r["groups"].get("BASE", []):
		var mi := part as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY  # the part in the facility's frame
		var up: Node = mi
		while up != null and up != node:
			xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var back := xf.affine_inverse()
		var draped := ArrayMesh.new()
		for si in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vi in range(verts.size()):
				var l := xf * verts[vi]
				var s: float = lift_at.call(l.x, l.z)
				if absf(s) > 0.002:
					verts[vi] = back * (l + Vector3(0.0, s, 0.0))
			arrays[Mesh.ARRAY_VERTEX] = verts
			draped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			draped.surface_set_material(si, mi.mesh.surface_get_material(si))
		mi.mesh = draped
	# batched props, each on the ground under it
	for c in node.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_"):
			var mmi := c as MultiMeshInstance3D
			var raise := mmi.transform.basis.inverse()
			for k in range(mmi.multimesh.instance_count):
				var t := mmi.multimesh.get_instance_transform(k)
				var l := mmi.transform * t.origin
				t.origin += raise * Vector3(0.0, lift_at.call(l.x, l.z), 0.0)
				mmi.multimesh.set_instance_transform(k, t)
		elif String(c.name).begins_with("AmericanFlag"):
			(c as Node3D).position.y += lift_at.call((c as Node3D).position.x, (c as Node3D).position.z)
	for sign: Node3D in r.get("signs", []):
		if not is_instance_valid(sign):
			continue
		var at := node.transform.affine_inverse() * sign.global_transform.origin if sign.is_inside_tree() else sign.position
		sign.position.y += lift_at.call(at.x, at.z)
	for spot: Dictionary in (r["spots"] as Dictionary).get("", []):
		var t: Transform3D = spot["xf"]
		t.origin.y += lift_at.call(t.origin.x, t.origin.z)
		spot["xf"] = t


## The course's flagstick in each of the facility's cups (its foot down the cup), the colours
## taking turns; the cloth stirs in a light breeze.
static func _flags(ctx: Dictionary, r: Dictionary, lv: int) -> void:
	for xf: Transform3D in r.get("american_flags", []):
		var flag := _scene(FLAGSTICK_SCENE).instantiate() as Node3D
		flag.name = "AmericanFlag"
		flag.set("size_scale", 4.0)
		flag.set("stiff_hoist_columns", 0)  # held at the pole by its very edge, a thread's width, not a stiff band
		flag.set("swivel_hoist", true)  # and free to go round the pole with the wind
		flag.set("wind_wander", 0.9)  # which comes round now and then
		flag.set("hoist_clearance", .045)
		flag.set("pole_radius_override", .09)
		flag.set("fabric_texture", load("res://assets/facilities/props/american_flag.svg"))
		flag.set("wind_force_scale", 4.0)  # flying out flat in the breeze
		# always the real cloth, however far the camera: its far stand-in (made for a pin's flag)
		# hangs differently, and coming back in the cloth starts flat again -- zooming the camera
		# out and in, the flag snapped from one to the other
		flag.set("simulation_distance", 1.0e6)
		# a stiff, heavy cloth: it holds its shape (few wrinkles) and settles fast rather than
		# rippling; strong gusts are still tamed (wind_tame_*), so it doesn't thrash
		flag.set("cloth_damping", 0.4)
		flag.set("cloth_precision", 36)
		flag.set("wind_velocity", Vector3(2.2, 0, .9))
		var height := xf.basis.get_scale().x
		flag.position = xf.origin + Vector3(0, height + .1 - 2.42 * 4.0, 0)
		(ctx["node"] as Node3D).add_child(flag)
		flag.get_node("Model").visible = false
	var plan: Dictionary = PRACTICE_TURF.get(lv, {}) if r["type"] == "short_game" else {}
	var scene := _scene(FLAGSTICK_SCENE)
	if plan.is_empty() or scene == null:
		return
	var node: Node3D = ctx["node"]
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.054
	cup_mesh.bottom_radius = 0.054
	cup_mesh.height = 0.012
	cup_mesh.radial_segments = 16
	cup_mesh.material = _mat(DARK)
	var flags: Array = r.get_or_add("flags", [])
	var practice: Array = r.get_or_add("practice", [])
	for g: Dictionary in plan["greens"]:
		var c: Vector2 = g["c"]
		var radii: Vector2 = g["r"]
		var rot := float(g.get("rot", 0.0))
		for uv: Vector2 in g["cups"]:
			var p := c + Vector2(uv.x * radii.x, uv.y * radii.y).rotated(rot)
			var y := _ground(ctx, p.x, p.y)
			var i := flags.size()
			flags.append(Transform3D(Basis(), Vector3(p.x, y, p.y)))
			var cup := MeshInstance3D.new()
			cup.mesh = cup_mesh
			cup.position = Vector3(p.x, y + 0.002, p.y)
			node.add_child(cup)
			var f := scene.instantiate() as Node3D
			f.name = "Flagstick%d" % i
			f.set("flag_color", PRACTICE_FLAGS[i % PRACTICE_FLAGS.size()])
			f.set("phase_offset", i * 1.37)
			f.set("simulation_distance", PRACTICE_FLAG_SIM)
			f.set("wind_velocity", Vector3(2.2, 0.0, 0.9))
			f.set("size_scale", PRACTICE_FLAG_SCALE)
			f.position = Vector3(p.x, y - 0.12 * PRACTICE_FLAG_SCALE, p.y)
			node.add_child(f)
			if not g.get("chip", false):
				# a putting spot a few metres off the cup, back toward the middle of the green
				var a := 0.6 * sin(i * 2.3)
				var toward := (c - p).normalized() if c.distance_to(p) > 1.0 else Vector2.RIGHT
				var spot := p + toward.rotated(a) * (2.4 + (i % 3) * 0.6)
				var sy := _ground(ctx, spot.x, spot.y)
				var from := Vector3(spot.x, sy, spot.y)
				var to := Vector3(p.x, y, p.y)
				practice.append({"xf": Transform3D(Basis.looking_at(to - from, Vector3.UP), from), "target": to, "kind": "putt"})
	# the mats aim at the middle of the chipping green
	for g: Dictionary in plan["greens"]:
		if g.get("chip", false):
			var c: Vector2 = g["c"]
			for s: Dictionary in practice:
				if s["kind"] == "chip":
					var from: Vector3 = (s["xf"] as Transform3D).origin
					var to := Vector3(c.x, _ground(ctx, c.x, c.y), c.y)
					s["xf"] = Transform3D(Basis.looking_at(Vector3(to.x - from.x, 0, to.z - from.z), Vector3.UP), from)
					s["target"] = to


## One top-level part of the model: keep, fill or drop it.
static func _take(part: Node, ctx: Dictionary, r: Dictionary, batches: Dictionary, interiors: bool, rooms: Dictionary, title: String) -> void:
	var xf := (part as Node3D).transform
	var kind := _kind(part.name)
	if kind in ["BASE", "WALLS_HIGH", "ROOF"]:
		((r["groups"] as Dictionary).get_or_add(kind, []) as Array).append(part)
		_markers(part, xf, r, batches, interiors, "")
	elif kind.begins_with("DOORLEAF_"):
		part.set_script(preload("res://scripts/manager/facility_door.gd"))
		part.call("configure")
		part.set_process(true)
		(r.get_or_add("door_leaves", []) as Array).append(part)
	elif kind.begins_with("ROOM_"):
		var k := kind.rfind("_T")
		var id := kind.substr(5, k - 5)
		if interiors and int(rooms.get(id, 0)) == int(kind.substr(k + 2)):
			r["rooms"][id] = part
			_markers(part, xf, r, batches, interiors, id)
		else:
			_drop(part)
	elif kind.begins_with("ROOMBOX_"):
		if interiors:
			var s := xf.basis.get_scale()
			r["boxes"][kind.substr(8)] = {"rect": Rect2(xf.origin.x - s.x * 0.5, xf.origin.z - s.z * 0.5, s.x, s.z), "y": xf.origin.y}
		_drop(part)
	elif kind == "SIGN":
		var panel := Vector2(xf.basis.get_scale().x, xf.basis.get_scale().y)
		var made: Node3D
		if panel.x > 1.5:  # the stone monument by the drive: the name fitted on its panel (each face's)
			made = _panel_sign(ctx, title if title != "" else "Clubhouse", Transform3D(xf.basis.orthonormalized(), xf.origin), panel)
			made.set_meta("standing", true)  # free-standing stone: never dropped with the walls (set_view)
		else:
			made = _sign(ctx, title.to_upper() if title != "" else "CLUBHOUSE", xf.origin + Vector3(0, 0, -0.06), 56, SIGN_INK)
		if r.get("sign") == null:
			r["sign"] = made
		(r.get_or_add("signs", []) as Array).append(made)
		_drop(part)
	elif kind.begins_with("COL_"):
		if ctx["body"] != null and part is MeshInstance3D and (part as MeshInstance3D).mesh != null:
			var aabb := (part as MeshInstance3D).mesh.get_aabb()
			var shape := BoxShape3D.new()
			shape.size = aabb.size * xf.basis.get_scale()
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = xf * aabb.get_center()
			(ctx["body"] as Node).add_child(cs)
		_drop(part)


## The markers under a group: batch the props, note the staff spots and club stands.
static func _markers(group: Node, group_xf: Transform3D, r: Dictionary, batches: Dictionary, interiors: bool, room: String) -> void:
	for m in group.get_children():
		if not (m is Node3D) or m is MeshInstance3D:
			continue
		var xf: Transform3D = group_xf * (m as Node3D).transform
		var kind := _kind(m.name)
		var block := 0.0  # how wide a berth people give it (m)
		if kind == "DOOR":
			(r.get_or_add("doors", []) as Array).append(xf)
		elif kind == "USFLAG":
			(r.get_or_add("american_flags", []) as Array).append(xf)
		elif kind == "TV_CLIP" or kind == "TV_VIDEO":
			# the clip (or the video) on the screen's face (the marker's scale: the screen's width),
			# facing out of it
			var w := xf.basis.get_scale().x
			var screen := MeshInstance3D.new()
			screen.name = "TvClip" if kind == "TV_CLIP" else "TvVideo"
			var quad := QuadMesh.new()
			quad.size = Vector2(w, w * 9.0 / 16.0)  # (L.tv's screen: 16:9, inside a thin bezel)
			screen.mesh = quad
			if kind == "TV_CLIP":
				screen.material_override = _tv_video(screen, TV_GOLF) if ResourceLoader.exists(TV_GOLF) else _tv_clip_material()
			else:
				screen.material_override = _tv_video(screen, TV_VIDEO)
			screen.transform = (m as Node3D).transform.orthonormalized() * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
			screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(screen)
		elif kind == "CART":
			if r["type"] == "cart_barn" and interiors:
				# one of the barn's own carts, parked: which of the batch's it is, for ClubLife to take
				# it out to wash (that one hidden) and put it back
				var batch: Dictionary = batches.get("cart", {"xf": []})
				(r.get_or_add("barn_carts", []) as Array).append({"xf": xf, "i": (batch["xf"] as Array).size()})
			_batch(batches, "cart", _first_mesh(CART_SCENE), xf)
			block = 1.3
		elif kind == "BAG":
			var pool: Array = RANGE_BAGS if r["type"] == "driving_range" else BAGS
			var v: String = pool[_pick(xf.origin, pool.size())]
			_batch(batches, "bag_" + v, _first_mesh(BAG_SCENE % v), xf)
			block = 0.3
			if room == "pro_shop" and interiors:
				for index in range(6):
					var offset := Transform3D(Basis(), Vector3(-.055 + (index % 3) * .055, .24 + (index % 2) * .035, -.035 + (index / 3) * .07))
					(r["clubs"] as Array).append({"family": "iron", "xf": xf * offset})
		elif kind.begins_with("HEDGE_"):
			_batch(batches, kind, _hedge_mesh(kind), xf)
			block = 0.7
		elif kind.begins_with("PLANT_") and _is_shrub(kind.substr(6)):
			var i := _pick(xf.origin, ForestPlanter.FOREST_BUSHES.size())
			var bush := _bush(i)
			var w := maxf(xf.basis.get_scale().x * SHRUB_WIDTH, SHRUB_MIN)
			var yaw := xf.basis.orthonormalized().get_euler().y
			_batch(batches, "bush_%d" % i, bush[0], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * w), xf.origin) * (bush[1] as Transform3D))
			block = w * 0.4
		elif kind.begins_with("PLANT_"):
			var id := kind.substr(6)
			_batch(batches, "plant_" + id, NaturePack.mesh_planting(id) if NaturePack.has(id) else null, xf)
			block = 0.3
		elif kind == "CAP":
			# "CAP_<colour>_<n>": the colour index is a number, so _kind() trims it with the rest
			var c := int(String(m.name).get_slice("_", 1))
			_batch(batches, "cap", _cap_mesh(), xf, CAP_COLOURS[posmod(c, CAP_COLOURS.size())])
		elif kind == "RESTAURANT_STOOL":
			# Source OBJ faces -Y in Blender; turn it to our +Y seating convention.
			_batch(batches, "restaurant_stools", _first_mesh("res://assets/facilities/props/kitchen_gear/stool.glb"), xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
		elif kind.begins_with("KITCHEN_"):
			var appliance := kind.substr(8).to_lower()
			var mesh := _first_mesh("res://assets/facilities/props/altesheim/%s.glb" % appliance)
			_batch(batches, "kitchen_" + appliance, mesh, xf)
			if mesh != null and appliance in ["range", "sink", "prep", "kettle", "storage", "potwash", "rack"]:
				# Floor-level equipment blocks walking; overhead fixtures do not.
				var box := mesh.get_aabb()
				var count := maxi(1, ceili(box.size.x / 0.5))
				for index in count:
					var local := Vector3(box.position.x + (index + 0.5) * box.size.x / count, 0, box.get_center().z)
					var at := xf * local
					((r["blockers"] as Dictionary).get_or_add(room, []) as Array).append(Vector3(at.x, at.z, box.size.z * 0.5))
		elif kind == "BAR_SHELF":
			var width := xf.basis.get_scale().x
			var placement := Transform3D(xf.basis.orthonormalized().scaled(Vector3(width, 1, 1)), xf.origin)
			_batch(batches, "bar_shelves", _first_mesh("res://assets/facilities/props/bar_bottles.glb"), placement)
		elif kind == "HANGING_GLASS":
			_batch(batches, "hanging_glasses", _first_mesh("res://assets/facilities/props/bar_wine_glass.glb"), xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO))
		elif kind.begins_with("COUNTER_BOTTLES_"):
			var category := kind.substr(16).to_lower()
			_batch(batches, "counter_bottles_" + category, _first_mesh("res://assets/facilities/props/bar_counter_" + category + ".glb"), xf)
		elif kind == "IMAC":
			_batch(batches, "imac", _first_mesh(IMAC_SCENE), xf)
		elif kind == "POS":
			_batch(batches, "pos", _first_mesh(POS_SCENE), xf)
		elif kind == "JACUZZI":
			_batch(batches, "jacuzzi", _first_mesh(JACUZZI_SCENE), xf)
			block = 1.5
		elif kind == "FOUNTAIN":
			_batch(batches, "fountain", _first_mesh(FOUNTAIN_SCENE), xf)
			_fountain_water(group, (group as Node3D).transform.affine_inverse() * xf)
			block = 3.4  # its basin's outer step is 3.1 m round
		elif kind == "CLOCK_FACE":
			# a dial of the lawn's street clock, facing out of it (-Z): ClubLife hangs its hands there
			(r.get_or_add("clock_faces", []) as Array).append(xf)
		elif kind == "STREET_LAMP":
			_batch(batches, "street_lamp", _first_mesh(STREET_LAMP_SCENE), xf)
			block = 0.3
		elif kind == "CANNON":
			_batch(batches, "cannon", _cannon_mesh(), xf)
			block = 1.9  # (its wheels and trail)
		elif kind.begins_with("PALM_"):
			var v := kind.substr(5).to_lower()
			_batch(batches, "palm_" + v, _palm_mesh(v), xf)
			block = 0.5  # (its trunk's flare)
		elif kind == "LOT_EXIT":
			(r.get_or_add("side_exits",[]) as Array).append(xf)
		elif kind == "ADA_SIGN":
			_batch(batches, "ada_sign", _first_mesh(ADA_SIGN_SCENE), xf)
			block = 0.2
		elif kind == "ADA_PAINT":
			_batch(batches, "ada_paint", _first_mesh(ADA_PAINT_SCENE), xf)
			(r.get_or_add("ada_marks", []) as Array).append(xf)
		elif kind == "MASSAGE_TABLE":
			_batch(batches, "massage_table", _first_mesh(MASSAGE_SCENE), xf)
			block = 0.9
		elif kind == "DUMBBELL_RACK":
			_batch(batches, "dumbbell_rack", _first_mesh(DUMBBELL_SCENE), xf)
			block = 1.1
		elif kind == "TOILET":
			_batch(batches, "toilet", _first_mesh(TOILET_SCENE), xf)
			block = 0.45
		elif kind.begins_with("GYM_"):
			var gid := kind.substr(4)
			if gid in BENCH_RACKS:
				# the rack and its bar apart: the bar racked till a member takes it to press (ClubLife)
				var split := bench_split(gid)
				_batch(batches, kind, split[0], xf)
				if split[1] != null:
					_batch(batches, kind + "_bar", split[1], xf)
			else:
				_batch(batches, kind, _first_mesh(GYM_SCENE % gid), xf)
			block = float(GYM_BLOCK.get(gid, 0.4))
		elif kind.begins_with("BALLPACK_"):
			_batch(batches, kind, _first_mesh(BALLPACK_SCENE % kind.substr(9)), xf)
		elif kind.begins_with("FOLD_"):
			_batch(batches, kind, _first_mesh(FOLD_SCENE % kind.substr(5).to_lower()), xf)
		elif kind.begins_with("RACK_"):
			_batch(batches, kind, _first_mesh(RACK_SCENE % kind.substr(5).to_lower()), xf)
			block = 0.95
		elif kind.begins_with("MANNEQUIN_"):
			var v := kind.substr(10).to_lower()
			_batch(batches, "mannequin_" + v, _first_mesh(MANNEQUIN_SCENE % v), xf)
			block = 0.35
		elif kind.begins_with("SHIRT_"):
			_batch(batches, kind, _first_mesh(SHIRT_SCENE % kind.substr(6).to_lower()), xf)
		elif kind.begins_with("SHOE_"):
			_batch(batches, kind, _first_mesh(SHOE_SCENE % kind.substr(5).to_lower()), xf)
		elif kind.begins_with("CLUB_"):
			if interiors:
				(r["clubs"] as Array).append({"family": kind.substr(5), "xf": xf})
		elif kind == "AUTO":
			if interiors:
				(r["stalls"] as Array).append(xf)
		elif kind == "PRACTICE_CHIP":
			# a hitting mat (_flags aims it at the chipping green): facing its target (-Z), the
			# marker's scale the distance to it
			(r.get_or_add("practice", []) as Array).append({"xf": Transform3D(xf.basis.orthonormalized(), xf.origin),
				"target": xf.origin - xf.basis.orthonormalized().z * xf.basis.get_scale().x, "kind": "chip"})
		elif kind == "KEEPOUT":
			block = xf.basis.get_scale().x  # a berth all round it, its radius: a monument, a fountain's island
		elif kind == "BARN_BAY":
			# just inside one of the barn's open bays: where a cart's driven in to be put away, and out
			(r.get_or_add("barn_bays", []) as Array).append(xf)
		elif kind == "HOSE_REEL" or kind == "HOSE_HOOK":
			# the barn's hose reel on its wall: where the hose comes off the drum, and the hook its
			# nozzle hangs on (ClubLife draws the hose from one to the other, or to the cart boy)
			var key := "hose_reel" if kind == "HOSE_REEL" else "hose_hook"
			if not r.has(key): r[key] = xf
			(r.get_or_add("hose_reels" if kind == "HOSE_REEL" else "hose_hooks", []) as Array).append(xf)
		elif kind == "CARTPICK":
			# A pickup position is not a solid object. ClubLife supplies actual cart bodies;
			# attendants must be able to reach an empty space and a washed cart's driver door.
			if interiors:
				var picks: Array = r.get_or_add("cart_pick", [])
				picks.append(xf)
				picks.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.basis.get_scale().x < b.basis.get_scale().x)
		elif kind == "CARTLINE":
			# the line of carts behind the clubhouse waiting for the golfers, head first
			if interiors:
				var line: Array = r.get_or_add("cart_line", [])
				line.append(xf)
				line.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.basis.get_scale().x < b.basis.get_scale().x)
		elif kind == "CARTTURN":
			if interiors:
				r["cart_turn"] = xf.origin  # where the line turns from one row into the other
		elif kind == "RANGE_BAY" or kind == "RANGE_BAY_UP":
			# the range's hitting bays (each mat's middle) on the ground, and up in its lounge: as
			# many golfers can practise at once as there are
			if interiors:
				var bays: Array = r.get_or_add("range_bays" if kind == "RANGE_BAY" else "range_bays_up", [])
				bays.append(xf)
				bays.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.x < b.origin.x)
		elif kind == "RANGE_STAIR" or kind == "RANGE_STAIRTOP":
			# the stairs up to the lounge: the foot of each and the landing at its top, paired in order
			if interiors:
				var ends: Array = r.get_or_add("range_stairs" if kind == "RANGE_STAIR" else "range_stair_tops", [])
				ends.append(xf)
				ends.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.basis.get_scale().x < b.basis.get_scale().x)
		elif kind == "BALL_DISPENSER":
			# where a range golfer stands to fill a bucket at the range's ball dispenser, facing it
			if interiors:
				(r.get_or_add("dispensers", []) as Array).append(xf)
		elif kind == "TEEWAY":
			# the golfers' way out to the course, in order (the marker's scale is its step)
			if interiors:
				var way: Array = r.get_or_add("tee_way", [])
				way.append(xf)
				way.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.basis.get_scale().x < b.basis.get_scale().x)
		elif kind == "SPOT" or kind.begins_with("SPOT_"):
			if interiors:
				var seat_xf := xf
				# Supplied stools have a 0.72m seat, 8cm below the old swivel stools.
				if room == "restaurant" and kind == "SPOT_guest_bar": seat_xf.origin.y -= 0.08
				((r["spots"] as Dictionary).get_or_add(room, []) as Array).append({"xf": seat_xf, "role": kind.substr(5)})
		else:
			continue
		if block > 0.0:
			((r["blockers"] as Dictionary).get_or_add(room, []) as Array).append(Vector3(xf.origin.x, xf.origin.z, block))
		_drop(m)


## A part's kind from its imported name: Blender's ".001" duplicates and the marker index come
## through as trailing "_<digits>" groups ("CLUB_driver_12_003" -> "CLUB_driver").
static func _kind(n: StringName) -> String:
	var s := String(n)
	while true:
		var i := s.rfind("_")
		if i <= 0 or not s.substr(i + 1).is_valid_int():
			break
		s = s.substr(0, i)
	return s


## Park cars in `share` (0..1) of a parking lot's stalls (Course Manager): the same stalls for
## the same share, filling in a fixed scattered order, nose in (one in four backed in), each a
## car from the pack by its stall. Never in an accessible space or one a golfer's car is in or on
## its way to (the rig's "taken": ClubLife), and always leaving VISITOR_ROOM stalls free for
## arriving golfers. Replaces whatever was parked; the rig's "parked" lists the stalls it filled.
static func park(fac: Node3D, share: float) -> void:
	for c in fac.get_children():
		if String(c.name).begins_with("Batch_parked_"):
			fac.remove_child(c)
			c.queue_free()
	var r := rig(fac)
	var stalls: Array = r.get("stalls", [])
	var ada := ada_stalls(r)
	var taken: Dictionary = r.get("taken", {})
	var spaces := stalls.size() - ada.size()
	var open: Array = range(stalls.size()).filter(func(i: int) -> bool: return not ada.has(i) and not taken.has(i))
	open.sort_custom(func(a: int, b: int) -> bool: return _stall_hash(a) < _stall_hash(b))
	var n := clampi(roundi(spaces * share), 0, mini(open.size(), maxi(spaces - VISITOR_ROOM, 0)))
	r["parked"] = open.slice(0, n)
	if n == 0:
		return
	var batches := {}
	for k in range(n):
		var i: int = open[k]
		var h := _stall_hash(i)
		var xf: Transform3D = stalls[i]
		if h % 4 == 0:
			xf = xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		var v: String = CARS[(h / 7) % CARS.size()]
		_batch(batches, "parked_" + v, car_mesh(v), xf, car_paint(v, h / 3))
	_emit_batches(fac, batches, true)


## Car model `v`'s mesh with its body in a paint of its own (car_paint): the same mesh, its body
## surface on the paint shader (its own paint's colour, found from its texture, to repaint from).
static func car_mesh(v: String) -> Mesh:
	if _car_meshes.has(v):
		return _car_meshes[v]
	var src := _first_mesh(CAR_SCENE % v)
	if src == null:
		return null
	var mesh := src.duplicate() as Mesh
	for i in range(mesh.get_surface_count()):
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m == null or m.albedo_texture == null or not m.resource_name.begins_with("Body"):
			continue
		var paint := ShaderMaterial.new()
		paint.shader = load(CAR_PAINT_SHADER)
		paint.set_shader_parameter("albedo_tex", m.albedo_texture)
		paint.set_shader_parameter("base_paint", _own_paint(m.albedo_texture))
		paint.set_shader_parameter("roughness", m.roughness)
		paint.set_shader_parameter("metallic", m.metallic)
		# The SUV's black albedo overlaps the trim's colour and has deep baked
		# shadows. Its packed finish map identifies body panels without that guess.
		if v == "suv" and m.roughness_texture != null:
			paint.set_shader_parameter("use_finish_mask", true)
			paint.set_shader_parameter("finish_tex", m.roughness_texture)
		mesh.surface_set_material(i, paint)
	_car_meshes[v] = mesh
	return mesh


## The colour a car's body texture is mostly painted (sRGB): its commonest colour, the near-black
## trim and the bright chrome left out.
static func _own_paint(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img == null:
		return Color.WHITE
	if img.is_compressed():
		img.decompress()
	img.resize(64, 64)
	var counts := {}
	var sums := {}
	for y in range(64):
		for x in range(64):
			var c := img.get_pixel(x, y)
			var v := maxf(c.r, maxf(c.g, c.b))
			if v < 0.06 or (v > 0.92 and minf(c.r, minf(c.g, c.b)) > 0.8):
				continue
			var key := Vector3i(int(c.r * 8.0), int(c.g * 8.0), int(c.b * 8.0))
			counts[key] = int(counts.get(key, 0)) + 1
			sums[key] = (sums.get(key, Color(0, 0, 0, 0)) as Color) + c
	var best: Variant = null
	for key in counts:
		if best == null or int(counts[key]) > int(counts[best]):
			best = key
	if best == null:
		return Color.WHITE
	var sum: Color = sums[best]
	return Color(sum.r / counts[best], sum.g / counts[best], sum.b / counts[best])


## The paint (linear, for the shader) of a car of model `v` picked by `pick`: one of CAR_PAINTS, or
## the model's own.
static func car_paint(v: String, pick: int) -> Color:
	var hexc: String = CAR_PAINTS[posmod(pick, CAR_PAINTS.size())]
	if hexc == "":
		var mesh := car_mesh(v)
		for i in range(mesh.get_surface_count() if mesh != null else 0):
			var m := mesh.surface_get_material(i) as ShaderMaterial
			if m != null:
				return (m.get_shader_parameter("base_paint") as Color).srgb_to_linear()
		return Color.WHITE
	return Color(hexc).srgb_to_linear()


static var _tv_clip_mat: ShaderMaterial


## The TV `screen`'s video (`path`): played round and round into a little viewport of the
## screen's own, its picture on the screen (unlit, like the clip's).
static func _tv_video(screen: Node3D, path: String) -> Material:
	var stream := load(path) as VideoStream if ResourceLoader.exists(path) else null
	if stream == null:
		var off := StandardMaterial3D.new()
		off.albedo_color = Color(0.05, 0.06, 0.07)  # switched off
		return off
	var view := SubViewport.new()
	view.name = "Picture"
	view.size = Vector2i(480, 270)
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var player := VideoStreamPlayer.new()
	player.stream = stream
	player.expand = true
	player.size = Vector2(view.size)
	player.loop = true
	player.autoplay = true
	player.volume_db = -80.0  # (a TV over the bar: no sound)
	view.add_child(player)
	screen.add_child(view)
	var mat := ShaderMaterial.new()
	mat.shader = load(TV_SHADER)
	mat.set_shader_parameter("sheet", false)
	mat.set_shader_parameter("frames", view.get_texture())
	return mat


static func _tv_clip_material() -> ShaderMaterial:
	if _tv_clip_mat == null:
		_tv_clip_mat = ShaderMaterial.new()
		_tv_clip_mat.shader = load(TV_SHADER)
		_tv_clip_mat.set_shader_parameter("frames", load(TV_CLIP["frames"]))
		for k in ["count", "cols", "rows", "fps"]:
			_tv_clip_mat.set_shader_parameter(k, TV_CLIP[k])
	return _tv_clip_mat


## The lot's accessible stalls (indices into the rig's "stalls": the one each painted symbol is
## in), kept for blue badges: no car is parked in them.
static func ada_stalls(r: Dictionary) -> Array:
	if not r.has("ada"):
		var stalls: Array = r.get("stalls", [])
		var out: Array = []
		for mark: Transform3D in r.get("ada_marks", []):
			var best := -1
			var near := 2.0  # (the symbol is 1.4 m from its stall's middle; the next stall's is 3 m off)
			for i in range(stalls.size()):
				var d := (stalls[i] as Transform3D).origin.distance_to(mark.origin)
				if d < near:
					near = d
					best = i
			if best >= 0:
				out.append(best)
		r["ada"] = out
	return r["ada"]


## Whether nobody's car is in stall `i` of the lot `r` (a rig): not one parked there, not a
## golfer's (or on its way there), and not an accessible space.
static func stall_free(r: Dictionary, i: int) -> bool:
	return not (r.get("parked", []) as Array).has(i) and not (r.get("taken", {}) as Dictionary).has(i) and not ada_stalls(r).has(i)


## The point on the aisle in front of the stall at `xf` (the lot's local frame): where a car
## turns in to park nose first, and backs out to.
static func stall_mouth(xf: Transform3D) -> Vector3:
	var head := -xf.basis.z.normalized()  # (the stall's car parks facing its head, its front -Z)
	return xf.origin - head * (STALL_D * 0.47 + LOT_AISLE * 0.5)


## Driving lanes in the lot's own XZ. Derive the aisles from the actual stalls.
static func lot_driving_lanes(r: Dictionary) -> Array:
	if r.has("driving_lanes"):
		return r["driving_lanes"]
	var level := clampi(int(r.get("level", 1)), 1, 4)
	var drives: Array = [[19.6, -19.3], [18.9, -18.9], [27.4, -27.4], [29.3, -29.3]][level - 1]
	var aisles: Array = []
	for stall: Transform3D in r.get("stalls", []):
		var z := snappedf(stall_mouth(stall).z, 0.1)
		if not aisles.has(z): aisles.append(z)
	var lanes: Array = []
	var back := -24.0
	for z: float in aisles:
		lanes.append([Vector2(drives[1], z), Vector2(drives[0], z)])
		back = maxf(back, z)
	for x: float in drives:
		lanes.append([Vector2(x, -38.0), Vector2(x, back)])
	if level == 4:
		lanes.append([Vector2(-16, -20.2), Vector2(drives[0], -20.2)])
	r["driving_lanes"] = lanes
	return lanes


## Prefer the edge of an aisle or the perimeter; crossing a lane remains possible.
static func lot_walk_weight(lanes: Array, p: Vector2) -> float:
	var distance := INF
	for lane: Array in lanes:
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, lane[0], lane[1])))
	return 1.0 + 12.0 * (1.0 - smoothstep(1.4, 2.6, distance))


## Apply only to pedestrian grids. The car routes and vehicle grids retain their costs.
static func prefer_lot_edges(nav: Dictionary, r: Dictionary, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var grid: AStarGrid2D = nav["astar"]
	var inv := xf.affine_inverse()
	var lanes := lot_driving_lanes(r)
	var weights: Dictionary = nav.get_or_add("parking_weights", {})
	for z in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var cell := Vector2i(x, z)
			if grid.is_point_solid(cell): continue
			var world := grid.get_point_position(cell)
			var p := inv * Vector3(world.x, 0, world.y)
			if absf(p.x) > 37 or p.z < -41 or p.z > 27: continue
			var weight := lot_walk_weight(lanes, Vector2(p.x, p.z))
			if weight > 1.0:
				weights[cell] = weight
				grid.set_point_weight_scale(cell, maxf(grid.get_point_weight_scale(cell), weight))
	nav["weighted_smoothing"] = true


static func _stall_hash(i: int) -> int:
	return ((i + 17) * 2654435761) % 1000003


## Where `type` (its site at `level`) can go beside the placed facility `anchor` (its site at its
## "level", if `placements` says), square to it: off either side, then behind, then in front
## ({"pos", "rot"}; empty when none of them is open rough).
static func beside(course: PaintedCourse, placements: Dictionary, type: String, anchor: String, level: int = -1) -> Dictionary:
	if not placements.has(anchor):
		return {}
	var a: Dictionary = placements[anchor]
	var sa := site(anchor, int(a.get("level", -1)))
	var st := site(type, level)
	var gap := 3.0
	var rot := float(a["rot"])
	var right := sa.end.x + gap - st.position.x
	var left := sa.position.x - gap - st.end.x
	var middle := sa.get_center() - st.get_center()
	for off in [Vector2(right, sa.end.y - st.end.y), Vector2(left, sa.end.y - st.end.y), Vector2(middle.x, sa.end.y + gap - st.position.y),
			Vector2(right, middle.y), Vector2(left, middle.y), Vector2(middle.x, sa.position.y - gap - st.end.y)]:
		var p := to_world(a["pos"], rot, off.x, off.y)
		if site_problem(course, placements, type, p, rot, level) == "":
			return {"pos": p, "rot": rot}
	return {}


static func _drop(n: Node) -> void:
	n.get_parent().remove_child(n)
	n.free()


## A stable choice of one of `n` things for whatever stands at `p`.
static func _pick(p: Vector3, n: int) -> int:
	return posmod(int(floor(p.x * 3.7 + p.z * 5.3 + p.y * 1.3)), n)


static func _batch(batches: Dictionary, key: String, mesh: Mesh, xf: Transform3D, colour: Variant = null) -> void:
	if mesh == null:
		return
	var b: Dictionary = batches.get_or_add(key, {"mesh": mesh, "xf": [], "col": []})
	(b["xf"] as Array).append(xf)
	if colour != null:
		(b["col"] as Array).append(colour)


static func _emit_batches(node: Node3D, batches: Dictionary, interiors: bool) -> void:
	for key in batches:
		var b: Dictionary = batches[key]
		var xfs: Array = b["xf"]
		var cols: Array = b["col"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = cols.size() == xfs.size() and not cols.is_empty()
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for i in range(xfs.size()):
			mm.set_instance_transform(i, xfs[i])
			if mm.use_colors:
				mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch_" + str(key)
		mmi.multimesh = mm
		if not interiors:
			mmi.visibility_range_end = PROP_RANGE_GOLF
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _is_shrub(id: String) -> bool:
	for s in SHRUBS:
		if id.begins_with(s):
			return true
	return false


## One of the woodland's bushes (the ones under the trees in the rough), normalised to 1 m
## across with its base at the origin.
static func _bush(i: int) -> Array:
	if not _bushes.has(i):
		var found := ForestPlanter.bush_mesh(i)
		var mesh: Mesh = found[0]
		var local: Transform3D = found[1]
		var box := local * mesh.get_aabb() if mesh != null else AABB(Vector3.ZERO, Vector3.ONE)
		var w := maxf(maxf(box.size.x, box.size.z), 0.01)
		var c := box.get_center()
		var fit := Transform3D(Basis.from_scale(Vector3.ONE / w), Vector3(-c.x, -box.position.y - 0.03 * w, -c.z) / w)
		_bushes[i] = [mesh, fit * local]
	return _bushes[i]


## Coarser architectural detail with real distance filtering prevents brick, boards and
## shingles from aliasing into stripes when the camera pulls back.
static func _crisp(model: Node) -> void:
	var architecture:={"roof":.62,"shingle":.68,"brick":.78,"patio_brick":.78,"wood_floor":.72,"deck":.72}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:continue
		for surface in mi.mesh.get_surface_count():
			var m:=mi.mesh.surface_get_material(surface) as BaseMaterial3D
			if m==null:continue
			m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var key:=m.resource_name.get_slice(".",0)
			if architecture.has(key):
				var scale:float=architecture[key]
				m.uv1_scale=Vector3(scale,scale,1)
				m.normal_scale=minf(m.normal_scale,.35)
				m.roughness=maxf(m.roughness,.75)
				m.metallic_specular=.25


## The first mesh in a prop scene (glTF imports keep the materials on the mesh surfaces).
## Bench rack `gid`'s model split in two (once): [the bench and rack without its bar, the bar
## with its plates on its own (null if there's none to find)]. Whole connected components
## are assigned together, keeping the uprights and their hardware intact. The bar is the long rod right
## across the model -- its ends the model's furthest out on x -- and the plates on it beyond the
## uprights.
static func bench_split(gid: String) -> Array:
	var key := "bench_split_" + gid
	if _meshes.has(key):
		return _meshes[key]
	var mesh := _first_mesh(GYM_SCENE % gid)
	var out: Array = [mesh, null]
	if mesh == null:
		_meshes[key] = out
		return out
	var reach := 0.0
	for s in range(mesh.get_surface_count()):
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			reach = maxf(reach, absf(v.x))
	var axis := Vector2.ZERO
	var n := 0
	for s in range(mesh.get_surface_count()):
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if absf(v.x) > reach - 0.04:
				axis += Vector2(v.y, v.z)
				n += 1
	if n == 0 or reach < 0.8:
		_meshes[key] = out
		return out
	axis /= n
	# Weld coincident positions across normal/UV seams and material surfaces. Decide
	# ownership for complete components, never individual triangles near the bar.
	var welded: Dictionary = {}
	var parents: Array[int] = []
	var surface_ids: Array = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var ids: Array[int] = []
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var position_key := Vector3i(roundi(v.x * 100000), roundi(v.y * 100000), roundi(v.z * 100000))
			if not welded.has(position_key):
				welded[position_key] = parents.size()
				parents.append(parents.size())
			ids.append(welded[position_key])
		surface_ids.append(ids)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for f in range(0, indices.size(), 3):
			var root := _bench_component_root(parents, ids[indices[f]])
			for j in [1, 2]:
				parents[_bench_component_root(parents, ids[indices[f + j]])] = root
	var components: Dictionary = {}
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):
			var v := vertices[i]
			var root := _bench_component_root(parents, surface_ids[surface][i])
			var radial := Vector2(v.y, v.z).distance_to(axis)
			# Inner hardware belongs to the uprights; the plates and collars sit outboard.
			var on_bar := radial < 0.035 or (absf(v.x) > 0.72 and radial < 0.27)
			components[root] = components.get(root, true) and on_bar
	var rack := ArrayMesh.new()
	var bar := ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, s) != OK:
			continue
		var keep := SurfaceTool.new()
		var lift := SurfaceTool.new()
		keep.begin(Mesh.PRIMITIVE_TRIANGLES)
		lift.begin(Mesh.PRIMITIVE_TRIANGLES)
		var kept := 0
		var lifted := 0
		for f in range(mdt.get_face_count()):
			var ids := [mdt.get_face_vertex(f, 0), mdt.get_face_vertex(f, 1), mdt.get_face_vertex(f, 2)]
			var component := _bench_component_root(parents, surface_ids[s][ids[0]])
			var onto: bool = components[component]
			var st := lift if onto else keep
			for i: int in ids:
				st.set_normal(mdt.get_vertex_normal(i))
				st.set_uv(mdt.get_vertex_uv(i))
				st.add_vertex(mdt.get_vertex(i))
			if onto:
				lifted += 1
			else:
				kept += 1
		var mat := mesh.surface_get_material(s)
		if kept > 0:
			keep.set_material(mat)
			keep.commit(rack)
		if lifted > 0:
			lift.set_material(mat)
			lift.commit(bar)
	out = [rack, bar if bar.get_surface_count() > 0 else null]
	_meshes[key] = out
	return out


static func _bench_component_root(parents: Array[int], index: int) -> int:
	var root := index
	while parents[root] != root: root = parents[root]
	while parents[index] != index:
		var next := parents[index]
		parents[index] = root
		index = next
	return root


static func _first_mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var m: Mesh = null
	var scene := _scene(path)
	if scene != null:
		var inst := scene.instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			m = (found[0] as MeshInstance3D).mesh
		inst.free()
	_meshes[path] = m
	return m


## The fountain running (user), on its model (FOUNTAIN_SCENE: a jet up out of its finial, its
## top bowl at z 2.85, the middle 2.06, the basin 0.80, their lips round them) put at `xf` under
## `parent`: a jet out of the finial falling back into the top bowl; a curtain of water over each
## bowl's lip down into the pool under it, spray at its foot; the three pools' surfaces rippling
## out from where it drops in (shaders/fountain_water.gdshader).
static func _fountain_water(parent: Node, xf: Transform3D) -> void:
	var root := Node3D.new()
	root.name = "FountainWater"
	root.transform = xf
	parent.add_child(root)
	var shader := load(FOUNTAIN_WATER) as Shader
	var pool_mat := func(start: float) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("fall", 0.0)
		m.set_shader_parameter("ring_start", start)
		return m
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = shader
	fall_mat.set_shader_parameter("fall", 1.0)
	# the pools: (height, radius, where their rings start from)
	for pool in [[2.865, 0.5, 0.0], [2.075, 0.79, 0.9], [0.815, 2.25, 0.5]]:
		var disc := MeshInstance3D.new()
		disc.mesh = _disc(float(pool[1]))
		disc.material_override = pool_mat.call(float(pool[2]))
		disc.position.y = float(pool[0])
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
	# the curtains over the bowls' lips: (lip height, lip radius, foot height, foot radius)
	for curtain in [[2.89, 0.62, 2.07, 0.7], [2.12, 0.96, 0.81, 1.12]]:
		var sheet := MeshInstance3D.new()
		sheet.mesh = _curtain(float(curtain[0]), float(curtain[1]), float(curtain[2]), float(curtain[3]))
		sheet.material_override = fall_mat
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sheet)
		root.add_child(_spray(float(curtain[3]), float(curtain[2]), 120))
	# the jet out of the finial, falling back into the top bowl
	var jet := _spray(0.0, 3.22, 160)
	jet.direction = Vector3.UP
	jet.spread = 9.0
	jet.initial_velocity_min = 2.4
	jet.initial_velocity_max = 2.8
	jet.lifetime = 0.75
	jet.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	root.add_child(jet)


## A flat disc `r` across its radius at y 0, facing up, its UVs the disc's (middle at 0.5, 0.5).
static func _disc(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in range(n):
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for v: Vector2 in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
			st.set_normal(Vector3.UP)
			st.set_uv(v * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(v.x * r, 0.0, v.y * r))
	return st.commit()


## An open sheet of falling water round the axis from a lip (height y0, radius r0) bowing out and
## down to its foot (y1, r1): UV.x round it, UV.y 0 at the lip to 1 at the foot.
static func _curtain(y0: float, r0: float, y1: float, r1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var rows := 8
	var ring := func(i: int, j: int) -> Vector3:
		var t := float(j) / rows
		var r := lerpf(r0, r1, sqrt(t))  # (out over the lip first, then near straight down)
		var a := TAU * i / n
		return Vector3(cos(a) * r, lerpf(y0, y1, t * t * 0.4 + t * 0.6), sin(a) * r)
	for i in range(n):
		for j in range(rows):
			var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for k in q:
				st.set_uv(Vector2(float(k[0]) / n, float(k[1]) / rows))
				st.add_vertex(ring.call(k[0], k[1]))
	st.generate_normals()
	return st.commit()


## Spray where falling water lands: droplets thrown up off a ring `r` round the axis at height `y`
## (a point on it when `r` is 0).
static func _spray(r: float, y: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.45
	p.position.y = y
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = maxf(r, 0.01)
	p.emission_ring_inner_radius = maxf(r - 0.08, 0.0)
	p.emission_ring_height = 0.02
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var drop := SphereMesh.new()
	drop.radius = 0.014
	drop.height = 0.028
	drop.radial_segments = 4
	drop.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.93, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = mat
	p.mesh = drop
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The lawn's cannon (CANNON_SCENE), weathered: a blotchy grime multiplied over each of its
## parts' (already aged) colours, so none of it reads as a fresh, even coat.
static func _cannon_mesh() -> Mesh:
	if _meshes.has("cannon_aged"):
		return _meshes["cannon_aged"]
	var src := _first_mesh(CANNON_SCENE)
	var m: Mesh = src.duplicate() if src != null else null
	if m != null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.5, 0.44))  # (grime and wear)
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var grime := NoiseTexture2D.new()
		grime.width = 256
		grime.height = 256
		grime.seamless = true
		grime.noise = noise
		grime.color_ramp = ramp
		for i in range(m.get_surface_count()):
			var mat := m.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as BaseMaterial3D
			mat.detail_enabled = true
			mat.detail_albedo = grime
			mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			mat.uv1_triplanar = true  # (the grime laid on by position: its parts' own UVs vary)
			mat.uv1_scale = Vector3.ONE * 0.9
			m.surface_set_material(i, mat)
	_meshes["cannon_aged"] = m
	return m


## Palm `v`'s mesh (PALM_SCENE), its fronds' cards cut out by their alpha and seen from both
## sides (as they come they're blended: no good in a row of them, out of order).
static func _palm_mesh(v: String) -> Mesh:
	var key := "palm_cut_" + v
	if _meshes.has(key):
		return _meshes[key]
	var src := _first_mesh(PALM_SCENE % v)
	var m: Mesh = src.duplicate() if src != null else null
	if m != null:
		for i in range(m.get_surface_count()):
			var mat := m.surface_get_material(i) as BaseMaterial3D
			if mat != null and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mat = mat.duplicate() as BaseMaterial3D
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.surface_set_material(i, mat)
	_meshes[key] = m
	return m


## The club cap for the shop's displays: its fabric tinted per cap (the MultiMesh's instance
## colours feed the albedo).
static func _cap_mesh() -> Mesh:
	var key := "cap#display"
	if _meshes.has(key):
		return _meshes[key]
	var src := _first_mesh(CAP_SCENE)
	var m: Mesh = null
	if src != null:
		m = src.duplicate()
		for i in range(m.get_surface_count()):
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D:
				var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				tinted.vertex_color_use_as_albedo = true
				m.surface_set_material(i, tinted)
	_meshes[key] = m
	return m


## One of the seamless hedge tiles, its leaf cut-outs alpha-scissored (no sorting trouble
## where tiles meet) and drawn from both sides.
static func _hedge_mesh(kind: String) -> Mesh:
	var key := "hedge#" + kind
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh = null
	var inst := _scene(HEDGE_SCENE).instantiate()
	var src := inst.find_child(kind, true, false) as MeshInstance3D
	if src != null and src.mesh != null:
		m = src.mesh.duplicate()
		for i in range(m.get_surface_count()):
			var mat := m.surface_get_material(i)
			if mat is BaseMaterial3D:
				var leaf := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				leaf.alpha_scissor_threshold = 0.45
				leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.surface_set_material(i, leaf)
	inst.free()
	_meshes[key] = m
	return m


# ---------------------------------------------------------------- walkable grids

## Trace a walkable grid for every furnished room (the kitchen as its own) and for the yard of a
## cart barn or range: AStarGrid2D cells over the floor, solid where furniture (the room's mesh
## between NAV_LOW and NAV_HIGH above the floor) or a prop stands, grown by one cell.
static func _build_nav(r: Dictionary) -> void:
	var boxes: Dictionary = r["boxes"]
	for key in boxes:
		var room := str(key).get_slice("__", 0)
		var part: MeshInstance3D = r["rooms"].get(room) as MeshInstance3D
		if part == null:
			continue
		var b: Dictionary = boxes[key]
		var rect: Rect2 = (b["rect"] as Rect2).grow(-0.3)  # off the walls
		r["nav"][key] = _nav_grid(rect, float(b["y"]), [part], NAV_CELL, r["blockers"].get(room, []))
	if r["type"] in ["cart_barn", "driving_range", "short_game", "parking_lot"]:
		var fp := footprint(str(r["type"]))
		var parts: Array = []
		for g in ["BASE", "WALLS_HIGH"]:
			parts.append_array(r["groups"].get(g, []))
		var blockers: Array = (r["blockers"].get("", []) as Array).duplicate()
		# Empty parking stalls remain walkable. ClubLife adds the actual parked
		# car bodies to each pedestrian route, rather than blocking every stall.
		# Include the range's (the short game area's, the lot's) apron so walkers can cross onto
		# the outdoor grid.
		var grow := 6.0 if r["type"] in ["driving_range", "short_game"] else (4.0 if r["type"] == "parking_lot" else -0.5)
		var yard := Callable()
		var line := range_line(r)
		if r["type"] == "driving_range" and line != INF:
			yard = func(p: Vector2) -> bool: return p.y > line  # (nobody on foot out in front of the bays)
		r["nav"][""] = _nav_grid(Rect2(-fp * 0.5, fp).grow(grow), 0.03, parts, NAV_YARD_CELL, blockers, 0.3, 2.2, yard)
		if r["type"] == "parking_lot":
			var pedestrian: Dictionary = r["nav"][""].duplicate()
			var source: AStarGrid2D = pedestrian["astar"]
			var grid := AStarGrid2D.new()
			grid.region = source.region
			grid.offset = source.offset
			grid.cell_size = source.cell_size
			grid.diagonal_mode = source.diagonal_mode
			grid.update()
			for z in range(source.region.position.y, source.region.end.y):
				for x in range(source.region.position.x, source.region.end.x):
					var cell := Vector2i(x, z)
					grid.set_point_solid(cell, source.is_point_solid(cell))
			pedestrian["astar"] = grid
			prefer_lot_edges(pedestrian, r)
			r["nav"]["pedestrian"] = pedestrian
		var up: Array = r.get("range_bays_up", [])
		if not up.is_empty():
			# the range's lounge upstairs: its own grid, on its floor (its stairs' landings and
			# bridges too) and nowhere else -- what's under it is the yard's
			var floor_y := (up[0] as Transform3D).origin.y
			var level := int(r["level"])
			var on_floor := func(p: Vector2) -> bool: return absf(walk_floor("driving_range", level, p) - floor_y) < 0.3
			r["nav"]["upper"] = _nav_grid(Rect2(-fp * 0.5, fp), floor_y, parts, NAV_YARD_CELL, [], 0.3, 2.2, on_floor)


## The driving range's hitting line (its own Z): just out in front of its ground bays' mats --
## beyond it (-Z) is the field, where the balls fly, and nobody walks. INF for anything else.
static func range_line(r: Dictionary) -> float:
	var line := INF
	for bay: Transform3D in r.get("range_bays", []):
		line = minf(line, bay.origin.z - 0.9)
	return line


## (`walkable`, if given, says which cells (by their middle) are on the floor at all.)
static func _nav_grid(rect: Rect2, floor_y: float, parts: Array, cell: float, blockers: Array, lo: float = NAV_LOW, hi: float = NAV_HIGH, walkable: Callable = Callable()) -> Dictionary:
	var nx := maxi(int(ceil(rect.size.x / cell)), 1)
	var nz := maxi(int(ceil(rect.size.y / cell)), 1)
	var solid := PackedByteArray()
	solid.resize(nx * nz)
	for node in parts:
		var part := node as MeshInstance3D  # a group with nothing in it comes through as a bare node
		if part == null or part.mesh == null:
			continue
		var xf := part.transform
		for si in range(part.mesh.get_surface_count()):
			var arr := part.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var w := PackedVector3Array()
			w.resize(verts.size())
			for i in range(verts.size()):
				w[i] = xf * verts[i]
			var n := idx.size() if not idx.is_empty() else verts.size()
			for t in range(0, n - 2, 3):
				var a := w[idx[t] if not idx.is_empty() else t]
				var b := w[idx[t + 1] if not idx.is_empty() else t + 1]
				var c := w[idx[t + 2] if not idx.is_empty() else t + 2]
				if maxf(a.y, maxf(b.y, c.y)) - floor_y < lo or minf(a.y, minf(b.y, c.y)) - floor_y > hi:
					continue
				var x0 := floori((minf(a.x, minf(b.x, c.x)) - rect.position.x) / cell)
				var x1 := floori((maxf(a.x, maxf(b.x, c.x)) - rect.position.x) / cell)
				var z0 := floori((minf(a.z, minf(b.z, c.z)) - rect.position.y) / cell)
				var z1 := floori((maxf(a.z, maxf(b.z, c.z)) - rect.position.y) / cell)
				if x1 < 0 or z1 < 0 or x0 >= nx or z0 >= nz:
					continue
				for cz in range(maxi(z0, 0), mini(z1, nz - 1) + 1):
					for cx in range(maxi(x0, 0), mini(x1, nx - 1) + 1):
						solid[cz * nx + cx] = 1
	for bl: Vector3 in blockers:
		var reach := ceili(bl.z / cell)
		var ccx := floori((bl.x - rect.position.x) / cell)
		var ccz := floori((bl.y - rect.position.y) / cell)
		for cz in range(maxi(ccz - reach, 0), mini(ccz + reach, nz - 1) + 1):
			for cx in range(maxi(ccx - reach, 0), mini(ccx + reach, nx - 1) + 1):
				if Vector2(cx - ccx, cz - ccz).length() * cell <= bl.z:
					solid[cz * nx + cx] = 1
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, nx, nz)
	g.cell_size = Vector2(cell, cell)
	g.offset = rect.position + Vector2(cell, cell) * 0.5
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for cz in range(nz):
		for cx in range(nx):
			if solid[cz * nx + cx] == 1 or (cx > 0 and solid[cz * nx + cx - 1] == 1) or (cx < nx - 1 and solid[cz * nx + cx + 1] == 1) \
					or (cz > 0 and solid[(cz - 1) * nx + cx] == 1) or (cz < nz - 1 and solid[(cz + 1) * nx + cx] == 1):
				g.set_point_solid(Vector2i(cx, cz))
			elif walkable.is_valid() and not walkable.call(g.get_point_position(Vector2i(cx, cz))):
				g.set_point_solid(Vector2i(cx, cz))  # (off the floor this grid is for)
	# Furniture can enclose tiny walkable pockets. Keep their connectivity so a
	# floor worker never spawns in one or chooses an unreachable destination.
	var labels := PackedInt32Array()
	labels.resize(nx * nz)
	labels.fill(-1)
	var regions: Array = []
	var largest := -1
	for cz in range(nz):
		for cx in range(nx):
			var start := Vector2i(cx, cz)
			if g.is_point_solid(start) or labels[cz * nx + cx] >= 0:
				continue
			var cells: Array[Vector2i] = [start]
			var id := regions.size()
			labels[cz * nx + cx] = id
			var cursor := 0
			while cursor < cells.size():
				var at := cells[cursor]
				cursor += 1
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = at + offset
					if g.region.has_point(next) and not g.is_point_solid(next) and labels[next.y * nx + next.x] < 0:
						labels[next.y * nx + next.x] = id
						cells.append(next)
			regions.append(cells)
			if largest < 0 or cells.size() > regions[largest].size():
				largest = id
	return {"astar": g, "rect": rect, "cell": cell, "y": floor_y, "labels": labels, "regions": regions, "largest": largest}


## A walking route on facility `fac`'s grid `key` (a room id, "restaurant__kitchen", or "" for
## the yard) between two points in the facility's own XZ, round whatever's in the way. Empty
## when there's no grid; ends at `to` (or the nearest walkable spot to it).
static func nav_route(fac: Node3D, key: String, from: Vector2, to: Vector2) -> PackedVector2Array:
	var nav: Dictionary = rig(fac).get("nav", {}).get(key, {})
	if nav.is_empty():
		return PackedVector2Array()
	var g: AStarGrid2D = nav["astar"]
	var a := _nav_cell(nav, from)
	var b := _nav_cell(nav, to)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var pts := g.get_point_path(a, b)
	if pts.size() > 1:
		pts[0] = from  # start where they stand, even half a cell off the grid
	return pull_tight(nav, _straighten(pts))


## Where to leave grid `key` (facility XZ) for somewhere beyond it, or come in from there: the
## walkable spot at the grid's edge that's reachable from `from` and nearest `toward`. INF if
## there's none.
static func nav_exit(fac: Node3D, key: String, from: Vector2, toward: Vector2) -> Vector2:
	var nav: Dictionary = rig(fac).get("nav", {}).get(key, {})
	if nav.is_empty():
		return Vector2.INF
	var g: AStarGrid2D = nav["astar"]
	var at := _nav_cell(nav, from)
	if at.x < 0:
		return Vector2.INF
	var n := g.region.size
	var best := Vector2.INF
	var distance := INF
	for cell: Vector2i in nav["regions"][nav["labels"][at.y * n.x + at.x]]:
		if cell.x > 1 and cell.y > 1 and cell.x < n.x - 2 and cell.y < n.y - 2:
			continue  # not at the edge
		var p := g.get_point_position(cell)
		if p.distance_squared_to(toward) < distance:
			best = p
			distance = p.distance_squared_to(toward)
	return best


## A random walkable point on grid `key` (facility XZ), or the centre of the grid if it's full.
static func nav_random(fac: Node3D, key: String, rng: RandomNumberGenerator, from: Vector2 = Vector2.INF) -> Vector2:
	var nav: Dictionary = rig(fac).get("nav", {}).get(key, {})
	if nav.is_empty():
		return Vector2.ZERO
	var g: AStarGrid2D = nav["astar"]
	if from != Vector2.INF:
		var at := _nav_cell(nav, from)
		if at.x >= 0:
			var id: int = nav["labels"][at.y * g.region.size.x + at.x]
			var cells: Array = nav["regions"][id]
			return g.get_point_position(cells[rng.randi_range(0, cells.size() - 1)])
	for _i in range(30):
		var c := Vector2i(rng.randi_range(0, g.region.size.x - 1), rng.randi_range(0, g.region.size.y - 1))
		if not g.is_point_solid(c):
			return g.get_point_position(c)
	return (nav["rect"] as Rect2).get_center()


## Nearest point on the room's main connected floor, excluding pockets behind furniture.
static func nav_floor_point(fac: Node3D, key: String, near: Vector2) -> Vector2:
	var nav: Dictionary = rig(fac).get("nav", {}).get(key, {})
	if nav.is_empty() or int(nav["largest"]) < 0:
		return Vector2.INF
	var g: AStarGrid2D = nav["astar"]
	var best := Vector2.INF
	var distance := INF
	for cell: Vector2i in nav["regions"][nav["largest"]]:
		var p := g.get_point_position(cell)
		var d := p.distance_squared_to(near)
		if d < distance:
			distance = d
			best = p
	return best


static func nav_has(fac: Node3D, key: String) -> bool:
	return rig(fac).get("nav", {}).has(key)


## The grid cell for `p`, or the nearest walkable one (Vector2i(-1, -1) if there's none near).
static func _nav_cell(nav: Dictionary, p: Vector2) -> Vector2i:
	var g: AStarGrid2D = nav["astar"]
	var cell: float = nav["cell"]
	var rect: Rect2 = nav["rect"]
	var c := Vector2i(clampi(floori((p.x - rect.position.x) / cell), 0, g.region.size.x - 1), clampi(floori((p.y - rect.position.y) / cell), 0, g.region.size.y - 1))
	if not g.is_point_solid(c):
		return c
	for ring in range(1, 12):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var q := c + Vector2i(dx, dz)
				if g.region.has_point(q) and not g.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Drop the in-between points of straight runs, so walkers head for the corners.
## Grid path `pts` on `nav` pulled tight: a corner kept only where the straight way on past it
## would cross a solid cell, so people walk straight across open floor at any angle, not in the
## grid's stair steps (the zig-zag of straight and diagonal moves).
static func pull_tight(nav: Dictionary, pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	var anchor := pts[0]
	var weighted := bool(nav.get("weighted_smoothing", false))
	var walked_cost := 0.0
	for k in range(1, pts.size() - 1):
		if weighted: walked_cost += _walk_line_cost(nav, pts[k - 1], pts[k])
		var shortcut := _clear_line(nav, anchor, pts[k + 1])
		if shortcut and weighted:
			shortcut = _walk_line_cost(nav, anchor, pts[k + 1]) <= (walked_cost + _walk_line_cost(nav, pts[k], pts[k + 1])) * 1.02
		if not shortcut:
			out.append(pts[k])
			anchor = pts[k]
			walked_cost = 0.0
	out.append(pts[pts.size() - 1])
	return out


## The same walking cost used by A*: smoothing must not cut back through a driving lane.
static func _walk_line_cost(nav: Dictionary, a: Vector2, b: Vector2) -> float:
	var g: AStarGrid2D = nav["astar"]
	var distance := a.distance_to(b)
	var n := maxi(ceili(distance / (float(nav["cell"]) * 0.5)), 1)
	var cost := 0.0
	for k in range(n):
		var p := a.lerp(b, (k + 0.5) / n)
		var cell := Vector2i(floori((p.x - g.offset.x) / g.cell_size.x + 0.5), floori((p.y - g.offset.y) / g.cell_size.y + 0.5))
		if not g.region.has_point(cell) or g.is_point_solid(cell): return INF
		cost += g.get_point_weight_scale(cell)
	return distance * cost / n


## Whether the straight way from `a` to `b` on `nav` crosses only open cells (sampled finely: no
## cutting a solid cell's corner).
static func _clear_line(nav: Dictionary, a: Vector2, b: Vector2) -> bool:
	var g: AStarGrid2D = nav["astar"]
	var cell: float = nav["cell"]
	var rect: Rect2 = nav["rect"]
	var n := maxi(ceili(a.distance_to(b) / (cell * 0.3)), 1)
	for k in range(n + 1):
		var p := a.lerp(b, float(k) / n)
		var c := Vector2i(floori((p.x - rect.position.x) / cell), floori((p.y - rect.position.y) / cell))
		if not g.region.has_point(c) or g.is_point_solid(c):
			return false
	return true


static func _straighten(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var d0 := (pts[i] - out[out.size() - 1]).normalized()
		var d1 := (pts[i + 1] - pts[i]).normalized()
		if d0.dot(d1) < 0.999:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


# ---------------------------------------------------------------- Course Manager: views, rooms, clubs

## Show every facility under `root` as `view` (View): the roof lifted off, or the walls dropped
## to waist height too, so the rooms and the people in them show.
static func set_view(root: Node, view: int) -> void:
	for fac in root.get_children():
		var r := rig(fac)
		var groups: Dictionary = r.get("groups", {})
		for n in groups.get("ROOF", []):
			(n as Node3D).visible = view == View.EXTERIOR
		for n in groups.get("WALLS_HIGH", []):
			(n as Node3D).visible = view != View.WALLS_DOWN
		for leaf: Node3D in r.get("door_leaves", []):
			leaf.visible = view != View.WALLS_DOWN
		for sign: Node3D in r.get("signs", []):
			# a sign on a wall drops with it; the monument by the drive keeps its name
			sign.visible = view != View.WALLS_DOWN or sign.has_meta("standing")


## The middle of a facility's building (its walls), in world space, for framing it.
static func building_center(fac: Node3D) -> Vector3:
	var groups: Dictionary = rig(fac).get("groups", {})
	for n in groups.get("WALLS_HIGH", []):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			return fac.global_transform * (mi.transform * mi.mesh.get_aabb().get_center())
	return fac.global_position


## The clubhouse room whose floor is under world point `p` ("" if none).
static func room_at(fac: Node3D, p: Vector3) -> String:
	var local := fac.global_transform.affine_inverse() * p
	var boxes: Dictionary = rig(fac).get("boxes", {})
	for id in boxes:
		if (boxes[id]["rect"] as Rect2).has_point(Vector2(local.x, local.z)):
			return str(id).get_slice("__", 0)  # "restaurant__kitchen" is the restaurant's
	return ""


## Stand the real clubs in the pro shop: each CLUB_<family> stand gets a playable catalog
## club of that family (picked by where it stands), drawn as one MultiMesh per part of that
## club's model. A club model takes a while to build, so this builds `max_models` per call;
## call it every frame until it returns true.
static func fill_clubs(fac: Node3D, max_models: int = 1) -> bool:
	var r := rig(fac)
	var todo: Array = r.get("clubs", [])
	if todo.is_empty():
		return true
	if r["club_root"] == null or not is_instance_valid(r["club_root"]):
		var holder := Node3D.new()
		holder.name = "Clubs"
		fac.add_child(holder)
		r["club_root"] = holder
	for _i in range(max_models):
		if todo.is_empty():
			break
		var asset := _shop_club(str(todo[0]["family"]), (todo[0]["xf"] as Transform3D).origin)
		var xfs: Array = []
		var rest: Array = []
		for c in todo:
			if _shop_club(str(c["family"]), (c["xf"] as Transform3D).origin) == asset:
				xfs.append(c["xf"])
			else:
				rest.append(c)
		todo = rest
		for part in _club_model(asset):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xfs.size()
			for k in range(xfs.size()):
				mm.set_instance_transform(k, (xfs[k] as Transform3D) * (part[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(r["club_root"] as Node3D).add_child(mmi)
	r["clubs"] = todo
	return todo.is_empty()


static func _shop_club(family: String, _p: Vector3) -> String:
	if not _club_ids.has(family):
		var ids: Array = []
		var cat := OFGEquipmentAssets.catalog()
		for id in cat:
			if str(cat[id].get("family", "")) == family and not bool(cat[id].get("admin_only", false)) and not str(id).begins_with("loaner"):
				ids.append(str(id))
		ids.sort()
		_club_ids[family] = ids
	var ids: Array = _club_ids[family]
	# A department carries one matching model line rather than a random club at each socket.
	return "" if ids.is_empty() else str(ids[0])


## A catalog club's parts, stood grip down: the butt of the shaft on the origin and the
## head straight up (the stands in the shop hold them that way).
static func _club_model(asset: String) -> Array:
	if _club_parts.has(asset):
		return _club_parts[asset]
	var parts: Array = []
	var club := OFGEquipmentAssets.create_club(asset) if asset != "" else null
	if club != null:
		var meshes := club.find_children("*", "MeshInstance3D", true, false)
		var butt := Vector3(0, 1, 0)
		var tip := Vector3.ZERO
		for mi: MeshInstance3D in meshes:
			if String(mi.name).ends_with("__shaft") and mi.mesh != null:
				var rel := _relative(mi, club)
				var lo := Vector3(0, INF, 0)
				var hi := Vector3(0, -INF, 0)
				for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var w := rel * v
					if w.y < lo.y:
						lo = w
					if w.y > hi.y:
						hi = w
				butt = hi
				tip = lo
				break
		var up := (tip - butt).normalized()
		var turn := Basis(Quaternion(up, Vector3.UP)) if up.length() > 0.5 else Basis()
		var display := Transform3D(turn, -(turn * butt))
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null or not mi.visible:
				continue
			var m: Mesh = mi.mesh.duplicate()
			for i in range(m.get_surface_count()):
				m.surface_set_material(i, mi.get_active_material(i))
			parts.append([m, display * _relative(mi, club)])
		club.free()
	_club_parts[asset] = parts
	return parts


static func _relative(n: Node, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# ---------------------------------------------------------------- primitives (sites, the range field)

static func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.82
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


static func _box(ctx: Dictionary, size: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = at
	(ctx["node"] as Node3D).add_child(mi)
	return mi


static func _cyl(ctx: Dictionary, r_top: float, r_bottom: float, h: float, at: Vector3, col: Color, sides: int = 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = h
	mesh.radial_segments = sides
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = at
	(ctx["node"] as Node3D).add_child(mi)
	return mi


## The club's name in a fine script -- Kunstler Script, the user's pick -- or the first of these
## the computer has (Windows has Segoe Script at least; Office adds the fancier ones), drawn
## from its own outlines, large (_raised_script letters it at SCRIPT_PX and scales it down).
static func _script_font() -> Font:
	if _script_face == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Kunstler Script", "Edwardian Script ITC", "Monotype Corsiva", "Segoe Script", "Brush Script MT", "cursive"])
		f.generate_mipmaps = true
		# each letter where the font puts it, its strokes running on into the next one's: no
		# distance field (Godot's sets each letter of a joined script a hair off, which steps
		# every join), and not nudged to whole pixels (hinting, rounded advances) either
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
		_script_face = f  # (bold by an outline: _raised_script)
	return _script_face


## The club's kind of club ("Country Club") under its name: engraved-looking small capitals,
## spaced a little apart -- Copperplate where there is it, else another titling face.
static func _titling_font() -> Font:
	if _titling_face == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Copperplate Gothic Bold", "Copperplate Gothic Light", "Perpetua Titling MT", "Engravers MT", "Baskerville Old Face", "Times New Roman", "serif"])
		f.generate_mipmaps = true  # (no distance field: Copperplate's overlapping strokes break it into specks)
		var spaced := FontVariation.new()
		spaced.base_font = f
		spaced.spacing_glyph = roundi(RELIEF_PX * 0.19)  # (px, at the size _relief cuts it: a fifth of a letter)
		_titling_face = spaced
	return _titling_face


## A club's name taken apart for its sign: the name itself, and what kind of club it is, to go
## under it ("Pinehurst Country Club": "Pinehurst" / "Country Club"; "Augusta National Golf Club":
## "Augusta" / "National Golf Club"; "Riviera CC": "Riviera" / "Country Club") or, when it's
## said first, over it ("The Golf Club of Georgia": "The Golf Club of" / "Georgia"). A name with
## no such ending, that's nothing else ("The Country Club") or that's just "... Club" (The
## Olympic Club) stays whole. {"name", "under", "over"}
static func club_name_parts(full: String) -> Dictionary:
	var out := {"name": full.strip_edges(), "under": "", "over": ""}
	var words: Array = []
	for w in full.strip_edges().split(" ", false):
		words.append(w)
	if words.size() < 2:
		return out
	const KINDS := ["golf", "country", "national", "club", "links", "course", "resort", "&", "and", "yacht", "racquet", "tennis", "hunt", "polo", "athletic", "cricket", "spa"]
	const ENDS := ["club", "links", "course", "resort"]
	const SHORT := {"cc": "Country Club", "c.c.": "Country Club", "gc": "Golf Club", "g.c.": "Golf Club", "gcc": "Golf & Country Club", "g&cc": "Golf & Country Club", "g.&c.c.": "Golf & Country Club", "gl": "Golf Links"}
	var last := str(words[-1]).to_lower()
	if SHORT.has(last):
		words.remove_at(words.size() - 1)
		words.append_array(str(SHORT[last]).split(" "))
	# said first: "The Golf Club of Georgia", "Country Club of Detroit"
	var of := -1
	for i in range(words.size()):
		if str(words[i]).to_lower() == "of":
			of = i
			break
	if of > 0 and of < words.size() - 1:
		var head := 1 if str(words[0]).to_lower() == "the" else 0
		var all_kind := of > head
		for i in range(head, of):
			all_kind = all_kind and KINDS.has(str(words[i]).to_lower())
		if all_kind and ENDS.has(str(words[of - 1]).to_lower()):
			out["over"] = " ".join(words.slice(0, of + 1))
			out["name"] = " ".join(words.slice(of + 1))
			return out
	# said after: back from the end over the kind-of-club words
	if not ENDS.has(str(words[-1]).to_lower()):
		return out
	var cut := words.size()
	while cut > 0 and KINDS.has(str(words[cut - 1]).to_lower()):
		cut -= 1
	while cut < words.size() and str(words[cut]).to_lower() in ["&", "and"]:
		cut += 1  # never start the small line on "&"
	var kind := words.slice(cut)
	var name := words.slice(0, cut)
	if kind.size() < 2 or name.is_empty() or (name.size() == 1 and str(name[0]).to_lower() == "the"):
		return out
	out["name"] = " ".join(name)
	out["under"] = " ".join(kind)
	return out


## A sign: text on the face pointing -Z (front), or +Z with back = true.
static func _sign(ctx: Dictionary, text: String, at: Vector3, px: int, col: Color = WHITE, back: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_modulate = Color(1, 1, 1, 0.35) if col.get_luminance() < 0.3 else Color(0, 0, 0, 0.8)
	l.outline_size = maxi(px / 10, 3)
	l.double_sided = false
	l.position = at
	l.rotation.y = 0.0 if back else PI
	(ctx["node"] as Node3D).add_child(l)
	return l


## The club's name lettered on a monument's panel (`panel`: its width and height in m), on up to
## two lines, as large as fits: raised letters standing out from the panel, not paint. `frame`:
## the panel's face (its middle), reading toward the frame's -Z (Godot's; the model's +Y).
static func _panel_sign(ctx: Dictionary, text: String, frame: Transform3D, panel: Vector2) -> Node3D:
	# the name in a script hand, and what kind of club it is in small capitals under it (or over
	# it: "The Golf Club of"); a script runs narrow, with a small body under tall loops, so it's
	# lettered larger than print
	var parts := club_name_parts(text)
	var name: String = parts["name"]
	var under: String = parts["under"]
	var over: String = parts["over"]
	var small := (under if under != "" else over).to_upper()  # all capitals, like the name's own lettering
	var room := 0.62 if small != "" else 1.0  # of the panel's height, for the name
	# (Kunstler: a narrow hand, its small body under capitals that fill the whole line)
	var one_line := minf(panel.y * 100.0 * room * 0.95, panel.x * 100.0 * 0.9 / (maxf(name.length(), 1.0) * 0.34))
	var two_lines := minf(panel.y * 100.0 * room * 0.36, panel.x * 100.0 * 0.9 * 2.0 / (maxf(name.length(), 1.0) * 0.34)) if name.contains(" ") else 0.0
	var px := clampi(int(maxf(one_line, two_lines)), 18, 150)
	var sub_px := clampi(int(minf(panel.y * 100.0 * 0.1, panel.x * 100.0 * 0.7 / (maxf(small.length(), 1.0) * 0.66))), 8, 30)
	# set by the letters' ink, not their fonts' line boxes (a script's box has room for loops far
	# below most names): the small line tucked just under the name's baseline -- or just over it,
	# "The Golf Club of" -- clear of any loop that hangs (or rises) over it, and the two together
	# centred on the panel, the name made smaller if they don't fit
	var kind := _ink_at(small, _titling_font(), sub_px, RELIEF_PX, 0.0) if small != "" else {}
	var ink := {}
	var sub_y := 0.0  # the small line's node from the name's (px, up)
	var top := 0.0
	var foot := 0.0
	for attempt in range(3):
		ink = _ink_at(name, _script_font(), px, SCRIPT_PX, panel.x * 100.0, float(kind.get("half", 0.0)) + sub_px * 0.3)
		top = ink["top"]
		foot = ink["foot"]
		if under != "":
			var gap := (float(kind["top"]) - float(kind["base"])) * 0.5  # half a capital
			sub_y = minf(ink["base"], ink["toe"]) - gap - float(kind["top"])
			foot = sub_y + float(kind["foot"])
		elif over != "":
			var gap := (float(kind["top"]) - float(kind["base"])) * 0.6
			sub_y = float(ink["head"]) + gap - float(kind["foot"])
			top = sub_y + float(kind["top"])
		if (top - foot) * 0.01 <= panel.y * 0.92 or px <= 18:
			break
		px = maxi(int(px * panel.y * 0.92 / ((top - foot) * 0.01)), 18)
	var holder := Node3D.new()  # the face's frame
	holder.name = "ClubSign"
	holder.transform = frame
	(ctx["node"] as Node3D).add_child(holder)
	var l := _raised_script(name, px, 0.025, panel.x * 100.0)
	l.name = "ClubName"
	l.position = Vector3(0.0, -(top + foot) * 0.5 * 0.01, 0.0)
	holder.add_child(l)
	if small != "":
		var sub := _relief(small, _titling_font(), sub_px, 0.025, 0.0)
		sub.name = "ClubKind"
		sub.rotation.y = 0.0  # it's turned with the name already
		sub.position = Vector3(0, sub_y * 0.01, 0.0125)  # in the name's frame, on the panel
		l.add_child(sub)
	return holder


## _ink, for `text` cut at `cut` px and scaled to `px` the way _raised_script and _relief letter it
## (so it wraps and reaches just as they draw it); `width` and `half` and what it gives are in `px`'s.
static func _ink_at(text: String, font: Font, px: int, cut: int, width: float, half: float = INF) -> Dictionary:
	var k := float(px) / cut
	var d := _ink(text, font, cut, width / k, half / k)
	for key in d:
		d[key] = float(d[key]) * k
	return d


## Where the ink of `text` reaches, set the way a Label3D or a TextMesh sets it (`font` at `px`,
## wrapped at `width` px if that's set, each line centred, the block centred on the node), in px
## from the node, up positive: "top" and "foot", the highest ink of its first line and the lowest
## of its last; "head" and "toe", the same within `half` px either side of the middle; "base",
## its last line's baseline; and "half", how far its ink reaches either side of the middle.
static func _ink(text: String, font: Font, px: int, width: float, half: float = INF) -> Dictionary:
	var ts := TextServerManager.get_primary_interface()
	var para := TextParagraph.new()
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE  # (AUTOWRAP_WORD_SMART)
	para.width = width if width > 0.0 else -1.0
	para.add_string(text, font, px)
	var lines := para.get_line_count()
	var tall := 0.0
	for i in range(lines):
		tall += para.get_line_size(i).y
	var out := {"top": -INF, "foot": INF, "head": -INF, "toe": INF, "base": 0.0, "half": 0.0}
	var y := tall * 0.5  # the top of the line, from the node
	for i in range(lines):
		var base := y - para.get_line_ascent(i)
		var x := -para.get_line_width(i) * 0.5
		for g: Dictionary in ts.shaped_text_get_glyphs(para.get_line_rid(i)):
			for _r in range(int(g["repeat"])):
				var rid: RID = g["font_rid"]
				var points: PackedVector3Array = ts.font_get_glyph_contours(rid, g["font_size"], g["index"]).get("points", PackedVector3Array()) if rid.is_valid() else PackedVector3Array()
				var off: Vector2 = g["offset"]
				for p in points:
					var ix := x + off.x + p.x
					var iy := base - off.y - p.y  # (a glyph's points run down from its baseline)
					var near := absf(ix) <= half
					out["half"] = maxf(out["half"], absf(ix))
					if i == 0:
						out["top"] = maxf(out["top"], iy)
						if near:
							out["head"] = maxf(out["head"], iy)
					if i == lines - 1:
						out["foot"] = minf(out["foot"], iy)
						if near:
							out["toe"] = minf(out["toe"], iy)
				x += float(g["advance"])
		if i == lines - 1:
			out["base"] = base
		y -= para.get_line_size(i).y
	for k in ["top", "head"]:
		if out[k] == -INF:
			out[k] = tall * 0.5
	for k in ["foot", "toe"]:
		if out[k] == INF:
			out[k] = out["base"]
	return out


const SCRIPT_PX := 400  # the size the club's name is lettered at, before it's scaled to the panel
const RELIEF_PX := 64  # and the size _relief cuts its letters at (every letter fills at 28 px and up)


## The club's name in the script, `depth` m proud of the panel (the node on the panel's face,
## reading from the front, -Z), `px` px high at 1 cm a px: the same letters in layers from the
## panel out to the front, a shade darker the deeper they are, the front a touch bold. (A
## TextMesh can't do a script: its strokes cross themselves, which leaves a TextMesh's letters
## hollow -- and Godot complaining.)
static func _raised_script(text: String, px: int, depth: float, width: float) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = PI  # a Label3D reads from +Z
	const LAYERS := 6
	# lettered at one size and scaled to `px`, so it's as bold on every panel (an outline is whole
	# px: thickening by px would jump a size), and large, so its hairlines hold up; bold by the
	# front's outline alone -- the layers behind it plain, so they can't close an "e"'s eye
	# seen from the side
	const LETTERED := SCRIPT_PX
	for k in range(LAYERS + 1):
		var t := float(k) / LAYERS  # 0 at the panel, 1 at the front
		var layer := Label3D.new()
		layer.text = text
		layer.font = _script_font()
		layer.font_size = LETTERED
		layer.pixel_size = 0.01 * px / LETTERED
		layer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		layer.width = width * LETTERED / px
		layer.modulate = SIGN_INK.darkened(0.3 * (1.0 - t))
		layer.outline_modulate = layer.modulate
		layer.outline_size = 12 if k == LAYERS else 8
		layer.shaded = true
		layer.double_sided = false
		layer.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS  # (edges blended: cut, a far sign's strokes wear thin)
		layer.position = Vector3(0.0, 0.0, 0.002 + depth * t)
		root.add_child(layer)
	return root


## `text` as raised letters `depth` m deep (centred on the node), reading from -Z like the panel
## signs, in the sign's dark green, matte; wrapping at `width` px if that's set. (A font whose
## strokes don't cross themselves: _raised_script for the script.)
static func _relief(text: String, font: Font, px: int, depth: float, width: float) -> MeshInstance3D:
	# cut at one size and scaled to `px`: a TextMesh can't fill some letters at some sizes
	# (Copperplate's "K" at 18 or 24 px, its overlapping strokes landing on each other)
	var mesh := TextMesh.new()
	mesh.text = text
	mesh.font = font
	mesh.font_size = RELIEF_PX
	mesh.pixel_size = 0.01 * px / RELIEF_PX
	mesh.depth = depth
	mesh.curve_step = 0.4 * RELIEF_PX / px  # (its curves as fine as they'd be cut at `px`)
	if width > 0.0:
		mesh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mesh.width = width * RELIEF_PX / px
	var mat := StandardMaterial3D.new()  # painted, matte: no glints off the strokes' edges
	mat.albedo_color = SIGN_INK
	mat.roughness = 0.9
	mat.metallic_specular = 0.15
	mesh.material = mat
	var l := MeshInstance3D.new()
	l.mesh = mesh
	l.rotation.y = PI  # a TextMesh reads from +Z: turned to read from the front (-Z)
	return l


## Ground height under local (x, z), relative to the facility's floor.
static func _ground(ctx: Dictionary, x: float, z: float) -> float:
	var w := to_world(ctx["pos"], float(ctx["rot"]), x, z)
	return float((ctx["height_at"] as Callable).call(w)) - float(ctx["floor"])


## The range's field out front, on the course's own ground beyond the plot: yardage boards
## with flags, and target greens (more of them at the higher levels).
static func _range_field(ctx: Dictionary, lv: int) -> void:
	var front := -footprint("driving_range").y * 0.5
	if lv >= 4:
		_range_perimeter(ctx, front)
	elif lv == 3:
		# down the right-hand side, like the top level's: from the end of the hitting bays,
		# flaring out, then on along the field
		_range_perimeter(ctx, front, range_net_outline(lv))
	var flags := [[50, RED], [100, WHITE], [150, Color("3f7fd1")], [200, GOLD], [250, DARK]]
	for f in flags:
		var z: float = front - float(f[0]) * YARD
		var gy := _ground(ctx, 0, z)
		_cyl(ctx, 0.05, 0.05, 3.0, Vector3(0, gy + 1.5, z), WHITE, 6)
		_box(ctx, Vector3(0.9, 0.6, 0.03), Vector3(0.45, gy + 2.7, z), f[1])
		_box(ctx, Vector3(2.6, 1.3, 0.1), Vector3(0, gy + 0.65, z + 0.3), WHITE)
		_sign(ctx, str(f[0]), Vector3(0, gy + 0.65, z + 0.36), 96, DARK, true)
	var targets := [[100, -14.0, 7.0], [150, 12.0, 8.0]]
	if lv >= 2:
		targets.append([200, -6.0, 9.0])
	if lv >= 3:
		targets.append([250, 16.0, 10.0])
	if lv >= 4:
		targets.append([75, 8.0, 5.0])
	for t in targets:
		var z: float = front - float(t[0]) * YARD
		var x: float = t[1]
		var gy := _ground(ctx, x, z)
		_range_target(ctx, Vector2(x,z), float(t[2]))
		_cyl(ctx, 0.03, 0.03, 2.2, Vector3(x, gy + 1.1, z), WHITE, 6)
		_box(ctx, Vector3(0.5, 0.35, 0.02), Vector3(x + 0.25, gy + 2.0, z), RED)


## A thin turf surface sampled across its entire area, rather than a flat
## cylinder balanced on the terrain height at its centre.
static func _range_target(ctx: Dictionary, center: Vector2, radius: float) -> void:
	var rings:=ceili(radius/.55)
	var segments:=64
	var points:=PackedVector3Array()
	points.append(Vector3(center.x,_ground(ctx,center.x,center.y)+.012,center.y))
	for ring in range(1,rings+1):
		for segment in range(segments):
			var p:=center+Vector2.from_angle(segment*TAU/segments)*(radius*ring/rings)
			points.append(Vector3(p.x,_ground(ctx,p.x,p.y)+.012,p.y))
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		for index in [0,1+(i+1)%segments,1+i]:st.add_vertex(points[index])
	for ring in range(1,rings):
		for i in range(segments):
			var a:=1+(ring-1)*segments+i
			var b:=1+(ring-1)*segments+(i+1)%segments
			var c:=1+ring*segments+(i+1)%segments
			var d:=1+ring*segments+i
			for index in [a,b,c,a,c,d]:st.add_vertex(points[index])
	st.generate_normals()
	var green:=MeshInstance3D.new();green.name="RangeTargetGreen";green.mesh=st.commit()
	green.material_override=_mat(TARGET_GREEN)
	green.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(ctx["node"] as Node3D).add_child(green)


## Full-height, open-top enclosure beyond the 250-yard target. The building closes
## the near end; both sides flare out from it and join the far catch net -- or, given
## `corners` (facility XZ), just that run of net. Sample the actual terrain along every panel
## so the lower edge never floats.
static func range_net_outline(level: int, front: float = -13.0) -> Array[Vector2]:
	if level >= 4:
		var far_z := front - 275.0 * YARD
		return [Vector2(-34.5, front + 1.0), Vector2(-42, front - 32), Vector2(-42, far_z), Vector2(42, far_z), Vector2(42, front - 32), Vector2(34.5, front + 1.0)]
	if level == 3:
		return [Vector2(23.5, front + 1.0), Vector2(31, front - 32), Vector2(31, front - 50)]
	return []


static func _range_perimeter(ctx: Dictionary, front: float, run: Array = []) -> void:
	var fence := Node3D.new()
	fence.name = "RangePerimeter"
	(ctx["node"] as Node3D).add_child(fence)
	var fence_ctx := ctx.duplicate()
	fence_ctx["node"] = fence
	var corners := run if not run.is_empty() else range_net_outline(4, front)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
void fragment() {
    vec2 grid = UV / 0.12;
    vec2 width = max(fwidth(grid), vec2(0.0001));
    vec2 dist = abs(fract(grid + 0.5) - 0.5);
    vec2 strand = 1.0 - smoothstep(vec2(0.025) - width * 0.5, vec2(0.025) + width * 0.5, dist);
    float coverage = max(strand.x, strand.y);
    coverage = mix(coverage, 0.10, clamp(max(width.x, width.y) - 0.5, 0.0, 1.0));
    float cable = 1.0 - smoothstep(0.018, 0.018 + max(fwidth(UV.y), 0.001), abs(mod(UV.y + 4.0, 8.0) - 4.0));
    ALBEDO = vec3(0.10, 0.14, 0.12);
    ROUGHNESS = 0.9;
    ALPHA = max(coverage, cable);
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var points: Array[Vector2] = []
	for side in range(corners.size() - 1):
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[side + 1]
		var count := ceili(a.distance_to(b) / 14.0)
		for i in range(count):
			points.append(a.lerp(b, float(i) / count))
	points.append(corners.back())
	for p in points:
		var ground := _ground(ctx, p.x, p.y)
		var post := _cyl(fence_ctx, 0.14, 0.25, 32.5, Vector3(p.x, ground + 16.25, p.y), Color("d9ded9"), 10)
		post.name = "NetPole"
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var segments := ceili(length / 1.0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(segments):
			var t0 := float(j) / segments
			var t1 := float(j + 1) / segments
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var g0 := _ground(ctx, p0.x, p0.y) - 0.08
			var g1 := _ground(ctx, p1.x, p1.y) - 0.08
			var h0 := lerpf(_ground(ctx, a.x, a.y), _ground(ctx, b.x, b.y), t0) + 32.0 - sin(t0 * PI) * 0.25
			var h1 := lerpf(_ground(ctx, a.x, a.y), _ground(ctx, b.x, b.y), t1) + 32.0 - sin(t1 * PI) * 0.25
			var vertices := [Vector3(p0.x, g0, p0.y), Vector3(p1.x, g1, p1.y), Vector3(p1.x, h1, p1.y), Vector3(p0.x, h0, p0.y)]
			var uvs := [Vector2(t0 * length, 0), Vector2(t1 * length, 0), Vector2(t1 * length, 32), Vector2(t0 * length, 32)]
			for index in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[index])
				st.add_vertex(vertices[index])
		st.generate_normals()
		var panel := MeshInstance3D.new()
		panel.name = "CatchNet"
		panel.mesh = st.commit()
		panel.material_override = material
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fence.add_child(panel)
		if ctx.get("body") != null:
			var collision := CollisionShape3D.new()
			collision.shape = panel.mesh.create_trimesh_shape()
			(ctx["body"] as StaticBody3D).add_child(collision)


## Level 0: stakes and tape round the first level's site and a sign naming what goes here.
static func _planned(ctx: Dictionary, type: String) -> void:
	var r := site(type, 1)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var fp := Vector2(0.0, -r.position.y)  # (the sign at the middle of its front: x 0, z -fp.y)
	var heights: Array = []
	for c in corners:
		var gy := _ground(ctx, c.x, c.y)
		heights.append(gy)
		_cyl(ctx, 0.06, 0.06, 1.3, Vector3(c.x, gy + 0.65, c.y), WOOD, 5)
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var y := (float(heights[i]) + float(heights[(i + 1) % 4])) * 0.5 + 1.1
		var tape := _box(ctx, Vector3(a.distance_to(b), 0.06, 0.02), Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5), TAPE)
		tape.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	var gy := _ground(ctx, 0.0, -fp.y)
	_box(ctx, Vector3(0.1, 1.4, 0.1), Vector3(-1.0, gy + 0.7, -fp.y), WOOD)
	_box(ctx, Vector3(0.1, 1.4, 0.1), Vector3(1.0, gy + 0.7, -fp.y), WOOD)
	_box(ctx, Vector3(2.8, 1.2, 0.08), Vector3(0, gy + 1.6, -fp.y), WHITE)
	var label := str(EconomyConfig.facility(type).get("name", type))
	_sign(ctx, "COMING SOON\n" + label.to_upper(), Vector3(0, gy + 1.6, -fp.y - 0.05), 30, DARK)


## Small, grounded wayfinding plaques outside each practice green's collar.
static func _practice_signs(ctx: Dictionary, rig: Dictionary, level: int) -> void:
	if rig["type"] != "short_game":return
	var plan:Dictionary=PRACTICE_TURF.get(level,{})
	for index in range((plan.get("greens",[]) as Array).size()):
		var green:Dictionary=plan["greens"][index]
		var center:Vector2=green["c"]
		var radii:Vector2=green["r"]
		var at:Vector2=center+Vector2(0,radii.y+PRACTICE_COLLAR+1.5).rotated(float(green.get("rot",0.0)))
		var sign:=Node3D.new();sign.name="PracticeAreaSign%d"%(index+1)
		sign.set_meta("standing",true)
		sign.set_meta("practice_label","CHIPPING AREA" if green.get("chip",false) else "PRACTICE GREEN")
		sign.position=Vector3(at.x,_ground(ctx,at.x,at.y),at.y)
		(ctx["node"] as Node3D).add_child(sign)
		(rig.get_or_add("signs",[]) as Array).append(sign)
		var local:={"node":sign}
		for x in [-.5,.5]:_box(local,Vector3(.07,.78,.06),Vector3(x,.39,0),Color("173e2b"))
		_box(local,Vector3(1.46,.5,.08),Vector3(0,1,0),Color("e4d7aa"))
		_box(local,Vector3(1.39,.43,.084),Vector3(0,1,0),Color("164b37"))
		for back in [false,true]:
			var face:=Node3D.new();face.name="Back" if back else "Front"
			face.position.z=-.05 if back else .05
			if back:face.rotation.y=PI
			sign.add_child(face)
			for item in [[str(sign.get_meta("practice_label")),1.045,.00145],["SHORT GAME",.89,.00075]]:
				var label:=Label3D.new();label.text=item[0];label.font=UITheme.font(700)
				label.font_size=64;label.pixel_size=item[2];label.modulate=Color("f5efda")
				label.outline_size=0;label.position.y=item[1];label.double_sided=false
				face.add_child(label)


static func _valet_station_details(ctx:Dictionary,rig:Dictionary)->void:
	if rig["type"]!="clubhouse" or not (rig.get("rooms",{}) as Dictionary).has("valet"):return
	var tier:=clampi(int(rig.get("room_tiers",{}).get("valet",1)),1,3)
	var counter:=Vector2(-6.65,3.205)
	var plaque:=MeshInstance3D.new();plaque.name="ValetGoldPlaque"
	var letters:=TextMesh.new();letters.text="Valet";letters.font=_script_font()
	letters.font_size=80;letters.pixel_size=.0032;letters.depth=.008
	letters.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;letters.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	plaque.mesh=letters
	var gold:=StandardMaterial3D.new();gold.albedo_color=Color("ffd36b")
	gold.metallic=1.0;gold.roughness=.2
	plaque.material_override=gold
	plaque.position=Vector3(counter.x,_ground(ctx,counter.x,counter.y)+.93,counter.y)
	plaque.rotation.y=PI
	(ctx["node"] as Node3D).add_child(plaque)
	var reflections:=ReflectionProbe.new();reflections.name="ValetGoldReflections"
	reflections.size=Vector3(10,7,10);reflections.max_distance=18;reflections.box_projection=true
	reflections.position=Vector3(counter.x,_ground(ctx,counter.x,counter.y)+1.4,3.6)
	(ctx["node"] as Node3D).add_child(reflections)
	if tier>=2:
		var shade:=_scene("res://assets/facilities/props/capri_d400.glb").instantiate() as Node3D
		shade.name="ValetUmbrella"
		shade.position=Vector3(-7.9,_ground(ctx,-7.9,4.1)+.1,4.1)
		(ctx["node"] as Node3D).add_child(shade)
	var bays:Array=[]
	for index in range(10):bays.append(Transform3D(Basis(Vector3.UP,PI),Vector3(-15.0-index*2.75,0,3.25)))
	rig["valet_stalls"]=bays
