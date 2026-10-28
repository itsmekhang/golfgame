class_name TeeHoleSign
extends RefCounted
## A stationary, double-sided tee plaque. All figures and the schematic follow the
## actual hole; one tee means one yardage. No camera-facing or screen-sized parts.
const CREAM := Color("f5efda")
const SIZE := Vector2(1.35,1.9)

static func for_painted(course: PaintedCourse, index: int) -> Node3D:
 var route := course.hole_route(index)
 return build(index+1,course.hole_par(index),course.hole_yards(index),route,course.course_name,course.height_at,{"painted":course})

static func for_layout(layout: CourseLayout, hole: CourseLayout.Hole) -> Node3D:
 var route := PackedVector2Array()
 for p in hole.waypoints:route.append(Vector2(p.x,p.z))
 if layout is PaintedLayout:route=layout.course.hole_route(hole.index)
 return build(hole.index+1,hole.par,roundi(hole.length_yd),route,layout.name_pretty,
  func(p:Vector2)->float:return layout.height_at(p.x,p.y),_layout_hazards(layout))

static func build(number:int, par:int, yards:int, route:PackedVector2Array, club:String, height_at:Callable, hazards:Dictionary={})->Node3D:
 var root:=Node3D.new();root.name="TeeSign%d"%number
 if route.size()<2:return root
 var direction:Vector2=(route[1]-route[0]).normalized()
 if direction.is_zero_approx():direction=Vector2(0,-1)
 var right:=Vector2(-direction.y,direction.x)
 # Outside the 9m-wide tee pad and behind its front line, clear of shots/markers.
 var site:=route[0]+right*9.5-direction*2.5
 root.position=Vector3(site.x,height_at.call(site),site.y)
 var inward:Vector2=(route[0]-site).normalized()
 root.rotation.y=atan2(inward.x,inward.y)
 root.set_meta("hole_number",number);root.set_meta("par",par);root.set_meta("yards",yards)
 root.set_meta("route",route)
 var tee_surface:=_tee_surface(route[0],direction,height_at)
 tee_surface.transform=root.transform.affine_inverse()*tee_surface.transform
 root.add_child(tee_surface)
 var green:=StandardMaterial3D.new();green.albedo_color=Color("123f30");green.roughness=.75
 for x in [-.43,.43]:
  var post:=MeshInstance3D.new();post.name="LeftPost" if x<0 else "RightPost"
  var box:=BoxMesh.new();box.size=Vector3(.085,.65,.065);post.mesh=box
  post.material_override=green;post.position=Vector3(x,.325,0);root.add_child(post)
 _solid_board(root,green)
 var face_texture:=_face_texture(route,hazards)
 var face_material:=StandardMaterial3D.new();face_material.albedo_texture=face_texture
 face_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
 face_material.alpha_scissor_threshold=.5;face_material.roughness=.85
 # Separate front and rear let the lettering read correctly from either side.
 for back in [false,true]:
  var face:=Node3D.new();face.name="Back" if back else "Front"
  face.position=Vector3(0,1.55,-.045 if back else .045)
  if back:face.rotation.y=PI
  root.add_child(face)
  var panel:=MeshInstance3D.new();panel.name="ArchedPlaque"
  var quad:=QuadMesh.new();quad.size=SIZE;panel.mesh=quad;panel.material_override=face_material
  face.add_child(panel)
  _label(face,"ClubCrest","GC",Vector2(0,.77),.085)
  _label(face,"HoleNumber",str(number),Vector2(-.31,.36),.34)
  _label(face,"Par","PAR %d"%par,Vector2(.27,.38),.14)
  _label(face,"TeeName","PRO TEE",Vector2(-.29,.10),.065)
  _label(face,"Yardage",str(yards),Vector2(-.29,-.08),.23)
  _label(face,"YardsUnit","YARDS",Vector2(-.29,-.25),.07)
  _label(face,"LayoutCaption","HOLE LAYOUT",Vector2(.29,-.73),.043)
  var title:=club.to_upper()
  if title.length()>29:title=title.left(27)+"..."
  _label(face,"CourseName",title,Vector2(0,-.84),.042)
 return root

static func _label(parent:Node3D,node_name:String,value:String,at:Vector2,height:float)->void:
 var label:=Label3D.new();label.name=node_name;label.text=value
 label.font=UITheme.font(700);label.font_size=96;label.pixel_size=height/96.0
 label.modulate=CREAM;label.outline_size=0;label.shaded=false
 label.position=Vector3(at.x,at.y,.007);parent.add_child(label)

