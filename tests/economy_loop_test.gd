extends SceneTree
## Headless check of the progression / shop / economy loop without the 3D course:
##   fresh player -> Goodwill purchase -> equip -> simulated round -> reward -> save -> reload
##   (no reroll, no double reward) -> first store unlock through valid play -> resale, reserve,
##   collection records, and the admin sandbox never leaking into normal progression.
## Run: godot --headless --path . --script tests/economy_loop_test.gd

var failed := false
const SAVE := "user://_economy_loop_test.json"
const PARS: Array[int] = [4, 5, 4, 3, 4, 3, 4, 5, 4]


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed = true
		push_error(label)


func fresh_state() -> GameState:
	var gs := GameState.new()
	gs.save_path = SAVE
	gs.delete_save()
	gs.new_game()
	return gs


func reload_state() -> GameState:
	var gs := GameState.new()
	gs.save_path = SAVE
	check(gs.load_game(), "save file reloads")
	return gs


func listing_ids(gs: GameState, store: String) -> Array:
	var out: Array = []
	for l in gs.listings(store):
		out.append(str(l["id"]))
	return out


## Simulate a finished round: `strokes_with` maps instance id -> swings, hole scores are
## spread so the total lands exactly at `rel_par` over par.
func play_round(gs: GameState, rel_par: int, strokes_with: Dictionary, sandbox_club: Clubs.Club = null, assisted := false) -> Dictionary:
	var t := gs.begin_round(PARS)
	gs.round_in_progress = true
	for iid in strokes_with:
		var inst := gs.get_club(iid)
		var club := Clubs.make_club(str(inst.model().get("slot", "DR")) if str(inst.model().get("slot", "")) != "IRONS" else "7I", inst)
		for i in range(int(strokes_with[iid])):
			t.record_stroke(club)
	if sandbox_club != null:
		t.record_stroke(sandbox_club)
	if assisted:
		t.record_stroke(Clubs.stock_bag()[0])
		t.undo_last_stroke()
	var extra := rel_par
	for h in range(PARS.size()):
		var s: int = PARS[h]
		if extra > 0:
			var add: int = mini(extra, 3)
			s += add
			extra -= add
		elif extra < 0:
			s -= 1
			extra += 1
		t.finish_hole(h, s)
	var result := t.to_result()
	check(result["rel_par"] == rel_par, "simulated round is %+d" % rel_par)
	return gs.complete_round(result)


func _init() -> void:
	call_deferred("run")


