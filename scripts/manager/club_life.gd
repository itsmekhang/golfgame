class_name ClubLife
extends Node3D
## The people at the club in Course Manager -- never in the golf game, where the course is
## booked just for you. The staff you've hired work at their posts: the shop clerk, the
## bartender and the receptionist stay behind their desk / bar; chefs move about the kitchen;
## waiters walk the dining room between the tables; the others work at their post with now and
## then a walk round their room; attendants work the cart barn's and the range's yards;
## greenskeepers work out on the holes and the marshal does the rounds in a cart. Golfers come
## in groups as the club draws them: they walk the holes carrying their bags, or ride in carts
## with the bags strapped on the back (the cart barn's share), swing on the tees and fairways
## and putt out on the greens, a few holes each.
##
## Nobody walks through things: indoors and in the yards people follow the facility's walkable
## grids (FacilityBuilder.nav_route), and on the course golfers, carts and greenskeepers go round
## water, woods and the club's buildings (a coarse grid over the course, bunkers avoided).
##
## People are the Blender-built characters in assets/facilities/people (one rig: idle, walk,
## work, swing, putt, sit); skin, hair and golfers' cap colours vary per person. Course Manager
## owns one, points it at the course, the built facilities and the business, and calls refresh()
## when they change.

const PERSON := "res://assets/facilities/people/%s.glb"
const CART := "res://assets/facilities/props/golf_cart.glb"
const BAG := "res://assets/facilities/props/bags/golf_bag_%s.glb"
## Golfer looks (tools/blender/build_people.py GOLFERS): half of them women; sleeves, shorts and
## head-wear differ by look, and each golfer's polo and trousers take colours of their own.
const LOOKS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
const POLOS := [Color("27324d"), Color("9d2f34"), Color("f5f3ee"), Color("3f7a4f"), Color("7fb6d8"), Color("e8c547"),
	Color("e2725b"), Color("e7a1b8"), Color("6c5b8f"), Color("2f2f33"), Color("4f9a94"), Color("d9d2c3"), Color("1f5fa8")]
const TROUSERS := [Color("c3a77f"), Color("27324d"), Color("5a5e63"), Color("f5f3ee"), Color("2b2b2e"), Color("8a8f76"),
	Color("d8ccb0"), Color("6e5844")]
## The walk clip (its motion capture) covers this many metres a second; it plays at the
## walker's own pace so the feet don't slide.
const WALK_PACE := 1.69
const SKIN := [Color("f1c7a5"), Color("e0ac86"), Color("c68e66"), Color("9a6a48"), Color("6e4a31"), Color("4b3020")]
const HAIR := [Color("2b1d14"), Color("3b2a1f"), Color("6b4a2f"), Color("b08a55"), Color("8a8a86"), Color("151515"), Color("d8c08a")]
const WALK := 1.35  # m/s
const CARRY_PACE := 1.05  # m/s the "carry" clip (a bucket in hand) walks at, at its own speed
## The range's ball bucket (the one that stood by each mat: fm_lib.range_bucket), carried from the
## ball dispenser to the bay by its bail (BUCKET_BAIL up from its foot) and set down beside the mat.
const BUCKET := "res://assets/facilities/props/range_bucket.glb"
const BUCKET_BAIL := 0.45
const RIDE := 5.5
const VALET_GREETING_SECONDS := 3.0
const VALET_STOP_ANGLE := deg_to_rad(125.0)
## A bucket at the range: each golfer hits this many, on their own time, before packing up.
const RANGE_BALLS := 20
## How far the ball tray beside each range mat reaches out from the mat's middle (fm_lib.mat_bay).
const RANGE_TRAY := 1.12
## The range's ball picker (tools/blender/build_range_picker.py): the caged cart, its gang of pick-up
## discs this far behind its middle, picking up what lies within PICKER_REACH either side of it.
const PICKER := "res://assets/facilities/props/range_picker.glb"
const PICKER_GANG := 2.45
const PICKER_REACH := 1.4
## The picker's three see-through wire baskets, one over each gang of pick-up discs (its frame,
## the cart facing -Z; build_range_picker.py gang()): what each gang picks up rides up into the
## basket over it, BASKET_SHOW for each ball (a real range's field holds far more than the ones
## hit while you watch), till the attendant empties them once it's parked. Each basket's middle
## across the gang, and the inside of the middle one.
const PICKER_BASKETS := [-0.9, 0.0, 0.9]
const PICKER_BASKET := AABB(Vector3(-0.41, 0.338, 2.28), Vector3(0.82, 0.23, 0.34))
const BASKET_SHOW := 3
## The range's ground floor, its mats' tops (its walk map has the lounge above where there is one).
const RANGE_FLOOR := 0.1
const MAX_GROUPS := 16
const MAX_FLIGHT_SIZE := 4
## Guests' places in the clubhouse's rooms (the model's SPOT_guest_* markers, build_facilities.py):
## role -> how they use it (the animation) and where they step to it from (m: to their right,
## ahead of them).
const GUEST_USE := {
	"guest_bar": ["sit", Vector2(0.0, -0.7)],  # up on a stool, from behind it
	"guest_seat": ["sit", Vector2(0.0, 0.75)],  # down into a lounge chair, from in front of it
	"guest_gym_run": ["walk", Vector2(0.8, 0.0)],  # on a treadmill, from its side
	"guest_gym_elliptical": ["elliptical", Vector2(0.8, 0.0)],  # on the elliptical, a hand on each handle
	"guest_gym_ride": ["spin", Vector2(0.75, 0.0)],  # a spin bike: over the bars, pedalling
	"guest_gym_sit": ["bench", Vector2(0.65, 0.0)],  # a weights bench: the bench press
	"guest_gym_stretch": ["work", Vector2(0.0, 0.0)],  # a mat: sit-ups (user: only those on a mat)
	"guest_gym_weights": ["front_raise", Vector2(0.0, 0.6)],  # by the dumbbell rack: raises with a dumbbell in each hand
	"guest_gym_kettlebell": ["kettlebell", Vector2(0.0, 0.6)],  # by the kettlebells: swinging one
	"guest_sim": ["swing", Vector2(0.0, 1.2)],  # a simulator bay: hitting balls at its screen, from behind the mat (_sim_swing)
}
const GYM_USES := ["guest_gym_run", "guest_gym_elliptical", "guest_gym_ride", "guest_gym_sit", "guest_gym_stretch", "guest_gym_weights", "guest_gym_kettlebell"]
## On a mat: what a member does there, and what they hold for it -- sit-ups only, nothing held.
const MAT_MOVES := {"situps": ""}
## Off the mats, by the weights: what a member holds for it (the use's own clip: GUEST_USE).
const WEIGHT_HOLDS := {"guest_gym_weights": "dumbbells", "guest_gym_kettlebell": "kettlebell"}
const DUMBBELL_MOVES := ["front_raise", "bicep_curl"]
const GYM_CURL_SCENE := "res://assets/facilities/people/gym_curl_%s.glb"
const GYM_KETTLEBELL := "res://assets/facilities/props/gym/gym_kettlebell.glb"
const GYM_VISITS := 5  # members working out at once (user: the gym used more)
const BAR_VISITS := 1  # one group visiting just for the bar
const BAR_GUESTS := 4  # includes returning golfers and people on their way to a stool
const SIM_SWING := 12.0  # s between a member's shots in a lesson in a simulator bay (the pro putting them right between)
## Game hours between simulator lessons: booked with the golf pro, by appointment -- only a few
## want one, with the range for practice (user) -- not first come, first served.
const SIM_LESSON_EVERY := 1.25
const STAFF_SHOWN := 3  # of any one role (greenskeepers: 6)
const SWING_S := 3.2
const PUTT_S := 2.6
const PUTT_IMPACT := 1.25  # the putt clip's stroke meets the ball this far in (s)
const SWING_IMPACT := 1.1666666667
## A chip (the "chip" clip: a short shot round the green, and the short game area's chipping
## mats): the club meets the ball this far in (s), and the stroke's done by CHIP_S. Shots with
## less than CHIP_RANGE to go are chipped.
const CHIP_IMPACT := 0.76
const CHIP_S := 2.4
const CHIP_RANGE := 40.0
const IMPACTS := {"swing": SWING_IMPACT, "putt": PUTT_IMPACT, "chip": CHIP_IMPACT}
const CLUB_HEAD_LOCAL := Vector3(.035, .85, 0)
## Cart seats in the cart model's frame (faces -Z; tools/blender/import_cart.py): driver on
## the left, in line with the steering wheel (centred 1.07 m up, 0.38 m forward, x = -0.30),
## passenger right. The person's own origin goes here: the seated poses put the hips 0.54 m up
## and 0.11 m back of it, onto the cushion (top 0.815 m up, z = 0.04 to 0.5; the driver sits
## nearer its front edge) with the feet on the floor (0.19 m); "drive" (build_people.py
## DRIVE_GRIP, CART_FEET) puts the hands on the wheel, "ride" rests them in the lap.
const SEATS := [Vector3(-0.3, 0.348, 0.18), Vector3(0.3, 0.348, 0.25)]
const SEAT_ANIMS := ["drive", "ride"]
## Getting into and out of a cart: the user's captures, each side of it ("_m": mirrored, the
## capture's getting in from the other side), played a little brisker than they were caught.
const CART_CLIPS := ["enter_cart", "enter_cart_m", "exit_cart", "exit_cart_m"]
const CART_CLIP_PACE := 1.35
## Golfers' caps (the club cap's fabric is mid grey, so these are bright).
const CAP_COLOURS := [Color("3a4a78"), Color("ffffff"), Color("d4404a"), Color("47a05b"), Color("2c2f33"), Color("f0d4a0"), Color("a8e0ff")]
## Who keeps to their post (behind the desk or the bar) and never wanders off.
const STAY := ["shop_clerk", "bartender", "receptionist", "golf_pro", "valet"]
## Who works their post typing, stood at the counter (the pro shop's till, the front desk).
const TYPING := ["shop_clerk", "receptionist"]
## The clips that go round and round (the rest play once: a swing, getting into a cart).
const LOOPS := ["breathe", "wipe", "wipe_hood", "bench_incline", "idle", "walk", "work", "sit", "drive", "ride", "carry", "type", "type_sit", "hose",
		"situps", "kettlebell", "front_raise", "bicep_curl", "elliptical", "spin", "bench"]
## The golf pros, one each (by hire): [room, the spot's role there] -- running the simulator bay from
## its screen, at the office desk, on the simulator room's sofa.
const PRO_JOBS := [["office", "golf_pro_desk"], ["simulator", "golf_pro"], ["simulator", "golf_pro_sit"]]  # (in hiring order: user)
## Where in their room a role moves about (a grid key: a part of the room, or the room itself).
const AREA := {"chef": "restaurant__kitchen"}
## The course grid: cell size (m) and what a bunker costs to cross.
const COURSE_CELL := 4.0
const BUNKER_COST := 5.0
const CART_PATH_COST := 6.0  # walking along the clubhouse's cart path (user: walkers keep off it; across it they may)
## The cart's two bag trays (their liners' tops); the bags stand upright in them.
const CART_BAGS := [Vector3(-0.301, 0.535, 1.039), Vector3(0.301, 0.535, 1.039)]
## Half the cart model's breadth and length (1.42 m by 2.58 m), and how far out to their own side
## of its middle its riders get on and off.
const CART_HALF := Vector2(0.72, 1.30)
const CART_DOOR := 1.3
## Where a bag run's second pair of bags ride on the first cart: in its passenger footwell, leaning
## back on the seat (the cart model's frame; its front is -Z).
const CART_CARGO := [Vector3(0.2, 0.19, -0.3), Vector3(0.5, 0.19, -0.3)]
## The cart's wheels where they touch the ground (x across, y forward): front left, front right,
## back left, back right.
const WHEELS := [Vector2(-0.57, 1.02), Vector2(0.57, 1.02), Vector2(-0.57, -0.95), Vector2(0.57, -0.95)]
const STOCK_MAX := 12  # carts left at the barn's row; past that they're put away inside
## The way a cart comes up to the clubhouse's front and away again, by level (facility XZ:
## build_facilities.py's plan x and -y): [in, out, backed off first]. In off the course past the
## plot's front edge and along the drive to the curb by the bag drop (its last point) -- on the
## drive, well clear of the front steps; out round and off past the front edge again, backed off
## the curb first where there's no drive on round (L1 beside its front walk, L2 across the car
## pad); L3 and L4 stop on their circle drive's near side and drive on round it.
## The clubhouse's front drive by level (its local XZ: Blender's x, -y): [in, out, backed off first].
## From L1 up, by its cart path (CART_PATHS): "in" is the way on from the path's end to the curb
## by the bag drop, "out" the way back onto it -- backed off the curb to turn round -- and the run
## along the path itself is put in (_front_drive).
const FRONT_DRIVE := {
	1: [[Vector2(2.6, 1.7)], [Vector2(4.6, -1.4), Vector2(7.0, 1.7)], true],
	2: [[Vector2(8.0, -1.2), Vector2(1.5, -1.4)], [Vector2(4.5, -5.0), Vector2(8.0, -1.2)], true],
	3: [[Vector2(5.0, -0.2), Vector2(2.6, -1.0), Vector2(0.0, -2.0)], [Vector2(2.6, -4.6), Vector2(5.0, -0.2)], true],
	4: [[Vector2(8.0, 1.9), Vector2(2.6, 1.2), Vector2(0.0, 0.8)], [Vector2(2.8, -1.6), Vector2(8.0, 1.9)], true],
}
## The cart boy's shortcut round the side of the clubhouse (user; build_facilities.cart_path, the
## same line): from the cart line's pad behind it, along the back, down the patio side and in along
## the front -- its corners swept round to CART_PATH_TURN like a running track's bends.
const CART_PATHS := {
	1: [Vector2(4.7, 39.8), Vector2(18.4, 39.8), Vector2(18.4, 1.7), Vector2(1.2, 1.7)],
	2: [Vector2(7.7, 39.8), Vector2(37.8, 39.8), Vector2(37.8, -1.2), Vector2(7.0, -1.2)],
	3: [Vector2(12.3, 39.8), Vector2(36.2, 39.8), Vector2(36.2, -0.2), Vector2(3.0, -0.2)],
	4: [Vector2(-3.4, 46.0), Vector2(41.8, 46.0), Vector2(41.8, 1.9), Vector2(4.0, 1.9)],
}
## Game hours between flights off the first tee: 8 minutes, a busy club's tee sheet (user: 15
## held the course's traffic back).
const TEE_INTERVAL := 8.0 / 60.0
## A golfer's range visit as it stands (data keys): cleared with it, or to start it again.
const RANGE_KEYS := ["practice", "range_bay", "range_stance", "range_bag", "range_hit", "range_next", "range_up", "range_bay_up", "range_step", "range_balls", "range_stall", "range_bucket", "range_machine", "range_chute"]
const CART_PATH_TURN := {1: 14.0, 2: 14.0, 3: 12.0, 4: 12.0}
## Where a flight's delivered carts wait for them, on the cart path's run past the line to the back
## walk (clubhouse local; the first there, the next a cart's length on along it): L4's, paved to its
## back door's walk (user). Without one, out past the end of the walk (_bag_run_meet).
const CART_PATH_MEET := {4: Vector2(4.9, 46.0)}  # m: as wide as each clears what's beside it
const RANGE_FIELD_WALK := 30.0  # m out in front of the range's bays the course's walkers keep off
const BAG_RUN_SERVICE_TARGET := 480.0  # Expected delivery time; never a substitute for a real handover.
## The cart boy, with nothing else on, washing the carts brought back to the barn's row: hosed
## down for WASH_HOSE s (the hose off the reel on the barn's wall), then wiped down for WASH_WIPE s;
## Each free attendant cleans a separate barn cart; ready-line wipes keep a cooldown.
const WASH_HOSE := 14.0
const WASH_WIPE := 6.0
const WASH_AGAIN := 150.0  # s before a cart's due washing (or wiping down) again (user: they stood about between)

var course: PaintedCourse
var facilities: Node3D  # FacilityBuilder.build()'s root: one child per facility
var business: CourseBusiness

var _traffic_cache_active := false
var _traffic_vehicles: Array = []
var _traffic_people: Array = []
var _vehicle_grid := {}
var _people_grid := {}
var animation_speed := 1.0
var _animation_players: Array[AnimationPlayer] = []

var _staff: Array = []  # Walker
var _groups: Array = []  # Group
var _staff_sig := ""
var _spawn_wait := 0.0
var _marked := -1  # how many groups there were when the lot's stalls were last marked (_mark_stalls)
var _guest_places := {}  # "room/i" (its guest spot) -> the Walker on it or on the way to it
var _filled := false  # the first golfers were spread over the course, not all on the first tee
var _rng := RandomNumberGenerator.new()
var _nav: AStarGrid2D  # the course's walking grid (water, woods and the buildings solid)
var _cart_nav: AStarGrid2D
var _arrival_serial := 0
var _cart_arrival_credit := .5
var _queue_serial := 0
var _lobby_serial := 0
var _board_serial := 0  # carts filled, in order: the first full leads off
var _bag_drop_serial := 0  # bags handed in at the front door (where the next one stands: _bag_drop_spot)
var _clock := 0.0  # seconds the club's been running (for the staff's now-and-then jobs)
var _pickers: Array = []  # the range's ball pickers (Walker), out sweeping or parked
## The club's own carts: the line behind the clubhouse (slot -> cart, or null; slot 0 its head),
## those brought back to the barn's row, and all of them (any the cart boy is moving too) --
## stepped here while they're not out with a flight.
var _line: Array = []
var _stock: Array = []
var _pool: Array = []
var _chute_users := {}  # a range ball dispenser's chute (its position) -> the golfer filling a bucket at it
var _restocking := false  # the line ran low: the cart boy keeps at it till it's full
var _bag_runs: Array = []  # [flight, cart index]: carts the cart boy's to bring round with their bags on (_bag_run)
var _nav_sig := ""
var _range_sig := ""  # the driving range as it was built last refresh: its level and placing (_re_range)
var _carts_on := false  # the cart barn working at the last refresh (_offer_carts)
var _barn_out := {}  # a parked cart's index in the barn (its rig's "barn_carts") -> the Walker driving it about, out of its space
var _barn_returns := {}  # Destination slot -> cart backing into its row; reserve until parked.
var _bay_washed := {}  # that index -> when it was last washed (_clock)
var _fac_was := {}
var _next_lesson := 0.0  # the club's time (business.hours) of the next simulator lesson booked
var _field_test: Callable  # the driving range's field, where nobody walks (_range_field), as it's built  # facility type -> [its global transform, its level] at the last refresh (_carry_with_facilities)
var _grounds_nav: Dictionary = {}
static var _scenes := {}
static var _mats := {}


## Someone (or a cart) moving about: walks its path, then waits, then thinks of what's next.
class Walker:
	var node: Node3D
	var anim: AnimationPlayer
	var path: Array = []  # Vector3 world points
	var speed := ClubLife.WALK
	var ground := true  # keep to the course's ground; false: walk at the path's own heights (indoors)
	var wait := 0.0
	var think: Callable
	var rest := "idle"  # what to play when standing
	var riding := false  # sat in a cart (plays its seat's pose whatever happens)
	var seat_anim := "sit"
	var data := {}


class Group:
	var golfers: Array = []  # Walker
	var carts: Array = []  # Walker (the cart; its riders are children)
	var hole := 0
	var start_hole := 0  # New rounds enter only at 1 or 10 (zero-based here).
	var holes_left := 3
	var stops: Array = []  # Vector2 along the hole: tee, fairway..., the pin
	var stop := 0
	var phase := "travel"  # travel -> (dismount) -> play -> (mount) -> travel
	var turn := 0
	var timer := 0.0
	var car: Walker
	var parking_path: Array = []  # the car's way in, to its bay
	var exit_path: Array = []  # and its way out
	var parking_slot := -1
	var parking_stall := -1  # the lot's stall its car is in, or on its way to (FacilityBuilder rig "stalls")
	var visit := ""  # "": a round of golf; "gym", "range", "short": in for just that, then home
	var checked_in := false
	var wants_cart := false
	var range_visit := false
	var short_visit := false  # warming up on the short game area first
	var short_rounds := 0
	var practice_balls: Array = []
	var range_slots: Array = []
	var balls: Array = []
	var ball_positions: Array = []
	var strokes: Array = []
	var holed: Array = []
	var scores: Array = []
	var flight := {}
	var retry := 0.0
	var hole_reserved := false
	var queue_hole := -1
	var queue_ticket := -1
	var sit_tight := false  # waiting on a tee in the carts till the flight ahead's out of reach
	var sit_tight_hole := -1  # (the hole that was decided for)
	var queue_rank := 0  # flights ahead of it in line for the tee when it last took its place
	var lane := -1  # its single file in the lobby's queue to check in (_lobby_queue), or -1
	var lobby_ticket := -1  # its turn at the desk: flights are seen in the order they came in
	var gym_left := -1  # stations a gym member's still to work out on (-1: not begun)
	var tee_started := false
	var wait_practice_elapsed := 0.0
	var wait_facility := ""
	var wait_practice := false  # filling its wait for the first tee on the short game area
	var wait_practiced := false  # (once is enough)
	var valet_service := {}  # Personal-car service only; golf carts remain attendant jobs.
	var bag_run := false  # the cart boy's bringing its carts round with its bags on (_bag_run)


func _ready() -> void:
	_rng.randomize()


## Call when the facilities were rebuilt or the business changed: the staff are respawned only
## when who's hired or where they work changed; golfers come and go on their own.
func refresh() -> void:
	_invalidate_traffic()
	if business == null:
		return
	_carry_with_facilities()  # (any moved: what's at it moved with it, before anyone's routed anew)
	_field_test = _range_field(RANGE_FIELD_WALK)
	var nsig := var_to_str([course.get_instance_id() if course != null else 0, business.placements, business.built, facilities.get_instance_id() if facilities != null else 0])
	if nsig != _nav_sig:
		_nav_sig = nsig
		_build_course_nav()
	var sig := var_to_str([business.staff, business.built, business.rooms, business.placements, facilities.get_instance_id() if facilities != null else 0])
	if sig != _staff_sig:
		_staff_sig = sig
		_spawn_staff()
	var barn := _fac("cart_barn")
	if barn != null:
		for index in _wall_reels(barn).size(): _hose_rest(barn, index)
	var carts := business.working("cart_barn")
	if carts and not _carts_on:
		_offer_carts()  # (just bought: those not yet checked in can ride now, not only the next in)
	_carts_on = carts
	var rsig := var_to_str([business.level("driving_range"), business.placements.get("driving_range", {})]) if business.placements.has("driving_range") else ""
	if rsig != _range_sig:
		if _range_sig != "" and rsig != "":
			_re_range()  # (upgraded or moved: its dispenser and bays elsewhere now)
		_range_sig = rsig
	_clock_hands(_fac("clubhouse"))


func clear() -> void:
	_animation_players.clear()
	for p in _staff:
		p.node.queue_free()
	_staff.clear()
	_invalidate_traffic()
	_pickers.clear()
	for c: Walker in _pool:
		if is_instance_valid(c.node):
			c.node.queue_free()
	_pool.clear()
	_invalidate_traffic()
	_stock.clear()
	_line.clear()
	for g in _groups:
		_free_group(g)
	_groups.clear()
	_invalidate_traffic()
	_guest_places.clear()
	_staff_sig = ""
	_nav_sig = ""
	_nav = null
	_cart_nav = null
	_filled = false


func staff_count() -> int:
	return _staff.size()


func golfer_count() -> int:
	var n := 0
	for g in _groups:
		n += (g as Group).golfers.size()
	return n


func _process(delta: float) -> void:
	_traffic_cache_active = true
	_invalidate_traffic()
	_simulate(delta)
	_traffic_cache_active = false
	_invalidate_traffic()


func _invalidate_traffic() -> void:
	_traffic_vehicles = []
	_traffic_people = []
	_vehicle_grid.clear()
	_people_grid.clear()


## Index full body bounds, including an off-center vehicle pivot. Rebuild lazily
## after a vehicle moves; queries return a conservative local candidate set.
func _nearby_vehicles(at: Vector3, reach: float = 1.0) -> Array:
	if not _traffic_cache_active: return _vehicles()
	if _vehicle_grid.is_empty():
		for v: Walker in _vehicles():
			if not is_instance_valid(v.node) or not v.node.is_visible_in_tree(): continue
			var frame := _vehicle_frame(v)
			var radius := _footprint(v).length() + 0.1
			var first := Vector2i(floori((frame.origin.x - radius) / 10.0), floori((frame.origin.z - radius) / 10.0))
			var last := Vector2i(floori((frame.origin.x + radius) / 10.0), floori((frame.origin.z + radius) / 10.0))
			for z in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					(_vehicle_grid.get_or_add(Vector2i(x, z), []) as Array).append(v)
	var found := {}
	var first := Vector2i(floori((at.x - reach) / 10.0), floori((at.z - reach) / 10.0))
	var last := Vector2i(floori((at.x + reach) / 10.0), floori((at.z + reach) / 10.0))
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for v: Walker in _vehicle_grid.get(Vector2i(x, z), []): found[v] = true
	return found.keys()


func _nearby_people(at: Vector3, reach: float) -> Array:
	if not _traffic_cache_active: return _pedestrians()
	if _people_grid.is_empty():
		for p: Walker in _pedestrians():
			if not is_instance_valid(p.node) or not p.node.is_visible_in_tree() or (p.riding and not p.data.has("cart_move")): continue
			var pos := p.node.global_position
			(_people_grid.get_or_add(Vector2i(floori(pos.x / 10.0), floori(pos.z / 10.0)), []) as Array).append(p)
	var out: Array = []
	var first := Vector2i(floori((at.x - reach) / 10.0), floori((at.z - reach) / 10.0))
	var last := Vector2i(floori((at.x + reach) / 10.0), floori((at.z + reach) / 10.0))
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): out.append_array(_people_grid.get(Vector2i(x, z), []))
	return out


## Camera and menus keep their normal speed. Only club animation follows the simulation.
func set_animation_speed(speed: float) -> void:
	animation_speed = speed
	for i in range(_animation_players.size() - 1, -1, -1):
		var player: AnimationPlayer = _animation_players[i]
		if is_instance_valid(player): player.speed_scale = speed
		else: _animation_players.remove_at(i)


func _simulate(delta: float) -> void:
	if course == null or business == null:
		return
	_clock += delta
	_wake_returning_attendants()
	_dispatch_cart_department()
	_turn_clock_hands()
	for p in _staff:
		if p.data.has("cart_move"):
			_cart_move_step(p, delta)  # (the cart boy climbing into a cart or out of it)
			continue
		_step(p, delta)
		if p.data.has("hose"):
			_hose_follow(p)
		if p.data.has("rag"):
			_rag_follow(p)
	for pk: Walker in _pickers:
		if not pk.path.is_empty():
			_picker_collect(pk)
	for c in _pool:
		(c as Walker).data["hurry"] = 1.0  # (the club's, back from a flight: the cart boy's pace)
		_step(c, delta)
	for g in _groups.duplicate():
		_step_group(g, delta)
	if _groups.size() != _marked:
		_mark_stalls()  # a group's gone: its car's stall is free again
	_spawn_wait -= delta
	if _spawn_wait <= 0.0:
		_spawn_wait = 4.0
		_top_up_golfers()


# ================================================================ people

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var s: PackedScene = load(path) if ResourceLoader.exists(path) else null
		_scenes[path] = s
	return _scenes[path]


## A person from `file` (e.g. "staff_chef", "golfer_c") with their own skin and hair (and, for
## a golfer, their own cap colour).
func _person(file: String) -> Walker:
	var scene := _scene(PERSON % file)
	if scene == null:
		return null
	var w := Walker.new()
	w.node = scene.instantiate() as Node3D
	w.node.add_to_group("club_people")
	w.node.set_meta("staff", file.begins_with("staff_"))
	add_child(w.node)
	for player: AnimationPlayer in w.node.find_children("*", "AnimationPlayer", true, false):
		player.speed_scale = animation_speed
		_animation_players.append(player)
	w.anim = w.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if w.anim != null:
		for loop in LOOPS:
			if w.anim.has_animation(loop):
				w.anim.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
		w.anim.play("breathe" if file.begins_with("staff_") and w.anim.has_animation("breathe") else "idle")
		w.anim.seek(_rng.randf() * 2.0, true)
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var hair: Color = HAIR[_rng.randi() % HAIR.size()]
	var cap: Color = CAP_COLOURS[_rng.randi() % CAP_COLOURS.size()]
	var shirt: Color = POLOS[_rng.randi() % POLOS.size()]
	var trousers: Color = TROUSERS[_rng.randi() % TROUSERS.size()]
	var golfer := file.begins_with("golfer_")
	if golfer and w.anim != null:
		var curl_scene := _scene(GYM_CURL_SCENE % ("female" if file.trim_prefix("golfer_") in ["d", "e", "g", "i", "k", "l"] else "male"))
		if curl_scene != null:
			var curl_model := curl_scene.instantiate()
			var curl_player := curl_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if curl_player != null and curl_player.has_animation("bicep_curl"):
				var library := AnimationLibrary.new()
				var curl := curl_player.get_animation("bicep_curl").duplicate() as Animation
				curl.loop_mode = Animation.LOOP_LINEAR
				var target_skeleton := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
				var animation_root := w.anim.get_node(w.anim.root_node)
				for i in curl.get_track_count():
					var path := curl.track_get_path(i)
					if path.get_subname_count() > 0:
						curl.track_set_path(i, NodePath(str(animation_root.get_path_to(target_skeleton)) + ":" + str(path.get_concatenated_subnames())))
				library.add_animation("bicep_curl", curl)
				w.anim.add_animation_library("gym", library)
			curl_model.free()
		# Retain the seated hip contact while the feet stay planted through each rep.
		var floor_clip := load("res://assets/facilities/people/gym_situps_%s.tres" % ("female" if file.trim_prefix("golfer_") in ["d", "e", "g", "i", "k", "l"] else "male")) as Animation
		if floor_clip != null:
			var library := w.anim.get_animation_library("").duplicate() as AnimationLibrary
			var seated := floor_clip.duplicate() as Animation
			var target_skeleton := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
			var animation_root := w.anim.get_node(w.anim.root_node)
			for i in seated.get_track_count():
				var path := seated.track_get_path(i)
				if path.get_subname_count() > 0:
					seated.track_set_path(i, NodePath(str(animation_root.get_path_to(target_skeleton)) + ":" + str(path.get_concatenated_subnames())))
			library.remove_animation("situps")
			library.add_animation("situps", seated)
			w.anim.remove_animation_library("")
			w.anim.add_animation_library("", library)
	for mi in w.node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var m := mesh.surface_get_material(i)
			if m == null:
				continue
			if m.resource_name == "skin":
				(mi as MeshInstance3D).set_surface_override_material(i, _tinted(m, skin))
			elif m.resource_name == "hair":
				(mi as MeshInstance3D).set_surface_override_material(i, _tinted(m, hair))
			elif m.resource_name == "cap" and golfer:
				(mi as MeshInstance3D).set_surface_override_material(i, _tinted(m, cap))
			elif m.resource_name == "shirt" and golfer:
				(mi as MeshInstance3D).set_surface_override_material(i, _tinted(m, shirt))
			elif m.resource_name == "pants" and golfer:
				(mi as MeshInstance3D).set_surface_override_material(i, _tinted(m, trousers))
	if golfer:
		var skeleton: Skeleton3D = w.node.find_child("Skeleton3D", true, false)
		if skeleton != null and skeleton.find_bone("hand.L") >= 0:
			var attachment := BoneAttachment3D.new()
			attachment.name = "HeldGolfClub"
			var grip_bone := "grip.L" if skeleton.find_bone("grip.L") >= 0 else "hand.L"
			attachment.bone_name = grip_bone
			w.data["grip_bone"] = grip_bone
			skeleton.add_child(attachment)
			var grip := Node3D.new()
			grip.name = "ClubGrip"
			attachment.add_child(grip)
			var shaft := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .008
			cylinder.bottom_radius = .006
			cylinder.height = .85
			cylinder.radial_segments = 6
			shaft.mesh = cylinder
			shaft.position.y = .42
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color("c3c8cc")
			steel.metallic = .8
			shaft.material_override = steel
			grip.add_child(shaft)
			var head := MeshInstance3D.new()
			var shape := BoxMesh.new()
			shape.size = Vector3(.10,.035,.055)
			head.mesh = shape
			head.position = Vector3(.035,.85,0)
			head.material_override = steel
			grip.add_child(head)
			attachment.visible = false
			w.data["held_club"] = attachment
			w.data["club_grip"] = grip
			var models := {}
			for family in ["iron", "putter"]:
				var model := _held_model(family)
				if model != null:
					grip.add_child(model)
					model.visible = family == "iron"
					models[family] = model
			if not models.is_empty():
				shaft.queue_free()
				head.queue_free()
			w.data["club_models"] = models
			var poses := {}
			for clip in IMPACTS:
				if w.anim != null and w.anim.has_animation(clip):
					w.anim.play(clip, 0)
					w.anim.seek(float(IMPACTS[clip]), true)
					poses[clip] = w.node.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(grip_bone))
			w.data["impact_hands"] = poses
			w.data["cart_clips"] = _measure_cart_clips(w, skeleton)
			if w.anim != null:
				w.anim.play("idle", 0)
				w.anim.seek(0, true)
	elif file in ["staff_cart_attendant", "staff_valet", "staff_range_attendant"]:
		# the cart boy gets in and out of the carts as the golfers do (user): their clips measured
		var sk: Skeleton3D = w.node.find_child("Skeleton3D", true, false)
		if sk != null:
			w.data["cart_clips"] = _measure_cart_clips(w, sk)
			if w.anim != null:
				w.anim.play("idle", 0)
				w.anim.seek(0, true)
	for player: AnimationPlayer in w.node.find_children("*", "AnimationPlayer", true, false):
		if not _animation_players.has(player):
			player.speed_scale = animation_speed
			_animation_players.append(player)
	return w


## Each of `w`'s cart clips (CART_CLIPS) measured in their own frame (feet at the origin, facing
## -Z): the hips where it starts and where it ends, which way the body faces then (yaw from -Z),
## and how long it runs; their seat poses' hips too ("drive", "ride").
func _measure_cart_clips(w: Walker, sk: Skeleton3D) -> Dictionary:
	var out := {}
	var hips := sk.find_bone("hips")
	if w.anim == null or hips < 0:
		return out
	var rest := sk.get_bone_global_rest(hips).basis
	var to_person := w.node.global_transform.affine_inverse() * sk.global_transform
	var sample := func(clip: String, t: float) -> Array:
		w.anim.play(clip, 0)
		w.anim.seek(t, true)
		var pose := to_person * sk.get_bone_global_pose(hips)
		var fwd := (pose.basis * rest.inverse()) * Vector3(0, 0, -1)
		return [pose.origin, atan2(-fwd.x, -fwd.z)]
	for clip in CART_CLIPS:
		if not w.anim.has_animation(clip):
			continue
		var length := w.anim.get_animation(clip).length
		var a: Array = sample.call(clip, 0.0)
		var b: Array = sample.call(clip, length)
		out[clip] = {"start": a[0], "start_yaw": a[1], "end": b[0], "end_yaw": b[1], "length": length}
	for clip in SEAT_ANIMS:
		if w.anim.has_animation(clip):
			out[clip] = {"hips": (sample.call(clip, 0.0) as Array)[0]}
	return out


## Use the same real equipment models as the pro shop and player.
func _held_model(family: String) -> Node3D:
	var asset := FacilityBuilder._shop_club(family, Vector3.ZERO)
	var model := OFGEquipmentAssets.create_club(asset) if asset != "" else null
	if model == null:
		return null
	var anchor: Node3D = ClubSwingRig._find_suffix(model, "__grip_anchor")
	if anchor == null:
		anchor = ClubSwingRig._find_suffix(model, "__grip")
	if anchor == null:
		model.free()
		return null
	var handle := ClubSwingRig._origin_relative_to(anchor, model)
	var a := -handle.normalized()
	var face := (Vector3.FORWARD - a * Vector3.FORWARD.dot(a)).normalized()
	var b := CLUB_HEAD_LOCAL.normalized()
	var front := (Vector3.BACK - b * Vector3.BACK.dot(b)).normalized()
	var turn := Basis(b, front, b.cross(front)) * Basis(a, face, a.cross(face)).transposed()
	var basis := turn.scaled(Vector3.ONE * CLUB_HEAD_LOCAL.length() / handle.length())
	model.transform = Transform3D(basis, -(basis * handle))
	return model


## The clip plays toward local -X; the ball is in front of the feet at local -Z.
func _address_offset(putt: bool) -> Vector3:
	return Vector3(0, 0, -.68 if putt else -.78)


func _shot_basis(aim: Vector2) -> Basis:
	var d := aim.normalized() if aim.length_squared() > .0001 else Vector2.UP
	return Basis(Vector3.UP, atan2(d.y, -d.x))


func _address_spot(ball: Vector2, target: Vector2, putt: bool) -> Vector2:
	var offset := _shot_basis(target - ball) * _address_offset(putt)
	return ball - Vector2(offset.x, offset.z)


## Fit the club at the actual impact frame, with its grip staying in the hand (`chip`: the chip's).
func _address_ball(w: Walker, ball: Vector3, aim: Vector2, putt: bool, chip: bool = false) -> void:
	w.data.erase("watch")  # (left from watching a flight-mate's shot, it'd turn them off the line mid-swing)
	w.data.erase("arrive_yaw")
	var basis := _shot_basis(aim)
	var at := ball - basis * _address_offset(putt)
	at.y = _surface_y(Vector2(at.x, at.z), ball.y - 0.085)  # (on the floor the ball is on: a range bay under its lounge)
	w.node.global_transform = Transform3D(basis, at)
	var clip := "putt" if putt else ("chip" if chip and w.data.get("impact_hands", {}).has("chip") else "swing")
	if w.data.has("club_grip") and w.data.get("impact_hands", {}).has(clip):
		var hand: Transform3D = w.data["impact_hands"][clip]
		var local_ball := w.node.global_transform.affine_inverse() * ball
		var reach := local_ball - hand.origin
		var toward := reach.normalized()
		# Resolve roll as well as shaft direction: +X is the head's toe, away
		# from the golfer; +Z is the club face, toward the shot's local -X.
		var toe := (Vector3.FORWARD - toward * Vector3.FORWARD.dot(toward)).normalized()
		var angle := atan2(CLUB_HEAD_LOCAL.x, CLUB_HEAD_LOCAL.y)
		var x := toward * sin(angle) + toe * cos(angle)
		var y := toward * cos(angle) - toe * sin(angle)
		var club_basis := Basis(x, y, x.cross(y)).orthonormalized()
		(w.data["club_grip"] as Node3D).transform = Transform3D((hand.basis.inverse() * club_basis).scaled(Vector3.ONE * reach.length() / CLUB_HEAD_LOCAL.length()), Vector3.ZERO)
		w.data["impact_grip"] = (w.data["club_grip"] as Node3D).transform
		w.data["swing_normal"] = -toe
		w.data["club_reach"] = reach.length()
		w.data["impact_direction"] = toward
	for family in w.data.get("club_models", {}):
		(w.data["club_models"][family] as Node3D).visible = family == ("putter" if putt else "iron")
	w.data["shot_ball"] = ball


## The two palm contacts define the shared grip and the captured wrist hinge.
func _update_held_club(w: Walker) -> void:
	if not w.data.has("impact_grip") or not w.data["held_club"].visible or w.riding:
		return
	var sk: Skeleton3D = w.node.find_child("Skeleton3D", true, false)
	var actor_inverse := w.node.global_transform.affine_inverse()
	var hand := actor_inverse * sk.global_transform * sk.get_bone_global_pose(sk.find_bone(w.data.get("grip_bone", "hand.L")))
	var raw: Vector3 = hand.basis * (w.data["impact_grip"] as Transform3D).basis * CLUB_HEAD_LOCAL
	var normal: Vector3 = w.data["swing_normal"]
	var toward := (raw - normal * raw.dot(normal)).normalized()
	if w.anim.assigned_animation in ["swing", "chip"] and sk.find_bone("grip.R") >= 0:
		var other := actor_inverse * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("grip.R"))
		toward = (hand.origin - other.origin).normalized()
		var contact: Vector3 = w.data["impact_direction"]
		var time := w.anim.current_animation_position
		var impact_blend := smoothstep(.11, 0.0, absf(time - float(IMPACTS[w.anim.assigned_animation])))
		toward = toward.slerp(contact, impact_blend).normalized()
		if time >= 1.95 and w.anim.assigned_animation == "swing":
			# The reference finish wraps the shaft slightly downward behind the shoulders.
			toward.y = -(.24 / sqrt(.80 * .80 + .90 * .90)) * Vector2(toward.x, toward.z).length()
			toward = toward.normalized()
	if toward.length_squared() < .5:
		return
	var toe := (Vector3.FORWARD - toward * Vector3.FORWARD.dot(toward)).normalized()
	var angle := atan2(CLUB_HEAD_LOCAL.x, CLUB_HEAD_LOCAL.y)
	var x := toward * sin(angle) + toe * cos(angle)
	var y := toward * cos(angle) - toe * sin(angle)
	var basis := hand.basis.inverse() * Basis(x, y, x.cross(y)).orthonormalized()
	basis = basis.scaled(Vector3.ONE * float(w.data["club_reach"]) / CLUB_HEAD_LOCAL.length())
	(w.data["club_grip"] as Node3D).transform = Transform3D(basis, Vector3.ZERO)


static func _tinted(base: Material, c: Color) -> Material:
	var key := "%s_%s" % [base.resource_name, c.to_html()]
	if not _mats.has(key):
		var m := base.duplicate() as BaseMaterial3D
		if m != null:
			m.albedo_color = c
		_mats[key] = m if m != null else base
	return _mats[key]


func _play(w: Walker, anim_name: String) -> void:
	if w.data.has("held_club"):
		w.data["held_club"].visible = anim_name in IMPACTS and not w.riding
	if w.anim == null:
		return
	if anim_name in ["work", "idle"] and w.node.get_meta("staff", false) and w.anim.has_animation("breathe"):
		anim_name = "breathe"
	if w.riding:
		anim_name = w.seat_anim if w.anim.has_animation(w.seat_anim) else "sit"
	elif anim_name == "walk" and w.data.has("bucket") and w.anim.has_animation("carry"):
		anim_name = "carry"  # (a bucket in the hand)
	if w.anim.current_animation != anim_name and w.anim.has_animation(anim_name):
		var pace := WALK_PACE if anim_name == "walk" else CARRY_PACE
		# The authored bike crank runs backwards; reverse this loop only. Hands stay fixed.
		var rate := w.speed * _pace(w) / pace if anim_name in ["walk", "carry"] else (-1.0 if anim_name == "spin" else 1.0)
		w.anim.play(anim_name, 0.25, rate, anim_name == "spin")
		if anim_name in ["walk", "carry"]:
			w.anim.seek(_rng.randf() * w.anim.current_animation_length, false)  # out of step with the rest


func _step(w: Walker, delta: float) -> void:
	if w.data.get("vehicle", false): _vehicle_grid.clear()
	else: _people_grid.clear()
	if _pedestrian_yield_step(w, delta):return
	if _rack_delivery_step(w,delta):return
	_update_held_club(w)
	if not w.data.get("vehicle", false):
		_repel(w, delta)  # (off the vehicles and each other, like poles: user)
		if not w.data.has("pedestrian_yield"):
			_unstick(w, delta)  # (walking and getting nowhere: off to one side, a roomba's way)
	if w.data.has("pass_route"):
		var aside: Vector3 = w.data["pass_aside"]
		if w.node.global_position.distance_to(aside) < 0.2:
			var other: Node3D = w.data["pass_other"].get_ref()
			if is_instance_valid(other) and other.global_position.distance_to(w.node.global_position) < 6.0:
				return
			w.path = w.data["pass_route"]
			for key in ["pass_route", "pass_aside", "pass_other"]: w.data.erase(key)
	if w.data.get("mat_move", "") == "situps" and w.data.get("seated", false):
		_mat_contact(w)
	if w.path.is_empty() and not w.riding and not w.data.get("vehicle", false) and not w.data.get("seated", false) and not w.data.has("cart_move"):
		var clear := _vehicle_space(w, w.node.global_position, delta)
		if _walk_region_clear(w, w.node.global_position, clear):
			clear.y = w.node.global_position.y
			w.node.global_position = clear
	if w.data.has("bucket"):
		_hang_bucket(w)
	if w.data.has("gym_held"):
		_gym_follow(w)
	if w.path.is_empty() and w.data.get("blocked", false):
		w.wait -= delta
		if w.wait <= 0.0:
			w.wait = 10.0
			if w.data.has("indoor_target"):
				var retry: Array = w.data["indoor_target"]
				var fac: Node3D = retry[0].get_ref()
				if is_instance_valid(fac):
					_go_inside(w, fac, retry[1], retry[2], retry[3])
			elif w.data.has("outdoor_target"):
				_go(w, w.data["outdoor_target"])
		return
	if not w.path.is_empty() and float(w.data.get("hold", 0.0)) > 0.0:
		w.data["hold"] = float(w.data["hold"]) - delta  # a beat before setting off
		return
	if not w.path.is_empty():
		var target: Vector3 = w.path[0]
		var pos := w.node.global_position
		var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		var d := to.length()
		var vehicle: bool = w.data.get("vehicle", false)
		if w.data.get("golf_cart", false) and not _manned(w):
			# a cart never drives itself (user): it waits for its driver to be sat in it -- and,
			# sent off with no one coming, stays where it is
			w.data["unmanned"] = float(w.data.get("unmanned", 0.0)) + delta
			if float(w.data["unmanned"]) > 20.0:
				w.path.clear()
				w.data["unmanned"] = 0.0
			return
		w.data["unmanned"] = 0.0
		var rounding := float(w.data.get("rounding", 0.0))
		if rounding > 0.0:
			w.data["rounding"] = rounding - delta  # (getting by someone stood in its way: on round them)
		if vehicle and d > 0.01 and _person_ahead(w, to / d):
			# someone on foot in the way: stopped for them till they're by (a car or a cart alike;
			# while they clear its body and stopping distance)
			w.data["give_way"] = float(w.data.get("give_way", 0.0)) + delta
			# Hold the original route and position; the pedestrian clears the lane first.
			w.data["pedestrian_stopped"] = true
			return  # No timeout permits driving into a pedestrian.
		else:
			w.data["give_way"] = 0.0
			w.data.erase("pedestrian_stopped")
		if vehicle and d > 0.01 and _cart_ahead(w, to / d):
			w.data["yield"] = float(w.data.get("yield", 0.0)) + delta
			if float(w.data["yield"]) > 2.5:
				_round_parked(w, to / d)  # (one parked in the way never moves: round it where there's room, or stopped short of it)
			return  # Waiting never grants permission to drive through another vehicle.
		else:
			w.data["yield"] = 0.0
		var stride := w.speed * _pace(w) * delta
		if not vehicle and d > 0.01:
			stride *= _give_way(w, to / d, delta)
			if not _walker_vehicle_clear(w, pos, pos + to / d * minf(stride, d)):
				w.data["traffic_wait"] = float(w.data.get("traffic_wait", 0.0)) + delta
				if float(w.data["traffic_wait"]) >= 0.75 and w.data.has("outdoor_target") and not w.data.has("indoor_target"):
					w.data["traffic_wait"] = 0.0
					_go(w, w.data["outdoor_target"])  # Route around a car waiting for this pedestrian.
				return
			w.data.erase("traffic_wait")
		if vehicle and d > 0.01:
			var next := w.node.global_transform
			next.origin = pos + to / d * minf(stride, d)
			if d > stride:
				var yaw := atan2(-to.x, -to.z) + (PI if int(w.data.get("reverse", 0)) > 0 else 0.0)
				next.basis = Basis(Vector3.UP, lerp_angle(w.node.rotation.y, yaw, minf(delta * 7.0, 1.0))).scaled(w.node.global_basis.get_scale())
			if not _vehicle_people_clear(w, w.node.global_transform, next):
				w.data["pedestrian_stopped"] = true
				return  # Check the whole stride and turn before moving or consuming a waypoint.
		if d <= stride:  # reach the corner before turning through a doorway
			pos = Vector3(target.x, pos.y, target.z) if d <= stride else pos + to / d * stride
			w.path.remove_at(0)
			if int(w.data.get("reverse", 0)) > 0:
				w.data["reverse"] = int(w.data["reverse"]) - 1
		else:
			pos += to / d * stride
			var yaw := atan2(-to.x, -to.z) + (PI if int(w.data.get("reverse", 0)) > 0 else 0.0)  # backing up: facing away
			w.node.rotation.y = lerp_angle(w.node.rotation.y, yaw, minf(delta * 7.0, 1.0))
		if not vehicle and d > 0.01 and _left_to_walk(w, pos) > 1.0:  # (not in their last metre: sidestepped round the spot they're making for, they never got there)
			var spaced := _personal_space(w, pos, to / d, delta)
			if _walk_region_clear(w, w.node.global_position, spaced):
				pos = spaced
		if not vehicle and not _walker_vehicle_clear(w, w.node.global_position, pos):
			return  # Keep the route; let a stopped car's pedestrian walk out around its body.
		# people stand on the floor, deck, step or paving under them (a facility's walk map), else
		# on the ground (or, off the ground with no walk map there, at the path's own height)
		pos.y = _surface_y(Vector2(pos.x, pos.z)) if w.data.get("vehicle", false) else _surface_y(Vector2(pos.x, pos.z), NAN if w.ground else target.y, w.node.global_position.y)
		w.node.global_position = pos
		if vehicle: _vehicle_grid.clear()
		else: _people_grid.clear()
		if w.data.get("vehicle", false) and w.data.has("half"):
			_on_wheels(w)
		if w.data.get("vehicle", false):
			pass
		elif w.path.is_empty():
			_play(w, w.rest)
			if w.data.has("arrive_yaw"):
				w.node.rotation.y = float(w.data["arrive_yaw"])  # back at the post, facing the work
				w.data.erase("arrive_yaw")
		else:
			_play(w, "walk")
		return
	if w.data.has("watch") and not w.riding:
		var look: Vector2 = w.data["watch"]
		var at := Vector2(look.x - w.node.global_position.x, look.y - w.node.global_position.z)
		if at.length() > 0.3:
			w.node.rotation.y = lerp_angle(w.node.rotation.y, atan2(-at.x, -at.y), minf(delta * 4.0, 1.0))
	if w.wait > 0.0:
		w.wait -= delta
		return
	if w.think.is_valid():
		w.think.call(w)


## The ground at world XZ `p` as it's drawn (the terrain's grid, bunkers and water dug in).
func _ground_y(p: Vector2) -> float:
	return course.drawn_height_at(p)


## A cart sat square on the ground under its four wheels: as high as they are, tipped nose up or
## down and over to a side as the ground under them is.
func _on_wheels(c: Walker) -> void:
	var yaw := c.node.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var at := c.node.global_position
	var h := []
	for wheel: Vector2 in WHEELS:
		var q := at + fwd * wheel.y + right * wheel.x
		h.append(_surface_y(Vector2(q.x, q.z)))
	# front left, front right, back left, back right
	var front := (float(h[0]) + float(h[1])) * 0.5
	var back := (float(h[2]) + float(h[3])) * 0.5
	var left := (float(h[0]) + float(h[2])) * 0.5
	var right_h := (float(h[1]) + float(h[3])) * 0.5
	c.node.rotation = Vector3(atan2(front - back, WHEELS[0].y - WHEELS[2].y), yaw, atan2(right_h - left, WHEELS[1].x - WHEELS[0].x))
	c.node.global_position.y = (front + back) * 0.5


## How high someone stands at world XZ `p`: on a facility's floor, deck, step or paving where its
## walk map has one, else on the course's ground. With `bare` (the height they're walking at) --
## or, walking the ground, `now` (where they stand) -- a storey or more below the walk map's
## floor, they're on the floor under it: at `bare` (on the ground).
func _surface_y(p: Vector2, bare: float = NAN, now: float = NAN) -> float:
	# (`bare`, a route's own height where there's no walk map -- an upper floor -- is never below the
	# ground as it's drawn: a route laid at 0 out onto a course that rises there walks on the grass;
	# a walk map has one floor, the top one: the range's lounge over its bays below)
	var y := _ground_y(p) if is_nan(bare) else maxf(bare, _ground_y(p))
	if facilities == null:
		return y
	for f in facilities.get_children():
		var fac := f as Node3D
		var rig := FacilityBuilder.rig(fac)
		if rig.is_empty():
			continue
		var local := fac.global_transform.affine_inverse() * Vector3(p.x, fac.global_position.y, p.y)
		var half := FacilityBuilder.footprint(str(rig["type"])) * 0.5
		if absf(local.x) > half.x or absf(local.z) > half.y:
			continue
		# Range routes explicitly identify the ground, upper floor or stair tread.
		# Never lift a pedestrian onto a bench/fence from the top-surface map. Off its slab
		# (its grass), a ground-floor route's on the ground, not at the slab's height: where the
		# land falls away from the range's level pad they'd walk on air.
		if rig["type"] == "driving_range" and not is_nan(bare):
			if is_nan(FacilityBuilder.walk_height(fac, Vector2(local.x, local.z))) and bare - fac.global_position.y < 2.0:
				return _ground_y(p)
			return y
		var h := FacilityBuilder.walk_height(fac, Vector2(local.x, local.z))
		if not is_nan(h):
			var at := bare if not is_nan(bare) else now
			if not is_nan(at) and fac.global_position.y + h - at > 1.5:
				return y  # under that floor
			return maxf(_ground_y(p), fac.global_position.y + h)
	# off every plot a route laid at a facility's floor (out over its apron) walks on the ground,
	# however far the land falls away from the floor (nothing up a storey is out here)
	return _ground_y(p)


func _face(w: Walker, yaw: float) -> void:
	w.node.rotation.y = yaw


func _walk_to(w: Walker, p: Vector3) -> void:
	w.path = [p]


## Send `w` across the course to `to` round water, woods and buildings.
func _go(w: Walker, to: Vector2) -> void:
	w.data.erase("indoor_target")
	w.data.erase("watch")
	w.data["outdoor_target"] = to
	w.data.erase("walk_region")
	if _rack_access_route(w, to): return
	var from := Vector2(w.node.global_position.x, w.node.global_position.z)
	var vehicle: bool = w.data.get("vehicle", false)
	var end := Vector3(to.x, 0.0, to.y)
	var lead: Array = []  # a cart backing out of the barn's row, or along the line to its head, first
	if vehicle and w.data.has("lead_out"):
		lead = w.data["lead_out"]
		w.data["reverse"] = int(w.data.get("lead_reverse", 0))
		w.data.erase("lead_out")
		w.data.erase("lead_reverse")
		var last: Vector3 = lead[lead.size() - 1]
		from = Vector2(last.x, last.z)
	var foot_path: Array = _grounds_path(from, to, bool(w.data.get("shortest_walk", false))) if not vehicle else []
	if not foot_path.is_empty():
		w.path = foot_path
		w.data["walk_region"] = {"nav": _grounds_nav, "xf": Transform3D.IDENTITY}
	elif not vehicle and w.data.get("role", "") == "cart_attendant" and not _grounds_nav.is_empty() and (_grounds_nav["rect"] as Rect2).has_point(from) and (_grounds_nav["rect"] as Rect2).has_point(to):
		w.path = []  # Retry the detailed route; the coarse course grid cannot resolve barn walls.
		w.data["walk_region"] = {"nav": _grounds_nav, "xf": Transform3D.IDENTITY}
	elif not vehicle and from.distance_to(to) < 12.0 and _open_line(_nav, w.node.global_position, end):
		w.path = [end]  # a few steps over open ground: straight there
	else:
		var route := _route(from, to, vehicle)
		if route.is_empty():
			route = _via_yards(from, to, vehicle)  # onto or off a facility's grounds
		if not vehicle and route.size() > 1 and _open_line(_nav, w.node.global_position, route[1]):
			route.remove_at(0)  # its first point is the middle of the square they're in: no step back to it
		w.path = _lanes(w, route)
	if not lead.is_empty():
		w.path = lead + w.path
	if not vehicle and not w.data.has("walk_region"):
		w.path = _round_vehicles(w.node.global_position, w.path)
	w.data["blocked"] = w.path.is_empty() and Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(to) > 2.0


func _walk_region_clear(w: Walker, a: Vector3, b: Vector3) -> bool:
	if not w.data.has("walk_region"):
		return _open_line(_nav, a, b) and _walker_vehicle_clear(w, a, b)
	var region: Dictionary = w.data["walk_region"]
	var inv: Transform3D = (region["xf"] as Transform3D).affine_inverse()
	var start := inv*a
	var end := inv*b
	var nav: Dictionary = region["nav"]
	var grid: AStarGrid2D = nav["astar"]
	var n := maxi(1, ceili(start.distance_to(end)/(.2)))
	for i in range(n+1):
		var q := start.lerp(end, float(i)/n)
		var cell := Vector2i(floori((q.x-grid.offset.x)/grid.cell_size.x+.5), floori((q.z-grid.offset.y)/grid.cell_size.y+.5))
		if not grid.region.has_point(cell) or grid.is_point_solid(cell):return false
	return _walker_vehicle_clear(w, a, b)


func _build_grounds_nav() -> void:
	if facilities == null:return
	var parts: Array = []
	var blockers: Array = []
	var rect := Rect2()
	var first := true
	for fac: Node3D in facilities.get_children():
		var rig := FacilityBuilder.rig(fac)
		if rig.is_empty():continue
		var half := FacilityBuilder.footprint(str(rig["type"]))* .5
		for x in [-half.x,half.x]:
			for z in [-half.y,half.y]:
				var q: Vector3 = fac.global_transform*Vector3(x,0,z)
				if first:rect=Rect2(Vector2(q.x,q.z),Vector2.ONE*.01);first=false
				else:rect=rect.expand(Vector2(q.x,q.z))
		for group in ["BASE","WALLS_HIGH"]:
			for node in rig["groups"].get(group,[]):
				var part := node as MeshInstance3D  # an empty group is a bare node
				if part == null:continue
				var proxy := MeshInstance3D.new();proxy.mesh=part.mesh
				proxy.transform=fac.global_transform*part.transform
				proxy.position.y-=fac.global_position.y
				parts.append(proxy)
		for block: Vector3 in rig["blockers"].get("",[]):
			var stored_cart := false
			if rig["type"] == "cart_barn":
				for entry: Dictionary in rig.get("barn_carts", []):
					var at: Vector3 = (entry["xf"] as Transform3D).origin
					if Vector2(block.x, block.y).distance_to(Vector2(at.x, at.z)) < 0.05:
						stored_cart = true
				for pickup: Transform3D in rig.get("cart_pick", []):
					if Vector2(block.x, block.y).distance_to(Vector2(pickup.origin.x, pickup.origin.z)) < 0.05:
						stored_cart = true
			if stored_cart: continue  # Use each visible cart's actual body bounds below.
			var q: Vector3 = fac.global_transform*Vector3(block.x,0,block.y)
			blockers.append(Vector3(q.x,q.z,block.z))
	if first:return
	_grounds_nav=FacilityBuilder._nav_grid(rect.grow(7),0.0,parts,.25,blockers,.85,2.1)
	for part: MeshInstance3D in parts:part.free()
	var grid: AStarGrid2D=_grounds_nav["astar"]
	_off_cart_path(grid)
	var lot := _fac("parking_lot")
	if lot != null:
		FacilityBuilder.prefer_lot_edges(_grounds_nav, FacilityBuilder.rig(lot), lot.global_transform)
	var layers:=course.layer_a()
	var field:=_range_field(INF)
	for z in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var cell:=Vector2i(x,z)
			var surface:=course.surface_nearest(grid.get_point_position(cell),layers)
			if surface in [PaintedCourse.Surface.WATER,PaintedCourse.Surface.WOODS]:grid.set_point_solid(cell)
			if field.call(grid.get_point_position(cell)):grid.set_point_solid(cell)  # (round the range's ends, not across its front)
			# This is the outdoor approach grid. Enter the house through its
			# front threshold in the guest phase, rather than cutting through
			# indoor rooms as a shortcut across the grounds. (The valet's stand
			# is outdoors, under the porte-cochere, the front step in it.)
			var world:=grid.get_point_position(cell)
			var house:=_fac("clubhouse")
			if house!=null:
				var local:=house.global_transform.affine_inverse()*Vector3(world.x,0,world.y)
				var boxes: Dictionary=FacilityBuilder.rig(house)["boxes"]
				for id in boxes:
					if id!="valet" and (boxes[id]["rect"] as Rect2).grow(.15).has_point(Vector2(local.x,local.z)):grid.set_point_solid(cell);break


## The clubhouse's cart path (CART_PATHS, rounded as it's paved) in the world, along its middle
## (XZ points); empty without one.
func _cart_path_line() -> Array:
	var house := _fac("clubhouse")
	if house == null:
		return []
	var level := clampi(int(FacilityBuilder.rig(house).get("level", 1)), 1, 4)
	if not CART_PATHS.has(level):
		return []
	var out: Array = []
	for q: Vector2 in _round_corners(CART_PATHS[level], float(CART_PATH_TURN[level])):
		var w := house.global_transform * Vector3(q.x, 0.0, q.y)
		out.append(Vector2(w.x, w.z))
	return out


## Walking grid `grid` costlier along the clubhouse's cart path (its 2.4 m and a little more): the
## club's people walk round it, not down it (user), crossing it where they must.
func _off_cart_path(grid: AStarGrid2D) -> void:
	var line := _cart_path_line()
	var reach := 1.6
	for i in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var n := maxi(int(ceil(a.distance_to(b) / (grid.cell_size.x * 0.5))), 1)
		for j in range(n + 1):
			var p := a.lerp(b, float(j) / n)
			var lo := Vector2i(floori((p.x - reach - grid.offset.x) / grid.cell_size.x + 0.5), floori((p.y - reach - grid.offset.y) / grid.cell_size.y + 0.5))
			var hi := Vector2i(floori((p.x + reach - grid.offset.x) / grid.cell_size.x + 0.5), floori((p.y + reach - grid.offset.y) / grid.cell_size.y + 0.5))
			for z in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var c := Vector2i(x, z)
					if grid.region.has_point(c) and not grid.is_point_solid(c) and grid.get_point_position(c).distance_to(p) <= reach:
						grid.set_point_weight_scale(c, maxf(grid.get_point_weight_scale(c), CART_PATH_COST))


## A test of whether a world XZ point is out on the driving range's field in front of its bays
## (`depth` metres out, across their breadth and a little more), where nobody walks. Always false
## without a range.
func _range_field(depth: float) -> Callable:
	var fac := _fac("driving_range")
	var line := FacilityBuilder.range_line(FacilityBuilder.rig(fac)) if fac != null else INF
	if line == INF:
		return func(_p: Vector2) -> bool: return false
	var inv := fac.global_transform.affine_inverse()
	var half := FacilityBuilder.footprint("driving_range").x * 0.5 + 3.0
	return func(p: Vector2) -> bool:
		var l := inv * Vector3(p.x, 0.0, p.y)
		return l.z < line and l.z > line - depth and absf(l.x) < half


func _grounds_path(from: Vector2, to: Vector2, shortest: bool = false) -> Array:
	if facilities == null:return []
	if _grounds_nav.is_empty():_build_grounds_nav()
	if _grounds_nav.is_empty() or not (_grounds_nav["rect"] as Rect2).has_point(from) or not (_grounds_nav["rect"] as Rect2).has_point(to):return []
	var grid: AStarGrid2D=_grounds_nav["astar"]
	var a:=FacilityBuilder._nav_cell(_grounds_nav,from)
	var b:=FacilityBuilder._nav_cell(_grounds_nav,to)
	if a.x<0 or b.x<0:return []
	# Include actual parked cars and vehicles stopped for pedestrians.
	# Empty stalls remain available for walking and sidestepping.
	var blocked: Array[Vector2i]=[]
	for vehicle: Walker in _vehicles():
		if not vehicle.node.visible or not vehicle.path.is_empty() and not vehicle.data.get("pedestrian_stopped", false):continue
		var half:=_footprint(vehicle)+Vector2(.25,.25)
		var frame := _vehicle_frame(vehicle)
		var center:=frame.origin
		var inv:=frame.affine_inverse()
		var reach:=half.length()
		var first:=Vector2i(floori((center.x-reach-grid.offset.x)/grid.cell_size.x),floori((center.z-reach-grid.offset.y)/grid.cell_size.y))
		var last:=Vector2i(ceili((center.x+reach-grid.offset.x)/grid.cell_size.x),ceili((center.z+reach-grid.offset.y)/grid.cell_size.y))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var cell:=Vector2i(x,z)
				if not grid.region.has_point(cell) or grid.is_point_solid(cell):continue
				var q:=grid.get_point_position(cell)
				var local:=inv*Vector3(q.x,0,q.y)
				if absf(local.x)<half.x and absf(local.z)<half.y and cell!=a and cell!=b:
					grid.set_point_solid(cell);blocked.append(cell)
	var weights := {}
	if shortest:
		if not _grounds_nav.has("shortest_weights"):
			var stored := {}
			for z in grid.region.size.y:
				for x in grid.region.size.x:
					var cell := Vector2i(x, z)
					var weight := grid.get_point_weight_scale(cell)
					if not is_equal_approx(weight, 1.0): stored[cell] = weight
			_grounds_nav["shortest_weights"] = stored
		weights = _grounds_nav["shortest_weights"]
		for cell: Vector2i in weights:
			grid.set_point_weight_scale(cell, float((_grounds_nav.get("parking_weights", {}) as Dictionary).get(cell, 1.0)))
	var points:=grid.get_point_path(a,b)
	if not points.is_empty():
		if points.size() > 1:points[0]=from
		points=FacilityBuilder.pull_tight(_grounds_nav,FacilityBuilder._straighten(points))  # (straight across the open, round the parked carts too)
	for cell in blocked:grid.set_point_solid(cell,false)
	for cell: Vector2i in weights: grid.set_point_weight_scale(cell, weights[cell])
	if points.is_empty():return []
	var out: Array=[]
	for q in points:out.append(Vector3(q.x,0,q.y))
	# Last metre remains on the detailed grid, rather than cutting an obstacle
	# to reach an arbitrary point that was snapped onto the floor.
	return out


## Each person walks their own way: a pace and a lane either side of a route of their own (a
## cart keeps a lane too), so a flight never marches in step down one track -- golfers and their
## carts all the quicker for the marshals keeping play moving (_marshal_pace).
func _pace(w: Walker) -> float:
	if not w.data.has("pace"):
		# carts and cars too: a flight's carts never drive (and turn) in step
		w.data["pace"] = _rng.randf_range(0.92, 1.06) if w.data.get("vehicle", false) else _rng.randf_range(0.9, 1.1)
		w.data["lane"] = _rng.randf_range(-1.0, 1.0)
	return float(w.data["pace"]) * float(w.data.get("hurry", 1.0))


## How much quicker golfers walk and drive with marshals hired: a tenth for each.
func _marshal_pace() -> float:
	return 1.0 + 0.1 * int(business.staff.get("marshal", 0)) if business != null else 1.0


## The route a little to one side of its line, by the walker's lane (people about a metre,
## carts a couple), wherever that side is open ground; its ends stay where they are.
func _lanes(w: Walker, path: Array) -> Array:
	if path.size() < 3:
		return path
	_pace(w)
	var vehicle: bool = w.data.get("vehicle", false)
	var grid := _cart_nav if vehicle else _nav
	var lane := float(w.data["lane"]) * (2.4 if vehicle else 1.0)
	var out: Array = [path[0]]
	for i in range(1, path.size() - 1):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i + 1]
		var d := Vector2(b.x - a.x, b.z - a.z)
		var q: Vector3 = path[i]
		if d.length_squared() > 0.0001:
			d = d.normalized()
			q = (path[i] as Vector3) + Vector3(d.y, 0, -d.x) * lane
			var a2 := Vector2((out[out.size() - 1] as Vector3).x, (out[out.size() - 1] as Vector3).z)
			var q2 := Vector2(q.x, q.z)
			var n2 := Vector2((path[i + 1] as Vector3).x, (path[i + 1] as Vector3).z)
			if not _clear_course(grid, a2, q2, 0.8 if vehicle else 0.0) or not _clear_course(grid, q2, n2, 0.8 if vehicle else 0.0):
				q = path[i]
		out.append(q)
	out.append(path[path.size() - 1])
	return out


## Whether the straight way from `a` to `b` stays on open cells of `grid` (sampled every metre).
func _open_line(grid: AStarGrid2D, a: Vector3, b: Vector3) -> bool:
	if grid == null:
		return false
	var n := maxi(int(Vector2(b.x - a.x, b.z - a.z).length()), 1)
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		var c := _nav_cell_raw(Vector2(p.x, p.z))
		if not grid.region.has_point(c) or grid.is_point_solid(c):
			return false
	return true


## The facility with grounds of its own to cross (a yard grid) whose plot `p` (world XZ) is on,
## or within the 2 m round it that the course's grid keeps clear; null if none.
func _yard_at(p: Vector2) -> Node3D:
	if business == null or facilities == null:
		return null
	for t in business.placements:
		var fac := _fac(str(t))
		if fac == null or not FacilityBuilder.nav_has(fac, ""):
			continue
		var pl: Dictionary = business.placements[t]
		if FacilityBuilder.contains(str(t), pl["pos"], float(pl["rot"]), p, 2.0):
			return fac
	return null


## `from` to `to` (world XZ) when an end is on a facility's grounds (solid on the course's grid)
## or just off the grid: across the grounds on the facility's own yard grid -- round its
## buildings, hedges and parked carts -- to the edge nearest the other end, and the course's
## grid between. Empty when there's no way.
func _via_yards(from: Vector2, to: Vector2, vehicle: bool) -> Array:
	var a := _yard_at(from)
	var b := _yard_at(to)
	if a != null and a == b:
		return _yard_leg(a, from, to, vehicle)
	var out: Array = []
	var start := from
	var end := to
	var tail: Array = []
	if a != null:
		var gate := _yard_gate(a, from, to, vehicle)
		if gate.is_empty():
			return []
		out.append_array(_yard_leg(a, from, gate[0], vehicle))
		start = gate[1]
		out.append(Vector3(start.x, 0.0, start.y))
	if b != null:
		var gate := _yard_gate(b, to, start, vehicle)
		if gate.is_empty():
			return []
		end = gate[1]
		tail.append(Vector3((gate[0] as Vector2).x, 0.0, (gate[0] as Vector2).y))
		tail.append_array(_yard_leg(b, gate[0], to, vehicle))
	var mid := _course_leg(start, end, vehicle)
	if mid.is_empty() and start.distance_to(end) > 0.5:
		return []
	out.append_array(mid)
	out.append_array(tail)
	return out


## Across facility `fac`'s grounds from `a` to `b` (world XZ), on its yard grid.
func _yard_leg(fac: Node3D, a: Vector2, b: Vector2, vehicle: bool = false) -> Array:
	var inv := fac.global_transform.affine_inverse()
	var la := inv * Vector3(a.x, 0.0, a.y)
	var lb := inv * Vector3(b.x, 0.0, b.y)
	var key := "pedestrian" if not vehicle and FacilityBuilder.rig(fac).get("type", "") == "parking_lot" else ""
	var pts := FacilityBuilder.nav_route(fac, key, Vector2(la.x, la.z), Vector2(lb.x, lb.z))
	var out: Array = []
	for i in range(1, pts.size()):
		out.append(fac.global_transform * Vector3(pts[i].x, 0.0, pts[i].y))
	out.append(Vector3(b.x, 0.0, b.y))
	return out


## Where the way between `inside` (on facility `fac`'s grounds) and `beyond` crosses the edge of
## them: [the walkable spot at the yard grid's edge that's reachable from `inside` and nearest
## `beyond`, the open ground on the course's grid just outside it] (world XZ); empty if none.
func _yard_gate(fac: Node3D, inside: Vector2, beyond: Vector2, vehicle: bool) -> Array:
	var inv := fac.global_transform.affine_inverse()
	var li := inv * Vector3(inside.x, 0.0, inside.y)
	var lb := inv * Vector3(beyond.x, 0.0, beyond.y)
	var edge := FacilityBuilder.nav_exit(fac, "", Vector2(li.x, li.z), Vector2(lb.x, lb.z))
	if edge == Vector2.INF:
		return []
	var half := FacilityBuilder.footprint(str(FacilityBuilder.rig(fac)["type"])) * 0.5
	var out := edge  # straight out from the side it's on
	if half.x - absf(edge.x) < half.y - absf(edge.y):
		out.x = signf(edge.x) * (half.x + 4.5)
	else:
		out.y = signf(edge.y) * (half.y + 4.5)
	var w_edge := fac.global_transform * Vector3(edge.x, 0.0, edge.y)
	var w_out := fac.global_transform * Vector3(out.x, 0.0, out.y)
	var open := _safe_point(Vector2(w_out.x, w_out.z), vehicle)
	if open == Vector2.INF:
		return []
	return [Vector2(w_edge.x, w_edge.z), open]


## A route on the course's grid from `a` to `b`, from (or to) the nearest open ground when an end
## is just inside a kept-clear cell (by a building, say).
func _course_leg(a: Vector2, b: Vector2, vehicle: bool) -> Array:
	var route := _route(a, b, vehicle)
	if not route.is_empty():
		return route
	var grid := _cart_nav if vehicle else _nav
	if grid == null:
		return []
	var sa := _safe_point(a, vehicle) if grid.is_point_solid(_nav_cell_raw(a)) else a
	var sb := _safe_point(b, vehicle) if grid.is_point_solid(_nav_cell_raw(b)) else b
	if sa == Vector2.INF or sb == Vector2.INF:
		return []
	route = _route(sa, sb, vehicle)
	if not route.is_empty() and sb != b:
		route.append(Vector3(b.x, 0.0, b.y))
	return route


## How far `w` still has to go along its path from `pos`.
func _left_to_walk(w: Walker, pos: Vector3) -> float:
	var left := 0.0
	var at := Vector2(pos.x, pos.z)
	for p: Vector3 in w.path:
		left += at.distance_to(Vector2(p.x, p.z))
		at = Vector2(p.x, p.z)
	return left


## A walking golfer sidesteps anyone closer than an arm's length rather than walking through
## them: a gentle step to the side of their heading `dir` (never back, so they always get there).
func _personal_space(w: Walker, pos: Vector3, dir: Vector3, delta: float) -> Vector3:
	var side := Vector3(-dir.z, 0, dir.x)
	var step := 0.0
	var dodge := Vector3.ZERO
	for g in _groups:
		for o: Walker in g.golfers:
			if o == w or o.riding or not o.node.visible:
				continue
			var rel := pos - o.node.global_position
			if absf(rel.y) > 0.8:
				continue  # People on another floor do not obstruct this walker.
			rel.y = 0.0
			var dist := rel.length()
			if dist < 0.85:
				var s := rel.dot(side)
				step += (1.0 if s >= 0.0 else -1.0) * (0.85 - dist) / 0.85
	for v: Walker in _nearby_vehicles(pos, 12.0):
		if v == w.data.get("wash_cart"):
			continue  # The attendant deliberately reaches this stationary cart.
		if not v.node.visible or absf(pos.y - v.node.global_position.y) > 1.5:
			continue
		var l := _vehicle_frame(v).affine_inverse() * pos
		var half := _footprint(v)
		var off := Vector2(maxf(absf(l.x) - half.x, 0.0), maxf(absf(l.z) - half.y, 0.0)).length()  # out from its body
		var room := 0.35 if v.path.is_empty() else 1.0  # more off one on the move
		if off < room:
			var rel := pos - v.node.global_position
			step += (1.0 if rel.dot(side) >= 0.0 else -1.0) * (room - off) / room
		# one coming their way: out of its lane ahead of it, to the side they're already on (user)
		if not v.path.is_empty() and v != w and not w.riding:
			var t: Vector3 = v.path[0]
			var vdir := Vector3(t.x - v.node.global_position.x, 0.0, t.z - v.node.global_position.z)
			if vdir.length() > 0.05:
				vdir = vdir.normalized()
				var rel := pos - v.node.global_position
				rel.y = 0.0
				var along := rel.dot(vdir)
				var vside := Vector3(-vdir.z, 0.0, vdir.x)
				var across := rel.dot(vside)
				var lane := _vehicle_lateral_extent(v, vside) + 0.9
				if along > -0.5 and along < half.y + 9.0 and absf(across) < lane:
					dodge += vside * (1.0 if across >= 0.0 else -1.0) * (lane - absf(across)) / lane
	var out := pos + side * clampf(step, -1.0, 1.0) * 0.9 * delta
	if dodge != Vector3.ZERO:
		var dodged := out + dodge.limit_length(1.0) * 1.3 * delta
		if _field_test.is_null() or not _field_test.call(Vector2(dodged.x, dodged.z)):
			out = dodged  # (never out onto the range's field in front of its bays)
	return _vehicle_space(w, out, delta)


## A soft exclusion around vehicle bodies, for walkers and people waiting nearby.
func _vehicle_space(w: Walker, pos: Vector3, delta: float) -> Vector3:
	if w.riding or w.data.has("cart_move") or w.data.get("seated", false): return pos
	var out := pos
	for v: Walker in _nearby_vehicles(pos, 1.0):
		if not v.node.visible or v == w.data.get("wash_cart") or absf(pos.y - v.node.global_position.y) > 1.2: continue
		var xf := _vehicle_frame(v)
		var p := xf.affine_inverse() * out
		var half := _footprint(v)
		var closest := Vector3(clampf(p.x, -half.x, half.x), p.y, clampf(p.z, -half.y, half.y))
		var away := p - closest
		var distance := away.length()
		var room := 0.38 if v.path.is_empty() else 0.7
		if distance >= room: continue
		if distance < 0.001:
			away = Vector3(1 if p.x >= 0 else -1, 0, 0) if half.x - absf(p.x) < half.y - absf(p.z) else Vector3(0, 0, 1 if p.z >= 0 else -1)
		var push := (xf.basis * away.normalized()).normalized() * minf(room - distance, 1.4 * delta)
		var candidate := out + push
		if _walk_region_clear(w, out, candidate): out = candidate
	return out


## How much of their stride walker `w` takes heading `dir`: less, down to none, on the heels of a
## golfer just in front going on ahead of them (or coming the other way: of two head on, the
## later-made one gives way, and both step aside, _personal_space), rather than walking into
## them -- 1 with nobody there. Never for ever: held up a few seconds, they go on regardless a
## while (people stood still are stepped round, not waited for).
func _give_way(w: Walker, dir: Vector3, delta: float) -> float:
	var held := float(w.data.get("held", 0.0))
	if held < 0.0:
		w.data["held"] = minf(held + delta, 0.0)
		return 1.0
	var p := w.node.global_position
	var least := 1.0
	for g in _groups:
		for o: Walker in g.golfers:
			if o == w or o.riding or not o.node.visible or o.path.is_empty():
				continue
			var rel := o.node.global_position - p
			if absf(rel.y) > 0.8:
				continue  # People on another floor do not obstruct this walker.
			rel.y = 0.0
			var dist := rel.length()
			if dist < 0.01 or dist > 0.9 or rel.dot(dir) / dist < 0.5:
				continue
			var t: Vector3 = o.path[0]
			var odir := Vector3(t.x - o.node.global_position.x, 0, t.z - o.node.global_position.z)
			if odir.length() > 0.01 and odir.normalized().dot(-rel / dist) > 0.5 and w.node.get_instance_id() < o.node.get_instance_id():
				continue  # head on: the other one gives way
			least = minf(least, clampf((dist - 0.5) / 0.4, 0.0, 1.0))
	if least >= 1.0:
		w.data["held"] = 0.0
	else:
		w.data["held"] = held + delta * (1.0 - least)
		if float(w.data["held"]) > 3.0:
			w.data["held"] = -1.5
	return least


## Golfers of flight `g` stood on (or come to a stop in) someone else ease apart a little at a
## time rather than standing in each other: each one stood still steps back off any other stood
## nearer than a shoulder's width (those walking by sidestep them: _personal_space) -- never
## someone sat down, riding or mid-swing (nor the one in their stance to play: the other steps
## off), and never off the floor or ground they walk.
func _ease_apart(g: Group, delta: float) -> void:
	var playing: Walker = g.golfers[g.turn] if g.phase in ["ready", "step_up", "play"] and g.turn < g.golfers.size() else null
	for w: Walker in g.golfers:
		if w == playing or w.riding or not w.node.visible or not w.path.is_empty() or w.data.get("seated", false):
			continue
		if w.anim != null and w.anim.current_animation in IMPACTS:
			continue
		var pos := w.node.global_position
		var push := Vector3.ZERO
		for other: Group in _groups:
			for o: Walker in other.golfers:
				if o == w or o.riding or not o.node.visible or not o.path.is_empty():
					continue
				var rel := pos - o.node.global_position
				if absf(rel.y) > 0.8:
					continue  # People on another floor do not obstruct this walker.
				rel.y = 0.0
				var dist := rel.length()
				if dist >= 0.6:
					continue
				if dist < 0.01:
					if w.node.get_instance_id() < o.node.get_instance_id():
						continue  # right on top of each other: the other steps off
					rel = Vector3.RIGHT.rotated(Vector3.UP, float(w.node.get_instance_id() % 628) * 0.01)
					dist = 0.01
				push += rel / dist * (0.6 - dist) / 0.6
		if push.length() < 0.001:
			continue
		var to := pos + push.normalized() * minf(push.length(), 1.0) * 0.8 * delta
		if not _walk_region_clear(w, pos, to):
			continue
		to.y = _surface_y(Vector2(to.x, to.z), NAN if w.ground else pos.y)
		w.node.global_position = to


## `path` walked from `from`, round any parked cart or car one of its legs would cross: past
## that vehicle's nose or tail and along its side, whichever way round is shorter.
func _round_vehicles(from: Vector3, path: Array) -> Array:
	var parked: Array = []
	for v: Walker in _vehicles():
		if v.node.visible and (v.path.is_empty() or v.data.get("pedestrian_stopped", false)):
			parked.append(v)
	if parked.is_empty() or path.is_empty():
		return path
	var out: Array = []
	var at := from
	for j in range(path.size()):
		var p: Vector3 = path[j]
		if j < path.size() - 1 and _in_vehicle(parked, p):
			continue  # a corner of the route where a cart's parked: by-passed
		for _i in range(4):  # round each in its way, the nearest first
			var way := _past_vehicle(parked, at, p)
			if way.is_empty():
				break
			out.append_array(way)
			at = way[way.size() - 1]
		out.append(p)
		at = p
	return out


## Whether `p` is on (or within a stride of) the body of any of the `parked` vehicles.
func _in_vehicle(parked: Array, p: Vector3) -> bool:
	for v: Walker in parked:
		var l := _vehicle_frame(v).affine_inverse() * p
		var half := _footprint(v) + Vector2(0.3, 0.3)
		if absf(l.x) < half.x and absf(l.z) < half.y:
			return true
	return false


## The corners to walk by to get from `a` to `b` past the first of the `parked` vehicles the
## straight way would cross (none when it's clear).
func _past_vehicle(parked: Array, a: Vector3, b: Vector3) -> Array:
	var first: Walker = null
	var first_t := INF
	for v: Walker in parked:
		var inv := _vehicle_frame(v).affine_inverse()
		var la := inv * a
		var lb := inv * b
		var t := _seg_box(Vector2(la.x, la.z), Vector2(lb.x, lb.z), _footprint(v) + Vector2(0.3, 0.3))
		if t < first_t:
			first_t = t
			first = v
	if first == null:
		return []
	var xf := _vehicle_frame(first)
	var la := xf.affine_inverse() * a
	var lb := xf.affine_inverse() * b
	var out: Array = []
	for c: Vector2 in _round_box(Vector2(la.x, la.z), Vector2(lb.x, lb.z), _footprint(first)):
		out.append(xf * Vector3(c.x, 0.0, c.y))
	return out


## The shortest way from `p` to `q` round a box `half` either side of the origin (the corners of
## it, stood off by 0.8 m, in order); empty when either end is inside it.
static func _round_box(p: Vector2, q: Vector2, half: Vector2) -> Array:
	var c := half + Vector2(0.8, 0.8)
	var wall := half + Vector2(0.3, 0.3)
	var pts: Array[Vector2] = [p, q, Vector2(c.x, c.y), Vector2(-c.x, c.y), Vector2(-c.x, -c.y), Vector2(c.x, -c.y)]
	var dist: Array[float] = [0.0, INF, INF, INF, INF, INF]
	var prev: Array[int] = [-1, -1, -1, -1, -1, -1]
	var done: Array[bool] = [false, false, false, false, false, false]
	for _n in range(pts.size()):
		var u := -1
		for i in range(pts.size()):
			if not done[i] and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or u == 1:
			break
		done[u] = true
		for v in range(pts.size()):
			if not done[v] and _seg_box(pts[u], pts[v], wall) == INF:
				var d := dist[u] + pts[u].distance_to(pts[v])
				if d < dist[v]:
					dist[v] = d
					prev[v] = u
	var way: Array = []
	var i := prev[1]
	while i >= 2:
		way.push_front(pts[i])
		i = prev[i]
	return way


## Where along `p` -> `q` (0..1) the segment first meets the box `half` either side of the
## origin; INF if it misses.
static func _seg_box(p: Vector2, q: Vector2, half: Vector2) -> float:
	var d := q - p
	var t0 := 0.0
	var t1 := 1.0
	for axis in range(2):
		var lo := -half[axis] - p[axis]
		var hi := half[axis] - p[axis]
		if absf(d[axis]) < 0.000001:
			if lo > 0.0 or hi < 0.0:
				return INF
			continue
		var ta := lo / d[axis]
		var tb := hi / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return INF
	return t0


## Half the breadth and length of vehicle `v`'s body in its own frame (X across, Z along): a
## cart's is known, anything else's is worked out once from its meshes (not its riders').
func _footprint(v: Walker) -> Vector2:
	if not v.data.has("half"):
		var inv := v.node.global_transform.affine_inverse()
		var box := AABB()
		var any := false
		for m in v.node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.skin != null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var parent := mi.get_parent()
			var rider := false
			while parent != null and parent != v.node:
				if parent.is_in_group("club_people"): rider = true; break
				parent = parent.get_parent()
			if rider: continue
			var b := (inv * mi.global_transform) * mi.get_aabb()
			box = box.merge(b) if any else b
			any = true
		v.data["half"] = Vector2(box.size.x, box.size.z) * 0.5 if any else Vector2(1.0, 2.3)
		v.data["body_center"] = Vector3(box.get_center().x, 0, box.get_center().z) if any else Vector3.ZERO
	return v.data["half"]


## Preserve an off-center model's real body rectangle, independent of its root pivot.
func _vehicle_frame(v: Walker) -> Transform3D:
	_footprint(v)
	return v.node.global_transform * Transform3D(Basis.IDENTITY, v.data.get("body_center", Vector3.ZERO))


func _vehicle_lateral_extent(v: Walker, side: Vector3) -> float:
	var frame := _vehicle_frame(v)
	var half := _footprint(v)
	return absf(side.dot(frame.basis.x)) * half.x + absf(side.dot(frame.basis.z)) * half.y


func _pedestrians() -> Array:
	if _traffic_cache_active and not _traffic_people.is_empty(): return _traffic_people
	var out: Array = []
	for g: Group in _groups: out.append_array(g.golfers)
	for p: Walker in _staff:
		if not p.data.get("vehicle", false): out.append(p)
	if _traffic_cache_active: _traffic_people = out
	return out


## Test the entire movement and rotation, including reversing and a person already touching
## any side. A stopped vehicle never resumes until its proposed movement is clear.
func _vehicle_people_clear(v: Walker, start: Transform3D, end: Transform3D, clearance: float = 0.45) -> bool:
	var half := _footprint(v) + Vector2.ONE * clearance
	var center: Vector3 = v.data.get("body_center", Vector3.ZERO)
	var turn := start.basis.orthonormalized().get_rotation_quaternion().angle_to(end.basis.orthonormalized().get_rotation_quaternion())
	var samples := maxi(1, maxi(ceili(start.origin.distance_to(end.origin) / 0.15), ceili(turn / 0.06)))
	var frames: Array[Transform3D] = []
	for i in range(samples + 1):
		frames.append((start.interpolate_with(end, float(i) / samples) * Transform3D(Basis.IDENTITY, center)).affine_inverse())
	var reach := (half + Vector2(absf(center.x), absf(center.z))).length() + start.origin.distance_to(end.origin)
	for p: Walker in _nearby_people(start.origin, reach):
		if not is_instance_valid(p.node) or not p.node.is_visible_in_tree(): continue
		var climbing: Dictionary = p.data.get("cart_move", {})
		if p.riding and climbing.is_empty(): continue
		if climbing.get("cart") == v: continue  # Only this vehicle's own boarding rider is exempt.
		if absf(p.node.global_position.y - start.origin.y) > 1.2: continue
		if Vector2(p.node.global_position.x - start.origin.x, p.node.global_position.z - start.origin.z).length_squared() > reach * reach: continue
		for inv: Transform3D in frames:
			var local := inv * p.node.global_position
			if absf(local.x) <= half.x and absf(local.z) <= half.y:
				v.data["blocker_person"] = p
				return false
	v.data.erase("blocker_person")
	return true


## Continuous body clearance for walkers. An existing overlap may only decrease, so a
## pedestrian can escape a touching car without stepping through it or through another car.
func _walker_vehicle_clear(w: Walker, start: Vector3, end: Vector3) -> bool:
	if w.riding or w.data.has("cart_move") or w.data.get("seated", false): return true
	for v: Walker in _nearby_vehicles(start, start.distance_to(end) + 0.3):
		if not v.node.is_visible_in_tree() or absf(start.y - v.node.global_position.y) > 1.2: continue
		var reach := _footprint(v).length() + 0.3 + start.distance_to(end)
		if Vector2(start.x - _vehicle_frame(v).origin.x, start.z - _vehicle_frame(v).origin.z).length_squared() > reach * reach: continue
		var inv := _vehicle_frame(v).affine_inverse()
		var a3 := inv * start
		var b3 := inv * end
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var half := _footprint(v) + Vector2(0.18, 0.18)
		var depth := minf(half.x - absf(a.x), half.y - absf(a.y))
		if depth <= 0.0:
			if _seg_box(a, b, half - Vector2.ONE * 0.001) != INF: return false
		else:
			var samples := maxi(1, ceili(a.distance_to(b) / 0.1))
			for i in range(1, samples + 1):
				var p := a.lerp(b, float(i) / samples)
				var next_depth := minf(half.x - absf(p.x), half.y - absf(p.y))
				if next_depth > depth + 0.001: return false
				depth = next_depth
	return true


## Match collision proxies to the visible ambient parking cars, including their rotation.
func _parked_lot_cars(lot: Node3D) -> Array:
	var rig := FacilityBuilder.rig(lot)
	var batches: Array = []
	var signature: Array = []
	for node in lot.get_children():
		if node is MultiMeshInstance3D and String(node.name).begins_with("Batch_parked_") and node.is_visible_in_tree():
			batches.append(node)
			signature.append(node.get_instance_id())
	if rig.get("parking_collision_signature", []) != signature:
		for old: Walker in rig.get("parking_collision_cars", []):
			if is_instance_valid(old.node): old.node.queue_free()
		var cars: Array = []
		for batch: MultiMeshInstance3D in batches:
			var box := batch.multimesh.mesh.get_aabb()
			for i in range(batch.multimesh.instance_count):
				var car := Walker.new()
				car.node = Node3D.new()
				car.node.name = "ParkedCarClearance"
				lot.add_child(car.node)
				car.node.transform = batch.transform * batch.multimesh.get_instance_transform(i)
				car.data = {"vehicle": true, "half": Vector2(box.size.x, box.size.z) * 0.5, "body_center": Vector3(box.get_center().x, 0, box.get_center().z)}
				cars.append(car)
		rig["parking_collision_cars"] = cars
		rig["parking_collision_signature"] = signature
	return rig.get("parking_collision_cars", [])


## Every cart and car on the move about the club.
func _vehicles() -> Array:
	if _traffic_cache_active and not _traffic_vehicles.is_empty(): return _traffic_vehicles
	var out: Array = []
	for g in _groups:
		out.append_array(g.carts)
		if g.car != null:
			out.append(g.car)
	for p in _staff:
		if p.data.get("vehicle", false):
			out.append(p)
	out.append_array(_pool)
	var barn := _fac("cart_barn")
	if barn != null:
		var rig := FacilityBuilder.rig(barn)
		var parked: Array = rig.get_or_add("parked_walkers", [])
		var entries: Array = rig.get("barn_carts", [])
		if parked.size() != entries.size():
			for v: Walker in parked:
				if is_instance_valid(v.node): v.node.queue_free()
			parked.clear()
			for entry: Dictionary in entries:
				var v := Walker.new()
				v.node = Node3D.new()
				v.node.name = "ParkedCartClearance"
				barn.add_child(v.node)
				v.node.transform = (entry["xf"] as Transform3D).orthonormalized()
				v.data = {"vehicle": true, "golf_cart": true, "half": CART_HALF}
				parked.append(v)
		for i in parked.size():
			if not _barn_out.has(i): out.append(parked[i])
	var lot := _fac("parking_lot")
	if lot != null: out.append_array(_parked_lot_cars(lot))
	if _traffic_cache_active: _traffic_vehicles = out
	return out


## Someone on foot just in front of vehicle `v` heading `dir`: in its way (across its width and a
## little more), from its nose out to a few metres on -- a car further than a cart.
func _person_ahead(v: Walker, dir: Vector3) -> bool:
	var end := v.node.global_transform
	end.origin += dir * 2.0
	return not _vehicle_people_clear(v, v.node.global_transform, end, 0.65 if v.data.get("pedestrian_stopped", false) else 0.45)


## A cart (or car) with another just in front of it -- closer than a gap between them (bumper to
## bumper: their lengths and a car's length's room more for a car, user: no tailgating), inside 50
## degrees of where it's heading -- waits for it rather than driving into it; of two nose to nose,
## the one made later gives way.
func _cart_ahead(v: Walker, dir: Vector3) -> bool:
	var p := v.node.global_position
	var mine := _footprint(v).y
	var gap := 1.0 if v.data.get("golf_cart", false) else 2.2
	for o: Walker in _nearby_vehicles(p, mine + gap + 2.0):
		if o == v or not o.node.visible:
			continue
		var rel := o.node.global_position - p
		rel.y = 0.0
		var dist := rel.length()
		var parking := v.data.has("barn_return_slot") and int(v.data.get("reverse", 0)) > 0 and o.path.is_empty()
		var stop_distance := mine + _footprint(o).y + 0.15 if parking else maxf(3.6, mine + _footprint(o).y + gap)
		if dist < 0.1 or dist > stop_distance or rel.dot(dir) / dist < 0.64:
			continue
		var side_gap := 0.04 if o.path.is_empty() else 0.35
		if absf(rel.cross(dir).y) > _footprint(v).x + _footprint(o).x + side_gap:
			continue
		v.data["blocker"] = o  # (who: a parked one's driven round, _round_parked)
		if not o.path.is_empty():
			var t: Vector3 = o.path[0]
			var odir := Vector3(t.x - o.node.global_position.x, 0, t.z - o.node.global_position.z)
			if odir.length() > 0.01 and odir.normalized().dot(dir) < -0.5:
				if v.node.get_instance_id() > o.node.get_instance_id():
					_cart_pull_aside(v, o, dir)
				else:
					_cart_pull_aside(o, v, odir.normalized())
		return true
	return false


## Vehicle `v` held up a while behind another that's parked (no way of its own: it'll never move
## on, user -- carts and cars stuck behind one for good): pulled up short where it stands when it's
## all but where it was going, else round it -- a way out past its side, the side it's nearer.
func _round_parked(v: Walker, dir: Vector3) -> void:
	var o: Variant = v.data.get("blocker")
	if o == null or not is_instance_valid((o as Walker).node) or not (o as Walker).path.is_empty() or v.path.is_empty():
		return
	var blocker := o as Walker
	var pos := v.node.global_position
	var last: Vector3 = v.path[v.path.size() - 1]
	var tries := int(v.data.get("round_tries", 0)) + 1
	v.data["round_tries"] = tries
	if not v.data.get("yard_maneuver", false) and Vector2(last.x - pos.x, last.z - pos.z).length() < _footprint(v).y * 2.0 + 3.0:
		v.path.clear()  # (there, near enough: the other's in the space beside)
		v.data["yield"] = 0.0
		v.data.erase("round_tries")
		return
	if tries > 3:
		return  # (round three times among them: no more turns, waits its turn as it is)
	var across := Vector3(-dir.z, 0.0, dir.x)
	var rel := blocker.node.global_position - pos
	var clear := _footprint(v).x + _footprint(blocker).x + 0.8
	var along := rel.dot(dir)
	var first := -1.0 if rel.dot(across) > 0.0 else 1.0  # (round the far side of it from us, else the near)
	for side: float in [first, -first]:
		var by := pos + dir * along + across * side * clear
		var past := by + dir * (_footprint(v).y + _footprint(blocker).y + 0.5)
		if _detour_clear(v, pos, [by, past, v.path[0]]):
			v.path.insert(0, Vector3(past.x, last.y, past.z))
			v.path.insert(0, Vector3(by.x, last.y, by.z))
			v.data["yield"] = 0.0
			v.data.erase("blocker")
			return


## Someone driving about the lot near car `car` (another vehicle on the move within a few spaces
## of it): it waits in its space for them to go by before pulling out.
func _lot_traffic(car: Walker) -> bool:
	if car == null or not is_instance_valid(car.node):
		return false
	var at := car.node.global_position
	for v: Walker in _vehicles():
		if v == car or not v.node.visible or v.path.is_empty():
			continue
		if Vector2(v.node.global_position.x - at.x, v.node.global_position.z - at.z).length() < 14.0:
			return true
	return false


## Whether vehicle `v` has room to drive from `from` through `pts` (world) on the carts' ground (no
## building, water, woods or other solid in the way, its width clear): a detour it's to take.
func _detour_clear(v: Walker, from: Vector3, pts: Array) -> bool:
	if _cart_nav == null:
		return false
	var half := _footprint(v).x + 0.2
	var a := Vector2(from.x, from.z)
	for q: Vector3 in pts:
		var b := Vector2(q.x, q.z)
		if not _clear_course(_cart_nav, a, b, half):
			return false
		a = b
	return true


## Vehicle `v` held up a while by someone on foot stood in its way: round them -- a way out past
## them on the side they're not, a body's width and a little more off them.
func _round_person(v: Walker, dir: Vector3) -> void:
	if v.path.is_empty() or float(v.data.get("rounding", 0.0)) > 0.0:
		return
	var pos := v.node.global_position
	var across := Vector3(-dir.z, 0.0, dir.x)
	var near: Walker = v.data.get("blocker_person")
	if near != null and (not is_instance_valid(near.node) or near.riding):
		near = null
	for g: Group in ([] if near != null else _groups):
		for o: Walker in g.golfers:
			if o.riding or not o.node.visible:
				continue
			var rel := o.node.global_position - pos
			if rel.dot(dir) > 0.0 and rel.dot(dir) < _footprint(v).y + 5.0 and absf(rel.dot(across)) < _footprint(v).x + 1.0:
				if near == null or rel.length() < (near.node.global_position - pos).length():
					near = o
	for o: Walker in ([] if near != null else _staff):
		if o.riding or o.data.get("vehicle", false) or not o.node.visible:
			continue
		var rel := o.node.global_position - pos
		if rel.dot(dir) > 0.0 and rel.dot(dir) < _footprint(v).y + 5.0 and absf(rel.dot(across)) < _footprint(v).x + 1.0:
			if near == null or rel.length() < (near.node.global_position - pos).length():
				near = o
	if near == null:
		return
	var rel := near.node.global_position - pos
	var clear := _footprint(v).x + 1.1
	var y: float = (v.path[0] as Vector3).y
	var first := -1.0 if rel.dot(across) > 0.0 else 1.0
	for side: float in [first, -first]:
		var by := pos + dir * rel.dot(dir) + across * side * clear
		var past := by + dir * (_footprint(v).y + 1.2)
		if _detour_clear(v, pos, [by, past, v.path[0]]):
			v.path.insert(0, Vector3(past.x, y, past.z))
			v.path.insert(0, Vector3(by.x, y, by.z))
			v.data["give_way"] = 0.0
			v.data["rounding"] = 2.0  # (s it doesn't stop for them again while it gets by)
			return


## Someone on foot meant to be walking (a way ahead of them) who's got nowhere for a second and a
## half: right, right again, left, then forward toward the original route. Each attempt must
## clear the walking region and vehicle bodies. Never someone sat, riding, climbing in or out,
## or on a machine (a treadmill's
## walking in place on purpose).
## Find a continuous escape around the whole nearby vehicle cluster. Nose/tail
## projections let someone in a narrow gap back out before turning sideways.
func _vehicle_escape_route(w: Walker, goal: Vector3) -> Array:
	var start := w.node.global_position
	var points: Array[Vector3] = [start, goal]
	var nearby := _nearby_vehicles(start, 10.0)
	for v: Walker in nearby:
		if not v.node.is_visible_in_tree() or absf(start.y - v.node.global_position.y) > 1.2: continue
		var xf := _vehicle_frame(v)
		var half := _footprint(v) + Vector2(0.65, 0.65)
		var local := xf.affine_inverse() * start
		for z: float in [-half.y, half.y]:
			for x: float in [-half.x, clampf(local.x, -half.x, half.x), half.x]:
				var at := xf * Vector3(x, 0, z)
				at.y = start.y
				points.append(at)
		if points.size() >= 74: break
	if points.size() == 2: return []
	var distance: Array = []
	var previous: Array = []
	var done: Array = []
	for i in points.size():
		distance.append(0.0 if i == 0 else INF)
		previous.append(-1)
		done.append(false)
	for iteration in points.size():
		var u := -1
		for i in points.size():
			if not done[i] and float(distance[i]) < INF and (u < 0 or float(distance[i]) < float(distance[u])): u = i
		if u < 0: return []
		if u == 1:
			var route: Array = []
			while u != 0:
				route.push_front(points[u])
				u = int(previous[u])
			return route
		done[u] = true
		for v in points.size():
			if done[v]: continue
			var cost := float(distance[u]) + points[u].distance_to(points[v])
			if cost >= float(distance[v]) or not _walk_region_clear(w, points[u], points[v]): continue
			distance[v] = cost
			previous[v] = u
	return []


func _unstick(w: Walker, delta: float) -> void:
	var keys := ["stuck_t", "stuck_stage", "stuck_best", "unstick_goal", "unstick_step", "stuck_heading", "stuck_origin"]
	if w.path.is_empty() or w.riding or w.data.get("seated", false) or w.data.has("cart_move") or w.data.get("blocked", false):
		for key in keys: w.data.erase(key)
		return
	var first: Vector3 = w.path[0]
	var goal: Vector3 = w.data.get("unstick_goal", first)
	var detour: Vector3 = w.data.get("unstick_step", goal)
	if first != goal and first != detour:
		# A new route replaces the previous recovery and its destination.
		for key in keys: w.data.erase(key)
		goal = first
	w.data["unstick_goal"] = goal
	var here := Vector2(w.node.global_position.x, w.node.global_position.z)
	var remaining := here.distance_to(Vector2(goal.x, goal.z))
	if first == goal and remaining < 0.4 and w.path.size() > 1 and _walk_region_clear(w, w.node.global_position, w.path[1]):
		# An intermediate grid corner is close enough; keep walking instead of orbiting it.
		w.path.pop_front()
		for key in keys: w.data.erase(key)
		return
	var best := float(w.data.get("stuck_best", remaining))
	if first == goal and remaining < best - 0.25:
		w.data["stuck_t"] = 0.0
		w.data["stuck_stage"] = 0
		w.data.erase("stuck_heading")
		w.data.erase("stuck_origin")
		best = remaining
	w.data["stuck_best"] = best
	if float(w.data.get("hold", 0.0)) > 0.0: return
	w.data["stuck_t"] = float(w.data.get("stuck_t", 0.0)) + delta
	if float(w.data["stuck_t"]) < 1.5 or remaining < 0.05: return
	w.data["stuck_t"] = 0.0
	var escape := _vehicle_escape_route(w, w.path.back())
	if not escape.is_empty():
		w.path = escape
		for key in keys: w.data.erase(key)
		return
	var heading: Vector2 = w.data.get("stuck_heading", (Vector2(goal.x, goal.z) - here).normalized())
	w.data["stuck_heading"] = heading
	var right := Vector2(-heading.y, heading.x)
	var origin: Vector2 = w.data.get("stuck_origin", here)
	w.data["stuck_origin"] = origin
	var stage := int(w.data.get("stuck_stage", 0))
	w.data["stuck_stage"] = (stage + 1) % 4
	if first == detour and first != goal: w.path.pop_front()
	w.data["unstick_step"] = goal
	# Each failed attempt advances once: right, right again, left, then forward.
	var direction := right if stage < 2 else (-right if stage == 2 else heading)
	var distance := 3.2 if stage == 1 else 1.6
	var at := origin + direction * (minf(distance, remaining) if stage == 3 else distance)
	var to := Vector3(at.x, w.node.global_position.y, at.y)
	if not _walk_region_clear(w, w.node.global_position, to): return
	for vehicle: Walker in _vehicles():
		if vehicle == w.data.get("wash_cart") or not vehicle.node.visible or absf(vehicle.node.global_position.y - to.y) > 1.2: continue
		var inv := _vehicle_frame(vehicle).affine_inverse()
		var start := inv * w.node.global_position
		var half := _footprint(vehicle) + Vector2(0.12, 0.12)
		var depth := maxf(0.0, minf(half.x - absf(start.x), half.y - absf(start.z)))
		for i in range(1, 9):
			var p := inv * w.node.global_position.lerp(to, i / 8.0)
			if minf(half.x - absf(p.x), half.y - absf(p.z)) > depth + 0.01: return
	if to.distance_to(goal) > 0.05:
		w.path.push_front(to)
		w.data["unstick_step"] = to


## Everyone on foot kept off the vehicles and each other (user: a magnet's like poles): anyone
## inside a vehicle's body and an arm's length round it, or standing in someone, pushed out a
## little each moment -- walking or stood still -- never someone sat, riding, climbing in or out, or
## in their stance over a ball.
func _repel(w: Walker, delta: float) -> void:
	if w.riding or w.data.get("seated", false) or w.data.has("cart_move") or not w.node.visible or w.data.has("shot_ball") and w.path.is_empty():
		return
	if not w.data.has("pedestrian_yield") and _walk_aside_for_stopped_vehicle(w): return
	var pos := w.node.global_position
	var push := Vector3.ZERO
	var own: Array = []  # (their own flight's carts and car: they walk right up to them to get in)
	for g: Group in _groups:
		if g.golfers.has(w):
			own = g.carts.duplicate()
			if g.car != null:
				own.append(g.car)
			break
	for v: Walker in _nearby_vehicles(pos, 10.0):
		if v == w.data.get("wash_cart") or (own.has(v) and v.path.is_empty()) or not v.node.visible or absf(pos.y - v.node.global_position.y) > 1.5:
			continue
		var l := _vehicle_frame(v).affine_inverse() * pos
		var half := _footprint(v) + (Vector2(0.45, 0.45) if not v.path.is_empty() else Vector2(0.12, 0.12))  # (a body's edge off a parked one)
		if not v.path.is_empty() and w.path.is_empty():
			# stood in the lane of one coming their way: aside out of it (walkers do as they go,
			# _personal_space)
			var t: Vector3 = v.path[0]
			var vdir := Vector3(t.x - v.node.global_position.x, 0.0, t.z - v.node.global_position.z)
			if vdir.length() > 0.05:
				vdir = vdir.normalized()
				var rel := pos - v.node.global_position
				rel.y = 0.0
				var vside := Vector3(-vdir.z, 0.0, vdir.x)
				var across := rel.dot(vside)
				var lane := _vehicle_lateral_extent(v, vside) + 0.8
				if rel.dot(vdir) > 0.0 and rel.dot(vdir) < _footprint(v).y + 6.0 and absf(across) < lane:
					push += vside * (1.0 if across >= 0.0 else -1.0) * (lane - absf(across)) * 0.6
		if absf(l.x) < half.x and absf(l.z) < half.y:
			# out of the nearer side of it
			var dx := half.x - absf(l.x)
			var dz := half.y - absf(l.z)
			var out := Vector3((1.0 if l.x >= 0 else -1.0) * dx, 0.0, 0.0) if dx < dz else Vector3(0.0, 0.0, (1.0 if l.z >= 0 else -1.0) * dz)
			push += _vehicle_frame(v).basis.orthonormalized() * out
	for g: Group in _groups:
		for o: Walker in g.golfers:
			if o == w or o.riding or not o.node.visible:
				continue
			var rel := pos - o.node.global_position
			if absf(rel.y) > 0.8:
				continue
			rel.y = 0.0
			var dist := rel.length()
			if dist > 0.01 and dist < 0.55:
				push += rel / dist * (0.55 - dist) * 0.5
	if push.length() < 0.005:
		return
	var moved := pos + push.limit_length(2.5 * delta)
	if _walk_region_clear(w, pos, moved):
		w.node.global_position = Vector3(moved.x, pos.y, moved.z)


## A waiting pedestrian walks to a clear side of a stopped vehicle rather than being
## slid along by repulsion. Keep the original task; this is only a short safety sidestep.
func _walk_aside_for_stopped_vehicle(w: Walker) -> bool:
	var pos := w.node.global_position
	for v: Walker in _nearby_vehicles(pos, 10.0):
		if v == w.data.get("wash_cart") or not v.data.get("pedestrian_stopped", false) or v.path.is_empty() or not v.node.is_visible_in_tree(): continue
		# Only the actual obstruction yields; nearby pedestrians keep their own routes.
		if v.data.get("blocker_person") != w: continue
		var bypass: Dictionary = w.data.get("yield_bypass", {})
		if not bypass.is_empty() and bypass["vehicle"].get_ref() == v.node:
			if v.node.global_position.distance_to(bypass["origin"]) < 1.0: continue
			w.data.erase("yield_bypass")
		if absf(pos.y - v.node.global_position.y) > 1.2: continue
		var target: Vector3 = v.path[0]
		var heading := Vector3(target.x - v.node.global_position.x, 0, target.z - v.node.global_position.z)
		if heading.length() < 0.01: continue
		heading = heading.normalized()
		var side := Vector3(-heading.z, 0, heading.x)
		var rel := pos - _vehicle_frame(v).origin
		var lane := _vehicle_lateral_extent(v, side) + 1.1
		var across := rel.dot(side)
		if absf(across) >= lane: continue
		var preferred := 1.0 if across >= 0 else -1.0
		for sign_value: float in [preferred, -preferred]:
			for shift: float in [0.0, -1.4, 1.4, -2.8, 2.8]:
				var aside := pos + side * (sign_value * lane - across) + heading * shift
				var route: Array = [aside]
				if not _walk_region_clear(w, pos, aside):
					route = _pedestrian_escape_route(w, aside)
					if route.is_empty(): continue
				var occupied := false
				for other: Walker in _pedestrians():
					if other == w or other.riding or not is_instance_valid(other.node) or not other.node.is_visible_in_tree(): continue
					var reserved: Vector3 = other.data.get("pedestrian_yield", {}).get("aside", other.node.global_position)
					if other.node.global_position.distance_to(aside) < 0.7 or reserved.distance_to(aside) < 0.7:
						occupied = true
				if occupied: continue
				w.data["pedestrian_yield"] = {"route": w.path.duplicate(), "aside": aside, "vehicle": weakref(v.node), "heading": heading, "half_length": _footprint(v).length(), "approach": route.duplicate()}
				w.path = route + [aside]
				w.data["blocked"] = false
				w.data["hold"] = 0.0
				_play(w, "walk")
				return true

	return false


## Wait off the lane until the vehicle has passed, then resume the original task.
## A newly assigned route cancels the yield instead of being overwritten by it.
func _pedestrian_yield_step(w: Walker, delta: float = 0.0) -> bool:
	if not w.data.has("pedestrian_yield"): return false
	var state: Dictionary = w.data["pedestrian_yield"]
	var aside: Vector3 = state["aside"]
	if w.path.is_empty() or (w.path[0] != aside and not (state.get("approach", []) as Array).has(w.path[0])):
		w.data.erase("pedestrian_yield")
		return false
	var vehicle: Node3D = state["vehicle"].get_ref()
	var finished := not is_instance_valid(vehicle) or not vehicle.is_visible_in_tree()
	if not finished:
		var along := (w.node.global_position - vehicle.global_position).dot(state["heading"])
		finished = along < -float(state["half_length"]) - 1.0 or w.node.global_position.distance_to(vehicle.global_position) > float(state["half_length"]) + 7.0
		# A vehicle whose task was cancelled must not strand its waiting pedestrian.
		for v: Walker in _vehicles():
			if v.node == vehicle and v.path.is_empty(): finished = true
	if finished:
		w.path = state["route"]
		w.data.erase("pedestrian_yield")
		return false
	# Recover both a queued vehicle and an obstructed passing place. A passing
	# place can become occupied after it was chosen, so approaching it also needs
	# a progress check. Rejoining is always checked against the actual car bodies.
	var remaining := w.node.global_position.distance_to(aside)
	var last: Vector3 = state.get("last_progress", vehicle.global_position)
	var best := float(state.get("best_aside", remaining))
	state["still"] = float(state.get("still", 0.0)) + delta
	if vehicle.global_position.distance_to(last) > 0.35 or remaining < best - 0.15:
		state["last_progress"] = vehicle.global_position
		state["best_aside"] = remaining
		state["still"] = 0.0
	elif not state.has("last_progress"):
		state["last_progress"] = last
		state["best_aside"] = remaining
	if float(state["still"]) > 4.0:
		state["still"] = 0.0
		# The passing place may be blocked by a second cart after it was chosen.
		# Idle workers have no saved route, but still need a way around that cart.
		if remaining >= 0.15:
			var approach := _pedestrian_escape_route(w, aside)
			if not approach.is_empty():
				state["approach"] = approach.duplicate()
				w.path = approach + [aside]
				_play(w, "walk")
				return false
		var saved: Array = state["route"]
		if not saved.is_empty():
			var goal: Vector3 = saved.back()
			var here := w.node.global_position
			var route := _grounds_path(Vector2(here.x, here.z), Vector2(goal.x, goal.z))
			if route.is_empty(): route = _round_vehicles(here, saved)
			var clear := not route.is_empty()
			var at := here
			for point: Vector3 in route:
				clear = clear and _walk_region_clear(w, at, point)
				at = point
			if not clear:
				route = _pedestrian_escape_route(w, goal)
				clear = not route.is_empty()
			if clear:
				w.path = route
				w.data["yield_bypass"] = {"vehicle": weakref(vehicle), "origin": vehicle.global_position}
				w.data.erase("pedestrian_yield")
				_play(w, "walk")
				return false
	if remaining < 0.15:
		_play(w, w.rest)
		return true
	return false


## A small visibility graph handles several touching car buffers together. Sequential
## detours around one rectangle can otherwise bounce between neighboring parked cars.
func _pedestrian_escape_route(w: Walker, goal: Vector3) -> Array:
	var here := w.node.global_position
	var nearby: Array = []
	for v: Walker in _nearby_vehicles(here, 18.0):
		if v.node.is_visible_in_tree() and absf(v.node.global_position.y - here.y) < 1.2 and v.node.global_position.distance_to(here) < 18.0:
			nearby.append(v)
	nearby.sort_custom(func(a: Walker, b: Walker) -> bool: return a.node.global_position.distance_squared_to(here) < b.node.global_position.distance_squared_to(here))
	var points: Array[Vector3] = [here, goal]
	for v: Walker in nearby.slice(0, 8):
		var half := _footprint(v) + Vector2.ONE * 0.65
		var frame := _vehicle_frame(v)
		for x in [-half.x, half.x]:
			for z in [-half.y, half.y]:
				var corner := frame * Vector3(x, 0, z)
				corner.y = here.y
				points.append(corner)
	var distances: Array[float] = []
	var previous: Array[int] = []
	var done: Array[bool] = []
	for i in points.size():
		distances.append(0.0 if i == 0 else INF)
		previous.append(-1)
		done.append(false)
	for step in points.size():
		var u := -1
		for i in points.size():
			if not done[i] and distances[i] < INF and (u < 0 or distances[i] < distances[u]): u = i
		if u < 0: break
		if u == 1:
			var route: Array = []
			while u > 0:
				route.push_front(points[u])
				u = previous[u]
			return route
		done[u] = true
		for i in points.size():
			if done[i]: continue
			var cost := distances[u] + points[u].distance_to(points[i])
			if cost < distances[i] and _walk_region_clear(w, points[u], points[i]):
				distances[i] = cost
				previous[i] = u
	return []



## Resolve a head-on meeting with one reserved passing place and one waiting cart.
func _cart_pull_aside(v: Walker, other: Walker, heading: Vector3) -> void:
	if v.data.has("pass_route") or v.path.is_empty(): return
	if _grounds_nav.is_empty() and facilities != null: _build_grounds_nav()
	var across := Vector3(-heading.z, 0, heading.x)
	var half := _footprint(v)
	for sign_value: float in [1.0, -1.0]:
		var aside: Vector3 = v.node.global_position + across * sign_value * (half.x + _footprint(other).x + 0.9) - heading * 1.2
		var safe := true
		for offset: Vector3 in [Vector3.ZERO, across * half.x, -across * half.x, heading * half.y, -heading * half.y]:
			var a := v.node.global_position + offset
			var b: Vector3 = aside + offset
			if not _grounds_nav.is_empty() and (_grounds_nav["rect"] as Rect2).has_point(Vector2(a.x, a.z)):
				safe = safe and FacilityBuilder._clear_line(_grounds_nav, Vector2(a.x, a.z), Vector2(b.x, b.z))
			else:
				safe = safe and _open_line(_cart_nav, a, b)
		if not safe: continue
		for obstacle: Walker in _vehicles():
			if obstacle == v or obstacle == other or not obstacle.node.visible: continue
			if aside.distance_to(obstacle.node.global_position) < half.length() + _footprint(obstacle).length(): safe = false
		if not safe: continue
		v.data["pass_route"] = v.path.duplicate()
		v.data["pass_aside"] = aside
		v.data["pass_other"] = weakref(other.node)
		v.path = [aside, aside]  # Keep the delivery active while parked out of the way.
		return


## Send the flight to `to` together: each to a spot of their own beside it, a step apart, and
## not all setting off on the same beat.
func _go_together(g: Group, to: Vector2) -> void:
	var n := g.golfers.size()
	var c := Vector2.ZERO
	for w: Walker in g.golfers:
		c += Vector2(w.node.global_position.x, w.node.global_position.z) / maxf(n, 1)
	var d := (to - c).normalized() if to.distance_to(c) > 0.5 else Vector2.UP
	var side := Vector2(d.y, -d.x)
	for k in range(n):
		var w: Walker = g.golfers[k]
		_go(w, _open_spot(to + side * (k - (n - 1) * 0.5) * 1.2 - d * _rng.randf_range(0.0, 0.8)))
		w.data["hold"] = _rng.randf_range(0.0, 0.7)


## `p` if it's open ground, else the nearest that is.
func _open_spot(p: Vector2) -> Vector2:
	# about the club's buildings, on the grounds' own fine grid: the course's coarse one has every
	# plot solid, so its nearest open cell could be round the far side of the building
	if facilities != null and _grounds_nav.is_empty():
		_build_grounds_nav()
	if not _grounds_nav.is_empty() and (_grounds_nav["rect"] as Rect2).has_point(p):
		var cell := FacilityBuilder._nav_cell(_grounds_nav, p)
		if cell.x >= 0:
			var grid: AStarGrid2D = _grounds_nav["astar"]
			var near := grid.get_point_position(cell)
			return p if near.distance_to(p) < 0.5 else near
	if _nav != null:
		var c := _nav_cell_raw(p)
		if _nav.region.has_point(c) and not _nav.is_point_solid(c):
			return p
	var safe := _safe_point(p)
	return safe if safe != Vector2.INF else p


## Send `w` to facility-local point `to` on `fac`'s walkable grid `key` (round the furniture).
func _go_inside(w: Walker, fac: Node3D, key: String, to: Vector2, y: float) -> void:
	var here := fac.global_transform.affine_inverse() * w.node.global_position
	var pts := FacilityBuilder.nav_route(fac, key, Vector2(here.x, here.z), to)
	var path: Array = []
	for i in range(1, pts.size()):
		path.append(fac.global_transform * Vector3(pts[i].x, y, pts[i].y))
	w.data["blocked"] = pts.is_empty() and Vector2(here.x, here.z).distance_to(to) > 1.0
	w.data["indoor_target"] = [weakref(fac), key, to, y]
	w.data["walk_region"] = {"nav": FacilityBuilder.rig(fac)["nav"][key], "xf": fac.global_transform}
	w.path = path


# ================================================================ the course grid

## A coarse grid over the course for everyone outdoors: water, woods and the club's buildings
## are solid, bunkers cost extra (golfers walk round them when they can).
func _build_course_nav() -> void:
	_nav = null
	_grounds_nav.clear()
	if course == null:
		return
	var b := course.bounds()
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, int(ceil(b.size.x / COURSE_CELL)), int(ceil(b.size.y / COURSE_CELL)))
	g.cell_size = Vector2(COURSE_CELL, COURSE_CELL)
	g.offset = b.position + Vector2.ONE * COURSE_CELL * 0.5
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	_cart_nav = AStarGrid2D.new()
	_cart_nav.region = g.region
	_cart_nav.cell_size = g.cell_size
	_cart_nav.offset = g.offset
	_cart_nav.diagonal_mode = g.diagonal_mode
	_cart_nav.update()
	# one sweep: each cell's surface at its centre and four corners, read straight from the
	# nearest canvas cell (the whole course at once: the blended surface_at() is far too slow)
	var a := course.layer_a()
	var corners := [Vector2.ZERO, Vector2(-1.8,-1.8), Vector2(1.8,-1.8), Vector2(-1.8,1.8), Vector2(1.8,1.8)]
	var exclusions: Array = []
	for z in range(g.region.size.y):
		for x in range(g.region.size.x):
			var c := Vector2i(x, z)
			var p := g.get_point_position(c)
			var radius := -1
			for k in range(corners.size()):
				var s := course.surface_nearest(p + corners[k], a)
				if k == 0:
					if s == PaintedCourse.Surface.WATER or s == PaintedCourse.Surface.WOODS:
						g.set_point_solid(c)
						_cart_nav.set_point_solid(c)
					elif s == PaintedCourse.Surface.BUNKER:
						g.set_point_weight_scale(c, BUNKER_COST)
				if s == PaintedCourse.Surface.GREEN:
					radius = maxi(radius, 5) # 20 m buffer beyond the green edge
				elif s == PaintedCourse.Surface.TEE:
					radius = maxi(radius, 1) # room for the cart body outside the painted tee
				elif s == PaintedCourse.Surface.BUNKER or s == PaintedCourse.Surface.WATER:
					radius = maxi(radius, 1)
			if radius >= 0:
				exclusions.append([c, radius])
	# the club's buildings (2 m round each plot): only the cells under each one are checked
	var pl: Dictionary = business.placements if business != null else {}
	for t in pl:
		var pos: Vector2 = pl[t]["pos"]
		var reach := (FacilityBuilder.footprint(t) * 0.5).length() + 2.0
		var lo := Vector2i(floori((pos.x - reach - g.offset.x) / COURSE_CELL), floori((pos.y - reach - g.offset.y) / COURSE_CELL))
		var hi := Vector2i(ceili((pos.x + reach - g.offset.x) / COURSE_CELL), ceili((pos.y + reach - g.offset.y) / COURSE_CELL))
		for z in range(maxi(lo.y, 0), mini(hi.y + 1, g.region.size.y)):
			for x in range(maxi(lo.x, 0), mini(hi.x + 1, g.region.size.x)):
				var c := Vector2i(x, z)
				if FacilityBuilder.contains(t, pos, float(pl[t]["rot"]), g.get_point_position(c), 2.0):
					g.set_point_solid(c)
					_cart_nav.set_point_solid(c)
	# nobody walks out across the driving range's field in front of its bays (its picker drives
	# its own lanes)
	var range_fac := _fac("driving_range")
	var field := _range_field(RANGE_FIELD_WALK)
	if range_fac != null:
		var fp := FacilityBuilder.footprint("driving_range")
		var reach := fp.length() * 0.5 + RANGE_FIELD_WALK
		var at := Vector2(range_fac.global_position.x, range_fac.global_position.z)
		var lo := Vector2i(floori((at.x - reach - g.offset.x) / COURSE_CELL), floori((at.y - reach - g.offset.y) / COURSE_CELL))
		var hi := Vector2i(ceili((at.x + reach - g.offset.x) / COURSE_CELL), ceili((at.y + reach - g.offset.y) / COURSE_CELL))
		for z in range(maxi(lo.y, 0), mini(hi.y + 1, g.region.size.y)):
			for x in range(maxi(lo.x, 0), mini(hi.x + 1, g.region.size.x)):
				if field.call(g.get_point_position(Vector2i(x, z))):
					g.set_point_solid(Vector2i(x, z))
	_nav = g
	# Explicit tee and pin clearances also protect courses whose surfaces are unpainted.
	for h in course.holes:
		exclusions.append([_nav_cell_raw(h["tee"]), 2])
		exclusions.append([_nav_cell_raw(h["pin"]), 6])
	for tree in course.trees:
		exclusions.append([_nav_cell_raw(tree[1]), 1])
	for entry in exclusions:
		var c: Vector2i = entry[0]
		var radius: int = entry[1]
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var q := c + Vector2i(dx, dz)
				if _cart_nav.region.has_point(q):
					_cart_nav.set_point_solid(q)
	_off_cart_path(g)  # (walkers keep off the clubhouse's cart path; the carts' own grid as it is)


func _nav_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(clampi(floori((p.x - _nav.offset.x) / COURSE_CELL + 0.5), 0, _nav.region.size.x - 1), clampi(floori((p.y - _nav.offset.y) / COURSE_CELL + 0.5), 0, _nav.region.size.y - 1))
	if not _nav.is_point_solid(c):
		return c
	for ring in range(1, 10):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var q := c + Vector2i(dx, dz)
				if maxi(absi(dx), absi(dz)) == ring and _nav.region.has_point(q) and not _nav.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Whether the straight line a -> b crosses nothing solid (nor a bunker).
func _clear_line(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / (COURSE_CELL * 0.5)) + 1
	for i in range(n + 1):
		var c := _nav_cell_raw(a.lerp(b, float(i) / n))
		if _nav.is_point_solid(c) or _nav.get_point_weight_scale(c) > 1.0:
			return false
	return true


func _nav_cell_raw(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - _nav.offset.x) / COURSE_CELL + 0.5), 0, _nav.region.size.x - 1), clampi(floori((p.y - _nav.offset.y) / COURSE_CELL + 0.5), 0, _nav.region.size.y - 1))


## Waypoints (Vector3, y unused: walkers keep to the ground) from `from` to `to` on the course:
## straight when the way is clear, else round water, woods and buildings.
func _route(from: Vector2, to: Vector2, vehicle: bool = false) -> Array:
	var half := 0.8 if vehicle else 0.0
	var grid := _cart_nav if vehicle else _nav
	if grid == null:
		return []
	var a := _nav_cell_raw(from)
	var b := _nav_cell_raw(to)
	if grid.is_point_solid(a) or grid.is_point_solid(b):
		return [] # Never replace an impossible route with a straight line through hazards.
	var pts := grid.get_point_path(a, b)
	if pts.is_empty():
		return []
	var out: Array = []
	# The A* corners pulled tight (straight on wherever the way's clear: no stair-stepping across
	# open ground), never cutting the corner of an obstacle.
	var kept: Array = [pts[0]]
	for k in range(1, pts.size()):
		var nxt: Vector2 = pts[k + 1] if k + 1 < pts.size() else to
		if not _clear_course(grid, kept[kept.size() - 1], nxt, half):
			kept.append(pts[k])
	for p in kept:
		out.append(Vector3(p.x, 0.0, p.y))
	out.append(Vector3(to.x, 0.0, to.y))
	return out


## Whether the straight way from `a` to `b` stays on open cells of the course's grid `grid`: every
## cell the line crosses (not samples along it: no clipping a corner), and the same `half` m to
## either side of it (a cart's width).
func _clear_course(grid: AStarGrid2D, a: Vector2, b: Vector2, half: float = 0.8) -> bool:
	var side := (b - a).orthogonal().normalized() * half if a.distance_to(b) > 0.01 else Vector2.ZERO
	for off in [Vector2.ZERO, side, -side]:
		if not _cells_clear(grid, a + off, b + off):
			return false
	return true


## Every cell of `grid` the segment `a`-`b` passes through open (a grid walk, cell to cell).
func _cells_clear(grid: AStarGrid2D, a: Vector2, b: Vector2) -> bool:
	var o := grid.offset - Vector2.ONE * COURSE_CELL * 0.5  # (the cells' corners)
	var p := (a - o) / COURSE_CELL
	var q := (b - o) / COURSE_CELL
	var c := Vector2i(floori(p.x), floori(p.y))
	var end := Vector2i(floori(q.x), floori(q.y))
	var d := q - p
	var step := Vector2i(1 if d.x > 0.0 else -1, 1 if d.y > 0.0 else -1)
	var next := Vector2((c.x + (1 if d.x > 0.0 else 0)) - p.x, (c.y + (1 if d.y > 0.0 else 0)) - p.y)
	var t_max := Vector2(next.x / d.x if absf(d.x) > 1e-9 else INF, next.y / d.y if absf(d.y) > 1e-9 else INF)
	var t_delta := Vector2(absf(1.0 / d.x) if absf(d.x) > 1e-9 else INF, absf(1.0 / d.y) if absf(d.y) > 1e-9 else INF)
	for _i in range(4096):
		if not grid.region.has_point(c) or grid.is_point_solid(c):
			return false
		if c == end:
			return true
		if t_max.x < t_max.y:
			c.x += step.x
			t_max.x += t_delta.x
		else:
			c.y += step.y
			t_max.y += t_delta.y
		if t_max.x > 1.0 and t_max.y > 1.0 and c != end:
			c = end  # (the last cell, reached on a float's rounding)
	return true


func _safe_point(at: Vector2, vehicle: bool = false) -> Vector2:
	var grid := _cart_nav if vehicle else _nav
	if grid == null:
		return Vector2.INF
	var center := _nav_cell_raw(at)
	for ring in range(0, 35):
		var best := Vector2.INF
		var distance := INF
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var c := center + Vector2i(dx, dz)
				if grid.region.has_point(c) and not grid.is_point_solid(c):
					var p := grid.get_point_position(c)
					if p.distance_squared_to(at) < distance:
						best = p
						distance = p.distance_squared_to(at)
		if best != Vector2.INF:
			return best
	return Vector2.INF


## Reserve a distinct parking bay, including destinations of carts still driving.
func _cart_parking_point(want: Vector2, own: Walker) -> Vector2:
	if _cart_nav == null:
		return Vector2.INF
	var center := _nav_cell_raw(want)
	for ring in range(36):
		var best := Vector2.INF
		var distance := INF
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cell := center + Vector2i(dx, dz)
				if not _cart_nav.region.has_point(cell) or _cart_nav.is_point_solid(cell):
					continue
				var p := _cart_nav.get_point_position(cell)
				var clear := true
				for flight in _groups:
					for cart in flight.carts:
						if cart == own or not cart.node.visible:
							continue
						var at: Vector3 = cart.node.global_position
						clear = clear and p.distance_to(Vector2(at.x, at.z)) >= 3.8
						if cart.data.has("parking_target"):
							clear = clear and p.distance_to(cart.data["parking_target"]) >= 3.8
					for w: Walker in flight.golfers:
						if w.riding or not w.node.visible:
							continue
						clear = clear and p.distance_to(Vector2(w.node.global_position.x, w.node.global_position.z)) >= 2.4
						if not w.path.is_empty() and w.data.has("outdoor_target"):
							clear = clear and p.distance_to(w.data["outdoor_target"]) >= 2.4
				if clear and p.distance_squared_to(want) < distance:
					best = p
					distance = p.distance_squared_to(want)
		if best != Vector2.INF:
			own.data["parking_target"] = best
			return best
	return Vector2.INF


## Flights wait their turn for the tee just back from it: on foot off to the side away from the
## carts' (out of the line of play, clear of the flight on the tee waiting 6 m back), in carts
## parked out on their side; the first in line a dozen metres back, each after it further back.
func _wait_for_tee(g: Group) -> void:
	g.queue_hole = g.hole
	g.queue_ticket = _queue_serial
	_queue_serial += 1
	if not _try_wait_practice(g):
		_hold_for_tee(g)


## How many flights are in line for `g`'s tee ahead of it.
## Whether flight `g`, waiting its turn on the first tee with a flight or more in line ahead of it
## (a while yet), could fill the wait on the short game area: on foot, not there yet this round,
## and the area open and not far from the tee.
func _wait_practice_ok(g: Group) -> bool:
	return g.hole == 0 and g.visit == "" and _tee_rank(g) >= 1 and business != null


## Keep the queue ticket while warming up, including cart flights. Park before dismounting.
func _drive_to_practice(g: Group, destination: String) -> bool:
	var front := _facility_front(destination)
	if front == Vector2.INF: return false
	var parking: Array = []
	for k in range(g.carts.size()):
		var park := _cart_parking_point(front + Vector2(k * 4.5, 4.0), g.carts[k])
		if park == Vector2.INF: return false
		parking.append(park)
	for k in range(g.carts.size()): _go(g.carts[k], parking[k])
	g.wait_facility = destination
	g.phase = "practice_park"
	return true


# Golfers take their own bags off their parked carts for practice and reload on boarding.
func _practice_bags_off(g: Group) -> void:
	for c: Walker in g.carts:
		for bag: Node3D in c.data.get("bags", []):
			if is_instance_valid(bag): bag.queue_free()
		c.data["bags"] = []
	for w: Walker in g.golfers:
		if not w.data.has("bag"): _carry_bag(w, str(w.data.get("bag_livery", "")))


func _pre_round_practice(g: Group) -> bool:
	if g.visit != "": return false
	var destination := "driving_range" if g.range_visit else ("short_game" if g.short_visit else "")
	if destination == "": return false
	if _fac(destination) == null or not business.working(destination):
		if destination == "driving_range": g.range_visit = false
		else: g.short_visit = false
		return false
	if not _drive_to_practice(g, destination):
		g.phase = "practice_depart"
		g.retry = 2.0
	return true


func _try_wait_practice(g: Group) -> bool:
	if not _wait_practice_ok(g): return false
	var destination := ""
	for kind in ["short_game", "driving_range"]:
		if _fac(kind) != null and business.working(kind):
			destination = kind
			break
	if destination == "": return false
	g.wait_practice = true
	g.wait_practiced = true
	g.wait_practice_elapsed = 0.0
	g.wait_facility = destination
	var front := _facility_front(destination)
	if not g.carts.is_empty():
		if not _drive_to_practice(g, destination):
			g.wait_practice = false
			return false
	else:
		_go_together(g, front)
		g.phase = "short_front" if destination == "short_game" else "range_front"
	return true


func _tee_time_ready(g: Group) -> bool:
	if g.tee_started: return true
	if g.hole != g.start_hole or g.start_hole not in [0, 9] or g.stop != 0: return false
	return business == null or business.hours + 0.000001 >= business.next_tee_hour


func _record_tee_start(g: Group) -> bool:
	if not _tee_time_ready(g): return false
	if not g.tee_started:
		g.tee_started = true
		if business != null: business.next_tee_hour = business.hours + TEE_INTERVAL
	return true


func _tee_rank(g: Group) -> int:
	var rank := 0
	for other in _groups:
		if other != g and not other.hole_reserved and other.queue_hole == g.hole and other.queue_ticket < g.queue_ticket:
			rank += 1
	return rank


## `g` to its place in line for the tee (_wait_for_tee).
func _hold_for_tee(g: Group) -> void:
	g.queue_rank = _tee_rank(g)
	var tee: Vector2 = g.stops[0]
	var d := (_target(g) - tee).normalized()
	var side := Vector2(d.y, -d.x)  # the carts' side (_go_play parks them out this way)
	var back := 12.0 + g.queue_rank * 6.0
	if not g.carts.is_empty():
		for k in range(g.golfers.size()):
			if not g.golfers[k].riding:
				_seat(g.golfers[k], g.carts[k / 2], k % 2)
		for k in range(g.carts.size()):
			var c: Walker = g.carts[k]
			var park := _cart_parking_point(tee - d * back + side * (9.0 + k * 4.5), c)
			if park != Vector2.INF:
				_go(c, park)
		_stagger(g)
	else:
		for k in range(g.golfers.size()):
			var w: Walker = g.golfers[k]
			_go(w, _open_spot(tee - d * back - side * (4.5 + k * 1.3)))
			w.data["watch"] = tee  # side by side, turned to the tee


# ================================================================ staff

func _spawn_staff() -> void:
	for p in _staff:
		_valet_release_worker(p)
		_release_wash(p)  # Release their cart and portable reel before replacing staff.
		p.node.queue_free()
	_staff.clear()
	_invalidate_traffic()
	_pickers.clear()
	_requeue_bag_runs()  # (a bag run's cart boy among them: the next one's)
	if course == null:
		return
	_reset_carts()
	for s in EconomyConfig.manager_cfg().get("staff", []):
		var role := str(s["id"])
		var works := str(s.get("works", "course"))
		var n := mini(business.heads(role), 2 if role == "valet" else (6 if role == "greenskeeper" else STAFF_SHOWN))
		if n == 0 or business.workplace_note(role) != "":
			continue
		for i in range(n):
			var w := _person("staff_" + role)
			if w == null:
				continue
			var ok := true
			if role == "marshal":
				# the marshal rides; the cart is what moves (and what the staff list keeps)
				var cart := _marshal(w)
				if cart != null:
					_staff.append(cart)
					_invalidate_traffic()
				else:
					w.node.queue_free()
				continue
			if works == "course":
				ok = _greenskeeper(w)
			elif works.begins_with("room:"):
				ok = _room_worker(w, works.substr(5), i, role)
			else:
				ok = _yard_worker(w, works, i, role)
			if ok:
				if role == "valet": _valet_post(w,i)
				_staff.append(w)
				_invalidate_traffic()
			else:
				w.node.queue_free()


func _fac(type: String) -> Node3D:
	return facilities.get_node_or_null(type) as Node3D if facilities != null else null


## The spots of `room` that suit `role`: those tagged for it, else the untagged ones, else any.
static func _spots_for(spots: Array, role: String) -> Array:
	var mine: Array = spots.filter(func(sp) -> bool: return str(sp["role"]) == role)
	if mine.is_empty():
		mine = spots.filter(func(sp) -> bool: return str(sp["role"]) == "")
	return mine if not mine.is_empty() else spots


## A post in a clubhouse room (its staff spots from the Blender model, the role's own first).
## What they do there depends on the job: STAY roles keep to the post; chefs move about the
## kitchen; waiters walk the floor between the tables; the rest work at the post with now and
## then a walk round the room. All of them on the room's walkable grid.
func _room_worker(w: Walker, room: String, i: int, role: String) -> bool:
	var house := _fac("clubhouse")
	var rig := FacilityBuilder.rig(house)
	var post_role := role
	if role == "golf_pro":
		# the pros, in the order they're hired: the first sat at the office desk, the next running
		# the bay from its screen, the last sat on the sofa (with no office fitted, the bay and the
		# sofa in turn)
		var jobs: Array = PRO_JOBS.filter(func(j: Array) -> bool: return j[0] != "office" or (rig.get("spots", {}) as Dictionary).has("office"))
		var job: Array = jobs[i % jobs.size()]
		room = job[0]
		post_role = job[1]
		i = 0
	var spots: Array = _spots_for(rig.get("spots", {}).get(room, []), post_role)
	var box: Dictionary = rig.get("boxes", {}).get(room, {})
	if house == null or box.is_empty():
		return false
	var post: Transform3D
	if spots.is_empty():
		var c: Vector2 = (box["rect"] as Rect2).get_center()
		post = house.global_transform * Transform3D(Basis(), Vector3(c.x, float(box["y"]), c.y))
	else:
		post = house.global_transform * (spots[i % spots.size()]["xf"] as Transform3D)
	var area := str(AREA.get(role, room))
	if not FacilityBuilder.nav_has(house, area):
		area = room
	w.ground = false
	# a second head on the same spot stands half a step along
	w.node.global_transform = Transform3D(post.basis.orthonormalized(), post.origin + post.basis.x.normalized() * 0.6 * (i / maxi(spots.size(), 1)))
	var local := house.global_transform.affine_inverse() * w.node.global_position
	if role == "waiter":
		var open := FacilityBuilder.nav_floor_point(house, area, Vector2(local.x, local.z))
		if open == Vector2.INF:
			return false
		local = Vector3(open.x, float(box["y"]), open.y)
		w.node.global_position = house.global_transform * local
	w.data = {"post": Vector2(local.x, local.z), "yaw": w.node.rotation.y, "home": true, "fac": house, "area": area, "y": float(box["y"]), "role": role}
	if post_role.ends_with("_sit") or post_role.ends_with("_desk"):
		w.node.global_transform = Transform3D(post.basis.orthonormalized(), post.origin)
		# (at the office desk: typing away, sat at the keyboard)
		w.rest = "type_sit" if post_role.ends_with("_desk") and w.anim != null and w.anim.has_animation("type_sit") else "sit"
		_play(w, w.rest)
		w.think = func(_p: Walker) -> void: pass  # sat there (the bookings at the desk; between lessons on the sofa)
		return true
	w.data["work"] = "type" if role in TYPING and w.anim != null and w.anim.has_animation("type") else "work"
	w.rest = w.data["work"]
	w.wait = _rng.randf_range(2.0, 10.0)
	_play(w, w.rest)
	w.think = _trainer_round if role == "trainer" else (_stay if role in STAY else (_wander_floor if role == "waiter" else _roam))
	return true


## The range's ball picker (the caged cart towing its gang of pick-up discs), parked at the side
## of the range by the end of its bays, facing down the field.
func _range_picker(fac: Node3D) -> Walker:
	var scene := _scene(PICKER)
	if scene == null or fac == null:
		return null
	var c := Walker.new()
	c.node = scene.instantiate() as Node3D
	c.node.name = "RangePicker"
	c.data["golf_cart"] = true
	c.data["picker_vehicle"] = true
	add_child(c.node)
	c.data["vehicle"] = true
	c.data["half"] = Vector2(PICKER_REACH, PICKER_GANG + 0.4)  # (the gang's breadth; its tail)
	c.speed = RIDE * 0.6
	c.ground = true
	var fp := FacilityBuilder.footprint("driving_range")
	var at := fac.global_transform * Vector3(fp.x * 0.5 + 4.0, 0.0, -fp.y * 0.5 + 4.0)
	var park := _safe_point(Vector2(at.x, at.z), true)
	if park == Vector2.INF:
		park = Vector2(at.x, at.z)
	c.node.global_position = Vector3(park.x, _ground_y(park), park.y)
	c.node.global_rotation = Vector3(0.0, fac.global_rotation.y, 0.0)
	c.data["park"] = park
	return c


## The range attendant's other job: now and then (more often with balls lying out) off their posts
## to the ball picker -- down from the lounge first, if that's where they are -- in at its driver's
## side, round the field in its lanes (_picker_sweep), picking up what lies there, then parked
## again, out, and back to their posts. True while they're at it.
func _pick_balls(p: Walker) -> bool:
	var picker: Walker = p.data["picker"]
	var fac: Node3D = p.data["fac"]
	if not is_instance_valid(picker.node) or not is_instance_valid(fac):
		return false
	match str(p.data.get("pick", "")):
		"":
			var lying := 0
			for g: Group in _groups:
				for b in g.practice_balls:
					lying += 1 if is_instance_valid(b) and (b as Node3D).visible else 0
			if _clock < float(p.data.get("pick_at", 0.0)) and lying < 8:
				return false
			if p.data.get("range_up", false):
				var fp := FacilityBuilder.footprint("driving_range")
				_range_go(p, fac, Vector2(fp.x * 0.5 + 2.0, -fp.y * 0.5 + 6.0), false)  # (down the stair first)
				p.data["pick"] = "down"
				return true
			p.data["pick"] = "down"
			return true
		"down":
			if not p.path.is_empty():
				return true
			p.ground = true
			var door := _cart_door(picker, 0)
			_go(p, Vector2(door.x, door.z))
			p.data["pick"] = "to_cart"
			return true
		"to_cart":
			if not p.path.is_empty():
				return true
			var door := _cart_door(picker, 0)
			if Vector2(p.node.global_position.x - door.x, p.node.global_position.z - door.z).length() > 1.2:
				_go(p, Vector2(door.x, door.z))
				return true  # An unreachable route is not arrival at the cage's side opening.
			_climb_in(p, picker, 0)
			p.data["pick"] = "boarding"
			p.wait = 0.2
			return true
		"boarding":
			if p.data.has("cart_move"): return true
			picker.path = _picker_sweep(fac, picker)
			p.data["pick"] = "sweep"
			return true
		"sweep":
			if not picker.path.is_empty():
				return true
			picker.node.global_rotation = Vector3(0.0, fac.global_rotation.y, 0.0)  # (parked again, facing down the field)
			_climb_out(p, picker, 0)
			p.data["pick"] = "alighting"
			p.wait = 0.2
			return true
		"alighting":
			if p.data.has("cart_move"): return true
			# The picker gang is wider than its cab; step clear before going to the baskets.
			var by := picker.node.global_transform * Vector3(-1.9, 0.0, PICKER_GANG)  # (round to the baskets, at the gang's end)
			_go(p, Vector2(by.x, by.z))
			p.data["pick"] = "empty"
			return true
		"empty":
			if not p.path.is_empty():
				return true
			# the baskets emptied out (into the ball washer's bins), a few seconds' work
			p.data["watch"] = Vector2(picker.node.global_position.x, picker.node.global_position.z)
			p.rest = "work"
			_play(p, "work")
			var left := _basket_count(picker)
			for mmi: MultiMeshInstance3D in _baskets(picker):
				mmi.multimesh.visible_instance_count = maxi(mmi.multimesh.visible_instance_count - maxi(ceili(mmi.multimesh.instance_count / 14.0), 1), 0)
			p.wait = 0.25
			if left == 0:
				p.data["pick"] = "emptied"
			return true
		"emptied":
			p.data.erase("watch")
			p.data["range_up"] = false
			p.data.erase("pick")
			p.data["pick_at"] = _clock + _rng.randf_range(120.0, 260.0)
			return false
	return false


## The balls in each of the picker `pk`'s baskets: a pile in each, filling from the bottom up a
## layer at a time (scattered over it, not in rows), none showing till it picks some up. Made the
## first time they're wanted.
func _baskets(pk: Walker) -> Array:
	var made: Array = pk.data.get("baskets", [])
	if not made.is_empty() and is_instance_valid(made[0]):
		return made
	made = []
	var ball := SphereMesh.new()
	ball.radius = 0.0214
	ball.height = 0.0428
	ball.radial_segments = 8
	ball.rings = 4
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f4f4ef")
	white.roughness = 0.45
	ball.material = white
	var box := PICKER_BASKET
	var nx := int(box.size.x / 0.046)
	var nz := int(box.size.z / 0.046)
	var ny := int(box.size.y / 0.038)
	var rng := RandomNumberGenerator.new()
	for sx: float in PICKER_BASKETS:
		rng.seed = 7 + int(sx * 10.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ball
		mm.instance_count = nx * ny * nz
		var i := 0
		for y in range(ny):
			var layer: Array = []
			for z in range(nz):
				for x in range(nx):
					layer.append(Vector2i(x, z))
			for k in range(layer.size() - 1, 0, -1):  # (each layer in no order)
				var j := rng.randi_range(0, k)
				var swap: Vector2i = layer[k]
				layer[k] = layer[j]
				layer[j] = swap
			for cell: Vector2i in layer:
				var shift := 0.0115 if y % 2 == 1 else 0.0  # (sat in the dips of the layer below)
				var p := box.position + Vector3(sx + 0.025 + cell.x * 0.046 + shift, 0.0214 + y * 0.038, 0.025 + cell.y * 0.046 + shift)
				p += Vector3(rng.randf_range(-0.006, 0.006), rng.randf_range(0.0, 0.006), rng.randf_range(-0.006, 0.006))
				mm.set_instance_transform(i, Transform3D(Basis(), p))
				i += 1
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BasketBalls"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pk.node.add_child(mmi)
		made.append(mmi)
	pk.data["baskets"] = made
	return made


## How many balls show in the picker's baskets, all told.
func _basket_count(pk: Walker) -> int:
	var n := 0
	for mmi: MultiMeshInstance3D in _baskets(pk):
		n += maxi(mmi.multimesh.visible_instance_count, 0)
	return n


## `n` more balls in the picker's basket `i` (as full as it gets).
func _basket_add(pk: Walker, i: int, n: int) -> void:
	var mm: MultiMesh = (_baskets(pk)[i] as MultiMeshInstance3D).multimesh
	mm.visible_instance_count = mini(maxi(mm.visible_instance_count, 0) + n, mm.instance_count)


## The ball picker's run (world points): from where it's parked out into the range's field, up and
## down it in four lanes clear of its yardage boards (down the middle) and its targets' flags, from
## 40 m out to 185 m (where the balls land), and back to park.
func _picker_sweep(fac: Node3D, picker: Walker) -> Array:
	var front := -FacilityBuilder.footprint("driving_range").y * 0.5
	var near := front - 40.0
	var far := front - 185.0
	var path: Array = []
	var lanes := [22.0, 3.0, -3.0, -22.0]
	for i in range(lanes.size()):
		var x: float = lanes[i]
		var ends := [near, far] if i % 2 == 0 else [far, near]
		for z: float in ends:
			path.append(fac.global_transform * Vector3(x, 0.0, z))
	var park: Vector2 = picker.data["park"]
	var by := fac.global_transform * Vector3(FacilityBuilder.footprint("driving_range").x * 0.5 + 4.0, 0.0, near)
	path.append(by)  # (round in front of the bays, well out, and back up the side)
	path.append(Vector3(park.x, 0.0, park.y))
	return path


## The balls lying out on the range that the picker `pk`'s gang passes over: picked up.
func _picker_collect(pk: Walker) -> void:
	var inv := pk.node.global_transform.affine_inverse()
	for g: Group in _groups:
		for b in g.practice_balls:
			if not is_instance_valid(b) or not (b as Node3D).visible:
				continue
			var l: Vector3 = inv * (b as Node3D).global_position
			if absf(l.x) < PICKER_REACH and absf(l.z - PICKER_GANG) < 0.7 and absf(l.y) < 1.0:
				(b as Node3D).visible = false  # (up into the basket over the gang that ran over it)
				(b as Node).queue_free()
				_basket_add(pk, clampi(roundi(l.x / 0.9) + 1, 0, PICKER_BASKETS.size() - 1), BASKET_SHOW)


## Behind the desk / the bar: work, look up, shift a little, work -- never off the post.
func _stay(p: Walker) -> void:
	var work: String = p.data.get("work", "work")
	p.rest = "idle" if p.rest == work else work
	_play(p, p.rest)
	# (typing: square to the keyboard; else turned this way and that about the post)
	p.node.rotation.y = float(p.data["yaw"]) + (_rng.randf_range(-0.06, 0.06) if work == "type" and p.rest == work else _rng.randf_range(-0.35, 0.35))
	p.wait = (_rng.randf_range(8.0, 16.0) if work == "type" else _rng.randf_range(5.0, 12.0)) if p.rest == work else _rng.randf_range(2.0, 4.0)


## Waiting tables: from table to table about the dining room, a moment at each.
func _wander_floor(p: Walker) -> void:
	var fac: Node3D = p.data["fac"]
	if not is_instance_valid(fac):
		return
	var here := fac.global_transform.affine_inverse() * p.node.global_position
	var start := Vector2(here.x, here.z)
	# now and then through to the ballroom's tables (and back), when the club has one
	var floors: Array = ["restaurant", "ballroom"].filter(func(r: String) -> bool: return FacilityBuilder.nav_has(fac, r))
	var area := str(p.data["area"])
	if floors.size() > 1 and floors.has(area) and _rng.randf() < 0.2:
		var other: String = floors[(floors.find(area) + 1) % floors.size()]
		if _cross_to(p, fac, FacilityBuilder.nav_random(fac, other, _rng)):
			p.data["area"] = other
			p.rest = "work"
			p.wait = _rng.randf_range(2.0, 5.0)
			return
	var to: Vector2 = p.data["post"]
	if area != "restaurant" or _rng.randf() >= 0.15 or start.distance_to(to) < 1.0:
		for attempt in range(12):
			to = FacilityBuilder.nav_random(fac, str(p.data["area"]), _rng, start)
			if start.distance_to(to) > 2.0:
				break
	_go_inside(p, fac, str(p.data["area"]), to, float(p.data["y"]))
	p.rest = "work" if _rng.randf() < 0.5 else "idle"
	p.wait = _rng.randf_range(2.0, 5.0)


## Across the clubhouse to facility-local point `to` -- out of one room and into another, on the
## whole house's grid (its doorways open) -- for a waiter going between the dining rooms.
func _cross_to(p: Walker, fac: Node3D, to: Vector2) -> bool:
	_guest_nav(fac)
	var here := fac.global_transform.affine_inverse() * p.node.global_position
	var pts := FacilityBuilder.nav_route(fac, "guest", Vector2(here.x, here.z), to)
	if pts.size() < 2:
		return false
	var path: Array = []
	for i in range(1, pts.size()):
		path.append(fac.global_transform * Vector3(pts[i].x, float(p.data["y"]), pts[i].y))
	p.data.erase("indoor_target")
	p.data["blocked"] = false
	p.path = path
	return true


## Working the post, now and then off round the room (a chef round the kitchen) and back.
func _trainer_round(p: Walker) -> void:
	var house: Node3D = p.data["fac"]
	var area := str(p.data["area"])
	var target: Walker = p.data.get("trainer_target")
	if target != null:
		if is_instance_valid(target.node) and str(target.data.get("place", {}).get("use", "")) in GYM_USES:
			p.data["watch"] = Vector2(target.node.global_position.x, target.node.global_position.z)
			p.data["trainer_visits"] = int(p.data.get("trainer_visits", 0)) + 1
			p.data.erase("trainer_target")
			p.rest = "idle"
			p.wait = 4.0
			return
		p.data.erase("trainer_target")
	p.data.erase("watch")
	var guests: Array = []
	for g: Group in _groups:
		for guest: Walker in g.golfers:
			if guest.path.is_empty() and guest.data.get("seated", false) and str(guest.data.get("place", {}).get("use", "")) in GYM_USES:
				guests.append(guest)
	var visits: Dictionary = p.data.get("trainer_seen", {})
	for seen: Variant in visits.keys():
		if not guests.has(seen): visits.erase(seen)
	guests.sort_custom(func(a: Walker, b: Walker) -> bool: return float(visits.get(a, -INF)) < float(visits.get(b, -INF)))
	for guest: Walker in guests:
		if _staff.any(func(other: Walker) -> bool: return other != p and other.data.get("trainer_target") == guest): continue
		var at := house.global_transform.affine_inverse() * guest.node.global_position
		for offset: Vector2 in [Vector2(1.4, 0), Vector2(-1.4, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
			var goal := FacilityBuilder.nav_floor_point(house, area, Vector2(at.x, at.z) + offset)
			if goal == Vector2.INF or goal.distance_to(Vector2(at.x, at.z)) < 1.0 or goal.distance_to(Vector2(at.x, at.z)) > 2.2: continue
			_go_inside(p, house, area, goal, float(p.data["y"]))
			if p.data.get("blocked", false): continue
			p.data["trainer_target"] = guest
			visits[guest] = _clock
			p.data["trainer_seen"] = visits
			p.rest = "idle"
			p.wait = 0.0
			return
	_go_inside(p, house, area, FacilityBuilder.nav_random(house, area, _rng), float(p.data["y"]))
	p.rest = "idle"
	p.wait = 2.0


func _roam(p: Walker) -> void:
	var fac: Node3D = p.data["fac"]
	if not is_instance_valid(fac):
		return
	var area := str(p.data["area"])
	if p.data["home"]:
		_go_inside(p, fac, area, FacilityBuilder.nav_random(fac, area, _rng), float(p.data["y"]))
		p.rest = "work" if p.data["role"] == "chef" else "idle"
		p.wait = _rng.randf_range(4.0, 9.0) if p.data["role"] == "chef" else _rng.randf_range(2.0, 5.0)
		p.data["home"] = false
	else:
		_go_inside(p, fac, area, p.data["post"], float(p.data["y"]))
		p.rest = "work"
		p.data["home"] = true
		p.data["arrive_yaw"] = p.data["yaw"]
		p.wait = _rng.randf_range(6.0, 14.0)


## At the cart barn or the range: round its staff spots, working at each a while.
func _yard_worker(w: Walker, type: String, i: int, role: String = "") -> bool:
	var fac := _fac(type)
	var spots: Array = FacilityBuilder.rig(fac).get("spots", {}).get("", [])
	if fac == null:
		return false
	var at: Transform3D = fac.global_transform * (spots[i % spots.size()]["xf"] as Transform3D) if not spots.is_empty() else fac.global_transform
	w.node.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	var clips: Dictionary = w.data.get("cart_clips", {})
	w.data = {"fac": fac, "spots": spots, "next": i, "role": role}
	if not clips.is_empty(): w.data["cart_clips"] = clips
	if not spots.is_empty():
		w.data["range_up"] = (spots[i % spots.size()]["xf"] as Transform3D).origin.y > 2.0  # (a post up in the range's lounge)
	if role == "range_attendant" and i == 0:
		var picker := _range_picker(fac)
		if picker != null:
			_staff.append(picker)  # (stepped and kept with the staff, like the marshal's cart)
			_invalidate_traffic()
			_pickers.append(picker)
			w.data["picker"] = picker
			w.data["pick_at"] = _clock + _rng.randf_range(20.0, 60.0)
	w.rest = "work"
	_play(w, "work")
	w.wait = _rng.randf_range(4.0, 12.0)
	w.think = func(p: Walker) -> void:
		if str(p.data.get("role", "")) == "cart_attendant" and _cart_boy(p):
			return  # keeping the line behind the clubhouse in carts
		if str(p.data.get("role", "")) == "cart_attendant":
			p.rest = "idle"  # All attendants wait for work instead of wandering off.
			_play(p, "idle")
			p.wait = 1.5
			return
		if p.data.has("picker") and _pick_balls(p):
			return  # out in the ball picker
		var f: Node3D = p.data["fac"]
		if not is_instance_valid(f):
			return
		var sp: Array = p.data["spots"]
		var local: Vector3 = (sp[(int(p.data["next"]) + 1) % sp.size()]["xf"] as Transform3D).origin if not sp.is_empty() else Vector3.ZERO
		p.data["next"] = int(p.data["next"]) + 1
		var to := Vector2(local.x, local.z) + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
		if FacilityBuilder.nav_has(f, "upper"):
			# a range with a lounge upstairs: on whichever floor the post is, up or down its stair
			# to get there -- round the lounge's sofas and dividers, never through them
			p.ground = true
			_range_go(p, f, to, local.y > 2.0)
		elif FacilityBuilder.nav_has(f, ""):
			p.ground = true
			var here := f.global_transform.affine_inverse() * p.node.global_position
			var pts := FacilityBuilder.nav_route(f, "", Vector2(here.x, here.z), to)
			p.path = []
			for k in range(1, pts.size()):
				p.path.append(f.global_transform * Vector3(pts[k].x, 0.0, pts[k].y))
		if p.path.is_empty():
			_walk_to(p, f.global_transform * Vector3(to.x, local.y, to.y))
		p.rest = "work" if _rng.randf() < 0.6 else "idle"
		p.wait = _rng.randf_range(6.0, 16.0)
	return true


## Out on a hole: a while working the turf, then on along the fairway.
func _greenskeeper(w: Walker) -> bool:
	if course.holes.is_empty():
		return false
	var h := _rng.randi() % course.holes.size()
	var route := course.hole_route(h, 10.0)
	var p0 := route[_rng.randi() % route.size()] + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
	w.node.global_position = Vector3(p0.x, _ground_y(p0), p0.y)
	w.node.rotation.y = _rng.randf() * TAU
	w.rest = "work"
	_play(w, "work")
	w.wait = _rng.randf_range(3.0, 12.0)
	w.think = func(p: Walker) -> void:
		var hh := _rng.randi() % course.holes.size()
		var r := course.hole_route(hh, 10.0)
		var here := Vector2(p.node.global_position.x, p.node.global_position.z)
		var best := r[0]
		var bd := INF
		for _k in range(6):  # somewhere near on the course, not across the map
			var q := r[_rng.randi() % r.size()] + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-14, 14))
			var d := absf(q.distance_to(here) - 35.0)
			if d < bd:
				bd = d
				best = q
		_go(p, best)
		p.rest = "work"
		p.wait = _rng.randf_range(8.0, 16.0)
	return true


## The marshal's rounds: a cart lap of every hole, out along the side of each fairway.
## Returns the cart (with the marshal in the driving seat), or null.
func _marshal(w: Walker) -> Walker:
	if course.holes.is_empty():
		return null
	var cart := _cart()
	if cart == null:
		return null
	_seat(w, cart, 0)
	cart.ground = true
	cart.speed = RIDE * 0.8
	cart.data["vehicle"] = true
	cart.data["rider"] = w
	var start := _safe_point(course.holes[0]["tee"] + Vector2(18, 0), true)
	if start == Vector2.INF:
		cart.node.queue_free()
		return null
	cart.node.global_position = Vector3(start.x, _ground_y(start), start.y)
	cart.data["lap"] = []
	cart.think = func(c: Walker) -> void:
		# the next leg of the lap, round whatever's in the way
		var lap: Array = c.data["lap"]
		if lap.is_empty():
			for hi in range(course.holes.size()):
				lap.append_array(_cart_path(hi))
		var next: Vector2 = lap.pop_front()
		var safe := _safe_point(next, true)
		c.path = _route(Vector2(c.node.global_position.x, c.node.global_position.z), safe, true) if safe != Vector2.INF else []
		c.wait = 0.0 if not lap.is_empty() else 4.0
	return cart


# ================================================================ carts

func _cart() -> Walker:
	var scene := _scene(CART)
	if scene == null:
		return null
	var c := Walker.new()
	c.node = scene.instantiate() as Node3D
	add_child(c.node)
	c.data["vehicle"] = true
	c.data["golf_cart"] = true  # (it goes nowhere with no one sat in it: _step)
	_footprint(c)  # Measure the visible cart before riders, bags, and wheel shadows are added.
	for wheel: Vector2 in WHEELS:
		var blob := MeshInstance3D.new()
		blob.mesh = _wheel_shadow()
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.position = Vector3(wheel.x, 0.015, -wheel.y)
		c.node.add_child(blob)
	return c


## A soft dark patch on the ground where a wheel sits (shared by every cart's wheels).
static func _wheel_shadow() -> QuadMesh:
	if not _scenes.has("wheel_shadow"):
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.6))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = tex
		var quad := QuadMesh.new()
		quad.size = Vector2(0.42, 0.62)
		quad.orientation = PlaneMesh.FACE_Y
		quad.material = mat
		_scenes["wheel_shadow"] = quad
	return _scenes["wheel_shadow"]


## Someone sat in cart `c` (riders ride as the cart's children).
func _manned(c: Walker) -> bool:
	for ch in c.node.get_children():
		if ch is Node3D and (ch as Node3D).find_child("Skeleton3D", true, false) != null:
			return true
	return false


## Sit `w` in seat `k` of `cart` (it rides along as the cart's child).
func _vehicle_seat(vehicle:Walker,k:int)->Vector3:
	if vehicle.data.get("golf_cart",false):return SEATS[k]
	var half:=_footprint(vehicle)
	var seat := (vehicle.data.get("body_center",Vector3.ZERO) as Vector3)+Vector3(half.x*(-.44 if k==0 else .44),.20,-half.y*.08)
	if str(vehicle.data.get("model", "")) == "hatchback": seat += Vector3(0, -0.28, 0.32)
	return seat

func _hatchback_driver_pose(w: Walker) -> void:
	if w.anim == null or w.anim.has_animation("cabin/drive") or not w.anim.has_animation("drive"): return
	var sk := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	_pose_now(w, "drive")
	var clip := w.anim.get_animation("drive").duplicate() as Animation
	for side in ["L", "R"]:
		var thigh := sk.find_bone("thigh." + side)
		var shin := sk.find_bone("shin." + side)
		var foot := sk.find_bone("foot." + side)
		var a := sk.get_bone_global_pose(thigh).origin
		var b := sk.get_bone_global_pose(shin).origin
		var c := sk.get_bone_global_pose(foot).origin
		var target := c + Vector3(0, 0.5, -0.18)
		var dir := (target - a).normalized()
		var distance := a.distance_to(target)
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var along := (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
		var pole := (Vector3.UP - dir * dir.y).normalized()
		var knee := a + dir * along + pole * sqrt(maxf(0.0, l1 * l1 - along * along))
		var pose := sk.get_bone_global_pose(thigh)
		pose.basis = Basis(Quaternion((b - a).normalized(), (knee - a).normalized())) * pose.basis
		sk.set_bone_global_pose(thigh, pose)
		b = sk.get_bone_global_pose(shin).origin
		c = sk.get_bone_global_pose(foot).origin
		pose = sk.get_bone_global_pose(shin)
		pose.basis = Basis(Quaternion((c - b).normalized(), (target - b).normalized())) * pose.basis
		sk.set_bone_global_pose(shin, pose)
		for bone in [thigh, shin]:
			for track in clip.get_track_count():
				if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and str(clip.track_get_path(track).get_concatenated_subnames()) == str(sk.get_bone_name(bone)):
					while clip.track_get_key_count(track) > 0: clip.track_remove_key(track, 0)
					clip.rotation_track_insert_key(track, 0.0, sk.get_bone_pose_rotation(bone))
	var library := AnimationLibrary.new()
	library.add_animation("drive", clip)
	w.anim.add_animation_library("cabin", library)


func _seat(w: Walker, cart: Walker, k: int) -> void:
	if w.node.get_parent() != null:
		w.node.get_parent().remove_child(w.node)
	cart.node.add_child(w.node)
	w.node.transform = Transform3D(Basis(), _vehicle_seat(cart,k))
	w.riding = true
	w.seat_anim = SEAT_ANIMS[k]
	if str(cart.data.get("model", "")) == "hatchback" and k == 0:
		_hatchback_driver_pose(w)
		w.seat_anim = "cabin/drive"
	w.path.clear()
	_play(w, w.seat_anim)


## Seat `k`'s side of `cart` -- the driver's on its left, the passenger's on its right: where
## its rider gets on and off (world).
func _cart_door(cart: Walker, k: int) -> Vector3:
	var xf := cart.node.global_transform
	var reach := maxf(CART_DOOR, _footprint(cart).x + 0.4) if cart.data.get("picker_vehicle", false) else CART_DOOR
	return xf.origin + xf.basis.x.normalized() * (reach if k == 1 else -reach)


## Each golfer into their seat as they reach their side of the cart -- turned to face it first,
## a beat, then in, their bag into the bag well behind them -- whoever's there first, not all at
## once. True once everyone's aboard.
func _board_arrivals(g: Group, delta: float) -> bool:
	var aboard := true
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		if w.riding and not w.data.has("cart_move"):
			continue
		aboard = false
		if not w.riding and w.path.is_empty() and k / 2 < g.carts.size():
			_board_turned(g, k, delta)
	return aboard


## Golfer `k` of flight `g`, there at their side of their cart: turned to face it, a beat, then in
## (their bag, if they've still got it, into the bag well behind them).
func _board_turned(g: Group, k: int, delta: float) -> void:
	var w: Walker = g.golfers[k]
	var c: Walker = g.carts[k / 2]
	var to := Vector2(c.node.global_position.x - w.node.global_position.x, c.node.global_position.z - w.node.global_position.z)
	w.data["watch"] = Vector2(c.node.global_position.x, c.node.global_position.z)  # turn to it
	var t := float(w.data.get("board_t", 0.0)) + delta
	w.data["board_t"] = t
	var facing := Vector2(-sin(w.node.global_rotation.y), -cos(w.node.global_rotation.y))
	if t < 0.4 or (facing.dot(to.normalized()) < 0.94 and t < 1.6):
		return
	w.data.erase("board_t")
	w.data.erase("watch")
	w.data["blocked"] = false
	_load_bag(w, c, k % 2)
	_climb_in(w, c, k % 2)
	var full := true
	for j in range(g.golfers.size()):
		full = full and (j / 2 != k / 2 or (g.golfers[j] as Walker).riding)
	if full:
		c.data["aboard"] = _board_serial
		_board_serial += 1


## A golfer's bag off their back and into the cart's bag well behind seat `k`.
func _load_bag(w: Walker, c: Walker, k: int) -> void:
	var bag: Variant = w.data.get("bag")
	if bag == null or not is_instance_valid(bag):
		return
	_drop_bag(w)
	_cart_bag(c, k, str(w.data.get("bag_livery", "")))


## `w`'s slung bag (`key`: the cart boy's second, "bag2") gone from their shoulder: into a cart's
## bag well, or the cart boy's hands.
func _drop_bag(w: Walker, key: String = "bag") -> void:
	var bag: Variant = w.data.get(key)
	if bag != null and is_instance_valid(bag):
		var holder := (bag as Node).get_parent()
		if holder is BoneAttachment3D:
			holder.queue_free()
		else:
			(bag as Node).queue_free()
	w.data.erase(key)


## A flight's carts set off one after another (the first filled leads), never on the same beat.
func _stagger(g: Group) -> void:
	var order := g.carts.duplicate()
	order.sort_custom(func(a: Walker, b: Walker) -> bool: return int(a.data.get("aboard", 0)) < int(b.data.get("aboard", 0)))
	for i in range(order.size()):
		(order[i] as Walker).data["hold"] = i * _rng.randf_range(1.0, 1.8) + _rng.randf_range(0.0, 0.4)


## Golfer `w` into seat `k` of `cart` by its captured clip, from where they stand at that side: the
## clip's seated end laid on the seat, its start eased in from where they are; seated (_seat) when
## it's done. Straight in when they've no clip.
func _climb_in(w: Walker, cart: Walker, k: int) -> void:
	var clip := _cart_clip_for(w, k, true)
	if clip == "":
		_seat(w, cart, k)
		return
	_cart_move(w, cart, k, clip, true)


## Golfer `w` out of seat `k` of `cart` by its captured clip, ending stood beside it (and off
## its frame); straight out when they've no clip. `w.riding` false once they're out.
func _climb_out(w: Walker, cart: Walker, k: int) -> void:
	var clip := _cart_clip_for(w, k, false)
	if clip == "":
		_unseat(w, cart, k)
		return
	_cart_move(w, cart, k, clip, false)


## Of `w`'s getting in (`entering`) or out clips, the one for seat `k`'s side of the cart -- the
## driver's on its left, the passenger's on its right: the one whose stood end is out that side of
## its seated one. "" without them.
func _cart_clip_for(w: Walker, k: int, entering: bool) -> String:
	var clips: Dictionary = w.data.get("cart_clips", {})
	var best := ""
	for clip in (["enter_cart", "enter_cart_m"] if entering else ["exit_cart", "exit_cart_m"]):
		if not clips.has(clip):
			continue
		var c: Dictionary = clips[clip]
		var stood: Vector3 = c["start"] if entering else c["end"]
		var sat: Vector3 = c["end"] if entering else c["start"]
		var yaw: float = c["end_yaw"] if entering else c["start_yaw"]
		var off := Basis(Vector3.UP, -yaw) * (stood - sat)  # in the seated body's frame (its left: -X)
		if (off.x < 0.0) == (k == 0):
			return clip
		best = clip
	return best


## The clip `clip` playing on `w` in seat `k` of `cart`: the person laid in the cart's frame so its
## seated end (getting in) or start (getting out) is on the seat, facing ahead; where they stand
## at its other end eased in or out from the ground.
func _cart_move(w: Walker, cart: Walker, k: int, clip: String, entering: bool) -> void:
	var c: Dictionary = w.data["cart_clips"][clip]
	var seat: Dictionary = w.data["cart_clips"].get(SEAT_ANIMS[k], {"hips": Vector3(0, 0.55, 0.04)})
	var sat: Vector3 = c["end"] if entering else c["start"]
	var yaw: float = c["end_yaw"] if entering else c["start_yaw"]
	var basis := Basis(Vector3.UP, -yaw)
	var seat_hips: Vector3 = _vehicle_seat(cart,k) + (seat["hips"] as Vector3)
	var origin := seat_hips - basis * sat
	var lift := origin.y  # (the stood end on the ground, the seated on the seat: eased between)
	origin.y = 0.0
	var frame := Transform3D(basis, origin)
	var from_here := Transform3D()
	if entering:
		# from where they are: their place and facing now against the clip's start, eased out
		var here := cart.node.global_transform.affine_inverse() * w.node.global_transform
		var start := frame * Transform3D(Basis(), Vector3((c["start"] as Vector3).x, 0.0, (c["start"] as Vector3).z))
		from_here = Transform3D(Basis(Vector3.UP, here.basis.get_euler().y - frame.basis.get_euler().y), here.origin - start.origin)
		if w.node.get_parent() != null:
			w.node.get_parent().remove_child(w.node)
		cart.node.add_child(w.node)
		_load_bag(w, cart, k)
	w.path.clear()
	w.riding = true
	w.seat_anim = clip
	w.data["cart_move"] = {"cart": cart, "k": k, "clip": clip, "t": 0.0, "length": float(c["length"]) / CART_CLIP_PACE,
		"frame": frame, "lift": lift, "in": entering, "from": from_here}
	if w.anim != null:
		w.anim.play(clip, 0.15, CART_CLIP_PACE)
	_cart_move_step(w, 0.0)


## A frame of `w` getting into or out of their cart: laid where the clip goes, the ground-to-seat
## lift and (getting in) the ease from where they started; at its end, sat in the seat or stood
## beside the cart.
# The captured golf-cart entry assumes no roof. Duck while crossing a small car's doorway.
func _cabin_entry_fit(w: Walker, car: Walker, frame: Transform3D) -> Transform3D:
	if str(car.data.get("model", "")) != "hatchback": return frame
	var sk := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null: return frame
	var local := w.node.global_transform.affine_inverse() * sk.global_transform
	var head := frame * local * sk.get_bone_global_pose(sk.find_bone("head")).origin
	var inside := 1.0 - smoothstep(0.82, 1.22, absf(head.x))
	if head.z > -0.85 and head.z < 0.8:
		frame.origin.y -= maxf(0.0, head.y - 1.12) * inside
	return frame


func _cart_move_step(w: Walker, delta: float) -> void:
	_people_grid.clear()
	var m: Dictionary = w.data["cart_move"]
	var cart: Walker = m["cart"]
	if not is_instance_valid(cart.node):
		w.data.erase("cart_move")
		return
	m["t"] = float(m["t"]) + delta
	var u := clampf(float(m["t"]) / float(m["length"]), 0.0, 1.0)
	var frame: Transform3D = m["frame"]
	if m["in"]:
		var ease := 1.0 - smoothstep(0.0, 0.35, u)
		var from: Transform3D = m["from"]
		var at := frame
		at.origin += from.origin * ease
		at.basis = Basis(Vector3.UP, from.basis.get_euler().y * ease) * frame.basis
		at.origin.y = float(m["lift"]) * smoothstep(0.45, 1.0, u)
		w.node.transform = _cabin_entry_fit(w, cart, at)
	else:
		var at := frame
		at.origin.y = float(m["lift"]) * (1.0 - smoothstep(0.0, 0.55, u))
		w.node.transform = _cabin_entry_fit(w, cart, at)
	if u < 1.0:
		return
	var k: int = m["k"]
	w.data.erase("cart_move")
	if m["in"]:
		_seat(w, cart, k)
		_pose_now(w, w.seat_anim)  # (the clip's last pose is the seat's: straight into it)
		return
	# stood beside the cart where the clip leaves them, off its frame and back on the ground
	var c: Dictionary = w.data["cart_clips"][m["clip"]]
	var end: Vector3 = c["end"]
	var stood := cart.node.global_transform * (frame * Vector3(end.x, 0.0, end.z))
	var facing := cart.node.global_rotation.y + frame.basis.get_euler().y + float(c["end_yaw"])
	cart.node.remove_child(w.node)
	add_child(w.node)
	w.node.global_position = Vector3(stood.x, _surface_y(Vector2(stood.x, stood.z)), stood.z)
	w.node.rotation = Vector3(0, facing, 0)
	w.riding = false
	w.seat_anim = SEAT_ANIMS[k]
	w.data["climbed_out"] = true
	_pose_now(w, "idle")


## `w` in clip `clip` this very frame, no blending from what they were doing (their frame moved
## with it, to keep them where they are).
func _pose_now(w: Walker, clip: String) -> void:
	if w.anim == null or not w.anim.has_animation(clip):
		return
	w.anim.play(clip, 0.0)
	w.anim.advance(0.0)


## Take `w` out of its cart, standing beside it.
func _unseat(w: Walker, cart: Walker, k: int) -> void:
	var at := _cart_door(cart, k)
	cart.node.remove_child(w.node)
	add_child(w.node)
	w.node.global_position = Vector3(at.x, _surface_y(Vector2(at.x, at.z)), at.z)
	w.node.rotation = Vector3(0, cart.node.rotation.y, 0)
	w.riding = false
	_play(w, "idle")


## A cart's route along hole `h`: off to the side of the line of play (where a cart path runs).
func _cart_path(h: int) -> Array:
	var route := course.hole_route(h, 25.0)
	var out: Array = []
	for i in range(route.size()):
		var a := route[maxi(i - 1, 0)]
		var b := route[mini(i + 1, route.size() - 1)]
		var d := (b - a).normalized() if b != a else Vector2.UP
		out.append(route[i] + Vector2(d.y, -d.x) * 16.0)
	return out


# ================================================================ golfers

## How many groups the club's pull puts on the course right now.
func _target_groups() -> int:
	if business == null or course == null or course.holes.is_empty():
		return 0
	var r := business.rates()
	if not r["open"]:
		return 0
	var demand := business.traffic_multiplier()
	var limit := MAX_GROUPS if demand > 1.1 else 8
	return clampi(int(ceil(float(r["golfers"]) * 1.2 * demand)) + (1 if demand >= 1.0 else 0), 1 if demand < 1.0 else 2, mini(limit, course.holes.size() * 3))


func _arrival_interval() -> float:
	return 6.0 / maxf(business.traffic_multiplier(), 0.1) if business != null else 6.0


func _top_up_golfers() -> void:
	if _groups.size() >= 24: return  # Bound golf and amenity visitors together.
	var golf := 0
	var others := {}  # the club's other customers in now, by what they came for
	for g: Group in _groups:
		if g.visit == "":
			golf += 1
		else:
			others[g.visit] = int(others.get(g.visit, 0)) + 1
	var want := _target_groups()
	if golf < want:
		_new_arrival()
		_spawn_wait = _arrival_interval()
		return
	if want == 0:
		return  # (closed)
	# and a few who come for the rest of what the club has: members at the gym, people in for a
	# bucket at the range or some chipping and putting
	var kinds: Array = []
	if business.room_working("spa_fitness") and int(others.get("gym", 0)) < maxi(1, roundi(GYM_VISITS * minf(business.traffic_multiplier(), 1.0))):
		kinds.append_array(["gym", "gym", "gym"])  # (the likeliest of them: user, the gym used more)
	if business.room_working("restaurant") and int(others.get("bar", 0)) < BAR_VISITS and _bar_guests() < BAR_GUESTS and not _free_places("restaurant", ["guest_bar"]).is_empty():
		kinds.append("bar")  # (in for a drink at the bar: user)
	if business.room_working("simulator") and business.heads("golf_pro") > 0 and business.hours >= _next_lesson 			and int(others.get("sim", 0)) == 0 and not _free_places("simulator", ["guest_sim"]).is_empty():
		kinds = ["sim"]  # (a lesson with the pro, at its appointed time: in now, whatever else is on)
		_next_lesson = business.hours + SIM_LESSON_EVERY
	var range_capacity := 0
	var range_fac := _fac("driving_range")
	if range_fac != null:
		var rig := FacilityBuilder.rig(range_fac)
		range_capacity = (rig.get("range_bays", []) as Array).size() + (rig.get("range_bays_up", []) as Array).size()
	for g: Group in _groups:
		if g.visit == "" and g.range_visit:
			range_capacity -= g.golfers.size()
	if business.working("driving_range") and int(others.get("range", 0)) < maxi(1, roundi(range_capacity * minf(business.traffic_multiplier(), 1.0))):
		kinds.append("range")
	if business.working("short_game") and _fac("short_game") != null and int(others.get("short", 0)) < 1:
		kinds.append("short")
	if not kinds.is_empty():
		_new_arrival(0, kinds[_rng.randi() % kinds.size()])
		_spawn_wait = _arrival_interval()


## Choose between the two legal starting tees. Both busy: join a tee's queue and wait.
func _starting_hole() -> int:
	var starts: Array = [0, 9] if course.holes.size() > 9 else [0]
	var best := 0
	var least := 2147483647
	for hole: int in starts:
		var waiting := 0
		for other: Group in _groups:
			if other.visit == "" and other.hole == hole and (not other.tee_started or other.stop == 0):
				waiting += 1
		if waiting < least:
			least = waiting
			best = hole
	return best


## A new round starts at a legal tee and queues there. Never seed golfers mid-hole.
func _new_group(hole: int, _mid_round: bool, ride_choice: int = -1, size: int = 0, bags: bool = true) -> Group:
	var g := Group.new()
	g.start_hole = 9 if hole == 9 and course.holes.size() > 9 else 0
	g.hole = g.start_hole
	g.holes_left = course.holes.size()
	var share := float(business.rates().get("cart_share", 0.0))
	var ride := (_rng.randf() < share if ride_choice < 0 else ride_choice == 1) and _scene(CART) != null
	var n := 2 if ride and _rng.randf() < 0.5 else _rng.randi_range(2, MAX_FLIGHT_SIZE)
	if size > 0:
		n = size
	for k in range(n):
		var w := _person("golfer_" + LOOKS[_rng.randi() % LOOKS.size()])
		if w == null:
			continue
		g.golfers.append(w)
		if not ride and bags:
			_carry_bag(w)
	if g.golfers.is_empty():
		return null
	_plan_hole(g)
	var at: Vector2 = g.stops[g.stop]
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		var p := at + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
		w.node.global_position = Vector3(p.x, _ground_y(p), p.y)
	if ride:
		for k in range(ceili(g.golfers.size() / 2.0)):
			var c := _cart()
			c.speed = RIDE
			c.ground = true
			var p := _safe_point(at + Vector2(18 + k * 5.0, 6), true)
			if p == Vector2.INF:
				c.node.queue_free()
				continue
			c.node.global_position = Vector3(p.x, _ground_y(p), p.y)
			for b in range(2):
				_cart_bag(c, b)
			g.carts.append(c)
			_invalidate_traffic()
	_groups.append(g)
	_invalidate_traffic()
	g.hole_reserved = false
	g.phase = "tee_queue"
	return g


## The stops on the group's hole: the tee, a fairway stop or two by its length, the pin.
func _plan_hole(g: Group) -> void:
	var route := course.hole_route(g.hole, 5.0)
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i].distance_to(route[i - 1])
	var par := course.hole_par(g.hole)
	var along: Array = [0.0]
	if par >= 5:
		along += [minf(240.0, total * 0.45), total * 0.78]
	elif par == 4:
		along.append(minf(235.0, total * 0.62))
	g.stops = []
	for d in along:
		g.stops.append(_point_along(route, d))
	g.stops.append(course.holes[g.hole]["pin"])
	g.stop = 0
	g.ball_positions.clear()
	g.strokes.clear()
	g.holed.clear()
	for k in range(g.golfers.size()):
		var p: Vector2 = g.stops[0]  # each tees off from the same spot, in turn
		g.ball_positions.append(p)
		g.strokes.append(0)
		g.holed.append(false)
		if g.balls.size() <= k:
			var ball := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = .045
			mesh.height = .09
			mesh.radial_segments = 8
			mesh.rings = 4
			ball.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.WHITE
			ball.material_override = mat
			add_child(ball)
			g.balls.append(ball)
		g.balls[k].position = Vector3(p.x, _ground_y(p) + .045, p.y)
		g.balls[k].visible = false  # teed up when its golfer steps up


static func _point_along(route: PackedVector2Array, d: float) -> Vector2:
	var left := d
	for i in range(1, route.size()):
		var seg := route[i].distance_to(route[i - 1])
		if left <= seg:
			return route[i - 1].lerp(route[i], left / maxf(seg, 0.001))
		left -= seg
	return route[route.size() - 1]


## Where golfer `k` plays from at the group's stop: the tee one at a time (the others wait back
## from it), spread on the fairway, round the hole on the green.
func _ball_spot(g: Group, k: int) -> Vector2:
	if k < g.holed.size() and g.holed[k]:
		# Finished players wait separately off the cup while their flight puts out.
		var pin: Vector2 = g.stops[g.stops.size() - 1]
		var angle := TAU * k / maxf(g.golfers.size(), 1) + float(g.hole)
		return _open_spot(pin + Vector2.from_angle(angle) * 3.5)
	_recover_lie(g, k)
	if g.stop == 0 and k < g.strokes.size() and g.strokes[k] == 0:
		return _tee_wait(g, k)
	if k < g.ball_positions.size():
		return _address_spot(g.ball_positions[k], _target(g), _putting(g, k))
	var at: Vector2 = g.stops[g.stop]
	var on_green := g.stop == g.stops.size() - 1
	var next := _target(g)
	var d := (next - at).normalized() if next != at else Vector2.UP
	var side := Vector2(d.y, -d.x)
	if on_green:
		var ang := float(k) / maxf(g.golfers.size(), 1) * TAU + float(g.hole)
		return at + Vector2.from_angle(ang) * (2.5 + k * 1.3)
	if g.stop == 0:
		return at + side * (k - (g.golfers.size() - 1) * 0.5) * 2.4
	return at + side * ((k - (g.golfers.size() - 1) * 0.5) * 7.0 + _rng.randf_range(-3, 3)) + d * _rng.randf_range(-8, 8)


## Where golfer `k` waits their turn on the tee: a few metres back from the box, side by side.
func _tee_wait(g: Group, k: int) -> Vector2:
	var at: Vector2 = g.stops[0]
	var next := _target(g)
	var d := (next - at).normalized() if next != at else Vector2.UP
	return at - d * 6.0 + Vector2(d.y, -d.x) * (k - (g.golfers.size() - 1) * 0.5) * 1.5


## On the tee, one golfer at a time: the next tees up and steps in from where the flight waits.
func _step_up(g: Group) -> void:
	_recover_lie(g, g.turn)
	for k in range(g.balls.size()):
		if g.strokes[k] == 0: g.balls[k].visible = false
	_to_stance(g.golfers[g.turn], g.ball_positions[g.turn], _target(g), false)
	for k in range(g.golfers.size()):
		if k != g.turn and not (g.golfers[k] as Walker).riding:
			(g.golfers[k] as Walker).data["watch"] = g.ball_positions[g.turn]
	g.phase = "step_up"


## `w` into their stance at `ball` for a shot toward `target`, turned square to the line as they get
## there (not still facing the way they walked in, or toward a ball they were watching).
func _to_stance(w: Walker, ball: Vector2, target: Vector2, putt: bool) -> void:
	w.data.erase("watch")
	if not _dry_footing(ball, 1.2): ball = _drop_dry(ball, ball, target)
	var stance := _address_spot(ball, target, putt)
	if Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(stance) > 0.25:
		_go(w, stance)
		w.data["arrive_yaw"] = _shot_basis(target - ball).get_euler().y
	else:
		w.node.rotation.y = _shot_basis(target - ball).get_euler().y


## What the group is playing toward from its stop: the next stop, or the pin on the green.
func _target(g: Group) -> Vector2:
	return g.stops[mini(g.stop + 1, g.stops.size() - 1)]


func _go_play(g: Group) -> void:
	if not g.carts.is_empty():
		# ride there: everyone in the carts, the carts to the side of the stop
		for k in range(g.golfers.size()):
			var c: Walker = g.carts[k / 2]
			if not (g.golfers[k] as Walker).riding:
				_seat(g.golfers[k], c, k % 2)
		var at: Vector2 = g.stops[g.stop]
		var nxt := _target(g)
		var d := (nxt - at).normalized() if nxt != at else Vector2.UP
		for ci in range(g.carts.size()):
			var c: Walker = g.carts[ci]
			var offset := 10.0 if g.stop == 0 else 18.0
			var park := _cart_parking_point(at + Vector2(d.y, -d.x) * (offset + ci * 5.0) - d * 4.0, c)
			if park != Vector2.INF:
				_go(c, park)
			else:
				c.data["blocked"] = true
		_stagger(g)
	else:
		for k in range(g.golfers.size()):
			var p := _ball_spot(g, k)
			var w: Walker = g.golfers[k]
			_bag_up(w)
			_go(w, p)
			w.data["hold"] = _rng.randf_range(0.0, 0.6)
			w.speed = WALK * _rng.randf_range(0.9, 1.1)
			w.rest = "idle"
	g.phase = "travel"


func _moving(list: Array) -> bool:
	for w in list:
		if not (w as Walker).path.is_empty() or w.data.get("blocked", false) or w.data.has("rack_delivery"):
			return true
	return false


func _step_group(g: Group, delta: float) -> void:
	if g.wait_practice: g.wait_practice_elapsed += delta
	if not g.flight.is_empty():
		g.flight["time"] += delta
		var t := clampf(float(g.flight["time"]) / float(g.flight["duration"]), 0.0, 1.0)
		var curve: Vector3 = g.flight.get("curve", Vector3.ZERO)
		(g.balls[g.flight["golfer"]] as Node3D).position = _ball_at(g.flight["from"], g.flight["to"], float(g.flight["arc"]), t) + curve * (sin(PI * t / 0.62) if t < 0.62 else 0.0)
		if t >= 1.0:
			if g.flight.has("drop"):
				(g.balls[g.flight["golfer"]] as Node3D).position = g.flight["drop"]
			if g.holed[g.flight["golfer"]]:
				(g.balls[g.flight["golfer"]] as Node3D).visible = false  # dropped: in the cup, out of sight
			g.flight.clear()
	if g.car != null:
		_step(g.car, delta)
	var hurry := _marshal_pace()
	for w in g.golfers:
		(w as Walker).data["hurry"] = hurry
		if (w as Walker).data.has("cart_move"):
			_cart_move_step(w, delta)
		elif not (w as Walker).riding:
			_step(w, delta)
	_ease_apart(g, delta)
	if g.phase in ["short_walk","short_practice","short_exit"]:
		for golfer:Walker in g.golfers:_ground_practice(golfer)
	for c in g.carts:
		(c as Walker).data["hurry"] = hurry
		_step(c, delta)
	_valet_hand_back(g)
	_valet_service_step(g,delta)
	if _visit_phase(g, delta):
		return
	match g.phase:
		"travel":
			for c in g.carts:
				if c.data.get("blocked", false):
					g.retry -= delta
					if g.retry <= 0:
						g.retry = 10.0
						_go_play(g)
					return
			if _moving(g.golfers) or _moving(g.carts):
				return
			if not g.carts.is_empty() and g.stop == 0:
				# at the tee with the flight ahead still in reach: most sit on in the carts till it's
				# out of it, rather than out and standing about the tee box
				if g.sit_tight_hole != g.hole:
					g.sit_tight_hole = g.hole
					g.sit_tight = _rng.randf() < 0.8
				if g.sit_tight and _flight_ahead(g):
					return
			if not g.carts.is_empty():
				# out of the carts and over to the balls: the drivers first, their passengers a
				# moment after
				for k in range(g.golfers.size()):
					(g.golfers[k] as Walker).data["unseat_in"] = _rng.randf_range(0.0, 0.3) if k % 2 == 0 else _rng.randf_range(0.6, 1.2)
				g.phase = "dismount"
			else:
				_begin_shots(g)
		"dismount":
			var seated := false
			for k in range(g.golfers.size()):
				var w: Walker = g.golfers[k]
				if not w.riding:
					continue
				w.data["unseat_in"] = float(w.data.get("unseat_in", 0.0)) - delta
				if w.data.has("cart_move"):
					seated = true  # (climbing out)
				elif float(w.data["unseat_in"]) <= 0.0:
					_climb_out(w, g.carts[k / 2], k % 2)
					seated = seated or w.riding
					if not w.riding:
						w.data.erase("climbed_out")
						_go(w, _ball_spot(g, k))
				else:
					seated = true
			for k in range(g.golfers.size()):
				var w: Walker = g.golfers[k]
				if w.data.get("climbed_out", false):
					w.data.erase("climbed_out")  # (out by the clip just now: over to the ball)
					_go(w, _ball_spot(g, k))
			if not seated and not _moving(g.golfers):
				_begin_shots(g)
		"tee_ready":
			if not _moving(g.golfers) and not _flight_ahead(g):
				_step_up(g)
		"ready":
			if not _moving(g.golfers) and not _flight_ahead(g):
				g.phase = "play"
				_shot(g)
		"putt_walk":
			if not _moving(g.golfers):
				_begin_shots(g)
		"play":
			g.timer -= delta
			if g.timer > 0.0:
				return
			g.turn += 1
			if g.stop == 0 and g.turn < g.golfers.size():
				# off the tee before the next one steps up
				_go(g.golfers[g.turn - 1], _tee_wait(g, g.turn - 1))
				g.phase = "step_off"
				return
			if g.turn < g.golfers.size():
				_ready_up(g)
				return
			if g.stop == 0 and g.carts.is_empty():
				_go(g.golfers[g.turn - 1], _tee_wait(g, g.turn - 1))
				g.phase = "tee_done"
				return
			_after_stop(g)
		"tee_done":
			if not _moving([g.golfers[g.turn - 1]]):
				_after_stop(g)
		"step_off":
			if not _moving([g.golfers[g.turn - 1]]):
				g.phase = "tee_ready"
		"step_up":
			if not _moving([g.golfers[g.turn]]) and not _flight_ahead(g):
				g.balls[g.turn].visible = true
				g.phase = "play"
				_shot(g)
		"mount":
			if not _board_arrivals(g, delta):
				return
			_next_stop(g)
		"bags_up":
			if _moving(g.golfers):
				g.timer = 0.6  # a beat at the bag, turned to it, before shouldering it
				return
			g.timer -= delta
			if g.timer > 0.0:
				return
			for w: Walker in g.golfers:
				_bag_up(w)
				w.data.erase("watch")
			_next_stop(g)


func _begin_shots(g: Group) -> void:
	for w in g.golfers:
		_bag_down(w)
	g.turn = 0
	if g.stop == 0:
		# The tee is ours, but the group ahead may still be inside shot range.
		g.phase = "tee_ready"
		return
	_ready_up(g)


## Before a shot: the player walks into their stance (if they aren't in it); anyone standing in
## front of them -- before their face, or out along the line of the shot -- steps round behind
## their back; and everyone else turns to watch the ball.
func _ready_up(g: Group) -> void:
	while g.turn < g.golfers.size() and g.holed[g.turn]:
		g.turn += 1
	if g.turn >= g.golfers.size():
		_after_stop(g)
		return
	var w: Walker = g.golfers[g.turn]
	var on_green := g.stop == g.stops.size() - 1
	var ball: Vector2 = g.ball_positions[g.turn]
	var tgt := _target(g) if not on_green else (g.stops[g.stop] as Vector2)
	var stance := _address_spot(ball, tgt, on_green)
	_to_stance(w, ball, tgt, on_green)
	var aim := (tgt - ball).normalized() if tgt.distance_to(ball) > 0.05 else Vector2.UP
	var face := (ball - stance).normalized()
	var reach := ball.distance_to(tgt)
	var aside := 0
	for k in range(g.golfers.size()):
		var o: Walker = g.golfers[k]
		if k == g.turn or o.riding:
			continue
		var p := Vector2(o.node.global_position.x, o.node.global_position.z)
		if not o.path.is_empty() and o.data.has("outdoor_target"):
			p = o.data["outdoor_target"]  # where they're headed
		if _in_the_way(p, stance, ball, face, aim, reach, on_green):
			_go(o, _open_spot(stance - face * (2.0 if on_green else 3.2) - aim * ((0.6 if on_green else 1.2) + aside * 1.3)))
			aside += 1
		o.data["watch"] = ball
	g.phase = "ready"


## Admission to the tee is separate from permission to hit. The next flight can
## approach once the previous flight has left the box, even while it walks to its balls.
func _tee_entry_blocked(g: Group) -> bool:
	if not g.tee_started and (g.hole != g.start_hole or g.start_hole not in [0, 9]): return true
	for other in _groups:
		if other == g or other.hole != g.hole:
			continue
		if not other.hole_reserved and other.queue_hole == g.hole and other.queue_ticket < g.queue_ticket:
			return true
		if not other.hole_reserved:
			continue
		if other.stop == 0:
			return true # still teeing off, collecting bags or boarding at the tee
		for w: Walker in other.golfers + other.carts:
			if (w.node.visible or w.riding) and Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(g.stops[0]) < 12.0:
				return true # let the last golfer/cart clear the approach
	return false


## Whether a flight further down the hole is still within reach of `g`'s next shot: `g` waits
## for it to move on rather than play into it. The shot onto the green waits only as long as the
## flight ahead is still playing the hole or standing on its green: once they've all holed out
## and stepped off it, on their way to the next tee, it's played.
func _flight_ahead(g: Group) -> bool:
	if not _tee_time_ready(g): return true
	var on_green := g.stop == g.stops.size() - 1
	var approach := g.stop == g.stops.size() - 2
	var from: Vector2 = g.ball_positions[g.turn] if g.turn < g.ball_positions.size() else g.stops[g.stop]
	var land: Vector2 = g.stops[g.stop] if on_green else _target(g)
	for other in _groups:
		if other == g:
			continue
		# Advancing the scorecard does not make a group leaving the green disappear.
		var ahead: bool = other.hole > g.hole or (other.hole == g.hole and other.hole_reserved and other.stop > g.stop)
		if not ahead:
			continue
		if approach and other.hole > g.hole and not _on_green(other, g.stops[g.stops.size() - 1]):
			continue  # done with the hole and off its green
		if _in_reach(g, other, from, land):
			return true
	return false


## Whether any of flight `other` (on foot) is standing on the green round the pin at `pin`.
func _on_green(other: Group, pin: Vector2) -> bool:
	for w: Walker in other.golfers:
		if w.riding or not w.node.visible:
			continue
		var p := Vector2(w.node.global_position.x, w.node.global_position.z)
		if p.distance_to(pin) < 40.0 and course.surface_at(p) == PaintedCourse.Surface.GREEN:
			return true
	return false


## Whether anyone of flight `other` (on foot or in a cart) is within reach of a shot from `from`
## toward `land`: in front of it, no further than the landing spot and 40 m on, and within a wide
## cone of the line.
func _in_reach(_g: Group, other: Group, from: Vector2, land: Vector2) -> bool:
	var aim := (land - from).normalized() if land.distance_to(from) > 0.1 else Vector2.UP
	var reach := from.distance_to(land) + 40.0
	for w: Walker in other.golfers + other.carts:
		if not w.node.visible and not w.riding:
			continue
		var p := Vector2(w.node.global_position.x, w.node.global_position.z) - from
		var along := p.dot(aim)
		if along > -5.0 and p.length() < reach and absf(p.cross(aim)) < maxf(30.0, along * 0.35):
			return true
	return false


## Whether someone at `p` is in front of a player at `stance` -- before their face (the ball
## side) within a few metres, or out along the line of the shot from `ball` toward `aim`.
static func _in_the_way(p: Vector2, stance: Vector2, ball: Vector2, face: Vector2, aim: Vector2, reach: float, putt: bool) -> bool:
	var rel := p - stance
	if rel.dot(face) > 0.0 and rel.length() < (2.5 if putt else 4.0):
		return true
	var along := (p - ball).dot(aim)
	if along > 0.0 and along < reach + (2.0 if putt else 30.0):
		if absf((p - ball).cross(aim)) < (1.0 if putt else maxf(3.0, along * 0.25)):
			return true
	return false


## Where a struck ball is, `t` (0..1) through its shot from `from` to `to` (its rest, `lift` up
## off the ground): up in an arc `arc` m high and down short of it, two bounces, each lower, then
## rolling out and slowing to a stop. With no arc (a putt) it only rolls, slowing.
func _ball_at(from: Vector3, to: Vector3, arc: float, t: float, lift: float = 0.045) -> Vector3:
	var ground := func(q: Vector3) -> Vector3:
		return Vector3(q.x, _surface_y(Vector2(q.x, q.z)) + lift, q.z)
	var slowing := func(u: float) -> float: return 1.0 - (1.0 - u) * (1.0 - u)
	if arc <= 0.0:
		return ground.call(from.lerp(to, slowing.call(t)))
	var land: Vector3 = ground.call(from.lerp(to, 0.85))  # it carries 85% of the way
	var hop1: Vector3 = ground.call(land.lerp(to, 0.45))
	var hop2: Vector3 = ground.call(land.lerp(to, 0.75))
	if t < 0.62:
		var u := t / 0.62
		var p := from.lerp(land, u)
		p.y += sin(u * PI) * arc
		return p
	if t < 0.76:
		var u := (t - 0.62) / 0.14
		var p: Vector3 = ground.call(land.lerp(hop1, u))
		p.y += sin(u * PI) * maxf(arc * 0.1, 0.25)
		return p
	if t < 0.85:
		var u := (t - 0.76) / 0.09
		var p: Vector3 = ground.call(hop1.lerp(hop2, u))
		p.y += sin(u * PI) * maxf(arc * 0.03, 0.08)
		return p
	return ground.call(hop2.lerp(to, slowing.call((t - 0.85) / 0.15)))


## Where golfer `g.turn`'s ball comes to rest instead of `at`, if `at` is on (or touching) another
## of the flight's balls still in play: swung round `around` (the cup, or where they aimed) a bit
## at a time, either way, till it lies clear.
func _clear_lie(g: Group, at: Vector2, around: Vector2) -> Vector2:
	var arm := at - around
	if arm.length() < 0.05:
		arm = Vector2(0.65, 0.0)
	for k in range(9):
		var p := around + arm.rotated((0.0 if k == 0 else (0.45 * ((k + 1) / 2)) * (1.0 if k % 2 == 1 else -1.0)))
		var clear := _dry_footing(p, 1.2)
		for j in range(g.ball_positions.size()):
			if j != g.turn and not g.holed[j] and (g.ball_positions[j] as Vector2).distance_to(p) < 0.3:
				clear = false
				break
		if clear:
			return p
	return at


## Golfer `g.turn` plays: square to the target with it off their left, a swing (or a putt).
func _dry_footing(at: Vector2, margin: float = 1.2) -> bool:
	var layer := course.layer_a()
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-0.7,-0.7), Vector2(0.7,-0.7), Vector2(-0.7,0.7), Vector2(0.7,0.7)]:
		var p := at + offset * margin
		if not course.in_canvas(p) or course.surface_nearest(p, layer) in [PaintedCourse.Surface.WATER, PaintedCourse.Surface.WOODS]: return false
	return true


func _drop_dry(from: Vector2, wet: Vector2, target: Vector2) -> Vector2:
	# Retreat along the shot to the last dry bank, leaving room for both feet.
	for i in range(65):
		var p := wet.lerp(from, float(i) / 64.0)
		if _dry_footing(p, 1.5): return p
	var best := Vector2.INF
	var cost := INF
	for radius in range(2, 42, 2):
		for i in range(24):
			var p := from + Vector2.from_angle(i * TAU / 24.0) * radius
			if not _dry_footing(p, 1.5): continue
			var score := from.distance_to(p) + maxf(0.0, from.distance_to(target) - p.distance_to(target)) * 4.0
			if score < cost: best = p; cost = score
		if best != Vector2.INF: return best
	return from


func _recover_lie(g: Group, k: int) -> void:
	if k >= g.ball_positions.size() or g.holed[k]: return
	var p: Vector2 = g.ball_positions[k]
	if not _dry_footing(p, 1.2):
		g.ball_positions[k] = _drop_dry(p, p, _target(g))
		g.strokes[k] += 1
		if k < g.balls.size():
			var dry: Vector2 = g.ball_positions[k]
			g.balls[k].position = Vector3(dry.x, _ground_y(dry) + .045, dry.y)


func _putting(g: Group, k: int) -> bool:
	if g.stop != g.stops.size() - 1 or k >= g.ball_positions.size(): return false
	var p: Vector2 = g.ball_positions[k]
	var distance := p.distance_to(g.stops[g.stop])
	return distance < 1.2 or (distance < 35.0 and course.surface_nearest(p, course.layer_a()) == PaintedCourse.Surface.GREEN)


## Choose a reachable landing area and a useful curve, considering dispersion,
## the run-out, trees, and the danger on either side of the intended landing.
func _shot_choice(w: Walker, from: Vector2, target: Vector2) -> Dictionary:
	if not w.data.has("skill"):
		w.data["skill"] = _rng.randf()
		w.data["shape"] = _rng.randf_range(-1.0, 1.0)
	var skill := float(w.data["skill"])
	var reach := minf(from.distance_to(target), lerpf(175.0, 255.0, skill))
	var dir := (target - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var layer := course.layer_a()
	var best := {"target": target, "curve": Vector2.ZERO, "strategy": "straight"}
	var least := INF
	for fraction: float in [1.0, 0.82, 0.65]:
		for lateral: float in [-1.0, 0.0, 1.0]:
			var landing := from + dir * reach * fraction + side * lateral * minf(16.0, reach * .08)
			if not _dry_footing(landing, 1.5): continue
			for shape: float in [-1.0, 0.0, 1.0]:
				if shape != 0.0 and (skill < .45 or reach < 45): continue
				var curve := side * shape * minf(16.0, reach * .075) * skill
				var cost := landing.distance_to(target) + absf(shape) * 2.0
				var surface := course.surface_nearest(landing, layer)
				cost += 18.0 if surface == PaintedCourse.Surface.BUNKER else (5.0 if surface == PaintedCourse.Surface.ROUGH else 0.0)
				var spread := lerpf(12.0, 3.0, skill) * minf(reach / 180.0, 1.0)
				for offset in [side * spread, -side * spread, dir * spread, -dir * spread]:
					if not _dry_footing(landing + offset, .7): cost += 95.0
				for i in range(1, 8):
					var t := i / 8.0
					var p := from.lerp(landing, t) + curve * sin(PI * t)
					var crossed := course.surface_nearest(p, layer)
					if crossed == PaintedCourse.Surface.WOODS: cost += 75.0
					if t >= .85 and crossed == PaintedCourse.Surface.WATER: cost += 120.0
				if cost < least:
					least = cost
					best = {"target": landing, "curve": curve, "strategy": "layup" if fraction < 1.0 else ("fade" if shape > 0 else ("draw" if shape < 0 else "straight"))}
	if least == INF: best["target"] = _drop_dry(from, from + dir * reach * .5, target)
	w.data["shot_choice"] = best
	return best


func _shot(g: Group) -> void:
	if not _record_tee_start(g): return
	_recover_lie(g, g.turn)
	var w: Walker = g.golfers[g.turn]
	var on_green := _putting(g, g.turn)
	var tgt := _target(g) if not on_green else (g.stops[g.stop] as Vector2)
	var ball_from: Vector2 = g.ball_positions[g.turn]
	var choice := {"target": tgt, "curve": Vector2.ZERO}
	if not on_green:
		choice = _shot_choice(w, ball_from, tgt)
		tgt = choice["target"]
	var chip := not on_green and ball_from.distance_to(tgt) < CHIP_RANGE and w.anim != null and w.anim.has_animation("chip")
	var anim_name := "putt" if on_green else ("chip" if chip else "swing")
	var impact := float(IMPACTS[anim_name])
	_address_ball(w, Vector3(ball_from.x, _ground_y(ball_from) + .045, ball_from.y), tgt - ball_from + (choice["curve"] as Vector2) * PI, on_green, chip)
	var ball_to := tgt
	var landing := tgt
	var penalty := false
	if on_green:
		var distance := ball_from.distance_to(tgt)
		ball_to = tgt if distance < 1.2 else tgt + (ball_from - tgt).normalized() * .65
		g.holed[g.turn] = ball_to.distance_to(tgt) < .1
	else:
		# where it goes: off line and long or short by the golfer's own game (an approach a touch
		# tighter than a drive)
		ball_to = ball_from + _miss(w, tgt - ball_from, 0.6 if g.stop == g.stops.size() - 2 else 1.0)
		landing = ball_to
		if not _dry_footing(ball_to, 1.2):
			penalty = true
			g.strokes[g.turn] += 1
			ball_to = _drop_dry(ball_from, ball_to, _target(g))
		if g.stop == g.stops.size() - 1 and ball_to.distance_to(g.stops[g.stop]) < .25: g.holed[g.turn] = true
	if not g.holed[g.turn]:
		ball_to = _clear_lie(g, ball_to, tgt)  # never on top of another's ball
	g.strokes[g.turn] += 1
	g.ball_positions[g.turn] = ball_to
	(g.balls[g.turn] as Node3D).visible = true
	var air := 1.8 if on_green else 3.0  # in the air, bouncing and rolling out (a putt: rolling)
	if chip:
		air = 2.2  # (up, down on the green and running out)
	g.flight = {"golfer": g.turn, "time": -impact, "duration": air, "from": Vector3(ball_from.x, _ground_y(ball_from) + .045, ball_from.y), "to": Vector3(ball_to.x, _ground_y(ball_to) + .045, ball_to.y), "arc": 0.0 if on_green else minf(ball_from.distance_to(ball_to) * .16, 25.0)}
	if not on_green:
		var curve: Vector2 = choice["curve"]
		g.flight["curve"] = Vector3(curve.x, 0, curve.y)
	if penalty:
		g.flight["drop"] = g.flight["to"]
		g.flight["to"] = Vector3(landing.x, _ground_y(landing) + .045, landing.y)
	if w.anim != null and w.anim.has_animation(anim_name):
		if w.data.has("held_club"):
			w.data["held_club"].visible = true
		w.anim.play(anim_name, 0)
	# Finish the flight before the next golfer can replace its active ball flight.
	g.timer = maxf((PUTT_S if on_green else (CHIP_S if chip else SWING_S)), impact + air + .2)
	for o in g.golfers:
		if o != w:
			_play(o, "idle")


## Where golfer `w`'s shot meant to go `aim` (from the ball) actually goes, from the ball: off
## line by their own game -- a miss of their own (a fade or a draw) and a spread about it, the
## weaker the player the wider -- and long or short; `tight` scales the spread (an approach).
func _miss(w: Walker, aim: Vector2, tight: float = 1.0) -> Vector2:
	if not w.data.has("skill"):
		w.data["skill"] = _rng.randf()  # 0: a hacker, 1: scratch
		w.data["shape"] = _rng.randf_range(-1.0, 1.0)  # which way and how much they tend to miss
	var skill := float(w.data["skill"])
	var off := deg_to_rad(float(w.data["shape"]) * lerpf(6.0, 1.0, skill) + _rng.randfn(0.0, lerpf(9.0, 2.5, skill) * tight))
	var long := 1.0 + _rng.randfn(0.0, lerpf(0.12, 0.04, skill) * tight)
	return aim.rotated(off) * maxf(long, 0.5)


func _after_stop(g: Group) -> void:
	if g.stop == g.stops.size() - 1 and g.holed.has(false):
		for k in range(g.golfers.size()):
			_go(g.golfers[k], _ball_spot(g, k))  # their bags stay where they set them, off the green
		g.phase = "putt_walk"
		return
	for w in g.golfers:
		_play(w, "idle")
	if not g.carts.is_empty():
		# back to the carts, each to their own side of it (and round it, not through it)
		for k in range(g.golfers.size()):
			var at := _cart_door(g.carts[k / 2], k % 2)
			_go(g.golfers[k], Vector2(at.x, at.z))
		g.phase = "mount"
	elif _to_bags(g):
		g.phase = "bags_up"  # on foot: back to their bags first, to pick them up
	else:
		_next_stop(g)


## Each walker whose bag stands more than a step away goes over to it (and turns to it); false
## when every bag is already at hand.
func _to_bags(g: Group) -> bool:
	var any := false
	for w: Walker in g.golfers:
		var stand: Variant = w.data.get("bag_down")
		if stand == null or not is_instance_valid(stand):
			continue
		var s := Vector2((stand as Node3D).global_position.x, (stand as Node3D).global_position.z)
		var here := Vector2(w.node.global_position.x, w.node.global_position.z)
		if here.distance_to(s) < 1.2:
			continue
		_go(w, _open_spot(s + (here - s).normalized() * 0.7))
		w.data["watch"] = s
		w.data["hold"] = _rng.randf_range(0.0, 0.6)
		any = true
	return any


func _next_stop(g: Group) -> void:
	if g.stop == g.stops.size() - 1:
		if g.holed.has(false):
			return
		g.scores.append({"hole": g.hole + 1, "strokes": g.strokes.duplicate()})
	g.stop += 1
	if g.stop >= g.stops.size():
		g.holes_left -= 1
		if g.holes_left <= 0:
			_begin_departure(g)
			return
		g.hole = (g.hole + 1) % course.holes.size()
		_plan_hole(g)
		g.hole_reserved = false
		g.queue_hole = -1
		g.phase = "tee_queue"
		return
	_go_play(g)


func _free_group(g: Group) -> void:
	_invalidate_traffic()
	_valet_release(g)
	_clear_practice(g)
	_bag_runs = _bag_runs.filter(func(run: Array) -> bool: return run[0] != g)
	for c: Walker in g.carts:
		_bag_run_let_go(c)  # (the cart boy out of it first: it goes with them)
	for w: Walker in g.golfers:
		if w.data.has("place"):
			_guest_places.erase(w.data["place"]["key"])
	for ball in g.balls:
		if is_instance_valid(ball):
			ball.queue_free()
	if g.car != null and is_instance_valid(g.car.node):
		g.car.node.queue_free()
	for w in g.golfers:
		var stand: Variant = (w as Walker).data.get("bag_down")
		if stand != null and is_instance_valid(stand):
			(stand as Node).queue_free()  # set down on the ground, not on them
		if is_instance_valid((w as Walker).node):
			(w as Walker).node.queue_free()
	for c in g.carts:
		if is_instance_valid((c as Walker).node):
			(c as Walker).node.queue_free()


# ================================================================ bags

## Visitors enter through the parking drive, check in, collect carts, and queue for tee one.
## Just outside `type`'s way in, on open ground: its front (-Z: the clubhouse's fountain side,
## the barn's bays); the range and the short game area are walked into from behind (+Z).
func _facility_front(type: String) -> Vector2:
	var fac := _fac(type)
	if fac == null:
		return Vector2.INF
	var side := 1.0 if type in ["driving_range", "short_game"] else -1.0
	var p := fac.global_transform * Vector3(0, 0, side * (FacilityBuilder.footprint(type).y * .5 + 5.0))
	return _safe_point(Vector2(p.x, p.z))


func _clubhouse_entry() -> Vector2:
	var house:=_fac("clubhouse")
	if house==null:return Vector2.INF
	var door:=_front_door(house)
	if door==Vector2.INF:return _facility_front("clubhouse")
	var world:=house.global_transform*Vector3(door.x,0,door.y-2.2)
	return Vector2(world.x,world.z)


## Someone driving in: a flight for a round of golf, or (`visit`) one or two in for the gym
## ("gym": a member, no golf bag), the driving range ("range") or the short game area ("short").
func _new_arrival(ride_choice: int = -1, visit: String = "") -> Group:
	var house := _fac("clubhouse")
	if house == null:
		return null
	if visit != "":
		ride_choice = 0  # (no carts: they're not going out on the course)
	if ride_choice < 0:
		var share := float(business.rates().get("cart_share", 0.0))
		_cart_arrival_credit += share
		ride_choice = 1 if _cart_arrival_credit >= 1.0 else 0
		if ride_choice == 1:
			_cart_arrival_credit -= 1.0
	var slot := 0
	while true:
		var occupied := false
		for other in _groups:
			occupied = occupied or other.parking_slot == slot
		if not occupied:
			break
		slot += 1
	var lot := _fac("parking_lot")
	var stall := _choose_stall(lot) if lot != null else -1
	var visiting_range:=visit=="range" or (visit=="" and business.working("driving_range") and _arrival_serial%3==1)
	var requests_valet:=not visiting_range and business!=null and business.room_tier("valet")>=1 and _rng.randf()<.08
	if stall < 0 and lot != null and not (FacilityBuilder.rig(lot).get("stalls", []) as Array).is_empty() and not (requests_valet and _valet_pocket_available()):
		return null  # the lot's full: they come when a space is free
	var g := _new_group(_starting_hole() if visit == "" else 0, false, ride_choice, 0 if visit == "" else (1 if visit in ["gym", "range", "sim"] else _rng.randi_range(1, 2)), visit not in ["gym", "sim", "bar"])
	if g == null:
		return null
	g.visit = visit
	g.parking_slot = slot
	g.parking_stall = stall
	_mark_stalls()
	g.hole_reserved = false
	g.wants_cart = not g.carts.is_empty()
	g.range_visit = business.working("driving_range") and _arrival_serial % 3 == 1
	g.short_visit = business.working("short_game") and _arrival_serial % 3 == 2
	if visit != "":
		g.range_visit = visit == "range"
		g.short_visit = visit == "short"
	_arrival_serial += 1
	for k in range(g.golfers.size()):
		if (g.golfers[k] as Walker).riding:
			_unseat(g.golfers[k], g.carts[k / 2], k % 2)
	for c in g.carts:
		c.node.queue_free()  # their carts are the club's: off the line behind the clubhouse, or from the barn
	g.carts.clear()
	_invalidate_traffic()
	for w in g.golfers:
		if not w.data.has("bag") and visit not in ["gym", "sim", "bar"]:
			_carry_bag(w)
	for w in g.golfers:
		w.path.clear()
		w.node.visible = false
	for c in g.carts:
		c.path.clear()
		c.node.visible = false
	for ball in g.balls:
		ball.visible = false
	g.car = _visitor_car(slot)
	if stall >= 0:
		# the lot's drives (build_facilities.py): in on the right, out on the left, both from the
		# road at its front (-Z); down the drive in, along the stall's aisle and in nose first,
		# then back out onto the aisle and along it to the drive out
		var level := clampi(business.level("parking_lot"), 1, 4)
		var lane: Array = [[19.6, -19.3], [18.9, -18.9], [27.4, -27.4], [29.3, -29.3]][level - 1]
		var x_in: float = lane[0]
		var x_out: float = lane[1]
		var xf: Transform3D = FacilityBuilder.rig(lot)["stalls"][stall]
		var bay := Vector2(xf.origin.x, xf.origin.z)
		var aisle := FacilityBuilder.stall_mouth(xf).z
		for p in [Vector2(x_in, -38), Vector2(x_in, -24), Vector2(x_in, aisle), Vector2(bay.x, aisle), bay]:
			g.parking_path.append(lot.global_transform * Vector3(p.x, .10, p.y))
		var exits:Array=FacilityBuilder.rig(lot).get("side_exits",[])
		if level>=2 and aisle>0 and not exits.is_empty():
			var side_exit:Vector3=(exits[0] as Transform3D).origin
			for p in [bay,Vector2(bay.x,aisle),Vector2(side_exit.x,aisle),Vector2(-42,aisle)]:
				g.exit_path.append(lot.global_transform*Vector3(p.x,.10,p.y))
		else:
			for p in [bay, Vector2(bay.x, aisle), Vector2(x_out, aisle), Vector2(x_out, -24), Vector2(x_out, -38)]:
				g.exit_path.append(lot.global_transform * Vector3(p.x, .10, p.y))
	else:
		var p := _facility_front("clubhouse")
		for offset in [Vector2(30, 12), Vector2(12 + slot * 2.8, 5)]:
			var point := _safe_point(p + offset, true)
			if point == Vector2.INF:
				point = p
			g.parking_path.append(Vector3(point.x, _ground_y(point), point.y))
	if g.exit_path.is_empty():
		g.exit_path = g.parking_path.duplicate()
		g.exit_path.reverse()
	g.car.node.position = g.parking_path[0]
	g.car.path = g.parking_path.slice(1)
	g.phase = "arrive"
	_valet_offer(g,requests_valet)
	return g


## The stall a golfer arriving by car takes: a free one (FacilityBuilder.stall_free: no car
## parked in it, no other golfer's, not an accessible space) close to the clubhouse's front door.
## While the lot's under 50% full they leave a space beside them if they can: a car either side
## counts as 25 m more walk. Nobody picks quite the same (a few metres' whim). -1: no space.
func _choose_stall(lot: Node3D) -> int:
	var r := FacilityBuilder.rig(lot)
	var stalls: Array = r.get("stalls", [])
	var ada := FacilityBuilder.ada_stalls(r)
	var spaces := stalls.size() - ada.size()
	if spaces <= 0:
		return -1
	var used := 0
	for i in range(stalls.size()):
		if not ada.has(i) and not FacilityBuilder.stall_free(r, i): used += 1
	var roomy := used * 2 < spaces
	var door := _clubhouse_entry()
	var best := -1
	var least := INF
	for i in range(stalls.size()):
		if not FacilityBuilder.stall_free(r, i):
			continue
		var a: Transform3D = stalls[i]
		var at := lot.global_transform * a.origin
		var cost := Vector2(at.x, at.z).distance_to(door) if door != Vector2.INF else 0.0
		if roomy:
			for j in range(stalls.size()):
				var b: Transform3D = stalls[j]
				if j != i and not ada.has(j) and not FacilityBuilder.stall_free(r, j) 						and a.origin.distance_to(b.origin) < 3.2 and a.basis.z.dot(b.basis.z) > 0.9:
					cost += 25.0  # a car in the stall beside it
		cost += randf() * 4.0
		if cost < least:
			least = cost
			best = i
	return best


## The lot's stalls golfers' cars are in or on their way to, for park() to leave be.
func _mark_stalls() -> void:
	_marked = _groups.size()
	var lot := _fac("parking_lot")
	if lot == null:
		return
	var taken := {}
	for g: Group in _groups:
		if g.parking_stall >= 0:
			taken[g.parking_stall] = true
	FacilityBuilder.rig(lot)["taken"] = taken


## A visitor's car: one of the user's car pack (FacilityBuilder.CARS), front to -Z like the carts.
func _visitor_car(index: int) -> Walker:
	var car := Walker.new()
	var v: String = FacilityBuilder.CARS[(index * 3 + _arrival_serial) % FacilityBuilder.CARS.size()]
	var scene := _scene(FacilityBuilder.CAR_SCENE % v)
	car.node = scene.instantiate() as Node3D if scene != null else Node3D.new()
	car.node.name = "VisitorCar"
	# in a paint of its own (any model in any of the paints)
	var mesh := FacilityBuilder.car_mesh(v)
	for mi in car.node.find_children("*", "MeshInstance3D", true, false):
		if mesh != null:
			(mi as MeshInstance3D).mesh = mesh
			var c := FacilityBuilder.car_paint(v, _rng.randi())
			(mi as MeshInstance3D).set_instance_shader_parameter("paint", Color(c.r, c.g, c.b, 1.0))
		break
	add_child(car.node)
	car.speed = 5.0
	car.data["vehicle"] = true
	car.data["model"] = v
	return car


func _guest_nav(house: Node3D) -> Dictionary:
	var rig := FacilityBuilder.rig(house)
	if not rig["nav"].has("guest"):
		var parts: Array = []
		parts.append_array(rig["groups"].get("WALLS_HIGH", []))
		parts.append_array(rig["rooms"].values())
		var fp := FacilityBuilder.footprint("clubhouse")
		# round the grounds' keep-outs too (the monument, the fountain's island, the flag island)
		rig["nav"]["guest"] = FacilityBuilder._nav_grid(Rect2(-fp*.5-Vector2.ONE*6, fp+Vector2.ONE*12), .6, parts, .2, rig["blockers"].get("", []), .3, 2.0)
		var grid: AStarGrid2D = rig["nav"]["guest"]["astar"]
		for door: Transform3D in rig.get("doors", []):
			var width := door.basis.get_scale().x
			var frame := Transform3D(door.basis.orthonormalized(), door.origin)
			var cell_size := grid.cell_size.x
			for along in range(-ceili(width/(2*cell_size)), ceili(width/(2*cell_size))+1):
				for depth in range(-ceili(1.6/cell_size),ceili(1.6/cell_size)+1):
					var p := frame * Vector3(clampf(along*cell_size, -width*.5+.12, width*.5-.12), 0, depth*cell_size)
					var cell := Vector2i(floori((p.x-grid.offset.x)/grid.cell_size.x+.5),floori((p.z-grid.offset.y)/grid.cell_size.y+.5))
					if grid.region.has_point(cell):
						grid.set_point_solid(cell,false)
	return rig["nav"]["guest"]


func _indoor_guest_nav(house: Node3D) -> void:
	var rig:=FacilityBuilder.rig(house)
	if rig["nav"].has("indoor_guest"):return
	var source:=_guest_nav(house)
	var old:AStarGrid2D=source["astar"]
	var grid:=AStarGrid2D.new();grid.region=old.region;grid.offset=old.offset;grid.cell_size=old.cell_size;grid.diagonal_mode=old.diagonal_mode;grid.update()
	var level:int=rig["level"]
	var floors:Array=[]
	match level:
		1:floors=[Rect2(-8,14,16,10)]
		2:floors=[Rect2(-18,15,36,12),Rect2(18,17,8,9)]
		3:floors=[Rect2(-22,14,44,14),Rect2(-6.5,10,13,4),Rect2(-30,15,8,11)]
		4:floors=[Rect2(-30,14,60,15),Rect2(-7,10.5,14,3.5),Rect2(-40,15,10,13),Rect2(30,15,10,13)]
	for z in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var cell:=Vector2i(x,z)
			var p:=grid.get_point_position(cell)
			var inside:=false
			for floor_rect:Rect2 in floors:
				if floor_rect.has_point(p):inside=true;break
			grid.set_point_solid(cell,old.is_point_solid(cell) or not inside)
	var nav:Dictionary=source.duplicate();nav["astar"]=grid;rig["nav"]["indoor_guest"]=nav


## The clubhouse's front door (facility XZ): of its doors, the one nearest the middle of its
## plot's front -- the fountain side. INF if it has none.
func _front_door(house: Node3D) -> Vector2:
	var front := Vector2(0, -FacilityBuilder.footprint("clubhouse").y * 0.5)
	var best := Vector2.INF
	for d: Transform3D in FacilityBuilder.rig(house).get("doors", []):
		var p := Vector2(d.origin.x, d.origin.z)
		if best == Vector2.INF or p.distance_to(front) < best.distance_to(front):
			best = p
	return best


func _shop_entry_route(house: Node3D, from: Vector2, to: Vector2) -> PackedVector2Array:
	_indoor_guest_nav(house)
	var rig:=FacilityBuilder.rig(house)
	var box:Dictionary=rig["boxes"].get("pro_shop",{})
	if box.is_empty():return FacilityBuilder.nav_route(house,"indoor_guest",from,to)
	var rect:Rect2=box["rect"]
	var chosen:=Vector2.INF
	var inward:=Vector2.ZERO
	for threshold:Transform3D in rig["doors"]:
		var at:=Vector2(threshold.origin.x,threshold.origin.z)
		var direction:=Vector2.ZERO
		if at.y>=rect.position.y-.3 and at.y<=rect.end.y+.3:
			if absf(at.x-rect.position.x)<.4:direction=Vector2.RIGHT
			elif absf(at.x-rect.end.x)<.4:direction=Vector2.LEFT
		if direction==Vector2.ZERO and at.x>=rect.position.x-.3 and at.x<=rect.end.x+.3:
			if absf(at.y-rect.position.y)<.4:direction=Vector2.DOWN
			elif absf(at.y-rect.end.y)<.4:direction=Vector2.UP
		if direction!=Vector2.ZERO and (chosen==Vector2.INF or at.distance_to(from)<chosen.distance_to(from)):
			chosen=at;inward=direction
	if chosen==Vector2.INF:return FacilityBuilder.nav_route(house,"indoor_guest",from,to)
	var before:=chosen-inward*1.0
	var after:=chosen+inward*1.0
	var approach:=FacilityBuilder.nav_route(house,"indoor_guest",from,before)
	var finish:=FacilityBuilder.nav_route(house,"indoor_guest",after,to)
	if approach.is_empty() or finish.is_empty():return PackedVector2Array()
	approach.append(before);approach.append(chosen);approach.append(after)
	for i in range(1,finish.size()):approach.append(finish[i])
	return approach


## Whether facility-XZ point `p` is on an open cell of walkable grid `nav` (that cell, not the
## nearest open one).
static func _nav_open(nav: Dictionary, p: Vector2) -> bool:
	var grid: AStarGrid2D = nav["astar"]
	var rect: Rect2 = nav["rect"]
	var cell: float = nav["cell"]
	var c := Vector2i(floori((p.x - rect.position.x) / cell), floori((p.y - rect.position.y) / cell))
	return grid.region.has_point(c) and not grid.is_point_solid(c)


## The lobby's queue to check in (facility XZ; worked out once for each clubhouse): "lanes", one
## for each flight waiting -- a single file of MAX_FLIGHT_SIZE places 0.9 m apart ("slots", from
## its head, nearest the way on to the desk, back; "face", the way they stand: up the line),
## along the lobby's length a good pace apart, clear of the way through it and of its doorways;
## "desk", the places at the shop's counter: the first at it, the rest one behind another back
## the way they came; "clerk", where the clerk stands behind it (INF with none); "entry", just
## inside the front door. No lanes without a lobby, a front door or a way on to the desk.
func _lobby_queue(house: Node3D) -> Dictionary:
	var rig := FacilityBuilder.rig(house)
	if rig.has("lobby_queue"):
		return rig["lobby_queue"]
	var out := {"lanes": [], "desk": [], "clerk": Vector2.INF, "entry": Vector2.INF}
	rig["lobby_queue"] = out
	var box: Dictionary = rig["boxes"].get("lobby", {})
	var door := _front_door(house)
	var desk := _desk_spot(house)
	if box.is_empty() or door == Vector2.INF or desk == Vector2.INF:
		return out
	_indoor_guest_nav(house)
	var nav: Dictionary = rig["nav"]["indoor_guest"]
	var lobby: Rect2 = box["rect"]
	var entry := door + Vector2(0, 1.2)  # (the front is -Z: in is +Z)
	var through := _shop_entry_route(house, entry, desk)
	if through.is_empty():
		return out
	out["entry"] = entry
	for spot in rig["spots"].get("pro_shop", []):
		if spot["role"] == "shop_clerk":
			var o: Vector3 = (spot["xf"] as Transform3D).origin
			out["clerk"] = Vector2(o.x, o.z)
	# the way through, every 0.2 m: the heads of the lines are toward where it leaves the lobby
	var steps: Array[Vector2] = []
	for i in range(1, through.size()):
		var n := maxi(1, ceili(through[i - 1].distance_to(through[i]) / 0.2))
		for j in range(n):
			steps.append(through[i - 1].lerp(through[i], float(j) / n))
	steps.append(through[through.size() - 1])
	var head := desk
	var inside := false
	for p in steps:
		if lobby.has_point(p):
			inside = true
		elif inside:
			head = p
			break
	var desk_places: Array = [desk]
	var walked := 0.0
	for i in range(steps.size() - 1, 0, -1):
		walked += steps[i].distance_to(steps[i - 1])
		if walked >= 0.85 * desk_places.size():
			desk_places.append(steps[i - 1])
			if desk_places.size() == MAX_FLIGHT_SIZE:
				break
	out["desk"] = desk_places
	# what to keep clear: the way through, and the lobby's doorways (each a line across its width)
	var near_way: Array[Vector2] = []
	for p in steps:
		if lobby.grow(1.0).has_point(p):
			near_way.append(p)
	var doorways: Array = []
	for d: Transform3D in rig.get("doors", []):
		var half := d.basis.x * 0.5  # (its scale is its width)
		var a := Vector2(d.origin.x - half.x, d.origin.z - half.z)
		var b := Vector2(d.origin.x + half.x, d.origin.z + half.z)
		if lobby.grow(1.5).intersects(Rect2(a, Vector2.ZERO).expand(b)):
			doorways.append([a, b])
	var free := func(p: Vector2) -> bool:
		if not lobby.grow(-0.3).has_point(p) or not _nav_open(nav, p):
			return false
		for q: Vector2 in near_way:
			if q.distance_to(p) < 0.8:
				return false
		for ab: Array in doorways:
			if Geometry2D.get_closest_point_to_segment(p, ab[0], ab[1]).distance_to(p) < 1.0:
				return false
		return true
	# how far each open cell about the lobby is from `head` on foot (in cells): a line's head is
	# its end nearer the way on that way -- not through a wall -- and the nearest lines are first
	var grid: AStarGrid2D = nav["astar"]
	var area := lobby.grow(1.2)
	var start := FacilityBuilder._nav_cell(nav, head)
	var far := {}
	if start.x >= 0:
		far[start] = 0
		var todo: Array[Vector2i] = [start]
		var i := 0
		while i < todo.size():
			var c := todo[i]
			i += 1
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + step
				if far.has(n) or not grid.region.has_point(n) or grid.is_point_solid(n) or not area.has_point(grid.get_point_position(n)):
					continue
				far[n] = int(far[c]) + 1
				todo.append(n)
	var rect: Rect2 = nav["rect"]
	var cell: float = nav["cell"]
	var walk := func(p: Vector2) -> float:
		return float(far.get(Vector2i(floori((p.x - rect.position.x) / cell), floori((p.y - rect.position.y) / cell)), INF))
	# free stretches of each row along the lobby's length, long enough for a full flight
	var along := Vector2.RIGHT if lobby.size.x >= lobby.size.y else Vector2(0, 1)
	var across := Vector2(along.y, along.x)
	var s0 := lobby.position.dot(along) + 0.3
	var s1 := lobby.end.dot(along) - 0.3
	var long := 0.9 * (MAX_FLIGHT_SIZE - 1) + 0.1
	var runs: Array = []  # [its head's walk to `head`, its head, the way back along it, row, from, to]
	var t := lobby.position.dot(across) + 0.4
	while t <= lobby.end.dot(across) - 0.4:
		var from := NAN
		var to := NAN
		var s := s0
		while true:
			var ok: bool = s <= s1 and free.call(along * s + across * t)
			if ok:
				from = s if is_nan(from) else from
				to = s
			elif not is_nan(from):
				var a := along * from + across * t
				var b := along * to + across * t
				var wa: float = walk.call(a)
				var wb: float = walk.call(b)
				if to - from >= long and minf(wa, wb) < INF:
					var first := a if wa <= wb else b
					runs.append([minf(wa, wb), first, (b - a).normalized() * (1.0 if first == a else -1.0), t, from, to])
				from = NAN
			if s > s1:
				break
			s += 0.2
		t += 0.2
	runs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	# the nearest the desk first, each a good pace from any beside it
	var lanes: Array = []
	var used: Array = []  # [row, from, to]
	for r: Array in runs:
		var clash := false
		for u: Array in used:
			clash = clash or (absf(float(r[3]) - float(u[0])) < 1.15 and float(r[4]) < float(u[2]) + 0.5 and float(u[1]) < float(r[5]) + 0.5)
		if clash:
			continue
		var slots: Array = []
		for i in range(MAX_FLIGHT_SIZE):
			slots.append((r[1] as Vector2) + (r[2] as Vector2) * 0.9 * i)
		if FacilityBuilder.nav_route(house, "indoor_guest", entry, slots[slots.size() - 1]).is_empty() or _shop_entry_route(house, r[1], desk).is_empty():
			continue
		used.append([r[3], r[4], r[5]])
		lanes.append({"slots": slots, "face": -(r[2] as Vector2)})
		if lanes.size() == MAX_GROUPS:
			break
	out["lanes"] = lanes
	return out


## A lane in the lobby's queue for flight `g`: the free one nearest the desk. False when the
## lanes are all taken; true, with no lane, at a clubhouse without them (the flight goes up to
## the desk together: _inside_guest).
func _lobby_lane(g: Group) -> bool:
	var house := _fac("clubhouse")
	var lanes: Array = _lobby_queue(house)["lanes"] if house != null else []
	if lanes.is_empty():
		return true
	for i in range(lanes.size()):
		var taken := false
		for other: Group in _groups:
			taken = taken or (other != g and other.lane == i)
		if not taken:
			g.lane = i
			return true
	return false


## Where golfer `k` of a flight walks up to the front door from the car park (world XZ): just
## outside it, the rest of the flight a step apart behind them.
func _door_step(k: int) -> Vector2:
	var house := _fac("clubhouse")
	var entry := _clubhouse_entry()
	if house == null or entry == Vector2.INF:
		return entry
	var out := house.global_transform.basis * Vector3(0, 0, -1)  # (the front is -Z)
	return entry + Vector2(out.x, out.z).normalized() * 0.9 * k


## Each of flight `g` in by the front door as they get up to it -- not waiting outside for the
## rest -- and along to their place in the flight's lane (the first in at its head). True once
## any of them is in.
func _lobby_arrivals(g: Group) -> bool:
	var any := false
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		if w.data.get("self_park_driver",false):continue
		if not w.data.get("lobby", false) and w.path.is_empty() and not w.data.has("rack_delivery"):
			_in_to_lane(g, k)
		any = any or w.data.get("lobby", false)
	return any


## Golfer `k` of `g` from where they stand outside, in by the front door to their place in the
## flight's lane, to stand there in line facing up it. False (nothing changed) with no way.
func _in_to_lane(g: Group, k: int) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	var q := _lobby_queue(house)
	var lanes: Array = q["lanes"]
	if g.lane < 0 or g.lane >= lanes.size():
		return false
	var slots: Array = lanes[g.lane]["slots"]
	var slot: Vector2 = slots[mini(k, slots.size() - 1)]
	var w: Walker = g.golfers[k]
	var here := house.global_transform.affine_inverse() * w.node.global_position
	var guest := _guest_nav(house)
	if w.data.get("blocked", false) and not (guest["rect"] as Rect2).has_point(Vector2(here.x, here.z)):
		return false  # (no way up to the door yet: still trying, from out on the course)
	var door := _front_door(house)
	var up := FacilityBuilder.nav_route(house, "guest", Vector2(here.x, here.z), door + Vector2(0, -1.6))
	var on := FacilityBuilder.nav_route(house, "indoor_guest", q["entry"], slot)
	if up.is_empty() or on.is_empty():
		return false
	var path: Array = []
	for p in up:
		path.append(house.global_transform * Vector3(p.x, 0, p.y))
	for p in on:
		path.append(house.global_transform * Vector3(p.x, 0, p.y))
	var face: Vector2 = lanes[g.lane]["face"]
	var ahead := house.global_transform * Vector3(slot.x + face.x * 2.0, 0, slot.y + face.y * 2.0)
	w.ground = false
	w.data.erase("outdoor_target")
	w.data.erase("indoor_target")
	w.data["blocked"] = false
	w.path = path
	w.data["walk_region"] = {"nav": guest, "xf": house.global_transform}
	w.data["watch"] = Vector2(ahead.x, ahead.z)  # in line, facing up it toward the desk
	w.data["lobby"] = true
	_valet_take(w)  # (their clubs stay outside: the bag drop)
	return true


## Of the flights in line in the lobby, the one whose turn at the desk is next: the first in.
func _next_at_desk() -> Group:
	var best: Group = null
	for g: Group in _groups:
		if g.lobby_ticket >= 0 and g.phase == "lobby" and (best == null or g.lobby_ticket < best.lobby_ticket):
			best = g
	return best


## Whether the shop's counter is free for `g`: no other flight on its way up to it or checking in,
## nor anyone still stood where the flight will stand.
func _desk_free(g: Group) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	var inv := house.global_transform.affine_inverse()
	var places: Array = _lobby_queue(house)["desk"]
	for other: Group in _groups:
		if other == g:
			continue
		if other.phase in ["shop_walk", "check_in"]:
			return false
		for w: Walker in other.golfers:
			if not w.node.visible:
				continue
			var l := inv * w.node.global_position
			for p: Vector2 in places:
				if Vector2(l.x, l.z).distance_to(p) < 0.7:
					return false
	return true


## Flight `g` out of its lane and up to the shop's counter to check in, in single file: the
## first of them at the counter facing the clerk, the rest in line behind. Its lane's free for
## the next flight in. False (nothing changed) with no way there.
func _to_desk(g: Group) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	var q := _lobby_queue(house)
	var places: Array = q["desk"]
	if places.is_empty():
		return false
	var routes: Array = []
	for k in range(g.golfers.size()):
		var here := house.global_transform.affine_inverse() * (g.golfers[k] as Walker).node.global_position
		var pts := _shop_entry_route(house, Vector2(here.x, here.z), places[mini(k, places.size() - 1)])
		if pts.is_empty():
			return false
		var path: Array = []
		for p in pts:
			path.append(house.global_transform * Vector3(p.x, 0, p.y))
		routes.append(path)
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		var look: Vector2 = places[mini(k, places.size() - 1) - 1] if k > 0 and k < places.size() else (q["clerk"] if q["clerk"] != Vector2.INF else places[0])
		var at := house.global_transform * Vector3(look.x, 0, look.y)
		w.data.erase("lobby")
		w.data["blocked"] = false
		w.data["hold"] = k * 0.6
		w.ground = false
		w.path = routes[k]
		w.data["walk_region"] = {"nav": _guest_nav(house), "xf": house.global_transform}
		w.data["watch"] = Vector2(at.x, at.z)  # the clerk, or the back of the one ahead
	g.lane = -1
	g.lobby_ticket = -1
	return true


## Where a flight checks in (facility XZ): at the shop's counter, across it from the clerk's
## place -- else the middle of the shop (of the lobby, without one). INF without either.
func _desk_spot(house: Node3D) -> Vector2:
	var rig := FacilityBuilder.rig(house)
	var room := "pro_shop" if rig["rooms"].has("pro_shop") else "lobby"
	var box: Dictionary = rig["boxes"].get(room, {})
	if box.is_empty():
		return Vector2.INF
	var target: Vector2 = box["rect"].get_center()
	var spots: Array = rig["spots"].get(room, [])
	for spot in spots:
		if spot["role"] == "shop_clerk":
			var xf: Transform3D = spot["xf"]
			var customer := xf.origin - xf.basis.z * 1.35
			var candidate := Vector2(customer.x, customer.z)
			var room_rect: Rect2 = box["rect"]
			if not room_rect.grow(-.4).has_point(candidate):
				customer = xf.origin + xf.basis.z * 1.35
				candidate = Vector2(customer.x, customer.z)
			if room_rect.grow(-.4).has_point(candidate):
				target = candidate
	return target


func _inside_guest(g: Group, entering: bool) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	_guest_nav(house)
	var rig := FacilityBuilder.rig(house)
	var target := _desk_spot(house)
	if target == Vector2.INF:
		return false
	var way: Array = rig.get("tee_way", [])
	if not entering:
		if not way.is_empty():
			target = Vector2((way[0] as Transform3D).origin.x, (way[0] as Transform3D).origin.z)
		else:
			var front := _facility_front("clubhouse")
			var local := house.global_transform.affine_inverse() * Vector3(front.x,0,front.y)
			target = Vector2(local.x,local.z)
	var routes: Array = []
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		var local := house.global_transform.affine_inverse() * w.node.global_position
		var side := (k - (g.golfers.size() - 1) * 0.5) * 0.55  # two abreast down the walk
		var to := target + Vector2(0 if not entering else k * .35, 0)
		var path := FacilityBuilder.nav_route(house, "guest", Vector2(local.x, local.z), to)
		var door := _front_door(house)
		if entering and door != Vector2.INF:
			# checking in is by the front door (the fountain side), however near another is: up to
			# it, then on from just inside
			var up := FacilityBuilder.nav_route(house, "guest", Vector2(local.x, local.z), door + Vector2(0, -1.6))
			_indoor_guest_nav(house)
			var on := _shop_entry_route(house, door + Vector2(0, 1.2), to)
			if on.is_empty():return false
			if not up.is_empty() and not on.is_empty():
				up.append_array(on)
				path = up
		if path.is_empty():
			return false
		var world_path: Array = []
		for p in path:
			world_path.append(house.global_transform * Vector3(p.x, 0, p.y))
		if not entering and not way.is_empty():
			for i in range(1, way.size()):
				var o: Vector3 = (way[i] as Transform3D).origin
				world_path.append(house.global_transform * Vector3(o.x + side, 0, o.z))
			# off the end of the walk and out onto the course (unless their carts are in the line,
			# right there)
			if not (g.wants_cart and not g.carts.is_empty()):
				var last: Vector3 = (way[-1] as Transform3D).origin
				var out := house.global_transform * Vector3(last.x + side, 0, FacilityBuilder.footprint("clubhouse").y * 0.5 + 5.0)
				var open := _open_spot(Vector2(out.x, out.z))  # (each their own: not the course grid's one square)
				world_path.append(Vector3(open.x, 0, open.y) if open != Vector2.INF else out)
		routes.append(world_path)
	for k in range(g.golfers.size()):
		g.golfers[k].ground = false
		g.golfers[k].data["blocked"] = false
		g.golfers[k].path = routes[k]
		g.golfers[k].data["hold"] = k * .65
		g.golfers[k].data["walk_region"] = {"nav": _guest_nav(house), "xf": house.global_transform}
		if entering:
			_valet_take(g.golfers[k])  # (their clubs stay outside: the bag drop)
	return true


## Where a flight heads first once checked in (world XZ): the range or the short game area to
## practise, else the cart barn for its carts; INF for those on foot going straight to the course
## (out the back and down the walk).
func _first_call(g: Group) -> Vector2:
	if g.wants_cart: return Vector2.INF
	if g.range_visit:
		return _facility_front("driving_range")
	if g.short_visit and _fac("short_game") != null:
		return _facility_front("short_game")
	if g.wants_cart:
		return Vector2.INF  # Wait by the clubhouse for attendant delivery.
	return Vector2.INF


## Out of the clubhouse by whichever door is nearest `toward` (world XZ) -- only the way in has
## to be the front door: each golfer from where they stand, round the furniture, to just outside
## the house on that side. False without a way.
func _out_toward(g: Group, toward: Vector2) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	_guest_nav(house)
	var fl := house.global_transform.affine_inverse() * Vector3(toward.x, 0, toward.y)
	var reach := FacilityBuilder.footprint("clubhouse") * 0.5 + Vector2(5.0, 5.0)
	fl = Vector3(clampf(fl.x, -reach.x, reach.x), 0, clampf(fl.z, -reach.y, reach.y))
	var n := g.golfers.size()
	var routes: Array = []
	for k in range(n):
		var here := house.global_transform.affine_inverse() * (g.golfers[k] as Walker).node.global_position
		var pts := FacilityBuilder.nav_route(house, "guest", Vector2(here.x, here.z), Vector2(fl.x + (k - (n - 1) * 0.5) * 0.9, fl.z))
		if pts.is_empty():
			return false
		var path: Array = []
		for i in range(1, pts.size()):
			path.append(house.global_transform * Vector3(pts[i].x, 0, pts[i].y))
		routes.append(path)
	for k in range(n):
		var w: Walker = g.golfers[k]
		w.data.erase("outdoor_target")
		w.data.erase("indoor_target")
		w.data["blocked"] = false
		w.data["hold"] = _rng.randf_range(0.0, 0.6)
		w.ground = false
		w.path = routes[k]
		w.data["walk_region"] = {"nav": _guest_nav(house), "xf": house.global_transform}
	return true


## Riders receive their loaded carts before warm-up, then keep the same carts for the round.
## After practising, they rejoin their own
## previously delivered carts. Walkers continue from the clubhouse or practice area.
func _send_to_collection(g: Group, _at: Vector2 = Vector2.INF) -> void:
	if g.wants_cart and (g.carts.is_empty() or g.bag_run):
		if not g.bag_run and not _bag_run(g):
			g.retry = 2.0
			g.phase = "delivery_request"
			return
		for w: Walker in g.golfers:
			w.ground = true
			_valet_take(w, Vector2(w.node.global_position.x, w.node.global_position.z))
		var house := _fac("clubhouse")
		var way: Array = FacilityBuilder.rig(house).get("tee_way", [])
		var end: Vector3 = house.global_transform * (way[way.size() - 1] as Transform3D).origin
		_go_together(g, Vector2(end.x, end.z))
		g.timer = 0.0
		g.phase = "cart_wait"
		return
	for w in g.golfers:
		w.ground = true
		_valet_give(w)
	if g.wants_cart and not g.carts.is_empty():
		# Rejoin carts already delivered to this flight, after its tee-wait practice.
		for k in range(g.golfers.size()):
			var door := _cart_door(g.carts[k / 2], k % 2)
			_go(g.golfers[k], Vector2(door.x, door.z))
			g.golfers[k].data["hold"] = _rng.randf_range(0.0, 0.6)
		g.phase = "board"
		return
	g.phase = "collect"

## Each golfer to a spot of their own on the short game area: on the putting green, or (the
## second of a pair, when there's a chipping green) on the mats.
func _start_short(g: Group) -> void:
	var fac := _fac("short_game")
	var spots: Array = FacilityBuilder.rig(fac).get("practice", []) if fac != null else []
	if spots.is_empty():
		g.short_visit = false
		g.phase = "collect"
		return
	var putts := spots.filter(func(s: Dictionary) -> bool: return s["kind"] == "putt")
	var chips := spots.filter(func(s: Dictionary) -> bool: return s["kind"] == "chip")
	var taken := {}
	for other in _groups:
		for w in other.golfers:
			if (w as Walker).data.has("practice"):
				taken[(w as Walker).data["practice"]] = true
	var base := _rng.randi()
	for k in range(g.golfers.size()):
		var pool: Array = chips if k % 2 == 1 and not chips.is_empty() else putts if not putts.is_empty() else chips
		var spot: Dictionary = pool[(base + k) % pool.size()]
		for j in range(pool.size()):
			if not taken.has(pool[(base + k + j) % pool.size()]):
				spot = pool[(base + k + j) % pool.size()]
				break
		taken[spot] = true
		var w: Walker = g.golfers[k]
		w.data["practice"] = spot
		w.ground = false
		# into the stance the stroke is played from (_practice_stroke: _address_ball)
		var xf: Transform3D = spot["xf"]
		var tgt: Vector3 = spot["target"]
		var at := _address_spot(Vector2(xf.origin.x, xf.origin.z), Vector2(tgt.x, tgt.z), spot["kind"] == "putt")
		_go_inside(w, fac, "", at, 0.0)
	g.short_rounds = 0
	g.phase = "short_walk"


## Square to the practice line: the target off the left shoulder, as at a shot.
func _face_practice(w: Walker) -> void:
	var spot: Dictionary = w.data.get("practice", {})
	var fac := _fac("short_game")
	if spot.is_empty() or fac == null:
		return
	var d3: Vector3 = fac.global_transform.basis * -(spot["xf"] as Transform3D).basis.z
	var d := Vector2(d3.x, d3.z).normalized()
	var facing := Vector2(-d.y, d.x)
	w.node.rotation.y = atan2(-facing.x, -facing.y)


## A practice putt (or chip) from the golfer's spot: the stroke, and a ball off toward the cup.
func _practice_stroke(g: Group, k: int) -> void:
	var w: Walker = g.golfers[k]
	var spot: Dictionary = w.data.get("practice", {})
	var fac := _fac("short_game")
	if spot.is_empty() or fac == null:
		return
	var chip: bool = spot["kind"] == "chip"
	while g.practice_balls.size() <= k:
		var b := (g.balls[0] as Node3D).duplicate() as Node3D
		add_child(b)
		g.practice_balls.append(b)
	var ball: Node3D = g.practice_balls[k]
	var from: Vector3 = fac.global_transform * (spot["xf"] as Transform3D).origin
	var cup: Vector3 = fac.global_transform * (spot["target"] as Vector3)
	var to := cup + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5)) * (2.0 if chip else 1.0)
	from.y = _surface_y(Vector2(from.x, from.z)) + 0.021
	to.y = _surface_y(Vector2(to.x, to.z)) + 0.021
	var clip := ("chip" if w.anim != null and w.anim.has_animation("chip") else "swing") if chip else "putt"
	_address_ball(w, from, Vector2(to.x - from.x, to.z - from.z), not chip, chip)
	_play(w, clip)
	if w.anim != null:
		w.anim.stop()
		w.anim.play(clip, 0)
	ball.position = from
	ball.visible = true
	var arc := 2.5 if chip else 0.0
	var t := ball.create_tween()  # Stop the shot when its practice ball is removed.
	t.tween_interval(float(IMPACTS[clip]))
	t.tween_method(func(p: float) -> void:
		if is_instance_valid(ball):
			ball.position = _ball_at(from, to, arc, p, 0.021), 0.0, 1.0, 2.2 if chip else 1.8)


func _clear_practice(g: Group) -> void:
	for b in g.practice_balls:
		if is_instance_valid(b):
			(b as Node).queue_free()
	g.practice_balls.clear()
	for w in g.golfers:
		_drop_bucket(w)
		for key in RANGE_KEYS:
			(w as Walker).data.erase(key)


## Every facility moved since the last refresh (picked up and put down again, or turned: the same
## level): whatever was at it moved with it, keeping its place on it (user: they went on to where
## it was) -- the people on it and in it, the cars and carts in its lot or row, the bags set down
## and the balls on it, and every way, spot and target there that the club's people had (their
## paths, the places they were headed or watching, their flights' parking ways). The staff are
## set out afresh anyway (_spawn_staff).
func _carry_with_facilities() -> void:
	if facilities == null:
		return
	for type: String in business.placements:
		var node := _fac(type)
		if node == null:
			continue
		var now := node.global_transform
		var lv := business.level(type)
		var was: Variant = _fac_was.get(type)
		_fac_was[type] = [now, lv]
		if was == null or int(was[1]) != lv or (was[0] as Transform3D).is_equal_approx(now):
			continue
		var old: Transform3D = was[0]
		var move := now * old.affine_inverse()
		var inv := old.affine_inverse()
		var site := FacilityBuilder.site(type, lv).grow(3.0)
		var on := func(p: Vector3) -> bool:
			var l := inv * p
			return site.has_point(Vector2(l.x, l.z))
		var walkers: Array = _pool.duplicate()
		for g: Group in _groups:
			walkers.append_array(g.golfers)
			walkers.append_array(g.carts)
			if g.car != null:
				walkers.append(g.car)
			for k in ["parking_path", "exit_path", "stops", "ball_positions"]:
				g.set(k, _carried(g.get(k), on, move))
			for b in g.practice_balls + g.balls:
				if b is Node3D and is_instance_valid(b) and on.call((b as Node3D).global_position):
					(b as Node3D).global_transform = move * (b as Node3D).global_transform
		for w: Walker in walkers:
			if not is_instance_valid(w.node) or w.riding:
				continue  # (riding: carried in its cart)
			if on.call(w.node.global_position):
				w.node.global_transform = move * w.node.global_transform
			w.path = _carried(w.path, on, move)
			for key in w.data.keys():
				var v: Variant = w.data[key]
				if v is Node3D and is_instance_valid(v) and not (v as Node3D).is_ancestor_of(w.node) and (v as Node3D).get_parent() != w.node and on.call((v as Node3D).global_position):
					(v as Node3D).global_transform = move * (v as Node3D).global_transform  # (a bag stood down there)
				elif key == "place" and v is Dictionary and (v as Dictionary).get("xf") is Transform3D:
					var xf: Transform3D = v["xf"]  # (a room's station: in the world's frame, _free_places)
					if on.call(xf.origin):
						(v as Dictionary)["xf"] = move * xf
				elif not v is Object:
					w.data[key] = _carried(v, on, move)
		_chute_users.clear()


## `v` (a point, a way of them, or anything holding them) with each world point on the moved
## facility (`on`) moved with it (`move`); anything else as it is.
func _carried(v: Variant, on: Callable, move: Transform3D) -> Variant:
	if v is Vector3:
		return move * v if on.call(v) else v
	if v is Vector2:
		var p := Vector3((v as Vector2).x, 0.0, (v as Vector2).y)
		if not on.call(p):
			return v
		var q := move * p
		return Vector2(q.x, q.z)
	if v is Transform3D:
		return v  # (a facility's own spot: in its own frame, already right)
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_carried(x, on, move))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _carried(v[k], on, move)
		return d
	return v


## The cart barn just working (bought, placed, built): the flights in for a round that haven't
## checked in yet take carts in the share the barn has them riding (as each arrival does:
## _new_arrival's credit), so the course has carts on it right away (user) -- at the desk they're
## then checked in to ride (their carts brought round with their bags: _bag_run).
func _offer_carts() -> void:
	var share := float(business.rates().get("cart_share", 0.0))
	for g: Group in _groups:
		if g.visit != "" or g.checked_in or g.wants_cart or not g.carts.is_empty() or g.tee_started or g.hole != g.start_hole or g.stop != 0:
			continue
		_cart_arrival_credit += share
		if _cart_arrival_credit >= 1.0:
			_cart_arrival_credit -= 1.0
			g.wants_cart = true


## The driving range rebuilt (upgraded or moved: its ball dispenser and bays somewhere else now,
## user): everyone at it set going again on the range as it is -- their bags picked up, their
## balls gone, a bay each again and, if they've no bucket yet, to its ball dispenser as it stands
## now; those done with it left to go.
func _re_range() -> void:
	_chute_users.clear()
	for g: Group in _groups:
		var at := g.golfers.any(func(w: Walker) -> bool: return str(w.data.get("range_step", "")) not in ["", "done"])
		if not at:
			continue
		for b in g.practice_balls:
			if is_instance_valid(b):
				(b as Node).queue_free()
		g.practice_balls.clear()
		for w: Walker in g.golfers:
			if str(w.data.get("range_step", "")) == "done":
				continue
			_bag_up(w)
			for key in RANGE_KEYS:
				w.data.erase(key)
			w.path.clear()
			w.data["blocked"] = false
			w.data.erase("outdoor_target")
			w.data.erase("indoor_target")
			w.rest = "idle"
			_play(w, "idle")
		_start_range(g)


## Allocate free bays to individual golfers. A partially admitted party never blocks an empty
## bay, and each player releases their own reservation as soon as they leave the range.
func _start_range(g: Group) -> bool:
	var range_fac := _fac("driving_range")
	if range_fac == null:
		g.phase = "tee_queue"
		return true
	# its bays (the model's RANGE_BAY markers on the ground, RANGE_BAY_UP in its lounge upstairs,
	# more at each level): as many practise at once as there are -- a bay each that nobody else is
	# in, the ground's first (all taken: they wait their turn by the range)
	var rig := FacilityBuilder.rig(range_fac)
	var ground: Array = rig.get("range_bays", [])
	var mats: Array = ground + (rig.get("range_bays_up", []) if not rig.get("range_stairs", []).is_empty() else [])
	if mats.is_empty():  # (no bays to hit from: on to the course, or home)
		g.range_visit = false
		if g.visit != "":
			_to_parking(g)
		else:
			g.phase = "tee_queue"
		return true
	var bays: Array = range(mats.size())
	for other: Group in _groups:
		for o: Walker in other.golfers:
			bays.erase(int(o.data.get("range_bay", -1)))
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		if w.data.has("range_bay") or w.data.get("range_step", "") == "done":
			continue
		if bays.is_empty():
			if w.data.get("range_step", "") != "wait":
				_go(w, _facility_front("driving_range") + Vector2(k * 1.1, 0.0))
				w.data["range_step"] = "wait"
			continue
		var bay: int = bays.pop_front()
		w.ground = false
		w.data["range_bay"] = bay
		var up: bool = bay >= ground.size()
		var mat: Vector3 = (mats[bay] as Transform3D).origin
		var ball := range_fac.global_transform * Vector3(mat.x, mat.y + 0.125, mat.z)  # (on its tee)
		var direction := -range_fac.global_basis.z
		var stance := _address_spot(Vector2(ball.x, ball.z), Vector2(ball.x + direction.x, ball.z + direction.z), false)
		var local := range_fac.global_transform.affine_inverse() * Vector3(stance.x, ball.y, stance.y)
		var at := Vector2(local.x, local.z)
		# their bag stood off the mat (1.5 m square, the ball in its middle), never on it: in the
		# gap between the bay's ball tray (on the mat's right, out to 1.12 m) and the divider to
		# the next bay (half a bay along), a little back of the ball, where that's room enough for
		# it; else (the narrower bays) just behind where they stand; in by way of it
		var step := INF
		for other: Transform3D in (rig["range_bays_up"] if up else ground):
			if absf(other.origin.x - mat.x) > 0.1:
				step = minf(step, absf(other.origin.x - mat.x))
		if step == INF:
			step = 4.8
		var bag := Vector2(mat.x + minf((RANGE_TRAY + step * 0.5) * 0.5, RANGE_TRAY + 0.35), mat.z + 0.2)
		if step * 0.5 - RANGE_TRAY < 0.9:
			bag = at + Vector2(0.0, 1.2)  # (the range's back is its +Z)
		w.data["range_ball"] = ball
		w.data["range_stance"] = at
		w.data["range_bag"] = bag
		w.data["range_bay_up"] = up
		w.data["range_up"] = false
		w.data["range_step"] = "approach"
		w.data["range_bucket"] = Vector2(mat.x - 1.0, mat.z + 0.45)  # (where the bay's bucket stood)
		# their own way there: round to the back of the range behind their bay (then in to it,
		# _range_golfers), unless they're on its grounds (its yard grid) already -- by way of
		# the ball dispenser for a bucket of balls, if they've none yet
		var here := range_fac.global_transform.affine_inverse() * w.node.global_position
		var fp := FacilityBuilder.footprint("driving_range")
		var machine := _dispenser_spot(range_fac, Vector2(here.x, here.z), k)
		if not w.data.has("bucket") and machine != Transform3D():
			w.data["range_step"] = "dispenser"
			w.data["range_machine"] = machine
			w.data["range_chute"] = _dispenser_spot(range_fac, Vector2(here.x, here.z), 0)
			var stand := range_fac.global_transform * machine.origin
			if Rect2(-fp * 0.5, fp).grow(5.5).has_point(Vector2(here.x, here.z)):
				_range_go(w, range_fac, Vector2(machine.origin.x, machine.origin.z), false)
			else:
				w.ground = true  # (across the course to it: on the ground)
				_go(w, Vector2(stand.x, stand.z))
				w.data["hold"] = _rng.randf_range(0.0, 0.6)
		elif Rect2(-fp * 0.5, fp).grow(5.5).has_point(Vector2(here.x, here.z)):
			var behind := range_fac.global_transform * Vector3(mat.x, 0.0, fp.y * 0.5 + 2.0)
			w.ground = true  # (across the course to it: on the ground)
			_go(w, Vector2(behind.x, behind.z))
			w.data["hold"] = _rng.randf_range(0.0, 0.6)
	g.phase = "range_practice"
	return true


## Flight `g` at the range, each golfer at their own step (data "range_step") as they get there,
## not waiting for the others: "approach" (round to the back of the range by their bay), "bag" (in
## to their bag's spot, up the stair for a bay in the lounge), "in" (bag down, up to the ball),
## "hit" (their bucket, RANGE_BALLS, on their own time), "pack" (their balls gathered up as they
## finish, back to the bag), "out" (bag on, off the back of the range), "done". True once all are.
func _range_golfers(g: Group, delta: float) -> bool:
	_start_range(g)  # Fill any vacancies without waiting for a whole flight.
	var fac := _fac("driving_range")
	var all_done := true
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		var up: bool = w.data.get("range_up", false)
		match str(w.data.get("range_step", "done")):
			"dispenser":
				# at the ball dispenser: turned to it, a bucket filled at its chute, then on with it
				# in hand to their bay
				if w.path.is_empty() and w.data.get("blocked", false):
					w.data["range_stall"] = float(w.data.get("range_stall", 0.0)) + delta
					if float(w.data["range_stall"]) > 20.0:
						w.data["blocked"] = false  # (no way to it: a bucket all the same)
				if w.path.is_empty() and not w.data.get("blocked", false):
					# one at a time at its chute, square in front of it; the rest in line behind,
					# stepping up as it's their turn
					var chute: Transform3D = w.data.get("range_chute", w.data["range_machine"])
					var key := str(chute.origin.snapped(Vector3.ONE * 0.1))
					var at := fac.global_transform * chute.origin
					var filling: Variant = _chute_users.get(key)
					if filling != w and filling != null and is_instance_valid((filling as Walker).node) and str((filling as Walker).data.get("range_step", "")) == "dispenser":
						if w.rest != "idle":
							_face(w, (fac.global_transform * chute).basis.get_euler().y)
							w.rest = "idle"
							_play(w, "idle")
						all_done = false
						continue  # (waiting their turn in line)
					_chute_users[key] = w
					if Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(Vector2(at.x, at.z)) > 0.25:
						w.path = [Vector3(at.x, w.node.global_position.y, at.z)]  # up to the chute
						w.rest = "idle"
						all_done = false
						continue
					if not w.data.has("range_next"):
						var machine: Transform3D = chute
						_face(w, (fac.global_transform * machine).basis.get_euler().y)
						w.rest = "work"
						_play(w, "work")
						w.data["range_next"] = 2.2
					w.data["range_next"] = float(w.data["range_next"]) - delta
					if float(w.data["range_next"]) <= 0.0:
						w.data.erase("range_next")
						w.data.erase("range_stall")
						w.rest = "idle"
						_hold_bucket(w)
						_chute_users.erase(key)  # (the next in line's turn)
						w.data["range_step"] = "approach"
			"approach":
				# (no way round to the back of it a while -- something's built in the way: on
				# from the nearest of its grounds instead, not holding the bay for ever)
				if w.path.is_empty() and w.data.get("blocked", false):
					w.data["range_stall"] = float(w.data.get("range_stall", 0.0)) + delta
					if float(w.data["range_stall"]) > 20.0:
						var fp := FacilityBuilder.footprint("driving_range")
						var here := fac.global_transform.affine_inverse() * w.node.global_position
						var edge := Vector2(clampf(here.x, -fp.x * 0.5, fp.x * 0.5), fp.y * 0.5 + 1.0)
						var open := FacilityBuilder.nav_floor_point(fac, "", edge)
						var at := fac.global_transform * Vector3(open.x, 0.0, open.y) if open != Vector2.INF else w.node.global_position
						w.node.global_position = Vector3(at.x, _surface_y(Vector2(at.x, at.z)), at.z)
						w.data["blocked"] = false
						w.data.erase("outdoor_target")
				if w.path.is_empty() and not w.data.get("blocked", false):
					w.data.erase("range_stall")
					w.ground = false
					_range_go(w, fac, w.data["range_bag"], w.data.get("range_bay_up", false))
					w.data["range_step"] = "bag"
			"bag":
				if w.path.is_empty():
					_range_bag_down(w)
					_range_bucket_down(w)
					_range_go(w, fac, w.data["range_stance"], up)
					w.data["range_step"] = "in"
			"in":
				if w.path.is_empty():
					_face(w, fac.global_rotation.y)
					w.data["range_hit"] = 0
					w.data["range_next"] = _rng.randf_range(1.5, 5.0)
					w.data["range_step"] = "hit"
			"hit":
				# a ball teed up, a practice swing or two, the shot; the last one landed, done
				w.data["range_next"] = float(w.data["range_next"]) - delta
				if float(w.data["range_next"]) <= 0.0:
					if g.wait_practice and _tee_rank(g) > 0 and int(w.data["range_hit"]) >= RANGE_BALLS:
						w.data["range_hit"] = 0
					if int(w.data["range_hit"]) < RANGE_BALLS:
						_range_stroke(g, k)
						w.data["range_hit"] = int(w.data["range_hit"]) + 1
						w.data["range_next"] = _rng.randf_range(5.5, 8.0)
					else:
						for ball in w.data.get("range_balls", []):
							if is_instance_valid(ball):
								(ball as Node).queue_free()
						w.data["range_balls"] = []
						_range_go(w, fac, w.data["range_bag"], up)
						w.data["range_step"] = "pack"
			"pack":
				if w.path.is_empty():
					_bag_up(w)
					# off the back of the range, side by side (not all to the one spot), down the stair
					# from the lounge
					_range_go(w, fac, Vector2((k - (g.golfers.size() - 1) * 0.5) * 1.1, FacilityBuilder.footprint("driving_range").y * 0.5 + 5.0), false)
					w.data["range_step"] = "out"
			"out":
				if w.path.is_empty():
					w.data.erase("range_bay")
					_drop_bucket(w)  # (the empty bucket cleared away from the bay)
					w.data["range_step"] = "done"
		all_done = all_done and str(w.data.get("range_step", "done")) == "done"
	return all_done


## The floor of the driving range `fac` people walk at (its own XZ's height): its lounge's, `up`
## there, else the ground's (RANGE_FLOOR).
static func _range_floor(fac: Node3D, up: bool) -> float:
	var upper: Array = FacilityBuilder.rig(fac).get("range_bays_up", [])
	return (upper[0] as Transform3D).origin.y if up and not upper.is_empty() else RANGE_FLOOR


## `w` across the driving range `fac` to `to` (its XZ) on its lounge floor upstairs (`up`) or the
## ground: on that floor's grid, round what's in the way -- by way of whichever of its stairs is
## nearest the way when that isn't the floor they're on (up or down its treads, a step at a time).
func _range_go(w: Walker, fac: Node3D, to: Vector2, up: bool) -> void:
	var was_up: bool = w.data.get("range_up", false)
	var rig := FacilityBuilder.rig(fac)
	var feet: Array = rig.get("range_stairs", [])
	var tops: Array = rig.get("range_stair_tops", [])
	if was_up == up or feet.is_empty() or feet.size() != tops.size():
		_go_inside(w, fac, "upper" if up else "", to, _range_floor(fac, up))
		w.data["range_up"] = up
		return
	var here3 := fac.global_transform.affine_inverse() * w.node.global_position
	var here := Vector2(here3.x, here3.z)
	var best := -1
	var least := INF
	for i in range(feet.size()):
		var foot := Vector2((feet[i] as Transform3D).origin.x, (feet[i] as Transform3D).origin.z)
		var top := Vector2((tops[i] as Transform3D).origin.x, (tops[i] as Transform3D).origin.z)
		var way := here.distance_to(foot) + top.distance_to(to) if up else here.distance_to(top) + foot.distance_to(to)
		if way < least:
			least = way
			best = i
	var a: Vector3 = (feet[best] as Transform3D).origin
	var b: Vector3 = (tops[best] as Transform3D).origin
	if not up:
		var swap := a
		a = b
		b = swap
	var from_key := "upper" if was_up else ""
	var to_key := "upper" if up else ""
	var first := FacilityBuilder.nav_route(fac, from_key, here, Vector2(a.x, a.z))
	var last := FacilityBuilder.nav_route(fac, to_key, Vector2(b.x, b.z), to)
	if first.is_empty() or last.is_empty():
		_go_inside(w, fac, to_key, to, _range_floor(fac, up))  # (no way to the stair: as near as it gets)
		w.data["range_up"] = up
		return
	var path: Array = []
	for i in range(1, first.size()):
		path.append(fac.global_transform * Vector3(first[i].x, _range_floor(fac, was_up), first[i].y))
	# the treads: from its foot (or top), the stair rising (or falling) along the way between them
	var run := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var n := maxi(ceili(run / 0.4), 2)
	for i in range(n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t)
		p.y = lerpf(a.y, b.y, clampf((t * run - 0.5) / maxf(run - 1.1, 0.1), 0.0, 1.0) if up else clampf((t * run - 0.6) / maxf(run - 1.1, 0.1), 0.0, 1.0))
		path.append(fac.global_transform * p)
	for i in range(1, last.size()):
		path.append(fac.global_transform * Vector3(last[i].x, _range_floor(fac, up), last[i].y))
	w.data.erase("indoor_target")
	w.data.erase("outdoor_target")
	w.data.erase("walk_region")  # (two floors and a stair: no one grid to sidestep on)
	w.data["blocked"] = false
	w.data["range_up"] = up
	w.path = path


## Golfer `w` on the range stands their bag at its spot beside the mat, pockets toward them.
func _range_bag_down(w: Walker) -> void:
	var fac := _fac("driving_range")
	var bag: Vector2 = w.data.get("range_bag", Vector2.ZERO)
	var stance: Vector2 = w.data.get("range_stance", bag + Vector2.LEFT)
	var p := fac.global_transform * Vector3(bag.x, 0.0, bag.y)
	var toward := fac.global_transform.basis * Vector3(stance.x - bag.x, 0.0, stance.y - bag.y)
	var floor_y := fac.global_position.y + _range_floor(fac, w.data.get("range_up", false))
	_bag_down_at(w, Vector3(p.x, _surface_y(Vector2(p.x, p.z), floor_y), p.z), atan2(toward.x, toward.z))


## Where at the range `fac`'s ball dispenser nearest `near` (its XZ) its `k`th golfer waits to
## fill a bucket (its frame: facing the machine): the first square in front of its chute, the rest
## in line behind them (user); the identity when it has none.
func _dispenser_spot(fac: Node3D, near: Vector2, k: int) -> Transform3D:
	var best := Transform3D()
	var least := INF
	for xf: Transform3D in FacilityBuilder.rig(fac).get("dispensers", []):
		var d := near.distance_to(Vector2(xf.origin.x, xf.origin.z))
		if d < least:
			least = d
			best = xf
	if least == INF:
		return best
	var basis := best.basis.orthonormalized()
	return Transform3D(basis, best.origin + basis.z * k * 0.9)


## A bucket of range balls in `w`'s right hand (our rig's .L), hung by its bail (_hang_bucket).
func _hold_bucket(w: Walker) -> void:
	var scene := _scene(BUCKET)
	if scene == null or w.data.has("bucket"):
		return
	var bucket := scene.instantiate() as Node3D
	bucket.name = "Bucket"
	w.node.add_child(bucket)
	w.data["bucket"] = bucket
	_hang_bucket(w)


## The bucket in `w`'s hand hanging straight down from it by its bail, upright whatever the hand.
func _hang_bucket(w: Walker) -> void:
	var bucket: Node3D = w.data.get("bucket")
	var skel := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if bucket == null or not is_instance_valid(bucket) or skel == null:
		return
	var bone := skel.find_bone("grip.L")
	if bone < 0:
		bone = skel.find_bone("hand.L")
	if bone < 0:
		return
	var grip := (skel.global_transform * skel.get_bone_global_pose(bone)).origin
	bucket.global_transform = Transform3D(Basis(Vector3.UP, w.node.global_rotation.y), grip - Vector3(0.0, BUCKET_BAIL, 0.0))


## `w`'s bucket set down on the floor at their bay, beside the mat where the bay's own stood.
func _range_bucket_down(w: Walker) -> void:
	var bucket: Node3D = w.data.get("bucket")
	var fac := _fac("driving_range")
	if bucket == null or not is_instance_valid(bucket) or fac == null:
		return
	w.data.erase("bucket")
	var at: Vector2 = w.data.get("range_bucket", Vector2.ZERO)
	var p := fac.global_transform * Vector3(at.x, 0.0, at.y)
	var floor_y := fac.global_position.y + _range_floor(fac, w.data.get("range_up", false))
	bucket.get_parent().remove_child(bucket)
	add_child(bucket)
	bucket.global_transform = Transform3D(Basis(Vector3.UP, fac.global_rotation.y), Vector3(p.x, _surface_y(Vector2(p.x, p.z), floor_y), p.z))
	w.data["bucket_down"] = bucket


## `w`'s bucket gone: out of their hand, or (empty, left at their bay) cleared away.
func _drop_bucket(w: Walker) -> void:
	for key in ["bucket", "bucket_down"]:
		var b: Variant = w.data.get(key)
		if b != null and is_instance_valid(b):
			(b as Node).queue_free()
		w.data.erase(key)


func _range_stroke(g: Group, k: int) -> void:
	var w: Walker = g.golfers[k]
	var from: Vector3 = w.data["range_ball"]
	var direction := -_fac("driving_range").global_basis.z
	_address_ball(w, from, Vector2(direction.x, direction.z), false)
	_play(w, "swing")
	if w.anim != null:
		w.anim.stop()
		w.anim.play("swing", 0)
	# a ball of its own every shot, left lying where it ends up out on the range till the golfer's
	# done there (_range_golfers)
	var ball := (g.balls[0] as Node3D).duplicate() as Node3D
	add_child(ball)
	g.practice_balls.append(ball)
	(w.data.get_or_add("range_balls", []) as Array).append(ball)
	var hit := _miss(w, Vector2(direction.x, direction.z) * _rng.randf_range(75, 170))
	var to := from + Vector3(hit.x, 0.0, hit.y)
	to.y = _ground_y(Vector2(to.x, to.z)) + .045
	ball.position = from
	ball.visible = true
	var contact := _range_net_contact(from, to, 20.0)
	var tween := ball.create_tween()  # Stop the shot when its range ball is removed.
	tween.tween_interval(SWING_IMPACT)
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(ball):
			ball.position = _range_ball_at(from, to, 20.0, t, contact), 0.0, 1.0, 3.0)


## Range shots are animated, so explicitly sweep their trajectory against the same net
## segments used to build the enclosure. Ordinary physics collisions cannot stop a tween.
func _range_net_contact(from: Vector3, to: Vector3, arc: float) -> Dictionary:
	var fac := _fac("driving_range")
	if fac == null:
		return {}
	var corners := FacilityBuilder.range_net_outline(business.level("driving_range"))
	var inv := fac.global_transform.affine_inverse()
	var start := inv * from
	var end := inv * to
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	var nearest := INF
	var impact := Vector3.ZERO
	for i in range(corners.size() - 1):
		var cross: Variant = Geometry2D.segment_intersects_segment(a, b, corners[i], corners[i + 1])
		if cross == null:
			continue
		# XZ is monotone throughout carry, bounces and roll; locate the contact time.
		var fraction := a.distance_to(cross) / maxf(a.distance_to(b), 0.001)
		var lo := 0.0
		var hi := 1.0
		for _j in range(24):
			var t := (lo + hi) * 0.5
			var p := inv * _ball_at(from, to, arc, t)
			if a.distance_to(Vector2(p.x, p.z)) / maxf(a.distance_to(b), 0.001) < fraction:
				lo = t
			else:
				hi = t
		var hit := _ball_at(from, to, arc, hi)
		var ground := _ground_y(Vector2(hit.x, hit.z))
		if hit.y <= ground + 31.5 and hi < nearest:
			nearest = hi
			impact = hit
	if nearest == INF:
		return {}
	var inward := Vector3(from.x - impact.x, 0, from.z - impact.z).normalized()
	impact += inward * 0.06  # ball radius stays inside the rope plane
	var rest := impact + inward * 0.65
	rest.y = _ground_y(Vector2(rest.x, rest.z)) + 0.045
	return {"time": nearest, "impact": impact, "rest": rest}


func _range_ball_at(from: Vector3, to: Vector3, arc: float, t: float, contact: Dictionary) -> Vector3:
	if contact.is_empty() or t < float(contact["time"]):
		return _ball_at(from, to, arc, t)
	var u := clampf((t - float(contact["time"])) / maxf(1.0 - float(contact["time"]), 0.001), 0, 1)
	var hit: Vector3 = contact["impact"]
	var rest: Vector3 = contact["rest"]
	var p := hit.lerp(rest, u)
	p.y = lerpf(hit.y, rest.y, u * u)
	return p


## Where the course meets the clubhouse's walk (its last TEEWAY marker, out past the plot's
## back edge): where golfers going home head for. INF without a clubhouse walk.
func _clubhouse_back() -> Vector2:
	var house := _fac("clubhouse")
	var way: Array = FacilityBuilder.rig(house).get("tee_way", []) if house != null else []
	if way.is_empty():
		return Vector2.INF
	var last: Vector3 = (way[-1] as Transform3D).origin
	var out := house.global_transform * Vector3(last.x, 0, FacilityBuilder.footprint("clubhouse").y * 0.5 + 5.0)
	return _open_spot(Vector2(out.x, out.z))


## Back into the clubhouse and out of it: each golfer up the walk (the TEEWAY markers in
## reverse), over the deck and in by the garden door, then across the clubhouse (its grid, round
## the furniture) and out of the front door. False when there's no such way.
func _through_clubhouse(g: Group) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	var way: Array = FacilityBuilder.rig(house).get("tee_way", [])
	if way.is_empty():
		return false
	_guest_nav(house)
	var fl := _house_exit(house)
	if fl == Vector2.INF:
		return false
	var n := g.golfers.size()
	var routes: Array = []
	for k in range(n):
		var side := (k - (n - 1) * 0.5) * 0.55  # two abreast up the walk
		var pts: Array = []
		for i in range(way.size() - 1, -1, -1):
			var o: Vector3 = (way[i] as Transform3D).origin
			pts.append(house.global_transform * Vector3(o.x + (side if i > 0 else 0.0), 0, o.z))
		var door: Vector3 = (way[0] as Transform3D).origin
		var inside := FacilityBuilder.nav_route(house, "guest", Vector2(door.x, door.z), Vector2(fl.x + side * 2.0, fl.y))
		if inside.is_empty():
			return false
		for q in inside:
			pts.append(house.global_transform * Vector3(q.x, 0, q.y))
		routes.append(pts)
	for k in range(n):
		var w: Walker = g.golfers[k]
		w.data.erase("outdoor_target")
		w.data.erase("indoor_target")
		w.data["blocked"] = false
		w.data["hold"] = _rng.randf_range(0.0, 0.6)
		w.path = routes[k]
		w.data["walk_region"] = {"nav": _guest_nav(house), "xf": house.global_transform}
		_valet_take(w, Vector2(w.node.global_position.x, w.node.global_position.z))
	_valet_return(g)
	return true


## Where people leave the clubhouse for home (its XZ): just outside, toward the car park -- out
## of whichever door is nearest it (only the way in has to be the front door). INF if nowhere.
func _house_exit(house: Node3D) -> Vector2:
	var hp := Vector2(house.global_position.x, house.global_position.z)
	var front := _lot_edge(hp)
	if front == Vector2.INF:
		front = _facility_front("clubhouse")
	if front == Vector2.INF:
		return Vector2.INF
	var fl := house.global_transform.affine_inverse() * Vector3(front.x, 0, front.y)
	var reach := FacilityBuilder.footprint("clubhouse") * 0.5 + Vector2(5.0, 5.0)
	return Vector2(clampf(fl.x, -reach.x, reach.x), clampf(fl.z, -reach.y, reach.y))


## The 19th hole: about half the flights in off the course stop for a drink at the bar (the
## restaurant's, from the Expanded clubhouse up) -- or, at a club with the lounge, some sit down
## in there -- before going home. True when they've gone in to sit down.
func _nineteenth(g: Group) -> bool:
	if g.visit != "" or _rng.randf() >= 0.55:
		return false
	var rooms: Array = []
	if business.room_working("restaurant") and _rng.randf() < 0.5:
		rooms.append(["restaurant", ["guest_bar"]])
	if business.room_working("lounge"):
		rooms.insert(0 if _rng.randf() < 0.65 else rooms.size(), ["lounge", ["guest_seat"]])
	for r: Array in rooms:
		if _to_places(g, r[0], r[1], true):
			return true
	return false


## Count reserved stools as well as seated guests so arrivals cannot overfill the bar.
func _bar_guests() -> int:
	var count := 0
	for w: Walker in _guest_places.values():
		if w.data.get("place", {}).get("use", "") == "guest_bar":
			count += 1
	return count


## Guest spots of `uses` in clubhouse room `room` that nobody has (world transforms, in the
## model's order: a bar's stools along it).
func _free_places(room: String, uses: Array) -> Array:
	var house := _fac("clubhouse")
	var out: Array = []
	if house == null:
		return out
	var spots: Array = FacilityBuilder.rig(house).get("spots", {}).get(room, [])
	for i in range(spots.size()):
		var key := "%s/%d" % [room, i]
		if str(spots[i]["role"]) in uses and not _guest_places.has(key):
			out.append({"key": key, "xf": house.global_transform * (spots[i]["xf"] as Transform3D), "use": str(spots[i]["role"])})
	return out


## Where someone steps onto or off guest spot `place` from (world XZ): behind a stool, in front
## of a chair, beside a machine (GUEST_USE).
func _place_step(place: Dictionary) -> Vector2:
	var xf: Transform3D = place["xf"]
	if place["use"] == "guest_sim" and _fac("clubhouse") != null:
		# a simulator bay's mat: from behind it, the open side away from its screen (nets either
		# side: no way in there -- members turned back at the door, user)
		var back := xf.origin + _fac("clubhouse").global_transform.basis.x.normalized() * 1.6
		return Vector2(back.x, back.z)
	var off: Vector2 = GUEST_USE[place["use"]][1]
	if place["use"] == "guest_gym_ride":
		var house := _fac("clubhouse")
		if house != null:
			# Approach from the outside of the pair, even when the other bike is occupied.
			for spot: Dictionary in FacilityBuilder.rig(house).get("spots", {}).get("spa_fitness", []):
				if str(spot["role"]) != "guest_gym_ride":
					continue
				var other: Vector3 = (house.global_transform * (spot["xf"] as Transform3D)).origin
				var delta := other - xf.origin
				if delta.length() > 0.1 and delta.length() < 1.5:
					off.x = -0.9 if delta.dot(xf.basis.x) > 0.0 else 0.9
					break
	var p := xf.origin + xf.basis.x.normalized() * off.x - xf.basis.z.normalized() * off.y
	return Vector2(p.x, p.z)


## Into clubhouse room `room` and onto free guest spots of `uses` there, one each, all together
## (within a few steps of each other: stools in a row, the sofa and the chair beside it): up the
## back walk and in by the garden door when `by_back` (off the course), else in by the door
## nearest them (the front: they've just walked up to it). False, and nothing changed, when they
## can't sit together there or there's no way in.
func _to_places(g: Group, room: String, uses: Array, by_back: bool) -> bool:
	var house := _fac("clubhouse")
	var free := _free_places(room, uses)
	var n := g.golfers.size()
	if "guest_bar" in uses and _bar_guests() + n > BAR_GUESTS:
		return false
	if house == null or free.size() < n:
		return false
	var pick: Array = []
	var starts: Array = range(free.size())
	starts.shuffle()
	for s: int in starts:
		var a: Vector3 = free[s]["xf"].origin
		var near := free.duplicate()
		near.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return a.distance_to(p["xf"].origin) < a.distance_to(q["xf"].origin))
		near = near.slice(0, n)
		if a.distance_to(near[n - 1]["xf"].origin) <= 2.6:
			pick = near
			break
	if pick.is_empty():
		return false
	var way: Array = FacilityBuilder.rig(house).get("tee_way", [])
	if by_back and way.is_empty():
		return false
	_guest_nav(house)
	var nav_key := "guest"
	if room == "spa_fitness":
		_indoor_guest_nav(house)
		nav_key = "indoor_guest"
	var inv := house.global_transform.affine_inverse()
	var routes: Array = []
	for k in range(n):
		var step := _place_step(pick[k])
		var sl := inv * Vector3(step.x, 0, step.y)
		var to := Vector2(sl.x, sl.z) if room == "spa_fitness" else FacilityBuilder.nav_floor_point(house, "guest", Vector2(sl.x, sl.z))
		if to == Vector2.INF:
			to = Vector2(sl.x, sl.z)
		var pts: Array = []
		var from: Vector2
		if by_back:
			var side := (k - (n - 1) * 0.5) * 0.55  # two abreast up the walk
			for i in range(way.size() - 1, -1, -1):
				var o: Vector3 = (way[i] as Transform3D).origin
				pts.append(house.global_transform * Vector3(o.x + (side if i > 0 else 0.0), 0, o.z))
			var door: Vector3 = (way[0] as Transform3D).origin
			from = Vector2(door.x, door.z)
		else:
			var here := inv * (g.golfers[k] as Walker).node.global_position
			from = Vector2(here.x, here.z)
		var inside := FacilityBuilder.nav_route(house, nav_key, from, to)
		if inside.is_empty():
			return false
		if room == "spa_fitness" and inside[inside.size() - 1].distance_to(Vector2(sl.x, sl.z)) > 0.8:
			return false
		for q in inside:
			pts.append(house.global_transform * Vector3(q.x, 0, q.y))
		routes.append(pts)
	for k in range(n):
		var w: Walker = g.golfers[k]
		_valet_take(w, Vector2(w.node.global_position.x, w.node.global_position.z))
		_guest_places[pick[k]["key"]] = w
		w.data["place"] = pick[k]
		w.data.erase("outdoor_target")
		w.data.erase("indoor_target")
		w.data["blocked"] = false
		w.data["hold"] = _rng.randf_range(0.0, 0.6)
		w.path = routes[k]
		w.data["walk_region"] = {"nav": FacilityBuilder.rig(house)["nav"][nav_key], "xf": house.global_transform}
	g.phase = "to_place"
	return true


## `w` there (their bag with the valet: no clubs in the clubhouse): up onto the stool, into the
## chair or onto the machine, facing the way it does, doing what it's for.
func _use_place(w: Walker) -> void:
	_gym_off(w)  # Finish the previous exercise before assigning the new one.
	var place: Dictionary = w.data["place"]
	var xf: Transform3D = place["xf"]
	w.node.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	if place["use"] == "guest_gym_ride":
		w.node.global_position += xf.basis.z.normalized() * 0.07
	var anim := str(GUEST_USE[place["use"]][0])
	if place["use"] == "guest_gym_stretch":
		# On a mat: sit-ups, down onto it first.
		var moves: Array = MAT_MOVES.keys().filter(func(m: String) -> bool: return w.anim != null and w.anim.has_animation(m))
		if not moves.is_empty():
			anim = moves[_rng.randi() % moves.size()]
			w.data["mat_move"] = anim
			_gym_hold(w, str(MAT_MOVES[anim]))
	elif WEIGHT_HOLDS.has(place["use"]):
		if place["use"] == "guest_gym_weights":
			var moves: Array = DUMBBELL_MOVES.filter(func(m: String) -> bool: return w.anim != null and w.anim.has_animation("gym/" + m if m == "bicep_curl" else m))
			if not moves.is_empty():
				anim = str(moves[_rng.randi() % moves.size()])
				if anim == "bicep_curl": anim = "gym/bicep_curl"
		_gym_hold(w, str(WEIGHT_HOLDS[place["use"]]))  # (off the rack, in hand)
	elif anim == "bench":
		_rack_bar(w, false)  # (the bar off its rack...)
		if w.data.get("rack_bar_gid", "") == "bench_incline": anim = "bench_incline"
		_gym_hold(w, "bar")  # (... and in their hands)
	if place["use"] == "guest_sim":
		w.data["seated"] = true
		_sim_swing(w)
		return
	if place["use"] == "guest_bar":
		_bar_drink(w)  # (sat up at the bar with a drink: user)
	if w.anim != null and not w.anim.has_animation(anim):
		anim = {"elliptical": "walk", "spin": "ride", "bench": "sit"}.get(anim, "work")
	w.rest = anim
	if anim == "situps" and w.anim.has_animation("situp_in"):
		w.anim.play("situp_in", 0.2)
		w.anim.queue("situps")
	else:
		_play(w, anim)
	w.data["seated"] = true


## `w` sat at the bar with a pint in their right hand, lifting it to drink now and then (DrinkArm).
func _bar_drink(w: Walker) -> void:
	var skel := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone("hand.R") < 0 or w.data.has("drink"):
		return
	# DrinkArm positions this in skeleton space with the palm around its side.
	# A bone attachment would inherit the club grip's downward pointing axis.
	var cup := Node3D.new()
	cup.name = "Drink"
	skel.add_child(cup)
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.038
	cm.bottom_radius = 0.03
	cm.height = 0.13
	cm.cap_top = false
	cm.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.15
	cm.material = mat
	glass.mesh = cm
	cup.add_child(glass)
	var liquid := MeshInstance3D.new()
	var fill := CylinderMesh.new()
	fill.top_radius = 0.034
	fill.bottom_radius = 0.027
	fill.height = 0.108
	fill.radial_segments = 24
	var lager := StandardMaterial3D.new()
	lager.albedo_color = Color("bc791b")
	lager.roughness = 0.25
	fill.material = lager
	liquid.mesh = fill
	liquid.position.y = -0.006
	cup.add_child(liquid)
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0355
	ring.outer_radius = 0.0385
	ring.rings = 24
	ring.ring_segments = 8
	ring.material = mat
	rim.mesh = ring
	rim.position.y = 0.065
	cup.add_child(rim)
	w.data["drink"] = [cup, DrinkArm.on(skel, cup)]


## The drink put down: glass and arm as they were.
func _bar_drink_off(w: Walker) -> void:
	for n: Variant in w.data.get("drink", []):
		if is_instance_valid(n):
			(n as Node).queue_free()
	w.data.erase("drink")


## A member's shot in a simulator bay: addressing the ball on its mat (their place), aimed at the
## screen, and swinging; the next in SIM_SWING s or so.
func _sim_swing(w: Walker) -> void:
	var house := _fac("clubhouse")
	var place: Dictionary = w.data.get("place", {})
	if house == null or place.is_empty():
		return
	var ball: Vector3 = (place["xf"] as Transform3D).origin + Vector3(0, 0.021, 0)
	var aim := house.global_transform.basis * Vector3(-1, 0, 0)  # (the bays' screens are on the room's west wall)
	_address_ball(w, ball, Vector2(aim.x, aim.z), false)
	_play(w, "swing")
	if w.anim != null:
		w.anim.stop()
		w.anim.play("swing", 0)
	w.rest = "idle"
	w.data["sim_next"] = SIM_SWING + _rng.randf_range(-2.0, 3.0)
	_sim_ball(ball, aim)


## A ball off the mat at `at` into the simulator's screen (`aim` toward it): struck at the swing's
## impact, into the screen at chest height, dropping off it to the floor and gone a while later.
func _sim_ball(at: Vector3, aim: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0214
	sm.height = 0.0428
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f6f6f2")
	sm.material = mat
	ball.mesh = sm
	add_child(ball)
	ball.global_position = at
	var d := Vector3(aim.x, 0.0, aim.z).normalized()
	var screen := at + d * 2.75 + Vector3(0, 1.1, 0)  # (the bay's screen: 2.8 m on from the mat's ball, about)
	var floor_at := at + d * 2.55
	var t := create_tween()
	t.tween_interval(float(IMPACTS.get("swing", 1.0)))
	t.tween_property(ball, "global_position", screen, 0.12)
	t.tween_property(ball, "global_position", floor_at, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(ball, "global_position", floor_at - d * 0.4, 0.8).set_ease(Tween.EASE_OUT)
	t.tween_interval(6.0)
	t.tween_callback(ball.queue_free)


## Gym member `g` (in on their own) up off their machine or mat and across to another they
## haven't used yet this visit, a free one. False, still on theirs, when there's none (or no way).
func _next_station(g: Group) -> bool:
	var house := _fac("clubhouse")
	if house == null or g.golfers.size() != 1:
		return false
	var w: Walker = g.golfers[0]
	var place: Dictionary = w.data.get("place", {})
	if place.is_empty():
		return false
	var done: Array = w.data.get_or_add("gym_done", [])
	done.append(place["use"])
	var free := _free_places("spa_fitness", GYM_USES).filter(func(p: Dictionary) -> bool: return not done.has(p["use"]))
	if free.is_empty():
		return false
	var pick: Dictionary = free[_rng.randi() % free.size()]
	var inv := house.global_transform.affine_inverse()
	var from := inv * Vector3(_place_step(place).x, 0, _place_step(place).y)
	var next := _place_step(pick)
	var to := inv * Vector3(next.x, 0, next.y)
	_indoor_guest_nav(house)
	var route := FacilityBuilder.nav_route(house, "indoor_guest", Vector2(from.x, from.z), Vector2(to.x, to.z))
	if route.is_empty():
		return false
	_guest_places.erase(place["key"])
	var step := _place_step(place)
	w.node.global_position = Vector3(step.x, _surface_y(step), step.y)
	_gym_off(w)
	w.rest = "idle"
	_play(w, "idle")
	w.data.erase("seated")
	var pts: Array = []
	for q in route:
		pts.append(house.global_transform * Vector3(q.x, 0, q.y))
	w.path = pts
	w.data["walk_region"] = {"nav": FacilityBuilder.rig(house)["nav"]["indoor_guest"], "xf": house.global_transform}
	w.data["blocked"] = false
	_guest_places[pick["key"]] = w
	w.data["place"] = pick
	g.phase = "to_place"
	return true


## Keep the actual skinned body on its mat through lying down, repetitions and rising.
## Skinning these contact samples also works in headless simulations.
func _mat_contact(w: Walker) -> void:
	var skel := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null: return
	var parts: Array = w.data.get("mat_skin", [])
	if parts.is_empty():
		for mi in w.node.find_children("*", "MeshInstance3D", true, false):
			if mi.skin == null: continue
			for s in mi.mesh.get_surface_count():
				var a: Array = mi.mesh.surface_get_arrays(s)
				if a[Mesh.ARRAY_BONES] != null and not a[Mesh.ARRAY_BONES].is_empty():
					parts.append([mi.skin, a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_BONES], a[Mesh.ARRAY_WEIGHTS]])
		w.data["mat_skin"] = parts
	var low := INF
	var local := w.node.global_transform.affine_inverse() * skel.global_transform
	for part: Array in parts:
		var skin: Skin = part[0]
		var palette: Array[Transform3D] = []
		for i in skin.get_bind_count():
			var bone := skel.find_bone(skin.get_bind_name(i)) if skin.get_bind_name(i) != &"" else skin.get_bind_bone(i)
			palette.append(local * skel.get_bone_global_pose(bone) * skin.get_bind_pose(i))
		var vertices: PackedVector3Array = part[1]
		var bones: PackedInt32Array = part[2]
		var weights: PackedFloat32Array = part[3]
		var influences: int = bones.size() / vertices.size()
		for i in vertices.size():
			var v := Vector3.ZERO
			for j in influences:
				var at: int = i * influences + j
				if weights[at] > 0: v += (palette[bones[at]] * vertices[i]) * weights[at]
			low = minf(low, v.y)
	if low != INF:
		w.node.global_position.y = (w.data["place"]["xf"] as Transform3D).origin.y - low


## What a gym member holds for their exercise ("kettlebell": the gym's, in both hands; "dumbbells":
## one in each; "bar": a barbell across both, the bench press; "": nothing), kept in their hands
## as they move (_gym_follow).
func _gym_hold(w: Walker, kind: String) -> void:
	if kind == "":
		return
	var held := Node3D.new()
	held.name = "GymHeld"
	add_child(held)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("1c1d1f")
	iron.roughness = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("c9ccd0")
	steel.metallic = 1.0
	steel.roughness = 0.2
	if kind == "kettlebell":
		var scene := _scene(GYM_KETTLEBELL)
		if scene != null:
			var bell := scene.instantiate() as Node3D
			held.add_child(bell)
			bell.position = Vector3(0, -0.3, 0)  # (hung from its handle, in the hands)
	elif kind == "dumbbells":
		for side in [-1.0, 1.0]:
			var one := Node3D.new()
			held.add_child(one)
			one.name = "L" if side < 0 else "R"
			var handle := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.016
			hm.bottom_radius = 0.016
			hm.height = 0.14
			hm.material = steel
			handle.mesh = hm
			handle.rotation = Vector3(0, 0, PI * 0.5)
			one.add_child(handle)
			for end in [-0.09, 0.09]:
				var head := MeshInstance3D.new()
				var dm := CylinderMesh.new()
				dm.top_radius = 0.05
				dm.bottom_radius = 0.05
				dm.height = 0.05
				dm.radial_segments = 6
				dm.material = iron
				head.mesh = dm
				head.rotation = Vector3(0, 0, PI * 0.5)
				head.position = Vector3(end, 0, 0)
				one.add_child(head)
	elif kind == "bar":
		# the rack's own barbell, lifted off it (FacilityBuilder.bench_split): its middle in the hands
		var mesh: Mesh = FacilityBuilder.bench_split(str(w.data.get("rack_bar_gid", "bench_flat")))[1]
		if mesh != null:
			var bar := MeshInstance3D.new()
			bar.mesh = mesh
			bar.position = -mesh.get_aabb().get_center()
			held.add_child(bar)
	w.data["gym_held"] = {"node": held, "kind": kind}
	_gym_follow(w)


## Whatever a gym member's holding put back (a bar back on its rack).
func _gym_off(w: Walker) -> void:
	var h: Dictionary = w.data.get("gym_held", {})
	if h.has("node") and is_instance_valid(h["node"]):
		(h["node"] as Node).queue_free()
	if str(h.get("kind", "")) == "bar":
		_rack_bar(w, true)
	for key in ["gym_held", "mat_move", "rising", "mat_skin"]:
		w.data.erase(key)


## The barbell racked on the bench `w` is at (the clubhouse's bench racks draw theirs apart:
## FacilityBuilder.bench_split) shown, or (`racked` false: they've taken it off to press) not.
func _rack_bar(w: Walker, racked: bool) -> void:
	var house := _fac("clubhouse")
	var place: Dictionary = w.data.get("place", {})
	if house == null:
		return
	if racked:
		var was: Array = w.data.get("rack_bar", [])
		w.data.erase("rack_bar")
		w.data.erase("rack_bar_gid")
		if was.size() == 3 and is_instance_valid(was[0]):
			(was[0] as MultiMeshInstance3D).multimesh.set_instance_transform(was[1], was[2])
		return
	if place.is_empty():
		return
	var at: Vector3 = (place["xf"] as Transform3D).origin
	for mmi in house.find_children("Batch_GYM_bench_*_bar", "MultiMeshInstance3D", true, false):
		var mm := (mmi as MultiMeshInstance3D).multimesh
		for i in range(mm.instance_count):
			var xf := mm.get_instance_transform(i)
			if ((mmi as Node3D).global_transform * xf.origin).distance_to(at) < 1.2 and xf.basis.get_scale().x > 0.01:
				w.data["rack_bar"] = [mmi, i, xf]
				w.data["rack_bar_gid"] = String((mmi as Node).name).trim_prefix("Batch_GYM_").trim_suffix("_bar")
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin))
				return


## The member's weight in their hands where the pose has them: a kettlebell hung below both hands
## along the arms' line, a dumbbell in each fist, a bar across both.
func _gym_follow(w: Walker) -> void:
	var h: Dictionary = w.data["gym_held"]
	var held: Node3D = h["node"]
	var skel := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or not is_instance_valid(held):
		return
	var grips := []
	for side in ["L", "R"]:
		var bone := skel.find_bone("grip." + side)
		if bone < 0:
			bone = skel.find_bone("hand." + side)
		grips.append(skel.global_transform * skel.get_bone_global_pose(bone))
	var a: Vector3 = (grips[0] as Transform3D).origin
	var b: Vector3 = (grips[1] as Transform3D).origin
	var mid := (a + b) * 0.5
	match str(h["kind"]):
		"kettlebell":
			var chest := skel.find_bone("chest")
			var shoulders := (skel.global_transform * skel.get_bone_global_pose(chest)).origin if chest >= 0 else mid + Vector3.UP
			var down := (mid - shoulders).normalized()
			var side := w.node.global_transform.basis.x.normalized()
			var fwd := side.cross(-down).normalized()
			held.global_transform = Transform3D(Basis(side, -down, fwd), mid)
		"dumbbells":
			held.global_transform = Transform3D(Basis(), mid)
			for k in range(2):
				var one := held.get_child(k) as Node3D
				var g: Transform3D = grips[k]
				one.global_transform = Transform3D(Basis(w.node.global_transform.basis.x.normalized(), Vector3.UP, w.node.global_transform.basis.z.normalized()), g.origin)
		"bar":
			var across := (b - a).normalized() if a.distance_to(b) > 0.05 else w.node.global_transform.basis.x.normalized()
			var up := across.cross(w.node.global_transform.basis.z.normalized()).normalized()
			if up.y < 0.0:
				up = -up
			held.global_transform = Transform3D(Basis(across, up, across.cross(up)), mid)


## Up from their places and out of the clubhouse toward the car park (their bags waiting outside).
func _leave_places(g: Group) -> void:
	var house := _fac("clubhouse")
	var nav_key := "indoor_guest" if g.visit == "gym" else "guest"
	if g.visit == "gym" and house != null: _indoor_guest_nav(house)
	for w: Walker in g.golfers:
		var place: Dictionary = w.data.get("place", {})
		if place.is_empty():
			continue
		_guest_places.erase(place["key"])
		var step := _place_step(place)
		w.node.global_position = Vector3(step.x, _surface_y(step), step.y)
		_gym_off(w)
		_bar_drink_off(w)
		w.rest = "idle"
		_play(w, "idle")
		w.data.erase("place")
		w.data.erase("seated")
	var fl := (_front_door(house) if g.visit == "gym" else _house_exit(house)) if house != null else Vector2.INF
	var routes: Array = []
	if fl != Vector2.INF:
		var n := g.golfers.size()
		for k in range(n):
			var here := house.global_transform.affine_inverse() * (g.golfers[k] as Walker).node.global_position
			var inside := FacilityBuilder.nav_route(house, nav_key, Vector2(here.x, here.z), fl + Vector2((k - (n - 1) * 0.5) * 1.1, 0))
			if inside.is_empty():
				break
			var pts: Array = []
			for q in inside:
				pts.append(house.global_transform * Vector3(q.x, 0, q.y))
			routes.append(pts)
	if routes.size() < g.golfers.size():
		for w: Walker in g.golfers:
			_valet_give(w)
		_to_parking(g)
		return
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		w.data["blocked"] = false
		w.data["hold"] = _rng.randf_range(0.0, 1.2)
		w.path = routes[k]
		w.data["walk_region"] = {"nav": FacilityBuilder.rig(house)["nav"][nav_key], "xf": house.global_transform}
	_valet_return(g)  # (their bags waiting outside the door they leave by)
	g.phase = "through_clubhouse"  # (then over to the car park)


## Out to the car park: to the edge of the lot nearest them (then across it to the car).
func _to_parking(g: Group) -> void:
	if _valet_request_pickup(g):return
	if g.valet_service.has("pocket_slot"):
		for k in range(g.golfers.size()):_go(g.golfers[k],_by_car(g,k))
		g.exit_path=_valet_pocket_path(int(g.valet_service["pocket_slot"]),false)+_valet_drive_out()
		g.phase="return_car"
		return
	var at := Vector2.ZERO
	for w: Walker in g.golfers:
		at += Vector2(w.node.global_position.x, w.node.global_position.z) / maxf(g.golfers.size(), 1)
	var edge := _lot_edge(at)
	_go_together(g, edge if edge != Vector2.INF else Vector2(g.parking_path[0].x, g.parking_path[0].z))
	g.phase = "return_parking"


## Where golfer `k` stands by the flight's parked car: in the aisle just behind it, side by side.
func _by_car(g: Group, k: int) -> Vector2:
	var xf := g.car.node.global_transform
	var p := xf.origin + xf.basis.z.normalized() * 3.2 + xf.basis.x.normalized() * (k - (g.golfers.size() - 1) * 0.5) * 0.9
	return Vector2(p.x, p.z)


## Just off the parking lot on its side nearest `toward` (world XZ): where people step on or off
## it (INF without a lot).
func _lot_edge(toward: Vector2) -> Vector2:
	var lot := _fac("parking_lot")
	if lot == null:
		return Vector2.INF
	var l := lot.global_transform.affine_inverse() * Vector3(toward.x, 0, toward.y)
	var half := FacilityBuilder.footprint("parking_lot") * 0.5 + Vector2(3.0, 3.0)
	var p := Vector2(clampf(l.x, -half.x, half.x), clampf(l.z, -half.y, half.y))
	if absf(p.x) < half.x and absf(p.y) < half.y:  # `toward` is on the lot: out by its nearest side
		if half.x - absf(p.x) < half.y - absf(p.y):
			p.x = signf(p.x) * half.x
		else:
			p.y = signf(p.y) * half.y
	var w := lot.global_transform * Vector3(p.x, 0, p.y)
	return _open_spot(Vector2(w.x, w.z))


## Across the lot by its lane edges and perimeter, crossing drives only where needed.
func _lot_walk(from: Vector2, to: Vector2) -> Array:
	var detailed := _grounds_path(from, to)
	if not detailed.is_empty(): return detailed
	var lot := _fac("parking_lot")
	var out: Array = []
	if lot != null and FacilityBuilder.nav_has(lot, "pedestrian"):
		var inv := lot.global_transform.affine_inverse()
		var a := inv * Vector3(from.x, 0, from.y)
		var b := inv * Vector3(to.x, 0, to.y)
		var pts := FacilityBuilder.nav_route(lot, "pedestrian", Vector2(a.x, a.z), Vector2(b.x, b.z))
		for i in range(1, pts.size()):
			out.append(lot.global_transform * Vector3(pts[i].x, 0, pts[i].y))
	out.append(Vector3(to.x, 0, to.y))
	return out


func _begin_departure(g: Group) -> void:
	g.hole_reserved = false
	g.queue_hole = -1
	g.queue_ticket = -1  # Finished flights must not keep a place in the last tee's queue.
	for w in g.golfers:
		_bag_up(w)
	for ball in g.balls:
		ball.visible = false
	if g.car == null:
		_groups.erase(g)
		_invalidate_traffic()
		_free_group(g)
		return
	var target := _facility_front("cart_barn") if not g.carts.is_empty() else _clubhouse_back()
	if target == Vector2.INF:
		target = _facility_front("clubhouse")
	if g.carts.is_empty():
		_go_together(g, target)  # each to a spot of their own, not all to the one
	for k in range(g.golfers.size()):
		if not g.carts.is_empty():
			_seat(g.golfers[k],g.carts[k/2],k%2)
	for c in g.carts:
		var park := _barn_spot(c)  # back to the barn's row, outside it
		if park != Vector2.INF:
			_park_in_row(c, park)
			continue
		park = _cart_parking_point(target, c)
		if park != Vector2.INF:
			_go(c, park)
	_stagger(g)
	g.phase = "return_carts"


func _visit_phase(g: Group, delta: float) -> bool:
	if g.phase in ["valet_arrival_queue","valet_greet","valet_dropoff","valet_pickup_wait","valet_board"]:return true
	match g.phase:
		"arrive":
			if g.car.path.is_empty():
				if g.valet_service.get("stage","")=="arrival":
					_valet_unload_arrival(g)
					return true
				if g.visit not in ["gym", "range", "sim", "bar"] and g.lane < 0 and not _lobby_lane(g):
					return true  # the lobby's lines are full: they sit in the car till there's room
				for k in range(g.golfers.size()):
					var w: Walker = g.golfers[k]
					if w.riding:
						_unseat(w,g.carts[k/2],k%2)
					w.node.visible = true
					var at := _by_car(g, k)
					w.node.global_position = Vector3(at.x, _surface_y(at), at.y)
					if g.visit != "range":
						_go(w, _door_step(k))
						w.data["hold"] = k * 0.8 + _rng.randf_range(0.0, 0.3)  # single file up to the door
				g.timer = 0.0
				g.phase = "parking_walk"
				if g.visit == "range":
					# in for a bucket of balls alone: nothing to check in for at the clubhouse --
					# straight over to the range's ball dispenser and on to a bay
					g.checked_in = true
					g.phase = "range_front"
		"parking_walk":
			if g.visit in ["gym", "sim", "bar"]:
				if not _moving(g.golfers):
					g.phase = "gym_door"
			elif g.lane >= 0:
				if _lobby_arrivals(g):
					g.timer = 0.0
					g.phase = "shop_front"  # (the first of them in at the front door)
				elif not _moving(g.golfers):
					if g.golfers.any(func(w:Walker)->bool:return w.data.get("self_park_driver",false)):return true
					g.timer += delta
					if g.timer > 6.0:
						g.lane = -1  # no way in to their lane: up to the desk all together instead
			elif not _moving(g.golfers):
				g.phase = "shop_front"
		"gym_door":
			# a member, in by the front door (no checking in at the shop) to a free machine -- or
			# a free simulator bay
			var room: String = {"sim": "simulator", "bar": "restaurant"}.get(g.visit, "spa_fitness")
			var uses: Array = {"sim": ["guest_sim"], "bar": ["guest_bar"]}.get(g.visit, GYM_USES)
			if not _moving(g.golfers) and not _to_places(g, room, uses, false):
				_to_parking(g)  # full: home again
		"to_place":
			# each up onto their stool, into their chair or onto their machine as they get to it
			var settled := true
			for w: Walker in g.golfers:
				if w.data.get("seated", false):
					continue
				settled = false
				if w.path.is_empty():
					if g.visit == "gym" and Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(_place_step(w.data["place"])) > 0.85:
						_leave_places(g)
						return true
					_use_place(w)
			if settled:
				g.timer = _rng.randf_range(35.0, 65.0) if g.visit == "gym" else (_rng.randf_range(150.0, 240.0) if g.visit == "sim" else (_rng.randf_range(70.0, 130.0) if g.visit == "bar" else _rng.randf_range(40.0, 75.0)))
				if g.visit == "gym" and g.gym_left < 0:
					g.gym_left = _rng.randi_range(1, 2)  # (a couple of exercises more after this one)
				g.phase = "at_place"
		"at_place":
			g.timer -= delta
			if g.visit == "sim":
				for w: Walker in g.golfers:
					w.data["sim_next"] = float(w.data.get("sim_next", SIM_SWING)) - delta
					if float(w.data["sim_next"]) <= 0.0:
						_sim_swing(w)
			if g.timer <= 0.0:
				var up := false
				for w: Walker in g.golfers:
					if w.data.get("mat_move", "") == "situps" and not w.data.get("rising", false):
						# up off the mat first
						w.data["rising"] = true
						if w.anim != null and w.anim.has_animation("situp_out"):
							w.anim.play("situp_out", 0.2)
							g.timer = w.anim.get_animation("situp_out").length
							up = true
				if up:
					return true
				if g.visit == "gym" and g.gym_left > 0 and _next_station(g):
					g.gym_left -= 1
				else:
					_leave_places(g)
		"shop_front":
			if g.lane >= 0:
				# in at the front door one by one as they get to it, each to their place in the
				# flight's lane in the lobby
				_lobby_arrivals(g)
				var out := g.golfers.filter(func(w: Walker) -> bool: return not w.data.get("lobby", false))
				if out.is_empty():
					if not _moving(g.golfers):
						g.lobby_ticket = _lobby_serial  # their turn at the desk: after those in line before them
						_lobby_serial += 1
						g.phase = "lobby"
						_bag_run(g)  # (all in, their bags at the bag drop: the cart boy on it while they check in)
				elif not _moving(out):
					if out.any(func(w:Walker)->bool:return w.data.get("self_park_driver",false)):return true
					g.timer += delta
					if g.timer > 6.0:
						g.lane = -1  # no way in to their lane: up to the desk all together instead
			elif not _moving(g.golfers) and _inside_guest(g,true):
				g.phase = "shop_walk"
				_bag_run(g)
		"lobby":
			# in line, till the desk's free and it's their turn (in the order flights came in)
			if not _moving(g.golfers) and _next_at_desk() == g and _desk_free(g):
				if _to_desk(g):
					g.phase = "shop_walk"
				else:
					g.lane = -1  # no way on from their lane: up to the desk all together instead
					g.lobby_ticket = -1
					g.phase = "shop_front"
		"shop_walk":
			if not _moving(g.golfers):
				g.timer = 5.0 + g.golfers.size()
				g.phase = "check_in"
		"check_in":
			if g.valet_service.get("stage","") in ["arrival","unload","bag_drop"]:return true
			g.timer -= delta
			if g.timer <= 0:
				for w: Walker in g.golfers:
					w.data.erase("watch")  # (the clerk)
				# riding: out the back to the end of the walk, where the cart boy brings their carts
				# round with their bags on (out of the front door if there's no way out the back); on
				# foot (or with no cart boy): out of the front door for their bags at the bag drop
				_bag_run(g)  # (if he wasn't about when they came in)
				if g.bag_run and (_inside_guest(g, false) or _out_front_for_bags(g, true)):
					g.checked_in = true
					g.timer = 0.0
					g.phase = "cart_wait"
				elif g.bag_run:
					g.timer = 2.0
				elif _out_front_for_bags(g):
					g.checked_in = true
					g.phase = "bag_pickup"
				else:
					g.timer = 2.0
		"delivery_request":
			g.retry -= delta
			if g.retry <= 0.0:
				_send_to_collection(g)
		"cart_wait":
			# each pair to their cart as the cart boy pulls up with it and gets out, and in
			g.timer += delta  # Waiting never substitutes for an attendant handover.
			var aboard := true
			for k in range(g.golfers.size()):
				var w: Walker = g.golfers[k]
				if w.riding and not w.data.has("cart_move"):
					continue  # (sat: not still climbing in)
				aboard = false
				if w.riding:
					continue
				var c: Walker = g.carts[k / 2]
				if not c.data.get("delivered", false):
					if w.path.is_empty() and c.data.has("parking_target"):
						w.data["watch"] = c.data["parking_target"]  # looking out for it
					continue
				if not w.data.get("to_ride", false):
					# The handover supersedes a waiting route, even if that spot is crowded.
					var door := _cart_door(c, k % 2)
					_go(w, Vector2(door.x, door.z))
					w.data["hold"] = _rng.randf_range(0.0, 0.6)
					w.data["to_ride"] = true
				elif w.path.is_empty():
					_board_turned(g, k, delta)
			if aboard:
				for c: Walker in g.carts:
					for key in ["delivered", "parking_target"]:
						c.data.erase(key)
				for w: Walker in g.golfers:
					w.data.erase("to_ride")
				g.bag_run = false
				if not _pre_round_practice(g): g.phase = "tee_queue"
		"bag_pickup":
			var collected := not _moving(g.golfers)
			for w: Walker in g.golfers:
				collected = collected and not w.data.get("valet", false)
			if collected:
				_send_to_collection(g)
		"back_walk":
			# out the back and along the walk: the carts are brought round to meet them there
			if not _moving(g.golfers):
				var at := Vector2.ZERO
				for w in g.golfers:
					at += Vector2(w.node.global_position.x, w.node.global_position.z) / g.golfers.size()
				_send_to_collection(g, at)
		"shop_exit":
			if not _moving(g.golfers):
				_send_to_collection(g)
		"board":
			if _board_arrivals(g, delta):
				if not _pre_round_practice(g):
					if g.queue_hole == g.hole: _hold_for_tee(g)
					g.phase = "tee_queue"
		"practice_depart":
			g.retry -= delta
			if g.retry <= 0.0 and not _pre_round_practice(g): g.phase = "tee_queue"
		"collect":
			if not _moving(g.golfers):
				if g.range_visit:
					if not _start_range(g):  # (each straight off to their own bay; all taken: wait by it)
						_go_together(g, _facility_front("driving_range"))
						g.phase = "range_front"
				elif g.short_visit and _fac("short_game") != null:
					_go_together(g, _facility_front("short_game"))
					g.phase = "short_front"
				else:
					g.phase = "tee_queue"
		"practice_park":
			if not _moving(g.carts):
				var out := true
				for k in range(g.golfers.size()):
					var w: Walker = g.golfers[k]
					if w.riding:
						out = false
						if not w.data.has("cart_move"): _climb_out(w, g.carts[k / 2], k % 2)
				if out:
					_practice_bags_off(g)
					_go_together(g, _facility_front(g.wait_facility))
					g.phase = "short_front" if g.wait_facility == "short_game" else "range_front"
		"short_front":
			if not _moving(g.golfers):
				_start_short(g)
		"short_walk":
			if not _moving(g.golfers):
				for k in range(g.golfers.size()):
					var w: Walker = g.golfers[k]
					_face_practice(w)
					_bag_down(w)
					# each at their own pace, a stroke at a time: putting takes a good while (in for
					# the practice alone, longer still), a few chips less; warming up before a
					# round, about half
					var putting: bool = (w.data.get("practice", {}) as Dictionary).get("kind", "putt") == "putt"
					var strokes := _rng.randi_range(16, 26) if putting else _rng.randi_range(9, 14)
					w.data["short_left"] = strokes if g.visit != "" else ceili(strokes * (0.6 if g.wait_practice else 0.45))
					w.data["short_next"] = _rng.randf_range(0.8, 3.0)
				g.phase = "short_practice"
		"short_practice":
			var practising := false
			for k in range(g.golfers.size()):
				var w: Walker = g.golfers[k]
				if int(w.data.get("short_left", 0)) <= 0:
					continue
				practising = true
				w.data["short_next"] = float(w.data["short_next"]) - delta
				if float(w.data["short_next"]) <= 0.0:
					var putting: bool = (w.data.get("practice", {}) as Dictionary).get("kind", "putt") == "putt"
					_practice_stroke(g, k)
					w.data["short_left"] = int(w.data["short_left"]) - 1
					w.data["short_next"] = (PUTT_S if putting else CHIP_S) + _rng.randf_range(1.2, 3.4)
			# (called up to the tee while they're at it, waiting their turn on it: off there now)
			if g.wait_practice and _tee_rank(g) > 0 and not practising:
				for w: Walker in g.golfers: w.data["short_left"] = 6
			if (not g.wait_practice and not practising) or (g.wait_practice and _tee_rank(g) == 0 and g.wait_practice_elapsed >= 20.0):
				var fac := _fac("short_game")
				for k in range(g.golfers.size()):
					var w: Walker = g.golfers[k]
					w.data.erase("short_left")
					w.data.erase("short_next")
					_bag_up(w)
					var out := Vector2((k - g.golfers.size() * 0.5) * 0.8, -FacilityBuilder.footprint("short_game").y*.5-4.0)
					_go_inside(w,fac,"",out,0.0)
					if w.data.get("blocked", false):
						# (no way off its walks from where they stood -- a mat or a green it doesn't
						# map: they froze there, user): across the ground to it instead
						w.data["blocked"] = false
						w.data.erase("indoor_target")
						w.data.erase("walk_region")
						w.ground = true
						var world := fac.global_transform * Vector3(out.x, 0.0, out.y)
						_go(w, Vector2(world.x, world.z))
				g.timer = 0.0
				g.phase = "short_exit"
		"short_exit":
			g.timer += delta
			if _moving(g.golfers) and g.timer > 25.0:
				for w: Walker in g.golfers:  # (still held up: on all the same, not stood there for good)
					if w.data.get("blocked", false):
						w.data["blocked"] = false
						w.data.erase("indoor_target")
						w.data.erase("outdoor_target")
						w.path.clear()
			if not _moving(g.golfers):
				_clear_practice(g)
				g.short_visit = false
				if g.visit != "":
					_to_parking(g)  # in for the practice alone: home
					return true
				if g.wait_practice:
					g.wait_practice = false
					if g.carts.is_empty():
						_hold_for_tee(g)
						g.phase = "tee_queue"
					else:
						_send_to_collection(g)
					return true
				var at := Vector2.ZERO
				for w in g.golfers:
					at += Vector2(w.node.global_position.x, w.node.global_position.z) / g.golfers.size()
				_send_to_collection(g, at)
		"range_front":
			# Each free bay admits one person, even when their companions still need a slot.
			_start_range(g)
		"range_practice":
			# each golfer on their own, not waiting for the rest (_range_golfers); the flight on
			# when they've all done
			if _range_golfers(g, delta):
				_clear_practice(g)
				g.range_visit = false
				if g.visit != "":
					_to_parking(g)  # in for a bucket of balls alone: home
					return true
				if g.wait_practice:
					g.wait_practice = false
					if g.carts.is_empty():
						_hold_for_tee(g)
						g.phase = "tee_queue"
					else:
						_send_to_collection(g)
				else:
					_send_to_collection(g)
		"tee_queue":
			if g.queue_hole != g.hole:
				_wait_for_tee(g)
				if g.phase != "tee_queue": return true
			if _moving(g.golfers) or _moving(g.carts):
				return true
			if _tee_entry_blocked(g):
				if _try_wait_practice(g): return true
				if _tee_rank(g) < g.queue_rank:
					_hold_for_tee(g)  # the flight ahead was called up to the tee: up a place in line
				return true
			g.hole_reserved = true
			for ball in g.balls:
				ball.visible = false  # each player tees up only when it is their turn
			_go_play(g)
		"return_carts":
			if not _moving(g.carts) and not _moving(g.golfers):
				for c in g.carts:
					var spot := _row_spot_at(Vector2(c.node.global_position.x, c.node.global_position.z))
					if spot != Vector2.INF:
						_settle_in_row(c, spot)  # squared up in its spot
				for k in range(g.golfers.size()):
					if g.golfers[k].riding:
						_unseat(g.golfers[k],g.carts[k/2],k%2)
						_carry_bag(g.golfers[k], str(g.golfers[k].data.get("bag_livery", "")))  # their bag off the cart and home with them
				for c in g.carts:
					for bag in c.data.get("bags", []):
						if is_instance_valid(bag):
							(bag as Node).queue_free()
					c.data["bags"] = []
					# left at the barn for the cart boy (past a dozen, put away inside)
					if _stock.size() < STOCK_MAX:
						_stock.append(c)
						_pool.append(c)
						_invalidate_traffic()
					else:
						c.node.queue_free()
				g.carts.clear()
				_invalidate_traffic()
				# home by way of the clubhouse: up the walk, in at the back, out of the front door
				var back := _clubhouse_back()
				if back != Vector2.INF:
					_go_together(g, back)
					g.phase = "to_clubhouse"
				else:
					_to_parking(g)
		"to_clubhouse":
			if not _moving(g.golfers):
				if _nineteenth(g):
					pass  # in to sit down a while (_to_places)
				elif _through_clubhouse(g):
					g.phase = "through_clubhouse"
				else:
					_to_parking(g)
		"through_clubhouse":
			if not _moving(g.golfers):
				_to_parking(g)
		"return_parking":
			# each on across the lot to the car as they get to its edge, not waiting there for the rest
			var all_on := true
			for k in range(g.golfers.size()):
				var w: Walker = g.golfers[k]
				if w.data.get("to_car", false):
					continue
				all_on = false
				if w.path.is_empty() and not w.data.get("blocked", false):
					w.path = _lot_walk(Vector2(w.node.global_position.x, w.node.global_position.z), _by_car(g, k))
					w.data["to_car"] = true
			if all_on:
				for w: Walker in g.golfers:
					w.data.erase("to_car")
				g.timer = 0.0  # (how long they've sat waiting for the lot to clear)
				g.phase = "return_car"
		"return_car":
			if not _moving(g.golfers):
				for w in g.golfers:
					w.node.visible = false
				# in, and waiting in the space till the lot's clear of anyone driving by before
				# pulling out (user) -- not for ever, should it never quite clear
				g.timer += delta
				if _lot_traffic(g.car) and g.timer < 40.0:
					return true
				g.timer = 0.0
				g.car.path = g.exit_path.duplicate()  # out by the lot's way out
				g.phase = "leave"
		"leave":
			if g.car.path.is_empty():
				_groups.erase(g)
				_invalidate_traffic()
				_free_group(g)
		_:
			return false
	return true

func _bag_scene(livery: String = "") -> PackedScene:
	return _scene(BAG % (livery if livery != "" else FacilityBuilder.PLAYER_BAGS[_rng.randi() % FacilityBuilder.PLAYER_BAGS.size()]))


## Sling a bag across `w`'s back: base by the right hip, the club heads over the left shoulder,
## pockets out. The bag (1.2 m to the top of the driver) is carried full size. A second (`key`
## "bag2": the cart boy bringing two over at once) the other way across, over the right shoulder.
func _carry_bag(w: Walker, livery: String = "", key: String = "bag") -> void:
	var skel := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if livery == "":
		livery = FacilityBuilder.PLAYER_BAGS[_rng.randi() % FacilityBuilder.PLAYER_BAGS.size()]
	var scene := _bag_scene(livery)
	if skel == null or scene == null:
		return
	var bone := skel.find_bone("chest")
	if bone < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = bone
	skel.add_child(att)
	var bag := scene.instantiate() as Node3D
	att.add_child(bag)
	# in the character's own frame (faces -Z, its back toward +Z)
	var side := 1.0 if key == "bag" else -1.0
	var behind := 0.0 if key == "bag" else 0.13  # (the second over the first)
	var bottom := Vector3(0.24 * side, 0.6, 0.25 + behind)
	var top := Vector3(-0.3 * side, 1.62, 0.31 + behind)
	var up := (top - bottom).normalized()
	var out := Vector3(0, 0, 1)
	var x := up.cross(out).normalized()
	out = x.cross(up).normalized()
	var want := Transform3D(Basis(x, up, out), bottom)
	# `want` is in the person's frame; the skeleton may sit under its own transformed node
	var skel_in_person := w.node.global_transform.affine_inverse() * skel.global_transform
	bag.transform = skel.get_bone_global_rest(bone).affine_inverse() * skel_in_person.affine_inverse() * want
	w.data[key] = bag
	if key == "bag":
		w.data["bag_livery"] = livery


## A walking golfer sets their bag down to play: the same bag stood on its legs (golf_bag_<livery>_stand,
## tools/blender/bag_stands.py) at their right, a little behind, out of the swing.
func _bag_down(w: Walker) -> void:
	var bag: Node3D = w.data.get("bag")
	if bag == null or not bag.visible:
		return
	var scene := _scene(BAG % (str(w.data["bag_livery"]) + "_stand"))
	if scene == null:
		return
	var at := w.node.global_transform
	var p := at.origin + at.basis.x.normalized() * 0.9 + at.basis.z.normalized() * 0.35
	var parking := _bag_parking_spot(Vector2(p.x, p.z))
	if parking == Vector2.INF:
		return
	# pockets toward the golfer, its legs out away from them
	_bag_down_at(w, Vector3(parking.x, _surface_y(parking), parking.y), w.node.global_rotation.y - PI * 0.5)


## `w`'s bag off their back and stood on its legs at `p`, turned `yaw`.
func _bag_down_at(w: Walker, p: Vector3, yaw: float) -> void:
	var bag: Node3D = w.data.get("bag")
	if bag == null or not bag.visible:
		return
	var scene := _scene(BAG % (str(w.data["bag_livery"]) + "_stand"))
	if scene == null:
		return
	var stand := scene.instantiate() as Node3D
	stand.name = "BagDown"
	add_child(stand)
	stand.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	bag.visible = false
	w.data["bag_down"] = stand


## The putting surface never holds a parked bag, including the stand's legs.
## Search outward to the nearest clear strip just beyond the green's edge.
func _bag_parking_spot(want: Vector2) -> Vector2:
	if _bag_ground_clear(want):
		return want
	for ring in range(1, 101):
		var best := Vector2.INF
		var score := INF
		for i in range(32):
			var p := want + Vector2.from_angle(i * TAU / 32.0) * ring * .5
			if not _bag_ground_clear(p):
				continue
			var near_green := false
			for j in range(8):
				near_green = near_green or course.surface_at(p + Vector2.from_angle(j * TAU / 8.0) * 1.5) == PaintedCourse.Surface.GREEN
			if not near_green:
				continue
			var clear := true
			for stand in find_children("BagDown*", "Node3D", false, false):
				var s: Vector3 = stand.global_position
				clear = clear and p.distance_to(Vector2(s.x, s.z)) > .9
			if clear and p.distance_squared_to(want) < score:
				best = p
				score = p.distance_squared_to(want)
		if best != Vector2.INF:
			return best
	return Vector2.INF


func _bag_ground_clear(at: Vector2) -> bool:
	for i in range(9):
		var p := at if i == 8 else at + Vector2.from_angle(i * TAU / 8.0) * .55
		if course.surface_at(p) not in [PaintedCourse.Surface.ROUGH, PaintedCourse.Surface.FAIRWAY, PaintedCourse.Surface.TEE]:
			return false
	return true


## ... and slings it back on before walking on (it stands beside them).
func _bag_up(w: Walker) -> void:
	var stand: Variant = w.data.get("bag_down")
	if stand == null:
		return
	if is_instance_valid(stand):
		(stand as Node).queue_free()
	w.data.erase("bag_down")
	(w.data["bag"] as Node3D).visible = true


# ---------------------------------------------------------------- the bag valet
# Nobody takes their clubs into the clubhouse: going in, a golfer hands their bag in (stood at the
# bag drop by the front door, or where they are as they come up the back walk); coming out, the
# valet has it on their cart, or stood waiting where they come out, for them to shoulder there.

## `w`'s bag off their back, stood at `at` (world XZ; the bag drop by the front door if INF).
func _valet_take(w: Walker, at: Vector2 = Vector2.INF) -> void:
	var bag: Variant = w.data.get("bag")
	if bag == null or not is_instance_valid(bag) or not (bag as Node3D).visible:
		return
	if w.data.has("rack_delivery"):return
	var house := _fac("clubhouse")
	if at==Vector2.INF and house!=null and business!=null and business.room_tier("valet")==3:
		var drop:=_bag_drop_spot()
		if drop==Vector2.INF:return
		var delivery:={"drop":drop,"resume":w.path.duplicate(),"ground":w.ground,"rest":w.rest,"placing":-1.0}
		for key in ["walk_region","outdoor_target","indoor_target","watch","hold"]:
			if w.data.has(key):delivery[key]=w.data[key]
		w.data["rack_delivery"]=delivery
		w.ground=true;w.rest="idle"
		_go(w,_valet_rack_approach(drop))
		return
	var p := at if at != Vector2.INF else _bag_drop_spot()
	if p == Vector2.INF:
		return
	_bag_down_at(w, Vector3(p.x, _surface_y(p), p.y), house.global_rotation.y + (PI*.5 if at==Vector2.INF and business!=null and business.room_tier("valet")==3 else PI) if house != null else 0.0)
	w.data["valet"] = true


## Where the next bag handed in at the front door stands (world XZ): in a row along the front of
## the house either side of the door, by turns -- the bag drop.
func _bag_drop_spot() -> Vector2:
	var house := _fac("clubhouse")
	var entry := _clubhouse_entry()
	if house == null or entry == Vector2.INF:return Vector2.INF
	var rig:=FacilityBuilder.rig(house)
	var room:Dictionary=rig.get("boxes",{}).get("valet",{}) if business!=null and business.room_tier("valet")==3 else {}
	if not room.is_empty():
		var rect:Rect2=room["rect"]
		var capacity:=9
		for row in range(1):
			for slot in range(capacity):
				var local:=Vector3(-4.45,0,4.7+slot*.5)
				var candidate:=house.global_transform*local
				var clear:=true
				for group:Group in _groups:
					for owner:Walker in group.golfers:
						var stand:Node3D=owner.data.get("bag_down")
						if is_instance_valid(stand) and stand.global_position.distance_to(Vector3(candidate.x,stand.global_position.y,candidate.z))<.43:clear=false
						var reserved:Dictionary=owner.data.get("rack_delivery",{})
						if not reserved.is_empty() and (reserved["drop"] as Vector2).distance_to(Vector2(candidate.x,candidate.z))<.43:clear=false
				if clear:return Vector2(candidate.x,candidate.z)
		return Vector2.INF
	# Without valet facilities keep bags beside, never on, the entrance route.
	var along := house.global_transform.basis.x.normalized()
	var i := _bag_drop_serial % 16
	_bag_drop_serial += 1
	var p := Vector3(entry.x, 0, entry.y) + along * (2.6 + 0.6 * (i / 2)) * (1.0 if i % 2 == 0 else -1.0)
	return Vector2(p.x, p.z)


## The bag the valet has of `w`'s, stood waiting by `at` (world XZ: where they come out), for them
## to shoulder as they get there (_valet_hand_back).
func _valet_bring(w: Walker, at: Vector2) -> void:
	var stand: Variant = w.data.get("bag_down")
	if not w.data.get("valet", false) or stand == null or not is_instance_valid(stand):
		return
	var p := at + Vector2(0.6, 0.0).rotated(float(w.node.get_instance_id() % 628) * 0.01)
	(stand as Node3D).global_position = Vector3(p.x, _surface_y(p), p.y)
	w.data["valet_at"] = at


## Out of the clubhouse: each of flight `g`'s bags the valet has on their cart already (theirs to
## ride), else waiting where their way out ends.
func _valet_return(g: Group) -> void:
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		if not w.data.get("valet", false):
			continue
		if g.wants_cart and k / 2 < g.carts.size():
			var stand: Variant = w.data.get("bag_down")
			if stand != null and is_instance_valid(stand):
				(stand as Node).queue_free()
			w.data.erase("bag_down")
			_load_bag(w, g.carts[k / 2], k % 2)
			w.data.erase("valet")
		elif not w.path.is_empty():
			var end: Vector3 = w.path[w.path.size() - 1]
			_valet_bring(w, Vector2(end.x, end.z))


## Flight `g`, checked in, back out of the front door to the bag drop, single file, each to their
## own bag there (shouldered as they get to it: _valet_hand_back); or (`wait`: the cart boy's
## bringing their bags round) just out, side by side. False, nothing changed, when there's no way.
func _out_front_for_bags(g: Group, wait: bool = false) -> bool:
	var house := _fac("clubhouse")
	if house == null:
		return false
	var door := _front_door(house)
	if door == Vector2.INF:
		return false
	_indoor_guest_nav(house)
	var inv := house.global_transform.affine_inverse()
	var outside_door := door + Vector2(0, -1.6)  # (the front is -Z)
	var routes: Array = []
	var bags: Array = []
	for w: Walker in g.golfers:
		var here := inv * w.node.global_position
		var stand: Variant = w.data.get("bag_down")
		var to := door + Vector2((routes.size() - (g.golfers.size() - 1) * 0.5) * 0.9 if wait else 0.0, -2.6)  # (no bag of theirs there: just outside)
		var bag := Vector2.INF
		if not wait and w.data.get("valet", false) and stand != null and is_instance_valid(stand):
			var s := inv * (stand as Node3D).global_position
			to = Vector2(s.x, s.z) + (outside_door - Vector2(s.x, s.z)).normalized() * 0.6  # beside it, the door's side
			bag = Vector2((stand as Node3D).global_position.x, (stand as Node3D).global_position.z)
		var inside := FacilityBuilder.nav_route(house, "indoor_guest", Vector2(here.x, here.z), door + Vector2(0, 1.2))
		var out := FacilityBuilder.nav_route(house, "guest", outside_door, to)
		if inside.is_empty() or out.is_empty():
			return false
		var pts: Array = []
		for q in inside:
			pts.append(house.global_transform * Vector3(q.x, 0, q.y))
		pts.append(house.global_transform * Vector3(door.x, 0, door.y))
		for q in out:
			pts.append(house.global_transform * Vector3(q.x, 0, q.y))
		routes.append(pts)
		bags.append(bag)
	for k in range(g.golfers.size()):
		var w: Walker = g.golfers[k]
		w.ground = false
		w.data.erase("outdoor_target")
		w.data.erase("indoor_target")
		w.data["blocked"] = false
		w.data["hold"] = k * 0.6 + _rng.randf_range(0.0, 0.3)  # (one after another out of the door)
		w.path = routes[k]
		w.data["walk_region"] = {"nav": _guest_nav(house), "xf": house.global_transform}
		if bags[k] != Vector2.INF:
			w.data["valet_at"] = bags[k]
	return true


## Those of flight `g` the valet has a bag waiting for, there now: shouldered.
func _valet_hand_back(g: Group) -> void:
	for w: Walker in g.golfers:
		if not w.data.has("valet_at") or not w.path.is_empty():
			continue
		var at: Vector2 = w.data["valet_at"]
		if Vector2(w.node.global_position.x, w.node.global_position.z).distance_to(at) < 1.6:
			_bag_up(w)
			w.data.erase("valet")
			w.data.erase("valet_at")


## A bag the valet still has of `w`'s straight back on their shoulder (the way out went elsewhere).
func _valet_give(w: Walker) -> void:
	if w.data.get("valet", false):
		_bag_up(w)
		w.data.erase("valet")
		w.data.erase("valet_at")


## With the line behind the clubhouse out of carts: the flight's from the barn's row instead --
## ones brought back there, else ones out of the barn.
func _stage_carts(g: Group) -> void:
	for _i in range(ceili(g.golfers.size() / 2.0) - g.carts.size()):
		var c: Walker = _stock.pop_front() if not _stock.is_empty() else _new_barn_cart()
		if c == null:
			return
		_pool.erase(c)
		_invalidate_traffic()
		c.speed = RIDE
		c.ground = true
		g.carts.append(c)
		_invalidate_traffic()


## A cart out of the barn into a free spot in its row (or just outside the barn): one of the barn's
## own parked carts, its space left empty (user: not one made up) -- for a barn with them; null
## without one, or with them all out already.
func _new_barn_cart() -> Walker:
	if _fac("cart_barn") == null:
		return null
	var slots := _barn_slots()
	var k := -1
	for j in range(slots.size()):
		if not _barn_out.has(j) and _barn_slot_clear(j):
			k = j
			break
	if not slots.is_empty() and k < 0:
		return null  # (every one of the barn's carts out)
	var c := _cart()
	if c == null:
		return null
	if k >= 0:
		c.data["barn_slot"] = k
		_barn_out[k] = c
		_barn_slot_shown(k, false)
	var spot := _barn_spot(c)
	if spot != Vector2.INF:
		_settle_in_row(c, spot)
	else:
		var front := _facility_front("cart_barn")
		var p := _cart_parking_point(front, c) if front != Vector2.INF else Vector2.INF
		if p == Vector2.INF:
			c.node.queue_free()
			return null
		c.node.global_position = Vector3(p.x, _ground_y(p), p.y)
	c.ground = true
	_pool.append(c)
	_invalidate_traffic()
	return c


## Cart `c` stood in the barn's row at `spot` (world XZ): nose in toward the barn, set to back out.
func _settle_in_row(c: Walker, spot: Vector2) -> void:
	var barn := _fac("cart_barn")
	var into := barn.global_transform.basis.z.normalized()
	c.path.clear()
	c.node.global_position = Vector3(spot.x, _ground_y(spot), spot.y)
	c.node.rotation = Vector3(0, barn.global_rotation.y + PI, 0)
	c.data["lead_out"] = [Vector3(spot.x, 0, spot.y) - into * 3.0]
	c.data["lead_reverse"] = 1
	c.data["parking_target"] = spot
	c.node.visible = true


## Back to the barn's row: up to the front of spot `spot` (world XZ), then in, nose first.
func _park_in_row(c: Walker, spot: Vector2) -> void:
	var into := _fac("cart_barn").global_transform.basis.z.normalized()
	var front := Vector3(spot.x, 0, spot.y) - into * 3.0
	c.data["parking_target"] = spot
	_go(c, Vector2(front.x, front.z))
	c.path.append(Vector3(spot.x, 0, spot.y))


## The barn's row spot at (or within a metre of) `p` (world XZ); INF if it isn't one.
func _row_spot_at(p: Vector2) -> Vector2:
	var barn := _fac("cart_barn")
	if barn == null:
		return Vector2.INF
	for xf: Transform3D in _wash_bays(barn):
		var w := barn.global_transform * xf.origin
		if p.distance_to(Vector2(w.x, w.z)) < 1.0:
			return Vector2(w.x, w.z)
	return Vector2.INF


## The club's carts from scratch: the line behind the clubhouse full, none back at the barn.
func _reset_carts() -> void:
	for c: Walker in _pool:
		if is_instance_valid(c.node):
			c.node.queue_free()
	_pool.clear()
	_invalidate_traffic()
	_stock.clear()
	_line.clear()
	_restocking = false
	for k: int in _barn_out:
		_barn_slot_shown(k, true)  # (every one of the barn's carts back in its space)
	_barn_out.clear()
	_barn_returns.clear()
	var slots := _line_slots()
	if slots.is_empty() or _fac("cart_barn") == null:
		return
	_line.resize(slots.size())
	for i in range(slots.size()):
		var c := _cart()
		if c == null:
			break
		c.ground = true
		_put_in_slot(c, i)
		_pool.append(c)
		_invalidate_traffic()


## The line's slots behind the clubhouse (world), head first; empty without one.
func _line_slots() -> Array:
	var house := _fac("clubhouse")
	var out: Array = []
	if house == null:
		return out
	for xf: Transform3D in FacilityBuilder.rig(house).get("cart_line", []):
		var w := house.global_transform * xf
		out.append(Transform3D(w.basis.orthonormalized(), w.origin))
	return out


## Where the line turns from one row into the other (world); INF without one.
func _line_turn() -> Vector3:
	var house := _fac("clubhouse")
	var rig := FacilityBuilder.rig(house) if house != null else {}
	return house.global_transform * (rig["cart_turn"] as Vector3) if rig.has("cart_turn") else Vector3.INF


## Cart `c` stood in slot `i` of the line, facing the way the line moves.
func _put_in_slot(c: Walker, i: int) -> void:
	var xf: Transform3D = _line_slots()[i]
	c.path.clear()
	c.node.global_transform = Transform3D(xf.basis, Vector3(xf.origin.x, _ground_y(Vector2(xf.origin.x, xf.origin.z)), xf.origin.z))
	c.node.visible = true
	c.data.erase("parking_target")
	c.data["reverse"] = 0
	_line[i] = c


## Along the line toward its head from slot `from` to slot `to` (from > to): the slots between
## and `to`, round the turn where it changes rows (world points).
func _line_way(from: int, to: int) -> Array:
	var slots := _line_slots()
	var turn := _line_turn()
	var out: Array = []
	for i in range(from - 1, to - 1, -1):
		var a: Vector3 = (slots[i + 1] as Transform3D).origin
		var b: Vector3 = (slots[i] as Transform3D).origin
		if a.distance_to(b) > 3.6 and turn != Vector3.INF:
			var d := turn - (a + b) * 0.5
			out.append_array([a + d * 0.85, turn + d * 0.15, b + d * 0.85])
		out.append(b)
	return out


## Out of the line from slot `i`: up it to the head and straight on off its end onto the course.
func _line_exit(i: int) -> Array:
	var head: Transform3D = _line_slots()[0]
	var out := _line_way(i, 0) if i > 0 else []
	out.append(head.origin - head.basis.z * 6.0)
	return out


## Into the line to slot `j`: in behind its tail from the course side and up it to `j`.
func _line_entry(j: int) -> Array:
	var slots := _line_slots()
	var tail: Transform3D = slots[slots.size() - 1]
	var out: Array = [tail.origin + tail.basis.z * 6.0, tail.origin]
	if j < slots.size() - 1:
		out.append_array(_line_way(slots.size() - 1, j))
	return out


## The flight's carts off the front of the line behind the clubhouse: the frontmost, as long as
## the cart boy isn't moving one up ahead of them. False if there aren't enough.
func _take_line(g: Group) -> bool:
	var need := ceili(g.golfers.size() / 2.0)
	var picked: Array = []
	for i in range(_line.size()):
		var c: Variant = _line[i]
		if c == null:
			continue
		if (c as Walker).data.has("job") or (c as Walker).data.has("washing"):
			break
		picked.append(i)
		if picked.size() == need:
			break
	if picked.size() < need:
		return false
	for i: int in picked:
		var c: Walker = _line[i]
		_line[i] = null
		_pool.erase(c)
		_invalidate_traffic()
		c.data["lead_out"] = _line_exit(i)
		c.data["lead_reverse"] = 0
		c.speed = RIDE
		c.ground = true
		g.carts.append(c)
		_invalidate_traffic()
	return true


## The cart boy keeps the line behind the clubhouse in carts: when it's run low he pulls what's
## left of it up to the front, then drives carts over from the barn to the back of it, one at a
## time, till it's full. True while he's at it (this turn of his is taken).
func _cart_boy(p: Walker) -> bool:
	# Driving and boarding finish safely; cleaning can yield to customer demand.
	var steps: Array = p.data.get("steps", [])
	if steps.is_empty():
		_assign_cart_department_job(p)
		steps = p.data.get("steps", [])
		if steps.is_empty(): return false
	var s: Dictionary = steps[0]
	var c: Walker = s.get("cart")
	match str(s["do"]):
		"walk":
			if not s.has("to"):
				s["to"] = _bag_run_goal(s)  # (somewhere about a cart that's moved since it was set)
			var to: Vector2 = s["to"]
			var here := Vector2(p.node.global_position.x, p.node.global_position.z)
			var hose_walk := bool(s.get("hose", false))
			var close := float(s.get("arrival_distance", 0.18 if hose_walk else 1.2))
			if here.distance_to(to) < close:
				steps.pop_front()
				p.data.erase("shortest_walk")
				return true
			s["tries"] = int(s.get("tries", 0)) + 1
			p.ground = true
			p.rest = "idle"
			p.data["shortest_walk"] = hose_walk
			_go(p, to)
			if p.path.is_empty():
				p.wait = 1.0
		"board":
			if not s.has("turned"):
				s["turned"] = true
				p.data["watch"] = Vector2(c.node.global_position.x, c.node.global_position.z)  # to the cart first
				p.wait = 0.6
				return true
			if not s.has("climbing"):
				s["climbing"] = true
				p.data.erase("watch")
				_climb_in(p, c, 0)  # (by the golfers' clip: user)
				p.wait = 0.2
				return true
			if p.data.has("cart_move"):
				p.wait = 0.2
				return true
			steps.pop_front()
			if not p.riding:
				_seat(p, c, 0)
			p.wait = 0.4
		"drive":
			# Hold at the ready line until the previous bag-loading cart has
			# completed its departure. Never queue opposing carts on this narrow path.
			if str(s["kind"]) == "curb" and not _claim_front_cart_route(c):
				p.wait = 0.5
				return true
			var errand := str(s["kind"]) in ["curb", "away", "over", "yard"]
			if not s.has("set"):
				s["set"] = true
				c.data["reverse"] = 0
				c.data.erase("round_tries")  # (a fresh drive: its own tries at getting round any parked one)
				c.data["yard_maneuver"] = str(s["kind"]) == "yard"
				if str(s["kind"]) == "yard":  # (round the barn's yard: its way given, backing off first if it says)
					c.path = (s["path"] as Array).duplicate()
					c.data["reverse"] = int(s.get("reverse", 0))
				else:
					c.path = _bag_run_way(c, str(s["kind"]), int(s.get("index", 0))) if errand else _job_way(c, s)
				c.data.erase("outdoor_target")
				c.speed = RIDE * (1.0 if errand else 0.6)
				c.ground = true
				c.data["blocked"] = false
				p.wait = 0.3
			elif c.path.is_empty():
				if str(s["kind"]) == "yard" and not (s.get("path", []) as Array).is_empty():
					var goal: Vector3 = (s["path"] as Array).back()
					if Vector2(c.node.global_position.x - goal.x, c.node.global_position.z - goal.z).length() > 0.25:
						c.path = [goal]
						c.data["reverse"] = 1 if int(s.get("reverse", 0)) > 0 else 0
						p.wait = 0.3
						return true  # A cleared/blocked route is not a completed parking maneuver.
				steps.pop_front()
				if not errand:
					_put_in_slot(c, int(s["slot"]))
					# Keep the reservation until its driver has fully climbed out.
			else:
				p.wait = 0.3
		"alight":
			if p.riding and not s.has("climbing"):
				s["climbing"] = true
				_climb_out(p, c, 0)  # (by the golfers' clip: user)
				p.wait = 0.2
				return true
			if p.data.has("cart_move"):
				p.wait = 0.2
				return true
			steps.pop_front()
			if p.riding:
				_unseat(p, c, 0)
			if steps.is_empty() and c != null:
				c.data.erase("job")
			p.rest = "idle"
		"grab", "stow":
			# a beat turned to it (the bag, or the cart), then the bag up off its stand (or the
			# cart's passenger side) and slung, one over each shoulder; or off his shoulder into
			# the bag well behind its owner's seat (or onto the passenger side, to ride round)
			var w: Walker = s["golfer"]
			var key := "bag" if int(s.get("hand", 0)) == 0 else "bag2"
			var stand: Variant = w.data.get("bag_down")
			var cargo := str(s.get("from", "")) == "cargo"
			if not s.has("turned"):
				s["turned"] = true
				var at: Vector3 = (stand as Node3D).global_position if s["do"] == "grab" and not cargo and stand != null and is_instance_valid(stand) else c.node.global_position
				p.data["watch"] = Vector2(at.x, at.z)
				p.wait = 0.5
				return true
			steps.pop_front()
			p.data.erase("watch")
			if s["do"] == "grab":
				var held := _cargo_off(c, w) if cargo else stand != null and is_instance_valid(stand)
				if held and not cargo:
					(stand as Node).queue_free()
					w.data.erase("bag_down")
				if held:
					_carry_bag(p, str(w.data.get("bag_livery", "")), key)
			elif p.data.has(key):
				_drop_bag(p, key)
				if int(s["seat"]) < 0:
					_cargo_on(c, w)
				else:
					_bag_aboard(w, c, int(s["seat"]))
			p.wait = 0.25
		"settle":
			# brought out to the barn's row: squared up in its spot, there for washing (and renting)
			steps.pop_front()
			_settle_in_row(c, s["spot"] as Vector2)
			c.data.erase("job")
			c.data.erase("washed_at")  # (straight off its charger: due a wash)
			if not _pool.has(c):
				_pool.append(c)
				_invalidate_traffic()
			if not c.data.has("washing") and not _stock.has(c):
				_stock.append(c)
			p.wait = 0.5
		"begin_wash":
			steps.pop_front()
			steps.assign(_clean_cart_steps(p, c) + steps)
		"repark":
			var back := _barn_cart_in(c)
			if back.is_empty():
				if _barn_transfer_busy(c) or not _barn_returns.is_empty():
					p.wait = 0.5
					return true  # Finish this wash-and-return job after the row is clear.
				steps.pop_front()
				_release_wash(p)  # Full/unreachable barn: leave the clean cart in the outside row.
			else:
				steps.pop_front()
				steps.assign(back + steps)
			p.wait = 0.3
		"put_away":
			# back in its space in the barn: one of its parked carts again (user)
			steps.pop_front()
			var k := int(s["slot"])
			_stock.erase(c)
			_pool.erase(c)
			_invalidate_traffic()
			_release_wash(p)
			_stock.erase(c)
			c.node.queue_free()
			_barn_out.erase(k)
			_barn_returns.erase(k)
			_bay_washed[k] = _clock
			p.data["completed_washes"] = int(p.data.get("completed_washes", 0)) + 1
			_barn_slot_shown(k, true)
			p.wait = 1.2
		"take_hose":
			# at the reel on the barn's wall: turned to it, the hose's end and nozzle off its hook, then
			# off with it trailing to the cart (user: not one spawned in his hand)
			if not s.has("turned"):
				s["turned"] = true
				var stand: Vector2 = s.get("stand", _hose_stand())
				if stand != Vector2.INF:  # (square in front of the reel: the walk stops a step short, user)
					p.path.clear()
					var r: Vector2 = s["reel"]
					_face(p, atan2(-(r.x - stand.x), -(r.y - stand.y)))
				p.data["watch"] = s["reel"]
				p.rest = "work"
				_play(p, "work")
				p.wait = 0.8
				return true
			steps.pop_front()
			p.data.erase("watch")
			_hose_on(p, c)
			p.rest = "idle"
			p.wait = 0.3
		"hang_hose":
			# back at the reel: the hose wound back on and its nozzle hung up
			if not s.has("turned"):
				s["turned"] = true
				var stand: Vector2 = s.get("stand", _hose_stand())
				if stand != Vector2.INF:  # (square in front of the reel: the walk stops a step short, user)
					p.path.clear()
					var r: Vector2 = s["reel"]
					_face(p, atan2(-(r.x - stand.x), -(r.y - stand.y)))
				p.data["watch"] = s["reel"]
				p.rest = "work"
				_play(p, "work")
				p.wait = 0.8
				return true
			steps.pop_front()
			p.data.erase("watch")
			_hose_off(p)
			p.rest = "idle"
			_play(p, "idle")
			p.wait = 0.3
		"wash":
			var t := float(s.get("t", -1.0))
			if t < 0.0:
				p.data["watch"] = Vector2(c.node.global_position.x, c.node.global_position.z)
				var toward := c.node.global_position - p.node.global_position
				_face(p, atan2(-toward.x, -toward.z))
				if not p.data.has("hose"):
					_hose_on(p, c)  # (a barn with no reel on its wall: his own)
				p.rest = "hose"
				_play(p, p.rest)
				t = 0.0
			t += 0.5
			s["t"] = t
			if t >= WASH_HOSE:
				if not s.get("keep", false):
					_hose_off(p)
				p.rest = "idle"
				_play(p, "idle")
				p.data.erase("watch")
				steps.pop_front()
			p.wait = 0.5
		"wash_step":
			# Short, close approaches around the outside of the cart, never across its body.
			var at: Vector3 = c.node.global_transform * (s["local"] as Vector3)
			if p.node.global_position.distance_to(at) > 0.08:
				_go(p, Vector2(at.x, at.z))
				p.ground = true
				p.rest = "idle"
			steps.pop_front()
		"dry":
			var hood := bool(s.get("hood", false))
			if not s.has("t"):
				var target: Vector3 = c.node.global_transform * (Vector3(0, 0.92, -1.0) if hood else Vector3(0.68 * float(s.get("sx", -1.0)), 1.0, 0.0))
				var toward := target - p.node.global_position
				_face(p, atan2(-toward.x, -toward.z))
				p.data["watch"] = Vector2(target.x, target.z)
				p.rest = "wipe_hood" if hood else "wipe"
				_play(p, p.rest)
				_rag_on(p, hood)
				s["t"] = 0.0
			s["t"] = float(s["t"]) + 0.5
			if float(s["t"]) >= WASH_WIPE:
				_rag_off(p)
				p.data.erase("watch")
				steps.pop_front()
				p.rest = "idle"
				_play(p, "idle")
				if hood:
					c.data["washed_at"] = _clock
					if not s.get("stow", false):
						_release_wash(p)  # (left where it stands: in the line; one at the barn's driven in first)
			p.wait = 0.5
		"hand_over":
			# their cart out at the end of the walk for its pair (any bag of theirs he hadn't got to
			# aboard too)
			steps.pop_front()
			var g: Group = s["group"]
			var i := int(s.get("index", 0))
			if i < g.carts.size():
				var own: Walker = g.carts[i]
				for k in [i * 2, i * 2 + 1]:
					if k < g.golfers.size() and (g.golfers[k] as Walker).data.get("valet", false):
						_bag_aboard(g.golfers[k], own, k % 2)
				own.data.erase("job")
				own.data.erase("front_cart_route")
				own.data["delivered"] = true
			p.speed = WALK
			p.wait = 0.5
	return true


## The cart boy's next job, as steps: a flight's cart brought round with their bags on (a bag
## run) if one's waiting; else pull the line up if there's a gap at its front, else fetch a cart
## from the barn to the back of it -- while it's restocking (from running low till it's full).
## Cleaning comes last. Attendants return to the barn between front-of-house jobs.
## Department priorities are claimed centrally; each employee owns an independent
## step queue. Reservations are made during each claim, before the next assignment.
func _dispatch_cart_department() -> void:
	var employees := _cart_boys()
	# The employee waiting at cart parking takes the next delivery first.
	employees.sort_custom(func(a: Walker, b: Walker) -> bool: return a.data.get("cart_standby", false) and not b.data.get("cart_standby", false))
	for employee: Walker in employees:
		var steps: Array = employee.data.get("steps", [])
		if not steps.is_empty() or employee.riding or employee.data.has("cart_move"): continue
		_assign_cart_department_job(employee)


func _assign_cart_department_job(employee: Walker) -> void:
	# Never replace an employee's unfinished assignment during department dispatch.
	if not (employee.data.get("steps", []) as Array).is_empty(): return
	employee.data.erase("cart_assignment")
	var steps := _cart_job(employee)
	if steps.is_empty(): return
	var kind := "washing"
	if not steps[0].get("cart_standby", false): employee.data.erase("cart_standby")
	if steps[0].get("cart_standby", false):
		kind = "standby"
	elif steps[0].get("return_to_barn", false):
		kind = "return_to_barn"
	else:
		for step: Dictionary in steps:
			if step.get("do") == "hand_over":
				kind = "delivery"
				break
			if step.get("do") == "drive" and step.get("kind") in ["up", "fetch"]:
				kind = "rearrange" if step["kind"] == "up" else "refill"
				break
	employee.data["steps"] = steps
	employee.data["cart_assignment"] = {"department": "cart", "kind": kind, "assigned_at": _clock}
	employee.wait = 0.0
	# An idle employee may still have an old route to a waiting position.
	employee.path.clear()
	employee.data.erase("pedestrian_yield")
	employee.data.erase("outdoor_target")
	employee.data["blocked"] = false


## Department totals and individual assignments share the same employee queues.
## Each complete assignment counts once, rather than once per walk/board/drive step.
func cart_department_workload() -> Dictionary:
	var employees: Array = []
	var active := {"delivery": 0, "rearrange": 0, "refill": 0, "washing": 0}
	for employee: Walker in _cart_boys():
		var steps: Array = employee.data.get("steps", [])
		var assignment: Dictionary = employee.data.get("cart_assignment", {})
		var kind := str(assignment.get("kind", "idle")) if not steps.is_empty() else "idle"
		if active.has(kind): active[kind] += 1
		employees.append({"employee": employee, "job": kind, "remaining_steps": steps.size()})
	return {"active": active, "pending_deliveries": _bag_runs.size(), "employees": employees}


func _cart_job(p: Walker) -> Array:
	# Bags/delivery, then compaction, then barn replenishment, then cleaning.
	if _runs_bags(p):
		var run := _bag_run_steps(p)
		if not run.is_empty():
			return run  # Any available attendant takes bag loading and delivery first.
	var slots := _line_slots()
	if slots.is_empty() or _line.size() != slots.size():
		var cleaning := _wash_steps(p)
		return cleaning if not cleaning.is_empty() else _waiting_steps(p)
	var have := 0
	for c: Variant in _line:
		if c != null:
			have += 1
			if (c as Walker).data.has("job"):
				# The line is reserved; free attendants return to the barn between jobs.
				var cleaning := _wash_steps(p)
				return cleaning if not cleaning.is_empty() else _waiting_steps(p)
	if have <= maxi(1, slots.size() / 2):
		_restocking = true
	if have >= slots.size():
		_restocking = false
	if not _restocking:
		var wash := _wash_steps(p)  # Cleaning is last, for every attendant.
		return wash if not wash.is_empty() else _post_steps(p)
	var gap := _line.find(null)
	var behind := -1
	for i in range(gap + 1, _line.size()):
		if _line[i] != null:
			behind = i
			break
	var c: Walker
	var kind := "up"
	if behind > gap:
		if (_line[behind] as Walker).data.has("washing"):
			return _wash_steps(p)  # Let its current cleaning finish before moving it.
		c = _line[behind]  # pull the line up: the cart behind the gap moves up into it
		_line[behind] = null
	else:
		c = _stock.pop_front() if not _stock.is_empty() else _new_barn_cart()  # over from the barn
		kind = "fetch"
		if c == null:
			_restocking = false
			return _waiting_steps(p)
	_line[gap] = c
	c.data["job"] = true
	var door := _cart_door(c, 0)
	return [{"do": "walk", "to": Vector2(door.x, door.z)}, {"do": "board", "cart": c},
		{"do": "drive", "cart": c, "kind": kind, "from": behind, "slot": gap}, {"do": "alight", "cart": c}]


## The way for the cart boy's job `s` with cart `c`: up the line (kind "up"), or from the barn --
## backed out of its row -- across to the line's tail and up it to its slot.
func _job_way(c: Walker, s: Dictionary) -> Array:
	if str(s["kind"]) == "up":
		return _line_way(int(s["from"]), int(s["slot"]))
	var entry := _line_entry(int(s["slot"]))
	var lead: Array = c.data.get("lead_out", [])
	c.data["reverse"] = int(c.data.get("lead_reverse", 0)) if not lead.is_empty() else 0
	c.data.erase("lead_out")
	c.data.erase("lead_reverse")
	var at: Vector3 = lead[lead.size() - 1] if not lead.is_empty() else c.node.global_position
	var a := Vector2(at.x, at.z)
	var b := Vector2((entry[0] as Vector3).x, (entry[0] as Vector3).z)
	var mid := _route(a, b, true)
	if mid.is_empty():
		mid = _via_yards(a, b, true)
	return lead + mid + entry.slice(1)


## The club's cart boys, in the order they were hired.
func _cart_boys() -> Array:
	return _staff.filter(func(s: Walker) -> bool: return str(s.data.get("role", "")) == "cart_attendant")


## All attendants share delivery, rearranging, replenishment, and cleaning duties.
## Keep this duty name for the existing washing and waiting-position helpers.
func _cart_duty(_p: Walker) -> String:
	return "all"


## Any idle cart attendant can take the next bag-and-cart delivery.
func _runs_bags(_p: Walker) -> bool:
	return true


## One otherwise-free attendant covers cart parking; the rest wait inside the barn.
func _post_steps(p: Walker) -> Array:
	return _waiting_steps(p)


func _waiting_steps(p: Walker) -> Array:
	var slots := _line_slots()
	if slots.is_empty(): return _home_steps(p)
	for other: Walker in _cart_boys():
		if other == p or not other.data.get("cart_standby", false): continue
		var work: Array = other.data.get("steps", [])
		if not other.riding and not other.data.has("cart_move") and (work.is_empty() or work[0].get("cart_standby", false)):
			p.data.erase("cart_standby")
			return _home_steps(p)
	var head: Transform3D = slots[0]
	# Wait beside the first cart, outside the parking and driving lanes.
	for side: float in [-1.0, 1.0]:
		var at := head * Vector3(side * 3.2, 0, 0)
		var clear := true
		for slot: Transform3D in slots:
			var local := slot.affine_inverse() * at
			if absf(local.x) < CART_HALF.x + 0.8 and absf(local.z) < CART_HALF.y + 0.8:
				clear = false
		if not clear: continue
		var spot := Vector2(at.x, at.z)
		if not _grounds_nav.is_empty() and _grounds_path(Vector2(p.node.global_position.x, p.node.global_position.z), spot).is_empty() and p.node.global_position.distance_to(at) > 0.4: continue
		p.data["cart_standby"] = true
		if Vector2(p.node.global_position.x, p.node.global_position.z).distance_to(spot) < 0.3: return []
		return [{"do": "walk", "to": spot, "arrival_distance": 0.25, "cart_standby": true, "return_to_barn": true}]
	p.data.erase("cart_standby")
	return _home_steps(p)


## Idle attendants wait at the barn's indoor staff markers, beside the cart lanes.
func _home_steps(p: Walker) -> Array:
	var barn := _fac("cart_barn")
	if barn == null: return []
	var rig := FacilityBuilder.rig(barn)
	var level := clampi(int(rig.get("level", 1)), 1, 4)
	var front: float = [4.0, 5.5, 6.0, 9.0][level - 1]
	var indoor: Array = []
	for marker: Dictionary in rig.get("spots", {}).get("", []):
		var local: Vector3 = (marker["xf"] as Transform3D).origin
		if local.z > front + 0.5: indoor.append(local)
	if indoor.is_empty(): return []
	var index := maxi(_cart_boys().find(p), 0)
	var local: Vector3 = indoor[index % indoor.size()]
	local.z += floori(float(index) / indoor.size()) * (-0.8 if level == 1 else 1.2)
	var home := barn.global_transform * local
	var spot := Vector2(home.x, home.z)
	if Vector2(p.node.global_position.x, p.node.global_position.z).distance_to(spot) < 0.3:
		return []
	p.data.erase("watch")
	return [{"do": "walk", "to": spot, "arrival_distance": 0.25, "return_to_barn": true}]


## Cleaning and return-to-barn walks yield to customer jobs or low ready stock.
## Finish boarding and barn maneuvers before releasing the cart safely.
func _wake_returning_attendants() -> void:
	var have := _line.filter(func(c: Variant) -> bool: return c != null).size()
	var refill := not _line.is_empty() and (have <= maxi(1, _line.size() / 2) or _restocking) and _line.has(null) and not _line.any(func(c: Variant) -> bool: return c != null and (c as Walker).data.has("job"))
	var demand := not _bag_runs.is_empty() or refill
	var cleaning_available := not _barn_transfer_busy() and _fac("cart_barn") != null
	if not demand and not cleaning_available: return
	# Wake only enough cleaners to cover demand; the others keep washing.
	var needed := _bag_runs.size() + (1 if refill else 0)
	for worker: Walker in _cart_boys():
		var work: Array = worker.data.get("steps", [])
		if not worker.riding and not worker.data.has("cart_move") and (work.is_empty() or work[0].get("return_to_barn", false)):
			needed = maxi(0, needed - 1)
	for p: Walker in _cart_boys():
		var steps: Array = p.data.get("steps", [])
		if steps.is_empty() or p.riding or p.data.has("cart_move"): continue
		var c: Walker = p.data.get("wash_cart")
		var cleaning := c != null and not c.data.has("job") and not c.data.has("barn_return_slot")
		if not steps[0].get("return_to_barn", false) and not (needed > 0 and cleaning): continue
		if cleaning:
			needed = maxi(0, needed - 1)
			c.data["wash_handoff"] = true
		# Leave the cart safely in its wash bay, ready for another attendant or refill.
		_hose_off(p)
		_release_wash(p)
		steps.clear()
		p.path.clear()
		p.data.erase("pedestrian_yield")
		p.data.erase("watch")
		p.data["blocked"] = false
		p.wait = 0.0


# ---------------------------------------------------------------- washing the carts

## The cart boy `p`'s wash of a cart in the barn's row, as steps: round to its driver's side,
## stood back off it, and the wash ("wash"). Empty with none due one.
func _release_wash(p: Walker) -> void:
	_rag_off(p)
	_hose_off(p)
	p.data.erase("wash_station")
	var c: Walker = p.data.get("wash_cart")
	p.data.erase("wash_cart")
	if c != null and is_instance_valid(c.node):
		c.data.erase("washing")
		if c.data.has("line_wipe"):
			c.data.erase("line_wipe")  # (wiped where it stands in the line: still in it)
		elif _pool.has(c) and not _stock.has(c): _stock.append(c)


func _wash_steps(p: Walker) -> Array:
	var due: Array = _stock.filter(func(c: Walker) -> bool:
		return c.node.visible and c.path.is_empty() and not c.data.has("job") and not c.data.has("washing"))
	if due.is_empty():
		var out := _barn_cart_out(p)
		if out.is_empty() and _fac("cart_barn") == null: out = _wipe_steps(p)
		return out
	due.sort_custom(func(a: Walker, b: Walker) -> bool:
		if a.data.has("wash_handoff") != b.data.has("wash_handoff"): return a.data.has("wash_handoff")
		return float(a.data.get("washed_at", -INF)) < float(b.data.get("washed_at", -INF)))
	return _clean_cart_steps(p, due[0])


func _clean_cart_steps(p: Walker, c: Walker) -> Array:
	var station := _wash_station(p, c)
	if station.is_empty(): return []
	_stock.erase(c)
	c.data.erase("wash_handoff")
	c.data["washing"] = true
	p.data["wash_cart"] = c

	# hosed from the side of it nearest the reel (user: not walking round it to the far one), and
	# dried down that side before the hood
	var reel: Vector2 = station.get("stand", Vector2.INF)
	var from := Vector3(reel.x, 0.0, reel.y) if reel != Vector2.INF else p.node.global_position
	var l := c.node.global_transform.affine_inverse() * from
	var sx := 1.0 if l.x > 0.0 else -1.0
	var spots := [Vector3(sx * (CART_HALF.x + 1.0), 0, 0), Vector3(0, 0, -(CART_HALF.y + 1.0)), Vector3(0, 0, CART_HALF.y + 1.0)]
	var stand: Vector3 = spots[0]
	for q: Vector3 in spots:
		if q.distance_to(Vector3(l.x, 0, l.z)) < stand.distance_to(Vector3(l.x, 0, l.z)):
			stand = q
	var at := c.node.global_transform * stand
	var hose: Array = [{"do": "walk", "to": Vector2(at.x, at.z)}, {"do": "wash", "cart": c}]
	if reel != Vector2.INF:
		# over to the reel for the hose first, the hose out to the cart, and back to hang it up
		var r: Vector3 = station["outlet"]
		hose = [{"do": "walk", "to": reel, "hose": true}, {"do": "take_hose", "cart": c, "reel": Vector2(r.x, r.z), "stand": reel},
			{"do": "walk", "to": Vector2(at.x, at.z), "hose": true}, {"do": "wash", "cart": c, "keep": true},
			{"do": "walk", "to": reel, "hose": true}, {"do": "hang_hose", "cart": c, "reel": Vector2(r.x, r.z), "stand": reel}]
	# Choose the parking destination after cleaning, when other returns have finished.
	var store := not _barn_slots().is_empty() and not _barn_out.is_empty()
	return hose + [
		{"do": "wash_step", "cart": c, "local": Vector3(sx * 1.16, 0, 0)},
		{"do": "dry", "cart": c, "sx": sx},
		{"do": "wash_step", "cart": c, "local": Vector3(sx * 1.16, 0, -1.73)},
		{"do": "wash_step", "cart": c, "local": Vector3(0, 0, -1.73)},
		{"do": "dry", "cart": c, "hood": true, "stow": store}] + ([{"do": "repark", "cart": c}] if store else [])


## The barn's parked carts (its rig's "barn_carts": facility-local transforms, nose out) in the
## world, by index; empty without a barn.
func _barn_slots() -> Array:
	var barn := _fac("cart_barn")
	if barn == null:
		return []
	var out: Array = []
	for e: Dictionary in FacilityBuilder.rig(barn).get("barn_carts", []):
		var w := barn.global_transform * (e["xf"] as Transform3D)
		out.append(Transform3D(w.basis.orthonormalized(), w.origin))
	return out


## Show or hide the barn's own parked cart `k` (out of its space: driven about by a Walker).
func _barn_slot_shown(k: int, shown: bool) -> void:
	_invalidate_traffic()
	var barn := _fac("cart_barn")
	var mmi := barn.get_node_or_null("Batch_cart") as MultiMeshInstance3D if barn != null else null
	var carts: Array = FacilityBuilder.rig(barn).get("barn_carts", []) if barn != null else []
	if mmi == null or k >= carts.size():
		return
	var xf: Transform3D = carts[k]["xf"]
	mmi.multimesh.set_instance_transform(int(carts[k]["i"]), xf if shown else Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin))


## Whether parked cart `k`'s space has a clear way to the barn's door: none of the barn's carts in
## their spaces between (a lane of them, one behind another: only the one nearest the door's
## driven out, or backed in to a space nearest it).
func _barn_slot_clear(k: int) -> bool:
	var slots := _barn_slots()
	var barn := _fac("cart_barn")
	var into := barn.global_transform.basis.z.normalized()
	var across := barn.global_transform.basis.x.normalized()
	var at: Vector3 = (slots[k] as Transform3D).origin
	for returning: int in _barn_returns:
		if absf(((slots[returning] as Transform3D).origin - at).dot(across)) < 1.0:
			return false  # Only one cart at a time enters or leaves this row.
	for j in range(slots.size()):
		if j == k or _barn_out.has(j):
			continue
		var d: Vector3 = (slots[j] as Transform3D).origin - at
		if absf(d.dot(across)) < 1.0 and d.dot(into) < -0.5:
			return false  # (one stands in front of it, toward the door)
		var driver := (slots[k] as Transform3D) * Vector3(-CART_DOOR, 0, 0)
		var local := (slots[j] as Transform3D).affine_inverse() * driver
		if absf(local.x) < CART_HALF.x + 0.15 and absf(local.z) < CART_HALF.y + 0.15:
			return false  # Reach the driver's side without crossing the neighbouring cart.
	return true


## Where in front of parked cart `k`'s space a cart's driven out to (or backed in from): just out
## of the barn's door, in line with it (world).
func _barn_door(k: int) -> Vector3:
	var slots := _barn_slots()
	var at: Transform3D = slots[k]
	var barn := _fac("cart_barn")
	var into := barn.global_transform.basis.z.normalized()
	var front := at.origin
	for xf: Transform3D in FacilityBuilder.rig(barn).get("barn_bays", []):
		var d := barn.global_transform * xf.origin
		if absf((d - at.origin).dot(barn.global_transform.basis.x.normalized())) < 1.4:
			front = at.origin + into * (d - at.origin).dot(into)  # (the bay's door: its BARN_BAY just inside it)
	return front - into * 1.6


## Cart `c` (washed, in the barn's row) back in its space in the barn (user: one of the barn's own,
## put back): out of its row spot, round onto the apron facing out, and backed in -- put away
## (put_away). Fill the deepest reachable vacant space first, preferably in its original row.
func _barn_cart_in(c: Walker) -> Array:
	if _barn_transfer_busy(c): return []
	var slots := _barn_slots()
	if slots.is_empty():
		return []
	var barn := _fac("cart_barn")
	var into := barn.global_transform.basis.z.normalized()
	var across := barn.global_transform.basis.x.normalized()
	var mine := int(c.data.get("barn_slot", -1))
	var preferred := (slots[mine] as Transform3D).origin if mine >= 0 and mine < slots.size() else c.node.global_position
	var k := -1
	var row_distance := INF
	var depth := -INF
	for j: int in _barn_out:
		if _barn_returns.has(j) or not _barn_slot_clear(j): continue
		var at: Vector3 = (slots[j] as Transform3D).origin
		var distance := absf((at - preferred).dot(across))
		var back := at.dot(into)
		if distance < row_distance - 0.1 or absf(distance - row_distance) <= 0.1 and back > depth:
			k = j
			row_distance = distance
			depth = back
	if k < 0:
		return []
	if mine >= 0 and mine != k and _barn_out.get(mine) == c:
		_barn_out[mine] = null  # Still vacant; changing bays must not create a phantom parked cart.
	_barn_out[k] = c
	_barn_returns[k] = c
	c.data["barn_slot"] = k
	c.data["barn_return_slot"] = k
	c.data["job"] = true
	var door := _barn_door(k)
	var at := c.node.global_position
	var at_space: Vector3 = (slots[k] as Transform3D).origin
	return [{"do": "walk", "cart": c, "at": "door"}, {"do": "board", "cart": c},
		{"do": "drive", "cart": c, "kind": "yard", "path": [at - into * 3.0], "reverse": 1},
		{"do": "drive", "cart": c, "kind": "yard", "path": [door - into * 6.0]},
		{"do": "drive", "cart": c, "kind": "yard", "path": [door, at_space], "reverse": 2},
		{"do": "alight", "cart": c}, {"do": "put_away", "cart": c, "slot": k}]


## The next of the barn's own parked carts due a wash (the longest since its last) driven out to a
## free spot in its row, nose in to the barn, there to be washed (user: each of the barn's carts in
## turn, not one made up for it): its steps, the cart out of its space now; empty with none due,
## or the row full.
func _barn_transfer_busy(own: Walker = null) -> bool:
	for cart: Walker in _pool:
		if cart == own or not cart.data.has("barn_slot") or not cart.data.has("job"): continue
		# Refills leave from the outside pickup row, not the garage lanes.
		# Their line reservation must never lock the barn's washing jobs.
		# Vehicle spacing and wash-bay reservations handle the shared apron.
		if _line.has(cart): continue
		return true
	return false


func _barn_cart_out(p: Walker) -> Array:
	if _barn_transfer_busy(): return []
	var slots := _barn_slots()
	var k := -1
	for j in range(slots.size()):
		if _barn_out.has(j) or not _barn_slot_clear(j):
			continue
		if k < 0 or float(_bay_washed.get(j, -INF)) < float(_bay_washed.get(k, -INF)):
			k = j
	if k < 0:
		return []
	var barn := _fac("cart_barn")
	var c := _cart()
	if c == null:
		return []
	var spot := _barn_spot_by_reel(c)
	if spot == Vector2.INF:
		c.node.queue_free()
		return []
	var into := barn.global_transform.basis.z.normalized()
	c.node.global_transform = slots[k]
	c.ground = true
	c.speed = RIDE * 0.6
	c.data["job"] = true  # (nobody's until it's in the row)
	c.data["parking_target"] = spot
	c.data["barn_slot"] = k
	p.data["wash_cart"] = c
	c.data["washing"] = true
	_barn_out[k] = c
	_barn_slot_shown(k, false)
	_pool.append(c)  # (one of the club's carts, stepped with them: not yet in the barn's stock)
	_invalidate_traffic()
	var door := _barn_door(k)
	var row := Vector3(spot.x, door.y, spot.y)
	return [{"do": "walk", "cart": c, "at": "door"}, {"do": "board", "cart": c},
		{"do": "drive", "cart": c, "kind": "yard", "path": [door]},
		{"do": "drive", "cart": c, "kind": "yard", "path": [door - into * 5.0]},
		{"do": "drive", "cart": c, "kind": "yard", "path": [row - into * 3.5]},
		{"do": "drive", "cart": c, "kind": "yard", "path": [row]},
		{"do": "alight", "cart": c}, {"do": "settle", "cart": c, "spot": spot}, {"do": "begin_wash", "cart": c}]


## A free spot in the barn's row for cart `own` (as _barn_spot) where its driver, out on his side
## (its left: nose in to the barn), has the hose reel nearest -- a step or two left of him, not round
## the cart and back (user); any free one with no reel.
# Wash between the garage entry lanes, leaving those lanes open for returns.
# The smaller barns' original pickup markers were only 2.4m apart.
func _wash_bays(barn: Node3D) -> Array:
	var level := int(FacilityBuilder.rig(barn).get("level", 1))
	if level >= 4:
		var between_lanes: Array = []
		for x: float in [-0.6, 4.6, 9.8]: between_lanes.append(Transform3D(Basis(), Vector3(x, 0.0, 5.1)))
		return between_lanes
	var spacing: float = {1: 4.8, 2: 5.6, 3: 6.95}[level]
	var front: float = {1: 0.6, 2: 1.0, 3: 2.4}[level]
	var bays: Array = []
	for x: float in [-spacing, 0.0, spacing]: bays.append(Transform3D(Basis(), Vector3(x, 0.0, front)))
	return bays


func _barn_spot_by_reel(own: Walker) -> Vector2:
	var barn := _fac("cart_barn")
	var reel := _hose_stand()
	if barn == null or reel == Vector2.INF:
		return _barn_spot(own)
	var into := barn.global_transform.basis.z.normalized()
	var left := Vector3(into.z, 0.0, -into.x)  # (the driver's side, facing the barn: -X of the cart)
	var best := Vector2.INF
	for xf: Transform3D in _wash_bays(barn):
		var p := barn.global_transform * xf.origin
		var spot := Vector2(p.x, p.z)
		var taken := false
		for v: Walker in _vehicles():
			if v != own and v.node.visible and (spot.distance_to(Vector2(v.node.global_position.x, v.node.global_position.z)) < 1.8 or (v.data.has("parking_target") and spot.distance_to(v.data["parking_target"]) < 1.8)):
				taken = true
		if taken:
			continue
		var door := p + left * (CART_DOOR + 0.9)
		if best == Vector2.INF or Vector2(door.x, door.z).distance_to(reel) < (Vector3(best.x, 0, best.y) + left * (CART_DOOR + 0.9)).distance_to(Vector3(reel.x, 0, reel.y)):
			best = spot
	return best


## Where the hoser stands at the barn's hose reel (world XZ): a step out from the wall in front of
## it; INF with no reel.
func _wall_reels(barn: Node3D) -> Array:
	var rig := FacilityBuilder.rig(barn)
	var reels: Array = rig.get("hose_reels", []).duplicate()
	if reels.is_empty() and rig.has("hose_reel"): reels.append(rig["hose_reel"])
	reels.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.x < b.origin.x)
	return reels


func _wall_hooks(barn: Node3D) -> Array:
	var rig := FacilityBuilder.rig(barn)
	var hooks: Array = rig.get("hose_hooks", []).duplicate()
	if hooks.is_empty() and rig.has("hose_hook"): hooks.append(rig["hose_hook"])
	hooks.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return a.origin.x < b.origin.x)
	return hooks


func _wash_station(p: Walker, c: Walker) -> Dictionary:
	if p.data.has("wash_station"): return p.data["wash_station"]
	var barn := _fac("cart_barn")
	if barn == null: return {}
	var reels := _wall_reels(barn)
	var hooks := _wall_hooks(barn)
	var best := {}
	var distance := INF
	for index in mini(reels.size(), hooks.size()):
		if _cart_boys().any(func(other: Walker) -> bool: return other != p and int(other.data.get("wash_station", {}).get("index", -1)) == index): continue
		var outlet := barn.global_transform * (reels[index] as Transform3D).origin
		var hook := barn.global_transform * (hooks[index] as Transform3D).origin
		var out := Vector2(outlet.x - hook.x, outlet.z - hook.z).normalized()
		var stand := Vector2(hook.x, hook.z) + out * 0.75
		var d := Vector2(c.node.global_position.x, c.node.global_position.z).distance_to(stand)
		if d < distance:
			distance = d
			best = {"index": index, "outlet": outlet, "stand": stand, "rest": _hose_rest(barn, index)}
	if not best.is_empty(): p.data["wash_station"] = best
	return best


func _hose_stand() -> Vector2:
	var barn := _fac("cart_barn")
	if barn == null:
		return Vector2.INF
	var rig := FacilityBuilder.rig(barn)
	if not rig.has("hose_reel") or not rig.has("hose_hook"):
		return Vector2.INF
	var reel := barn.global_transform * (rig["hose_reel"] as Transform3D).origin
	var hook := barn.global_transform * (rig["hose_hook"] as Transform3D).origin
	var out := Vector2(reel.x - hook.x, reel.z - hook.z).normalized()
	return Vector2(hook.x, hook.z) + out * 0.75


## Cart boy `p`'s wipe-down of a cart waiting in the line behind the clubhouse, where it stands (no
## hose out there: dried and wiped, its side then its hood), so he's not stood about between bag
## runs (user). Empty with none due one.
func _wipe_steps(p: Walker) -> Array:
	var due: Array = []
	for c: Variant in _line:
		if c != null and not (c as Walker).data.has("job") and not (c as Walker).data.has("washing") 				and _clock - float((c as Walker).data.get("washed_at", -WASH_AGAIN)) >= WASH_AGAIN:
			due.append(c)
	if due.is_empty():
		return []
	var here := p.node.global_position
	due.sort_custom(func(a: Walker, b: Walker) -> bool: return a.node.global_position.distance_to(here) < b.node.global_position.distance_to(here))
	var c: Walker = due[0]
	c.data["washing"] = true
	c.data["line_wipe"] = true
	p.data["wash_cart"] = c
	var at := c.node.global_transform * Vector3(-1.16, 0, 0)
	return [{"do": "walk", "to": Vector2(at.x, at.z)},
		{"do": "dry", "cart": c},
		{"do": "wash_step", "cart": c, "local": Vector3(-1.16, 0, -1.73)},
		{"do": "wash_step", "cart": c, "local": Vector3(0, 0, -1.73)},
		{"do": "dry", "cart": c, "hood": true}]


## The hands on each dial of the clubhouse lawn's street clock (its rig's "clock_faces"): an hour
## and a minute hand on each, on the clubhouse so they stay with it; _turn_clock_hands keeps them
## to the club's time.
func _clock_hands(house: Node3D) -> void:
	if house == null or house.get_node_or_null("ClockHands") != null:
		return
	var faces: Array = FacilityBuilder.rig(house).get("clock_faces", [])
	if faces.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "ClockHands"
	house.add_child(holder)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color("15181a")
	ink.roughness = 0.6
	for xf: Transform3D in faces:
		var face := Node3D.new()
		face.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		holder.add_child(face)
		for spec in [["hour", 0.035, 0.24], ["minute", 0.024, 0.36]]:
			var pivot := Node3D.new()
			pivot.name = spec[0]
			pivot.position = Vector3(0, 0, -0.008 if spec[0] == "hour" else -0.014)  # (out of the dial, the minute hand over the hour)
			face.add_child(pivot)
			var hand := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(spec[1], spec[2], 0.006)
			bm.material = ink
			hand.mesh = bm
			hand.position = Vector3(0, spec[2] * 0.42, 0)  # (from just behind the hub, out to its tip)
			hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(hand)
	_turn_clock_hands()


## The clock's hands set to the club's time of day (CourseBusiness.time_of_day): clockwise as read
## from in front of each dial.
func _turn_clock_hands() -> void:
	var house := _fac("clubhouse")
	var holder := house.get_node_or_null("ClockHands") if house != null else null
	if holder == null or business == null:
		return
	var t := business.time_of_day()
	for face in holder.get_children():
		(face.get_node("hour") as Node3D).rotation.z = fmod(t, 12.0) / 12.0 * TAU
		(face.get_node("minute") as Node3D).rotation.z = fmod(t, 1.0) * TAU


## The barn's hose at rest on the reel on its wall (FacilityBuilder's rig: "hose_reel", "hose_hook"):
## off the drum, looped up over the hook under it and its nozzle hanging off that -- on the barn,
## so it stays put with it. Null for a barn without one.
func _hose_rest(barn: Node3D, index: int = 0) -> Node3D:
	if barn == null:
		return null
	var name := "HoseRest" if index == 0 else "HoseRest%d" % index
	var rest := barn.get_node_or_null(name) as Node3D
	if rest != null:
		return rest
	var reels := _wall_reels(barn)
	var hooks := _wall_hooks(barn)
	if index >= mini(reels.size(), hooks.size()): return null
	rest = Node3D.new()
	rest.name = name
	barn.add_child(rest)
	var a: Vector3 = (reels[index] as Transform3D).origin
	var hook: Vector3 = (hooks[index] as Transform3D).origin
	var out := Vector3(a.x - hook.x, 0.0, a.z - hook.z).normalized()  # (off the wall)
	var down := Vector3.DOWN
	# off the bottom of the drum, sagging below the hook, up over it and down to the nozzle
	var pts: Array = []
	var n := 14
	for i in range(n + 1):
		var t := float(i) / n
		var u := 1.0 - t
		var b1 := a + down * 0.45 + out * 0.04
		var b2 := hook + down * 0.55 + out * 0.12
		pts.append(a * u * u * u + b1 * 3.0 * u * u * t + b2 * 3.0 * u * t * t + hook * t * t * t)
	pts.append(hook + out * 0.03 + down * 0.08)
	var loop := MeshInstance3D.new()
	loop.mesh = _tube(pts, 0.014)
	loop.material_override = _hose_material(false)
	rest.add_child(loop)
	var nozzle := _nozzle()
	nozzle.position = hook + out * 0.03 + down * 0.19
	nozzle.basis = Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD)  # (tip down)
	rest.add_child(nozzle)
	return rest


## The hose's green (or the nozzle's steel).
func _hose_material(steel: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("8d9399") if steel else Color("2f7d32")
	m.metallic = 0.6 if steel else 0.0
	m.roughness = 0.4 if steel else 0.55
	return m


## The hose's nozzle: tip at its +Y.
func _nozzle() -> MeshInstance3D:
	var nozzle := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.012
	nm.bottom_radius = 0.02
	nm.height = 0.22
	nm.material = _hose_material(true)
	nozzle.mesh = nm
	return nozzle


## The hose off the barn's wall reel to the nozzle in the cart boy's hand, the water spraying from
## it: its end and nozzle off the hook (the rest hidden till he hangs them back up).
func _hose_on(p: Walker, c: Walker) -> void:
	_hose_off(p)
	var barn := _fac("cart_barn")
	var station: Dictionary = p.data.get("wash_station", {})
	var rest: Node3D = station.get("rest", _hose_rest(barn))
	var outlet: Vector3 = station.get("outlet", Vector3.INF)
	if rest != null:
		rest.visible = false
		if outlet == Vector3.INF: outlet = barn.global_transform * (FacilityBuilder.rig(barn)["hose_reel"] as Transform3D).origin
	var hose := MeshInstance3D.new()
	hose.name = "Hose"
	hose.material_override = _hose_material(false)
	add_child(hose)
	# the nozzle in his hand, and the spray from it
	var nozzle := _nozzle()
	add_child(nozzle)
	var spray := CPUParticles3D.new()
	spray.amount = 90
	spray.lifetime = 0.55
	spray.direction = Vector3(0, 1, 0)  # (out of the nozzle's tip: its +Y)
	spray.spread = 7.0
	spray.initial_velocity_min = 6.5
	spray.initial_velocity_max = 8.0
	spray.gravity = Vector3(0, -9.8, 0)
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.4
	var drop := SphereMesh.new()
	drop.radius = 0.012
	drop.height = 0.024
	drop.radial_segments = 4
	drop.rings = 2
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.82, 0.92, 1.0, 0.55)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = water
	spray.mesh = drop
	spray.position = Vector3(0, 0.11, 0)
	nozzle.add_child(spray)
	p.data["hose"] = {"rest": rest, "hose": hose, "nozzle": nozzle, "outlet": outlet, "cart": c}
	_hose_follow(p)


## The hose put away: wound back on the reel, its end and nozzle hung back up on the hook.
func _hose_off(p: Walker) -> void:
	var h: Dictionary = p.data.get("hose", {})
	for key in ["hose", "nozzle"]:
		if h.has(key) and is_instance_valid(h[key]):
			(h[key] as Node).queue_free()
	if h.get("rest") != null and is_instance_valid(h["rest"]):
		(h["rest"] as Node3D).visible = true
	p.data.erase("hose")


## The nozzle in the cart boy's hand, pointed at the cart, and the hose from the reel to it:
## down off the reel onto the ground, along it and up to his hand, a tube redrawn each frame.
func _hose_follow(p: Walker) -> void:
	var h: Dictionary = p.data["hose"]
	var skel := p.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or not is_instance_valid(h["nozzle"]):
		return
	var bone := skel.find_bone("grip.L")
	if bone < 0:
		bone = skel.find_bone("hand.L")
	var hand := (skel.global_transform * skel.get_bone_global_pose(bone)).origin
	var c: Walker = h["cart"]
	var aim := (c.node.global_position + Vector3(0, 0.6, 0) - hand).normalized() if is_instance_valid(c.node) else -p.node.global_transform.basis.z
	var up := aim
	var side := up.cross(Vector3.UP).normalized() if absf(up.y) < 0.99 else Vector3.RIGHT
	(h["nozzle"] as Node3D).global_transform = Transform3D(Basis(side, up, side.cross(up)), hand)
	var a: Vector3 = h["outlet"]
	if a == Vector3.INF:
		return  # (no reel on this barn's wall)
	# the hose's line: off the reel, down to the ground, along it -- round any cart in the way, never
	# through one (user) -- and up into his hand
	var d := hand - aim * 0.1
	var a2 := Vector2(a.x, a.z) + (Vector2(d.x, d.z) - Vector2(a.x, a.z)).normalized() * 0.35
	var route := _hose_route(a2, Vector2(d.x, d.z) - Vector2(aim.x, aim.z).normalized() * 0.3)
	var line: Array = [a, Vector3(a2.x, lerpf(a.y, _surface_y(a2), 0.75), a2.y)]
	for q: Vector2 in route:
		line.append(Vector3(q.x, _surface_y(q) + 0.015, q.y))
	line.append(d)
	var pts := _smooth_line(line, 3)
	(h["hose"] as MeshInstance3D).mesh = _tube(pts, 0.014)


## The hose's way along the ground from `a` to `b` (world XZ): round each cart in between -- a
## step clear of its body -- not through it. Points from a to b.
func _hose_route(a: Vector2, b: Vector2) -> Array:
	var carts: Array = []
	var span := Rect2(a, Vector2.ZERO).expand(b).grow(4.0)
	for v: Walker in _vehicles():
		if v.data.get("golf_cart", false) and v.node.visible and span.has_point(Vector2(v.node.global_position.x, v.node.global_position.z)):
			carts.append(v)
	var clear := CART_HALF.length() + 0.25  # (round its corners, and the hose's width)
	var route: Array = [a, b]
	for pass_i in range(8):
		var hit := false
		for i in range(route.size() - 1):
			var p: Vector2 = route[i]
			var q: Vector2 = route[i + 1]
			for c: Walker in carts:
				var o := Vector2(c.node.global_position.x, c.node.global_position.z)
				var near := Geometry2D.get_closest_point_to_segment(o, p, q)
				if near.distance_to(o) >= clear - 0.05 or o.distance_to(a) < clear * 0.6 or o.distance_to(b) < clear * 0.6:
					continue
				# round it on the side the line already passes
				var off := near - o
				if off.length() < 0.01:
					off = (q - p).orthogonal()
				route.insert(i + 1, o + off.normalized() * (clear + 0.1))
				hit = true
				break
			if hit:
				break
		if not hit:
			break
	return route


## `pts` (Vector3s) rounded off (Chaikin, `passes` times): its ends kept.
static func _smooth_line(pts: Array, passes: int) -> Array:
	var out := pts
	for k in range(passes):
		var next: Array = [out[0]]
		for i in range(out.size() - 1):
			var p: Vector3 = out[i]
			var q: Vector3 = out[i + 1]
			next.append(p.lerp(q, 0.25))
			next.append(p.lerp(q, 0.75))
		next.append(out[out.size() - 1])
		out = next
	return out


## A tube of radius `r` along `pts` (six-sided).
func _tube(pts: Array, r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings: Array = []
	for i in range(pts.size()):
		var tangent: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var nrm := tangent.cross(Vector3.UP).normalized() if absf(tangent.y) < 0.99 else Vector3.RIGHT
		var bi := tangent.cross(nrm).normalized()
		var ring: Array = []
		for k in range(sides):
			var ang := TAU * k / sides
			ring.append((pts[i] as Vector3) + (nrm * cos(ang) + bi * sin(ang)) * r)
		rings.append(ring)
	for i in range(rings.size() - 1):
		for k in range(sides):
			var k2 := (k + 1) % sides
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- bag runs
# A flight riding carts doesn't fetch its bags from the bag drop. Once they're all in, the cart
# boy brings a cart round -- out of the barn's row or off the line behind the clubhouse, whichever
# he's nearer -- up the front drive to the curb by the bag drop, carries the flight's bags over to
# it two at a time (the first pair's into its bag well, the second pair's onto its passenger
# side), and drives it round to the end of the walk out the back; then a second cart, for the
# second pair, off the line there to beside it, their bags moved across into its well. Checked in,
# the flight comes out the back to the end of the walk, gets in and goes (cart_wait).

## Flight `g`'s carts claimed for a bag run and the run in the cart boy's queue (g.bag_run). False,
## nothing changed, when they walk, are off to practise first, have their carts already, or
## there's no cart boy, front drive, walk or carts to be had.
func _bag_run(g: Group) -> bool:
	if g.golfers.any(func(w:Walker)->bool:return w.data.has("rack_delivery")):return false
	if g.valet_service.get("stage","") in ["arrival","unload","bag_drop"]:return false
	if g.bag_run or not g.carts.is_empty() or not g.wants_cart:
		return false
	var boys := _staff.filter(func(p: Walker) -> bool: return str(p.data.get("role", "")) == "cart_attendant")
	var house := _fac("clubhouse")
	if boys.is_empty() or house == null or _front_drive().is_empty() or (FacilityBuilder.rig(house).get("tee_way", []) as Array).is_empty():
		return false
	var need := ceili(g.golfers.size() / 2.0)
	# off the line behind the clubhouse (the barn keeps it stocked: _cart_job), the barn's own only
	# when the line's out of them
	for i in range(need):
		var c := _claim_cart("line")
		if c == null:
			c = _claim_cart("barn")
		if c == null:
			break
		c.speed = RIDE
		c.ground = true
		g.carts.append(c)
		_invalidate_traffic()
	if g.carts.size() < need:
		_cancel_bag_run(g)
		return false
	for i in range(g.carts.size()):
		if _bag_run_meet(g.carts[i], i) == Vector2.INF:
			_cancel_bag_run(g)
			return false
	for c: Walker in g.carts:
		c.data["job"] = true
	g.bag_run = true
	for i in range(g.carts.size()):
		_bag_runs.append([g, i])  # (a cart each: a cart boy apiece when there's two)
	for p: Walker in boys:
		if (p.data.get("steps", []) as Array).is_empty() and not p.riding and not p.data.has("cart_move") and not p.data.has("wash_cart"):
			p.path.clear()
			p.data["blocked"] = false
			p.wait = minf(p.wait, 0.3)
	return true


## The head of the line behind the clubhouse (world XZ); INF without one.
func _line_head() -> Vector2:
	var slots := _line_slots()
	if slots.is_empty():
		return Vector2.INF
	var o: Vector3 = (slots[0] as Transform3D).origin
	return Vector2(o.x, o.z)


## One of the club's carts for a bag run: the frontmost off the line behind the clubhouse ("line":
## its head row, the left, before the right -- user; never one past another, whose way out would be
## through it: wait while the front one is being cleaned or moved),
## or out of the barn's row ("barn"); null when there's none to be had there.
func _claim_cart(from: String) -> Walker:
	if from == "line":
		for i in range(_line.size()):
			var c: Variant = _line[i]
			if c == null:
				continue
			if (c as Walker).data.has("job"):
				return null  # (being moved up the line: none past it, its way out blocked -- one from the barn)
			if (c as Walker).data.has("washing"):
				return null  # Finish the cleaning job before this cart is rented out.
			_line[i] = null
			_pool.erase(c)
			_invalidate_traffic()
			(c as Walker).data["lead_out"] = _line_exit(i)
			(c as Walker).data["lead_reverse"] = 0
			(c as Walker).data["run_slot"] = i
			return c
		return null
	if _fac("cart_barn") == null:
		return null
	var c: Walker = _stock.pop_front() if not _stock.is_empty() else _new_barn_cart()
	if c != null:
		_pool.erase(c)
		_invalidate_traffic()
	return c


## Flight `g`'s bag run called off before it began: its carts back where they came from.
func _cancel_bag_run(g: Group) -> void:
	_bag_runs = _bag_runs.filter(func(run: Array) -> bool: return run[0] != g)
	for c: Walker in g.carts:
		for key in ["job", "parking_target", "front_cart_route"]:
			c.data.erase(key)
		var slot := int(c.data.get("run_slot", -1))
		c.data.erase("run_slot")
		if slot >= 0 and slot < _line.size() and _line[slot] == null:
			c.data.erase("lead_out")
			c.data.erase("lead_reverse")
			_line[slot] = c
		else:
			_stock.push_front(c)
		_pool.append(c)
		_invalidate_traffic()
	g.carts.clear()
	_invalidate_traffic()
	g.bag_run = false


## The cart boy `p`'s next bag run, as steps (at a jog): one cart of a flight's -- over to it on the
## line behind the clubhouse and in, up the front drive to the curb, that cart's pair's two bags
## from the bag drop (one on each shoulder) into its well, back in, round to the end of the walk
## out the back, and theirs. A flight of four's second cart is a run of its own: another cart
## boy's at once when there's one free, else his next. Empty with none waiting.
func _bag_run_steps(p: Walker) -> Array:
	while not _bag_runs.is_empty():
		var run: Array = _bag_runs.pop_front()
		var g: Group = run[0]
		var i: int = run[1]
		if not g in _groups or not g.bag_run or i >= g.carts.size() or (g.carts[i] as Walker).data.get("delivered", false):
			continue
		var c: Walker = g.carts[i]
		var steps: Array = [{"do": "walk", "cart": c, "at": "door"}, {"do": "board", "cart": c}]
		# this cart's pair's bags, the two at once, over to its bag well
		var two: Array = []
		for k in [i * 2, i * 2 + 1]:
			if k < g.golfers.size() and (g.golfers[k] as Walker).data.get("valet", false) and (g.golfers[k] as Walker).data.has("bag_down"):
				two.append(k)
		if not two.is_empty():
			steps.append_array([{ "do": "drive", "cart": c, "kind": "curb", "index": i}, {"do": "alight", "cart": c}])
		for h in range(two.size()):
			steps.append_array([{"do": "walk", "cart": c, "at": "bag", "golfer": g.golfers[two[h]]}, {"do": "grab", "cart": c, "golfer": g.golfers[two[h]], "hand": h}])
		if not two.is_empty():
			steps.append({"do": "walk", "cart": c, "at": "well"})
		for h in range(two.size()):
			steps.append({"do": "stow", "cart": c, "golfer": g.golfers[two[h]], "seat": two[h] % 2, "hand": h})
		if not two.is_empty(): steps.append_array([{"do": "walk", "cart": c, "at": "door"}, {"do": "board", "cart": c}])
		steps.append_array([{"do": "drive", "cart": c, "kind": "over" if two.is_empty() else "away"}, {"do": "alight", "cart": c},
			{"do": "hand_over", "group": g, "index": i}])
		p.speed = WALK * 1.5
		return steps
	return []


## Where a bag-run walk goes (world XZ): the driver's side of its cart, the passenger's side (where
## the second pair's bags ride), round behind it to the bag well, or up to a golfer's bag at the bag
## drop (on the cart's side of it).
func _bag_run_goal(s: Dictionary) -> Vector2:
	var c: Walker = s["cart"]
	var at := _cart_door(c, 0)
	match str(s.get("at", "door")):
		"cargo":
			at = _cart_door(c, 1)
		"well":
			at = c.node.global_transform * Vector3(0, 0, CART_HALF.y + 0.6)  # (the cart faces -Z)
		"bag":
			var stand: Variant = (s["golfer"] as Walker).data.get("bag_down")
			if stand != null and is_instance_valid(stand):
				var b := (stand as Node3D).global_position
				var point := Vector2(b.x, b.z)
				if _is_rack_bag(point): return _valet_rack_approach(point)
				var toward := Vector2(c.node.global_position.x - b.x, c.node.global_position.z - b.z).normalized()
				return Vector2(b.x, b.z) + toward * 0.6
	return Vector2(at.x, at.z)


## FRONT_DRIVE for the clubhouse as it's built (world points): [in, out, backed off first]; empty
## without one. Along its cart path (CART_PATHS) rounded as it's paved, for the carts to follow its
## bends: in, the path then on to the curb; out, back onto it and along it the other way.
func _front_drive() -> Array:
	var house := _fac("clubhouse")
	if house == null:
		return []
	var level := clampi(int(FacilityBuilder.rig(house).get("level", 1)), 1, 4)
	var plan: Array = FRONT_DRIVE.get(level, [])
	if plan.is_empty():
		return []
	var legs: Array = [plan[0], plan[1]]
	if CART_PATHS.has(level):
		var path := _round_corners(CART_PATHS[level], float(CART_PATH_TURN[level]))
		var back := path.duplicate()
		back.reverse()
		var approach := path
		if level == 4:
			# Leave the ready line outward before turning; do not cross the neighboring row.
			approach = [Vector2(25.3, 46.0)] + path.slice(1)
		legs = [approach.slice(0, approach.size() - 1) + plan[0], plan[1] + back.slice(1)]
	var out: Array = []
	for leg: Array in legs:
		var pts: Array = []
		for q: Vector2 in leg:
			pts.append(house.global_transform * Vector3(q.x, 0.0, q.y))
		out.append(pts)
	out.append(plan[2])  # (backed off the curb first)
	return out


## The polyline `pts` (Vector2s) with each corner filleted: an arc of radius `r` (less where its
## legs are short) in place of the corner -- as build_facilities.rounded_corners paves it.
static func _round_corners(pts: Array, r: float, step: float = deg_to_rad(9.0)) -> Array:
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var d1 := (a - b).normalized()
		var d2 := (c - b).normalized()
		var th := acos(clampf(d1.dot(d2), -1.0, 1.0))
		if th > deg_to_rad(170.0) or th < deg_to_rad(10.0):
			out.append(b)
			continue
		var t := minf(r / tan(th * 0.5), minf(a.distance_to(b), c.distance_to(b)) * 0.45)
		var rr := t * tan(th * 0.5)
		var p1 := b + d1 * t
		var p2 := b + d2 * t
		var centre := b + (d1 + d2).normalized() * (rr / sin(th * 0.5))
		var a1 := (p1 - centre).angle()
		var da := wrapf((p2 - centre).angle() - a1, -PI, PI)
		var n := maxi(2, ceili(absf(da) / step))
		for j in range(n + 1):
			out.append(centre + Vector2.from_angle(a1 + da * j / n) * rr)
	out.append(pts[pts.size() - 1])
	return out


## Cart `c`'s way on a bag run (world points). "curb": out of where it stands (backed out of the
## barn's row, or up the line and off its head), across the course to the foot of the front drive
## and up it to the curb. "away": backed off the curb, round and down the drive, and across to where
## its riders are to find it (its parking target). "over": out of where it stands straight there.
## The paved front approach is shared by incoming and departing bag carts.
## Reserve the whole trip, including loading, so the outbound cart can always leave.
func _claim_front_cart_route(cart: Walker) -> bool:
	for other: Walker in _vehicles():
		if other == cart or not other.data.get("front_cart_route", false): continue
		if not other.data.has("job") or other.data.get("delivered", false):
			other.data.erase("front_cart_route")
			continue
		return false
	cart.data["front_cart_route"] = true
	return true


func _bag_run_way(c: Walker, kind: String, index: int = 0) -> Array:
	var drive := _front_drive()
	if drive.is_empty():
		return []
	var meet: Vector2 = c.data.get("parking_target", Vector2(c.node.global_position.x, c.node.global_position.z))
	if kind == "away":
		var way_out: Array = drive[1]
		var last: Vector3 = way_out[way_out.size() - 1]
		c.data["reverse"] = 1 if drive.size() < 3 or drive[2] else 0  # (backed off the curb, with no drive on round)
		return way_out + _cart_way(Vector2(last.x, last.z), meet)
	var lead: Array = c.data.get("lead_out", [])
	c.data["reverse"] = int(c.data.get("lead_reverse", 0)) if not lead.is_empty() else 0
	c.data.erase("lead_out")
	c.data.erase("lead_reverse")
	var at: Vector3 = lead[lead.size() - 1] if not lead.is_empty() else c.node.global_position
	if kind == "over":
		return lead + _cart_way(Vector2(at.x, at.z), meet)
	var way_in: Array = (drive[0] as Array).duplicate()
	if index % 2 == 1 and way_in.size() >= 2:
		# (a flight's second cart pulls up a cart's length short of the first, behind it on the
		# drive, the two loading at once)
		var last: Vector3 = way_in[way_in.size() - 1]
		var prev: Vector3 = way_in[way_in.size() - 2]
		way_in[way_in.size() - 1] = last - (last - prev).normalized() * minf(4.5, last.distance_to(prev) * 0.8)
	var first: Vector3 = way_in[0]
	return lead + _cart_way(Vector2(at.x, at.z), Vector2(first.x, first.z)) + way_in.slice(1)


## By cart across the course from `a` to `b` (world XZ), round what's in the way; straight there
## when there's no way round.
func _cart_way(a: Vector2, b: Vector2) -> Array:
	var r := _course_leg(a, b, true)
	if r.is_empty():
		r = _via_yards(a, b, true)
	return r if not r.is_empty() else [Vector3(b.x, 0.0, b.y)]


## Where a flight's `i`th cart is left for its riders (world XZ; reserved for `c`): out past the
## end of the walk off the back of the clubhouse, beside it on the side away from the line's head.
## INF without a walk or room there.
func _bag_run_meet(c: Walker, i: int) -> Vector2:
	var house := _fac("clubhouse")
	var way: Array = FacilityBuilder.rig(house).get("tee_way", []) if house != null else []
	if way.is_empty():
		return Vector2.INF
	var end: Vector3 = (way[way.size() - 1] as Transform3D).origin
	var level := clampi(int(FacilityBuilder.rig(house).get("level", 1)), 1, 4)
	if CART_PATH_MEET.has(level):
		var at: Vector2 = CART_PATH_MEET[level]
		var on_path := house.global_transform * Vector3(at.x + 3.8 * i, 0.0, at.y)
		return _cart_parking_point(Vector2(on_path.x, on_path.z), c)
	var side := 1.0
	var head := _line_head()
	if head != Vector2.INF:
		side = -1.0 if (house.global_transform.affine_inverse() * Vector3(head.x, 0, head.y)).x > end.x else 1.0
	var want := house.global_transform * Vector3(end.x + side * (3.5 + 3.8 * i), 0.0, FacilityBuilder.footprint("clubhouse").y * 0.5 + 4.0)
	return _cart_parking_point(Vector2(want.x, want.z), c)


## `w`'s bag (the valet's still: on its stand, in the cart boy's hands, on a cart's passenger side
## or gone astray) in cart `c`'s bag well behind seat `seat`: theirs again, to ride.
func _bag_aboard(w: Walker, c: Walker, seat: int) -> void:
	var stand: Variant = w.data.get("bag_down")
	if stand != null and is_instance_valid(stand):
		(stand as Node).queue_free()
	w.data.erase("bag_down")
	_drop_bag(w)
	_cart_bag(c, seat, str(w.data.get("bag_livery", "")))
	w.data.erase("valet")
	w.data.erase("valet_at")


## Golfer `w`'s bag stood on cart `c`'s passenger side, in the footwell leaning back on the seat
## (the second pair's, riding round to their own cart).
func _cargo_on(c: Walker, w: Walker) -> void:
	var scene := _bag_scene(str(w.data.get("bag_livery", "")))
	if scene == null:
		return
	var cargo: Array = c.data.get_or_add("cargo", [])
	var bag := scene.instantiate() as Node3D
	c.node.add_child(bag)
	bag.transform = Transform3D(Basis(Vector3.RIGHT, 0.3), CART_CARGO[cargo.size() % CART_CARGO.size()])
	cargo.append([w, bag])


## Golfer `w`'s bag off cart `c`'s passenger side; false if it wasn't there.
func _cargo_off(c: Walker, w: Walker) -> bool:
	var cargo: Array = c.data.get("cargo", [])
	for i in range(cargo.size()):
		if cargo[i][0] == w:
			if is_instance_valid(cargo[i][1]):
				(cargo[i][1] as Node).queue_free()
			cargo.remove_at(i)
			return true
	return false


## Every bag of flight `g`'s the valet still has into its owner's cart.
func _bags_aboard(g: Group) -> void:
	for k in range(g.golfers.size()):
		if k / 2 < g.carts.size() and (g.golfers[k] as Walker).data.get("valet", false):
			_cargo_off(g.carts[0], g.golfers[k])
			_bag_aboard(g.golfers[k], g.carts[k / 2], k % 2)


## The cart boy on a bag run with cart `c` off it: out of it, his hands empty, his steps dropped.
func _bag_run_let_go(c: Walker) -> void:
	for p: Walker in _staff:
		var mine := false
		for s: Dictionary in p.data.get("steps", []):
			mine = mine or s.get("cart") == c
		if not mine and p.node.get_parent() != c.node:
			continue
		if p.riding:
			_unseat(p, c, 0)
		_drop_bag(p)
		_drop_bag(p, "bag2")
		p.data["steps"] = []
		p.data.erase("watch")
		p.speed = WALK


## Any flight's bag run still to finish (its cart boy's gone: the staff were respawned) back in
## the queue for the next cart boy.
func _requeue_bag_runs() -> void:
	for g: Group in _groups:
		if not g.bag_run:
			continue
		for i in range(g.carts.size()):
			var queued := _bag_runs.any(func(run: Array) -> bool: return run[0] == g and run[1] == i)
			if not (g.carts[i] as Walker).data.get("delivered", false) and not queued:
				_bag_runs.append([g, i])


## A free spot in the cart barn's pickup row (world XZ) for cart `own`: one no other cart stands
## on or is headed for. INF when the row's full, or there's no barn.
func _barn_spot(own: Walker) -> Vector2:
	var barn := _fac("cart_barn")
	if barn == null:
		return Vector2.INF
	for xf: Transform3D in _wash_bays(barn):
		var p := barn.global_transform * xf.origin
		var spot := Vector2(p.x, p.z)
		var free := true
		for v: Walker in _vehicles():
			if v == own:
				continue
			if v.node.visible and spot.distance_to(Vector2(v.node.global_position.x, v.node.global_position.z)) < 1.8:
				free = false
			if v.data.has("parking_target") and spot.distance_to(v.data["parking_target"]) < 1.8:
				free = false
		if free:
			return spot
	return Vector2.INF


## A bag in the cart's bag well.
func _cart_bag(c: Walker, k: int, livery: String = "") -> void:
	var scene := _bag_scene(livery)
	if scene == null:
		return
	var bag := scene.instantiate() as Node3D
	c.node.add_child(bag)
	(c.data.get_or_add("bags", []) as Array).append(bag)
	# pockets to the back of the cart (+Z), standing in the tray, held by the cradle above it
	bag.transform = Transform3D(Basis(), CART_BAGS[k])


## The drying rag under the cart boy's open hand (user: his fingers up flat, as for a wave or a high
## five -- OpenHand -- not closed on a wad, nor poking through a sheet at his wrist): a folded cloth
## pressed between his palm and the panel he's wiping.
func _rag_on(p: Walker, hood: bool) -> void:
	_rag_off(p)
	var cloth := MeshInstance3D.new()
	cloth.name = "CartDryingRag"
	var pad := BoxMesh.new()
	pad.size = Vector3(0.16, 0.022, 0.2)
	cloth.mesh = pad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d4b989")
	mat.roughness = 1.0
	cloth.material_override = mat
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloth)
	p.data["rag"] = cloth
	p.data["rag_hood"] = hood
	var skel := p.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel != null:
		p.data["open_hand"] = OpenHand.on(skel, "L")
	_rag_follow(p)

func _rag_off(p: Walker) -> void:
	var rag: Node = p.data.get("rag")
	if is_instance_valid(rag): rag.queue_free()
	var hand: Node = p.data.get("open_hand")
	if is_instance_valid(hand): hand.queue_free()
	p.data.erase("rag")
	p.data.erase("rag_hood")
	p.data.erase("open_hand")

func _rag_follow(p: Walker) -> void:
	var skel := p.node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null: return
	var hand := skel.find_bone("hand.L")
	var mid := skel.find_bone("finger_middle1.L")
	if hand < 0: return
	var wrist := (skel.global_transform * skel.get_bone_global_pose(hand)).origin
	var knuckle := (skel.global_transform * skel.get_bone_global_pose(mid)).origin if mid >= 0 else wrist + Vector3(0, -0.08, 0)
	var palm := (wrist + knuckle) * 0.5
	# the panel's toward the cart (its side) or down onto it (its hood): the cloth flat against it,
	# under his palm, its long way along his fingers
	var c: Walker = p.data.get("wash_cart")
	var into := Vector3.DOWN
	if not bool(p.data.get("rag_hood", false)) and c != null and is_instance_valid(c.node):
		into = c.node.global_position - p.node.global_position
		into.y = 0.0
		into = into.normalized() if into.length() > 0.01 else -p.node.global_basis.z
	var along := knuckle - wrist
	along -= into * along.dot(into)
	along = along.normalized() if along.length() > 0.001 else (Vector3.FORWARD if absf(into.y) > 0.9 else Vector3.UP)
	var across := along.cross(into).normalized()
	var cloth: Node3D = p.data["rag"]
	cloth.global_transform = Transform3D(Basis(across, -into, along), palm + into * 0.03)


# ------------------------------------------------------- Personal-car valet service
# The old "valet" bag flag below means bag-drop custody, never ownership of a
# golf-cart job. Only cart attendants claim bag runs, stock, rearranging and washing.
func _valet_post(p:Walker,index:int)->void:
	# Room assignment replaces job data; restore the existing retargeted clip measurements.
	if not p.data.has("cart_clips"):
		var sk:=p.node.find_child("Skeleton3D",true,false) as Skeleton3D
		if sk!=null:p.data["cart_clips"]=_measure_cart_clips(p,sk)
	var house:=_fac("clubhouse")
	var box:Dictionary=FacilityBuilder.rig(house).get("boxes",{}).get("valet",{})
	if house==null or box.is_empty():return
	var rect:Rect2=box["rect"]
	var counter:=Vector2(-6.65,3.6)
	var local:=Vector3(counter.x-index*.8,0,4.85)
	var world:=house.global_transform*local
	p.node.global_position=Vector3(world.x,_surface_y(Vector2(world.x,world.z)),world.z)
	p.ground=true;p.rest="idle";p.path.clear()
	p.data["valet_home"]=Vector2(world.x,world.z)
	var face:=house.global_transform*Vector3(counter.x,0,counter.y)
	p.data["valet_face"]=Vector2(face.x,face.z)
	p.think=_valet_idle;p.wait=0
	_valet_idle(p)

func _valet_idle(p:Walker)->void:
	if p.data.has("valet_group"):p.wait=.25;return
	var home:Vector2=p.data.get("valet_home",Vector2.INF)
	if home!=Vector2.INF and Vector2(p.node.global_position.x,p.node.global_position.z).distance_to(home)>.4:
		_go(p,home);return
	p.data["watch"]=p.data.get("valet_face",home)
	var at:Vector2=p.data["watch"]-Vector2(p.node.global_position.x,p.node.global_position.z)
	if at.length()>.1:p.node.rotation.y=atan2(-at.x,-at.y)
	p.rest="idle";_play(p,"idle");p.wait=.5

func _valet_staff()->Array:
	return _staff.filter(func(p:Walker)->bool:return p.data.get("role","")=="valet" and is_instance_valid(p.node))

func _valet_free()->Walker:
	for p:Walker in _valet_staff():
		if not p.data.has("valet_group") and not p.riding and p.path.is_empty() and Vector2(p.node.global_position.x,p.node.global_position.z).distance_to(p.data.get("valet_home",Vector2.INF))<.5:return p
	return null

func _valet_curb()->Vector2:
	var house:=_fac("clubhouse")
	if house==null:return Vector2.INF
	var drive := _valet_main_drive(true)
	if drive.is_empty(): return Vector2.INF
	var stop: Vector3 = drive.back()
	return Vector2(stop.x, stop.z)

func _valet_curb_busy(own:Group=null)->bool:
	for other:Group in _groups:
		if other==own:continue
		var stage:String=other.valet_service.get("stage","")
		if stage in ["arrival","greeting","unload","bag_drop","to_driver","fetch","retrieving","pickup_bag","load_trunk","boarding"]:return true
		if stage=="parking" and other.car!=null and Vector2(other.car.node.global_position.x,other.car.node.global_position.z).distance_to(other.valet_service["curb"])<7:return true
	return false

func _valet_offer(g:Group,requested:bool=false)->void:
	if business==null or business.room_tier("valet")<1 or g.visit=="range" or g.range_visit:return
	var curb:=_valet_curb()
	if curb==Vector2.INF:return
	var full:=true
	# Arrival requests are sampled once: only eight percent choose valet.
	if not requested:return
	if not full and g.visit!="":return
	var pocket:=_valet_pocket_slot() if full else -1
	if pocket<0 and g.parking_stall<0:return
	g.valet_service={"used":true,"stage":"arrival_queue","worker":null,"curb":curb,"park":g.parking_path.duplicate(),"next_bag":0,"full":full}
	if pocket>=0:
		g.valet_service["pocket_slot"]=pocket
		g.parking_stall=-1
		g.parking_path=_valet_pocket_path(pocket,true)
		g.exit_path=_valet_pocket_path(pocket,false)
		g.valet_service["park"]=g.parking_path.duplicate()
		_mark_stalls()
	var start:=Vector2(g.car.node.global_position.x,g.car.node.global_position.z)
	var entry:Vector3=_valet_main_drive(true)[0]
	var rank:=0
	for other:Group in _groups:
		if other!=g and other.valet_service.get("stage","")=="arrival_queue":rank+=1
	entry-=_fac("clubhouse").global_basis.z*rank*7.0
	g.car.path=_cart_way(start,Vector2(entry.x,entry.z))
	g.phase="valet_arrival_queue"
	g.car.data["reverse"]=0

func _valet_car_door(g:Group)->Vector2:
	var frame:=_vehicle_frame(g.car)
	var half:=_footprint(g.car)
	# Driver's side is the vehicle's left (-X); -Z is its nose.
	var point:=frame.origin-frame.basis.x.normalized()*(half.x+.75)-frame.basis.z.normalized()*half.y*.08
	return Vector2(point.x,point.z)

func _valet_trunk(g:Group)->Vector2:
	var frame:=_vehicle_frame(g.car)
	var point:=frame.origin+frame.basis.z.normalized()*(_footprint(g.car).y+.85)
	return Vector2(point.x,point.z)


func _valet_at(p:Walker,point:Vector2)->bool:
	if not p.path.is_empty() or p.data.get("blocked",false):return false
	if Vector2(p.node.global_position.x,p.node.global_position.z).distance_to(point)>1.0:
		_go(p,point);return false
	return true

func _valet_unload_arrival(g:Group)->void:
	var here:=Vector2(g.car.node.global_position.x,g.car.node.global_position.z)
	if here.distance_to(g.valet_service["curb"])>1.0:
		g.car.path=_valet_drive_in(here);return
	if g.visit not in ["gym","range","sim","bar"] and g.lane<0 and not _lobby_lane(g):return
	for k in range(g.golfers.size()):
		var w:Walker=g.golfers[k]
		var at:=_by_car(g,k)
		w.node.global_position=Vector3(at.x,_surface_y(at),at.y);w.node.visible=true;w.path.clear()
		var bag:Node3D=w.data.get("bag")
		if bag!=null:bag.visible=false;w.data["valet_in_car"]=true
		var local:=Vector3(-6.65,0,2.35)
		if k>0:local+=Vector3((-.8 if k%2==1 else .8)*ceilf(float(k)/2.0),0,-.9)
		var house:=_fac("clubhouse")
		var arrival:Vector3=house.global_transform*local
		_go(w,Vector2(arrival.x,arrival.z))
		var counter:Vector3=house.global_transform*Vector3(-6.65,0,3.6)
		w.data["watch"]=Vector2(counter.x,counter.z)
	if not g.valet_service.get("full",true):(g.golfers[0] as Walker).data["self_park_driver"]=true
	g.phase="valet_greet";g.valet_service["stage"]="greeting"
	if business.room_tier("valet")<3:
		g.valet_service["next_bag"]=g.golfers.size()
		for w:Walker in g.golfers:
			w.data.erase("valet_in_car")
			var bag:Node3D=w.data.get("bag")
			if bag!=null:bag.visible=true

func _valet_release_worker(p:Walker)->void:
	if p==null:return
	var g:Group=p.data.get("valet_group")
	if g!=null and g.valet_service.get("worker")==p:g.valet_service["worker"]=null
	_drop_bag(p,"valet_carry")
	if p.riding and is_instance_valid(p.node) and p.node.get_parent()!=self:
		p.node.reparent(self,true)
	p.data.erase("cart_move");p.data.erase("valet_drive")
	p.data.erase("valet_group");p.riding=false;p.node.visible=true

func _valet_release(g:Group)->void:
	var p:Walker=g.valet_service.get("worker")
	if p==null:return
	_valet_release_worker(p)
	p.path.clear();p.data["blocked"]=false;_valet_idle(p)

func _valet_drive(p:Walker,g:Group,path:Array,reverse:int=0)->void:
	p.path.clear();p.data.erase("watch");p.data.erase("outdoor_target");p.data.erase("walk_region");p.data["blocked"]=false
	p.node.visible=true
	g.car.path.clear()
	p.data["valet_drive"]={"path":path.duplicate(),"reverse":reverse}
	_climb_in(p,g.car,0)

func _valet_get_out(p:Walker,g:Group)->bool:
	if p.data.has("cart_move"):return false
	if p.riding:
		_climb_out(p,g.car,0)
		return not p.data.has("cart_move")
	p.node.visible=true;p.data["blocked"]=false
	return true


func _valet_finish_drop(g:Group)->void:
	g.valet_service["stage"]="to_driver"
	var p:Walker=g.valet_service.get("worker")
	if p!=null:_go(p,_valet_car_door(g))

func _valet_request_pickup(g:Group)->bool:
	if not g.valet_service.get("used",false) or g.valet_service.get("stage","")!="parked" or _valet_staff().is_empty():return false
	g.valet_service["stage"]="pickup_queue"
	var house:=_fac("clubhouse")
	var front:=_clubhouse_entry()
	var side:Vector3=house.global_basis.x*2.0
	_go_together(g,front+Vector2(side.x,side.z))
	g.phase="valet_pickup_wait"
	return true

# Round the front column before joining the open side of the bag rack.
func _valet_enter_clubhouse(w: Walker, index: int) -> void:
	var house := _fac("clubhouse")
	_guest_nav(house)
	var local := house.global_transform.affine_inverse() * w.node.global_position
	var from := Vector2(local.x, local.z)
	var door := _door_step(index)
	var goal := house.global_transform.affine_inverse() * Vector3(door.x, 0, door.y)
	var path: Array = []
	for to: Vector2 in [Vector2(-3.0 + index * 0.25, 2.0), Vector2(-2.4 + index * 0.25, 9.2), Vector2(goal.x, goal.z)]:
		var leg := FacilityBuilder.nav_route(house, "guest", from, to)
		if leg.is_empty():
			_go_inside(w, house, "guest", Vector2(goal.x, goal.z), 0.0)
			w.ground = true
			return
		for i in range(1, leg.size()): path.append(house.global_transform * Vector3(leg[i].x, 0, leg[i].y))
		from = leg[leg.size() - 1]
	w.data.erase("watch")
	w.data.erase("outdoor_target")
	w.data.erase("indoor_target")
	w.data["walk_region"] = {"nav": FacilityBuilder.rig(house)["nav"]["guest"], "xf": house.global_transform}
	w.data["blocked"] = false
	w.ground = true
	w.path = _round_vehicles(w.node.global_position, path)
	w.wait = index * 0.2


func _valet_service_step(g:Group,delta:float=0.0)->void:
	var service:=g.valet_service
	if service.is_empty():return
	var active_driver:Walker=service.get("worker")
	if active_driver!=null and active_driver.data.has("valet_drive"):
		if active_driver.data.has("cart_move"):return
		var drive:Dictionary=active_driver.data["valet_drive"]
		g.car.path=(drive["path"] as Array).duplicate();g.car.data["reverse"]=drive["reverse"]
		active_driver.data.erase("valet_drive")
	if active_driver!=null and active_driver.data.has("cart_move"):return
	if service.get("stage","")=="greeting":
		if _moving(g.golfers):return
		var greeter:Walker=service.get("worker")
		if greeter==null:return
		var house:=_fac("clubhouse")
		var staff_at:Vector3=house.global_transform*Vector3(-6.65,0,4.85)
		if not _valet_at(greeter,Vector2(staff_at.x,staff_at.z)):return
		var counter:Vector3=house.global_transform*Vector3(-6.65,0,3.6)
		for customer:Walker in g.golfers:
			customer.data["watch"]=Vector2(counter.x,counter.z)
			_play(customer,"idle")
		greeter.data["watch"]=Vector2((g.golfers[0] as Walker).node.global_position.x,(g.golfers[0] as Walker).node.global_position.z)
		service["greet_elapsed"]=float(service.get("greet_elapsed",0.0))+delta
		if float(service["greet_elapsed"]) < VALET_GREETING_SECONDS: return
		service["stage"]="unload";_go(greeter,_valet_trunk(g))
	if g.phase=="valet_greet" and not _moving(g.golfers):
		for k in range(g.golfers.size()):
			if not (g.golfers[k] as Walker).data.get("self_park_driver",false):_valet_enter_clubhouse(g.golfers[k], k)
		g.phase="parking_walk"
		if g.visit=="range":g.checked_in=true;g.phase="range_front"
	var stage:String=service.get("stage","")
	if stage in ["parked","done","self_park"]:return
	if stage=="arrival_queue":
		if _valet_staff().is_empty():return
		# Keep the second employee at the podium while their partner serves a car.
		for worker:Walker in _valet_staff():
			if worker.data.has("valet_group"):return
		if _valet_curb_busy(g):return
		var available:=_valet_free()
		if available==null:return
		service["worker"]=available;available.data["valet_group"]=g
		var staff_at:Vector3=_fac("clubhouse").global_transform*Vector3(-6.65,0,4.85)
		_go(available,Vector2(staff_at.x,staff_at.z))
		service["stage"]="arrival";g.phase="arrive"
		g.car.path=_valet_drive_in(Vector2(g.car.node.global_position.x,g.car.node.global_position.z))
		return
	var p:Walker=service.get("worker")
	if p==null and stage not in ["pickup_queue","parking","retrieving","boarding"]:
		p=_valet_free()
		if p!=null:service["worker"]=p;p.data["valet_group"]=g
		elif _valet_staff().is_empty():
			# Service removed mid-dropoff: guests self-park rather than wait forever.
			for w:Walker in g.golfers:
				_bag_up(w);w.data.erase("valet");w.data.erase("valet_in_car")
				var bag:Node3D=w.data.get("bag")
				if bag!=null:bag.visible=true
				w.node.visible=false;w.path.clear()
			var park:Array=service["park"]
			g.car.path=_cart_way(Vector2(g.car.node.global_position.x,g.car.node.global_position.z),Vector2(park[0].x,park[0].z))+park.slice(1)
			g.valet_service={};g.phase="arrive"
			return
	if stage=="unload" and p!=null and _valet_at(p,_valet_trunk(g)):
		if not _valet_handle_bags(p,g,service,delta):return
		var index:int=service["next_bag"]
		while index<g.golfers.size() and not (g.golfers[index] as Walker).data.has("bag"):index+=1
		service["next_bag"]=index
		if index>=g.golfers.size():_valet_finish_drop(g);return
		var owner:Walker=g.golfers[index]
		var drop:=_bag_drop_spot()
		if drop==Vector2.INF:
			_bag_up(owner);owner.data.erase("valet_in_car")
			var carried_bag:Node3D=owner.data.get("bag")
			if carried_bag!=null:carried_bag.visible=true
			service["next_bag"]=index+1;return
		var owner_bag:Node3D=owner.data.get("bag")
		if owner_bag!=null:owner_bag.visible=true
		owner.data.erase("valet_in_car")
		_bag_down_at(owner,Vector3(drop.x,_surface_y(drop),drop.y),_fac("clubhouse").global_rotation.y+PI*.5)
		owner.data["valet"]=true
		var stand:Node3D=owner.data.get("bag_down")
		if stand!=null:stand.visible=false
		_carry_bag(p,str(owner.data.get("bag_livery","")),"valet_carry")
		service["drop"]=drop;service["stage"]="bag_drop";_go(p,_valet_rack_approach(drop))
	elif stage=="bag_drop" and p!=null and _valet_at(p,_valet_rack_approach(service["drop"])):
		var owner:Walker=g.golfers[int(service["next_bag"])]
		var stand:Node3D=owner.data.get("bag_down")
		if stand!=null:stand.visible=true
		_drop_bag(p,"valet_carry")
		service["next_bag"]=int(service["next_bag"])+1
		service["stage"]="unload";_go(p,_valet_trunk(g))
	elif stage=="to_driver" and p!=null and _valet_at(p,_valet_car_door(g)):
		var park:Array=service["park"]
		var at:=Vector2(g.car.node.global_position.x,g.car.node.global_position.z)
		if not service.get("full",true):
			var driver:Walker=g.golfers[0]
			driver.path.clear();driver.node.visible=false
			var drive:=_valet_drive_out()
			var end:Vector3=drive[-1]
			g.car.path=drive+_cart_way(Vector2(end.x,end.z),Vector2(park[0].x,park[0].z))+park.slice(1)
			service["used"]=false
			_valet_release(g)
		elif service.has("pocket_slot"):
			_valet_drive(p,g,park.slice(1))
		else:
			var driveway:=_valet_drive_out()
			var exit:Vector3=driveway[-1]
			_valet_drive(p,g,driveway+_cart_way(Vector2(exit.x,exit.z),Vector2(park[0].x,park[0].z))+park.slice(1))
		service["stage"]="parking"
	elif stage=="parking" and g.car.path.is_empty():
		var park:Array=service["park"]
		var goal:Vector3=park[-1]
		if Vector2(g.car.node.global_position.x,g.car.node.global_position.z).distance_to(Vector2(goal.x,goal.z))>1:return
		if not service.get("full",true):
			var driver:Walker=g.golfers[0]
			var door:=_by_car(g,0)
			driver.node.global_position=Vector3(door.x,_surface_y(door),door.y);driver.node.visible=true
			driver.data.erase("self_park_driver");_go(driver,_door_step(0))
		elif p!=null:
			if not _valet_get_out(p,g):return
			_valet_release(g)
		service["stage"]="parked"
	elif stage=="pickup_queue":
		if _valet_staff().is_empty():service["used"]=false;service["stage"]="parked";_to_parking(g);return
		if _valet_curb_busy(g):return
		for worker:Walker in _valet_staff():
			if worker.data.has("valet_group"):return
		p=_valet_free()
		if p==null:return
		service["worker"]=p;p.data["valet_group"]=g
		service["stage"]="fetch";_go(p,_valet_car_door(g))
	elif stage=="fetch" and p!=null and _valet_at(p,_valet_car_door(g)):
		var end:Vector3=g.exit_path[-1]
		var curb:Vector2=service["curb"]
		var route:Array=g.exit_path.slice(1) if service.has("pocket_slot") else g.exit_path.slice(1)+_valet_drive_in(Vector2(end.x,end.z))
		_valet_drive(p,g,route,2 if service.has("pocket_slot") else 1)
		service["stage"]="retrieving"
	elif stage=="retrieving" and g.car.path.is_empty():
		var curb:Vector2=service["curb"]
		if Vector2(g.car.node.global_position.x,g.car.node.global_position.z).distance_to(curb)>1:return
		if p!=null:
			if not _valet_get_out(p,g):return
			service["load_index"]=0
			_valet_next_load(g)
		else:_valet_start_boarding(g)
	elif stage=="pickup_bag" and p!=null and _valet_at(p,service["load_from"]):
		var owner:Walker=g.golfers[int(service["load_index"])]
		_bag_up(owner)
		_drop_bag(owner)
		owner.data.erase("valet");owner.data.erase("valet_at")
		_carry_bag(p,str(owner.data.get("bag_livery","")),"valet_carry")
		service["stage"]="load_trunk";_go(p,_valet_trunk(g))
	elif stage=="load_trunk" and p!=null and _valet_at(p,_valet_trunk(g)):
		if not _valet_handle_bags(p,g,service,delta):return
		_drop_bag(p,"valet_carry")
		service["loaded_bags"]=int(service.get("loaded_bags",0))+1
		service["load_index"]=int(service["load_index"])+1
		_valet_next_load(g)
	elif stage=="boarding" and not _moving(g.golfers):
		for w:Walker in g.golfers:w.node.visible=false
		var end:Vector3=g.exit_path[-1]
		var curb:Vector2=service["curb"]
		g.car.path=_valet_drive_out()
		g.car.data["reverse"]=0
		service["stage"]="done";g.phase="leave"


## The main driveway and right/left halves of the real 12m fountain roundabout.
## A 9.3m lane center keeps full-size cars between its 6.6m island and 12m edge.
func _valet_main_drive(incoming:bool)->Array:
	var house:=_fac("clubhouse")
	if house==null:return []
	var local:Array=[]
	if incoming:local=[Vector2(1.7,-42),Vector2(1.7,-24)]
	for step in range(19):
		var angle:float=lerpf(-PI*.5,VALET_STOP_ANGLE,float(step)/18.0) if incoming else lerpf(VALET_STOP_ANGLE,PI*1.5,float(step)/18.0)
		local.append(Vector2(cos(angle)*9.3,-8.5+sin(angle)*9.3))
	if not incoming:local.append(Vector2(-1.7,-24));local.append(Vector2(-1.7,-42))
	var result:Array=[]
	for q:Vector2 in local:result.append(house.global_transform*Vector3(q.x,.1,q.y))
	return result

func _valet_drive_in(start:Vector2)->Array:
	var drive:=_valet_main_drive(true)
	if drive.is_empty():return []
	var entry:Vector3=drive[0]
	return _cart_way(start,Vector2(entry.x,entry.z))+drive.slice(1)

func _valet_drive_out()->Array:
	return _valet_main_drive(false).slice(1)


func _valet_pocket_slot()->int:
	var house:=_fac("clubhouse")
	if house==null:return -1
	var bays:Array=FacilityBuilder.rig(house).get("valet_stalls",[])
	for index in range(bays.size()):
		var used:=false
		for g:Group in _groups:
			if int(g.valet_service.get("pocket_slot",-1))==index:used=true;break
		if not used:return index
	return -1

func _valet_pocket_available()->bool:
	return business!=null and business.room_tier("valet")>=1 and _valet_pocket_slot()>=0

func _valet_pocket_path(index:int,parking:bool)->Array:
	var house:=_fac("clubhouse")
	var bays:Array=FacilityBuilder.rig(house).get("valet_stalls",[])
	if index<0 or index>=bays.size():return []
	var origin:Vector3=(bays[index] as Transform3D).origin
	var bay:=Vector2(origin.x,origin.z)
	var throat:Array=[Vector2(-9.3,-8.5),Vector2(-10,-6.7),Vector2(-11.7,-4.4),Vector2(-14,-2.5),Vector2(bay.x,-2.5)]
	var local:Array=[]
	if parking:
		for step in range(10):
			var angle:=lerpf(VALET_STOP_ANGLE,PI,float(step)/9.0)
			local.append(Vector2(cos(angle)*9.3,-8.5+sin(angle)*9.3))
		local.append_array(throat.slice(1));local.append(Vector2(bay.x,.2));local.append(bay)
	else:
		local=[bay,Vector2(bay.x,.2),Vector2(bay.x,-2.5)]
		throat.reverse();local.append_array(throat.slice(1))
		for step in range(28):
			var angle:=lerpf(PI,VALET_STOP_ANGLE+TAU,float(step)/27.0)
			local.append(Vector2(cos(angle)*9.3,-8.5+sin(angle)*9.3))
	var path:Array=[]
	for q:Vector2 in local:path.append(house.global_transform*Vector3(q.x,.1,q.y))
	return path


## Only the long nine-bag rack has a single open loading face. Bags returned
## beside a golfer or a different entrance keep their usual local approach.
func _is_rack_bag(point: Vector2) -> bool:
	var house := _fac("clubhouse")
	if house == null or business == null or business.room_tier("valet") != 3: return false
	var local := house.global_transform.affine_inverse() * Vector3(point.x, house.global_position.y, point.y)
	return absf(local.x + 4.45) < 0.35 and local.z >= 4.35 and local.z <= 9.05


## The furniture-aware guest map includes the rack rails and podium. The outdoor
## grounds map deliberately omits indoor furnishings and cannot route this leg.
func _rack_access_route(w: Walker, target: Vector2) -> bool:
	if w.data.get("vehicle", false): return false
	var house := _fac("clubhouse")
	if house == null: return false
	var side := house.global_basis.x.normalized() * 0.95
	if not _is_rack_bag(target - Vector2(side.x, side.z)): return false
	var inv := house.global_transform.affine_inverse()
	var here := inv * w.node.global_position
	var goal := inv * Vector3(target.x, house.global_position.y, target.y)
	var nav := _guest_nav(house)
	if not (nav["rect"] as Rect2).has_point(Vector2(here.x, here.z)): return false
	_go_inside(w, house, "guest", Vector2(goal.x, goal.z), 0.0)
	w.ground = true
	w.path = _round_vehicles(w.node.global_position, w.path)
	return true


func _valet_rack_approach(drop:Vector2)->Vector2:
	var offset:=_fac("clubhouse").global_basis*Vector3(.95,0,0)
	return drop+Vector2(offset.x,offset.z)

## Golfers retain their visible carried bag throughout the walk and put it down only at the rack.
func _rack_delivery_step(w:Walker,delta:float)->bool:
	var delivery:Dictionary=w.data.get("rack_delivery",{})
	if delivery.is_empty():return false
	if not w.path.is_empty() or w.data.get("blocked",false):return false
	var drop:Vector2=delivery["drop"]
	var approach:=_valet_rack_approach(drop)
	var here:=Vector2(w.node.global_position.x,w.node.global_position.z)
	if here.distance_to(approach)>.65:
		_go(w,approach);return false
	var placing:float=delivery["placing"]
	if is_equal_approx(placing,-1.0):
		delivery["placing"]=.8
		w.node.rotation.y=atan2(here.x-drop.x,here.y-drop.y)
		_play(w,"work")
		return true
	delivery["placing"]=placing-delta
	if placing>0:return true
	var house:=_fac("clubhouse")
	_bag_down_at(w,Vector3(drop.x,_surface_y(drop),drop.y),house.global_rotation.y+PI*.5)
	if w.data.has("bag_down"):w.data["valet"]=true
	var resume:Array=delivery["resume"]
	var bridge:Array=[]
	if not resume.is_empty():
		var inv:=house.global_transform.affine_inverse()
		var start:Vector3=inv*w.node.global_position
		var end:Vector3=inv*(resume[0] as Vector3)
		var local_path:=FacilityBuilder.nav_route(house,"guest",Vector2(start.x,start.z),Vector2(end.x,end.z))
		for point:Vector2 in local_path:bridge.append(house.global_transform*Vector3(point.x,0,point.y))
		if bridge.is_empty():
			_go(w,Vector2((resume[0] as Vector3).x,(resume[0] as Vector3).z));bridge=w.path.duplicate()
	w.data.erase("rack_delivery")
	w.ground=delivery["ground"];w.rest=delivery["rest"]
	for key in ["walk_region","outdoor_target","indoor_target","watch","hold"]:
		if delivery.has(key):w.data[key]=delivery[key]
		else:w.data.erase(key)
	w.data["blocked"]=false
	w.path=bridge+resume.slice(1) if not resume.is_empty() else []
	_play(w,"walk" if not w.path.is_empty() else w.rest)
	return true

## Keep practice feet on the visible turf even while waiting or after a sideways avoidance step.
## This adjusts the actor placement, leaving captured poses, club fitting and animation tracks intact.
func _ground_practice(w:Walker)->void:
	if not w.data.has("practice") or w.riding or w.data.get("seated",false):return
	var at:=w.node.global_position
	at.y=_surface_y(Vector2(at.x,at.z))
	w.node.global_position=at
	var sk:=w.node.find_child("Skeleton3D",true,false) as Skeleton3D
	if sk==null:return
	var depths:Dictionary=w.data.get("practice_soles",{})
	var lift:=0.0
	for name in ["foot.L","foot.R"]:
		var bone:=sk.find_bone(name)
		if bone<0:continue
		if not depths.has(name):
			var rest:=w.node.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_rest(bone)
			depths[name]=clampf(rest.origin.y,.025,.15)
		var foot:Vector3=(sk.global_transform*sk.get_bone_global_pose(bone)).origin
		lift=maxf(lift,_surface_y(Vector2(foot.x,foot.z))+float(depths[name])-foot.y)
	w.data["practice_soles"]=depths
	w.node.global_position.y+=lift

func _valet_handle_bags(p:Walker,g:Group,service:Dictionary,delta:float)->bool:
	var center:=_vehicle_frame(g.car).origin
	p.data["watch"]=Vector2(center.x,center.z)
	_play(p,"work")
	service["handling"]=float(service.get("handling",0.0))+delta
	if float(service["handling"])<.8:return false
	service.erase("handling")
	return true

func _valet_next_load(g:Group)->void:
	var service:=g.valet_service
	var p:Walker=service.get("worker")
	var index:int=service.get("load_index",0)
	while index<g.golfers.size():
		var owner:Walker=g.golfers[index]
		var stand:Node3D=owner.data.get("bag_down")
		var bag:Node3D=owner.data.get("bag")
		if is_instance_valid(stand) or (is_instance_valid(bag) and bag.visible):
			var at:Vector3=stand.global_position if is_instance_valid(stand) else owner.node.global_position
			var point := Vector2(at.x, at.z)
			var side := _fac("clubhouse").global_basis.x.normalized() * 0.7
			var pickup := _valet_rack_approach(point) if _is_rack_bag(point) else point + Vector2(side.x, side.z)
			service["load_index"]=index;service["load_from"]=pickup
			service["stage"]="pickup_bag";_go(p,pickup)
			return
		index+=1
	_valet_release(g)
	_valet_start_boarding(g)

func _valet_start_boarding(g:Group)->void:
	for k in range(g.golfers.size()):_go(g.golfers[k],_by_car(g,k))
	g.valet_service["stage"]="boarding";g.phase="valet_board"