static func _face_texture(route:PackedVector2Array,hazards:Dictionary={})->ImageTexture:
 # Rotate the real route so the tee is at the bottom. Keep one uniform scale;
 # doglegs retain their direction and proportions rather than using stock art.
 var forward:Vector2=(route[-1]-route[0]).normalized()
 if forward.is_zero_approx():forward=Vector2(0,-1)
 var across:=Vector2(-forward.y,forward.x)
 var points:=PackedVector2Array()
 var bounds:=Rect2(Vector2.ZERO,Vector2.ZERO)
 for p in route:
  var offset:=p-route[0]
  var q:=Vector2(offset.dot(across),-offset.dot(forward))
  points.append(q);bounds=bounds.expand(q)
 bounds=bounds.grow(38.0)
 var scale_value:=minf(280.0/maxf(bounds.size.x,1),720.0/maxf(bounds.size.y,1))
 var center:=Vector2(742,955)
 var path:=""
 for p in points:
  var q:=center+(p-bounds.get_center())*scale_value
  path+=("M" if path=="" else " L")+"%.2f %.2f"%[q.x,q.y]
 var tee:=center+(points[0]-bounds.get_center())*scale_value
 var pin:=center+(points[-1]-bounds.get_center())*scale_value
 var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1536" viewBox="0 0 1024 1536">'
 var outline:='M 20 1516 L 20 245 L 210 245 C 305 -60 719 -60 814 245 L 1004 245 L 1004 1516 Z'
 svg+='<path d="%s" fill="#0e4938" stroke="#153728" stroke-width="30"/>'%outline
 svg+='<path d="%s" fill="none" stroke="#f5efda" stroke-width="10"/>'%outline
 svg+='<path d="M 510 70 L 580 100 L 575 180 Q 510 265 445 180 L 440 100 Z" fill="none" stroke="#f5efda" stroke-width="7"/>'
 svg+='<path d="M 95 580 H 930" stroke="#a9b58a" stroke-width="3"/>'
 svg+='<path d="%s" fill="none" stroke="#22734a" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/>'%[path,maxf(12,40*scale_value)]
 svg+='<path d="%s" fill="none" stroke="#8fba58" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/>'%[path,maxf(7,23*scale_value)]
 svg+=_hazard_svg(hazards,route[0],forward,across,bounds,scale_value,center)
 svg+='<ellipse cx="%.2f" cy="%.2f" rx="%.2f" ry="%.2f" fill="#b1cd77" stroke="#e1e1ae" stroke-width="2"/>'%[pin.x,pin.y,maxf(9,12*scale_value),maxf(12,15*scale_value)]
 svg+='<rect x="%.2f" y="%.2f" width="14" height="10" rx="2" fill="#f5efda"/>'%[tee.x-7,tee.y-5]
 svg+='<path d="M %.2f %.2f v -28 l 19 6 l -19 6" fill="#da6655" stroke="#f5efda" stroke-width="2"/>'%[pin.x,pin.y]
 svg+='</svg>'
 var image:=Image.new();image.load_svg_from_string(svg);image.generate_mipmaps()
 return ImageTexture.create_from_image(image)


static func _layout_hazards(layout:CourseLayout)->Dictionary:
 if layout is PaintedLayout:return {"painted":layout.course}
 var polygons:=[]
 for bunker in layout.bunkers:polygons.append({"polygon":bunker.polygon,"color":"#e5cd91"})
 for water in layout.water_hazards:polygons.append({"polygon":water.polygon,"color":"#43a9dc"})
 return {"polygons":polygons}

static func _hazard_svg(hazards:Dictionary,origin:Vector2,forward:Vector2,across:Vector2,bounds:Rect2,scale_value:float,center:Vector2)->String:
 var svg:='<defs><clipPath id="map"><rect x="590" y="590" width="304" height="735"/></clipPath></defs><g clip-path="url(#map)">'
 if hazards.has("painted"):
  var course:PaintedCourse=hazards["painted"]
  var layer:=course.layer_a()
  var extent:=Rect2(course.origin,Vector2(course.size)*PaintedCourse.CELL)
  # Scan small rows once when the sign is built; no per-frame map work.
  # Nearest-cell coverage preserves the same sand/water edges as the painting.
  for row in range(245):
   var run_start:=-1
   var run_surface:=-1
   for column in range(102):
    var surface:=-1
    if column<101:
     var q:Vector2=(Vector2(590+(column+.5)*3,590+(row+.5)*3)-center)/scale_value+bounds.get_center()
     var world:Vector2=origin+across*q.x-forward*q.y
     if extent.has_point(world):surface=course.surface_nearest(world,layer)
     if surface not in [PaintedCourse.Surface.WATER,PaintedCourse.Surface.BUNKER]:surface=-1
    if surface!=run_surface:
     if run_start>=0:
      var color:="#43a9dc" if run_surface==PaintedCourse.Surface.WATER else "#e5cd91"
      svg+='<rect x="%d" y="%d" width="%d" height="3.1" fill="%s"/>'%[590+run_start*3,590+row*3,(column-run_start)*3,color]
     run_start=column if surface!=-1 else -1
     run_surface=surface
 else:
  for hazard in hazards.get("polygons",[]):
   var coords:=""
   for p:Vector2 in hazard["polygon"]:
    var offset:=p-origin
    var local:=Vector2(offset.dot(across),-offset.dot(forward))
    var q:=center+(local-bounds.get_center())*scale_value
    coords+="%.2f,%.2f "%[q.x,q.y]
   svg+='<polygon points="%s" fill="%s"/>'%[coords,hazard["color"]]
 return svg+"</g>"

