class_name CourseBusiness
extends RefCounted
## The golf course the player owns (the manager mode): which Course Studio course it runs on,
## the facilities built on it and their levels, the staff, the green fee, turf condition and
## the books. Pure data + rules, no nodes: GameState owns one, saves it, runs advance() on a
## real-time clock and moves the money in and out of the shared wallet.
##
## Course Manager mode runs all of it, separate from Course Studio (which only builds the
## course). Facilities are *placed* on the club's course (`placements`, one per type) and
## *built* (`built`: type -> level). One works only when it is both, and -- when its config
## names a `staff` role -- at least one of that role is on the payroll. Nothing opens without a
## working clubhouse. Rooms (pro shop, restaurant, ...) are fitted out inside the clubhouse
## (`rooms`: id -> tier) once it reaches the room's level. Money is per business hour; every
## tunable is in economy.json "manager".

const OPENING_HOUR := 7  # the day's first tee time, for the clock readout

var owned := false
var traffic_mode := "normal"
var accepting_visitors := false
var course_path := ""
var course_name := ""
## Read from the course file by refresh_course().
var holes := 0
## Where each facility stands on the club's course: id -> {"pos": Vector2 world XZ, "rot": yaw}.
var placements := {}
var course_sites := {}  # Course path -> independent saved business progress.
var auto_parked := false  # the deed's parking lot has been set down beside the clubhouse once
var built := {}  # facility id -> level (1..levels) on the selected course
var rooms := {}  # clubhouse room id -> tier (1..3)
var staff := {}  # role id -> head count
var green_fee := 0
var condition := 0.0  # 0..1 turf condition; drifts toward what the greenskeepers keep up with
var next_tee_hour := 0.0  # next first-tee start, in the same clock as hours
var hours := 0.0  # business hours run since the deed was bought
var today := {}  # {"visitors", "revenue", "costs"} for the business day in progress
var days: Array = []  # finished days, newest last: {"day", "visitors", "revenue", "costs"}
var lifetime := {}  # {"visitors", "revenue", "costs"}


static func create() -> CourseBusiness:
	var b := CourseBusiness.new()
	var cfg := EconomyConfig.manager_cfg()
	b.owned = true
	b.green_fee = int(cfg.get("green_fee", {}).get("default", 3))
	b.condition = float(cfg.get("start_condition", 0.6))
	return b


func _init() -> void:
	today = _empty_books()
	lifetime = _empty_books()


static func _empty_books() -> Dictionary:
	return {"visitors": 0.0, "revenue": 0.0, "costs": 0.0}


func to_dict() -> Dictionary:
	var current := _current_site_dict()
	var sites := course_sites.duplicate(true)
	if course_path != "":
		sites[course_path] = current.duplicate(true)
	current["course_sites"] = sites
	return current


## A snapshot contains no other courses, so saves never nest previous snapshots.
func _current_site_dict() -> Dictionary:
	var places := {}
	for id in placements:
		var p: Dictionary = placements[id]
		places[id] = [snappedf(p["pos"].x, 0.01), snappedf(p["pos"].y, 0.01), snappedf(float(p["rot"]), 0.0001)]
	return {"owned": owned, "traffic_mode": traffic_mode, "accepting_visitors": accepting_visitors, "course_path": course_path, "course_name": course_name,
		"placements": places, "auto_parked": auto_parked, "built": built.duplicate(), "rooms": rooms.duplicate(), "staff": staff.duplicate(), "green_fee": green_fee,
		"condition": condition, "hours": hours, "next_tee_hour": next_tee_hour, "today": today.duplicate(),
		"days": days.duplicate(true), "lifetime": lifetime.duplicate()}


