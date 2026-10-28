class_name TreeTwigTrim
extends RefCounted
## The nature pack's medium-detail trees keep bare twig tips that poke out past the leaves,
## above and around the crown, and read as spikes. trim() clips only the protruding part of
## those twigs: twig geometry (triangles with an edge under THIN, so trunks and limbs are
## never touched) that rises above the highest leaves around it, or reaches past the
## outermost leaves at its height and bearing, by more than MARGIN. Twigs inside the crown,
## including the ones in the gaps between leaf tiers, keep their full length and number, and
## the main trunk (within KEEP_RADIUS of the axis) is never clipped below the highest
## leaves, even where it rises through a sparse top tier. A twig with leaves still near it
## (LEAF_NEAR) is never clipped either: that is a branch carrying foliage on its way
## out -- typical of pine branches, which climb through sparse tiers to needles further
## out -- and clipping it left those needles floating. Only the
## bark's index buffers are rewritten (its LOD buffers too), so the mesh keeps its
## compression and automatic LODs.

const THIN := 0.03  # metres: a triangle with an edge this short is part of a twig
const MARGIN := 0.0  # metres of twig allowed past the leaves
## Leaf cards tilt, so the highest leaf corner sits 20-30 cm above the tier a player sees;
## twigs are measured against the top this much lower.
const TOP_SINK := 0.2
const CELL := 0.4  # metres: canopy sampling (x/z columns for the top, height bands for the edge)
const SECTORS := 24  # bearings around the trunk for the crown's edge
const TOP_REACH := 1  # columns either side searched for the leaves above a twig
const KEEP_RADIUS := 0.35  # metres: never clip this close to the trunk axis
const LEAF_NEAR := 0.35  # metres: leaf-occupancy cell; a twig within one cell of leaves is kept


