extends SceneTree
const Sign = preload("res://scripts/tee_hole_sign.gd")
var failed:=false
func _init()->void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:failed=true;push_error(message)
func run()->void:
 var course:=PaintedCourse.create("Pinehurst Golf Club",Vector2i(512,512))
 course.holes=[{"tee":Vector2(0,40),"pin":Vector2(25,-200),"bends":[Vector2(-40,-80)],"par":4}]
 course.paint(PaintedCourse.Surface.WATER,Vector2(4,-55),19,1.0,1.0)
 course.paint(PaintedCourse.Surface.BUNKER,Vector2(-25,-128),11,1.0,1.0)
 var sign:=Sign.for_painted(course,0);root.add_child(sign)
 check(sign.has_node("SolidSignBody"),"Sign needs an opaque body behind the face")
 check(sign.get_meta("yards")==course.hole_yards(0),"Sign yardage differs from scorecard")
 check(sign.position.distance_to(Vector3(0,course.height_at(Vector2(0,40)),40))>6,"Sign obstructs the tee")
 check(is_equal_approx(sign.position.y,course.height_at(Vector2(sign.position.x,sign.position.z))),"Sign is not grounded")
 for face in ["Front","Back"]:
  check(sign.get_node(face+"/HoleNumber").text=="1","Wrong hole number")
  check(sign.get_node(face+"/Par").text=="PAR 4","Wrong par")
  check(sign.get_node(face+"/Yardage").text==str(course.hole_yards(0)),"Wrong single-tee yardage")
  check(sign.get_node(face+"/HoleNumber").billboard==BaseMaterial3D.BILLBOARD_DISABLED,"Sign lettering must stay on the plaque")
 check(sign.find_children("Yardage","Label3D",true,false).size()==2,"Must display only one yardage per side")
 var left:MeshInstance3D=sign.get_node("LeftPost")
 var right:MeshInstance3D=sign.get_node("RightPost")
 check(is_equal_approx(left.position.z,right.position.z),"Sign legs are at different depths")
 for post in [left,right]:
  check(post.position.y+post.mesh.size.y*.5<.67,"Support leg sticks up into sign face")
  check(post.mesh.size.z*.5<.045,"Support leg protrudes through the sign surface")
 var old_texture:Texture2D=sign.get_node("Front/ArchedPlaque").material_override.albedo_texture
 var map_image:=old_texture.get_image()
 check(_has_color(map_image,Color("43a9dc")),"Actual painted water is absent from sign")
 check(_has_color(map_image,Color("e5cd91")),"Actual painted bunker is absent from sign")
 course.holes[0]["pin"]=Vector2(90,-220)
 var updated:=Sign.for_painted(course,0)
 var new_texture:Texture2D=updated.get_node("Front/ArchedPlaque").material_override.albedo_texture
 check(old_texture.get_image().get_data()!=new_texture.get_image().get_data(),"Map does not follow edited route")
 updated.free()
 var layout:=CourseLayout.new();var hole:=CourseLayout.Hole.new();hole.index=17;hole.par=5
 hole.tee=Vector3(10,0,20);hole.waypoints=[hole.tee,Vector3(50,0,-170),Vector3(90,0,-370)]
 var gameplay:=Sign.for_layout(layout,hole)
 check(gameplay.get_meta("hole_number")==18 and gameplay.get_meta("par")==5,"Gameplay sign has wrong hole information")
 check(gameplay.get_meta("yards")==roundi(hole.length_yd),"Gameplay yardage differs from scorecard")
 var bunker:=Bunker.new();bunker.polygon=PackedVector2Array([Vector2(35,-120),Vector2(55,-120),Vector2(55,-95),Vector2(35,-95)])
 var water:=WaterHazard.new();water.polygon=PackedVector2Array([Vector2(30,-240),Vector2(65,-240),Vector2(65,-205),Vector2(30,-205)])
 layout.bunkers.append(bunker);layout.water_hazards.append(water)
 var with_hazards:=Sign.for_layout(layout,hole)
 var hazard_image:Image=with_hazards.get_node("Front/ArchedPlaque").material_override.albedo_texture.get_image()
 check(_has_color(hazard_image,Color("43a9dc")) and _has_color(hazard_image,Color("e5cd91")),"Gameplay hazard polygons missing from sign")
 with_hazards.free();bunker.free();water.free()
 gameplay.free()
 check(load("res://scripts/course.gd")!=null,"Gameplay integration failed")
 check(load("res://scripts/manager/manager_green_pins.gd")!=null,"Manager integration failed")
 check(load("res://scripts/studio/course_studio.gd")!=null,"Studio integration failed")
 print("TEE SIGNS ","FAIL" if failed else "PASS","; correct single-tee data, route updates, grounding, two readable sides, all three views")
 if "--preview" in OS.get_cmdline_user_args():
  root.size=Vector2i(1000,1000);sign.position=Vector3.ZERO;sign.rotation=Vector3.ZERO
  var env:=WorldEnvironment.new();env.environment=Environment.new()
  env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("94afbd")
  env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.75;root.add_child(env)
  var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.shadow_enabled=true;root.add_child(sun)
  var grass:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100);grass.mesh=plane
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color("386a43");grass.material_override=mat;root.add_child(grass)
  var eye:=Camera3D.new();root.add_child(eye);eye.near=.05
  for side in [1,-1]:
   eye.position=Vector3(.35,1.65,3.25*side);eye.look_at(Vector3(0,1.3,0))
   for i in range(4):await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/tee_sign_%d.png"%side)
 quit(1 if failed else 0)

func _has_color(image:Image,color:Color)->bool:
 for y in range(590,1325,2):
  for x in range(590,894,2):
   var pixel:=image.get_pixel(x,y)
   if absf(pixel.r-color.r)<.01 and absf(pixel.g-color.g)<.01 and absf(pixel.b-color.b)<.01:return true
 return false
