class_name PropScatter
extends RefCounted
## Scatters the Golf Nature Pack's understory (grasses, ferns, flowers, ground cover,
## rocks, fallen wood) across the rough with MultiMeshInstance3D batches, and dresses
## water hazards' shorelines. Trees are ForestPlanter's job.

const OBSTACLE_LAYER := 2


class PropSpec:
	var meshes: Array[String]
	var count: int  # per hectare
	var min_dist_to_fairway: float
	var scale_range: Vector2
	var collider_radius: float  # 0 = none
	var collider_height: float
	func _init(p_meshes: Array[String], p_count: int, p_min_dist: float, p_scale: Vector2,
			p_col_r: float = 0.0, p_col_h: float = 0.0) -> void:
		meshes = p_meshes
		count = p_count
		min_dist_to_fairway = p_min_dist
		scale_range = p_scale
		collider_radius = p_col_r
		collider_height = p_col_h


## Props per hectare of course.
static func specs() -> Array[PropSpec]:
	return [
		PropSpec.new(["rough_clump_A", "rough_clump_B", "dry_grass_clump_A", "dry_grass_clump_B", "fairway_clump_A", "fairway_clump_B"], 40, 0.5, Vector2(0.8, 1.3)),
		PropSpec.new(["fescue_tussock_A", "fescue_tussock_B", "broomsedge_A", "broomsedge_B", "rushes_A", "rushes_B"], 16, 1.5, Vector2(0.7, 1.2)),
		PropSpec.new(["sword_fern_A", "sword_fern_B", "bracken_fern_A", "bracken_fern_B", "hosta_A", "hosta_B"], 10, 4.0, Vector2(0.7, 1.1)),
		PropSpec.new(["daisy_patch", "buttercup_patch", "wildflower_mix", "clover_patch"], 10, 1.5, Vector2(0.8, 1.3)),
		PropSpec.new(["pine_straw", "leaf_litter", "ivy_patch", "moss_patch"], 14, 6.0, Vector2(0.9, 1.5)),
		PropSpec.new(["mushroom_cluster"], 3, 5.0, Vector2(0.7, 1.1)),
		PropSpec.new(["pink_muhly_A", "pink_muhly_B", "pampas_grass_A", "pampas_grass_B", "blue_flag_iris_A", "blue_flag_iris_B"], 3, 3.0, Vector2(0.7, 1.1)),
		PropSpec.new(["granite_boulder_A", "granite_boulder_B", "limestone_boulder_A", "limestone_boulder_B", "mossy_boulder_A", "mossy_boulder_B", "rock_outcrop_A", "rock_outcrop_B"], 1, 8.0, Vector2(0.6, 1.2), 1.1, 1.8),
		PropSpec.new(["flat_slab_A", "flat_slab_B", "river_stones_A", "river_stones_B", "pebble_cluster_A", "pebble_cluster_B"], 3, 3.0, Vector2(0.6, 1.2)),
		PropSpec.new(["stump_low", "stump_tall", "fallen_log", "fallen_log_mossy", "driftwood", "dead_branch"], 2, 7.0, Vector2(0.8, 1.2), 0.8, 0.8),
	]


