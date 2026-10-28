class_name GameState
extends Node
## Everything persistent about the player: cash, every owned club instance, the equipped bag,
## store inventories, purchase history, unlocked locations, collection records and round
## results. Registered as the `GolfState` autoload (project.godot); code reaches it through
## GameState.current so headless tests can build their own instance with a private save path.
##
## Rules enforced here (not in the UI):
##  - store stock only rerolls in complete_round() after a completed standard round; opening
##    menus, restarting, reloading or abandoning a round never touches it;
##  - a round's rewards are applied once per round_id (processed_round_ids), so a reload or a
##    duplicate signal can't pay twice;
##  - loaner clubs can't be sold, so a playable bag always exists;
##  - sandbox (illegal) gear lives in sandbox_clubs, never in clubs, shops, resale or collections.

signal changed
signal bag_changed
signal location_unlocked(store_id: String)
signal model_discovered(model_id: String)
## The owned course ran another real-time tick (cash may have moved). Separate from `changed`
## so the Clubhouse doesn't rebuild every couple of seconds.
signal business_ticked

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://openfairway_save.json"
const HISTORY_LIMIT := 30

static var current: GameState

var save_path := DEFAULT_SAVE_PATH
var autosave := true

var cash: int = 0
## Testing switch (admin, the Clubhouse's admin tab or Course Manager's wallet): the wallet never
## runs out. The real balance is set aside -- saves keep it -- and comes back when it's switched
## off; whatever was bought meanwhile is kept.
var unlimited_money := false
var _real_cash := 0
const TEST_MONEY := 99999999
var clubs: Dictionary = {}  # instance id -> ClubInstance
var bag: Dictionary = {}  # bag key ("DR", "IRONS", "PT", ...) -> instance id
var stores: Dictionary = {}  # store id -> {"listings": Array}
var purchases: Array = []  # {instance_id, model_id, store_id, price, round}
var sales: Array = []  # {instance_id, model_id, price, round}
var unlocked: Array = []  # store ids
var discovered: Dictionary = {}  # model id -> {round, store, price, condition, instance_id}
var qualified_rounds: Dictionary = {}  # store id -> true once a qualifying round is played
var best_attempts: Dictionary = {}  # store id -> best rel-par among eligible rounds
var rounds_completed: int = 0
var sandbox_rounds: int = 0
var round_history: Array = []  # summaries, newest last
var best_round: Dictionary = {}  # {rel_par, total, round_no}
var processed_round_ids: Array = []
var stock_generation: int = 0
var loot_seed: int = 0
var next_instance_no: int = 1
var sandbox_clubs: Dictionary = {}  # instance id -> ClubInstance (admin grants only)
var completion_reward_earned := false
var completion_reward_round := -1
## The golf course the player owns (manager mode). Not owned until the deed is bought.
var business := CourseBusiness.new()
## What the course made while the game was closed, set on load: {"seconds", "net"} or {}.
var offline_report: Dictionary = {}
## Set by course.gd while a round has strokes on the card; bag edits and sales wait.
var round_in_progress := false
var loaded_from_disk := false

var _bag_cache: Array = []
var _bag_dirty := true
var _bag_cache_admin := false
var manager_simulation_active := false
var _manager_seconds := 0.0
var _biz_last_ms := 0
var _biz_save_ms := 0
var _biz_frac := 0.0  # cents the business made that haven't added up to a whole dollar yet


func _init() -> void:
	current = self


func _ready() -> void:
	# The course earns in real time, through pauses and menus alike.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Tools/screenshots point this at a throwaway file so they never share the player's save.
	if OS.get_environment("GOLF_SAVE_PATH") != "":
		save_path = OS.get_environment("GOLF_SAVE_PATH")
	if clubs.is_empty():
		load_or_new()


## The owned course's real-time clock. Wall-clock time, not frame delta, so the in-round
## fast-forward (Engine.time_scale) never speeds up the business.
func _process(_delta: float) -> void:
	if unlimited_money and cash != TEST_MONEY:
		cash = TEST_MONEY  # spent or earned, the test wallet stays full
	if not business.owned:
		_biz_last_ms = 0
		return
	var now := Time.get_ticks_msec()
	if manager_simulation_active:
		_biz_last_ms = now
		if now - _biz_save_ms >= 60000:
			_biz_save_ms = now
			save()
		return
	if _biz_last_ms == 0:
		_biz_last_ms = now
		_biz_save_ms = now
		return
	var cfg := EconomyConfig.manager_cfg()
	if now - _biz_last_ms < int(float(cfg.get("tick_seconds", 2.0)) * 1000.0):
		return
	# A long gap (the machine slept, a debugger break) counts as time away, not full time.
	var secs := (now - _biz_last_ms) / 1000.0
	_biz_last_ms = now
	if secs > 600.0:
		_run_business(600.0, 1.0)
		_run_business(minf(secs - 600.0, _offline_cap_seconds()), _offline_rate())
	else:
		_run_business(secs, 1.0)
	business_ticked.emit()
	if now - _biz_save_ms >= int(float(cfg.get("save_every_seconds", 60)) * 1000.0):
		_biz_save_ms = now
		save()


## Manager advances the books by the same bounded time as people and vehicles.
## Outside the manager, the existing wall-clock and offline rules still apply.
func begin_manager_simulation() -> void:
	manager_simulation_active = true
	_manager_seconds = 0.0
	_biz_last_ms = Time.get_ticks_msec()
	_biz_save_ms = _biz_last_ms


func advance_manager_simulation(seconds: float) -> void:
	if not manager_simulation_active or not business.owned: return
	seconds = maxf(seconds, 0.0)
	if seconds <= 0.0: return
	_run_business(seconds, 1.0)
	_manager_seconds += seconds
	if _manager_seconds >= 2.0:
		_manager_seconds = fmod(_manager_seconds, 2.0)
		business_ticked.emit()


func end_manager_simulation() -> void:
	if not manager_simulation_active: return
	_manager_seconds = 0.0
	manager_simulation_active = false
	_biz_last_ms = Time.get_ticks_msec()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and business.owned:
		end_manager_simulation()
		save()  # don't lose the last minute of takings on quit


