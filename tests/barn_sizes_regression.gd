extends SceneTree
func _init():
 root.child_entered_tree.connect(func(n):
  if n is GameState: n.autosave = false)
 call_deferred("run")
var failed = false
func run():
 for level in [1, 2, 3, 4]:
  await scenario(3, level)
 print("BARN TRAFFIC: ", "FAIL" if failed else "PASS")
 quit(1 if failed else 0)
func scenario(count, level):
 var life = ClubLife.new()
 root.add_child(life)
 life.set_process(false)
 life.course = PaintedCourse.create("Barn traffic", Vector2i(180,180))
 life.business = CourseBusiness.create()
 life.business.built = {"cart_barn":level}
 life.business.placements = {"cart_barn":{"pos":Vector2.ZERO,"rot":0.0}}
 var built = FacilityBuilder.build([{"type":"cart_barn","level":level,"pos":Vector2.ZERO,"rot":0.0}],func(_p): return 0.0,false,true)
 root.add_child(built)
 life.facilities = built
 life.refresh()
 life.business.staff = {"cart_attendant":count}
 life.refresh()
 life._rng.seed = 81028
 var last_return = 0.0
 var last_stamp = -1.0
 var returns = 0
 for tick in range(6000):
  life._spawn_wait = 1e9
  life._process(0.1)
  var latest = -1.0
  for stamp in life._bay_washed.values(): latest = maxf(latest, float(stamp))
  if latest > last_stamp:
   returns += 1
   last_stamp = latest
   last_return = life._clock
  if life._clock - last_return > 200.0:
   push_error("Barn stalled with %d attendants at %.1f seconds" % [count,life._clock])
   failed = true
   break
  if tick % 100 == 0: await process_frame
 if returns < 4:
  push_error("Too few completed barn returns with %d attendants: %d" % [count,returns])
  failed = true
 print("BARN TRAFFIC level=%d attendants=%d returns=%d elapsed=%.1f" % [level,count,returns,life._clock])
 life.clear()
 life.queue_free()
 built.queue_free()
 await process_frame
