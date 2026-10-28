class_name Progression
extends RefCounted
## Store unlock rules. Each store (after Goodwill) needs two things, in any order:
##   1. N distinct club models bought from the previous store (duplicates don't count), and
##   2. one qualifying round at or better than a score target, played with at least two clubs
##      bought from that previous store, each swung at least once.
## Score targets in economy.json are written for nine holes and scaled to the configured
## round length. Unlocks are permanent once earned.


## Does this finished round satisfy the "qualifying round" half of a store's requirement?
static func round_meets(store_cfg: Dictionary, result: Dictionary) -> Dictionary:
	var req: Dictionary = store_cfg.get("unlock", {}) if store_cfg.get("unlock") != null else {}
	if req.is_empty():
		return {"meets": true, "clubs_used": 0, "reason": "always available", "eligible": true}
	var from_store := str(req.get("from_store", ""))
	var need_clubs := int(req.get("min_clubs_used", 2))
	var target := EconomyConfig.scale_rel_par(float(req.get("score_rel_par_max_per_9", 12)))
	var used := 0
	var by_inst: Dictionary = result.get("strokes_by_instance", {})
	var by_store: Dictionary = result.get("store_by_instance", {})
	for iid in by_inst:
		if int(by_inst[iid]) > 0 and str(by_store.get(iid, "")) == from_store:
			used += 1
	var standard: bool = bool(result.get("complete", false)) and not bool(result.get("sandbox", false)) and not bool(result.get("assisted", false))
	var eligible := standard and used >= need_clubs
	var rel := int(result.get("rel_par", 999))
	var meets := eligible and rel <= target
	var reason := ""
	if not bool(result.get("complete", false)):
		reason = "round not completed"
	elif bool(result.get("sandbox", false)):
		reason = "sandbox round (illegal club used)"
	elif bool(result.get("assisted", false)):
		reason = "mulligan or restart used"
	elif used < need_clubs:
		reason = "used %d/%d %s clubs" % [used, need_clubs, EconomyConfig.store_name(from_store)]
	elif rel > target:
		reason = "%+d, needed %+d or better" % [rel, target]
	return {"meets": meets, "clubs_used": used, "reason": reason, "eligible": eligible, "target": target, "rel_par": rel}


## Everything the objectives screen needs for one store.
static func status(state: GameState, store_cfg: Dictionary) -> Dictionary:
	var id := str(store_cfg.get("id", ""))
	var name := str(store_cfg.get("name", id))
	var unlocked := state.store_unlocked(id)
	var req_v = store_cfg.get("unlock")
	var out := {
		"id": id, "name": name, "unlocked": unlocked, "has_requirement": req_v != null,
		"lines": [], "summary": "", "from_store": "", "from_name": "",
		"distinct_have": 0, "distinct_need": 0, "score_need": 0, "min_clubs": 2,
		"round_met": false, "best_attempt": null,
	}
	if req_v == null:
		out["summary"] = "Open from day one."
		out["lines"] = ["Always available."]
		return out
	var req: Dictionary = req_v
	var from_store := str(req.get("from_store", ""))
	var from_name := EconomyConfig.store_name(from_store)
	var need := int(req.get("distinct_models", 2))
	var have := mini(state.distinct_models_from(from_store), need)
	var target := EconomyConfig.scale_rel_par(float(req.get("score_rel_par_max_per_9", 12)))
	var min_clubs := int(req.get("min_clubs_used", 2))
	var round_met := state.qualified_rounds.has(id)
	var best = state.best_attempts.get(id, null)
	out["from_store"] = from_store
	out["from_name"] = from_name
	out["distinct_have"] = have
	out["distinct_need"] = need
	out["score_need"] = target
	out["min_clubs"] = min_clubs
	out["round_met"] = round_met
	out["best_attempt"] = best
	var line1 := "Buy %s clubs: %d/%d distinct models" % [from_name, have, need]
	var line2 := "Finish a round at %+d or better using %d %s finds (one stroke each)" % [target, min_clubs, from_name]
	if unlocked:
		line1 += "  - done"
		line2 += "  - done"
	else:
		if have >= need:
			line1 += "  - done"
		if round_met:
			line2 += "  - done"
		elif best != null:
			line2 += "  (best eligible round so far: %+d)" % int(best)
	out["lines"] = [line1, line2]
	if unlocked:
		out["summary"] = "Unlocked."
	else:
		out["summary"] = "Buy %s clubs: %d/%d. Finish at %+d or better using %d %s finds." % [from_name, have, need, target, min_clubs, from_name]
	return out


## The single most useful next objective for the HUD / summary screen.
static func next_objective(state: GameState) -> String:
	for s in EconomyConfig.stores():
		var st := status(state, s)
		if not st["unlocked"]:
			return "%s: %s" % [st["name"], st["summary"]]
	return "Every store is unlocked. Hunt the cabinet: %d/7 putters owned." % state.owned_collectible_count()
