class_name NaturePack
extends RefCounted
## Loads the Golf Nature Pack and hands out meshes ready for MultiMesh use.
##
## `assets/nature_pack/` is version 2 ("Flexible Leaves", vertex-coloured PBR, real
## leaf geometry). The forest is real geometry at every distance, the way the pack's
## own wrappers do it: full-detail (broadleaf) or LOD1 mesh inside MESH_AT, the LOD2
## mesh out to MID_AT, nothing beyond. The 1M-triangle base meshes only ship for the
## six broadleaf species. (Impostor cards were tried and rejected; tools/ keeps the baker.)
## Materials are ours, not the GLBs': leaf/needle/petal/blade surfaces get the pack's
## wind shader, everything else a vertex-colour StandardMaterial3D with back-face culling.

const DIR := "res://nature_pack/"
const DIR_FAR := "res://assets/nature_pack_v1/"
const WIND_SHADER := "res://nature_pack/shaders/foliage_wind.gdshader"
const HEAVY_CATEGORIES := ["trees", "shrubs", "palms"]

static var _catalog: Dictionary = {}
static var _catalog_far: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _foliage_mat: ShaderMaterial
static var _grass_mat: ShaderMaterial
static var _solid_mat: ShaderMaterial


static func _load_catalog(dir: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(dir + "catalog.json", FileAccess.READ)
	assert(f != null, "missing nature pack catalog in " + dir)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for a in data["assets"]:
		out[a["id"]] = a
	return out


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = _load_catalog(DIR)
	return _catalog


static func catalog_far() -> Dictionary:
	if _catalog_far.is_empty():
		_catalog_far = _load_catalog(DIR_FAR)
	return _catalog_far


static func has(id: String) -> bool:
	return catalog().has(id)


## Model bounding size (width, height, depth) in metres at scale 1.
static func dims(id: String) -> Vector3:
	var d: Array = catalog()[id]["dimensions_m"]
	return Vector3(float(d[0]), float(d[1]), float(d[2]))


## True when the asset has low-poly far tiers in the version 1 pack.
static func has_far_tiers(id: String) -> bool:
	return catalog_far().has(id) and (catalog_far()[id]["lods"] as Array).size() >= 2


## Distance at which a tree/shrub mesh hands over to its impostor card, per instance
## (the batches' per-tile visibility ranges are only a coarse first cut).
const MESH_AT := 26.0
const SHRUB_MESH_AT := 18.0
static var _heavy_mats: Dictionary = {}  # max_dist -> [leaves, solid]


static func _materials() -> void:
	if _foliage_mat != null:
		return
	_foliage_mat = ShaderMaterial.new()
	_foliage_mat.shader = load("res://shaders/nature_leaves.gdshader")
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = _foliage_mat.shader
	_grass_mat.set_shader_parameter("sway_strength", 0.012)
	_solid_mat = ShaderMaterial.new()
	_solid_mat.shader = load("res://shaders/nature_solid.gdshader")


## Leaf/solid materials that only draw instances between `min_dist` and `max_dist`
## from the camera (tree and shrub mesh tiers).
static func _heavy_materials(max_dist: float, min_dist: float = 0.0) -> Array:
	_materials()
	var key := Vector2(min_dist, max_dist)
	if not _heavy_mats.has(key):
		var leaves := _foliage_mat.duplicate()
		leaves.set_shader_parameter("max_dist", max_dist)
		leaves.set_shader_parameter("min_dist", min_dist)
		var solid := _solid_mat.duplicate()
		solid.set_shader_parameter("max_dist", max_dist)
		solid.set_shader_parameter("min_dist", min_dist)
		_heavy_mats[key] = [leaves, solid]
	return _heavy_mats[key]


static func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and n.mesh != null:
		return n.mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


static func _is_foliage(sname: String) -> bool:
	var s := sname.to_lower()
	return s.contains("foliage") or s.contains("leaf") or s.contains("leaves") or s.contains("needle") or s.contains("petal") or s.contains("blade")


static func _load_mesh(path: String, id: String, key: String, max_dist: float = 0.0, min_dist: float = 0.0) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("NaturePack: missing model " + path)
		return null
	var inst := scene.instantiate()
	var src := _find_mesh(inst)
	inst.free()
	if src == null:
		push_error("NaturePack: no mesh in " + path)
		return null
	_materials()
	var small := id.contains("clump") or id.contains("patch") or id.contains("straw") or id.contains("litter")
	var leaves_mat: Material = _grass_mat if small else _foliage_mat
	var solid_mat: Material = _solid_mat
	if max_dist > 0.0:
		var hm := _heavy_materials(max_dist, min_dist)
		leaves_mat = hm[0]
		solid_mat = hm[1]
	var m: Mesh = src.duplicate()
	for i in range(m.get_surface_count()):
		var sname := ""
		if m is ArrayMesh:
			sname = (m as ArrayMesh).surface_get_name(i)
		if sname == "":
			var existing := m.surface_get_material(i)
			sname = existing.resource_name if existing != null else ""
		m.surface_set_material(i, leaves_mat if _is_foliage(sname) else solid_mat)
	_mesh_cache[key] = m
	return m


## The runtime mesh for `id`: the base file for light categories, the LOD1 file
## (47k-238k tris, the pack's own "under 65 m" tier) for trees/shrubs/palms. The
## 1M-triangle base tree meshes are only used offline to bake impostors.
static func mesh(id: String, _lod: int = 0) -> Mesh:
	var entry: Dictionary = catalog().get(id, {})
	if entry.is_empty():
		push_error("NaturePack: unknown asset " + id)
		return null
	var path: String = entry["path"]
	var max_dist := 0.0
	if entry["category"] in HEAVY_CATEGORIES:
		var lods: Array = entry["lods"]
		if lods.is_empty():
			push_error("NaturePack: no LOD1 for " + id)
			return null
		# the full-crowned broadleaf species ship at full detail (the pack's preview
		# look); everything else at LOD1
		if not FULL_DETAIL_IDS.has(id):
			path = lods[0]["path"]
		max_dist = SHRUB_MESH_AT if entry["category"] == "shrubs" else MESH_AT
	return _load_mesh(DIR + path, id, "near#" + id, max_dist)


## Species whose 1M-triangle base mesh ships for the near tier.
const FULL_DETAIL_IDS := ["white_oak_B", "red_maple_B", "sweetgum_B", "tulip_poplar_B", "southern_magnolia_B", "live_oak_B"]
## Far edge of the forest: real LOD2 geometry out to here, nothing beyond. Every
## 10 m added here is hundreds more 12k-42k-triangle trees per frame.
const MID_AT := 220.0


## The pack's LOD2 mesh for the mid-range tier, drawn only between the near tier's
## cut and MID_AT.
static func mesh_mid(id: String) -> Mesh:
	var entry: Dictionary = catalog().get(id, {})
	if entry.is_empty() or not (entry["category"] in HEAVY_CATEGORIES):
		return null
	var lods: Array = entry["lods"]
	if lods.size() < 2:
		return null
	var near := SHRUB_MESH_AT if entry["category"] == "shrubs" else MESH_AT
	var far := 60.0 if entry["category"] == "shrubs" else MID_AT
	return _load_mesh(DIR + lods[1]["path"], id, "mid#" + id, far, near)


## The full-detail base mesh from the offline bake folder (tools/bake_impostors.gd).
static func base_mesh_for_bake(id: String) -> Mesh:
	return _load_mesh(DIR + "models/_bake/" + id + ".glb", id, "bake#" + id)


## Baked impostor card for `id`: [Mesh quad, ShaderMaterial] or [] when not baked.
const IMPOSTOR_DIR := "res://nature_pack/impostors/"
static var _impostor_meta: Dictionary = {}
static var _impostor_cache: Dictionary = {}


static func impostor(id: String) -> Array:
	if _impostor_cache.has(id):
		return _impostor_cache[id]
	if _impostor_meta.is_empty():
		var f := FileAccess.open(IMPOSTOR_DIR + "impostors.json", FileAccess.READ)
		_impostor_meta = JSON.parse_string(f.get_as_text()) if f != null else {"_": true}
	var meta: Dictionary = _impostor_meta.get(id, {})
	if meta.is_empty():
		_impostor_cache[id] = []
		return []
	var tex: Texture2D = load(IMPOSTOR_DIR + id + ".png")
	if tex == null:
		_impostor_cache[id] = []
		return []
	var w := float(meta["width_m"])
	var h := float(meta["height_m"])
	# three vertical quads 60 degrees apart, fixed in the instance frame; UV2.x carries
	# each quad's facing yaw for the shader's view selection
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vi := 0
	for k in range(3):
		var yaw := PI / 3.0 * k
		var right := Vector3(cos(yaw), 0.0, sin(yaw)) * (w * 0.5)
		var corners := [-right, right, right + Vector3(0.0, h, 0.0), -right + Vector3(0.0, h, 0.0)]
		var uvs := [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
		for c in range(4):
			st.set_uv(uvs[c])
			st.set_uv2(Vector2(yaw, 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(corners[c])
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_index(vi + idx)
		vi += 4
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impostor.gdshader")
	mat.set_shader_parameter("atlas", tex)
	mat.set_shader_parameter("views", int(meta["views"]))
	mat.set_shader_parameter("near_cut", MID_AT)
	mesh.surface_set_material(0, mat)
	_impostor_cache[id] = [mesh, mat]
	return _impostor_cache[id]


## Beyond MID_AT, real LOD2 geometry stopped entirely -- nothing drew all the way out
## to PerformanceSettings.tree_distance() (900 m by default), so the forest just
## vanished into an empty horizon past 220 m. This is the far, cheap stand-in: real
## static 3D geometry (no camera-facing billboard, no cross-card -- both were tried
## earlier and rejected), just very few triangles, pooled across every species into
## two shapes (a shared "pine" cone and a shared "hardwood" double-blob) rather than
## one mesh per species, so the far tier costs two MultiMesh batches instead of dozens.
static var _far_proxy_cache: Dictionary = {}


static func _proxy_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# Emitted both winding directions so the (very few) triangles read correctly from
	# every angle without needing to hand-verify outward winding on each face --
	# doubling ~30 triangles to ~60 is still negligible next to a 12k+ tri LOD2 mesh.
	for tri in [[a, b, c], [a, c, b]]:
		for v: Vector3 in tri:
			st.set_color(col)
			st.add_vertex(v)


## A low-poly cylinder trunk, shared by both proxy kinds.
static func _proxy_trunk(st: SurfaceTool, radius: float, height: float, col: Color) -> void:
	const SIDES := 6
	for i in range(SIDES):
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * radius
		var p0t := p0 + Vector3(0.0, height, 0.0)
		var p1t := p1 + Vector3(0.0, height, 0.0)
		_proxy_face(st, p0, p1, p1t, col)
		_proxy_face(st, p0, p1t, p0t, col)


## A squashed octahedron canopy lobe: a top and bottom apex over a 4-point equator.
static func _proxy_lobe(st: SurfaceTool, center: Vector3, radius_xz: float, radius_up: float, radius_down: float, col: Color) -> void:
	var top := center + Vector3(0.0, radius_up, 0.0)
	var bottom := center - Vector3(0.0, radius_down, 0.0)
	var eq := [center + Vector3(radius_xz, 0.0, 0.0), center + Vector3(0.0, 0.0, radius_xz),
		center + Vector3(-radius_xz, 0.0, 0.0), center + Vector3(0.0, 0.0, -radius_xz)]
	for i in range(4):
		var e0: Vector3 = eq[i]
		var e1: Vector3 = eq[(i + 1) % 4]
		_proxy_face(st, top, e0, e1, col)
		_proxy_face(st, bottom, e1, e0, col)


static func far_proxy_mesh(kind: String) -> Mesh:
	var key := "farproxy#" + kind
	if _far_proxy_cache.has(key):
		return _far_proxy_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_col := Color(0.28, 0.20, 0.13)
	if kind == "pine":
		_proxy_trunk(st, 0.30, 3.0, trunk_col)
		var canopy_col := Color(0.14, 0.28, 0.11)
		# three stacked narrowing tiers read as a conifer silhouette from a distance
		_proxy_lobe(st, Vector3(0.0, 6.0, 0.0), 2.6, 5.5, 1.2, canopy_col)
		_proxy_lobe(st, Vector3(0.0, 11.5, 0.0), 1.9, 4.5, 1.0, canopy_col)
		_proxy_lobe(st, Vector3(0.0, 16.0, 0.0), 1.1, 3.2, 0.8, canopy_col)
	else:
		_proxy_trunk(st, 0.35, 4.0, trunk_col)
		var canopy_col := Color(0.19, 0.36, 0.13)
		# two offset lobes for a rounder, less symmetric hardwood crown
		_proxy_lobe(st, Vector3(-1.1, 8.5, 0.2), 4.4, 4.6, 3.2, canopy_col)
		_proxy_lobe(st, Vector3(1.3, 9.2, -0.3), 4.0, 4.2, 3.0, canopy_col.lightened(0.06))
	st.generate_normals()
	var mesh := st.commit()
	var hm := _heavy_materials(PerformanceSettings.tree_distance(), MID_AT)
	mesh.surface_set_material(0, hm[1])  # vertex-colour "solid" material, distance-gated
	_far_proxy_cache[key] = mesh
	return mesh


## The version 1 low-poly mesh for `id` at detail `lod` (1 or 2) for the far tiers.
static func mesh_far(id: String, lod: int) -> Mesh:
	var entry: Dictionary = catalog_far().get(id, {})
	if entry.is_empty():
		push_error("NaturePack: no far-tier asset " + id)
		return null
	var lods: Array = entry["lods"]
	lod = clampi(lod, 1, lods.size())
	return _load_mesh(DIR_FAR + lods[lod - 1]["path"], id, "far%d#%s" % [lod, id])
