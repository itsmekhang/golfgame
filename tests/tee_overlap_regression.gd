extends SceneTree
var failed := false
func _init() -> void:
	root.child_entered_tree.connect(func(n: Node) -> void:
		if n is GameState: n.autosave = false)
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func area(mesh: ArrayMesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var total := 0.0
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		total += (b-a).cross(c-a).length() * 0.5
	return total
func run() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(40,40)
	plane.subdivide_width = 20
	plane.subdivide_depth = 20
	var arrays := plane.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colors.fill(Color.WHITE)
	arrays[Mesh.ARRAY_COLOR] = colors
	var original := ArrayMesh.new()
	original.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for angle in [0.0,0.4,1.1]:
		var center := Vector2(1.2,-3.4)
		var dir := Vector2.from_angle(angle)
		var cut := TerrainCupCutout.cut_rectangle(original,center,dir,PaintedCourse.TEE_BOX_HALF)
		check(absf(area(cut) - (1600.0-108.0)) < 0.01, "Tee cutout removed the wrong area")
		var a := cut.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ids: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var right := Vector2(-dir.y,dir.x)
		for i in range(0,ids.size(),3):
			var midpoint := (v[ids[i]]+v[ids[i+1]]+v[ids[i+2]])/3.0
			var d := Vector2(midpoint.x,midpoint.z)-center
			check(absf(d.dot(right)) >= 4.4999 or absf(d.dot(dir)) >= 5.9999, "Old ground remains underneath the tee")
	var cup := TerrainCupCutout.cut(original,Vector2.ZERO,0.1)
	check(absf(area(cup)-(1600-PI*0.01)) < 0.001, "Cup cutout regressed")
	var course := PaintedCourse.create("Clean first tee",Vector2i(128,128))
	course.holes = [{"tee":Vector2(-10,10),"pin":Vector2(40,-40),"par":4,"bends":[],"curve":false}]
	course.paint_box(PaintedCourse.Surface.TEE,Vector2(-10,10),Vector2(7,7),Vector2.UP,1.0,1.0)
	var view := PaintedView.new()
	root.add_child(view)
	view.set_course(course)
	ManagerGreenPins.install(view,course)
	check(view.get_node("GreenPins/TeeSign1/RectangularTeeSurface") != null,"Replacement tee surface missing")
	if DisplayServer.get_name() != "headless":
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("789bad")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.6
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45,-20,0)
		root.add_child(sun)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(-25,30,35)
		camera.look_at(Vector3(-10,0,10))
		for tick in range(10): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/willi/Documents/ChatGPT/golfgame/tee_overlap_fixed.png")
	print("TEE OVERLAP: ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