static func from_dict(d: Dictionary) -> CourseBusiness:
	var b := CourseBusiness.new()
	if d.is_empty():
		return b
	b.owned = bool(d.get("owned", false))
	b.accepting_visitors = bool(d.get("accepting_visitors", true))
	b.traffic_mode = str(d.get("traffic_mode", "normal"))
	if b.traffic_mode not in ["normal", "quiet", "rush", "daily"]: b.traffic_mode = "normal"
	b.course_path = str(d.get("course_path", ""))
	b.course_name = str(d.get("course_name", ""))
	b.auto_parked = bool(d.get("auto_parked", false))
	b.course_sites = (d.get("course_sites", {}) as Dictionary).duplicate(true)
	for k in d.get("placements", {}):
		var v: Array = d["placements"][k]
		if not EconomyConfig.facility(str(k)).is_empty() and v.size() >= 3:
			b.placements[str(k)] = {"pos": Vector2(float(v[0]), float(v[1])), "rot": float(v[2])}
	for k in d.get("built", {}):
		if not EconomyConfig.facility(str(k)).is_empty():
			b.built[str(k)] = clampi(int(d["built"][k]), 1, b.max_level(str(k)))
		elif not EconomyConfig.room(str(k)).is_empty():
			# saves from before rooms: the pro shop and restaurant were their own buildings
			b.rooms[str(k)] = clampi(int(d["built"][k]), 1, b.room_max(str(k)))
	for k in d.get("rooms", {}):
		if not EconomyConfig.room(str(k)).is_empty():
			b.rooms[str(k)] = clampi(int(d["rooms"][k]), 1, b.room_max(str(k)))
	for k in d.get("staff", {}):
		if not EconomyConfig.staff_role(str(k)).is_empty():
			b.staff[str(k)] = clampi(int(d["staff"][k]), 0, 2) if str(k) == "valet" else maxi(int(d["staff"][k]), 0)
	b.green_fee = int(d.get("green_fee", 3))
	b.condition = clampf(float(d.get("condition", 0.6)), 0.0, 1.0)
	b.hours = maxf(float(d.get("hours", 0.0)), 0.0)
	b.next_tee_hour = maxf(float(d.get("next_tee_hour", 0.0)), 0.0)
	for k in ["today", "lifetime"]:
		var books := _empty_books()
		var src: Dictionary = d.get(k, {})
		for f in books:
			books[f] = float(src.get(f, 0.0))
		b.set(k, books)
	b.days = (d.get("days", []) as Array).duplicate(true)
	b.refresh_course()
	return b


## Save the outgoing club and restore the selected course's own upgrades and crew.
func select_course(path: String) -> void:
	if path == course_path:
		refresh_course()
		return
	if course_path == "":
		# The first map receives any purchases made before choosing a course.
		course_path = path
		refresh_course()
		return
	var outgoing := _current_site_dict()
	course_sites[course_path] = outgoing
	var site: Dictionary = course_sites.get(path, {})
	var restored: CourseBusiness
	if site.is_empty():
		restored = CourseBusiness.create()
	else:
		if not site.has("built"):
			# Early multi-map saves only stored layouts and shared one set of
			# purchases. Preserve that progress when migrating those layouts.
			var migrated := outgoing.duplicate(true)
			migrated["placements"] = site.get("placements", {}).duplicate(true)
			migrated["auto_parked"] = site.get("auto_parked", false)
			site = migrated
		restored = CourseBusiness.from_dict(site)
	for key in restored._current_site_dict():
		set(key, restored.get(key))
	course_path = path
	course_name = ""
	refresh_course()


# ---------------------------------------------------------------- the course it runs on

## Re-read the course's name and hole count from its file (cheap: no layer decoding).
func refresh_course() -> void:
	holes = 0
	if course_path == "" or not FileAccess.file_exists(course_path):
		return
	var info := PaintedCourse.peek(course_path)
	if info.is_empty():
		return
	course_name = str(info.get("name", course_name))
	holes = int(info.get("holes", 0))


## Stand facility `id` at `pos` turned by `rot` (Course Manager checks the site first).
func place(id: String, pos: Vector2, rot: float) -> void:
	placements[id] = {"pos": pos, "rot": rot}


func unplace(id: String) -> void:
	placements.erase(id)


func has_course() -> bool:
	return course_path != "" and FileAccess.file_exists(course_path)


# ---------------------------------------------------------------- facilities & staff

func level(id: String) -> int:
	return int(built.get(id, EconomyConfig.facility(id).get("default_level", 0)))


