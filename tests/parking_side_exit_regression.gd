extends SceneTree
var failed:=false
func _init()->void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:failed=true;push_error(message)
func run()->void:
 for level in range(1,5):
  var built:=FacilityBuilder.build([{"type":"parking_lot","level":level,"pos":Vector2.ZERO,"rot":0.0}],func(_p:Vector2)->float:return 0.0,false,true);root.add_child(built)
  var lot:=built.get_child(0) as Node3D;var rig:=FacilityBuilder.rig(lot)
  check(rig["stalls"].size()==[24,48,64,80][level-1],"Changed parking capacity")
  check(rig.get("side_exits",[]).size()==(0 if level==1 else 1),"Side exit missing or added at wrong level")
  if level>=2:
   var out:Vector3=(rig["side_exits"][0] as Transform3D).origin
   check(out.x<-32 and out.z>5,"Side exit is at wrong end of lot")
   check(FacilityBuilder.built_near("parking_lot",level,Vector2.ZERO,0,Vector2(out.x,out.z),.1),"Side exit has no pavement")
   var nav:Dictionary=rig["nav"][""]
   var path:=FacilityBuilder.nav_route(lot,"",Vector2(-25,out.z),Vector2(out.x,out.z))
   check(not path.is_empty(),"Side-exit curb blocks vehicle route")
  built.free()
 print("PARKING CAPACITY AND SIDE EXITS: ","FAIL" if failed else "PASS")
 quit(1 if failed else 0)