static func _solid_board(parent:Node3D,material:Material)->void:
 # Opaque 9cm body behind both faces. Supports cannot show through the sign.
 var outline:=PackedVector2Array([Vector2(20,1516),Vector2(20,245),Vector2(210,245)])
 for step in range(1,25):
  var t:=float(step)/24.0
  outline.append(pow(1-t,3)*Vector2(210,245)+3*pow(1-t,2)*t*Vector2(305,-60)+3*(1-t)*t*t*Vector2(719,-60)+t*t*t*Vector2(814,245))
 outline.append(Vector2(1004,245));outline.append(Vector2(1004,1516))
 for i in range(outline.size()):outline[i]=Vector2((outline[i].x/1024.0-.5)*SIZE.x,(.5-outline[i].y/1536.0)*SIZE.y)
 var indices:=Geometry2D.triangulate_polygon(outline)
 var mesh:=SurfaceTool.new();mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
 for depth in [-.044,.044]:
  for i in range(0,indices.size(),3):
   var triangle:=[indices[i],indices[i+1],indices[i+2]]
   if depth<0:triangle.reverse()
   for index in triangle:mesh.add_vertex(Vector3(outline[index].x,outline[index].y,depth))
 for i in range(outline.size()):
  var a:=outline[i];var b:=outline[(i+1)%outline.size()]
  for v in [Vector3(a.x,a.y,-.044),Vector3(b.x,b.y,-.044),Vector3(b.x,b.y,.044),Vector3(a.x,a.y,-.044),Vector3(b.x,b.y,.044),Vector3(a.x,a.y,.044)]:mesh.add_vertex(v)
 mesh.generate_normals()
 var body:=MeshInstance3D.new();body.name="SolidSignBody";body.mesh=mesh.commit();body.material_override=material
 body.position.y=1.55;parent.add_child(body)


static func _tee_surface(center:Vector2,direction:Vector2,height_at:Callable)->MeshInstance3D:
 # Actual mesh edges, rather than the 1m splat pixels, form the tee rectangle.
 # Its 9m narrow end faces down the hole; its 12m length runs along play.
 var half:=PaintedCourse.TEE_BOX_HALF
 var right:=Vector2(-direction.y,direction.x)
 var base_height:float=height_at.call(center)
 var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for z in range(12):
  for x in range(9):
   for corner in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]:
    var uv:Vector2=Vector2((x+corner.x)/9.0,(z+corner.y)/12.0)
    var offset:Vector2=(uv*2-Vector2.ONE)*half
    var world:Vector2=center+right*offset.x+direction*offset.y
    surface.set_uv(uv)
    surface.add_vertex(Vector3(offset.x,float(height_at.call(world))-base_height+.008,-offset.y))
 surface.generate_normals()
 var mesh:=MeshInstance3D.new();mesh.name="RectangularTeeSurface";mesh.mesh=surface.commit()
 mesh.position=Vector3(center.x,base_height,center.y)
 mesh.rotation.y=atan2(-direction.x,-direction.y)
 var grass:=ShaderMaterial.new();grass.shader=load("res://shaders/tee_surface.gdshader")
 grass.set_shader_parameter("rough_texture",load("res://assets/textures/tiles/rough_variants/rough_001_albedo.png"))
 grass.set_shader_parameter("rough_color",TerrainBuilder.ROUGH_COLOR)
 grass.set_shader_parameter("tee_texture",load("res://assets/textures/tiles/green_tile.png"))
 grass.set_shader_parameter("tee_color",Color("75934b"))
 mesh.material_override=grass
 return mesh