# ---------------------------------------------------------------- lifecycle / persistence

func load_or_new() -> void:
	if not load_game():
		new_game()


func new_game() -> void:
	cash = EconomyConfig.starting_cash()
	unlimited_money = false
	clubs = {}
	bag = {}
	stores = {}
	purchases = []
	sales = []
	unlocked = []
	discovered = {}
	qualified_rounds = {}
	best_attempts = {}
	rounds_completed = 0
	sandbox_rounds = 0
	round_history = []
	best_round = {}
	processed_round_ids = []
	stock_generation = 0
	loot_seed = randi()
	next_instance_no = 1
	sandbox_clubs = {}
	completion_reward_earned = false
	completion_reward_round = -1
	business = CourseBusiness.new()
	offline_report = {}
	_biz_frac = 0.0
	round_in_progress = false
	loaded_from_disk = false
	_ensure_starters()
	for s in EconomyConfig.stores():
		if s.get("unlock") == null:
			unlocked.append(str(s["id"]))
	_generate_all_stock(false)
	_bag_dirty = true
	save()
	changed.emit()
	bag_changed.emit()


func save() -> void:
	if not autosave:
		return
	force_save()


## Atomic: write a sibling temp file, then swap it in, so a reader (or a second copy of the
## game sharing the save) never sees a half-written file.
func force_save() -> void:
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	var target := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), target) != OK:
		push_error("GameState: cannot replace %s" % save_path)


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# Never let the fresh game that follows overwrite the only copy of a save that
		# merely failed to parse: keep it beside the save for recovery.
		var keep := save_path.get_basename() + "_unreadable_%d.json" % int(Time.get_unix_time_from_system())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(keep))
		push_warning("GameState: save file unreadable, kept a copy at %s and starting fresh" % keep)
		return false
	_apply(_migrate(parsed))
	loaded_from_disk = true
	_bag_dirty = true
	changed.emit()
	bag_changed.emit()
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func to_dict() -> Dictionary:
	var club_list: Array = []
	for id in clubs:
		club_list.append(clubs[id].to_dict())
	var sandbox_list: Array = []
	for id in sandbox_clubs:
		sandbox_list.append(sandbox_clubs[id].to_dict())
	return {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"cash": _real_cash if unlimited_money else cash,
		"unlimited_money": unlimited_money,
		"clubs": club_list,
		"bag": bag.duplicate(),
		"stores": stores.duplicate(true),
		"purchases": purchases.duplicate(true),
		"sales": sales.duplicate(true),
		"unlocked": unlocked.duplicate(),
		"discovered": discovered.duplicate(true),
		"qualified_rounds": qualified_rounds.duplicate(),
		"best_attempts": best_attempts.duplicate(),
		"rounds_completed": rounds_completed,
		"sandbox_rounds": sandbox_rounds,
		"round_history": round_history.duplicate(true),
		"best_round": best_round.duplicate(),
		"processed_round_ids": processed_round_ids.duplicate(),
		"stock_generation": stock_generation,
		"loot_seed": loot_seed,
		"next_instance_no": next_instance_no,
		"sandbox_clubs": sandbox_list,
		"completion_reward_earned": completion_reward_earned,
		"completion_reward_round": completion_reward_round,
		"business": business.to_dict(),
	}


## Fill in anything an older (or hand-edited) save lacks. Unknown versions are treated as
## version 0 and upgraded field by field; nothing the player owns is ever dropped unless its
## catalog model no longer exists.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	var defaults := {
		"cash": EconomyConfig.starting_cash(), "clubs": [], "bag": {}, "stores": {}, "purchases": [],
		"sales": [], "unlocked": [], "discovered": {}, "qualified_rounds": {}, "best_attempts": {},
		"rounds_completed": 0, "sandbox_rounds": 0, "round_history": [], "best_round": {},
		"processed_round_ids": [], "stock_generation": 0, "loot_seed": randi(), "next_instance_no": 1,
		"sandbox_clubs": [], "completion_reward_earned": false, "completion_reward_round": -1,
		"business": {},
	}
	for k in defaults:
		if not d.has(k) or d[k] == null:
			d[k] = defaults[k]
	if v < SAVE_VERSION:
		# v0 -> v1: nothing structural beyond the defaults above; bump the stamp.
		d["version"] = SAVE_VERSION
	return d


func _apply(d: Dictionary) -> void:
	cash = int(d.get("cash", 0))
	unlimited_money = bool(d.get("unlimited_money", false))
	if unlimited_money:
		_real_cash = cash
		cash = TEST_MONEY
	clubs = {}
	var max_no := 0
	for cd in d.get("clubs", []):
		var inst := ClubInstance.from_dict(cd)
		if not ClubCatalog.has_model(inst.model_id) or inst.is_illegal():
			continue  # model removed from the catalog, or sandbox gear that leaked in
		clubs[inst.id] = inst
		max_no = maxi(max_no, _instance_number(inst.id))
	sandbox_clubs = {}
	for cd in d.get("sandbox_clubs", []):
		var inst := ClubInstance.from_dict(cd)
		if ClubCatalog.has_model(inst.model_id) and inst.is_illegal():
			sandbox_clubs[inst.id] = inst
			max_no = maxi(max_no, _instance_number(inst.id))
	bag = {}
	for k in d.get("bag", {}):
		bag[str(k)] = str(d["bag"][k])
	stores = {}
	for sid in d.get("stores", {}):
		var listings: Array = []
		for l in d["stores"][sid].get("listings", []):
			if ClubCatalog.has_model(str(l.get("model_id", ""))) and not ClubCatalog.is_illegal(ClubCatalog.model(str(l["model_id"]))):
				listings.append(l)
		stores[str(sid)] = {"listings": listings}
	purchases = d.get("purchases", [])
	sales = d.get("sales", [])
	unlocked = []
	for u in d.get("unlocked", []):
		unlocked.append(str(u))
	discovered = d.get("discovered", {})
	qualified_rounds = d.get("qualified_rounds", {})
	best_attempts = d.get("best_attempts", {})
	rounds_completed = int(d.get("rounds_completed", 0))
	sandbox_rounds = int(d.get("sandbox_rounds", 0))
	round_history = d.get("round_history", [])
	best_round = d.get("best_round", {})
	processed_round_ids = d.get("processed_round_ids", [])
	stock_generation = int(d.get("stock_generation", 0))
	loot_seed = int(d.get("loot_seed", 0))
	next_instance_no = maxi(int(d.get("next_instance_no", 1)), max_no + 1)
	completion_reward_earned = bool(d.get("completion_reward_earned", false))
	completion_reward_round = int(d.get("completion_reward_round", -1))
	business = CourseBusiness.from_dict(d.get("business", {}))
	_biz_frac = 0.0
	offline_report = {}
	var away := int(Time.get_unix_time_from_system()) - int(d.get("saved_at", 0))
	if business.owned and away > 30 and int(d.get("saved_at", 0)) > 0:
		var secs := minf(float(away), _offline_cap_seconds())
		offline_report = {"seconds": away, "net": _run_business(secs, _offline_rate())}
	round_in_progress = false
	# Self-heal: loaners always exist, always-open stores are open, every configured store has
	# stock (a store added to the data after this save was written gets its first shelf now),
	# and every bag key points at something we actually own.
	_ensure_starters()
	for s in EconomyConfig.stores():
		var sid := str(s["id"])
		if s.get("unlock") == null and not unlocked.has(sid):
			unlocked.append(sid)
		if not stores.has(sid):
			stores[sid] = {"listings": _generate_store(s, stock_generation)}
	_heal_bag()
	_check_completion_reward()


