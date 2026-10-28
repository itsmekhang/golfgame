extends SceneTree
func _init() -> void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run() -> void:
	for level in range(1,5):
		for tier in range(1,4):
			var f:=FacilityBuilder.build([{"type":"clubhouse","level":level,"pos":Vector2.ZERO,"rooms":{"restaurant":tier}}],func(_p:Vector2)->float:return 0.0,false,true)
			root.add_child(f)
			var house:Node3D=f.get_child(0)
			var rig:=FacilityBuilder.rig(house)
			if not rig["nav"].has("restaurant"):f.free();continue
			var nav:Dictionary=rig["nav"]["restaurant"]
			var g:AStarGrid2D=nav["astar"]
			var spots:=ClubLife._spots_for(rig["spots"]["restaurant"],"waiter")
			var p:Vector3=spots[0]["xf"].origin
			var a:=FacilityBuilder._nav_cell(nav,Vector2(p.x,p.z))
			var count:=0;var reachable:=0
			for z in range(g.region.size.y):
				for x in range(g.region.size.x):
					var b:=Vector2i(x,z)
					if not g.is_point_solid(b):
						count+=1
						if a.x>=0 and not g.get_id_path(a,b).is_empty():reachable+=1
			print("WAITER ",level,"/",tier," rect ",nav["rect"]," post ",p," snapped ",a," reachable ",reachable,"/",count)
			f.free()
	quit()
