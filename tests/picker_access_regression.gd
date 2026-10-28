extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func run() -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Picker access", Vector2i(400,400))
	life.business = CourseBusiness.create()
	life.business.built = {"driving_range":1}
	life.business.placements = {"driving_range":{"pos":Vector2.ZERO,"rot":0.0}}
	life.business.staff = {"range_attendant":1}
	var built := FacilityBuilder.build([{"type":"driving_range","level":1,"pos":Vector2.ZERO,"rot":0.0}],func(_p):return 0.0,false,true)
	root.add_child(built)
	life.facilities = built
	life.refresh()
	var worker: ClubLife.Walker
	for p: ClubLife.Walker in life._staff:
		if p.data.has("picker"): worker = p
	check(worker != null, "Range attendant has no pickup cart")
	if worker != null:
		var picker: ClubLife.Walker = worker.data["picker"]
		var door := life._cart_door(picker,0)
		check(life._walker_vehicle_clear(worker,door,door), "Trailer footprint blocks the driver's doorway")
		check(life._vehicle_seat(picker,0) == ClubLife.SEATS[0], "Picker driver is not seated at the wheel")
		worker.data["pick_at"] = 0.0
		var boarded := false
		var finished := false
		for tick in range(8000):
			life._spawn_wait = 1e9
			life._process(0.05)
			var stage := str(worker.data.get("pick",""))
			if stage == "sweep" and not boarded:
				boarded = worker.riding and life._manned(picker)
				picker.path.clear()
			if boarded and stage == "" and float(worker.data.get("pick_at",0)) > life._clock:
				finished = true
				break
			if tick % 100 == 0: await process_frame
		check(boarded, "Attendant never reached and boarded the caged picker")
		check(finished and not worker.riding, "Attendant could not exit and empty the picker")
		print("PICKER ACCESS boarded=",boarded," finished=",finished," time=",life._clock," stage=",worker.data.get("pick")," path=",worker.path)
	life.clear()
	life.queue_free()
	built.queue_free()
	await process_frame
	print("PICKER ACCESS: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