static func _instance_number(id: String) -> int:
	if id.begins_with("c") and id.substr(1).is_valid_int():
		return int(id.substr(1))
	return 0


func _new_instance_id() -> String:
	var id := "c%04d" % next_instance_no
	next_instance_no += 1
	return id


func _ensure_starters() -> void:
	for m in ClubCatalog.starter_models():
		var mid := str(m["id"])
		var have := false
		for id in clubs:
			if clubs[id].model_id == mid:
				have = true
				break
		if not have:
			var inst := ClubInstance.create(_new_instance_id(), mid, 0.55, "starter", 0, rounds_completed, "Clubhouse loaner set.")
			clubs[inst.id] = inst
	_heal_bag()


## Every bag key either points at an owned club or falls back to the loaner for that slot.
func _heal_bag() -> void:
	var keys: Array = []
	for slot in ClubCatalog.bag_order():
		var key: String = "IRONS" if ClubCatalog.iron_set_slots().has(slot) else str(slot)
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		var iid := str(bag.get(key, ""))
		var ok := clubs.has(iid) or (sandbox_clubs.has(iid) and admin())
		if ok and not clubs.has(iid) and sandbox_clubs.has(iid):
			ok = true
		if not ok:
			var fb := fallback_for_key(key, "")
			if fb == "":
				bag.erase(key)
			else:
				bag[key] = fb
	_bag_dirty = true


# ---------------------------------------------------------------- clubs & bag

func admin() -> bool:
	return AdminAccess.is_admin()


func get_club(id: String) -> ClubInstance:
	if clubs.has(id):
		return clubs[id]
	if sandbox_clubs.has(id):
		return sandbox_clubs[id]
	return null


## Owned (legal) clubs, sorted: type order, then rarity descending, then name.
func owned() -> Array:
	var out: Array = []
	for id in clubs:
		out.append(clubs[id])
	out.sort_custom(func(a: ClubInstance, b: ClubInstance):
		var ta := ClubCatalog.type_order().find(a.type())
		var tb := ClubCatalog.type_order().find(b.type())
		if ta != tb:
			return ta < tb
		var ra := EconomyConfig.rarity_rank(a.rarity())
		var rb := EconomyConfig.rarity_rank(b.rarity())
		if ra != rb:
			return ra > rb
		return a.display_name() < b.display_name())
	return out


func owned_for_key(key: String) -> Array:
	var out: Array = []
	for c in owned():
		if ClubCatalog.bag_key(c.model()) == key:
			out.append(c)
	return out


func equipped_id(key: String) -> String:
	return str(bag.get(key, ""))


func is_equipped(instance_id: String) -> bool:
	return bag.values().has(instance_id)


func equipped_for_model(m: Dictionary) -> ClubInstance:
	return get_club(equipped_id(ClubCatalog.bag_key(m)))


## Loaner for a slot, or (if excluding the loaner itself) the best other owned club for it.
func fallback_for_key(key: String, exclude_id: String) -> String:
	var best_id := ""
	var best_rank := -1
	for id in clubs:
		if id == exclude_id:
			continue
		var c: ClubInstance = clubs[id]
		if ClubCatalog.bag_key(c.model()) != key:
			continue
		if c.is_starter():
			return id
		var r := EconomyConfig.rarity_rank(c.rarity())
		if r > best_rank:
			best_rank = r
			best_id = id
	return best_id


func can_edit_bag() -> Dictionary:
	if round_in_progress:
		return {"ok": false, "error": "Finish or abandon the round before changing the bag."}
	return {"ok": true, "error": ""}


func equip(instance_id: String) -> Dictionary:
	var gate := can_edit_bag()
	if not gate["ok"]:
		return gate
	var inst := get_club(instance_id)
	if inst == null:
		return {"ok": false, "error": "You don't own that club."}
	if inst.is_illegal() and not admin():
		return {"ok": false, "error": "Sandbox equipment needs admin access."}
	var key := ClubCatalog.bag_key(inst.model())
	if key == "":
		return {"ok": false, "error": "That club has no bag slot."}
	bag[key] = instance_id
	_bag_dirty = true
	save()
	bag_changed.emit()
	changed.emit()
	return {"ok": true, "error": ""}


func unequip(key: String) -> Dictionary:
	var gate := can_edit_bag()
	if not gate["ok"]:
		return gate
	var cur := equipped_id(key)
	var fb := fallback_for_key(key, cur)
	if fb == "":
		if key == "HY":
			bag.erase(key)
		else:
			return {"ok": false, "error": "Nothing else fits that slot."}
	else:
		bag[key] = fb
	_bag_dirty = true
	save()
	bag_changed.emit()
	changed.emit()
	return {"ok": true, "error": ""}


