extends SceneTree
var failed := false
func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		push_error(label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var layout := CourseLayout.new()
	layout.bounds = Rect2(0, 0, 64, 64)
	var heights := PackedFloat32Array()
	heights.resize(65 * 65)
	# One-metre ridge: both segment endpoints can be clear while the middle hits.
	for z in range(65):
		for x in range(65):
			heights[z * 65 + x] = 2.0 if x == 10 else 0.0
	layout.rendered_terrain.register_tile(Vector2i.ZERO, Vector2.ZERO, 1.0, 65, 65, heights)
	var ball := GolfBall.new()
	ball.layout = layout
	ball.skip_obstacles = true
	root.add_child(ball)
	var hit = ball._sweep_ground(Vector3(9, 0.5, 10), Vector3(11, 0.5, 10))
	check(hit != null and hit.x < 10, "Sweep catches a ridge between clear endpoints")
	hit = ball._sweep_ground(Vector3(9, 0.2, 10), Vector3(10, 1.0, 10))
	check(hit != null, "Ascending shots collide with rising ground")
	check(ball._sweep_ground(Vector3(9, 10, 10), Vector3(11, 10, 10)) == null, "Clear flight remains uninterrupted")
	hit = ball._sweep_ground(Vector3(9.15, 1.99, 10), Vector3(11.15, 1.99, 10))
	check(hit != null and hit.x < 10.0, "A grazing shot must hit a narrow ridge between the old sweep samples")
	hit = ball._sweep_ground(Vector3(11.15, 1.99, 10), Vector3(9.15, 1.99, 10))
	check(hit != null and hit.x > 10.0, "The grazing ridge is caught in the reverse direction")
	ball.place(Vector2(9.5, 10))
	check(ball.position.y > 1.0 + BallPhysics.RADIUS, "Placement rests on visible mesh with slope clearance")
	check(ball._sweep_ground(ball.position, ball.position + Vector3.UP) == null, "A ball launched away from the surface is not caught at time zero")
	ball.position = Vector3(10, 3, 10)
	ball.launch(60, 5, 0, 0, Vector3.RIGHT)
	ball.velocity = Vector3(0, -180, 0)
	ball._step(GolfBall.DT)
	check(ball.position.y >= ball._contact_height(ball.position) - 0.0001, "Fast landing cannot penetrate rendered ground")

	# Saddle cell distinguishes actual triangle interpolation from bilinear heights.
	var contact := TerrainContact.new()
	contact.register_tile(Vector2i.ZERO, Vector2.ZERO, 64, 2, 2, PackedFloat32Array([0, 0, 0, 4]))
	check(absf(contact.sample(16, 16).x) < 0.0001, "First triangle matches rendered plane")
	check(absf(contact.sample(48, 48).x - 2.0) < 0.0001, "Second triangle matches rendered plane")
	contact.register_tile(Vector2i.ZERO, Vector2.ZERO, 64, 2, 2, PackedFloat32Array([0, 4, 4, 0]))
	var previous_contact := layout.rendered_terrain
	layout.rendered_terrain = contact
	hit = ball._sweep_ground(Vector3(31.85, 4.02, 31.85), Vector3(32.9, 4.02, 32.9))
	check(hit != null, "A grazing shot catches a triangle diagonal between grid lines")
	layout.rendered_terrain = previous_contact
	# A steep bunker landing must not animate the visible ball below its contact point.
	ball.set_physics_process(false)
	ball.resolve_surface = func(_p: Vector3) -> Dictionary:
		return {"engine": layout.engine_surface(CourseLayout.SURFACE_BUNKER), "surface": CourseLayout.SURFACE_BUNKER, "source": "test"}
	ball.velocity = Vector3(0, -20, 0)
	ball._handle_impact(ball.position)
	await create_timer(0.3).timeout
	check(ball._mesh.position.y >= -0.001, "Bunker impact keeps the visible ball above the sand")
	ball.free()
	print("GROUND CONTACT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
