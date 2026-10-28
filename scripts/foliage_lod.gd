class_name FoliageLod
extends RefCounted
## Distance LODs for card foliage (pine needles): the pack's pine crowns are ~45-75k triangles
## of needle cards, and their only automatic LOD (built by the importer) sits at an edge
## length so large it never engages, so every pine out to the impostor hand-over drew in full
## -- most of the course's triangles. This builds a proper chain by thinning whole cards
## (triangles joined through shared vertices), never by collapsing edges, so a far crown is
## the same needle clumps, just fewer of them, and the near tree is untouched.
##
## LEVELS: [edge length (m), share of cards kept]. Godot picks a LOD once the edge length
## projects under the viewport's mesh_lod_threshold (1 px by default); at 900 px and a 60
## degree FOV a pixel spans ~0.0013 m per metre of distance, so 0.08 m switches near 60 m.
const LEVELS := [[0.08, 0.6], [0.14, 0.35], [0.22, 0.2]]
## Woodland bushes are 1-3 m tall, so they thin sooner (~25 / 45 / 80 m).
const BUSH_LEVELS := [[0.032, 0.6], [0.06, 0.35], [0.1, 0.2]]

static var _cache := {}


## with_card_lods(), built once per `key` for the session.
static func cached(key: String, src: ArrayMesh, is_foliage: Callable, levels: Array = LEVELS) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = with_card_lods(src, is_foliage, levels)
	return _cache[key]


## A copy of `src` whose foliage surfaces (is_foliage(surface_name)) carry the card LODs.
## Other surfaces keep their own LODs.
static func with_card_lods(src: ArrayMesh, is_foliage: Callable, levels: Array = LEVELS) -> ArrayMesh:
	var surfaces: Array = (src.get("_surfaces") as Array).duplicate(true)
	for s in range(src.get_surface_count()):
		if not is_foliage.call(src.surface_get_name(s)):
			continue
		var d: Dictionary = surfaces[s]
		var vcount := int(d["vertex_count"])
		var wide := vcount > 0xFFFF
		var idx := TreeTwigTrim._decode(d["index_data"], wide)
		var comp := _card_ids(idx, vcount)
		var lods: Array = []
		for lv in levels:
			var keep := float(lv[1])
			var kept := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				if _keep(comp[t / 3], keep):
					kept.append(idx[t])
					kept.append(idx[t + 1])
					kept.append(idx[t + 2])
			if kept.is_empty():
				continue
			lods.append(float(lv[0]))
			lods.append(TreeTwigTrim._encode(kept, wide))
		d["lods"] = lods
	var out := ArrayMesh.new()
	out.set("_surfaces", surfaces)
	return out


## Per triangle: the id of the card (connected component through shared vertices) it is in.
static func _card_ids(idx: PackedInt32Array, vcount: int) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(vcount)
	for i in range(vcount):
		parent[i] = i
	for t in range(0, idx.size() - 2, 3):
		var a := _find(parent, idx[t])
		var b := _find(parent, idx[t + 1])
		var c := _find(parent, idx[t + 2])
		if b != a:
			parent[b] = a
		if c != a and c != b:
			parent[c] = a
	var out := PackedInt32Array()
	out.resize(idx.size() / 3)
	for t in range(0, idx.size() - 2, 3):
		out[t / 3] = _find(parent, idx[t])
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	# path halving keeps later finds short
	while parent[i] != r:
		var nxt := parent[i]
		parent[i] = r
		i = nxt
	return r


## Deterministic per-card keep test, nested across levels (a card kept at 20% is also kept at
## 35% and 60%), so the crown thins smoothly instead of reshuffling between LODs.
static func _keep(card: int, share: float) -> bool:
	var h := (card * 2654435761) & 0xFFFFFFFF
	return float(h % 10007) / 10007.0 < share