## The equipped bag as Clubs.Club objects in bag order (iron sets expanded to 4I..9I).
## Cached until the bag changes; Clubs.bag() calls this every time course.gd asks.
func bag_clubs() -> Array:
	var is_admin := admin()
	if not _bag_dirty and _bag_cache_admin == is_admin:
		return _bag_cache
	var out: Array = []
	for slot in ClubCatalog.bag_order():
		var key: String = "IRONS" if ClubCatalog.iron_set_slots().has(slot) else str(slot)
		var iid := equipped_id(key)
		var inst := get_club(iid)
		if inst != null and inst.is_illegal() and not is_admin:
			inst = null
		if inst == null:
			var fb := fallback_for_key(key, iid)
			if fb == "":
				continue
			bag[key] = fb
			inst = clubs[fb]
		out.append(Clubs.make_club(str(slot), inst))
	_bag_cache = out
	_bag_cache_admin = is_admin
	_bag_dirty = false
	return out


func invalidate_bag() -> void:
	_bag_dirty = true
	bag_changed.emit()


# ---------------------------------------------------------------- shops

func store_unlocked(store_id: String) -> bool:
	return unlocked.has(store_id)


func listings(store_id: String) -> Array:
	return stores.get(store_id, {}).get("listings", [])


func find_listing(store_id: String, listing_id: String) -> Dictionary:
	for l in listings(store_id):
		if str(l.get("id", "")) == listing_id:
			return l
	return {}


func distinct_models_from(store_id: String) -> int:
	var seen := {}
	for p in purchases:
		if str(p.get("store_id", "")) == store_id:
			seen[str(p.get("model_id", ""))] = true
	return seen.size()


func buy(store_id: String, listing_id: String) -> Dictionary:
	if not store_unlocked(store_id):
		return {"ok": false, "error": "That store isn't unlocked yet."}
	var l := find_listing(store_id, listing_id)
	if l.is_empty():
		return {"ok": false, "error": "That listing is gone."}
	var due := int(l["price"]) - (int(l.get("deposit", 0)) if bool(l.get("reserved", false)) else 0)
	due = maxi(0, due)
	if cash < due:
		return {"ok": false, "error": "You need $%d more." % (due - cash)}
	var model := ClubCatalog.model(str(l["model_id"]))
	if model.is_empty() or ClubCatalog.is_illegal(model) or ClubCatalog.is_starter(model):
		return {"ok": false, "error": "That listing can't be sold."}
	cash -= due
	var prov := str(l.get("provenance", ""))
	if str(l.get("seller", "")) != "":
		prov = "%s (seller: %s)" % [prov, l["seller"]]
	var inst := ClubInstance.create(_new_instance_id(), str(model["id"]), float(l["condition"]), store_id, int(l["price"]), rounds_completed, prov)
	clubs[inst.id] = inst
	purchases.append({"instance_id": inst.id, "model_id": inst.model_id, "store_id": store_id, "price": int(l["price"]), "round": rounds_completed, "listing_id": listing_id})
	var arr: Array = stores[store_id]["listings"]
	arr.erase(l)
	_record_discovery(inst, store_id)
	var newly := _evaluate_unlocks()
	_check_completion_reward()
	_bag_dirty = true
	save()
	changed.emit()
	return {"ok": true, "error": "", "instance_id": inst.id, "unlocked": newly}


func reserve(store_id: String, listing_id: String) -> Dictionary:
	if not store_unlocked(store_id):
		return {"ok": false, "error": "That store isn't unlocked yet."}
	var l := find_listing(store_id, listing_id)
	if l.is_empty():
		return {"ok": false, "error": "That listing is gone."}
	if bool(l.get("reserved", false)):
		return {"ok": false, "error": "Already reserved."}
	var max_res := int(EconomyConfig.reserve_cfg().get("max_reserved_per_store", 1))
	var count := 0
	for other in listings(store_id):
		if bool(other.get("reserved", false)):
			count += 1
	if count >= max_res:
		return {"ok": false, "error": "You can only hold %d listing per store." % max_res}
	var deposit := EconomyConfig.reserve_deposit(int(l["price"]))
	if cash < deposit:
		return {"ok": false, "error": "The deposit is $%d." % deposit}
	cash -= deposit
	l["reserved"] = true
	l["deposit"] = deposit
	l["reserve_rounds_left"] = int(EconomyConfig.reserve_cfg().get("extra_rounds", 2))
	save()
	changed.emit()
	return {"ok": true, "error": "", "deposit": deposit}


# ---------------------------------------------------------------- haggling

func haggle_cfg() -> Dictionary:
	return EconomyConfig.data().get("haggle", {})


func haggle_offers() -> Array:
	return haggle_cfg().get("offers", [])


func store_haggles(store_id: String) -> bool:
	return (haggle_cfg().get("stores", []) as Array).has(store_id)


