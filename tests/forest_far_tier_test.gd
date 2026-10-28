extends SceneTree
## Sanity check for the forest tiers (ForestPlanter.LOW_POLY_TREES): builds a real hole's
## forest and checks every tree has a medium-detail near tier ("_L2", no high-poly "_L0") and
## exactly one far batch -- impostor cards ("_IMP"), or the low-poly crown ("_LP") only for a
## species with no baked impostor -- starting by NaturePack.DENSE_AT and reaching the tree
## distance.
## Run: godot --headless --path . --script tests/forest_far_tier_test.gd

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var ok := true
	var layout := CourseBuilder.build(7)
	layout.build_cache(4.0)
	var hole: CourseLayout.Hole = layout.holes[6]  # No. 7: has real woods
	var region := layout.hole_bbox(hole).grow(60.0)
	var forest := ForestPlanter.build(layout, 7, region)
	root.add_child(forest)
	var tree_ids: Array = ForestPlanter.PINES + ForestPlanter.HARDWOODS + ForestPlanter.UNDERSTORY_TREES + ForestPlanter.FRINGE_TREES + ForestPlanter.WATERSIDE
	var lp_instances := 0
	var impostor_nodes := 0
	var tree_detail_nodes := 0
	var tree_high_nodes := 0
	for child in forest.get_children():
		var n := String(child.name)
		if n.contains("_LP_") or n.contains("_IMP_"):
			lp_instances += (child as MultiMeshInstance3D).multimesh.instance_count
			if child.visibility_range_begin > NaturePack.DENSE_AT:
				print("FAIL low-poly tile %s starts at %.0f m (past the near tiers' hand-over)" % [n, child.visibility_range_begin])
				ok = false
			if child.visibility_range_end < PerformanceSettings.tree_distance():
				print("FAIL low-poly tile %s ends at %.0f m (< tree distance)" % [n, child.visibility_range_end])
				ok = false
		elif n.begins_with("FAR_"):
			impostor_nodes += 1
		elif n.contains("_L0_") or n.contains("_L2_") or n.contains("_L3_"):
			var id := n.substr(0, n.find("_L"))
			if tree_ids.has(id):
				tree_detail_nodes += 1
				if n.contains("_L0_"):
					tree_high_nodes += 1
	print("[Forest] trees=%d low-poly instances=%d impostor nodes=%d tree LOD nodes=%d" % [forest.tree_count, lp_instances, impostor_nodes, tree_detail_nodes])
	if lp_instances != forest.tree_count:
		print("FAIL every tree should be in exactly one far batch")
		ok = false
	if impostor_nodes > 0:
		print("FAIL old pooled FAR_ proxies are back")
		ok = false
	if tree_detail_nodes == 0:
		print("FAIL trees have no medium-detail near tier")
		ok = false
	if tree_high_nodes > 0:
		print("FAIL trees still have a high-poly tier")
		ok = false
	print("FOREST LOW-POLY TEST: " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
