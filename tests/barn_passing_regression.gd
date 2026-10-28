extends SceneTree
var failed := false
func _init() -> void:
 root.child_entered_tree.connect(func(n: Node) -> void:
  if n is GameState: n.autosave = false)
 call_deferred("run")
func actor(life: ClubLife) -> ClubLife.Walker:
 var w := ClubLife.Walker.new()
 w.node = Node3D.new()
 life.add_child(w.node)
 return w
func run() -> void:
 var life := ClubLife.new()
 root.add_child(life)
 life.set_process(false)
 life.course = PaintedCourse.create("Blocked passing place",Vector2i(180,180))
 life.business = CourseBusiness.create()
 life._nav = AStarGrid2D.new()
 life._nav.region = Rect2i(0,0,40,40)
 life._nav.offset = Vector2(-80,-80)
 life._nav.cell_size = Vector2.ONE * 4
 life._nav.update()
 var vehicle := actor(life)
 vehicle.data = {"vehicle":true,"half":Vector2(0.7,1.3)}
 vehicle.path = [Vector3(0,0,-20)]
 var obstacle := actor(life)
 obstacle.node.position = Vector3(2,0,-3)
 obstacle.data = {"vehicle":true,"half":Vector2(0.5,0.5)}
 life._pool = [vehicle,obstacle]
 var p := actor(life)
 life._staff = [p]
 p.node.position = Vector3(0,0,-3)
 var aside := Vector3(4,0,-3)
 p.path = [aside,aside]
 p.data["pedestrian_yield"] = {"route":[],"aside":aside,"vehicle":weakref(vehicle.node),"heading":Vector3.FORWARD,"half_length":1.5}
 life._pedestrian_yield_step(p,4.1)
 var at := p.node.global_position
 if p.path.size() < 3: failed = true
 for point: Vector3 in p.path:
  if not life._walk_region_clear(p,at,point): failed = true
  at = point
 life._pedestrian_yield_step(p,0.1)
 if not p.data.has("pedestrian_yield"): failed = true
 vehicle.path.clear()
 life._pedestrian_yield_step(p,0.1)
 if p.data.has("pedestrian_yield") or not p.path.is_empty(): failed = true
 print("BLOCKED PASSING PLACE: ","FAIL" if failed else "PASS")
 life.queue_free()
 await process_frame
 quit(1 if failed else 0)
