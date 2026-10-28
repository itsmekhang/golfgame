class_name GrassStreamer
extends Node3D
## Dense 8 m batches, background placement workers, one packed GPU upload per batch.
## Per-clump shader fades hide the boundaries between distance tiers and batches.

var layout: CourseLayout
var params: Dictionary
var material: ShaderMaterial
var resident: Dictionary = {}
var pending: Array = []
var last_focus := Vector2(INF, INF)
var active := false
var built_tiles := 0
var instance_count := 0
var max_tile_build_usec := 0 # main-thread commit time only
var focus_position := Vector2.ZERO
var view_position := Vector3.ZERO
## Placement jobs in flight: [{"thread": Thread, "key": Vector2i}]. Several run at once so
## the patches around a freshly landed ball fill in within a few frames, not one by one.
var _jobs: Array = []
var _wanted: Dictionary = {}
var _cache: Dictionary = {} # bounded recently evicted CPU buffers, including empty patches
var _data: Dictionary = {}
var _suspended := false
var _lod_accum := 0.0
const CACHE_TILES := 64
const COMMITS_PER_FRAME := 6  # finished patches uploaded per frame (one buffer upload each)

static func _max_jobs() -> int:
	return clampi(OS.get_processor_count() - 2, 2, 8)

func configure(course_layout: CourseLayout, seed_value: int) -> void:
	name = "RoughGrass"
	layout = course_layout
	params = {"seed": seed_value, "band": 22.0, "density": 100.0, "far": 12.0,
		"scale": 1.0, "mode": "kolosok", "max_per_tile": PerformanceSettings.grass_per_tile()}
	material = RoughGrass._material("kolosok")
	material.set_shader_parameter("streamed_grass", true)
	material.set_shader_parameter("grass_fade_end", PerformanceSettings.grass_distance())
	RoughGrass.last_material = material
	for variant in range(RoughGrass.KOLOSOK_VARIANTS):
		for lod in range(3):
			RoughGrass._kolosok_mesh(variant, lod)
	set_meta("blade_count", 0)

func _process(delta: float) -> void:
	if not active or _suspended or not PerformanceSettings.grass_enabled():
		return
	material.set_shader_parameter("grass_focus", focus_position)
	if not is_finite(last_focus.x) or focus_position.distance_squared_to(last_focus) > 16.0:
		_refresh(focus_position)
	_lod_accum += delta
	if _lod_accum >= 0.15:
		_lod_accum = 0.0
		for key in resident:
			_update_lod(key)
	var commits := 0
	for i in range(_jobs.size() - 1, -1, -1):
		var job: Dictionary = _jobs[i]
		var thread: Thread = job["thread"]
		if thread.is_alive() or commits >= COMMITS_PER_FRAME:
			continue
		var data: Dictionary = thread.wait_to_finish()
		_jobs.remove_at(i)
		var job_key: Vector2i = job["key"]
		if _wanted.has(job_key):
			_commit(job_key, data)
			commits += 1
		else:
			_cache_put(job_key, data)
	while not pending.is_empty() and (_jobs.size() < _max_jobs() or _cache.has(pending[0])):
		var key: Vector2i = pending.pop_front()
		if _cache.has(key):
			if commits >= COMMITS_PER_FRAME:
				pending.push_front(key)
				break
			var cached: Dictionary = _cache[key]
			_cache.erase(key)
			_commit(key, cached)
			commits += 1
			continue
		var worker := Thread.new()
		var error := worker.start(RoughGrass.sample_tile_buffer.bind(layout, key, params.duplicate()))
		if error != OK:
			pending.push_front(key)
			push_error("Grass placement worker could not start: %s" % error)
			break
		_jobs.append({"thread": worker, "key": key})


func _job_running(key: Vector2i) -> bool:
	for job in _jobs:
		if job["key"] == key:
			return true
	return false

