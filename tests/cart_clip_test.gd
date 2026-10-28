extends SceneTree
## Getting into and out of a golf cart by the captured clips: in from the door the driver's side
## (the capture) and mirrored the passenger's, smoothly -- no jump along the way or into the seat
## at the end -- and out again, each stood on their own side of the cart on the ground.
var failed := false


func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState:
			n.autosave = false
			n.save_path = "user://_cart_clip_test_unused.json")
	call_deferred("run")


func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)


func hips(w: ClubLife.Walker) -> Vector3:
	var sk := w.node.find_child("Skeleton3D", true, false) as Skeleton3D
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hips"))).origin


func run() -> void:
	var c := PaintedCourse.create("Cart clips", Vector2i(200, 200))
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = c
	var cart := life._cart()
	cart.node.global_position = Vector3(10, 0, 10)
	cart.node.rotation.y = 0.6
	for k in [0, 1]:
		var w := life._person("golfer_a")
		check(w != null and (w.data.get("cart_clips", {}) as Dictionary).size() == 6, "No cart clips measured on the golfer")
		if w == null:
			continue
		var door := life._cart_door(cart, k)
		w.node.global_position = Vector3(door.x, 0, door.z)
		var to := cart.node.global_position - w.node.global_position
		w.node.rotation.y = atan2(-to.x, -to.z)
		life._climb_in(w, cart, k)
		check(w.data.has("cart_move") and w.riding, "Seat %d: not climbing in" % k)
		var last := hips(w)
		var jump := 0.0
		var steps := 0
		var at := -1
		while w.data.has("cart_move") and steps < 2000:
			w.anim.advance(1.0 / 60.0)
			life._cart_move_step(w, 1.0 / 60.0)
			if w.data.has("cart_move"):
				w.anim.advance(0.0)
			var now := hips(w)
			if now.distance_to(last) > jump:
				jump = now.distance_to(last)
				at = steps
			last = now
			steps += 1
		w.anim.advance(0.0)
		var sat := hips(w)
		check(w.riding and w.node.get_parent() == cart.node, "Seat %d: not sat in the cart after climbing in" % k)
		check(jump < 0.12, "Seat %d: climbing in jumped %.2f m in a frame" % [k, jump])
		print("seat %d in: %d frames, worst step %.3f m at frame %d, sat %.2f m off its last pose" % [k, steps, jump, at, sat.distance_to(last)])
		life._climb_out(w, cart, k)
		last = hips(w)
		jump = 0.0
		steps = 0
		at = -1
		while w.data.has("cart_move") and steps < 2000:
			w.anim.advance(1.0 / 60.0)
			life._cart_move_step(w, 1.0 / 60.0)
			var now := hips(w)
			if now.distance_to(last) > jump:
				jump = now.distance_to(last)
				at = steps
			last = now
			steps += 1
		var local := cart.node.global_transform.affine_inverse() * w.node.global_position
		check(not w.riding and w.node.get_parent() == life, "Seat %d: still in the cart after climbing out" % k)
		check((local.x < -0.6) if k == 0 else (local.x > 0.6), "Seat %d: stood out on the wrong side (%.2f across)" % [k, local.x])
		check(absf(w.node.global_position.y) < 0.05, "Seat %d: not back on the ground (%.2f up)" % [k, w.node.global_position.y])
		check(jump < 0.12, "Seat %d: climbing out jumped %.2f m in a frame" % [k, jump])
		print("seat %d out: %d frames, worst step %.3f m at frame %d, stood %.2f m across" % [k, steps, jump, at, local.x])
		w.node.queue_free()
	life.free()
	print("CART CLIPS: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
