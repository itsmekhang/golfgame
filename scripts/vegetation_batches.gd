class_name VegetationBatches
extends RefCounted
## A MultiMesh is culled as one object. Keep batches spatially small and their
## transforms local so generated bounds include every instance, wherever it is.

## `distance_begin` > 0 makes the batch a far LOD tier that only appears past that
## range (pair it with a nearer tier ending at the same distance).
static func add_batches(root: Node3D, label: String, mesh: Mesh, transforms: Array,
		material: Material, casts_shadow: bool, distance: float, tile_size: float,
		detail_only: bool = false, distance_begin: float = 0.0) -> void:
	var tiles: Dictionary = {}
	for transform: Transform3D in transforms:
		var key := Vector2i(floori(transform.origin.x / tile_size), floori(transform.origin.z / tile_size))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(transform)
	for key: Vector2i in tiles:
		var origin := Vector3((key.x + 0.5) * tile_size, 0.0, (key.y + 0.5) * tile_size)
		var instances: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = instances.size()
		for i in range(instances.size()):
			var local: Transform3D = instances[i]
			local.origin -= origin
			mm.set_instance_transform(i, local)
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%d_%d" % [label, key.x, key.y]
		node.position = origin
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = distance
		if distance_begin > 0.0:
			# exact hand-over between LOD tiers: no margins, so a tile is never drawn twice
			node.visibility_range_begin = distance_begin
			node.visibility_range_begin_margin = 0.0
			node.visibility_range_end_margin = 0.0
		else:
			node.visibility_range_end_margin = 0.0 if distance < PerformanceSettings.tree_distance() else 8.0
		node.extra_cull_margin = 1.0
		if detail_only:
			node.layers = PerformanceSettings.DETAIL_LAYER
		root.add_child(node)
