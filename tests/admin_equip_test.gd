extends SceneTree
## Regression test for GameState.admin_equip(): equip any catalog model (legal or
## illegal) as admin, with no purchase/loot/unlock, preferring an owned copy if one
## exists, else spawning a Mint admin copy. Run: godot --headless --path . --script
## tests/admin_equip_test.gd

var failures := 0


func _init() -> void:
	AdminAccess.set_override(true)
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)
	else:
		print("PASS ", message)


func run() -> void:
	var gs := GameState.new()
	gs.autosave = false
	gs.save_path = "user://admin_equip_test_unused.json"
	gs.delete_save()
	gs.new_game()
	root.add_child(gs)

	# 1. Without admin, admin_equip is refused.
	AdminAccess.set_override(false)
	var refused := gs.admin_equip("loaner_3w")
	check(not refused["ok"], "admin_equip refuses without admin access")
	AdminAccess.set_override(true)

	# 2. A legal loot model the player does not own yet: spawns a Mint admin copy and
	# equips it into the right slot, without touching cash or unlock progress.
	var cash_before := gs.cash
	var r := gs.admin_equip("thrift_titan_460")  # a lootable "driver" model
	check(r["ok"], "admin_equip grants+equips an unowned legal model")
	var equipped := gs.equipped_for_model(ClubCatalog.model("thrift_titan_460"))
	check(equipped != null and equipped.model_id == "thrift_titan_460", "the model is now equipped in its slot")
	check(is_equal_approx(equipped.condition, 1.0), "the spawned admin copy is Mint")
	check(gs.cash == cash_before, "admin_equip never spends cash")

	# 3. Calling it again on the already-equipped model is idempotent (same instance).
	var again := gs.admin_equip("thrift_titan_460")
	check(again["ok"] and str(again.get("instance_id", "")) == "", "second admin_equip call succeeds")  # equip() itself returns no instance_id
	check(gs.equipped_id(ClubCatalog.bag_key(ClubCatalog.model("thrift_titan_460"))) == equipped.id, "re-equipping reuses the same admin instance, not a duplicate")

	# 4. An illegal (sandbox) model still works through the same entry point.
	var illegal_models := ClubCatalog.illegal_models()
	check(not illegal_models.is_empty(), "catalog has illegal models to test with")
	if not illegal_models.is_empty():
		var illegal_id := str(illegal_models[0]["id"])
		var ri := gs.admin_equip(illegal_id)
		check(ri["ok"], "admin_equip works for an illegal model too")
		var eq_illegal := gs.equipped_for_model(ClubCatalog.model(illegal_id))
		check(eq_illegal != null and eq_illegal.model_id == illegal_id, "the illegal model is equipped")
		check(gs.bag_has_illegal(), "bag_has_illegal reflects the equipped illegal club")

	# 5. A model the player genuinely owns (e.g. their starter loaner) is equipped by
	# reusing that real instance -- no new instance is created.
	var owned_before := gs.owned().size()
	var starter: ClubInstance = null
	for inst in gs.owned():
		if inst.is_starter():
			starter = inst
			break
	check(starter != null, "a starter instance exists to test reuse with")
	if starter != null:
		# unequip it first if needed by switching to something else, then admin_equip it back
		var rs := gs.admin_equip(starter.model_id)
		check(rs["ok"], "admin_equip works for an already-owned model")
		check(gs.owned().size() == owned_before, "equipping an owned model creates no new instance")
		check(gs.equipped_id(ClubCatalog.bag_key(starter.model())) == starter.id, "the player's own instance is what gets equipped")

	# 6. Unknown model id is rejected cleanly.
	var bad := gs.admin_equip("does_not_exist")
	check(not bad["ok"], "admin_equip rejects an unknown model id")

	gs.delete_save()
	AdminAccess.clear_override()
	print("ADMIN EQUIP TEST: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
