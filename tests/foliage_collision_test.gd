extends SceneTree
var failed := false
func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var incoming := Vector3(35, 10, 0)
	check(GolfBall.foliage_velocity(incoming, 0.1, 0.0) == incoming, "Foliage gaps preserve flight")
	var leaves := GolfBall.foliage_velocity(incoming, 0.5, 0.4)
	check(leaves.length() < incoming.length() and leaves.x > 0, "Leaves slow the ball without bouncing backward")
	var branch := GolfBall.foliage_velocity(incoming, 0.95, -0.5)
	check(branch.y < 0 and branch.length() < leaves.length(), "Branches knock the ball downward")
	for v in [Vector3(0.01, 0, 0), Vector3(0, -40, 0), incoming]:
		for i in range(101):
			check(GolfBall.foliage_velocity(v, i / 100.0, 0.8).length() <= v.length() + 0.0001, "Contacts cannot add energy")
	var forest := ForestPlanter.new()
	forest._colliders = [[Vector3.ZERO, 0.3, 4.0, 3.0, 6.0], [Vector3(12, 0, 0), 0.3, 4.0, 3.0, 6.0]]
	root.add_child(forest)
	var ball := GolfBall.new()
	root.add_child(ball)
	for i in range(3):
		await physics_frame
	var space := root.world_3d.direct_space_state
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-5, 6, 1), Vector3(5, 6, 1), 2)).is_empty(), "Crown must not act as a solid obstacle")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-5, 6, 0), Vector3(5, 6, 0), 2)).is_empty(), "Trunk remains solid inside the crown")
	ball.velocity = incoming
	ball._foliage_rng.seed = 37
	ball._pass_foliage(Vector3(-5, 6, 1), Vector3(17, 6, 1))
	check(ball._foliage_touched.size() == 2, "Fast sweep hits both soft crowns")
	var after := ball.velocity
	ball._pass_foliage(Vector3(-5, 6, 1), Vector3(17, 6, 1))
	check(ball.velocity == after, "A crown cannot repeatedly drain speed on adjacent frames")
	ball.place(Vector2.ZERO)
	check(ball._foliage_touched.is_empty(), "New ball placement clears crown contacts")
	forest.free()
	ball.free()
	print("FOLIAGE COLLISION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
