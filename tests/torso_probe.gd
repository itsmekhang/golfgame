extends SceneTree
func _init()->void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run()->void:
	var life:=ClubLife.new();root.add_child(life);life.set_process(false)
	var w:=life._person("golfer_a")
	var sk:Skeleton3D=w.node.find_child("Skeleton3D",true,false)
	for time in [0.0,1.17,1.30,1.55,1.8,2.4]:
		w.anim.play("swing",0);w.anim.seek(time,true);w.anim.pause()
		var out:={}
		for name in ["hips","spine","chest","neck","upper_arm.L","upper_arm.R","forearm.L","forearm.R","hand.L","hand.R","thigh.L","thigh.R"]:
			var bone:=sk.get_bone_global_pose(sk.find_bone(name))
			out[name]=[bone.origin, bone.basis.get_euler()]
		var side:=sk.get_bone_global_pose(sk.find_bone("upper_arm.L")).origin-sk.get_bone_global_pose(sk.find_bone("upper_arm.R")).origin
		var hips:=sk.get_bone_global_pose(sk.find_bone("thigh.L")).origin-sk.get_bone_global_pose(sk.find_bone("thigh.R")).origin
		print("TORSO ",time," chest yaw ",rad_to_deg(atan2(-side.z,side.x))," hip yaw ",rad_to_deg(atan2(-hips.z,hips.x))," ",out)
	quit()