## Golfers the parking can take an hour: the lot's spaces (or the roadside, without a lot) at
## golfers_per_space_hour each. Until Course Manager has set the deed's lot down it counts as
## placed, so a club doesn't lose golfers before you've seen it.
func parking_cap() -> float:
	var cfg := EconomyConfig.manager_cfg()
	var spaces := float(cfg.get("street_spaces", 8))
	if working("parking_lot") or (not auto_parked and not placements.has("parking_lot")):
		spaces = float(_level_cfg("parking_lot").get("spaces", 0))
	if room_tier("valet")==3 and room_working("valet"):spaces+=6.0
	return spaces * float(cfg.get("golfers_per_space_hour", 0.35))


func max_level(id: String) -> int:
	return maxi((EconomyConfig.facility(id).get("levels", []) as Array).size(), 1)


func _level_cfg(id: String) -> Dictionary:
	var lv := level(id)
	var levels: Array = EconomyConfig.facility(id).get("levels", [])
	return levels[lv - 1] if lv >= 1 and lv <= levels.size() else {}


func heads(role: String) -> int:
	return int(staff.get(role, 0))


## The name of facility `id`'s level `lv` ("Grand"), or "" past its levels.
func level_name(id: String, lv: int) -> String:
	var levels: Array = EconomyConfig.facility(id).get("levels", [])
	return str(levels[lv - 1].get("name", "Level %d" % lv)) if lv >= 1 and lv <= levels.size() else ""


## What building (or upgrading) `id` costs next; -1 once it's at its top level.
func next_cost(id: String) -> int:
	var levels: Array = EconomyConfig.facility(id).get("levels", [])
	var lv := level(id)
	return int(levels[lv].get("cost", 0)) if lv < levels.size() else -1


## Why `id` isn't earning ("" when it is): not placed, not built, or nobody to run it.
func facility_note(id: String) -> String:
	if not placements.has(id):
		return "Not placed on your course yet"
	if level(id) == 0:
		return "Planned: not built yet"
	return _staff_note(EconomyConfig.facility(id))


func working(id: String) -> bool:
	return facility_note(id) == ""


func _staff_note(cfg: Dictionary) -> String:
	var role := str(cfg.get("staff", ""))
	if role != "" and heads(role) == 0:
		return "Needs a %s" % str(EconomyConfig.staff_role(role).get("name", role)).to_lower()
	return ""


## How much a facility or room does with the people on it: 1.0 for its one required hand,
## plus each extra required hand's and each optional crew member's `bonus_each`.
func crew_mult(cfg: Dictionary) -> float:
	var m := 1.0
	var req := str(cfg.get("staff", ""))
	if req != "":
		m += maxi(heads(req) - 1, 0) * float(EconomyConfig.staff_role(req).get("bonus_each", 0.0))
	var crew: Variant = cfg.get("crew", [])
	for c in (crew if crew is Array else [crew]):
		if str(c) != "":
			m += heads(str(c)) * float(EconomyConfig.staff_role(str(c)).get("bonus_each", 0.0))
	return m


# ---------------------------------------------------------------- clubhouse rooms

func room_tier(id: String) -> int:
	return int(rooms.get(id, 0))


func room_max(id: String) -> int:
	return maxi((EconomyConfig.room(id).get("tiers", []) as Array).size(), 1)


func _tier_cfg(id: String) -> Dictionary:
	var t := room_tier(id)
	var tiers: Array = EconomyConfig.room(id).get("tiers", [])
	return tiers[t - 1] if t >= 1 and t <= tiers.size() else {}


## The name of room `id` at tier `t` ("Boutique Pro Shop"), or "" past its tiers.
func tier_name(id: String, t: int) -> String:
	var tiers: Array = EconomyConfig.room(id).get("tiers", [])
	return str(tiers[t - 1].get("name", "Tier %d" % t)) if t >= 1 and t <= tiers.size() else ""


## Whether the clubhouse is big enough for room `id` (it opens at its `min_level`).
func room_open(id: String) -> bool:
	return level("clubhouse") >= int(EconomyConfig.room(id).get("min_level", 1))


## What fitting out (or upgrading) room `id` costs next; -1 once it's at its top tier.
func room_next_cost(id: String) -> int:
	var tiers: Array = EconomyConfig.room(id).get("tiers", [])
	var t := room_tier(id)
	return int(tiers[t].get("cost", 0)) if t < tiers.size() else -1


