extends SceneTree
## Run with a rendered viewport too: the renderer updates the soft-body mesh,
## so a headless-only test cannot catch reuse of deformed world-space vertices.
const Flag = preload("res://assets/world_flagstick/world_flagstick.tscn")
const Grid = preload("res://assets/world_flagstick/cloth_grid.gd")
var failures := 0
func _init() -> void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:
  failures+=1
  push_error(message)
func run()->void:
 var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.near=.05
 var cup:=Node3D.new();cup.position=Vector3(125,7,230);cup.rotation.y=.45;root.add_child(cup)
 eye.global_position=cup.global_position+Vector3(0,5,160)
 var flag=Flag.instantiate();cup.add_child(flag);flag.place_in_cup(cup.global_position,.12)
 var peak_radius:=0.0
 var peak_pin_error:=0.0
 for scale_value in [1.0,.6]:
  flag.size_scale=scale_value;flag.get_node("Model").scale=Vector3.ONE*scale_value
  flag.reset_cloth()
  for cycle in range(4):
   eye.global_position=cup.global_position+Vector3(0,5,160)
   flag._update_lod(true)
   for i in range(12):await physics_frame
   check(flag.distant.visible and not flag.cloth.visible,"Far flag must show only wind fallback")
   check(flag.cloth.process_mode==Node.PROCESS_MODE_DISABLED,"Far cloth must leave physics")
   var previous_body:WeakRef=weakref(flag.cloth)
   eye.global_position=cup.global_position+Vector3(0,2,4)
   eye.look_at(cup.global_position+Vector3(.2,2,0))
   flag._update_lod(true)
   check(previous_body.get_ref()!=flag.cloth,"Waking flag reused a renderer-deformed mesh")
   check(flag.cloth.visible and not flag.distant.visible,"Near flag must show only attached cloth")
   var max_radius:=0.0
   var max_pin_error:=0.0
   for frame in range(60):
    await physics_frame
    for index in range(Grid.COUNT):
     var point:Vector3=flag.cloth.get_point_transform(index)
     check(point.is_finite(),"Cloth has a non-finite vertex")
     max_radius=maxf(max_radius,point.distance_to(flag.global_position+Vector3(0,2.245*scale_value,0)))
    for row in range(Grid.ROWS+1):
     var expected:Vector3=flag.anchor.global_transform*(Grid.point(0,row)*scale_value)
     max_pin_error=maxf(max_pin_error,flag.cloth.get_point_transform(row*21).distance_to(expected))
   # Allow the render server to consume the deformed mesh before disabling it.
   await process_frame
   if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
   check(max_radius<.85*scale_value,"Cloth stretched away from the pole after approach: "+str(max_radius))
   check(max_pin_error<.012,"Hoist detached after approach: "+str(max_pin_error))
   check(flag.find_children("Fabric","SoftBody3D",true,false).size()==1,"Waking accumulated cloth bodies")
   peak_radius=maxf(peak_radius,max_radius);peak_pin_error=maxf(peak_pin_error,max_pin_error)
 print("FLAG LOD ","PASS" if failures==0 else "FAIL"," (",failures," failures); peak radius=",peak_radius," pin error=",peak_pin_error)
 cup.queue_free();eye.queue_free()
 await process_frame
 quit(0 if failures==0 else 1)
