extends SceneTree
## Sanity check for the pooled far-tier tree proxies (NaturePack.far_proxy_mesh /
## ForestPlanter._far_pine/_far_hardwood): builds a real hole's forest and checks the
## FAR_pine/FAR_hardwood batches exist, are sized sensibly, and sit beyond MID_AT.
## Run: godot --headless --path . --script tests/forest_far_tier_test.gd

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var layout := CourseBuilder.build(7)
	layout.build_cache(4.0)
	var hole: CourseLayout.Hole = layout.holes[6]  # No. 7: has real woods
	var region := layout.hole_bbox(hole).grow(60.0)
	var forest := ForestPlanter.build(layout, 7, region)
	root.add_child(forest)
	print("[Forest] trees=%d shrubs=%d far_pine_xf=%d far_hardwood_xf=%d" % [
		forest.tree_count, forest.shrub_count, forest._far_pine.size(), forest._far_hardwood.size()])
	var far_nodes := 0
	var far_instances := 0
	for child in forest.get_children():
		if child.name.begins_with("FAR_"):
			far_nodes += 1
			far_instances += (child as MultiMeshInstance3D).multimesh.instance_count
			var mat: Material = (child as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0)
			assert(child.visibility_range_begin == NaturePack.MID_AT, "far tier should start exactly at MID_AT")
			assert(mat != null, "far proxy mesh has no material")
	var tri_count := 0
	for kind in ["pine", "hardwood"]:
		var m := NaturePack.far_proxy_mesh(kind)
		var arrays := (m as ArrayMesh).surface_get_arrays(0)
		var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		tri_count += n
		print("[Forest] proxy %s: %d triangles" % [kind, n])
		assert(n < 100, "far proxy mesh should be very cheap (~30-60 tris)")
	print("[Forest] FAR_* nodes=%d instances=%d" % [far_nodes, far_instances])
	assert(far_nodes > 0, "no far-tier batches were built")
	assert(far_instances == forest.tree_count, "every tree should be pooled into exactly one far-tier batch")
	print("FOREST FAR TIER TEST: PASS")
	quit(0)
