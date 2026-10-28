extends SceneTree
const Sign=preload("res://scripts/tee_hole_sign.gd")
var failed:=false
func _init()->void:
 root.child_entered_tree.connect(func(n:Node)->void:
  if n is GameState:n.autosave=false)
 call_deferred("run")
func check(ok:bool,message:String)->void:
 if not ok:failed=true;push_error(message)
func run()->void:
 var course:=PaintedCourse.create("Tee geometry",Vector2i(128,128))
 for z in range(course.size.y):
  for x in range(course.size.x):course.height[z*course.size.x+x]=.15*x+.1*z+sin(x*.9)*.6
 course.holes=[{"tee":Vector2(-10,10),"pin":Vector2(45,-45),"par":4,"bends":[],"curve":false}]
 var tee:Vector2=course.holes[0]["tee"]
 # Deliberately wrong, square old stamp. Rendering must repair it without changing the save.
 course.paint_box(PaintedCourse.Surface.TEE,tee,Vector2(7,7),Vector2(0,-1),1.0,1.0)
 var saved_height:=course.height.duplicate();var saved_paint:=course.splat_a.duplicate()
 var sign:=Sign.for_painted(course,0);root.add_child(sign)
 var inward:=Vector3(tee.x-sign.position.x,0,tee.y-sign.position.z).normalized()
 check(sign.basis.z.dot(inward)>.999,"Front of sign must face the tee box")
 var dir:Vector2=(course.holes[0]["pin"]-tee).normalized()
 var right:=Vector2(-dir.y,dir.x)
 var offset:=Vector2(sign.position.x,sign.position.z)-tee
 check(absf(offset.dot(right))>=9.4,"Sign is too close to the tee")
 var platform:MeshInstance3D=sign.get_node("RectangularTeeSurface")
 var points:PackedVector3Array=platform.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var minp:=Vector3(INF,INF,INF);var maxp:=-minp
 for p in points:minp=minp.min(p);maxp=maxp.max(p)
 check(is_equal_approx(maxp.x-minp.x,9) and is_equal_approx(maxp.z-minp.z,12),"Tee must have a 9m narrow end and 12m length")
 check(maxp.y-minp.y<.001,"Sculpted terrain left the tee surface uneven")
 var world_basis:Basis=sign.basis*platform.basis
 check((-world_basis.z).dot(Vector3(dir.x,0,dir.y))>.999,"Narrow end is not aimed down the hole")
 var normals:PackedVector3Array=platform.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
 check(normals[0].y>.99,"Tee surface faces down instead of up")
 var adapter:=PaintedLayout.build(course)
 check(adapter.tee_sd(tee+right*4.4+dir*5.9)<0,"Gameplay adapter lost the tee corners")
 check(adapter.tee_sd(tee+right*5.3)>0,"Gameplay adapter retained the old jagged edge")
 var top:=course.height_at(tee)
 for local:Vector2 in [Vector2(0,0),Vector2(4.4,5.9),Vector2(-4.4,5.9),Vector2(4.4,-5.9),Vector2(-4.4,-5.9)]:
  var p:=tee+right*local.x+dir*local.y
  check(absf(course.height_at(p)-top)<.001,"Tee corners are not level")
  check(course.surface_at(p)==PaintedCourse.Surface.TEE,"Tee classification disagrees with rectangle")
 var outside:=tee+right*5.3
 check(course.coverage(PaintedCourse.Surface.TEE,outside)<.01,"Old jagged stamp protrudes outside new tee")
 var image:=course.height_image()
 var cell:=course.cell_of(tee+right*2+dir*3)
 var index:=Vector2i(floori(cell.x),floori(cell.y))
 check(absf(image.get_pixel(index.x,index.y).r-top)<.001,"Preview height texture disagrees with gameplay")
 check(course.height==saved_height and course.splat_a==saved_paint,"Rendering destructively changed the course sculpture")
 course.holes[0]["tee"]=Vector2(30,25);course.revision+=1
 check(absf(course.height_at(tee)-course.raw_height_at(tee))<.001,"Moving tee did not restore original terrain")
 course.holes[0]["tee"]=tee;course.revision+=1
 print("TEE GEOMETRY ","FAIL" if failed else "PASS","; sign faces tee, 5m edge clearance, rectangle orientation, flat grade, old stamp repair, gameplay/preview heights, nondestructive edits")
 if "--preview" in OS.get_cmdline_user_args():
  root.size=Vector2i(1200,900)
  var view:=PaintedView.new();root.add_child(view);view.set_course(course)
  var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("789bad")
  env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;root.add_child(env)
  var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-20,0);sun.shadow_enabled=true;root.add_child(sun)
  var eye:=Camera3D.new();root.add_child(eye);eye.near=.05
  eye.position=Vector3(tee.x-dir.x*19-right.x*6,top+19,tee.y-dir.y*19-right.y*6)
  eye.look_at(Vector3(tee.x+right.x*3,top,tee.y+right.y*3))
  for i in range(8):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/tee_geometry_fixed.png")
 quit(1 if failed else 0)
