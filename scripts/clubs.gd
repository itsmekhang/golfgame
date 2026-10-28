class_name Clubs
extends RefCounted
## Club bag. Launch numbers are typical launch-monitor values at full power
## (ball speed mph, vertical launch deg, backspin rpm) and live per bag slot in
## data/club_catalog.json ("stock_launch"). A Club is one swingable entry in the bag: the
## slot's stock launch numbers plus the bounded modifiers and condition of the specific
## ClubInstance equipped there (see GameState.bag_clubs). Without a GameState (headless
## tests, tools) bag() is the plain loaner set with neutral modifiers, exactly the old feel.

class Club:
	var name: String
	var short: String
	var ball_speed_mph: float
	var vla_deg: float
	var backspin_rpm: float
	var is_putter: bool
	# --- equipment layer (neutral defaults reproduce the stock bag) ---
	var slot: String = ""
	var model_id: String = ""
	var model_name: String = ""
	var instance_id: String = ""
	var source_store: String = ""
	var carry_yd: float = 0.0
	var distance: float = 1.0  # ball-speed multiplier (bounded by economy.json)
	var forgiveness: float = 1.0  # >1 softens off-centre penalties, <1 sharpens them
	var dispersion_deg: float = 0.0  # random push at a full mishit, degrees
	var spin: float = 1.0  # backspin multiplier
	var control: float = 1.0  # >1 = heel/toe shaping is more precise (less unintended push)
	var condition: float = 1.0
	var illegal: bool = false
	var illegal_kind: String = ""  # "grenade" | "auto_putt" | ""
	var is_starter: bool = false
	var audio_category: String = "general"
	var feel: String = ""

	func _init(p_name: String, p_short: String, p_speed: float, p_vla: float, p_spin: float, p_putter: bool = false) -> void:
		name = p_name
		short = p_short
		ball_speed_mph = p_speed
		vla_deg = p_vla
		backspin_rpm = p_spin
		is_putter = p_putter


## The equipped bag when a GameState exists, else the stock loaner set.
static func bag() -> Array:
	if GameState.current != null:
		var b: Array = GameState.current.bag_clubs()
		if not b.is_empty():
			return b
	return stock_bag()


static var _stock_cache: Array = []


## Stock loaner set straight from the catalog's stock_launch table, neutral modifiers.
static func stock_bag() -> Array:
	if not _stock_cache.is_empty():
		return _stock_cache
	var out: Array = []
	for slot in ClubCatalog.bag_order():
		if slot == "HY":
			continue  # the loaner set carries no hybrid
		var c := _stock_club(str(slot))
		c.dispersion_deg = 0.0
		out.append(c)
	_stock_cache = out
	return out


static func _stock_club(slot: String) -> Club:
	var sl := ClubCatalog.stock_launch(slot)
	var c := Club.new(str(sl.get("name", slot)), slot, float(sl.get("speed", 100.0)), float(sl.get("vla", 15.0)), float(sl.get("spin", 5000.0)), slot == "PT")
	c.slot = slot
	c.carry_yd = float(sl.get("carry_yd", 0.0))
	c.audio_category = str(sl.get("audio", "general"))
	return c


## Build the swingable Club for `slot` from an owned instance (catalog model + this copy's
## condition). Modifiers are clamped to the bounds in economy.json so no data edit can push
## the working shot mechanics outside a playable range.
static func make_club(slot: String, inst: ClubInstance) -> Club:
	var c := _stock_club(slot)
	var m := inst.model()
	var mods: Dictionary = m.get("mods", {})
	c.model_id = inst.model_id
	c.model_name = str(m.get("name", inst.model_id))
	c.instance_id = inst.id
	c.source_store = inst.source_store
	c.condition = inst.condition
	c.is_starter = ClubCatalog.is_starter(m)
	c.illegal = ClubCatalog.is_illegal(m)
	c.feel = str(m.get("feel", ""))
	if c.illegal:
		c.illegal_kind = "auto_putt" if c.is_putter else "grenade"
	c.distance = clampf(float(mods.get("distance", 1.0)), EconomyConfig.modifier_bound("distance_mult_min", 0.9), EconomyConfig.modifier_bound("distance_mult_max", 1.08))
	c.forgiveness = clampf(float(mods.get("forgiveness", 1.0)), EconomyConfig.modifier_bound("forgiveness_min", 0.75), EconomyConfig.modifier_bound("forgiveness_max", 1.25))
	var disp_max := EconomyConfig.modifier_bound("putter_dispersion_deg_max", 0.3) if c.is_putter else EconomyConfig.modifier_bound("dispersion_deg_max", 2.5)
	c.dispersion_deg = clampf(float(mods.get("dispersion_deg", 0.0)), 0.0, disp_max)
	c.spin = clampf(float(mods.get("spin", 1.0)), EconomyConfig.modifier_bound("spin_mult_min", 0.85), EconomyConfig.modifier_bound("spin_mult_max", 1.25))
	c.control = clampf(float(mods.get("control", 1.0)), EconomyConfig.modifier_bound("control_min", 0.85), EconomyConfig.modifier_bound("control_max", 1.15))
	# Illegal gear may override the launch numbers outright (that is the whole joke).
	if c.illegal and m.has("launch"):
		var l: Dictionary = m["launch"]
		c.ball_speed_mph = float(l.get("speed", c.ball_speed_mph))
		c.vla_deg = float(l.get("vla", c.vla_deg))
		c.backspin_rpm = float(l.get("spin", c.backspin_rpm))
		c.carry_yd = float(l.get("carry_yd", c.carry_yd))
	else:
		c.carry_yd *= c.distance
	# Display name: the slot for irons of a set ("7 Iron"), the model name otherwise.
	if str(m.get("slot", "")) == "IRONS":
		c.name = "%s (%s)" % [c.name, c.model_name]
	else:
		c.name = c.model_name
	return c


## Best club index for a distance to the pin (yards) - used for auto-select.
static func suggest(distance_yd: float, on_green: bool) -> int:
	var b := bag()
	if b.is_empty():
		return 0
	if on_green:
		for i in range(b.size()):
			if b[i].is_putter:
				return i
		return b.size() - 1
	var last_full := 0
	for i in range(b.size()):
		if b[i].is_putter:
			continue
		last_full = i
		if distance_yd >= b[i].carry_yd * 0.93:
			return i
	return last_full


## Rough full-swing carry estimate (yards) for a bag index at a power fraction (0..1) --
## a cheap pre-flight proxy (audio cues, etc.) that doesn't need to run real ball physics.
static func stock_carry_yd(club_index: int, pfrac: float = 1.0) -> float:
	var b := bag()
	if club_index < 0 or club_index >= b.size():
		return 0.0
	return b[club_index].carry_yd * clampf(pfrac, 0.0, 1.0)


static func index_of_putter() -> int:
	var b := bag()
	for i in range(b.size()):
		if b[i].is_putter:
			return i
	return maxi(0, b.size() - 1)
