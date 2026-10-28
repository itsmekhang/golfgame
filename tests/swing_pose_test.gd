extends SceneTree
var failed:=false
func _init()->void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failed=true;push_error(message)
func run()->void:
	var life:=ClubLife.new();root.add_child(life);life.set_process(false)
	life.course=PaintedCourse.create("Swing test",Vector2i(64,64))
	var looks: Array = ["a","e"] if "--prototype" in OS.get_cmdline_user_args() else ClubLife.LOOKS
	for look in looks:
		var w:=life._person("golfer_"+look)
		var sk:Skeleton3D=w.node.find_child("Skeleton3D",true,false)
		check(sk.find_bone("grip.R")>=0,"Missing palm contacts: "+look)
		if sk.find_bone("grip.R")<0:continue
		life._address_ball(w,Vector3(0,.045,-.78),Vector2.LEFT,false)
		w.data["held_club"].visible=true
		var closest:=10.0;var palm_max:=0.0;var worst_time:=0.0;var finish_y:=0.0;var trail_front:=10.0;var trail_side:=-10.0;var head_clear:=10.0;var head_time:=0.0;var shoulder_offset:=0.0
		for i in range(377):
			var time:=minf(i/120.0,3.13)
			w.anim.play("swing",0);w.anim.seek(time,true);w.anim.pause()
			life._update_held_club(w)
			var joints:={}
			for bone in ["upper_arm.L","upper_arm.R","forearm.L","forearm.R","hand.L","hand.R","grip.L","grip.R"]:
				joints[bone]=sk.get_bone_global_pose(sk.find_bone(bone)).origin
			palm_max=maxf(palm_max,joints["grip.L"].distance_to(joints["grip.R"]))
			# At the grip only the hands meet. Test arm volumes above the wrist cuffs.
			var cuff_l:Vector3=joints["hand.L"].move_toward(joints["forearm.L"],.055)
			var cuff_r:Vector3=joints["hand.R"].move_toward(joints["forearm.R"],.055)
			for a in [[joints["upper_arm.L"],joints["forearm.L"]],[joints["forearm.L"],cuff_l]]:
				for b in [[joints["upper_arm.R"],joints["forearm.R"]],[joints["forearm.R"],cuff_r]]:
					var pair:=Geometry3D.get_closest_points_between_segments(a[0],a[1],b[0],b[1])
					var d:=pair[0].distance_to(pair[1])
					if d<closest:closest=d;worst_time=time
			if time>=1.6:
				var palm:=sk.get_bone_global_pose(sk.find_bone("grip.L"))
				var head:=sk.get_bone_global_pose(sk.find_bone("head"))
				var head_axis:=head.basis.y.normalized()
				var shaft_end:Vector3=palm.origin+palm.basis*(w.data["club_grip"] as Node3D).basis*ClubLife.CLUB_HEAD_LOCAL
				var near:=Geometry3D.get_closest_points_between_segments(palm.origin,shaft_end,head.origin+head_axis*.045,head.origin+head_axis*.155)
				var gap:=near[0].distance_to(near[1])
				if gap<head_clear:head_clear=gap;head_time=time
				if time>=1.95:shoulder_offset=maxf(shoulder_offset,absf(palm.origin.y-joints["upper_arm.R"].y))
			if time>=1.95:
				var midpoint:Vector3=(joints["upper_arm.L"]+joints["upper_arm.R"])*.5
				var side:Vector3=(joints["upper_arm.L"]-joints["upper_arm.R"])*Vector3(1,0,1)
				side=side.normalized()
				var forward:=Vector3.UP.cross(side)
				var elbow:Vector3=joints["forearm.L"]-midpoint
				trail_front=minf(trail_front,elbow.dot(forward))
				trail_side=maxf(trail_side,elbow.dot(side))
				var grip_pose:=sk.get_bone_global_pose(sk.find_bone("grip.L"))
				var shaft:Vector3=grip_pose.basis*(w.data["club_grip"] as Node3D).basis*ClubLife.CLUB_HEAD_LOCAL
				finish_y=maxf(finish_y,absf(shaft.normalized().y))
		check(palm_max<.035,"Palms leave shared grip: "+look+" "+str(palm_max))
		check(closest>.07,"Arms intersect: "+look+" "+str(closest)+" at "+str(worst_time))
		check(trail_front>.05,"Right elbow passes behind the chest: "+look+" "+str(trail_front))
		check(trail_side<.06,"Right arm does not cross toward the lead side: "+look+" "+str(trail_side))
		check(head_clear>.10,"Club enters head clearance: "+look)
		check(shoulder_offset>.14 and shoulder_offset<.26,"Finishing hands are not beside the lead shoulder: "+look)
		check(finish_y>.15 and finish_y<.25,"Club does not wrap behind the shoulders: "+look)
		print("SWING ",look," palm separation ",palm_max," arm clearance ",closest," at ",worst_time," finish vertical ",finish_y)
		print("TRAIL ARM ",look," front ",trail_front," side ",trail_side," head clearance ",head_clear)
		w.node.queue_free()
	print("SWING POSE ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
