class_name ManagerGreenPins
extends RefCounted
const TEE_SIGN = preload("res://scripts/tee_hole_sign.gd")
const FLAG:=preload("res://assets/world_flagstick/world_flagstick.tscn")
static func install(view:PaintedView, course:PaintedCourse)->void:
	var previous:=view.get_node_or_null("GreenPins")
	if previous!=null:view.remove_child(previous);previous.queue_free()
	var root:=Node3D.new();root.name="GreenPins";view.add_child(root)
	var arrays:=view.terrain.mesh.surface_get_arrays(0)
	var colors:=PackedColorArray();colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size());colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR]=colors
	var terrain:=ArrayMesh.new();terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for i in range(course.holes.size()):
		root.add_child(TEE_SIGN.for_painted(course,i))
		var route := course.hole_route(i)
		var direction := (route[1] - route[0]).normalized() if route.size() > 1 else Vector2(0, -1)
		terrain = TerrainCupCutout.cut_rectangle(terrain, course.holes[i]["tee"] - Vector2(view.terrain.position.x, view.terrain.position.z), direction, PaintedCourse.TEE_BOX_HALF)
		var p:Vector2=course.holes[i]["pin"]
		terrain=TerrainCupCutout.cut(terrain,p-Vector2(view.terrain.position.x,view.terrain.position.z),GolfBall.CUP_RADIUS)
		var cup:=Node3D.new();cup.name="GreenCup%d"%(i+1);cup.position=Vector3(p.x,course.height_at(p),p.y);root.add_child(cup)
		var wall:=MeshInstance3D.new();wall.name="CupLiner"
		var liner:=CylinderMesh.new();liner.top_radius=GolfBall.CUP_RADIUS;liner.bottom_radius=GolfBall.CUP_RADIUS;liner.height=.16
		liner.cap_top=false;liner.cap_bottom=false;liner.radial_segments=32;wall.mesh=liner
		var inside:=StandardMaterial3D.new();inside.albedo_color=Color("6b7368");inside.cull_mode=BaseMaterial3D.CULL_FRONT;inside.roughness=1
		wall.material_override=inside;wall.position.y=-.08;cup.add_child(wall)
		var bottom:=MeshInstance3D.new();bottom.name="CupFloor"
		var base:=CylinderMesh.new();base.top_radius=GolfBall.CUP_RADIUS;base.bottom_radius=GolfBall.CUP_RADIUS;base.height=.01;base.radial_segments=32
		bottom.mesh=base;bottom.position.y=-.165
		var dark:=StandardMaterial3D.new();dark.albedo_color=Color("080908");bottom.material_override=dark;cup.add_child(bottom)
		var rim:=MeshInstance3D.new();rim.name="CupRim"
		var ring:=TorusMesh.new();ring.inner_radius=GolfBall.CUP_RADIUS-.003;ring.outer_radius=GolfBall.CUP_RADIUS+.005;ring.rings=32;ring.ring_segments=8
		rim.mesh=ring;rim.position.y=-.004
		var white:=StandardMaterial3D.new();white.albedo_color=Color("eae8dc");rim.material_override=white;cup.add_child(rim)
		var pin:=FLAG.instantiate() as Node3D;pin.name="Flagpin%d"%(i+1)
		pin.set("phase_offset",i*.7);pin.set("flag_color",[Color("ca3341"),Color("163b60"),Color("d7ac43")][i%3])
		pin.set("wind_velocity",Vector3(2.2,0,.7));pin.set("pole_collision_layer",0);cup.add_child(pin)
		pin.call("place_in_cup",cup.global_position,.12)
	view.terrain.mesh=terrain
