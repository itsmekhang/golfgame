extends SceneTree
## Where the frame time goes (windowed; ~5 min course load):
##   godot --path . --resolution 1600x900 --script tests/perf_probe.gd -- 1:tee 1:fly
## For each view, renders with everything on, then with one feature switched off at a time,
## and prints GPU / CPU ms, draw calls and primitives per config. Uses a throwaway save.

var course: Node3D
var _rid: RID
var _tri_cache := {}


func _init() -> void:
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is GameState:
			node.autosave = false
			node.save_path = "user://_perf_probe_unused.json")
	call_deferred("run")


func wait_ready() -> void:
	for i in range(4000):
		await process_frame
		if course.ball != null and course.hud != null and course.active_region.size != Vector2.ZERO and course._loading_screen == null and not course._transitioning:
			break
		if i % 10 == 0 and course._loading_screen != null:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
	await process_frame


func measure(label: String) -> void:
	for i in range(45):
		await process_frame
	var gpu := 0.0
	var cpu := 0.0
	var frames := 60
	var t0 := Time.get_ticks_usec()
	var draws := 0.0
	var prims := 0.0
	for i in range(frames):
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("[perf] %-14s gpu %6.2f ms  render-cpu %6.2f ms  frame %6.2f ms (%4.1f fps)  draws %6d  prims %9d  process %5.1f ms  physics %5.1f ms" % [label, gpu / frames, cpu / frames, wall, 1000.0 / wall, int(draws / frames), int(prims / frames), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])


func foliage_materials() -> Array:
	var out := {}
	var stack: Array = [course]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var meshes: Array = []
		if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			meshes.append(n.multimesh.mesh)
		elif n is MeshInstance3D and n.mesh != null:
			meshes.append(n.mesh)
		for m: Mesh in meshes:
			for s in range(m.get_surface_count()):
				var mat := m.surface_get_material(s)
				if mat is ShaderMaterial and mat.shader != null and mat.shader.resource_path.ends_with("nature_leaves.gdshader"):
					out[mat] = true
	return out.keys()