## Why room `id` isn't earning ("" when it is).
func room_note(id: String) -> String:
	var cfg := EconomyConfig.room(id)
	if not room_open(id):
		return "Opens with the %s clubhouse" % level_name("clubhouse", int(cfg.get("min_level", 1)))
	if not placements.has("clubhouse"):
		return "The clubhouse isn't on your course"
	if room_tier(id) == 0:
		return "Not fitted out yet"
	return _staff_note(cfg)


func room_working(id: String) -> bool:
	return room_note(id) == ""


func can_build_room(id: String) -> String:
	if EconomyConfig.room(id).is_empty():
		return "Unknown room."
	if not room_open(id):
		return room_note(id) + "."
	if room_next_cost(id) < 0:
		return "Already at the top tier."
	return ""


## Where a role works, for the staff list ("" for the course; else the facility or room id).
func workplace(role: String) -> String:
	var w := str(EconomyConfig.staff_role(role).get("works", "course"))
	return "" if w == "course" else w.trim_prefix("room:")


## Why nobody in `role` has anywhere to work yet ("" when they do).
func workplace_note(role: String) -> String:
	var w := str(EconomyConfig.staff_role(role).get("works", "course"))
	if w == "course":
		return ""
	if w.begins_with("room:"):
		var rid := w.trim_prefix("room:")
		return "" if room_tier(rid) > 0 and room_open(rid) else "No %s to work in yet" % str(EconomyConfig.room(rid).get("name", rid)).to_lower()
	return "" if level(w) > 0 and placements.has(w) else "No %s to work in yet" % str(EconomyConfig.facility(w).get("name", w)).to_lower()


## Why the gates are shut ("" when open).
func closed_reason() -> String:
	var why := opening_problem()
	if why != "":
		return why
	return "Closed to new arrivals — click CLOSED to open" if not accepting_visitors else ""


func opening_problem() -> String:
	if not owned:
		return "You don't own a course yet"
	if not has_course():
		return "Choose which of your courses to run"
	var min_holes := int(EconomyConfig.manager_cfg().get("min_holes", 3))
	if holes < min_holes:
		return "Your course needs at least %d holes" % min_holes
	if not working("clubhouse"):
		var note := facility_note("clubhouse")
		return "Place and build a clubhouse" if note.begins_with("Not placed") or note.begins_with("Planned") else note
	return ""


# ---------------------------------------------------------------- the money model