func _commit(key: Vector2i, data: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	var variant := absi(key.x * 7 + key.y * 13) % RoughGrass.KOLOSOK_VARIANTS
	var tile := RoughGrass.tile_from_buffer(key, data, RoughGrass._kolosok_mesh(variant), material)
	resident[key] = tile
	_data[key] = data
	if tile != null:
		add_child(tile)
		instance_count += tile.multimesh.instance_count
		_update_lod(key)
	set_meta("blade_count", instance_count)
	built_tiles += 1
	max_tile_build_usec = maxi(max_tile_build_usec, Time.get_ticks_usec() - start)

func _update_lod(key: Vector2i) -> void:
	var tile: MultiMeshInstance3D = resident[key]
	if tile == null:
		return
	var centre := tile.position + tile.multimesh.custom_aabb.get_center()
	# Use the nearest possible root, plus camera-motion slack. Per-root fading in
	# the shader has finished before an entire card tier or instance is culled.
	var distance := maxf(0.0, centre.distance_to(view_position) - tile.multimesh.custom_aabb.size.length() * 0.5 - 4.0)
	var lod := 0 if distance < 24.0 else (1 if distance < 38.0 else 2)
	var variant := absi(key.x * 7 + key.y * 13) % RoughGrass.KOLOSOK_VARIANTS
	if tile.get_meta("lod", -1) != lod:
		tile.multimesh.mesh = RoughGrass._kolosok_mesh(variant, lod)
		tile.set_meta("lod", lod)
	var fraction := 1.0 - 0.4 * smoothstep(16.0, 24.0, distance) - 0.3 * smoothstep(28.0, 38.0, distance)
	tile.multimesh.visible_instance_count = mini(tile.multimesh.instance_count, ceili(tile.multimesh.instance_count * (fraction + 0.05)))
	# Ground distance keeps patches visible from the overhead/scout camera too.
	tile.visible = _center(key).distance_to(focus_position) <= PerformanceSettings.grass_distance() + RoughGrass.TILE

func _refresh(focus: Vector2) -> void:
	last_focus = focus
	var radius := PerformanceSettings.grass_distance() + RoughGrass.TILE
	var keys := RoughGrass._tile_keys(layout, Rect2(focus - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	keys = keys.filter(func(key: Vector2i) -> bool: return _center(key).distance_squared_to(focus) <= radius * radius)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _center(a).distance_squared_to(focus) < _center(b).distance_squared_to(focus))
	if keys.size() > PerformanceSettings.grass_tiles():
		keys.resize(PerformanceSettings.grass_tiles())
	_wanted.clear()
	for key in keys:
		_wanted[key] = true
	for key in resident.keys():
		if not _wanted.has(key):
			_remove(key, true)
	pending.clear()
	for key in keys:
		if not resident.has(key) and not _job_running(key):
			pending.append(key)

func _center(key: Vector2i) -> Vector2:
	return layout.bounds.position + (Vector2(key) + Vector2.ONE * 0.5) * RoughGrass.TILE

func _cache_put(key: Vector2i, data: Dictionary) -> void:
	_cache.erase(key)
	_cache[key] = data
	while _cache.size() > CACHE_TILES:
		_cache.erase(_cache.keys()[0])

func _remove(key: Vector2i, remember: bool = false) -> void:
	if remember:
		_cache_put(key, _data[key])
	var tile: MultiMeshInstance3D = resident[key]
	if is_instance_valid(tile):
		instance_count -= tile.multimesh.instance_count
		remove_child(tile)
		tile.queue_free()
	resident.erase(key)
	_data.erase(key)

## Join before any terrain/straw mutation or freeing the layout.
func finish_pending() -> void:
	for job in _jobs:
		(job["thread"] as Thread).wait_to_finish()
	_jobs.clear()
	last_focus = Vector2(INF, INF)

func set_suspended(value: bool) -> void:
	_suspended = value
	if value:
		finish_pending()
		for key in resident.keys():
			_remove(key)
		_cache.clear()
		pending.clear()
		_wanted.clear()
		set_meta("blade_count", 0)

func rebuild_area(rect: Rect2) -> void:
	finish_pending()
	for key in RoughGrass._tile_keys(layout, rect.grow(RoughGrass.HAZARD_CLEARANCE)):
		if resident.has(key):
			_remove(key)
		_cache.erase(key)
	set_meta("blade_count", instance_count)

func _exit_tree() -> void:
	finish_pending()
