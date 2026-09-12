extends SceneTree
const Grid = preload("res://assets/world_flagstick/cloth_grid.gd")
const Flag = preload("res://assets/world_flagstick/world_flagstick.tscn")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures < 20:
			printerr(message)

func _init() -> void:
	call_deferred("run")

func vertices(flag: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in range(Grid.COUNT):
		result.append(flag.cloth.get_point_transform(i))
	return result

func wait_steps(count: int) -> void:
	for i in range(count):
		await physics_frame

func run() -> void:
	print("Physics backend: ",ProjectSettings.get_setting("physics/3d/physics_engine"))
	var flag := Flag.instantiate()
	root.add_child(flag)
	flag.set_wind_velocity(Vector3.ZERO)
	await wait_steps(240)
	var calm := vertices(flag)
	var calm_free := calm[Grid.COUNT-1]
	print("Calm free upper corner: ",calm_free)
	check(calm_free.y < 2.12,"Calm fabric did not sag under gravity")
	var child_count: int = flag.find_children("*","",true,false).size()
	flag.set_wind_velocity(Vector3(4.0,0.0,0.6))
	var frames: Array = []
	var maximum_extension := 0.0
	var largest_edge_ratio := 0.0
	for frame in range(300):
		await physics_frame
		var points := vertices(flag)
		for i in range(points.size()):
			check(points[i].is_finite(),"Non-finite cloth point")
			maximum_extension = maxf(maximum_extension,points[i].distance_to(Vector3(0,2.245,0)))
		for row in range(Grid.ROWS+1):
			var index := row*(Grid.COLUMNS+1)
			var expected: Vector3 = flag.anchor.global_transform*Grid.point(0,row)
			check(points[index].distance_to(expected)<0.012,"Pinned hoist drifted")
			for column in range(Grid.COLUMNS):
				var p := index+column
				largest_edge_ratio = maxf(largest_edge_ratio,points[p].distance_to(points[p+1])/(Grid.WIDTH/Grid.COLUMNS))
		if frame % 30 == 0:
			frames.append(points[Grid.COUNT-1])
	var windy := vertices(flag)
	print("Windy free upper corner: ",windy[Grid.COUNT-1])
	print("Largest structural edge ratio: ",largest_edge_ratio, "; maximum radius: ",maximum_extension)
	check(windy[Grid.COUNT-1].x > 0.30,"Wind did not carry the free edge downwind")
	check(windy[Grid.COUNT-1].y > calm_free.y+0.08,"Wind did not lift the hanging fabric")
	check(largest_edge_ratio < 1.45 and maximum_extension < 0.85,"Cloth exploded or stretched excessively")
	check((frames[-1] as Vector3).distance_to(frames[-3])>0.001,"Windy cloth stopped responding")
	check(flag.find_children("*","",true,false).size()==child_count,"Cloth update accumulated nodes")
	flag.set_wind_velocity(Vector3(-4.0,0.0,-1.0))
	await wait_steps(300)
	var reversed := vertices(flag)
	print("Reversed wind upper corner: ",reversed[Grid.COUNT-1])
	check(reversed[Grid.COUNT-1].x < -0.25,"Cloth did not follow a reversed wind")
	# Distance gating must remove the soft body from physics, not merely hide it.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(0,2,200)
	flag._update_lod(true)
	print("Far switch: ",flag.is_cloth_simulating())
	check(not flag.is_cloth_simulating() and flag.cloth.process_mode==Node.PROCESS_MODE_DISABLED,"Distant cloth is still simulating")
	check(flag.distant.visible and not flag.cloth.visible,"Distance fallback did not replace the simulated surface")
	camera.position = Vector3(0,2,5)
	flag._update_lod(true)
	await wait_steps(90)
	print("Near switch: ",flag.is_cloth_simulating())
	check(flag.is_cloth_simulating() and flag.cloth.visible,"Cloth did not wake near the camera")
	# Relocation and the user's cup depth: foot is 12 cm below a 3 m green.
	flag.place_in_cup(Vector3(10,3,-7),0.12)
	check(flag.global_position.is_equal_approx(Vector3(10,2.88,-7)),"Cup placement offset is wrong")
	await wait_steps(120)
	var moved := vertices(flag)
	for row in range(Grid.ROWS+1):
		var expected: Vector3 = flag.anchor.global_transform*Grid.point(0,row)
		check(moved[row*(Grid.COLUMNS+1)].distance_to(expected)<0.012,"Pin attachment broke after moving to another cup")
	check(absf(flag.pole_body.get_child(0).shape.radius-0.009)<0.000001,"Pole collision diameter is wrong")
	flag.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	print("CLOTH VALIDATION: %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	quit(0 if failures==0 else 1)
