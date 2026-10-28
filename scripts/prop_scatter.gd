class_name PropScatter
extends RefCounted
## Scatters the Golf Nature Pack's understory (grasses, ferns, flowers, ground cover,
## fallen wood) across the rough with MultiMeshInstance3D batches, and adds
## floating lily pads to ponds. Banks stay clear. Trees are ForestPlanter's job.

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


## Props per hectare of course. Only the A size variant of each species -- B/C
## dropped at the user's request to cut the number of distinct meshes; per-instance
## scale_range still supplies size variety.
static func specs() -> Array[PropSpec]:
	return [
		PropSpec.new(["rough_clump_A", "dry_grass_clump_A", "fairway_clump_A"], 40, 0.5, Vector2(0.8, 1.3)),
		PropSpec.new(["fescue_tussock_A", "broomsedge_A", "rushes_A"], 16, 1.5, Vector2(0.7, 1.2)),
		PropSpec.new(["sword_fern_A", "bracken_fern_A", "hosta_A"], 10, 4.0, Vector2(0.7, 1.1)),
		PropSpec.new(["daisy_patch", "buttercup_patch", "wildflower_mix", "clover_patch"], 10, 1.5, Vector2(0.8, 1.3)),
		PropSpec.new(["pine_straw", "leaf_litter", "ivy_patch", "moss_patch"], 14, 6.0, Vector2(0.9, 1.5)),
		PropSpec.new(["mushroom_cluster"], 3, 5.0, Vector2(0.7, 1.1)),
		PropSpec.new(["pink_muhly_A", "pampas_grass_A", "blue_flag_iris_A"], 3, 3.0, Vector2(0.7, 1.1)),
		PropSpec.new(["stump_low", "stump_tall", "fallen_log", "fallen_log_mossy", "driftwood", "dead_branch"], 2, 7.0, Vector2(0.8, 1.2), 0.8, 0.8),
	]


## Flowering plants and ferns big enough to read from down the fairway: drawn out to the tree
## distance like the trees and shrubs instead of vanishing at prop_distance(). They're sparse
## (a few per hectare), so the extra range is cheap; ground cover stays at prop_distance().
const FAR_PROP_IDS := ["pink_muhly_A", "pampas_grass_A", "blue_flag_iris_A", "sword_fern_A", "bracken_fern_A", "hosta_A", "daisy_patch", "buttercup_patch", "wildflower_mix"]


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
			if layout.hazard_near(xz, 4.0) or layout.bunker_near(xz, 3.0) or layout.in_pad(xz, 1.0):
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
			var far_reaching: bool = large or FAR_PROP_IDS.has(mesh_name)
			VegetationBatches.add_batches(root, mesh_name, mesh, xforms, null, large,
				PerformanceSettings.tree_distance() if far_reaching else PerformanceSettings.prop_distance(), 128.0 if large else (64.0 if far_reaching else 32.0), not large)

	return root


## Keep floating lily pads in ponds and build the authored stone bridges; do not spawn
## nature along water banks.
## `region`: when non-empty, skip hazards outside it.
static func decorate(layout: CourseLayout, rng_seed: int = 11, region: Rect2 = Rect2()) -> Node3D:
	var root := Node3D.new()
	root.name = "Decor"
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var per_mesh: Dictionary = {}
	for hz in layout.water_hazards:
		if region.size != Vector2.ZERO and not hz.bounds.intersects(region):
			continue
		var n: int = hz.polygon.size()
		# a few lily pads floating just inside the bank of ponds
		if not hz.is_creek:
			for i in range(0, n, 3):
				var p: Vector2 = hz.polygon[i].lerp(hz.center, rng.randf_range(0.08, 0.2))
				if not hz.contains(p):
					continue
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(p.x, hz.water_level + 0.02, p.y))
				if not per_mesh.has("lily_pads"):
					per_mesh["lily_pads"] = []
				per_mesh["lily_pads"].append(xf)
	# Stone footbridges authored on the holes (the Hogan and Nelson bridges on 12).
	for hole in layout.holes:
		for br in hole.bridges:
			var ba: Vector2 = br[0]
			var bb: Vector2 = br[1]
			if region.size != Vector2.ZERO and not Rect2(ba, Vector2.ZERO).expand(bb).grow(4.0).intersects(region):
				continue
			root.add_child(StoneBridge.build(layout, ba, bb, float(br[2]), int(br[3])))
	for name in per_mesh:
		var mesh := NaturePack.mesh(name)
		if mesh == null:
			continue
		VegetationBatches.add_batches(root, name, mesh, per_mesh[name], null, false, PerformanceSettings.prop_distance(), 32.0, true)
	return root


## Space decoration along the bank, independent of how densely it is traced.
## One prop per polygon vertex buried smooth narrow creeks under a wall of rocks.
static func _shoreline_samples(polygon: PackedVector2Array, spacing: float, phase: float) -> Array:
	var samples := []
	var next := phase
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b-a
		var length := edge.length()
		if length < 0.0001: continue
		var outward := Vector2(edge.y,-edge.x) / length
		while next < length:
			samples.append([a.lerp(b,next/length),outward])
			next += spacing
		next -= length
	return samples
