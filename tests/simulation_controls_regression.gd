extends SceneTree
var failed := false
class Counter extends ClubLife:
	var elapsed := 0.0
	var largest_step := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		largest_step = maxf(largest_step, delta)
class Frame extends CourseManager:
	func _ready() -> void:
		set_process(false)
		camera = StudioCamera.new()
		add_child(camera)
		_build_ui()
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func run() -> void:
	var gs := GameState.current
	gs.set_process(false)
	gs.autosave = false
	gs.business = CourseBusiness.create()
	var frame := Frame.new()
	root.add_child(frame)
	var counter := Counter.new()
	frame.add_child(counter)
	counter.set_process(false)
	counter.course = PaintedCourse.create("Clock test", Vector2i(128,128))
	frame._life = counter
	gs.begin_manager_simulation()
	var time_scale := Engine.time_scale
	for tick in range(60): frame._advance_simulation(1.0 / 60.0)
	check(absf(counter.elapsed - 1.0) < 0.001, "1x does not match real time")
	var per_hour := float(EconomyConfig.manager_cfg().get("real_seconds_per_hour",240))
	check(absf(gs.business.hours - 1.0 / per_hour) < 0.00001, "Clock waits for a later accounting tick")
	frame._speed_option.item_selected.emit(0)
	var paused := counter.elapsed
	for tick in range(60): frame._advance_simulation(1.0 / 60.0)
	check(counter.elapsed == paused and counter.animation_speed == 0.0, "Pause failed")
	frame._speed_option.item_selected.emit(4)
	for tick in range(60): frame._advance_simulation(1.0 / 60.0)
	check(absf(counter.elapsed - 9.0) < 0.001, "8x did not advance eight seconds")
	check(absf(gs.business.hours - counter.elapsed / per_hour) < 0.00001, "Clock lags 8x activity before exiting")
	for speed in [2.0,4.0]:
		frame.set_simulation_speed(speed)
		for tick in range(60):
			frame._advance_simulation(1.0 / 60.0)
			check(absf(gs.business.hours - counter.elapsed / per_hour) < 0.00001, "Clock drifts when changing speeds")
	gs.end_manager_simulation()
	check(absf(gs.business.hours - 15.0 / per_hour) < 0.00001, "Exiting double-counted simulated time")
	check(Engine.time_scale == time_scale, "Speed changed camera/menu time")
	gs.begin_manager_simulation()
	var advanced := frame._advance_simulation(4.0)
	check(advanced <= 0.40001 and counter.largest_step <= CourseManager.SIM_STEP + 0.00001, "Slow frame skipped safe substeps")
	gs.end_manager_simulation()
	frame._traffic_option.item_selected.emit(1)
	check(gs.business.traffic_mode == "quiet", "Quiet control failed")
	var quiet := gs.business.traffic_multiplier()
	frame._traffic_option.item_selected.emit(2)
	check(gs.business.traffic_mode == "rush" and gs.business.traffic_multiplier() > quiet * 5, "Rush control failed")
	var restored := CourseBusiness.from_dict(gs.business.to_dict())
	check(restored.traffic_mode == "rush", "Traffic mode was not saved")
	check(CourseBusiness.from_dict({"owned":true}).traffic_mode == "normal", "Legacy save compatibility failed")
	gs.business.traffic_mode = "daily"
	gs.business.hours = 1.0
	var morning := gs.business.traffic_multiplier()
	gs.business.hours = 5.0
	var lunch := gs.business.traffic_multiplier()
	gs.business.hours = 8.0
	check(morning > lunch and gs.business.traffic_multiplier() > lunch, "Daily cycle failed")
	var course := PaintedCourse.create("Traffic fixture",Vector2i(128,128))
	for i in range(3):
		course.holes.append({"tee":Vector2(-40+i*20,30),"pin":Vector2(-40+i*20,-30),"par":3,"bends":[],"curve":false})
	var path := "user://_simulation_controls_test.course.json"
	check(course.save(path) == OK,"Traffic fixture could not be saved")
	var business := CourseBusiness.create()
	business.course_path = path
	business.refresh_course()
	business.accepting_visitors = true
	business.placements = {"clubhouse":{"pos":Vector2.ZERO,"rot":0.0},"parking_lot":{"pos":Vector2(60,0),"rot":0.0}}
	business.built = {"clubhouse":2,"parking_lot":4}
	business.staff = {"shop_clerk":1}
	business.rooms = {"pro_shop":1}
	var normal_rate := float(business.rates()["golfers"])
	var crowd := ClubLife.new()
	crowd.business = business
	crowd.course = course
	var normal_target := crowd._target_groups()
	business.traffic_mode = "quiet"
	var quiet_rate := float(business.rates()["golfers"])
	var quiet_target := crowd._target_groups()
	var quiet_interval := crowd._arrival_interval()
	business.traffic_mode = "rush"
	check(normal_rate > 0.0 and quiet_rate < normal_rate,"Quiet mode did not reduce business demand")
	check(float(business.rates()["golfers"]) >= normal_rate,"Rush mode reduced demand")
	check(crowd._target_groups() > quiet_target and crowd._target_groups() >= normal_target,"Traffic modes do not change crowd size")
	check(crowd._arrival_interval() < quiet_interval,"Rush arrivals are not faster")
	crowd.free()
	DirAccess.remove_absolute(path)
	frame.set_simulation_speed(0.0)
	frame.is_loaded = true
	frame._process(0.016)
	check(frame._clock.text == gs.business.clock_text(),"Displayed clock lags behind when paused")
	if DisplayServer.get_name() != "headless":
		for tick in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/rush_controls_preview.png")
	frame.queue_free()
	await process_frame
	print("SIMULATION CONTROLS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
