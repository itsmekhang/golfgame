class_name EconomyConfig
extends RefCounted
## Read-only access to res://data/economy.json (prices, payouts, store personalities, loot
## weights, modifier bounds). Everything numeric that a playtester might want to tune lives in
## that file, not in code. Loaded once; call reload() after editing the JSON at runtime.

const PATH := "res://data/economy.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		reload()
	return _data


static func reload() -> void:
	_data = {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("EconomyConfig: cannot open %s" % PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EconomyConfig: %s is not a JSON object" % PATH)
		return
	_data = parsed


static func starting_cash() -> int:
	return int(data().get("starting_cash", 60))


static func bag_size() -> int:
	return int(data().get("bag_size", 14))


static func round_cfg() -> Dictionary:
	return data().get("round", {})


static func holes_per_round() -> int:
	return maxi(1, int(round_cfg().get("holes_per_round", 9)))


## Score targets in the data are written for nine holes; scale them to the configured round.
static func scale_rel_par(per_9: float) -> int:
	return int(round(per_9 * float(holes_per_round()) / 9.0))


static func stores() -> Array:
	return data().get("stores", [])


static func store(id: String) -> Dictionary:
	for s in stores():
		if s.get("id", "") == id:
			return s
	return {}


static func store_name(id: String) -> String:
	var s := store(id)
	if s.is_empty():
		return id.capitalize()
	return str(s.get("name", id))


static func rarity_order() -> Array:
	return data().get("rarity", {}).get("order", ["common", "uncommon", "rare", "epic", "legendary", "mythic"])


static func rarity_rank(rarity: String) -> int:
	return maxi(0, rarity_order().find(rarity))


static func rarity_color(rarity: String) -> Color:
	var colors: Dictionary = data().get("rarity", {}).get("colors", {})
	return Color(str(colors.get(rarity, "8a8f8c")))


static func modifiers() -> Dictionary:
	return data().get("modifiers", {})


static func modifier_bound(key: String, fallback: float) -> float:
	return float(modifiers().get(key, fallback))


static func condition_grade(condition: float) -> String:
	var grades: Array = data().get("condition", {}).get("grades", [])
	var label := "Fair"
	for g in grades:
		if condition >= float(g[1]):
			label = str(g[0])
	return label


## Multiplier on a model's base value for a given condition (piecewise linear curve from data).
static func condition_value_factor(condition: float) -> float:
	var curve: Array = data().get("condition", {}).get("value_curve", [[0.0, 0.4], [1.0, 1.15]])
	condition = clampf(condition, 0.0, 1.0)
	if curve.is_empty():
		return 1.0
	if condition <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var x0 := float(curve[i - 1][0])
		var x1 := float(curve[i][0])
		if condition <= x1:
			var t := 0.0 if x1 == x0 else (condition - x0) / (x1 - x0)
			return lerpf(float(curve[i - 1][1]), float(curve[i][1]), t)
	return float(curve[curve.size() - 1][1])


## Fair used value: model + condition only. Never the price that was paid.
static func fair_value(model: Dictionary, condition: float) -> int:
	var base := float(model.get("base_value", 0))
	if base <= 0.0:
		return 0
	return maxi(1, int(round(base * condition_value_factor(condition))))


## What a shop offers for an instant sale: 50-65% of fair value, better condition = better rate.
static func resale_offer(model: Dictionary, condition: float) -> int:
	var fair := fair_value(model, condition)
	if fair <= 0:
		return 0
	var r: Dictionary = data().get("resale", {})
	var rate := lerpf(float(r.get("rate_min", 0.5)), float(r.get("rate_max", 0.65)), clampf(condition, 0.0, 1.0))
	return maxi(1, int(floor(fair * rate)))


static func reserve_cfg() -> Dictionary:
	return data().get("reserve", {})


static func reserve_deposit(price: int) -> int:
	var r := reserve_cfg()
	return maxi(int(r.get("min_deposit", 2)), int(ceil(price * float(r.get("deposit_fraction", 0.1)))))


static func illegal_cfg() -> Dictionary:
	return data().get("illegal", {})


static func completion_reward() -> Dictionary:
	return data().get("completion_reward", {})


## Golf course manager tunables ("manager" in economy.json; see CourseBusiness).
static func manager_cfg() -> Dictionary:
	return data().get("manager", {})


## One facility's config by id ({} if unknown).
static func facility(id: String) -> Dictionary:
	for f in manager_cfg().get("facilities", []):
		if str(f.get("id", "")) == id:
			return f
	return {}


## One clubhouse room's config by id ({} if unknown).
static func room(id: String) -> Dictionary:
	for r in manager_cfg().get("rooms", []):
		if str(r.get("id", "")) == id:
			return r
	return {}


## One staff role's config by id ({} if unknown).
static func staff_role(id: String) -> Dictionary:
	for s in manager_cfg().get("staff", []):
		if str(s.get("id", "")) == id:
			return s
	return {}
