extends SceneTree
const FLAG = preload("res://assets/world_flagstick/world_flagstick.tscn")
var flags: Array[Node3D] = []

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,2,6)
	camera.current = true
	for i in range(18):
		var flag := FLAG.instantiate() as Node3D
		flag.position.x = 200.0*i
		root.add_child(flag)
		flag._update_lod(true)
		flags.append(flag)
	var active := 0
	for flag in flags:
		if flag.is_cloth_simulating():
			active += 1
	var original_count := root.find_children("*","",true,false).size()
	var started := Time.get_ticks_usec()
	for i in range(240):
		await physics_frame
	var milliseconds := (Time.get_ticks_usec()-started)/1000.0
	assert(active==1,"Distant flags are running physics")
	assert(root.find_children("*","",true,false).size()==original_count,"Node count grew while flags ran")
	for flag in flags:
		if not flag.is_cloth_simulating():
			assert(flag.cloth.process_mode==Node.PROCESS_MODE_DISABLED)
	# Cup changes also need to work while this flag's physics is suspended.
	flags[1].place_in_cup(Vector3(220,3,0))
	for i in range(3):
		await physics_frame
	assert(not flags[1].is_cloth_simulating())
	camera.position = Vector3(220,5,5)
	flags[1]._update_lod(true)
	for i in range(30):
		await physics_frame
	var pinned: Vector3 = flags[1].cloth.get_point_transform(0)
	print("Relocated suspended flag pin: ",pinned)
	if pinned.distance_to(Vector3(220.015,4.95,0))>=0.012:
		printerr("A suspended flag failed to relocate")
		quit(1)
		return
	print("BUDGET CHECK: PASS; 18 flags, %d active soft body, stable %d nodes; 240 fixed physics steps in %.1f ms headless (not a GPU benchmark)." % [active,original_count,milliseconds])
	for flag in flags:
		flag.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	quit()