## Returns a Node3D containing all scattered props and an obstacle StaticBody3D.
## `region`: when non-empty, only scatter within region.intersection(layout.bounds) instead of
## the whole course (see course.gd's _ensure_hole_region) -- density per hectare is unchanged,
## only the total count shrinks with the smaller area.
static func scatter(layout: CourseLayout, rng_seed: int = 7, _random_trees: bool = true, region: Rect2 = Rect2()) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var obstacles := StaticBody3D.new()
	obstacles.name = "Obstacles"
	obstacles.collision_layer = OBSTACLE_LAYER
	obstacles.collision_mask = 0
	root.add_child(obstacles)

	var b := region.intersection(layout.bounds) if region.size != Vector2.ZERO else layout.bounds
	var hectares := b.size.x * b.size.y / 10000.0
	for spec in specs():
		var per_mesh: Dictionary = {}
		for m in spec.meshes:
			per_mesh[m] = []
		var want := int(spec.count * hectares)
		var placed := 0
		var attempts := 0
		while placed < want and attempts < want * 30:
			attempts += 1
			var x := rng.randf_range(b.position.x + 3.0, b.end.x - 3.0)
			var z := rng.randf_range(b.position.y + 3.0, b.end.y - 3.0)
			var xz := Vector2(x, z)
			if layout.cached_surface(xz) != PhysicsEnums.SurfaceType.ROUGH:
				continue
			# Thick dampening border: density ramps from 0 at min_dist_to_fairway up to
			# full over FORAGE_BORDER_WIDTH more metres into the rough.
			var turf_d := layout.cached_turf(xz)
			if turf_d < spec.min_dist_to_fairway:
				continue
			var damp := clampf((turf_d - spec.min_dist_to_fairway) / CourseLayout.FORAGE_BORDER_WIDTH, 0.0, 1.0)
			if rng.randf() > damp:
				continue
			if layout.hazard_near(xz, 4.0) or layout.bunker_near(xz, 3.0):
				continue
			# Exact analytic height, not the coarse cache: on slopes the bilinear cache can
			# undershoot enough that a prop visibly floats.
			var y := layout.height_at(x, z)
			var sc := rng.randf_range(spec.scale_range.x, spec.scale_range.y)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sc, sc, sc))
			var mesh_name: String = spec.meshes[rng.randi_range(0, spec.meshes.size() - 1)]
			(per_mesh[mesh_name] as Array).append(Transform3D(basis, Vector3(x, y - 0.05, z)))
			placed += 1
			if spec.collider_radius > 0.0:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = spec.collider_radius * sc
				cyl.height = spec.collider_height * sc
				cs.shape = cyl
				cs.position = Vector3(x, y + cyl.height * 0.5, z)
				obstacles.add_child(cs)

		for mesh_name in per_mesh.keys():
			var xforms: Array = per_mesh[mesh_name]
			if xforms.is_empty():
				continue
			var mesh := NaturePack.mesh(mesh_name)
			if mesh == null:
				continue
			var large := spec.collider_radius > 0.0
			VegetationBatches.add_batches(root, mesh_name, mesh, xforms, null, large,
				PerformanceSettings.tree_distance() if large else PerformanceSettings.prop_distance(), 128.0 if large else 32.0, not large)

	return root


## Decorative props: stones, reeds, cattails and lily pads along every water hazard's
## shoreline (one MultiMesh per model). `region`: when non-empty, skip hazards outside it.
static func decorate(layout: CourseLayout, rng_seed: int = 11, region: Rect2 = Rect2()) -> Node3D:
	var root := Node3D.new()
	root.name = "Decor"
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var rock_names := ["river_stones_A", "river_stones_B", "pebble_cluster_A", "pebble_cluster_B", "flat_slab_A"]
	var reed_names := ["reeds_A", "reeds_B", "cattails_A", "cattails_B", "rushes_A", "rushes_B", "blue_flag_iris_A"]
	var per_mesh: Dictionary = {}
	for hz in layout.water_hazards:
		if region.size != Vector2.ZERO and not hz.bounds.intersects(region):
			continue
		var n: int = hz.polygon.size()
		for i in range(n):
			var a: Vector2 = hz.polygon[i]
			var b: Vector2 = hz.polygon[(i + 1) % n]
			var edge_len := a.distance_to(b)
			var steps := maxi(1, int(edge_len / 3.0))
			for k in range(steps):
				var p := a.lerp(b, (k + rng.randf()) / steps)
				var outward: Vector2 = (p - hz.center).normalized()
				var q := p + outward * rng.randf_range(0.5, 2.5)
				var use_rock := rng.randf() < 0.4
				var names: Array = rock_names if use_rock else reed_names
				var name: String = names[rng.randi_range(0, names.size() - 1)]
				var sc := rng.randf_range(0.7, 1.4) if use_rock else rng.randf_range(0.8, 1.3)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(sc, sc, sc)), Vector3(q.x, layout.cached_height(q.x, q.y) - 0.05, q.y))
				if not per_mesh.has(name):
					per_mesh[name] = []
				per_mesh[name].append(xf)
		# a few lily pads floating just inside the bank of ponds
		if not hz.is_creek:
			for i in range(0, n, 3):
				var p: Vector2 = hz.polygon[i].lerp(hz.center, rng.randf_range(0.08, 0.2))
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(p.x, hz.water_level + 0.02, p.y))
				if not per_mesh.has("lily_pads"):
					per_mesh["lily_pads"] = []
				per_mesh["lily_pads"].append(xf)
	for name in per_mesh:
		var mesh := NaturePack.mesh(name)
		if mesh == null:
			continue
		VegetationBatches.add_batches(root, name, mesh, per_mesh[name], null, false, PerformanceSettings.prop_distance(), 32.0, true)
	return root
