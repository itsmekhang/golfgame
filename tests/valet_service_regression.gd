extends SceneTree
var failed:=false
func _init()->void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:failed=true;push_error(message)
func run()->void:
 var c:=PaintedCourse.create("Valet regression",Vector2i(400,400))
 c.holes=[{"tee":Vector2(60,10),"pin":Vector2(60,-100),"par":3,"bends":[],"curve":false}]
 c.paint(PaintedCourse.Surface.GREEN,Vector2(60,-100),9,1,1)
 var b:=CourseBusiness.create();b.accepting_visitors=true
 b.placements={"clubhouse":{"pos":Vector2(-70,40),"rot":0.0},"parking_lot":{"pos":Vector2(-70,135),"rot":0.0},"cart_barn":{"pos":Vector2(30,135),"rot":0.0}}
 b.built={"clubhouse":4,"parking_lot":1,"cart_barn":1};b.rooms={"valet":3,"pro_shop":1}
 b.staff={"valet":3,"shop_clerk":1,"cart_attendant":3}
 var items:Array=[]
 for type in b.placements:items.append({"type":type,"level":b.level(type),"pos":b.placements[type]["pos"],"rot":0.0,"rooms":b.rooms})
 var facilities:=FacilityBuilder.build(items,func(_p:Vector2)->float:return 0.0,false,true);root.add_child(facilities)
 var life:=ClubLife.new();root.add_child(life);life.set_process(false)
 life.course=c;life.business=b;life.facilities=facilities;life._rng.seed=132;seed(132);life.refresh()
 check(life._valet_staff().size()==2,"Valet must have at most two workers")
 var valets:=life._valet_staff()
 for p:ClubLife.Walker in valets:
  var target:Vector2=p.data["valet_face"]
  var facing:Vector3=-p.node.global_basis.z
  check(facing.dot(Vector3(target.x-p.node.global_position.x,0,target.y-p.node.global_position.z).normalized())>.99,"Valet faces away from the counter")
 check(facilities.find_children("ValetUmbrella","Node3D",true,false).size()==1,"Top valet tier has no umbrella")
 check(facilities.find_children("ValetGoldPlaque","MeshInstance3D",true,false).size()==1,"Black/gold valet plaque is missing")
 check(FacilityBuilder.rig(facilities.get_node("clubhouse")).get("valet_stalls",[]).size()==10,"Reserved parking bays missing")
 var house:=facilities.get_node("clubhouse") as Node3D
 var sign:=facilities.find_children("ValetGoldPlaque","MeshInstance3D",true,false)[0] as MeshInstance3D
 check((sign.material_override as StandardMaterial3D).metallic==1.0,"Valet lettering is not metal")
 check(sign.mesh is TextMesh and (sign.mesh as TextMesh).depth>0,"Valet lettering is not raised text")
 var bays:Array=FacilityBuilder.rig(house)["valet_stalls"]
 for index in range(10):
  var at:Vector3=(bays[index] as Transform3D).origin
  check(is_equal_approx(at.z,3.25),"Valet spaces are not in a single row beside the clubhouse")
  for incoming in [true,false]:
   var path:Array=life._valet_pocket_path(index,incoming)
   for k in range(path.size()-1):
    var a:Vector3=path[k];var z:Vector3=path[k+1]
    var steps:=maxi(1,ceili(a.distance_to(z)*2))
    for sample in range(steps+1):
     var at_world:Vector3=a.lerp(z,float(sample)/steps)
     check(FacilityBuilder.built_near("clubhouse",4,Vector2(house.position.x,house.position.z),0,Vector2(at_world.x,at_world.z),.1),"Valet route crosses lawn: bay %d point %s"%[index,at_world])
 check(not FacilityBuilder.built_near("clubhouse",4,Vector2.ZERO,0,Vector2(-24.75,-15.4),0),"Old parking slab still occupies the lawn")
 # Every rack slot stays to the side of the central entrance corridor.
 var rack_group:=ClubLife.Group.new();life._groups.append(rack_group)
 var test_bags:Array=[]
 for slot in range(9):
  var drop:Vector2=life._bag_drop_spot()
  check(drop!=Vector2.INF,"Rack lost a storage slot")
  if drop==Vector2.INF:break
  var local_drop:Vector3=house.global_transform.affine_inverse()*Vector3(drop.x,house.global_position.y,drop.y)
  check(absf(local_drop.x+4.45)<.01 and absf(local_drop.z-(4.7+slot*.5))<.01,"Rack storage did not move with its model")
  check(absf(local_drop.x)>4,"Bag storage obstructs the doorway")
  var approach:Vector2=life._valet_rack_approach(drop)
  var local_approach:Vector3=house.global_transform.affine_inverse()*Vector3(approach.x,house.global_position.y,approach.y)
  check(absf(local_approach.x)>3.4,"Bag handoff obstructs the central walk")
  var owner:=ClubLife.Walker.new();var bag:=Node3D.new();life.add_child(bag)
  bag.global_position=Vector3(drop.x,0,drop.y);owner.data["bag_down"]=bag
  rack_group.golfers.append(owner);test_bags.append(bag)
 check(life._bag_drop_spot()==Vector2.INF,"Rack overflow spills into the doorway")
 life._groups.erase(rack_group)
 for bag in test_bags:bag.free()
 print("ENTRANCE CLEAR: nine slots at canopy side; collection points outside central walk")
 var reservations:Array=[]
 for index in range(10):
  var reserved:=ClubLife.Group.new();reserved.valet_service={"pocket_slot":index}
  life._groups.append(reserved);reservations.append(reserved)
 check(life._valet_pocket_slot()==-1,"Valet accepted more than ten cars")
 for reserved in reservations:life._groups.erase(reserved)
 print("FORECOURT: ten bays, paved entry/retrieval routes, removed old slab, metallic extruded lettering")
 var restored:=CourseBusiness.from_dict(b.to_dict())
 check(restored.heads("valet")==2,"Legacy save kept a third valet")
 var g:=life._new_arrival(0)
 for retry in range(20):
  if g.valet_service.get("used",false):break
  life._valet_offer(g,true)
 check(g!=null and g.valet_service.get("used",false),"Full valet service was not offered")
 if g==null:quit(1);return
 g.range_visit=false;g.short_visit=false
 var another:=life._new_arrival(0,"gym")
 for retry in range(20):
  if another.valet_service.get("used",false):break
  life._valet_offer(another,true)
 check(another!=null and another.valet_service.get("used",false),"Busy valet service sent the next customer to self-park")
 if another!=null:
  check(another.valet_service.get("pocket_slot",-1)!=g.valet_service.get("pocket_slot",-1),"Two customers reserved the same valet bay")
  check(another.valet_service.get("stage","")=="arrival_queue","New valet customer did not queue for the curb")
  life._groups.erase(another);life._free_group(another)
 # No greeter means the customer waits in the arrival queue.
 for p:ClubLife.Walker in valets:p.data["role"]="test_off_duty"
 life._valet_service_step(g)
 check(g.valet_service.get("stage")=="arrival_queue","Unstaffed arrivals did not wait")
 for p:ClubLife.Walker in valets:p.data["role"]="valet"
 var last:="";var carried:=false;var reached:=false;var entered:=false;var exited:=false;var greeted:=false
 for step in range(6000):
  if g.phase=="check_in":g.timer=100000.0
  var stage:String=g.valet_service.get("stage","")
  if stage!=last:print("ARRIVAL ",step," ",stage," guest=",g.phase);last=stage
  if stage=="parked":reached=true;break
  life._spawn_wait=1e9;life._process(.2)
  var working:=0
  for employee:ClubLife.Walker in valets:
   if employee.data.has("valet_group"):working+=1
  check(working<=1,"Both valets left the podium")
  for p:ClubLife.Walker in valets:
   carried=carried or p.data.has("valet_carry")
   if p.data.has("cart_move"):
    entered=entered or bool(p.data["cart_move"]["in"])
    exited=exited or not bool(p.data["cart_move"]["in"])
  if g.valet_service.get("stage")=="greeting" and not life._moving(g.golfers):
   var lead:ClubLife.Walker=g.golfers[0]
   var local_lead:Vector3=house.global_transform.affine_inverse()*lead.node.global_position
   check(absf(local_lead.x+6.65)<.45 and absf(local_lead.z-2.35)<.45,"Lead valet customer is not centred at booth")
   if float(g.valet_service.get("greet_elapsed",0))>2.5:
    greeted=true
    var facing:Vector3=-lead.node.global_basis.z
    var target:Vector3=house.global_transform*Vector3(-6.65,0,3.6)
    var direction:Vector3=target-lead.node.global_position;direction.y=0
    check(facing.dot(direction.normalized())>.95,"Valet customer is not facing booth during conversation")
  if step%120==0:await process_frame
 check(reached,"Valet failed to finish unloading and parking")
 check(carried,"Valet never carried bags from car to rack")
 check(entered and exited,"Valet did not visibly enter and exit car")
 check(greeted,"Valet conversation was too brief")
 var car_frame:Transform3D=life._vehicle_frame(g.car)
 var trunk:Vector2=life._valet_trunk(g)
 var driver_door:Vector2=life._valet_car_door(g)
 var trunk_local:Vector3=car_frame.affine_inverse()*Vector3(trunk.x,car_frame.origin.y,trunk.y)
 var driver_local:Vector3=car_frame.affine_inverse()*Vector3(driver_door.x,car_frame.origin.y,driver_door.y)
 check(trunk_local.z>life._footprint(g.car).y and driver_local.x<0,"Trunk or driver door is on wrong side")
 print("DIAGNOSTIC ",g.phase," ",g.valet_service.get("stage")," car ",g.car.node.global_position," path ",g.car.path.size())
 if not reached:
  for p:ClubLife.Walker in valets:print("WORKER ",p.node.global_position," path=",p.path.size()," blocked=",p.data.get("blocked")," target=",p.data.get("outdoor_target"))
 else:
  life._to_parking(g)
  check(g.phase=="valet_pickup_wait","Valet customer was told to walk to parking")
  last="";var fetched:=false
  for step in range(6000):
   var stage:String=g.valet_service.get("stage","")
   if stage!=last:print("PICKUP ",step," ",stage," guest=",g.phase);last=stage
   if stage=="done":fetched=true;break
   life._spawn_wait=1e9;life._process(.2)
   if step%120==0:await process_frame
  check(fetched,"Valet failed to retrieve car and return it to the customer")
  check(int(g.valet_service.get("loaded_bags",0))>0,"Valet failed to visibly reload bags at trunk")
  if not fetched:
   print("PICKUP CAR ",g.car.node.global_position," path=",g.car.path.size())
   for p:ClubLife.Walker in valets:print("WORKER ",p.node.global_position," path=",p.path.size()," blocked=",p.data.get("blocked")," target=",p.data.get("outdoor_target"))
 # All tiers offer parking, with the rack reserved for level three.
 life._groups.erase(g);life._free_group(g);life._mark_stalls()
 for tier in [1,2]:
  life.clear()
  facilities.free()
  b.rooms["valet"]=tier
  items.clear()
  for type in b.placements:items.append({"type":type,"level":b.level(type),"pos":b.placements[type]["pos"],"rot":0.0,"rooms":b.rooms})
  facilities=FacilityBuilder.build(items,func(_p:Vector2)->float:return 0.0,false,true);root.add_child(facilities)
  life.course=c;life.business=b;life.facilities=facilities;life.refresh()
  var guest:=life._new_arrival(0)
  for retry in range(20):
   if guest.valet_service.get("used",false):break
   life._valet_offer(guest,true)
  check(guest.valet_service.get("full",false),"Base tier did not offer parking")
  check(facilities.find_children("ValetUmbrella","Node3D",true,false).size()==(0 if tier==1 else 1),"Wrong umbrella upgrade")
  guest.range_visit=false;guest.short_visit=false
  var parked:=false
  for step in range(7000):
   if guest.phase=="check_in":guest.timer=100000.0
   life._spawn_wait=1e9;life._process(.2)
   if guest.valet_service.get("stage","")=="parked":parked=true;break
   if step%120==0:await process_frame
  check(parked,"Stand-only service stalled at tier %d"%tier)
  life._groups.erase(guest);life._free_group(guest)
 print("VALET REDESIGN ","FAIL" if failed else "PASS")
 life.clear();life.queue_free();facilities.queue_free();await process_frame
 quit(1 if failed else 0)
