extends SceneTree

class AudioProbe:
	extends GolfAudio
	var cues: Array = []
	var stingers: Array = []
	func _play_at(streams: Array, _pos: Vector3, _volume_db: float = 0.0) -> void:
		cues.append(streams)
	func _play_stinger(streams: Array, _volume_db: float = 0.0, _delay: float = 0.0) -> void:
		stingers.append(streams)

var failures := 0
func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://audio_regression_unused.json")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func run() -> void:
	var probe := AudioProbe.new()
	root.add_child(probe)
	for entry in [["utility_2u","HY","irons"],["rescue_rookie","HY","hybrid"],["loaner_3w","3W","woods"],["loaner_irons","4I","irons"]]:
		var inst := ClubInstance.create("test",entry[0],1.0,"test",0,0)
		var club := Clubs.make_club(entry[1],inst)
		probe.cues.clear()
		probe.play_shot(club,CourseLayout.SURFACE_TEE,Vector2.ZERO,Vector3.ZERO)
		check(probe.cues.size() == 1 and probe.cues[0] == probe._by_club[entry[2]],"Correct tee impact for " + entry[0])
	var utility := Clubs.make_club("HY",ClubInstance.create("utility","utility_2u",1.0,"test",0,0))
	probe.cues.clear()
	probe.play_shot(utility,PhysicsEnums.SurfaceType.FAIRWAY,Vector2.ZERO,Vector3.ZERO)
	check(probe.cues.size() == 2 and probe.cues[0] == probe._fairway_hits and probe.cues[1] == probe._by_club["irons"],"Utility iron uses iron fairway contact and impact")
	probe.cues.clear()
	probe.stingers.clear()
	var voice := probe._pool_next
	probe.play_grenade(Vector3.ZERO)
	check(probe.cues.is_empty(),"Grenade strike adds no explosion layer")
	check(probe.stingers.is_empty(),"Grenade strike adds no crowd applause")
	check(probe._by_club["driver"].has(probe._pool[voice].stream),"Grenade retains its driver impact")
	await create_timer(0.7).timeout
	check(probe.stingers.is_empty(),"No delayed grenade applause")
	probe.play_crowd_cheer()
	check(probe.stingers.size() == 1 and probe.stingers[0] == probe._crowd_cheer,"Scoring applause remains available")
	probe.queue_free()
	await process_frame
	print("CLUB AUDIO REGRESSION: ","PASS" if failures == 0 else "FAIL"," (",failures," failures)")
	quit(0 if failures == 0 else 1)