## A copy of `src` with the spikes clipped. `is_foliage(surface_name)` tells leaf surfaces
## from bark, as NaturePack._is_foliage does.
## `spare_leafy` false restores the old rule (clip even twigs that carry leaves), for comparison.
## `bark_lods` >= 0 keeps only that many of the bark's automatic LODs: Godot's import LODs
## thin a pine's branches to 25%, 11%, 2% while its needles stay at 63%, so at range the
## branches shorten and vanish under needle clumps that then float. 1 keeps the 50% level.
static func trim(src: ArrayMesh, is_foliage: Callable, margin: float = MARGIN, spare_leafy: bool = true, bark_lods: int = -1) -> ArrayMesh:
	var box := src.get_aabb()
	var x0 := floori(box.position.x / CELL) - 1
	var z0 := floori(box.position.z / CELL) - 1
	var nx := ceili(box.size.x / CELL) + 3
	var nz := ceili(box.size.z / CELL) + 3
	var b0 := floori(box.position.y / CELL) - 1
	var nb := ceili(box.size.y / CELL) + 3
	var top := PackedFloat32Array()  # highest leaf per x/z column
	top.resize(nx * nz)
	top.fill(-1.0e9)
	var edge := PackedFloat32Array()  # outermost leaf radius per (height band, bearing)
	edge.resize(nb * SECTORS)
	edge.fill(-1.0)
	var base := INF  # lowest leaf
	var crown_top := -INF  # highest leaf
	for s in range(src.get_surface_count()):
		if not is_foliage.call(src.surface_get_name(s)):
			continue
		for p in (src.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var ti := clampi(floori(p.x / CELL) - x0, 0, nx - 1) * nz + clampi(floori(p.z / CELL) - z0, 0, nz - 1)
			if p.y > top[ti]:
				top[ti] = p.y
			var sector := int((atan2(p.z, p.x) + PI) * SECTORS / TAU) % SECTORS
			var ei := clampi(floori(p.y / CELL) - b0, 0, nb - 1) * SECTORS + sector
			var r := sqrt(p.x * p.x + p.z * p.z)
			if r > edge[ei]:
				edge[ei] = r
			if p.y < base:
				base = p.y
			if p.y > crown_top:
				crown_top = p.y
	if base == INF:
		return src
	# 3D occupancy of leaf vertices, for "is there still foliage on this twig?"
	var o0 := Vector3i(floori(box.position.x / LEAF_NEAR) - 1, floori(box.position.y / LEAF_NEAR) - 1, floori(box.position.z / LEAF_NEAR) - 1)
	var on := Vector3i(ceili(box.size.x / LEAF_NEAR) + 3, ceili(box.size.y / LEAF_NEAR) + 3, ceili(box.size.z / LEAF_NEAR) + 3)
	var leafy := PackedByteArray()
	leafy.resize(on.x * on.y * on.z)
	for s in range(src.get_surface_count()):
		if not is_foliage.call(src.surface_get_name(s)):
			continue
		for p in (src.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var c := Vector3i(floori(p.x / LEAF_NEAR), floori(p.y / LEAF_NEAR), floori(p.z / LEAF_NEAR)) - o0
			leafy[(c.x * on.y + c.y) * on.z + c.z] = 1 if spare_leafy else 0
	var grid := [x0, z0, nx, nz, b0, nb, crown_top, o0, on, leafy]
	var surfaces: Array = (src.get("_surfaces") as Array).duplicate(true)
	for s in range(src.get_surface_count()):
		if is_foliage.call(src.surface_get_name(s)):
			continue
		var arrays := src.surface_get_arrays(s)
		var spikes := _protruding_twig_vertices(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX], top, edge, grid, base, margin)
		var d: Dictionary = surfaces[s]
		var wide := int(d["vertex_count"]) > 0xFFFF
		var kept := _keep_triangles(_decode(d["index_data"], wide), spikes)
		d["index_data"] = _encode(kept, wide)
		d["index_count"] = kept.size()
		var lods: Array = d.get("lods", [])
		if bark_lods >= 0 and lods.size() > bark_lods * 2:
			lods = lods.slice(0, bark_lods * 2)
			d["lods"] = lods
		for i in range(1, lods.size(), 2):  # [edge_length, index_data, ...]
			lods[i] = _encode(_keep_triangles(_decode(lods[i], wide), spikes), wide)
	var out := ArrayMesh.new()
	out.set("_surfaces", surfaces)
	return out


## 1 for twig vertices that stick out of the crown: above the highest leaves in the
## neighbouring columns, or past the outermost leaves in the neighbouring height bands and
## bearings, by more than `margin`.
static func _protruding_twig_vertices(verts: PackedVector3Array, idx: PackedInt32Array, top: PackedFloat32Array, edge: PackedFloat32Array, grid: Array, base: float, margin: float) -> PackedByteArray:
	var x0: int = grid[0]
	var z0: int = grid[1]
	var nx: int = grid[2]
	var nz: int = grid[3]
	var b0: int = grid[4]
	var nb: int = grid[5]
	var crown_top: float = grid[6]
	var o0: Vector3i = grid[7]
	var on: Vector3i = grid[8]
	var leafy: PackedByteArray = grid[9]
	var flag := PackedByteArray()
	flag.resize(verts.size())
	for t in range(0, idx.size() - 2, 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		if minf(a.distance_to(b), minf(b.distance_to(c), c.distance_to(a))) < THIN:
			flag[idx[t]] = 1
			flag[idx[t + 1]] = 1
			flag[idx[t + 2]] = 1
	for i in range(verts.size()):
		if flag[i] == 0:
			continue
		var p := verts[i]
		flag[i] = 0
		var r := sqrt(p.x * p.x + p.z * p.z)
		if p.y <= base or (r < KEEP_RADIUS and p.y <= crown_top):
			continue
		var cx := floori(p.x / CELL) - x0
		var cz := floori(p.z / CELL) - z0
		var local_top := -1.0e9
		for gx in range(maxi(cx - TOP_REACH, 0), mini(cx + TOP_REACH + 1, nx)):
			for gz in range(maxi(cz - TOP_REACH, 0), mini(cz + TOP_REACH + 1, nz)):
				local_top = maxf(local_top, top[gx * nz + gz])
		var band := floori(p.y / CELL) - b0
		var sector := int((atan2(p.z, p.x) + PI) * SECTORS / TAU) % SECTORS
		var local_edge := -1.0
		for gb in range(maxi(band - 1, 0), mini(band + 2, nb)):
			for ds in range(-1, 2):
				local_edge = maxf(local_edge, edge[gb * SECTORS + (sector + ds + SECTORS) % SECTORS])
		if p.y > local_top - TOP_SINK + margin or (local_edge >= 0.0 and r > local_edge + margin):
			if not _near_leaves(p, o0, on, leafy):
				flag[i] = 1
	return flag


## True when a leaf vertex lies in the twig vertex's occupancy cell or one next to it.
static func _near_leaves(p: Vector3, o0: Vector3i, on: Vector3i, leafy: PackedByteArray) -> bool:
	var c := Vector3i(floori(p.x / LEAF_NEAR), floori(p.y / LEAF_NEAR), floori(p.z / LEAF_NEAR)) - o0
	for dx in range(-1, 2):
		var x := c.x + dx
		if x < 0 or x >= on.x:
			continue
		for dy in range(-1, 2):
			var y := c.y + dy
			if y < 0 or y >= on.y:
				continue
			for dz in range(-1, 2):
				var z := c.z + dz
				if z >= 0 and z < on.z and leafy[(x * on.y + y) * on.z + z] == 1:
					return true
	return false


static func _keep_triangles(idx: PackedInt32Array, outside: PackedByteArray) -> PackedInt32Array:
	var kept := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		if outside[idx[t]] == 0 and outside[idx[t + 1]] == 0 and outside[idx[t + 2]] == 0:
			kept.append(idx[t])
			kept.append(idx[t + 1])
			kept.append(idx[t + 2])
	return kept


## Index buffers as stored in ArrayMesh's raw surfaces: 16-bit unless the surface has more
## than 65535 vertices.
static func _decode(bytes: PackedByteArray, wide: bool) -> PackedInt32Array:
	if wide:
		return bytes.to_int32_array()
	var idx := PackedInt32Array()
	idx.resize(bytes.size() / 2)
	for i in range(idx.size()):
		idx[i] = bytes.decode_u16(i * 2)
	return idx


static func _encode(idx: PackedInt32Array, wide: bool) -> PackedByteArray:
	if wide:
		return idx.to_byte_array()
	var bytes := PackedByteArray()
	bytes.resize(idx.size() * 2)
	for i in range(idx.size()):
		bytes.encode_u16(i * 2, idx[i])
	return bytes
