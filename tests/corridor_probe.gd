extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	var built:=FacilityBuilder.build([{"type":"clubhouse","level":3,"pos":Vector2.ZERO,"rooms":{"lobby":3,"pro_shop":3,"ballroom":3,"lounge":3}}],func(_p:Vector2)->float:return 0.0,false,true);root.add_child(built)
	var house:=built.get_child(0) as Node3D
	var life:=ClubLife.new();root.add_child(life);life.set_process(false);life.facilities=built
	life._indoor_guest_nav(house)
	var nav:Dictionary=FacilityBuilder.rig(house)["nav"]["indoor_guest"]
	var grid:AStarGrid2D=nav["astar"]
	for pair in [[Vector2(0,11.2),Vector2(0,15.5)],[Vector2(0,15.5),Vector2(-8,17.5)],[Vector2(-8,17.5),Vector2(-20,20.5)],[Vector2(-20,20.5),Vector2(-24,20.5)]]:
		print("SEGMENT ",pair," ",FacilityBuilder.nav_route(house,"indoor_guest",pair[0],pair[1]))
	for z in range(10,23):
		var row:=""
		for x in range(-31,8):
			var c:=Vector2i(roundi((x-grid.offset.x)/.4),roundi((z-grid.offset.y)/.4))
			row+="#" if grid.is_point_solid(c) else "."
		print(z," ",row)
	quit()
