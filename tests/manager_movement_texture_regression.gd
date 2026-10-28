extends SceneTree
var failed:=false
func _init()->void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:failed=true;push_error(message)
func run()->void:
 for texture in ["roof_shingle","cedar_shingle","brick","wood_floor","deck"]:
  var img:Image=(load("res://assets/facilities/textures/%s.png"%texture) as Texture2D).get_image()
  check(img.has_mipmaps(),"Architectural texture lacks distance mipmaps: "+texture)
 var c:=PaintedCourse.create("Contact and drop",Vector2i(256,256))
 c.holes=[{"tee":Vector2(50,-40),"pin":Vector2(50,-90),"par":3,"bends":[],"curve":false}]
 for z in range(c.size.y):
  for x in range(c.size.x):c.height[z*c.size.x+x]=sin(x*.15)*.5+cos(z*.11)*.6
 var b:=CourseBusiness.create();b.accepting_visitors=true;b.built={"clubhouse":4,"parking_lot":1};b.rooms={"valet":3,"pro_shop":1};b.staff={"valet":2,"shop_clerk":1};b.placements={"clubhouse":{"pos":Vector2.ZERO,"rot":0.0},"parking_lot":{"pos":Vector2(0,-75),"rot":0.0}}
 var built:=FacilityBuilder.build([{"type":"clubhouse","level":4,"pos":Vector2.ZERO,"rot":0.0,"rooms":b.rooms},{"type":"parking_lot","level":1,"pos":Vector2(0,-75),"rot":0.0}],func(_p:Vector2)->float:return 0.0,false,true);root.add_child(built)
 var life:=ClubLife.new();root.add_child(life);life.set_process(false);life.course=c;life.business=b;life.facilities=built;life.refresh()
 var g:=life._new_arrival(0)
 # Isolate ordinary self-parking: no valet claim for this rack walk.
 if g.valet_service.get("used",false):life._valet_release(g);g.valet_service.clear()
 var w:ClubLife.Walker=g.golfers[0]
 w.node.visible=true;w.node.global_position=Vector3(0,life._surface_y(Vector2(0,3)),3)
 w.path=[Vector3(0,0,10)]
 var bag:Node3D=w.data["bag"];bag.visible=true
 life._valet_take(w)
 check(w.data.has("rack_delivery") and bag.visible and not w.data.has("bag_down"),"Golfer's bag appeared at rack before walking")
 var drop:Vector2=w.data["rack_delivery"]["drop"]
 var moved:=false;var finished:=false
 for i in range(1000):
  life._step(w,.1)
  moved=moved or Vector2(w.node.global_position.x,w.node.global_position.z).distance_to(Vector2(0,3))>1
  if not w.data.has("rack_delivery"):finished=true;break
 check(finished and moved and w.data.has("bag_down"),"Golfer failed to walk to rack and set bag down")
 if w.data.has("bag_down"):
  var stand:Node3D=w.data["bag_down"]
  check(Vector2(stand.global_position.x,stand.global_position.z).distance_to(drop)<.02,"Bag placed in wrong rack slot")
 check(not w.path.is_empty(),"Golfer failed to resume clubhouse route after dropping bag")
 # Waiting golfers must re-ground after terrain changes and avoidance movements.
 w.data["practice"]={"kind":"putt"};w.path.clear();w.node.global_position=Vector3(20,-3,20)
 life._ground_practice(w)
 check(w.node.global_position.y>=life._surface_y(Vector2(20,20))-.001,"Practice golfer remained below turf")
 w.data.erase("practice")
 for role in ["staff_valet","staff_cart_attendant"]:
  var attendant:=life._person(role)
  check(attendant.data.get("cart_clips",{}).has("enter_cart") and attendant.data.get("cart_clips",{}).has("exit_cart"),"Attendant lacks provided car animations: "+role)
  attendant.node.queue_free()
 var range_customer:=life._new_arrival(0,"range")
 life._valet_offer(range_customer,true)
 check(range_customer.valet_service.is_empty(),"Range customer was offered valet")
 print("TEXTURES / VISIBLE RACK WALK / PRACTICE GROUNDING / STAFF CLIPS / RANGE RULE: ","FAIL" if failed else "PASS")
 life.clear();life.queue_free();built.queue_free();await process_frame
 quit(1 if failed else 0)