func run() -> void:
	AdminAccess.set_override(false)
	# ---- 1. fresh player
	var gs := fresh_state()
	check(gs.cash == EconomyConfig.starting_cash(), "starts with $%d" % EconomyConfig.starting_cash())
	check(gs.bag_clubs().size() == 14, "starter bag has 14 clubs (got %d)" % gs.bag_clubs().size())
	var all_starter := true
	for c in gs.bag_clubs():
		if not c.is_starter:
			all_starter = false
	check(all_starter, "starter bag is all loaners")
	check(gs.store_unlocked("goodwill") and not gs.store_unlocked("pawn") and not gs.store_unlocked("marketplace") and not gs.store_unlocked("pga"), "only Goodwill is open at the start")
	var gw := gs.listings("goodwill")
	check(gw.size() == int(EconomyConfig.store("goodwill").get("listings", 8)), "Goodwill has a full shelf")
	var price_ok := true
	for l in gw:
		if int(l["price"]) < 5 or int(l["price"]) > 25:
			price_ok = false
	check(price_ok, "Goodwill tags are $5-$25")
	check(Clubs.bag().size() == 14, "Clubs.bag() serves the equipped bag")

	# ---- 2. reload never rerolls stock
	var ids0 := listing_ids(gs, "goodwill")
	var pawn0 := listing_ids(gs, "pawn")
	var gs2 := reload_state()
	check(listing_ids(gs2, "goodwill") == ids0 and listing_ids(gs2, "pawn") == pawn0, "reload keeps the same stock")
	check(gs2.cash == gs.cash, "reload keeps cash")
	gs = gs2

	# ---- 3. buy two distinct Goodwill models (plus a duplicate model if one exists)
	var by_model := {}
	for l in gs.listings("goodwill"):
		var mid := str(l["model_id"])
		if not by_model.has(mid):
			by_model[mid] = []
		by_model[mid].append(l)
	var bought: Array = []
	var models_seen: Array = []
	for mid in by_model:
		if bought.size() >= 2:
			break
		var l: Dictionary = by_model[mid][0]
		var r := gs.buy("goodwill", str(l["id"]))
		check(r["ok"], "bought %s for $%d (%s)" % [mid, int(l["price"]), r["error"]])
		if r["ok"]:
			bought.append(str(r["instance_id"]))
			models_seen.append(mid)
	check(bought.size() == 2, "two Goodwill purchases made")
	check(gs.distinct_models_from("goodwill") == 2, "distinct Goodwill models = 2")
	check(gs.cash < EconomyConfig.starting_cash(), "cash went down")
	check(gs.listings("goodwill").size() == gw.size() - 2, "bought listings left the shelf")
	for iid in bought:
		var inst := gs.get_club(iid)
		check(inst != null and inst.source_store == "goodwill" and inst.purchase_price > 0, "instance %s records its source and price" % iid)
		check(gs.is_discovered(inst.model_id), "%s is recorded as discovered" % inst.model_id)
	# a duplicate of an already-bought model must not raise the distinct count
	var dup_found := false
	for l in gs.listings("goodwill"):
		if models_seen.has(str(l["model_id"])) and gs.cash >= int(l["price"]):
			var r := gs.buy("goodwill", str(l["id"]))
			if r["ok"]:
				dup_found = true
				bought.append(str(r["instance_id"]))
			break
	if dup_found:
		check(gs.distinct_models_from("goodwill") == 2, "duplicate copy doesn't count as a new distinct model")
	else:
		print("INFO no affordable duplicate on this shelf; distinct-duplicate rule checked by count only")

	# ---- 4. equip the finds
	for iid in bought.slice(0, 2):
		var r := gs.equip(iid)
		check(r["ok"], "equip %s (%s)" % [iid, r["error"]])
	var equipped_count := 0
	for c in gs.bag_clubs():
		if bought.has(c.instance_id):
			equipped_count += 1
	check(equipped_count >= 1, "equipped finds show up in the bag")
	gs.round_in_progress = true
	check(not gs.equip(bought[0])["ok"], "bag is locked mid-round")
	gs.round_in_progress = false

	# ---- 5. a qualifying round at +12 using both Goodwill finds
	var gen_before := gs.stock_generation
	var ids_before := listing_ids(gs, "goodwill")
	var cash_before := gs.cash
	var strokes := {}
	strokes[bought[0]] = 5
	strokes[bought[1]] = 3
	var summary := play_round(gs, 12, strokes)
	check(summary["payout"] >= 35, "round paid $%d (>= $35)" % summary["payout"])
	check(gs.cash == cash_before + int(summary["payout"]), "cash matches the payout")
	check(gs.rounds_completed == 1, "rounds_completed = 1")
	check(gs.store_unlocked("pawn"), "pawn shop unlocked by 2 distinct buys + a +12 round with two Goodwill clubs")
	check(summary["unlocked_now"].has("pawn"), "summary announces the unlock")
	check(gs.stock_generation == gen_before + 1 and listing_ids(gs, "goodwill") != ids_before, "stores restocked after the round")
	check(gs.get_club(bought[0]).rounds_played == 1 and gs.get_club(bought[0]).strokes == 5, "club play history recorded")
	check(gs.best_round.get("rel_par", 99) == 12, "personal best recorded")

	# ---- 6. same round can't pay twice
	var cash_after := gs.cash
	var again := gs.complete_round({"round_id": summary["round_id"], "pars": PARS, "hole_strokes": [], "total": 48, "par": 36, "rel_par": 12, "complete": true, "sandbox": false, "assisted": false, "strokes_by_instance": {}, "store_by_instance": {}})
	check(again["already_processed"] and gs.cash == cash_after and gs.rounds_completed == 1, "duplicate round completion is ignored")

	# ---- 7. reload keeps the unlock and the restocked shelf
	var ids_after := listing_ids(gs, "goodwill")
	gs = reload_state()
	check(gs.store_unlocked("pawn"), "unlock persists across reload")
	check(listing_ids(gs, "goodwill") == ids_after, "restocked shelf persists across reload")
	check(gs.processed_round_ids.has(summary["round_id"]), "processed round id persists")

	# ---- 8. a round that fails the club-use rule does not qualify
	var strokes_one := {}
	strokes_one[bought[0]] = 4
	var s2 := play_round(gs, 6, strokes_one)
	check(not gs.qualified_rounds.has("marketplace"), "+6 round with only one pawn club (none) can't qualify for Marketplace")
	check(s2["payout"] > 0, "non-qualifying rounds still pay")
	# an assisted (mulligan) round pays but neither qualifies nor sets a record
	var best_before: int = gs.best_round["rel_par"]
	var s3 := play_round(gs, -2, strokes, null, true)
	check(s3["payout"] > 0 and gs.best_round["rel_par"] == best_before, "mulligan round pays but sets no record")

	# ---- 9. resale
	var inst0 := gs.get_club(bought[0])
	var offer := gs.sell_offer(bought[0])
	var fair := inst0.fair_value()
	check(offer >= int(floor(fair * 0.5)) and offer <= int(ceil(fair * 0.65)), "resale offer $%d is 50-65%% of fair $%d" % [offer, fair])
	var starter_id := ""
	for id in gs.clubs:
		if gs.clubs[id].is_starter():
			starter_id = id
			break
	check(not gs.can_sell(starter_id)["ok"], "loaners can't be sold")
	var was_equipped := gs.is_equipped(bought[0])
	var model_sold := inst0.model_id
	var cash_pre_sale := gs.cash
	var sr := gs.sell(bought[0])
	check(sr["ok"] and gs.cash == cash_pre_sale + offer, "sold for the quoted offer")
	check(gs.get_club(bought[0]) == null, "sold club is gone")
	check(gs.is_discovered(model_sold), "discovery record survives the sale")
	if was_equipped:
		var key := ClubCatalog.bag_key(ClubCatalog.model(model_sold))
		# The hybrid slot has no loaner, so selling the only hybrid may leave it empty (by design).
		if key == "HY" and gs.equipped_id(key) == "":
			check(true, "selling the only hybrid leaves its optional slot empty")
		else:
			check(gs.equipped_id(key) != "" and gs.get_club(gs.equipped_id(key)) != null, "selling an equipped club swaps a replacement in")
	check(gs.bag_clubs().size() >= 13, "bag still playable after the sale")

	# ---- 10. reserve survives two restocks, then expires
	var target: Dictionary = gs.listings("goodwill")[0]
	var cash_pre := gs.cash
	var rr := gs.reserve("goodwill", str(target["id"]))
	check(rr["ok"] and gs.cash == cash_pre - int(rr["deposit"]), "reservation takes a deposit")
	play_round(gs, 20, {})
	check(not gs.find_listing("goodwill", str(target["id"])).is_empty(), "reserved listing survives restock 1")
	play_round(gs, 20, {})
	check(not gs.find_listing("goodwill", str(target["id"])).is_empty(), "reserved listing survives restock 2")
	var held := gs.find_listing("goodwill", str(target["id"]))
	var due := int(held["price"]) - int(held["deposit"])
	if gs.cash >= due:
		var cash_b := gs.cash
		var br := gs.buy("goodwill", str(target["id"]))
		check(br["ok"] and gs.cash == cash_b - due, "deposit credited toward the purchase")
	else:
		play_round(gs, 20, {})
		check(gs.find_listing("goodwill", str(target["id"])).is_empty(), "reserved listing expires after its extra rounds")

	# ---- 11. admin sandbox
	check(not gs.grant_sandbox("grenade_driver")["ok"], "sandbox grants refused without admin")
	AdminAccess.set_override(true)
	var g := gs.grant_sandbox("grenade_driver")
	check(g["ok"], "admin can grant the Grenade driver")
	var grenade := gs.get_club(str(g["instance_id"]))
	check(grenade != null and not gs.clubs.has(grenade.id), "sandbox gear is kept out of the owned inventory")
	check(not gs.can_sell(grenade.id)["ok"], "sandbox gear can't be sold")
	check(gs.equip(grenade.id)["ok"], "admin can equip the Grenade")
	var gclub: Clubs.Club = null
	for c in gs.bag_clubs():
		if c.illegal:
			gclub = c
	check(gclub != null and gclub.illegal_kind == "grenade" and gclub.ball_speed_mph > 200.0, "Grenade club is flagged illegal with its own launch numbers")
	var rounds_pre := gs.rounds_completed
	var gen_pre := gs.stock_generation
	var cash_pre_sb := gs.cash
	var best_pre: int = gs.best_round["rel_par"]
	var sb := play_round(gs, -8, {}, gclub)
	check(sb["sandbox"] and sb["payout"] == 0, "sandbox round pays nothing")
	check(gs.cash == cash_pre_sb and gs.rounds_completed == rounds_pre and gs.stock_generation == gen_pre and gs.best_round["rel_par"] == best_pre, "sandbox round grants no money, progress, restock or record")
	check(not gs.store_unlocked("marketplace"), "sandbox -8 didn't unlock anything")
	AdminAccess.set_override(false)
	var legal_only := true
	for c in gs.bag_clubs():
		if c.illegal:
			legal_only = false
	check(legal_only, "without admin the bag drops sandbox gear")
	var ap := gs.grant_sandbox("auto_putt_9000")
	check(not ap["ok"], "Auto-Putt can't be granted without admin")
	# collectible catalog excludes it
	var seven := ClubCatalog.collectible_putters()
	check(seven.size() == 7, "exactly seven collectible putters")
	var has_auto := false
	for m in seven:
		if str(m["id"]) == "auto_putt_9000":
			has_auto = true
	check(not has_auto, "Auto-Putt 9000 is not an eighth collectible")

	# ---- 11b. grant & equip all sandbox gear in one call
	check(not gs.grant_and_equip_all_sandbox()["ok"], "bulk grant refused without admin")
	AdminAccess.set_override(true)
	check(gs.grant_and_equip_all_sandbox()["ok"], "admin can bulk grant and equip")
	var illegal_models := ClubCatalog.illegal_models()
	var all_granted := true
	for m in illegal_models:
		var found := false
		for inst in gs.sandbox_instances():
			if inst.model_id == str(m["id"]):
				found = true
		if not found:
			all_granted = false
	check(all_granted, "every illegal model was granted")
	var slots_filled := true
	for m in illegal_models:
		var mid := str(m["id"])
		var key := ClubCatalog.bag_key(m)
		var eq := gs.get_club(gs.equipped_id(key))
		if eq == null or eq.model_id != mid:
			var shares_slot := false
			for other in illegal_models:
				if str(other["id"]) != mid and ClubCatalog.bag_key(other) == key:
					shares_slot = true
			if not shares_slot:
				slots_filled = false
	check(slots_filled, "every illegal model with a unique slot ended up equipped")
	AdminAccess.set_override(false)

	# ---- 12. loot never contains illegal or loaner models; every store can roll every putter
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var leak := false
	var goodwill_tag_ok := true
	var mythic_hits := 0
	var n := 60000
	for s in EconomyConfig.stores():
		for i in range(n if str(s["id"]) == "goodwill" else 5000):
			var l := LootGenerator.generate_listing(s, rng, 0, i)
			var m := ClubCatalog.model(str(l["model_id"]))
			if ClubCatalog.is_illegal(m) or ClubCatalog.is_starter(m):
				leak = true
			if str(s["id"]) == "goodwill":
				if int(l["price"]) < 5 or int(l["price"]) > 25:
					goodwill_tag_ok = false
				if str(m.get("id", "")) == "scotty_grail":
					mythic_hits += 1
	check(not leak, "no illegal or loaner club ever appears in loot")
	check(goodwill_tag_ok, "Goodwill never tags above $25, even a legendary")
	print("INFO Goodwill Grail hits in %d listings: %d (expected ~%.1f)" % [n, mythic_hits, n * 0.0001])
	for s in EconomyConfig.stores():
		for m in seven:
			var r := str(m["rarity"])
			var chance := float(s.get("mythic_chance", 0.0)) if r == "mythic" else float(s.get("rarity_weights", {}).get(r, 0.0))
			var in_pool := ClubCatalog.models_by_rarity(r, s.get("types", [])).has(m)
			check(chance > 0.0 and in_pool, "%s can produce %s" % [s["name"], m["name"]])
	var expected_mythic := {"goodwill": 0.0001, "pawn": 0.0005, "marketplace": 0.0015, "pga": 0.003}
	for s in EconomyConfig.stores():
		check(is_equal_approx(float(s["mythic_chance"]), expected_mythic[str(s["id"])]), "%s Scotty chance is %.2f%%" % [s["name"], expected_mythic[str(s["id"])] * 100.0])

	gs.delete_save()
	print("economy_loop_test: %s" % ("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
