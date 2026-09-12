class_name GrassStreamer
extends Node3D
## Deterministic 32 m grass tiles. Never more than one new tile per frame, and
## never more than the configured resident tile/instance budgets. No spawn timers.

var layout: CourseLayout
var params: Dictionary
var material: ShaderMaterial
var resident: Dictionary = {} # includes empty tiles, to avoid retrying fairways
var pending: Array = []
var last_focus := Vector2(INF, INF)
var active := false
var built_tiles := 0
var instance_count := 0
var max_tile_build_usec := 0
## World XZ grass streams around, set explicitly by course.gd each frame (the ball's
## position) rather than read from the camera -- the Z scout camera can jump far from the
## ball to preview a landing spot, and streaming around wherever the camera happens to be
## would trigger a full tile eviction/rebuild storm (a visible FPS stutter) on every press
## and release instead of just following where the player actually is.
var focus_position := Vector2.ZERO

func configure(course_layout: CourseLayout, seed_value: int) -> void:
	name = "RoughGrass"
	layout = course_layout
	# Maxed-out, dense-carpet coverage everywhere in the rough, not just near turf --
	# max_per_tile (see PerformanceSettings) is the real backstop against runaway instance
	# counts, not this density value itself; density/far are set high enough that
	# essentially every resident tile saturates that cap instead of reading thin/stubbly.
	params = {"seed": seed_value, "band": 22.0, "density": 100.0, "far": 8.0,
		"scale": 1.0, "mode": "kolosok", "max_per_tile": PerformanceSettings.grass_per_tile()}
	material = RoughGrass._material("kolosok")
	RoughGrass.last_material = material
	# Load the six tiny baked resources once, outside the streaming loop.
	for i in range(RoughGrass.KOLOSOK_VARIANTS):
		RoughGrass._kolosok_mesh(i)
	set_meta("blade_count", 0)

func _process(_delta: float) -> void:
	if not active or not PerformanceSettings.grass_enabled():
		return
	if not is_finite(last_focus.x) or focus_position.distance_squared_to(last_focus) > 64.0:
		_refresh(focus_position)
	if pending.is_empty():
		return
	var start := Time.get_ticks_usec()
	var key: Vector2i = pending.pop_front()
	var variant := absi(key.x * 7 + key.y * 13) % RoughGrass.KOLOSOK_VARIANTS
	var tile := RoughGrass._build_tile(layout, key, params, RoughGrass._kolosok_mesh(variant), material)
	resident[key] = tile
	if tile != null:
		tile.layers = PerformanceSettings.DETAIL_LAYER
		add_child(tile)
		instance_count += tile.multimesh.instance_count
	set_meta("blade_count", instance_count)
	built_tiles += 1
	max_tile_build_usec = maxi(max_tile_build_usec, Time.get_ticks_usec() - start)

func _refresh(focus: Vector2) -> void:
	last_focus = focus
	var radius := PerformanceSettings.grass_distance() + RoughGrass.TILE
	var keys := RoughGrass._tile_keys(layout, Rect2(focus - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _center(a).distance_squared_to(focus) < _center(b).distance_squared_to(focus))
	if keys.size() > PerformanceSettings.grass_tiles():
		keys.resize(PerformanceSettings.grass_tiles())
	var wanted: Dictionary = {}
	for key in keys:
		wanted[key] = true
	for key in resident.keys():
		if not wanted.has(key):
			_remove(key)
	pending.clear()
	for key in keys:
		if not resident.has(key):
			pending.append(key)

func _center(key: Vector2i) -> Vector2:
	return layout.bounds.position + (Vector2(key) + Vector2.ONE * 0.5) * RoughGrass.TILE

func _remove(key: Vector2i) -> void:
	var tile: MultiMeshInstance3D = resident[key]
	if is_instance_valid(tile):
		instance_count -= tile.multimesh.instance_count
		remove_child(tile)
		tile.queue_free()
	resident.erase(key)

func rebuild_area(rect: Rect2) -> void:
	for key in RoughGrass._tile_keys(layout, rect.grow(RoughGrass.HAZARD_CLEARANCE)):
		if resident.has(key):
			_remove(key)
	last_focus = Vector2(INF, INF)
	set_meta("blade_count", instance_count)
