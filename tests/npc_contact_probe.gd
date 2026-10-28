extends SceneTree
func _init() -> void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run() -> void:
	var life:=ClubLife.new()
	root.add_child(life)
	life.set_process(false)
	for look in ["a","e"]:
		var w:=life._person("golfer_"+look)
		var sk:Skeleton3D=w.node.find_child("Skeleton3D",true,false)
		var hand:=sk.find_bone("hand.L")
		for clip in ["swing","putt"]:
			w.anim.play(clip,0)
			print("PROFILE ",look," ",clip," length ",w.anim.get_animation(clip).length)
			for i in range(25):
				var time:=i*.1
				w.anim.seek(time,true)
				var h:=sk.global_transform*sk.get_bone_global_pose(hand)
				var head:=h*Vector3(.035,.85,0)
				print("CONTACT ",time," hand ",h.origin," head ",head)
		w.node.queue_free()
	quit()