## The shop owner's mood for the current restock ({name, mult}); same all round, new each restock.
func store_mood(store_id: String) -> Dictionary:
	var moods: Array = haggle_cfg().get("moods", [])
	if moods.is_empty():
		return {"name": "", "mult": 1.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%s:mood" % [loot_seed, stock_generation, store_id])
	var total := 0.0
	for m in moods:
		total += float(m.get("weight", 1))
	var pick := rng.randf() * total
	for m in moods:
		pick -= float(m.get("weight", 1))
		if pick <= 0.0:
			return m
	return moods[-1]


## Chance (0..1) the seller takes offer `offer_index` on this listing.
func haggle_odds(store_id: String, l: Dictionary, offer_index: int) -> float:
	var offers := haggle_offers()
	if offer_index < 0 or offer_index >= offers.size():
		return 0.0
	var odds := float(offers[offer_index].get("accept", 0.5))
	var seller := str(l.get("seller", ""))
	if seller != "":
		odds *= float((haggle_cfg().get("seller_accept_mult", {}) as Dictionary).get(seller, 1.0))
	else:
		odds *= float(store_mood(store_id).get("mult", 1.0))
	return clampf(odds, 0.02, 0.95)


func can_haggle(store_id: String, l: Dictionary) -> bool:
	return store_haggles(store_id) and store_unlocked(store_id) and not l.is_empty() \
		and str(l.get("haggled", "")) == "" and not bool(l.get("reserved", false))


## One offer per listing. Accepted: the listing's price drops to the offer (buy it normally).
## Refused: price stands, and a refused lowball may make the seller pull the listing.
func haggle(store_id: String, listing_id: String, offer_index: int) -> Dictionary:
	var l := find_listing(store_id, listing_id)
	if l.is_empty():
		return {"ok": false, "error": "That listing is gone."}
	if not can_haggle(store_id, l):
		return {"ok": false, "error": "No more haggling on this one."}
	var offers := haggle_offers()
	if offer_index < 0 or offer_index >= offers.size():
		return {"ok": false, "error": "Unknown offer."}
	var offer: Dictionary = offers[offer_index]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:haggle" % [loot_seed, listing_id])
	var accepted := rng.randf() < haggle_odds(store_id, l, offer_index)
	var old_price := int(l["price"])
	var result := {"ok": true, "error": "", "accepted": accepted, "price": old_price, "walked": false}
	if accepted:
		l["list_price"] = old_price
		l["price"] = maxi(1, int(round(float(old_price) * (1.0 - float(offer.get("discount", 0.1))))))
		l["haggled"] = "accepted"
		result["price"] = l["price"]
	else:
		l["haggled"] = "refused"
		if rng.randf() < float(offer.get("walk_away_chance", 0.0)):
			(stores[store_id]["listings"] as Array).erase(l)
			result["walked"] = true
	save()
	changed.emit()
	return result


func sell_offer(instance_id: String) -> int:
	var inst := get_club(instance_id)
	return 0 if inst == null else inst.resale_offer()


func can_sell(instance_id: String) -> Dictionary:
	var inst := get_club(instance_id)
	if inst == null:
		return {"ok": false, "error": "You don't own that club."}
	if inst.is_starter():
		return {"ok": false, "error": "Loaners belong to the clubhouse."}
	if inst.is_illegal():
		return {"ok": false, "error": "Sandbox gear can't be sold."}
	if round_in_progress:
		return {"ok": false, "error": "Finish or abandon the round first."}
	if is_equipped(instance_id):
		var key := ClubCatalog.bag_key(inst.model())
		if fallback_for_key(key, instance_id) == "" and key != "HY":
			return {"ok": false, "error": "Nothing else fits that slot."}
	return {"ok": true, "error": ""}


func sell(instance_id: String) -> Dictionary:
	var gate := can_sell(instance_id)
	if not gate["ok"]:
		return gate
	var inst: ClubInstance = clubs[instance_id]
	var offer := inst.resale_offer()
	var key := ClubCatalog.bag_key(inst.model())
	if is_equipped(instance_id):
		var fb := fallback_for_key(key, instance_id)
		if fb == "":
			bag.erase(key)
		else:
			bag[key] = fb
	cash += offer
	clubs.erase(instance_id)
	sales.append({"instance_id": instance_id, "model_id": inst.model_id, "price": offer, "round": rounds_completed})
	_bag_dirty = true
	save()
	bag_changed.emit()
	changed.emit()
	return {"ok": true, "error": "", "price": offer}


func _record_discovery(inst: ClubInstance, store_id: String) -> void:
	if discovered.has(inst.model_id):
		return
	discovered[inst.model_id] = {"round": rounds_completed, "store": store_id, "price": inst.purchase_price, "condition": inst.condition, "instance_id": inst.id}
	model_discovered.emit(inst.model_id)


func _rng_for(store_id: String, generation: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%s" % [loot_seed, generation, store_id])
	return rng


func _generate_store(store_cfg: Dictionary, generation: int) -> Array:
	var rng := _rng_for(str(store_cfg["id"]), generation)
	return LootGenerator.generate_store(store_cfg, rng, int(store_cfg.get("listings", 8)), generation)


func _generate_all_stock(keep_reserved: bool) -> void:
	for s in EconomyConfig.stores():
		var sid := str(s["id"])
		var kept: Array = []
		if keep_reserved and stores.has(sid):
			for l in stores[sid]["listings"]:
				if bool(l.get("reserved", false)) and int(l.get("reserve_rounds_left", 0)) > 0:
					l["reserve_rounds_left"] = int(l["reserve_rounds_left"]) - 1
					kept.append(l)
		var fresh := _generate_store(s, stock_generation)
		var want := int(s.get("listings", 8))
		while kept.size() < want and not fresh.is_empty():
			kept.append(fresh.pop_front())
		stores[sid] = {"listings": kept}


## Only ever called from complete_round() after a completed, non-sandbox round.
func _restock() -> void:
	stock_generation += 1
	_generate_all_stock(true)


# ---------------------------------------------------------------- collection

func collectible_putters() -> Array:
	return ClubCatalog.collectible_putters()


func owned_instance_of_model(model_id: String) -> ClubInstance:
	var best: ClubInstance = null
	for id in clubs:
		var c: ClubInstance = clubs[id]
		if c.model_id == model_id and (best == null or c.condition > best.condition):
			best = c
	return best


func owns_model(model_id: String) -> bool:
	return owned_instance_of_model(model_id) != null


func is_discovered(model_id: String) -> bool:
	return discovered.has(model_id)


func discovery(model_id: String) -> Dictionary:
	return discovered.get(model_id, {})


func owned_collectible_count() -> int:
	var n := 0
	for m in collectible_putters():
		if owns_model(str(m["id"])):
			n += 1
	return n


func putter_collection_complete() -> bool:
	return owned_collectible_count() == collectible_putters().size()


func _check_completion_reward() -> void:
	if not completion_reward_earned and putter_collection_complete():
		completion_reward_earned = true
		completion_reward_round = rounds_completed


## Broader catalog progress: type -> {discovered, owned, total}.
func catalog_progress() -> Dictionary:
	var out := {}
	for t in ClubCatalog.type_order():
		out[t] = {"discovered": 0, "owned": 0, "total": 0}
	for m in ClubCatalog.lootable_models():
		var t := str(m["type"])
		out[t]["total"] += 1
		if is_discovered(str(m["id"])):
			out[t]["discovered"] += 1
		if owns_model(str(m["id"])):
			out[t]["owned"] += 1
	return out


# ---------------------------------------------------------------- rounds

func begin_round(pars: Array[int]) -> RoundTracker:
	var id := "r%d-%d-%08x" % [rounds_completed + 1, int(Time.get_unix_time_from_system()), randi()]
	round_in_progress = false
	return RoundTracker.start(id, pars)


func summary_for(round_id: String) -> Dictionary:
	for s in round_history:
		if str(s.get("round_id", "")) == round_id:
			return s
	return {}


## Apply a finished round exactly once. Returns the summary (also kept in round_history).
func complete_round(result: Dictionary) -> Dictionary:
	round_in_progress = false
	var rid := str(result.get("round_id", ""))
	if rid != "" and processed_round_ids.has(rid):
		var prev := summary_for(rid)
		if prev.is_empty():
			prev = {"round_id": rid}
		prev = prev.duplicate(true)
		prev["already_processed"] = true
		return prev
	var holes: int = result.get("pars", []).size()
	var summary := {
		"round_id": rid, "total": int(result.get("total", 0)), "par": int(result.get("par", 0)),
		"rel_par": int(result.get("rel_par", 0)), "holes": holes,
		"hole_strokes": result.get("hole_strokes", []), "pars": result.get("pars", []),
		"payout": 0, "breakdown": [], "sandbox": bool(result.get("sandbox", false)),
		"complete": bool(result.get("complete", false)), "assisted": bool(result.get("assisted", false)),
		"unlocked_now": [], "new_best": false, "restocked": false, "notes": [],
		"qualifying": [], "already_processed": false, "round_no": rounds_completed,
		"illegal_used": result.get("illegal_used", []), "side_bets": [],
	}
	if rid != "":
		processed_round_ids.append(rid)
	if summary["sandbox"]:
		sandbox_rounds += 1
		summary["notes"].append("Sandbox round: illegal equipment was used. No money, progress, records or restock.")
		_push_history(summary)
		save()
		changed.emit()
		return summary
	if not summary["complete"]:
		summary["notes"].append("Round not completed (a hole was skipped or left unfinished). No payout, no restock.")
		_push_history(summary)
		save()
		changed.emit()
		return summary

	rounds_completed += 1
	summary["round_no"] = rounds_completed
	var cfg := EconomyConfig.round_cfg()
	var scale := float(holes) / 9.0
	var breakdown: Array = []
	var base := int(round(float(cfg.get("base_payout_per_9", 35)) * scale))
	breakdown.append(["Round complete (%d holes)" % holes, base])
	var hole_bonus := 0
	var pars: Array = result.get("pars", [])
	var strokes: Array = result.get("hole_strokes", [])
	for i in range(mini(pars.size(), strokes.size())):
		var rel := int(strokes[i]) - int(pars[i])
		if rel <= 0:
			hole_bonus += int(cfg.get("bonus_par_or_better_per_hole", 2))
		if rel < 0:
			hole_bonus += int(cfg.get("bonus_birdie_or_better_per_hole", 3))
	hole_bonus = mini(hole_bonus, int(cfg.get("bonus_per_hole_cap", 20)))
	if hole_bonus > 0:
		breakdown.append(["Pars and birdies", hole_bonus])
	var tier_bonus := 0
	for t in cfg.get("bonus_score_tiers", []):
		if summary["rel_par"] <= EconomyConfig.scale_rel_par(float(t.get("rel_par_max", 0))):
			tier_bonus = maxi(tier_bonus, int(t.get("bonus", 0)))
	if tier_bonus > 0:
		breakdown.append(["Score bonus (%+d)" % summary["rel_par"], tier_bonus])
	if rounds_completed == 1:
		breakdown.append(["First round", int(cfg.get("bonus_first_round", 15))])
	var milestones: Dictionary = cfg.get("milestone_bonuses", {})
	if milestones.has(str(rounds_completed)):
		breakdown.append(["Milestone: %d rounds" % rounds_completed, int(milestones[str(rounds_completed)])])
	var bets: Array = result.get("side_bets", [])
	summary["side_bets"] = SideBets.rows(bets, result, true)
	for row in summary["side_bets"]:
		if row["status"] == SideBets.WON:
			breakdown.append(["Side bet: %s" % row["text"], int(row["reward"])])
	if not summary["assisted"]:
		if best_round.is_empty() or summary["rel_par"] < int(best_round.get("rel_par", 999)):
			if not best_round.is_empty():
				breakdown.append(["Personal best", int(cfg.get("bonus_personal_best", 10))])
			best_round = {"rel_par": summary["rel_par"], "total": summary["total"], "round_no": rounds_completed}
			summary["new_best"] = true
	else:
		summary["notes"].append("Mulligan or restart used: paid out, but not a qualifying round or a personal record.")
	var payout := 0
	for b in breakdown:
		payout += int(b[1])
	cash += payout
	summary["payout"] = payout
	summary["breakdown"] = breakdown

	# Wear-and-tear bookkeeping on the clubs that were swung.
	var by_inst: Dictionary = result.get("strokes_by_instance", {})
	for iid in by_inst:
		var c := get_club(str(iid))
		if c != null:
			c.rounds_played += 1
			c.strokes += int(by_inst[iid])

	# Qualifying-round checks for every store that still needs one.
	for s in EconomyConfig.stores():
		var sid := str(s["id"])
		if s.get("unlock") == null:
			continue
		var rm := Progression.round_meets(s, result)
		if rm["eligible"]:
			var prev_best = best_attempts.get(sid, null)
			if prev_best == null or int(rm["rel_par"]) < int(prev_best):
				best_attempts[sid] = int(rm["rel_par"])
		if rm["meets"] and not qualified_rounds.has(sid):
			qualified_rounds[sid] = true
			summary["qualifying"].append("%s: qualifying round done (%+d with %d %s clubs)" % [s["name"], rm["rel_par"], rm["clubs_used"], EconomyConfig.store_name(str(s["unlock"]["from_store"]))])
		elif not unlocked.has(sid) and not qualified_rounds.has(sid) and rm["reason"] != "":
			summary["qualifying"].append("%s: not yet (%s)" % [s["name"], rm["reason"]])
	summary["unlocked_now"] = _evaluate_unlocks()
	_restock()
	summary["restocked"] = true
	summary["cash_after"] = cash
	summary["next_objective"] = Progression.next_objective(self)
	_push_history(summary)
	save()
	changed.emit()
	return summary


func _push_history(summary: Dictionary) -> void:
	round_history.append(summary)
	while round_history.size() > HISTORY_LIMIT:
		round_history.pop_front()


func _evaluate_unlocks() -> Array:
	var newly: Array = []
	for s in EconomyConfig.stores():
		var sid := str(s["id"])
		if unlocked.has(sid) or s.get("unlock") == null:
			continue
		var req: Dictionary = s["unlock"]
		var have := distinct_models_from(str(req.get("from_store", "")))
		if have >= int(req.get("distinct_models", 2)) and qualified_rounds.has(sid):
			unlocked.append(sid)
			newly.append(sid)
			location_unlocked.emit(sid)
	return newly


# ---------------------------------------------------------------- admin sandbox

func sandbox_instances() -> Array:
	var out: Array = []
	for id in sandbox_clubs:
		out.append(sandbox_clubs[id])
	return out


func grant_sandbox(model_id: String) -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	var m := ClubCatalog.model(model_id)
	if m.is_empty() or not ClubCatalog.is_illegal(m):
		return {"ok": false, "error": "Not a sandbox item."}
	for id in sandbox_clubs:
		if sandbox_clubs[id].model_id == model_id:
			return {"ok": true, "error": "", "instance_id": id}
	var inst := ClubInstance.create(_new_instance_id(), model_id, 1.0, "admin", 0, rounds_completed, "Granted from the admin sandbox.")
	sandbox_clubs[inst.id] = inst
	save()
	changed.emit()
	return {"ok": true, "error": "", "instance_id": inst.id}


## Admin-only "wear whatever I want": equips any catalog model, legal or illegal, into its
## bag slot immediately, no purchase/loot/unlock required. Prefers a copy the player already
## owns (real condition and history intact); only spawns a Mint admin sandbox copy -- same
## mechanism as grant_sandbox() -- for a model they don't own. Distinct from grant_sandbox()
## itself, which stays illegal-only for the dedicated sandbox-gear panel below.
func admin_equip(model_id: String) -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	var m := ClubCatalog.model(model_id)
	if m.is_empty():
		return {"ok": false, "error": "Unknown club."}
	for inst in owned():
		if inst.model_id == model_id:
			return equip(inst.id)
	for id in sandbox_clubs:
		if sandbox_clubs[id].model_id == model_id:
			return equip(id)
	var inst := ClubInstance.create(_new_instance_id(), model_id, 1.0, "admin", 0, rounds_completed, "Admin: equipped directly for testing.")
	sandbox_clubs[inst.id] = inst
	save()
	changed.emit()
	return equip(inst.id)


## Grant every illegal model and equip one into each bag slot it fills. Admin-only, same rules
## as grant_sandbox()/equip() applied one model at a time; a slot with more than one illegal
## model ends up wearing whichever was granted last.
func grant_and_equip_all_sandbox() -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	for m in ClubCatalog.illegal_models():
		var mid := str(m["id"])
		var g := grant_sandbox(mid)
		if not g["ok"]:
			continue
		equip(str(g["instance_id"]))
	return {"ok": true, "error": ""}


# ---------------------------------------------------------------- golf course manager
## Owning a course is gated: the player has to play their way up to the `unlock.store` store
## and then pay `unlock.deed_price` for the deed, so nobody runs a course before they've proved
## themselves as a golfer (and passive income can't shortcut the store/club progression).
## The rules live in CourseBusiness; these wrappers move the money, save and signal.

func manager_status() -> Dictionary:
	var u: Dictionary = EconomyConfig.manager_cfg().get("unlock", {})
	var sid := str(u.get("store", "pga"))
	var price := int(u.get("deed_price", 2500))
	var store_name := sid
	for s in EconomyConfig.stores():
		if str(s["id"]) == sid:
			store_name = str(s.get("name", sid))
	var store_ok := store_unlocked(sid)
	return {"owned": business.owned, "store_id": sid, "store_name": store_name, "store_ok": store_ok,
		"price": price, "cash_ok": cash >= price, "can_buy": not business.owned and store_ok and cash >= price}


func buy_course() -> Dictionary:
	var st := manager_status()
	if st["owned"]:
		return {"ok": false, "error": "You already own a course."}
	if not st["store_ok"]:
		return {"ok": false, "error": "Unlock %s first: the deed is only sold to proven golfers." % st["store_name"]}
	if not st["cash_ok"]:
		return {"ok": false, "error": "The deed costs $%d." % st["price"]}
	cash -= int(st["price"])
	business = CourseBusiness.create()
	_biz_frac = 0.0
	_biz_last_ms = 0
	save()
	changed.emit()
	return {"ok": true, "error": ""}


## Manager-only reset. Shared player money, equipment, unlocks and course files survive.
func reset_manager_progress(keep_deed: bool = true) -> void:
	var old_path := business.course_path
	var was_owned := business.owned
	business = CourseBusiness.create() if keep_deed and was_owned else CourseBusiness.new()
	if business.owned:
		business.course_path = old_path
		business.refresh_course()
	offline_report = {}
	_biz_frac = 0.0
	_biz_last_ms = 0
	_biz_save_ms = 0
	save()
	changed.emit()
	business_ticked.emit()


func set_course_open(open: bool) -> Dictionary:
	if open:
		var why := business.opening_problem()
		if why != "":
			return {"ok": false, "error": why}
	business.accepting_visitors = open
	save()
	changed.emit()
	business_ticked.emit()
	return {"ok": true, "error": ""}


## Run the owned course on one of the player's Course Studio courses.
func set_business_course(path: String) -> Dictionary:
	_manager_seconds = 0.0
	if not business.owned:
		return {"ok": false, "error": "Buy a course first."}
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "error": "That course file is missing."}
	var switched := path != business.course_path
	business.select_course(path)
	if switched:
		_biz_frac = 0.0
		_biz_last_ms = 0
		_biz_save_ms = 0
		offline_report = {}
	save()
	changed.emit()
	return {"ok": true, "error": ""}


## Stand a facility on the club's course (Course Manager validates the site against the course).
func place_facility(id: String, pos: Vector2, rot: float) -> Dictionary:
	if not business.owned or not business.has_course():
		return {"ok": false, "error": "Choose your club's course first."}
	if EconomyConfig.facility(id).is_empty():
		return {"ok": false, "error": "Unknown facility."}
	business.place(id, pos, rot)
	save()
	changed.emit()
	return {"ok": true, "error": ""}


## Take a facility off the course. A built one keeps its level and can be placed again.
func unplace_facility(id: String) -> void:
	business.unplace(id)
	save()
	changed.emit()


## Re-read the owned course's file (holes, placed facilities) after Course Studio edits.
func refresh_business() -> void:
	if business.owned:
		business.refresh_course()


## Turn the testing wallet on or off (see `unlimited_money`).
func set_unlimited_money(on: bool) -> void:
	if on == unlimited_money:
		return
	unlimited_money = on
	if on:
		_real_cash = cash
		cash = TEST_MONEY
	else:
		cash = _real_cash
	save()
	changed.emit()


## Build a placed facility, or upgrade a built one, for its next level's cost.
func build_facility(id: String) -> Dictionary:
	if not business.owned:
		return {"ok": false, "error": "Buy a course first."}
	business.refresh_course()
	var why := business.can_build(id)
	if why != "":
		return {"ok": false, "error": why}
	var cost := business.next_cost(id)
	if cash < cost:
		return {"ok": false, "error": "That costs $%d." % cost}
	cash -= cost
	business.built[id] = business.level(id) + 1
	save()
	changed.emit()
	return {"ok": true, "error": "", "cost": cost}


## Fit out a clubhouse room, or take it up a tier, for its next tier's cost.
func build_room(id: String) -> Dictionary:
	if not business.owned:
		return {"ok": false, "error": "Buy a course first."}
	var why := business.can_build_room(id)
	if why != "":
		return {"ok": false, "error": why}
	var cost := business.room_next_cost(id)
	if cash < cost:
		return {"ok": false, "error": "That costs $%d." % cost}
	cash -= cost
	business.rooms[id] = business.room_tier(id) + 1
	save()
	changed.emit()
	return {"ok": true, "error": "", "cost": cost}


func hire_staff(role: String) -> Dictionary:
	if not business.owned:
		return {"ok": false, "error": "Buy a course first."}
	var why := business.can_hire(role)
	if why != "":
		return {"ok": false, "error": why}
	business.staff[role] = business.heads(role) + 1
	save()
	changed.emit()
	return {"ok": true, "error": ""}


func let_go_staff(role: String) -> Dictionary:
	if business.heads(role) <= 0:
		return {"ok": false, "error": "Nobody in that role to let go."}
	business.staff[role] = business.heads(role) - 1
	save()
	changed.emit()
	return {"ok": true, "error": ""}


func set_green_fee(fee: int) -> void:
	if not business.owned:
		return
	business.green_fee = business.clamp_fee(fee)
	save()
	changed.emit()


## Turn real seconds of the owned course into dollars in the wallet: whole dollars move, the
## cents carry to the next tick, and the wallet never goes below zero. Returns dollars moved.
func _run_business(real_seconds: float, rate: float) -> int:
	var per_hour := maxf(float(EconomyConfig.manager_cfg().get("real_seconds_per_hour", 240)), 1.0)
	_biz_frac += business.advance(real_seconds / per_hour, rate)
	var whole := int(_biz_frac)  # toward zero, so losses carry their cents too
	_biz_frac -= whole
	var before := cash
	cash = maxi(0, cash + whole)
	return cash - before


func _offline_rate() -> float:
	return float(EconomyConfig.manager_cfg().get("offline", {}).get("rate", 0.25))


func _offline_cap_seconds() -> float:
	return float(EconomyConfig.manager_cfg().get("offline", {}).get("cap_hours", 4)) * 3600.0


# ---------------------------------------------------------------- admin cheats
## Everything below is admin-only and deliberately edits real progression (cash, store
## unlocks, owned clubs) for the person running the build with --admin. Granted legal clubs
## are real owned clubs (source "admin_grant") so they count for the bag and collection;
## illegal gear still goes through grant_sandbox() only.

func admin_add_cash(amount: int) -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	cash = maxi(0, cash + amount)
	save()
	changed.emit()
	return {"ok": true, "error": ""}


func admin_unlock_all_stores() -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	for s in EconomyConfig.stores():
		var sid := str(s["id"])
		qualified_rounds[sid] = true
		if not unlocked.has(sid) and s.get("unlock") != null:
			unlocked.append(sid)
			location_unlocked.emit(sid)
	save()
	changed.emit()
	return {"ok": true, "error": ""}


func admin_restock() -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	_restock()
	save()
	changed.emit()
	return {"ok": true, "error": ""}


## One Mint copy of every legal, non-loaner club the player doesn't already own.
func admin_grant_all_clubs() -> Dictionary:
	if not admin():
		return {"ok": false, "error": "Admin access required."}
	var granted := 0
	for m in ClubCatalog.lootable_models():
		var mid := str(m["id"])
		if owns_model(mid):
			continue
		var inst := ClubInstance.create(_new_instance_id(), mid, 1.0, "admin_grant", 0, rounds_completed, "Admin grant.")
		clubs[inst.id] = inst
		_record_discovery(inst, "admin_grant")
		granted += 1
	_check_completion_reward()
	_bag_dirty = true
	save()
	bag_changed.emit()
	changed.emit()
	return {"ok": true, "error": "", "granted": granted}


func remove_sandbox(instance_id: String) -> void:
	if not sandbox_clubs.has(instance_id):
		return
	sandbox_clubs.erase(instance_id)
	_heal_bag()
	save()
	bag_changed.emit()
	changed.emit()


## True if any equipped club is sandbox gear (the HUD shows a warning before the first swing).
func bag_has_illegal() -> bool:
	for c in bag_clubs():
		if c.illegal:
			return true
	return false
