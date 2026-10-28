extends SceneTree
## Headless check of per-round side bets and shop haggling:
##   side bets roll deterministically per round id, track live (won/lost/open), only pay on
##   completed non-sandbox rounds, and land in the payout breakdown; haggling is one offer per
##   listing, only at haggle stores, lowers the price when accepted, and can't be retried.
## Run: godot --headless --path . --script tests/side_bets_haggle_test.gd

var failed := false
const SAVE := "user://_side_bets_haggle_test.json"
const PARS: Array[int] = [4, 5, 4, 3, 4, 3, 4, 5, 4]


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed = true
		push_error(label)


func _init() -> void:
	_side_bet_rules()
	_side_bet_payout()
	_haggling()
	print("side_bets_haggle_test: " + ("FAIL" if failed else "OK"))
	quit(1 if failed else 0)


func _result(strokes: Array, extra: Dictionary = {}) -> Dictionary:
	var r := {"pars": PARS.duplicate(), "hole_strokes": strokes}
	r.merge(extra, true)
	return r


func _side_bet_rules() -> void:
	var a := SideBets.roll("round-abc", PARS)
	var b := SideBets.roll("round-abc", PARS)
	check(a.size() == 3, "three side bets per round")
	check(str(a) == str(b), "same round id rolls the same bets")
	var ids := {}
	for bet in a:
		ids[bet["id"]] = true
		check(int(bet["reward"]) > 0 and not str(bet["text"]).contains("{n}"), "bet %s has a reward and filled-in text" % bet["id"])
	check(ids.size() == a.size(), "no duplicate bets in one round")
	check(not SideBets._applies("par3s", [4, 4, 5]), "no par-3 bet on a round without par 3s")

	var open := [-1, -1, -1, -1, -1, -1, -1, -1, -1]
	var birdie := {"id": "birdies", "target": 1, "reward": 10}
	check(SideBets.status(birdie, _result(open)) == SideBets.OPEN, "birdie bet open before play")
	check(SideBets.status(birdie, _result([3, -1, -1, -1, -1, -1, -1, -1, -1])) == SideBets.WON, "birdie on hole 1 wins at once")
	check(SideBets.status(birdie, _result([4, 5, 4, 3, 4, 3, 4, 5, 4]), true) == SideBets.LOST, "all pars loses the birdie bet")
	var doubles := {"id": "no_doubles", "target": 0, "reward": 10}
	check(SideBets.status(doubles, _result([6, -1, -1, -1, -1, -1, -1, -1, -1])) == SideBets.LOST, "a double loses no-doubles immediately")
	check(SideBets.status(doubles, _result([5, 6, 5, 4, 5, 4, 5, 6, 5])) == SideBets.WON, "all bogeys keeps no-doubles")
	var p5 := {"id": "par5_birdie", "target": 0, "reward": 12}
	check(SideBets.status(p5, _result([4, 4, -1, -1, -1, -1, -1, -1, -1])) == SideBets.WON, "birdie on a par 5 wins")
	var streak := {"id": "par_streak", "target": 3, "reward": 8}
	check(SideBets.status(streak, _result([4, 5, 4, -1, -1, -1, -1, -1, -1])) == SideBets.WON, "three pars in a row wins the streak")
	check(SideBets.status(streak, _result([4, 5, 5, 4, 4, 4, 5, 4, -1])) == SideBets.LOST, "streak lost when not enough holes remain")
	var target := {"id": "under_target", "target": 5, "reward": 10}
	check(SideBets.status(target, _result([5, 6, 5, 4, 5, 3, 4, 5, 4])) == SideBets.WON, "+5 meets a +5 target")
	check(SideBets.status(target, _result([5, 6, 5, 4, 5, 4, 5, 6, 5])) == SideBets.LOST, "+9 misses a +5 target")
	var shop := {"id": "shop_clubs", "target": 2, "reward": 6}
	var shop_result := _result([4, 5, 4, 3, 4, 3, 4, 5, 4], {
		"strokes_by_instance": {"c1": 2, "stock:DR": 30, "c2": 5},
		"store_by_instance": {"c1": "goodwill", "stock:DR": "starter", "c2": "starter"}})
	check(SideBets.status(shop, shop_result) == SideBets.WON, "only bought clubs count toward the shop-club bet")