## Triangles submitted per vegetation batch family (name up to the last "_"), counting only
## MultiMesh tiles whose visibility range covers the camera: where the primitives come from.
func breakdown() -> void:
	var cam := root.get_viewport().get_camera_3d()
	var fam := {}
	var stack: Array = [course]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MultiMeshInstance3D) or not n.is_visible_in_tree():
			continue
		var mmi := n as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var aabb := mmi.global_transform * mmi.get_aabb()
		var d := aabb.get_center().distance_to(cam.global_position)
		if mmi.visibility_range_end > 0.0 and d > mmi.visibility_range_end:
			continue
		if d < mmi.visibility_range_begin:
			continue
		var m := mmi.multimesh.mesh
		if not _tri_cache.has(m):
			var count := 0
			for s in range(m.get_surface_count()):
				var idx: PackedInt32Array = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] if m is ArrayMesh else PackedInt32Array()
				count += idx.size() / 3
			_tri_cache[m] = count
		var tris: int = _tri_cache[m]
		# batch names are "<label>_<tile x>_<tile z>": the family is the label
		var parts := String(mmi.name).split("_")
		var key := "_".join(parts.slice(0, maxi(parts.size() - 2, 1)))
		var e: Array = fam.get(key, [0, 0, 0, mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
		e[0] += mmi.multimesh.visible_instance_count if mmi.multimesh.visible_instance_count >= 0 else mmi.multimesh.instance_count
		e[1] += tris * (mmi.multimesh.visible_instance_count if mmi.multimesh.visible_instance_count >= 0 else mmi.multimesh.instance_count)
		e[2] += 1
		fam[key] = e
	var tiers := {}
	for k in fam:
		var t := String(k).get_slice("_", String(k).get_slice_count("_") - 1)
		if String(k).begins_with("bushfar"):
			t = "bushfar"
		elif String(k).begins_with("bush"):
			t = "bush"
		tiers[t] = tiers.get(t, 0) + fam[k][1]
	print("[perf]   tiers ", tiers)
	var keys := fam.keys()
	keys.sort_custom(func(a, b) -> bool: return fam[a][1] > fam[b][1])
	for k in keys.slice(0, 25):
		print("[perf]   %-22s inst %7d  tris %10d  tiles %4d  shadow %s" % [k, fam[k][0], fam[k][1], fam[k][2], fam[k][3]])


func set_shells_visible(value: bool) -> void:
	for shell in get_nodes_in_group("turf_shells"):
		shell.visible = value


func run() -> void:
	var args := OS.get_cmdline_user_args()
	course = load("res://scenes/course.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await wait_ready()
	_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	# Measure the real cost, not the display's refresh: with the screen asleep Windows paces
	# vsync'd presents at a few Hz, which made every frame read ~240 ms regardless of content.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var env: Environment = (course.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = course.get_node("Sun")
	for k in range(args.size()):
		var parts: PackedStringArray = args[k].split(":")
		var i := int(parts[0]) - 1
		var view := parts[1] if parts.size() > 1 else "tee"
		if course.hole_index != i:
			course.transition_to_hole(i)
			await wait_ready()
		course.camera.frozen = false
		course.camera.mode = OrbitCamera.Mode.AIM
		if view == "fly":
			course.skip_swing_animation = true
			course._fire_shot(100.0, Vector2.ZERO)
			for f in range(40):
				await process_frame
			course.camera.frozen = true
		print("[perf] ---- hole %d %s" % [i + 1, view])
		await measure("all")
		var capture_dir := OS.get_environment("PERF_CAPTURE_DIR")
		if not capture_dir.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_dir.path_join("hole_%d_%s.png" % [i + 1, view]))
		if OS.get_environment("PERF_BREAKDOWN") == "1":
			breakdown()
		if OS.get_environment("PERF_LOD") == "1":
			for thr in [2.0, 4.0, 8.0]:
				root.mesh_lod_threshold = thr
				await measure("lod %.0f px" % thr)
			root.mesh_lod_threshold = 1.0
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 120.0
			await measure("2 splits 120m")
			root.mesh_lod_threshold = 4.0
			await measure("2spl + lod 4")
			root.mesh_lod_threshold = 1.0
			GolfLook.apply(env, sun)
			await measure("back to all")
		if OS.get_environment("PERF_FX") == "1":
			var lut: Texture = env.adjustment_color_correction
			env.adjustment_color_correction = null
			await measure("no-lut")
			env.adjustment_color_correction = lut
			env.ssao_enabled = false
			await measure("no-ssao")
			env.ssao_enabled = true
			env.glow_enabled = false
			await measure("no-glow")
			env.glow_enabled = true
			env.fog_enabled = false
			await measure("no-fog")
			env.fog_enabled = true
			set_shells_visible(false)
			await measure("no-shells")
			set_shells_visible(true)
			if course.minimap_viewport != null:
				var um: int = course.minimap_viewport.render_target_update_mode
				course.minimap_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				await measure("no-minimap")
				course.minimap_viewport.render_target_update_mode = um
			course.hud.visible = false
			await measure("no-hud")
			course.hud.visible = true
			course.swing_rig.visible = false
			await measure("no-golfer")
			course.swing_rig.visible = true
		if OS.get_environment("PERF_SHELLS") == "1":
			set_shells_visible(false)
			await measure("no-shells")
			set_shells_visible(true)
			course.nature_props_root.visible = false
			await measure("no-forest")
			course.nature_props_root.visible = true
			sun.shadow_enabled = false
			await measure("no-shadows")
			sun.shadow_enabled = true
			await measure("all-again")
		if OS.get_environment("PERF_SCALE") == "1":
			var vp := root.get_viewport()
			for sc in [0.67, 0.5]:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				vp.scaling_3d_scale = sc
				await measure("scale %.2f" % sc)
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.67
			await measure("fsr2 0.67")
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
		if OS.get_environment("PERF_QUICK") == "1":
			continue
		var mats := foliage_materials()
		var old_sway := {}
		for m: ShaderMaterial in mats:
			old_sway[m] = m.get_shader_parameter("sway_strength")
			m.set_shader_parameter("sway_strength", 0.0)
		await measure("no-sway")
		for m: ShaderMaterial in mats:
			m.set_shader_parameter("sway_strength", old_sway[m])
		sun.shadow_enabled = false
		await measure("no-shadows")
		sun.shadow_enabled = true
		env.ssao_enabled = false
		await measure("no-ssao")
		env.ssao_enabled = true
		env.glow_enabled = false
		env.adjustment_enabled = false
		await measure("no-glow+grade")
		env.glow_enabled = true
		env.adjustment_enabled = true
		course.grass_root.visible = false
		await measure("no-grass")
		course.grass_root.visible = true
		course.nature_props_root.visible = false
		await measure("no-forest")
		course.nature_props_root.visible = true
		for n in [course.props_root, course.decor_root]:
			if n != null:
				n.visible = false
		await measure("no-props")
		for n in [course.props_root, course.decor_root]:
			if n != null:
				n.visible = true
		course.hud.visible = false
		await measure("no-hud")
		course.hud.visible = true
		course.terrain_root.visible = false
		await measure("no-terrain")
		course.terrain_root.visible = true
		if course.hazards_root != null:
			course.hazards_root.visible = false
			await measure("no-water")
			course.hazards_root.visible = true
		await measure("all-again")
	quit(0)
