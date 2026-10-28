extends SceneTree
class Crowd extends ClubLife:
 func _step_group(g: Group, delta: float) -> void:
  for p: Walker in g.golfers: _step(p,delta)
  for c: Walker in g.carts: _step(c,delta)
  if g.car != null: _step(g.car,delta)
 func _surface_y(_p: Vector2, _fallback: float = NAN, _from: float = NAN) -> float:
  return 0.0
func _init():
 root.child_entered_tree.connect(func(n):
  if n is GameState: n.autosave = false)
 call_deferred("run")
func actor(life, x, z, vehicle=false):
 var w = ClubLife.Walker.new()
 w.node = Node3D.new()
 life.add_child(w.node)
 w.node.position = Vector3(x,0,z)
 w.speed = 1.35
 w.data = {"pace":1.0,"lane":0.0}
 if vehicle: w.data.merge({"vehicle":true,"half":Vector2(0.7,1.3)})
 return w
func run():
 var life = Crowd.new()
 root.add_child(life)
 life.set_process(false)
 life.course = PaintedCourse.create("Crowd benchmark",Vector2i(400,400))
 life.business = CourseBusiness.create()
 life._nav = AStarGrid2D.new()
 life._nav.region = Rect2i(0,0,100,100)
 life._nav.offset = Vector2(-200,-200)
 life._nav.cell_size = Vector2.ONE * 4
 life._nav.update()
 life._cart_nav = life._nav
 for i in range(24):
  var p = actor(life,-30+i*2,20)
  p.path = [Vector3(p.node.position.x,0,-80)]
  life._staff.append(p)
 for i in range(24): life._pool.append(actor(life,-48+i*4,0,true))
 for i in range(12):
  var g = ClubLife.Group.new()
  for j in range(4):
   var p = actor(life,-40+i*7+j,45)
   p.path = [Vector3(p.node.position.x,0,-60)]
   g.golfers.append(p)
  g.car = actor(life,-40+i*7,65,true)
  g.car.path = [Vector3(g.car.node.position.x,0,-80)]
  life._groups.append(g)
 life._marked = life._groups.size()
 var start = Time.get_ticks_usec()
 var worst = 0
 for tick in range(180):
  life._spawn_wait = 1e9
  var t = Time.get_ticks_usec()
  life._process(1.0/30.0)
  worst = maxi(worst,Time.get_ticks_usec()-t)
 print("CROWD BENCHMARK mean_ms=%.3f worst_ms=%.3f" % [(Time.get_ticks_usec()-start)/180000.0,worst/1000.0])
 quit()
