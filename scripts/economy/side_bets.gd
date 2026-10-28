class_name SideBets
extends RefCounted
## Per-round side bets: a few small, bonus-paying challenges rolled when a round starts
## (RoundTracker.side_bets), tracked live on the HUD and paid by GameState.complete_round()
## for completed, non-sandbox rounds. The pool, targets and rewards live in
## data/economy.json "side_bets"; targets/rewards marked per_9 scale with the round length.
##
## Each bet is a plain Dictionary {id, text, target, reward} so it survives the save file and
## the round summary unchanged.

const WON := "won"
const LOST := "lost"
const OPEN := "open"


static func cfg() -> Dictionary:
	return EconomyConfig.data().get("side_bets", {})


## Deterministic per round id, so a reload can't reroll the bets for the same round.
static func roll(round_id: String, pars: Array) -> Array:
	var pool: Array = cfg().get("pool", [])
	var count := mini(int(cfg().get("count", 3)), pool.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:side_bets" % round_id)
	var scale := maxf(float(pars.size()) / 9.0, 1.0 / 9.0)
	var candidates: Array = []
	for entry in pool:
		if _applies(str(entry.get("id", "")), pars):
			candidates.append(entry)
	var bets: Array = []
	while bets.size() < count and not candidates.is_empty():
		var entry: Dictionary = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		var target := int(entry.get("target", 0))
		if entry.has("target_per_9"):
			target = maxi(1, int(round(float(entry["target_per_9"]) * scale)))
		if entry.has("rel_par_per_9"):
			target = int(round(float(entry["rel_par_per_9"]) * scale))
		var reward := int(entry.get("reward", 0))
		if bool(entry.get("reward_scales", true)):
			reward = maxi(1, int(round(float(reward) * scale)))
		bets.append({
			"id": str(entry["id"]),
			"text": str(entry.get("text", entry["id"])).replace("{n}", "%+d" % target if entry.has("rel_par_per_9") else str(target)).replace("{s}", "" if target == 1 else "s"),
			"target": target,
			"reward": reward,
		})
	return bets


## A bet about par 3s on a round with no par 3s would be free money (or impossible).
static func _applies(id: String, pars: Array) -> bool:
	match id:
		"par3s":
			return pars.has(3)
		"par5_birdie":
			return pars.has(5)
	return true


## WON / LOST / OPEN for one bet given a round result (complete or in progress -- unplayed
## holes are -1 in hole_strokes). With final = true, anything still open is LOST.
static func status(bet: Dictionary, result: Dictionary, final: bool = false) -> String:
	var s := _status(bet, result)
	return LOST if final and s == OPEN else s


static func _status(bet: Dictionary, result: Dictionary) -> String:
	var pars: Array = result.get("pars", [])
	var strokes: Array = result.get("hole_strokes", [])
	var n := mini(pars.size(), strokes.size())
	var target := int(bet.get("target", 0))
	var played := 0
	for i in range(n):
		if int(strokes[i]) >= 0:
			played += 1
	var remaining := n - played
	match str(bet.get("id", "")):
		"birdies":
			var birdies := 0
			for i in range(n):
				if int(strokes[i]) >= 0 and int(strokes[i]) < int(pars[i]):
					birdies += 1
			if birdies >= target:
				return WON
			return LOST if birdies + remaining < target else OPEN
		"no_doubles":
			for i in range(n):
				if int(strokes[i]) >= 0 and int(strokes[i]) - int(pars[i]) >= 2:
					return LOST
			return WON if remaining == 0 else OPEN
		"par3s":
			var open := false
			for i in range(n):
				if int(pars[i]) != 3:
					continue
				if int(strokes[i]) < 0:
					open = true
				elif int(strokes[i]) > 3:
					return LOST
			return OPEN if open else WON
		"par5_birdie":
			var open := false
			for i in range(n):
				if int(pars[i]) != 5:
					continue
				if int(strokes[i]) < 0:
					open = true
				elif int(strokes[i]) < 5:
					return WON
			return OPEN if open else LOST
		"par_streak":
			var run := 0
			for i in range(n):
				var s := int(strokes[i])
				if s < 0:
					break
				run = run + 1 if s <= int(pars[i]) else 0
				if run >= target:
					return WON
			return LOST if run + remaining < target else OPEN
		"under_target":
			if remaining > 0:
				return OPEN
			var rel := 0
			for i in range(n):
				rel += int(strokes[i]) - int(pars[i])
			return WON if rel <= target else LOST
		"shop_clubs":
			var swings := 0
			var by_inst: Dictionary = result.get("strokes_by_instance", {})
			var by_store: Dictionary = result.get("store_by_instance", {})
			for iid in by_inst:
				if not EconomyConfig.store(str(by_store.get(iid, ""))).is_empty():
					swings += int(by_inst[iid])
			if swings >= target:
				return WON
			return LOST if remaining == 0 else OPEN
	return OPEN


## {text, reward, status} rows for the HUD / summary.
static func rows(bets: Array, result: Dictionary, final: bool = false) -> Array:
	var out: Array = []
	for b in bets:
		out.append({"text": str(b.get("text", "")), "reward": int(b.get("reward", 0)), "status": status(b, result, final)})
	return out
