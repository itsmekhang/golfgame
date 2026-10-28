extends SceneTree
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func run() -> void:
	var failed := false
	var life := ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	life.course = PaintedCourse.create("Car entry", Vector2i(128,128))
	life.business = CourseBusiness.create()
	life._arrival_serial = 2
	var car := life._visitor_car(0)
	var worker := life._person("staff_valet")
	worker.node.global_position = life._cart_door(car, 0)
	life._climb_in(worker, car, 0)
	var move: Dictionary = worker.data["cart_move"]
	var sk := worker.node.find_child("Skeleton3D", true, false) as Skeleton3D
	var clip := worker.anim.get_animation(move["clip"])
	for i in range(21):
		life._pose_now(worker, move["clip"])
		worker.anim.seek(clip.length * i / 20.0, true)
		life._cart_move_step(worker, 0.0 if i == 0 else float(move["length"]) / 20.0)
		var head := car.node.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head")).origin
		if absf(head.x) < 0.82 and head.y > 1.14:
			failed = true
			push_error("Hatchback entry puts the head through the roof")
	var foot := car.node.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("foot.L")).origin
	if foot.y < 0.1:
		failed = true
		push_error("Hatchback driver feet cross the floor")
	print("HATCHBACK ENTRY AND SEATING: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