## The hourly picture right now: demand, takings per facility and room, running costs. Costs
## run whether or not the gates are open (staff are paid, placed buildings kept up).
func rates() -> Dictionary:
	var cfg := EconomyConfig.manager_cfg()
	var r := {"open": false, "reason": closed_reason(), "capacity": 0.0, "course_capacity": 0.0, "parking_cap": 0.0, "appeal": 0.0,
		"fair_fee": 0.0, "price_factor": 0.0, "golfers": 0.0, "range_golfers": 0.0, "practice_golfers": 0.0, "stars": 1.0,
		"fees": 0.0, "shop": 0.0, "restaurant": 0.0, "range": 0.0, "practice": 0.0, "carts": 0.0,
		"events": 0.0, "members": 0.0, "lessons": 0.0,
		"revenue": 0.0, "upkeep": 0.0, "wages": 0.0, "costs": 0.0, "net": 0.0}
	if not owned:
		return r
	for f in cfg.get("facilities", []):
		var id := str(f["id"])
		if level(id) > 0 and placements.has(id):
			r["upkeep"] += float(_level_cfg(id).get("upkeep", 0.0))
	for rm in cfg.get("rooms", []):
		var id := str(rm["id"])
		if room_tier(id) > 0 and room_open(id) and placements.has("clubhouse"):
			r["upkeep"] += float(_tier_cfg(id).get("upkeep", 0.0))
	for s in cfg.get("staff", []):
		r["wages"] += heads(str(s["id"])) * float(s.get("wage", 0.0))
	r["costs"] = r["upkeep"] + r["wages"]
	# Appeal and the fair price come from the turf and every working facility and room.
	var appeal := float(cfg.get("base_appeal", 0.25)) + condition * float(cfg.get("condition_appeal", 0.35))
	var fee_cfg: Dictionary = cfg.get("green_fee", {})
	var fair := float(fee_cfg.get("fair_base", 3)) * (0.6 + 0.8 * condition)
	var extra_capacity := 0.0
	for f in cfg.get("facilities", []):
		var id := str(f["id"])
		if working(id):
			appeal += float(_level_cfg(id).get("appeal", 0.0))
			fair += float(_level_cfg(id).get("fair_fee", 0.0))
	for rm in cfg.get("rooms", []):
		var id := str(rm["id"])
		if room_working(id):
			var tc := _tier_cfg(id)
			var m := crew_mult(rm)
			appeal += float(tc.get("appeal", 0.0)) * m
			fair += float(tc.get("fair_fee", 0.0)) * m
			extra_capacity += float(tc.get("capacity", 0.0))
	r["appeal"] = appeal
	r["fair_fee"] = fair
	r["stars"] = clampf(1.0 + 4.0 * (appeal - 0.25) / 0.95, 1.0, 5.0)
	if r["reason"] != "":
		r["net"] = -r["costs"]
		return r
	r["open"] = true
	var marshal := EconomyConfig.staff_role("marshal")
	var capacity := holes * float(cfg.get("golfers_per_hole_per_hour", 0.35)) * (1.0 + heads("marshal") * float(marshal.get("capacity_each", 0.1)) + extra_capacity)
	r["course_capacity"] = capacity
	r["parking_cap"] = parking_cap()
	capacity = minf(capacity, r["parking_cap"])  # no space to park, no round
	var price_factor := clampf(1.5 - 0.5 * green_fee / maxf(fair, 0.01), 0.05, 1.3)
	var golfers := minf(capacity, capacity * minf(appeal, 1.0) * price_factor * traffic_multiplier())
	var pull := minf(appeal, 1.0)
	r["capacity"] = capacity
	r["price_factor"] = price_factor
	r["golfers"] = golfers
	r["fees"] = golfers * green_fee
	if room_working("pro_shop"):
		r["shop"] = golfers * float(_tier_cfg("pro_shop").get("spend", 0.0)) * crew_mult(EconomyConfig.room("pro_shop"))
	if room_working("restaurant"):
		r["restaurant"] = golfers * float(_tier_cfg("restaurant").get("spend", 0.0)) * crew_mult(EconomyConfig.room("restaurant"))
	if room_working("ballroom"):
		r["events"] = float(_tier_cfg("ballroom").get("events", 0.0)) * pull * crew_mult(EconomyConfig.room("ballroom"))
	if room_working("spa_fitness"):
		r["members"] = float(_tier_cfg("spa_fitness").get("members", 0.0)) * pull * crew_mult(EconomyConfig.room("spa_fitness"))
	if room_working("simulator"):
		r["lessons"] = float(_tier_cfg("simulator").get("lessons", 0.0)) * pull * crew_mult(EconomyConfig.room("simulator"))
	if working("driving_range"):
		var rc := _level_cfg("driving_range")
		var range_golfers := float(rc.get("range_golfers", 0.0)) * pull * crew_mult(EconomyConfig.facility("driving_range"))
		r["range_golfers"] = range_golfers
		r["range"] = range_golfers * float(rc.get("bucket", 0.0))
	if working("short_game"):
		var sc := _level_cfg("short_game")
		var practice_golfers := float(sc.get("practice_golfers", 0.0)) * pull * crew_mult(EconomyConfig.facility("short_game"))
		r["practice_golfers"] = practice_golfers
		r["practice"] = practice_golfers * float(sc.get("practice_fee", 0.0))
	if working("cart_barn"):
		var cc := _level_cfg("cart_barn")
		var share := minf(float(cc.get("cart_share", 0.0)) * crew_mult(EconomyConfig.facility("cart_barn")), 0.9)
		r["cart_share"] = share
		r["carts"] = golfers * share * float(cc.get("cart_fee", 0.0))
	r["revenue"] = r["fees"] + r["shop"] + r["restaurant"] + r["range"] + r["practice"] + r["carts"] + r["events"] + r["members"] + r["lessons"]
	r["net"] = r["revenue"] - r["costs"]
	return r


