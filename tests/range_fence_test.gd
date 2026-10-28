extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		push_error(msg)
func run() -> void:
	for yaw in [0.0, 1.2]:
		var built := FacilityBuilder.build([{"type":"driving_range", "level":1, "pos":Vector2.ZERO, "rot":yaw}],func(_p: Vector2) -> float: return 0.0,false,true)
		root.add_child(built)
		var fac := built.get_node("driving_range") as Node3D
		var life := ClubLife.new()
		root.add_child(life)
		life.set_process(false)
		life.course = PaintedCourse.create("Fence",Vector2i(300,300))
		life.facilities = built
		life._build_course_nav()
		var rig := FacilityBuilder.rig(fac)
		var machine: Transform3D = rig["dispensers"][0]
		print("Dispenser ", machine.origin, " facing ", machine.basis.z)
		for start in [Vector2(-23,-5),Vector2(-25,2),Vector2(-30,5)]:
			var w := ClubLife.Walker.new()
			w.node = Node3D.new()
			life.add_child(w.node)
			w.node.global_position = fac.global_transform * Vector3(start.x,0.1,start.y)
			w.ground = false
			life._range_go(w,fac,Vector2(machine.origin.x,machine.origin.z),false)
			print("Route ",start," blocked ",w.data.get("blocked")," points ",w.path)
			check(not w.data.get("blocked",false),"Dispenser inaccessible")
			for destination in [Vector2(machine.origin.x,machine.origin.z),Vector2(-23,-8)]:
				life._range_go(w,fac,destination,false)
				var highest := 0.0
				for frame in range(3600):
					if w.path.is_empty(): break
					life._step(w,1.0/30)
					var p: Vector3 = fac.global_transform.affine_inverse() * w.node.global_position
					highest = maxf(highest,p.y)
					check(not (absf(p.x+26)<0.3 and p.z < -1.8 and p.z > -12.7),"Walker crossed left fence: %s" % p)
				check(w.path.is_empty(),"Route never finished")
				check(highest < 0.3,"Walker floated %.3f m" % highest)
			w.node.free()
		life.free()
		built.free()
	print("RANGE FENCE: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
