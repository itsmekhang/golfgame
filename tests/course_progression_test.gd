extends SceneTree
## Drives the real course scene (headless) through the progression layer: a fresh save,
## the starter bag on the tee, strokes recorded per club, a short round holed out, the
## reward applied once and persisted, the clubhouse summary shown, then a Grenade sandbox
## round that earns nothing. Run:
##   godot --headless --path . --script tests/course_progression_test.gd

var failed := false
const SAVE := "user://_course_progression_test.json"
var gs: GameState
var course: Node3D


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed = true
		push_error(label)


func _init() -> void:
	call_deferred("run")


func wait_frames(n: int) -> void:
	for i in range(n):
		await process_frame


func wait_until(pred: Callable, max_seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not pred.call():
		if Time.get_ticks_msec() - t0 > max_seconds * 1000.0:
			return false
		await process_frame
	return true


func hole_out(strokes_taken: int, club_index: int) -> void:
	course.club_index = club_index
	for i in range(strokes_taken):
		course.tracker.record_stroke(course._current_club())
	course.strokes = strokes_taken
	course._sync_round_in_progress()
	course._on_ball_holed(Vector3.ZERO)


func run() -> void:
	AdminAccess.set_override(false)
	# Two-hole rounds keep this test short; the rule scales targets with round length.
	EconomyConfig.data()["round"]["holes_per_round"] = 2
	gs = GameState.new()
	gs.save_path = SAVE
	gs.delete_save()
	gs.new_game()
	root.add_child(gs)

	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	var ready := await wait_until(func(): return course.ball != null and not course._transitioning, 240.0)
	check(ready, "course finished loading")
	if not ready:
		quit(1)
		return
	check(course.hub != null and not course.hub.is_open(), "clubhouse hub exists and starts closed")
	check(course.tracker != null and course.tracker.holes() == 2, "round tracker started for a 2-hole round")
	check(course.round_holes() == 2, "round length follows the config")
	check(Clubs.bag().size() == 14 and course._current_club().is_starter, "tee shot uses the loaner bag")
	check(course.hud.cash_label.text == "60", "HUD shows the starting cash (%s)" % course.hud.cash_label.text)
	check(not course.hud.sandbox_label.visible, "no sandbox banner with a legal bag")

	# Tab opens the clubhouse, Tab again closes it.
	var ev := InputEventAction.new()
	ev.action = "hub_toggle"
	ev.pressed = true
	course._unhandled_input(ev)
	check(course.hub.is_open(), "Tab opens the clubhouse")
	course._unhandled_input(ev)
	check(not course.hub.is_open(), "Tab closes the clubhouse")

	# Buy one Goodwill club and equip it, then play the round with it.
	var l: Dictionary = gs.listings("goodwill")[0]
	var r := gs.buy("goodwill", str(l["id"]))
	check(r["ok"], "bought a Goodwill club from the tee")
	check(gs.equip(str(r["instance_id"]))["ok"], "equipped it (round has no strokes yet)")
	var bought_idx := -1
	for i in range(Clubs.bag().size()):
		if Clubs.bag()[i].instance_id == str(r["instance_id"]):
			bought_idx = i
	check(bought_idx >= 0, "purchased club is in the bag")

	# A shot with a real modifier-bearing club produces sane launch numbers.
	var sp: Dictionary = course._shot_params(Clubs.bag()[0], 1.0, Vector2.ZERO, PhysicsEnums.SurfaceType.FAIRWAY, Vector3.FORWARD)
	check(sp["speed_mph"] > 140.0 and sp["speed_mph"] < 175.0, "driver ball speed stays in a sane band (%.1f mph)" % sp["speed_mph"])
	var jitter_max := 0.0
	for i in range(200):
		jitter_max = maxf(jitter_max, absf(course._dispersion_deg(Clubs.bag()[bought_idx], Vector2(1.0, 1.0))))
	check(jitter_max <= EconomyConfig.modifier_bound("dispersion_deg_max", 2.5) + 0.001, "dispersion is capped (max %.2f deg)" % jitter_max)

	var cash0 := gs.cash
	var gen0 := gs.stock_generation
	hole_out(5, bought_idx)
	check(gs.round_in_progress, "bag locks once strokes are on the card")
	var moved := await wait_until(func(): return course.hole_index == 1 and not course._transitioning, 120.0)
	check(moved, "advanced to hole 2 after holing out")
	hole_out(4, bought_idx)
	var done := await wait_until(func(): return course._round_complete_pending, 30.0)
	check(done, "round completed after the last hole")
	check(gs.rounds_completed == 1, "GameState recorded one completed round")
	check(gs.cash > cash0, "cash went up ($%d -> $%d)" % [cash0, gs.cash])
	check(gs.stock_generation == gen0 + 1, "stores restocked once")
	check(course.hub.is_open(), "clubhouse opened with the round summary")
	check(not gs.round_in_progress, "bag unlocked between rounds")
	var inst := gs.get_club(str(r["instance_id"]))
	check(inst.rounds_played == 1 and inst.strokes == 9, "club history: 1 round, 9 strokes")

	# Reload from disk: same cash, same stock, nothing paid twice.
	var gs2 := GameState.new()
	gs2.save_path = SAVE
	check(gs2.load_game() and gs2.cash == gs.cash and gs2.rounds_completed == 1, "reload matches (cash $%d, rounds %d)" % [gs2.cash, gs2.rounds_completed])
	check(gs2.listings("goodwill").size() == gs.listings("goodwill").size() and str(gs2.listings("goodwill")[0]["id"]) == str(gs.listings("goodwill")[0]["id"]), "reloaded stock is identical")
	GameState.current = gs

	# Tee off from the hub into a new round.
	course.hub.close()  # summary -> hub
	course.hub.close()  # hub -> tee off (round complete pending)
	var teed := await wait_until(func(): return course.hole_index == 0 and not course._transitioning and course.tracker != null, 120.0)
	check(teed, "teed off on a fresh round from the clubhouse")

	# Admin sandbox: the Grenade makes the round a sandbox round; nothing is earned.
	AdminAccess.set_override(true)
	var g := gs.grant_sandbox("grenade_driver")
	check(g["ok"] and gs.equip(str(g["instance_id"]))["ok"], "admin granted and equipped the Grenade")
	course._on_bag_changed()
	check(course.hud.sandbox_label.visible, "HUD warns that an illegal club is equipped")
	course.club_index = 0
	check(course._current_club().illegal_kind == "grenade", "driver slot now holds the Grenade")
	course.skip_swing_animation = true; course._fire_shot(100.0, Vector2.ZERO)
	check(course.tracker.sandbox, "swinging the Grenade flags a sandbox round")
	check(course.ball.velocity.length() > 90.0, "Grenade launches the ball hard (%.1f m/s)" % course.ball.velocity.length())
	await wait_until(func(): return not course.ball.is_moving, 30.0)
	var cash1 := gs.cash
	var gen1 := gs.stock_generation
	var rounds1 := gs.rounds_completed
	course.strokes = 3
	course.tracker.finish_hole(0, 3)
	course._on_ball_holed(Vector3.ZERO)
	await wait_until(func(): return course.hole_index == 1 and not course._transitioning, 120.0)
	hole_out(2, 0)
	await wait_until(func(): return course._round_complete_pending, 30.0)
	check(gs.cash == cash1 and gs.stock_generation == gen1 and gs.rounds_completed == rounds1, "sandbox round: no cash, no restock, no progress")
	check(gs.sandbox_rounds == 1, "sandbox round counted separately")
	AdminAccess.set_override(false)

	gs.delete_save()
	print("course_progression_test: %s" % ("FAILED" if failed else "OK"))
	quit(1 if failed else 0)