## Where the greenskeepers can hold the turf: each keeps `holes_each` holes in shape.
func condition_target() -> float:
	if holes <= 0:
		return 0.0
	var gk := EconomyConfig.staff_role("greenskeeper")
	return clampf(heads("greenskeeper") * float(gk.get("holes_each", 4)) / float(holes), 0.0, 1.0)


## Run the business for `h` hours. Condition drifts and the books fill in an hour at most at a
## time, so a long stretch (time away) still closes each business day into `days`. `rate`
## scales the takings and costs (time away earns a share). Returns the net money made.
func advance(h: float, rate: float = 1.0) -> float:
	if not owned or h <= 0.0:
		return 0.0
	var cfg := EconomyConfig.manager_cfg()
	var day_len := maxf(float(cfg.get("open_hours_per_day", 12)), 1.0)
	var drift := float(cfg.get("condition_rate", 0.12))
	var net := 0.0
	var left := h
	while left > 1e-9:
		var into_day := fmod(hours, day_len)
		var step := minf(minf(left, 1.0), day_len - into_day)
		if step <= 1e-9:
			step = minf(left, 1.0)
		condition = lerpf(condition, condition_target(), 1.0 - exp(-drift * step))
		var r := rates()
		var visitors: float = (r["golfers"] + r["range_golfers"] + r["practice_golfers"]) * step * rate
		for books in [today, lifetime]:
			books["visitors"] += visitors
			books["revenue"] += r["revenue"] * step * rate
			books["costs"] += r["costs"] * step * rate
		net += r["net"] * step * rate
		var day_before := int(floor(hours / day_len))
		hours += step
		left -= step
		if int(floor((hours + 1e-6) / day_len)) > day_before:
			_close_day(day_before + 1)
	return net


func _close_day(day: int) -> void:
	var entry := today.duplicate()
	entry["day"] = day
	days.append(entry)
	var keep := int(EconomyConfig.manager_cfg().get("days_kept", 7))
	while days.size() > keep:
		days.pop_front()
	today = _empty_books()


## The club's time of day (hours, 0..24): business days are `open_hours_per_day` long from
## OPENING_HOUR.
## Demand changes arrivals and hourly revenue together; staffing costs remain payable.
func traffic_multiplier() -> float:
	match traffic_mode:
		"quiet": return 0.2
		"rush": return 2.5
		"daily":
			var hour := time_of_day()
			if hour < 9.0: return 1.8
			if hour < 11.0: return 1.0
			if hour < 14.0: return 0.35
			if hour < 17.0: return 1.6
			return 0.25
	return 1.0


func time_of_day() -> float:
	var day_len := maxf(float(EconomyConfig.manager_cfg().get("open_hours_per_day", 12)), 1.0)
	return fmod(OPENING_HOUR + fmod(hours, day_len), 24.0)


## "Day 3 · 2:15 PM" (time_of_day).
func clock_text() -> String:
	var day_len := maxf(float(EconomyConfig.manager_cfg().get("open_hours_per_day", 12)), 1.0)
	var day := int(floor(hours / day_len)) + 1
	var t := time_of_day()
	var hh := int(t) % 24
	var mm := int((t - floor(t)) * 60.0)
	return "Day %d · %d:%02d %s" % [day, 12 if hh % 12 == 0 else hh % 12, mm, "AM" if hh < 12 else "PM"]


# ---------------------------------------------------------------- edits (GameState pays)

func can_build(id: String) -> String:
	if EconomyConfig.facility(id).is_empty():
		return "Unknown facility."
	if next_cost(id) < 0:
		return "Already at the top level."
	if level(id) == 0 and not placements.has(id):
		return "Place it on your course first."
	return ""


func can_hire(role: String) -> String:
	var r := EconomyConfig.staff_role(role)
	if r.is_empty():
		return "Unknown role."
	if heads(role) >= int(r.get("max", 3)):
		return "That's as many as you can use."
	return ""


func clamp_fee(v: int) -> int:
	var fc: Dictionary = EconomyConfig.manager_cfg().get("green_fee", {})
	return clampi(v, int(fc.get("min", 1)), int(fc.get("max", 25)))
