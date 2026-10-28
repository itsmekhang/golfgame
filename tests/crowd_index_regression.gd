extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func actor(life: ClubLife, pos: Vector3) -> ClubLife.Walker:
	var w := ClubLife.Walker.new()
	w.node = Node3D.new()
	life.add_child(w.node)
	w.node.position = pos
	return w
func run() -> void:
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 281026
	for i in range(40):
		var v := actor(life,Vector3(rng.randf_range(-40,40),0,rng.randf_range(-40,40)))
		v.node.rotation.y = rng.randf_range(-PI,PI)
		v.data = {"vehicle":true,"half":Vector2(rng.randf_range(0.5,2),rng.randf_range(1,4)),"body_center":Vector3(rng.randf_range(-2,2),0,rng.randf_range(-2,2))}
		life._pool.append(v)
	for i in range(60):
		life._staff.append(actor(life,Vector3(rng.randf_range(-40,40),0,rng.randf_range(-40,40))))
	var walker: ClubLife.Walker = life._staff[0]
	var checks := 0
	for i in range(250):
		var a := Vector3(rng.randf_range(-40,40),0,rng.randf_range(-40,40))
		var b := a + Vector3(rng.randf_range(-10,10),0,rng.randf_range(-10,10))
		life._traffic_cache_active = false
		var exhaustive := life._walker_vehicle_clear(walker,a,b)
		life._traffic_cache_active = true
		var indexed := life._walker_vehicle_clear(walker,a,b)
		if indexed != exhaustive: failed = true
		var vehicle: ClubLife.Walker = life._pool[i % life._pool.size()]
		var start := vehicle.node.global_transform
		var end := start
		end.origin += b-a
		end.basis = Basis(Vector3.UP,rng.randf_range(-PI,PI))
		life._traffic_cache_active = false
		exhaustive = life._vehicle_people_clear(vehicle,start,end)
		life._traffic_cache_active = true
		indexed = life._vehicle_people_clear(vehicle,start,end)
		if indexed != exhaustive: failed = true
		checks += 2
	life._traffic_cache_active = false
	life.queue_free()
	await process_frame
	print("CROWD INDEX: ","FAIL" if failed else "PASS","; ",checks," comparisons with exhaustive body checks")
	quit(1 if failed else 0)
