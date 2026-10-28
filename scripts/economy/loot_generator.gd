class_name LootGenerator
extends RefCounted
## Builds shop listings. Model, condition, asking price and provenance are rolled as related
## but separate attributes: a rare club can be beat up, a common one pristine, and a valuable
## club can be underpriced by a seller who doesn't know what they have.
##
## Rarity roll per listing: the store's mythic_chance is checked first as a flat per-listing
## probability (that IS the Scotty Cameron chance, there is no second putter-type roll), then
## the remaining rarities are drawn from rarity_weights. Every store's weights and model pools
## include every rarity, so each store has a nonzero chance of every collectible putter.


static func generate_store(store_cfg: Dictionary, rng: RandomNumberGenerator, count: int, generation: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(generate_listing(store_cfg, rng, generation, i))
	return out


static func generate_listing(store_cfg: Dictionary, rng: RandomNumberGenerator, generation: int, index: int) -> Dictionary:
	var rarity := roll_rarity(store_cfg, rng)
	var model := roll_model(store_cfg, rarity, rng)
	var condition := roll_condition(store_cfg, rng)
	var pricing := price_for(store_cfg, model, condition, rng)
	var prov_pool: Array = store_cfg.get("provenance", [])
	var provenance := ""
	if not prov_pool.is_empty():
		provenance = str(prov_pool[rng.randi_range(0, prov_pool.size() - 1)])
	return {
		"id": "%s-%d-%d-%08x" % [str(store_cfg.get("id", "store")), generation, index, rng.randi()],
		"model_id": str(model.get("id", "")),
		"condition": condition,
		"price": int(pricing["price"]),
		"seller": str(pricing.get("seller", "")),
		"seller_blurb": str(pricing.get("blurb", "")),
		"provenance": provenance,
		"generation": generation,
		"reserved": false,
		"reserve_rounds_left": 0,
		"deposit": 0,
	}


static func roll_rarity(store_cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	var mythic := float(store_cfg.get("mythic_chance", 0.0))
	if mythic > 0.0 and rng.randf() < mythic:
		return "mythic"
	var weights: Dictionary = store_cfg.get("rarity_weights", {})
	var total := 0.0
	for r in weights:
		if r != "mythic":
			total += float(weights[r])
	if total <= 0.0:
		return "common"
	var pick := rng.randf() * total
	var acc := 0.0
	for r in EconomyConfig.rarity_order():
		if r == "mythic" or not weights.has(r):
			continue
		acc += float(weights[r])
		if pick < acc:
			return r
	return "common"


static func roll_model(store_cfg: Dictionary, rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var types: Array = store_cfg.get("types", [])
	var order := EconomyConfig.rarity_order()
	var idx := order.find(rarity)
	# Walk down the rarity ladder if this store has no models at the rolled rarity.
	while idx >= 0:
		var pool := ClubCatalog.models_by_rarity(str(order[idx]), types)
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
		idx -= 1
	var any := ClubCatalog.lootable_models()
	return any[rng.randi_range(0, any.size() - 1)] if not any.is_empty() else {}


## Condition is drawn around the store's mean with a store-specific spread, independent of
## rarity or price. Clamped to [0.02, 1.0].
static func roll_condition(store_cfg: Dictionary, rng: RandomNumberGenerator) -> float:
	var c: Dictionary = store_cfg.get("condition", {})
	var mean := float(c.get("mean", 0.5))
	var spread := float(c.get("spread", 0.2))
	return clampf(rng.randfn(mean, spread), 0.02, 1.0)


## Asking price by store personality. Returns {price, seller, blurb}.
static func price_for(store_cfg: Dictionary, model: Dictionary, condition: float, rng: RandomNumberGenerator) -> Dictionary:
	var fair := EconomyConfig.fair_value(model, condition)
	var p: Dictionary = store_cfg.get("pricing", {})
	var mode := str(p.get("mode", "fair_range"))
	var frac: Array = p.get("fair_fraction", [0.8, 1.2])
	var price := 0.0
	var seller := ""
	var blurb := ""
	match mode:
		"tag":
			# A volunteer with a price gun: the tag tracks type and looks, not rarity. A legendary
			# find gets the same $5-$25 ceiling as a garage-sale 3 wood.
			price = fair * rng.randf_range(float(frac[0]), float(frac[1]))
			var tag_min := float(p.get("tag_min", 5))
			var tag_max := float(p.get("tag_max", 25))
			if bool(p.get("rarity_blind", true)):
				price = clampf(price, tag_min, tag_max)
			else:
				price = maxf(price, tag_min)
		"seller":
			var sellers: Array = p.get("sellers", [])
			var total := 0.0
			for s in sellers:
				total += float(s.get("weight", 1))
			var pick := rng.randf() * total
			var chosen: Dictionary = sellers[0] if not sellers.is_empty() else {"fraction": frac}
			for s in sellers:
				pick -= float(s.get("weight", 1))
				if pick <= 0.0:
					chosen = s
					break
			var f: Array = chosen.get("fraction", frac)
			price = fair * rng.randf_range(float(f[0]), float(f[1]))
			seller = str(chosen.get("name", ""))
			blurb = str(chosen.get("blurb", ""))
		_:
			price = fair * rng.randf_range(float(frac[0]), float(frac[1]))
			if rng.randf() < float(p.get("underprice_chance", 0.0)):
				var uf: Array = p.get("underprice_fraction", [0.4, 0.7])
				price = fair * rng.randf_range(float(uf[0]), float(uf[1]))
	return {"price": maxi(1, int(round(price))), "seller": seller, "blurb": blurb}