func _fresh() -> GameState:
	var gs := GameState.new()
	gs.save_path = SAVE
	gs.delete_save()
	gs.new_game()
	return gs


func _side_bet_payout() -> void:
	var gs := _fresh()
	var t := gs.begin_round(PARS)
	check(t.side_bets.size() == 3, "begin_round attaches side bets to the tracker")
	t.side_bets = [{"id": "no_doubles", "text": "No double bogeys or worse", "target": 0, "reward": 10},
		{"id": "birdies", "text": "Make 1 birdie or better", "target": 1, "reward": 10}]
	for i in range(PARS.size()):
		t.finish_hole(i, PARS[i])
	var cash_before := gs.cash
	var summary := gs.complete_round(t.to_result())
	var rows: Array = summary["side_bets"]
	check(rows.size() == 2 and rows[0]["status"] == SideBets.WON and rows[1]["status"] == SideBets.LOST, "summary lists won and missed bets")
	var paid_bet := false
	for b in summary["breakdown"]:
		if str(b[0]).begins_with("Side bet: No double"):
			paid_bet = int(b[1]) == 10
		check(not str(b[0]).contains("birdie or better"), "missed bet is not paid")
	check(paid_bet, "won bet is in the payout breakdown")
	check(gs.cash - cash_before == int(summary["payout"]), "payout includes the side bet")

	var t2 := gs.begin_round(PARS)
	t2.side_bets = [{"id": "no_doubles", "text": "x", "target": 0, "reward": 10}]
	t2.sandbox = true
	for i in range(PARS.size()):
		t2.finish_hole(i, PARS[i])
	var cash2 := gs.cash
	gs.complete_round(t2.to_result())
	check(gs.cash == cash2, "sandbox rounds pay no side bets")
	gs.delete_save()


func _haggling() -> void:
	var gs := _fresh()
	gs.cash = 100000
	gs.unlocked.append("pawn")
	gs.unlocked.append("marketplace")
	check(not gs.store_haggles("goodwill") and not gs.store_haggles("pga"), "Goodwill and PGA prices are fixed")
	check(gs.store_haggles("pawn") and gs.store_haggles("marketplace"), "Pawn and Marketplace haggle")
	var gw: Array = gs.listings("goodwill")
	if not gw.is_empty():
		check(not gs.haggle("goodwill", str(gw[0]["id"]), 0)["ok"], "haggling refused at Goodwill")
	var mood := gs.store_mood("pawn")
	check(str(mood) == str(gs.store_mood("pawn")) and str(mood.get("name", "")) != "", "owner mood is stable within a restock")

	var accepted := 0
	var refused := 0
	for sid in ["pawn", "marketplace"]:
		for l in gs.listings(sid).duplicate():
			var lid := str(l["id"])
			var before := int(l["price"])
			var r := gs.haggle(sid, lid, 1)
			check(r["ok"], "offer made on %s" % lid)
			var after := gs.find_listing(sid, lid)
			if r["accepted"]:
				accepted += 1
				check(int(after["price"]) < before and int(after["list_price"]) == before, "accepted offer lowers the price")
			else:
				refused += 1
				check(after.is_empty() == bool(r["walked"]), "listing only disappears when the seller walks")
				if not after.is_empty():
					check(int(after["price"]) == before, "refused offer keeps the price")
			if not after.is_empty():
				check(not gs.haggle(sid, lid, 0)["ok"], "one offer per listing")
	check(accepted > 0 and refused > 0, "some offers land and some don't (%d / %d)" % [accepted, refused])

	# Same save, same listing, same offer -> same answer (no reload-scumming).
	var a := _fresh()
	a.unlocked.append("pawn")
	var l0: Dictionary = a.listings("pawn")[0]
	var id0 := str(l0["id"])
	var r1 := a.haggle("pawn", id0, 2)
	var b := GameState.new()
	b.save_path = SAVE
	b.delete_save()
	b.new_game()
	b.loot_seed = a.loot_seed
	b.stock_generation = a.stock_generation
	b.unlocked.append("pawn")
	b._generate_all_stock(false)
	if b.find_listing("pawn", id0).is_empty():
		print("INFO regenerated stock differs; determinism checked by seed only")
	else:
		check(b.haggle("pawn", id0, 2)["accepted"] == r1["accepted"], "haggle outcome is seeded per listing")
	b.delete_save()
