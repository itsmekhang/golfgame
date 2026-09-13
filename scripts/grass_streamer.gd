class_name GrassStreamer
extends Node3D
## Dense 8 m patches, one placement worker, one packed GPU upload per patch.
## Nearby patches retain all cards; distance tiers reduce geometry and density.

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
var _worker: Thread
var _job_key := Vector2i.ZERO
var _wanted: Dictionary = {}
var _cache: Dictionary = {} # bounded recently evicted CPU buffers, including empty patches
var _data: Dictionary = {}
var _suspended := false
var _lod_accum := 0.0
const CACHE_TILES := 64

func configure(course_layout: CourseLayout, seed_value: int) -> void:
	name = "RoughGrass"
	layout = course_layout
	params = {"seed": seed_value, "band": 22.0, "density": 100.0, "far": 12.0,
		"scale": 1.0, "mode": "kolosok", "max_per_tile": PerformanceSettings.grass_per_tile()}
	material = RoughGrass._material("kolosok")
	RoughGrass.last_material = material
	for variant in range(RoughGrass.KOLOSOK_VARIANTS):
		for lod in range(3):
			RoughGrass._kolosok_mesh(variant, lod)
	set_meta("blade_count", 0)

func _process(delta: float) -> void:
	if not active or _suspended or not PerformanceSettings.grass_enabled():
		return
	if not is_finite(last_focus.x) or focus_position.distance_squared_to(last_focus) > 16.0:
		_refresh(focus_position)
	_lod_accum += delta
	if _lod_accum >= 0.15:
		_lod_accum = 0.0
		for key in resident:
			_update_lod(key)
	if _worker != null:
		if _worker.is_alive():
			return
		var data: Dictionary = _worker.wait_to_finish()
		_worker = null
		if _wanted.has(_job_key):
			_commit(_job_key, data)
		else:
			_cache_put(_job_key, data)
	if pending.is_empty():
		return
	var key: Vector2i = pending.pop_front()
	if _cache.has(key):
		var data: Dictionary = _cache[key]
		_cache.erase(key)
		_commit(key, data)
		return
	_job_key = key
	_worker = Thread.new()
	var error := _worker.start(RoughGrass.sample_tile_buffer.bind(layout, key, params.duplicate()))
	if error != OK:
		_worker = null
		pending.push_front(key)
		push_error("Grass placement worker could not start: %s" % error)

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
	var distance := centre.distance_to(view_position)
	var lod := 0 if distance < 20.0 else (1 if distance < 34.0 else 2)
	var variant := absi(key.x * 7 + key.y * 13) % RoughGrass.KOLOSOK_VARIANTS
	if tile.get_meta("lod", -1) != lod:
		tile.multimesh.mesh = RoughGrass._kolosok_mesh(variant, lod)
		var fraction: float = [1.0, 0.60, 0.30][lod]
		tile.multimesh.visible_instance_count = maxi(1, int(tile.multimesh.instance_count * fraction))
		tile.set_meta("lod", lod)
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
		if not resident.has(key) and not (_worker != null and key == _job_key):
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
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
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
