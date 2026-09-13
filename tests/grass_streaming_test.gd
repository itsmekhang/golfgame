extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(15.0).timeout.connect(func() -> void: quit(1))
	var layout := CourseLayout.new()
	layout.bounds = Rect2(100, 200, 160, 160)
	layout.cache_cell = 2.0
	layout.cache_nx = 81
	layout.cache_nz = 81
	var cells := 81 * 81
	layout.cache_surface.resize(cells)
	layout.cache_surface.fill(PhysicsEnums.SurfaceType.ROUGH)
	layout.cache_turf.resize(cells)
	layout.cache_turf.fill(5.0)
	layout.cache_green.resize(cells)
	layout.cache_green.fill(30.0)
	layout.cache_height.resize(cells)
	layout.cache_height.fill(3.0)
	var params := {"seed": 7, "band": 22.0, "density": 100.0, "far": 12.0,
		"scale": 1.0, "mode": "kolosok", "max_per_tile": 1600}
	var key := Vector2i(5, 5)
	var a := RoughGrass.sample_tile_buffer(layout, key, params)
	var b := RoughGrass.sample_tile_buffer(layout, key, params)
	assert(a["buffer"] == b["buffer"], "Placement must be deterministic")
	assert(a["count"] >= 1500 and a["count"] <= 1600, "Nearby rough should have dense coverage")
	var mat := RoughGrass._material("kolosok")
	var tile := RoughGrass.tile_from_buffer(key, a, RoughGrass._kolosok_mesh(0), mat)
	root.add_child(tile)
	for i in range(tile.multimesh.instance_count):
		var buffer: PackedFloat32Array = a["buffer"]
		var p := tile.position + Vector3(buffer[i * 16 + 3], buffer[i * 16 + 7], buffer[i * 16 + 11])
		assert(is_equal_approx(p.y, 3.0), "Packed transforms changed ground height")
		assert(p.x >= 139.0 and p.x <= 147.0 and p.z >= 239.0 and p.z <= 247.0)
		assert(tile.multimesh.custom_aabb.has_point(p - tile.position))
	var triangles: Array = []
	for lod in range(3):
		triangles.append(RoughGrass._kolosok_mesh(0, lod).get_faces().size() / 3)
	assert(triangles == [24, 12, 6], "Distance tiers must reduce card geometry")
	tile.free()
	var grass := GrassStreamer.new()
	grass.configure(layout, 7)
	root.add_child(grass)
	grass.focus_position = Vector2(145, 245)
	grass.view_position = Vector3(145, 5, 245)
	grass.active = true
	for frame in range(160):
		await create_timer(0.002).timeout
		if grass.built_tiles >= 8:
			break
	assert(grass.built_tiles >= 8 and grass.instance_count > 0, "Worker did not populate grass")
	assert(grass.resident.size() <= PerformanceSettings.grass_tiles())
	var commit_ms := grass.max_tile_build_usec / 1000.0
	# Scout away, then return: retained buffers should be reused rather than rebuilt.
	grass.focus_position += Vector2(80, 0)
	grass._refresh(grass.focus_position)
	assert(grass._cache.size() > 0 and grass._cache.size() <= GrassStreamer.CACHE_TILES)
	grass.finish_pending()
	grass.rebuild_area(Rect2(100, 200, 160, 160))
	assert(grass.resident.is_empty() and grass._cache.is_empty(), "Edited grass survived invalidation")
	grass.set_suspended(true)
	assert(grass._worker == null and grass.instance_count == 0)
	grass.free()
	print("GRASS STREAMING: PASS; dense patch %d clumps; LOD triangles %s; max commit %.2f ms" % [a["count"], triangles, commit_ms])
	quit()
