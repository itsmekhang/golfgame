class_name ClubCatalog
extends RefCounted
## Read-only access to res://data/club_catalog.json: the shared club *model* definitions
## (name, type, bag slot, rarity, value, modifiers, art hints). Individual owned copies are
## ClubInstance objects that reference a model by id.

const PATH := "res://data/club_catalog.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		reload()
	return _data


static func reload() -> void:
	_data = {}
	_by_id = {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("ClubCatalog: cannot open %s" % PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ClubCatalog: %s is not a JSON object" % PATH)
		return
	_data = parsed
	for m in _data.get("models", []):
		_by_id[str(m.get("id", ""))] = m


static func models() -> Array:
	return data().get("models", [])


static func model(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func has_model(id: String) -> bool:
	data()
	return _by_id.has(id)


static func stock_launch(slot: String) -> Dictionary:
	return data().get("stock_launch", {}).get(slot, {})


static func bag_order() -> Array:
	return data().get("bag_order", ["DR", "3W", "5W", "HY", "4I", "5I", "6I", "7I", "8I", "9I", "PW", "GW", "SW", "LW", "PT"])


static func iron_set_slots() -> Array:
	return data().get("iron_set_slots", ["4I", "5I", "6I", "7I", "8I", "9I"])


## Bag slots a model occupies: an iron set expands to 4I..9I, everything else is one slot.
static func slots_for_model(m: Dictionary) -> Array:
	if str(m.get("slot", "")) == "IRONS":
		return iron_set_slots()
	return [str(m.get("slot", ""))]


## Bag-dictionary key for a model ("IRONS" for a set, else the slot itself).
static func bag_key(m: Dictionary) -> String:
	return str(m.get("slot", ""))


static func is_starter(m: Dictionary) -> bool:
	return bool(m.get("starter", false))


static func is_illegal(m: Dictionary) -> bool:
	return bool(m.get("illegal", false))


static func is_putter(m: Dictionary) -> bool:
	return str(m.get("type", "")) == "putter"


static func is_collectible_putter(m: Dictionary) -> bool:
	return is_putter(m) and bool(m.get("collectible", false)) and not is_illegal(m) and not is_starter(m)


## The seven-piece prestige collection, in rarity order. Exactly seven entries by contract.
static func collectible_putters() -> Array:
	var out: Array = []
	for m in models():
		if is_collectible_putter(m):
			out.append(m)
	out.sort_custom(func(a, b): return EconomyConfig.rarity_rank(str(a["rarity"])) < EconomyConfig.rarity_rank(str(b["rarity"])))
	return out


## Everything that can turn up in a shop: not a loaner, not admin sandbox gear.
static func lootable_models() -> Array:
	var out: Array = []
	for m in models():
		if not is_starter(m) and not is_illegal(m):
			out.append(m)
	return out


static func starter_models() -> Array:
	var out: Array = []
	for m in models():
		if is_starter(m):
			out.append(m)
	return out


static func illegal_models() -> Array:
	var out: Array = []
	for m in models():
		if is_illegal(m):
			out.append(m)
	return out


static func models_by_rarity(rarity: String, types: Array) -> Array:
	var out: Array = []
	for m in lootable_models():
		if str(m.get("rarity", "")) == rarity and (types.is_empty() or types.has(str(m.get("type", "")))):
			out.append(m)
	return out


static func type_label(type: String) -> String:
	match type:
		"driver": return "Driver"
		"wood": return "Fairway Wood"
		"hybrid": return "Hybrid"
		"iron_set": return "Iron Set"
		"wedge": return "Wedge"
		"putter": return "Putter"
	return type.capitalize()


static func type_order() -> Array:
	return ["driver", "wood", "hybrid", "iron_set", "wedge", "putter"]


## Short slot tag as shown on a price tag ("3W", "IRONS", "PT").
static func slot_label(m: Dictionary) -> String:
	var slot := str(m.get("slot", ""))
	if slot == "IRONS":
		return "4-9 irons"
	return slot
