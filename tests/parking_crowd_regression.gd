extends SceneTree
func _init()->void:
	root.child_entered_tree.connect(func(n:Node)->void:
		if n is GameState:n.autosave=false)
	call_deferred("run")
func run()->void:
	var life:=ClubLife.new();root.add_child(life);life.set_process(false)
	life.course=PaintedCourse.create("Crowded parking",Vector2i(240,240));life.course.holes=[{"tee":Vector2(60,20),"pin":Vector2(60,-80),"par":3,"bends":[],"curve":false}]
	life.business=CourseBusiness.create();life.business.built={"clubhouse":4,"parking_lot":4}
	life.business.placements={"clubhouse":{"pos":Vector2.ZERO,"rot":0.0},"parking_lot":{"pos":Vector2(0,-80),"rot":0.3}}
	var built:=FacilityBuilder.build([{"type":"clubhouse","level":4,"pos":Vector2.ZERO,"rot":0.0},{"type":"parking_lot","level":4,"pos":Vector2(0,-80),"rot":0.3}],func(_p:Vector2)->float:return 0.0,false,true)
	root.add_child(built);life.facilities=built;life._build_course_nav();FacilityBuilder.park(life._fac("parking_lot"),.55)
	var failures:=0
	for tick in range(1800):
		if tick%60==0 and tick<720:life._new_arrival(0)
		for g:ClubLife.Group in life._groups:
			life._step(g.car,.1)
			if g.phase=="arrive" and g.car.path.is_empty():
				g.phase="walk"
				for k in range(g.golfers.size()):
					var w:ClubLife.Walker=g.golfers[k];var at:=life._by_car(g,k)
					w.node.visible=true;w.node.global_position=Vector3(at.x,life._surface_y(at),at.y);life._go(w,life._clubhouse_entry()+Vector2(k*.9,0))
			for w:ClubLife.Walker in g.golfers:
				if w.node.visible:life._step(w,.1)
	for g:ClubLife.Group in life._groups:
		if g.phase=="arrive":failures+=1
		print("GROUP phase=",g.phase," car=",g.car.node.position," carpath=",g.car.path.slice(0,2)," stop=",g.car.data.get("pedestrian_stopped",false))
		for w:ClubLife.Walker in g.golfers:
			if not w.path.is_empty() or w.data.get("blocked",false):
				failures+=1
				print("FROZEN ",w.node.global_position," path=",w.path.slice(0,3)," state=",w.data.get("pedestrian_yield",{})," region=",w.data.has("walk_region")," traffic=",w.data.get("traffic_wait",0))
	life.free();built.free();print("PARKING CROWD: ","PASS" if failures==0 else "FAIL", " failures=",failures);quit(0 if failures==0 else 1)
