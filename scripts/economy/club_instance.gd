class_name ClubInstance
extends RefCounted
## One physical club the player owns (or a shop is selling): a catalog model plus this copy's
## own condition, where it came from, what was paid, and how much it has been played. Two
## copies of the same model are two instances with different histories and values.

var id: String = ""
var model_id: String = ""
var condition: float = 0.7  # 0 = wrecked, 1 = mint
var source_store: String = ""  # store id, "starter" for loaners, "admin" for sandbox gear
var purchase_price: int = 0
var acquired_round: int = 0  # rounds_completed at the time of purchase
var rounds_played: int = 0
var strokes: int = 0
var provenance: String = ""


static func create(p_id: String, p_model_id: String, p_condition: float, p_source: String, p_price: int, p_round: int, p_provenance: String = "") -> ClubInstance:
	var c := ClubInstance.new()
	c.id = p_id
	c.model_id = p_model_id
	c.condition = clampf(p_condition, 0.0, 1.0)
	c.source_store = p_source
	c.purchase_price = p_price
	c.acquired_round = p_round
	c.provenance = p_provenance
	return c


func model() -> Dictionary:
	return ClubCatalog.model(model_id)


func display_name() -> String:
	return str(model().get("name", model_id))


func rarity() -> String:
	return str(model().get("rarity", "common"))


func type() -> String:
	return str(model().get("type", ""))


func is_starter() -> bool:
	return ClubCatalog.is_starter(model())


func is_illegal() -> bool:
	return ClubCatalog.is_illegal(model())


func is_collectible_putter() -> bool:
	return ClubCatalog.is_collectible_putter(model())


func condition_grade() -> String:
	return EconomyConfig.condition_grade(condition)


func fair_value() -> int:
	return EconomyConfig.fair_value(model(), condition)


func resale_offer() -> int:
	if is_starter() or is_illegal():
		return 0
	return EconomyConfig.resale_offer(model(), condition)


func source_label() -> String:
	match source_store:
		"starter": return "Clubhouse loaner"
		"admin": return "Admin sandbox"
		"admin_grant": return "Admin grant"
		"": return "Unknown"
	return EconomyConfig.store_name(source_store)


func to_dict() -> Dictionary:
	return {
		"id": id, "model_id": model_id, "condition": condition, "source_store": source_store,
		"purchase_price": purchase_price, "acquired_round": acquired_round,
		"rounds_played": rounds_played, "strokes": strokes, "provenance": provenance,
	}


static func from_dict(d: Dictionary) -> ClubInstance:
	var c := ClubInstance.new()
	c.id = str(d.get("id", ""))
	c.model_id = str(d.get("model_id", ""))
	c.condition = clampf(float(d.get("condition", 0.7)), 0.0, 1.0)
	c.source_store = str(d.get("source_store", ""))
	c.purchase_price = int(d.get("purchase_price", 0))
	c.acquired_round = int(d.get("acquired_round", 0))
	c.rounds_played = int(d.get("rounds_played", 0))
	c.strokes = int(d.get("strokes", 0))
	c.provenance = str(d.get("provenance", ""))
	return c
