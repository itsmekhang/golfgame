class_name RoughGrass
extends RefCounted
## Fills the rough with grass in 64 m tiles that can be rebuilt individually.
## Dense beside fairways/greens (from the layout's cached distance-to-turf), sparser further out.
##
## Render modes (see `MODE`, key G cycles):
##  - "wind": generated blade mesh (RoughGrass._blade_mesh) on shaders/grass_wind.gdshader --
##    unshaded, colored by a generated vertical gradient, swayed by a tiling wind noise
##    texture, pushed away from the ball. No per-instance texture, no baked geometry.
##    Default: cheap enough to replace "kolosok" everywhere.
##  - "gradient": user-supplied gradient/wind shader on a generated clump of short blades.
##    Blades flatten around `interracting_object_pos` (the ball).
##  - "atlas": user-supplied atlas shader on the SimpleGrassTextured cross-quad mesh + texture.
##  - "sgt": stock SimpleGrassTextured node (addons/simplegrasstextured, MIT).
##  - "kolosok": photo-scanned blade cards ("Trava Kolosok" atlas + OBJ clump) on the
##    two-sided card shader (shaders/grass_cards.gdshader). 34 cards/clump + a 2.4 MB atlas
##    per instance -- kept for reference but no longer the default; it's what was killing
##    performance in the rough.

static var MODE: String = "wind"

const KOLOSOK_OBJ := "res://assets/textures/tiles/rough_grass/Trava Kolosok.obj"
const KOLOSOK_ATLAS := "res://assets/textures/tiles/rough_grass/kolosok_atlas.png"
const KOLOSOK_SCALE := 0.0013  # OBJ units -> metres
const KOLOSOK_WIDEN := 2.6  # blades in the scan are very thin; widen the cards so they read at distance
const KOLOSOK_CARDS_PER_CLUMP := 12
const KOLOSOK_VARIANTS := 6
## Second, sparser layer of taller modelled wild grass (56 blades sampled from the
## user's grass.obj scatter), drawn with the gradient shader.
const WILD_OBJ := "res://assets/textures/tiles/rough_grass/wild_grass_clump.obj"
const WILD_SCALE := 0.55  # clump ~0.4 m wide, 0.5 m tall
const WILD_DENSITY := 0.12  # clumps per m2 in the rough band
const WILD_MAX_CLUMPS := 60000  # independent budget so a big course can't make this layer unbounded
## Keep every blade/clump this far from a bunker or water outline, matching (and
## slightly exceeding) the terrain shader's anti-aliased edge so grass never reads
## as sitting on top of sand or water.
const HAZARD_CLEARANCE := 1.5
static var _wild_mesh: Mesh = null
static var _kolosok_cards: Array = []  # [[Vector3 x4, Vector2 x4], ...]
static var _kolosok_meshes: Array = []

const TILE := 32.0
const SGT_SCRIPT := "res://addons/simplegrasstextured/grass.gd"
const SGT_MESH := "res://addons/simplegrasstextured/default_mesh.tres"
const SGT_TEXTURE := "res://addons/simplegrasstextured/textures/grassbushcc008.png"

static var last_material: ShaderMaterial = null


static func sgt_available() -> bool:
	return ResourceLoader.exists(SGT_SCRIPT)


## Build all grass. `density` = clumps per m² within 8 m of turf; 30% of that out to `band`;
## `far_density` from `band` to 60 m; nothing beyond. Defaults are maxed out for the cheap
## "wind" blade mesh (~1 clump per 15x15 cm near turf, each a 9-strand tuft -- solid hair-like
## coverage up close); kolosok's 34-card clumps are ~40x heavier per instance, so its cap is
## clamped back down below regardless of what's passed in here. `max_blades` is the real
## limiter on the level-load hang risk: placement is a CPU loop (one RNG draw + array append
## per clump), not GPU cost, so this is capped well short of "as many as the GPU could draw."
static func build(layout: CourseLayout, rng_seed: int = 3, band: float = 26.0, density: float = 22.0,
		far_density: float = 5.0, max_blades: int = 900000) -> Node3D:
	if not layout.has_cache():
		layout.build_cache(2.0)
	var mode := MODE
	if mode == "sgt" and not sgt_available():
		mode = "gradient"
	if mode == "kolosok":
		max_blades = mini(max_blades, 140000)
	var params := {"seed": rng_seed, "band": band, "density": density, "far": far_density, "scale": 1.0, "mode": mode}
	params["scale"] = _density_scale(layout, params, max_blades)

	var group := Node3D.new()
	group.name = "RoughGrass"
	group.set_meta("params", params)
	var mesh: Mesh
	if mode == "atlas":
		mesh = _cross_quad_mesh()
	elif mode == "kolosok":
		mesh = _kolosok_mesh(0)
	else:
		mesh = _blade_mesh()  # "wind" and "gradient" both use the plain blade clump
	var mat := _material(mode)
	last_material = mat
	group.set_meta("mesh", mesh)
	group.set_meta("material", mat)

	var total := 0
	if mode == "sgt":
		var script: GDScript = load(SGT_SCRIPT)
		var node = script.new()
		node.texture_albedo = load(SGT_TEXTURE)
		node.scale_h = 0.3
		node.scale_w = 0.35
		node.scale_var = -0.35
		node.light_mode = 1
		node.grass_strength = 0.5
		node.optimization_by_distance = true
		node.optimization_dist_min = 25.0
		node.optimization_dist_max = 140.0
		node.sgt_dist_min = 0.0
		var xf: Array = []
		for key in _tile_keys(layout, layout.bounds):
			var tile := _sample_tile(layout, key, params)
			xf.append_array(tile[0])
		node.add_grass_batch(xf)
		node.name = "SGT"
		group.add_child(node)
		total = xf.size()
	else:
		for key in _tile_keys(layout, layout.bounds):
			var tile_mesh: Mesh = _kolosok_mesh(absi(key.x * 7 + key.y * 13) % KOLOSOK_VARIANTS) if mode == "kolosok" else mesh
			var mmi := _build_tile(layout, key, params, tile_mesh, mat)
			if mmi != null:
				total += mmi.multimesh.instance_count
				group.add_child(mmi)
	# wild grass layer on top (any mode)
	var wild := _wild_mesh_get()
	if wild != null:
		var wild_params := params.duplicate()
		wild_params["mode"] = "wild"
		wild_params["density"] = WILD_DENSITY
		wild_params["far"] = WILD_DENSITY * 0.5
		wild_params["scale"] = 1.0
		wild_params["seed"] = rng_seed + 77
		wild_params["scale"] = _density_scale(layout, wild_params, WILD_MAX_CLUMPS)
		var wild_mat := _material("gradient")
		wild_mat.set_shader_parameter("bottom_color", Color(0.08, 0.2, 0.05))
		wild_mat.set_shader_parameter("top_color", Color(0.36, 0.6, 0.2))
		wild_mat.set_shader_parameter("windDis", 0.18)
		var wild_group := Node3D.new()
		wild_group.name = "WildGrass"
		wild_group.set_meta("params", wild_params)
		wild_group.set_meta("mesh", wild)
		wild_group.set_meta("material", wild_mat)
		for key in _tile_keys(layout, layout.bounds):
			var mmi := _build_tile(layout, key, wild_params, wild, wild_mat)
			if mmi != null:
				total += mmi.multimesh.instance_count
				wild_group.add_child(mmi)
		group.add_child(wild_group)
	group.set_meta("blade_count", total)
	return group


## Parse the wild grass clump OBJ (quads, UV.y = 1 at root) into a mesh.
static func _wild_mesh_get() -> Mesh:
	if _wild_mesh != null:
		return _wild_mesh
	var text := FileAccess.get_file_as_string(WILD_OBJ)
	if text == "":
		return null
	var vs: Array[Vector3] = []
	var vts: Array[Vector2] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	for line in text.split("
"):
		var p := line.strip_edges().split(" ", false)
		if p.is_empty():
			continue
		if p[0] == "v" and p.size() >= 4:
			vs.append(Vector3(float(p[1]), float(p[2]), float(p[3])) * WILD_SCALE)
		elif p[0] == "vt" and p.size() >= 3:
			vts.append(Vector2(float(p[1]), float(p[2])))
		elif p[0] == "f" and p.size() >= 4:
			var pos: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for k in range(1, p.size()):
				var a := p[k].split("/")
				pos.append(vs[int(a[0]) - 1])
				uv.append(vts[int(a[1]) - 1] if a.size() > 1 and a[1] != "" else Vector2(0.5, 0.5))
			var nrm: Vector3 = (pos[1] - pos[0]).cross(pos[2] - pos[0]).normalized()
			for k in range(pos.size()):
				st.set_normal(nrm)
				st.set_uv(uv[k])
				st.set_color(Color.WHITE)
				st.add_vertex(pos[k])
			for t in range(1, pos.size() - 1):
				st.add_index(idx)
				st.add_index(idx + t)
				st.add_index(idx + t + 1)
			idx += pos.size()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	_wild_mesh = mesh
	return mesh


## Rebuild the grass tiles intersecting `rect` (after a dig). SGT mode rebuilds everything.
static func rebuild_tiles(layout: CourseLayout, group: Node3D, rect: Rect2) -> void:
	if group == null:
		return
	var params: Dictionary = group.get_meta("params")
	if params["mode"] == "sgt":
		var parent := group.get_parent()
		var fresh := build(layout, params["seed"], params["band"], params["density"], params["far"])
		parent.add_child(fresh)
		group.queue_free()
		commit(fresh)
		return
	var wild_group := group.get_node_or_null("WildGrass")
	if wild_group != null:
		var wp: Dictionary = wild_group.get_meta("params")
		for key in _tile_keys(layout, rect):
			var oldw := wild_group.get_node_or_null(_tile_name(key))
			if oldw != null:
				oldw.name = "old"
				oldw.queue_free()
			var mmw := _build_tile(layout, key, wp, wild_group.get_meta("mesh"), wild_group.get_meta("material"))
			if mmw != null:
				wild_group.add_child(mmw)
	var mesh: Mesh = group.get_meta("mesh")
	var mat: Material = group.get_meta("material")
	for key in _tile_keys(layout, rect):
		var old := group.get_node_or_null(_tile_name(key))
		if old != null:
			old.name = "old"
			old.queue_free()
		var tile_mesh: Mesh = _kolosok_mesh(absi(key.x * 7 + key.y * 13) % KOLOSOK_VARIANTS) if params["mode"] == "kolosok" else mesh
		var mmi := _build_tile(layout, key, params, tile_mesh, mat)
		if mmi != null:
			group.add_child(mmi)


## Call after the node is in the tree (needed by the SGT node to build its multimesh).
static func commit(grass: Node) -> void:
	if grass == null:
		return
	var sgt := grass.get_node_or_null("SGT")
	if sgt != null and sgt.has_method("_update_multimesh"):
		sgt._update_multimesh()


## Feed the ball position into the active shader so blades flatten/push under it.
## Setting both uniform names is harmless -- Godot silently ignores a shader-parameter
## key the current shader doesn't declare -- so this doesn't need to know which mode is live.
static func set_interactor(pos: Vector3) -> void:
	if last_material != null:
		last_material.set_shader_parameter("interracting_object_pos", pos)
		last_material.set_shader_parameter("character_position", pos)


# ---- tiles --------------------------------------------------------------------

static func _tile_name(key: Vector2i) -> String:
	return "Tile_%d_%d" % [key.x, key.y]


static func _tile_keys(layout: CourseLayout, rect: Rect2) -> Array:
	var b := layout.bounds
	var r := rect.intersection(b)
	var out := []
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return out
	var tx0 := int(floor((r.position.x - b.position.x) / TILE))
	var tz0 := int(floor((r.position.y - b.position.y) / TILE))
	var tx1 := int(floor((r.end.x - b.position.x - 0.001) / TILE))
	var tz1 := int(floor((r.end.y - b.position.y - 0.001) / TILE))
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			out.append(Vector2i(tx, tz))
	return out


static func _per_cell(d: float, params: Dictionary, area: float) -> float:
	var density: float = params["density"]
	if params["mode"] == "kolosok":
		density *= 0.6
	if params["mode"] == "wild":
		var band_w: float = params["band"]
		if d < band_w:
			return density * area
		if d < 60.0:
			return float(params["far"]) * area
		return 0.0
	var band: float = params["band"]
	if d < minf(8.0, band):
		return density * area * params["scale"]
	if d < band:
		return density * 0.3 * area * params["scale"]
	if d < 60.0:
		return float(params["far"]) * area * params["scale"]
	return 0.0


static func _density_scale(layout: CourseLayout, params: Dictionary, max_blades: int) -> float:
	var area := layout.cache_cell * layout.cache_cell
	var expected := 0.0
	for i in range(layout.cache_surface.size()):
		if layout.cache_surface[i] == PhysicsEnums.SurfaceType.ROUGH:
			expected += _per_cell(layout.cache_turf[i], params, area)
	return 1.0 if expected <= max_blades else float(max_blades) / expected


## Sample clump transforms for one tile from the cache. Returns [transforms, colors].
static func _sample_tile(layout: CourseLayout, key: Vector2i, params: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([params["seed"], key.x, key.y])
	var cell := layout.cache_cell
	var area := cell * cell
	var b := layout.bounds
	var cpt := maxi(int(TILE / cell), 1)
	var ix0 := key.x * cpt
	var iz0 := key.y * cpt
	var xf: Array = []
	var cols: Array = []
	var limit: int = params.get("max_per_tile", 1000000)
	var expected := 0.0
	for iz in range(iz0, mini(iz0 + cpt, layout.cache_nz)):
		for ix in range(ix0, mini(ix0 + cpt, layout.cache_nx)):
			var i := iz * layout.cache_nx + ix
			if layout.cache_surface[i] == PhysicsEnums.SurfaceType.ROUGH:
				expected += _per_cell(layout.cache_turf[i], params, area)
	# Reduce sampling before generating transforms/hazard queries, rather than
	# spending a frame generating thousands of clumps only to discard most of them.
	var tile_scale := minf(1.0, float(limit) / maxf(expected, 1.0))
	for iz in range(iz0, mini(iz0 + cpt, layout.cache_nz)):
		for ix in range(ix0, mini(ix0 + cpt, layout.cache_nx)):
			var i := iz * layout.cache_nx + ix
			if layout.cache_surface[i] != PhysicsEnums.SurfaceType.ROUGH:
				continue
			var cell_xz := Vector2(b.position.x + ix * cell, b.position.y + iz * cell)
			var d := layout.cache_turf[i]
			var per_cell := _per_cell(d, params, area) * tile_scale
			if per_cell <= 0.0:
				continue
			var count := int(per_cell)
			if rng.randf() < per_cell - count:
				count += 1
			var cx := b.position.x + ix * cell
			var cz := b.position.y + iz * cell
			var in_band: bool = d < params["band"]
			if count == 0:
				continue
			if layout.bunker_near(cell_xz, HAZARD_CLEARANCE) or layout.hazard_near(cell_xz, HAZARD_CLEARANCE):
				continue
			for k in range(count):
				var x := cx + rng.randf_range(-0.5, 0.5) * cell
				var z := cz + rng.randf_range(-0.5, 0.5) * cell
				var sample_xz := Vector2(x, z)
				if not layout.bounds.has_point(sample_xz) or layout.cached_sdf(x, z).x < CourseLayout.FIRST_CUT_WIDTH:
					continue
				if layout.bunker_near(sample_xz, HAZARD_CLEARANCE) or layout.hazard_near(sample_xz, HAZARD_CLEARANCE):
					continue
				var y := layout.cached_height(x, z)
				var s := rng.randf_range(0.65, 1.0) * (1.0 if in_band else 1.15)
				var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
				if params["mode"] == "atlas":
					basis = basis.scaled(Vector3(0.4, 0.35, 0.4))
				elif params["mode"] == "kolosok":
					basis = basis.scaled(Vector3(1.0, rng.randf_range(0.6, 0.86), 1.0))
				elif params["mode"] == "wind":
					basis = basis.scaled(Vector3(1.3, 1.0, 1.3))  # bushier clump footprint
				xf.append(Transform3D(basis, Vector3(x, y, z)))
				cols.append(Color(rng.randf(), rng.randf(), 1.0, 1.0))
	if xf.size() > limit:
		var selected: Array = []
		var selected_colors: Array = []
		for i in range(limit):
			var index := int(float(i) * xf.size() / limit)
			selected.append(xf[index])
			selected_colors.append(cols[index])
		return [selected, selected_colors]
	return [xf, cols]


static func _build_tile(layout: CourseLayout, key: Vector2i, params: Dictionary, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var sampled := _sample_tile(layout, key, params)
	var xf: Array = sampled[0]
	if xf.is_empty():
		return null
	var cols: Array = sampled[1]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in range(xf.size()):
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = _tile_name(key)
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = PerformanceSettings.grass_distance()
	mmi.visibility_range_end_margin = 5.0
	mmi.extra_cull_margin = 0.6
	# Hysteresis avoids forcing cutout grass through transparent alpha blending.
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mmi


# ---- meshes -------------------------------------------------------------------

## A clump of nine thin tapered strands fanned around the instance origin -- more, thinner
## blades than a fatter/fewer-bladed clump reads as individual hair strands instead of a
## blobby tuft. Still one shared mesh (built once, instanced everywhere), so this is a
## GPU triangle-count cost only -- it doesn't touch the per-instance CPU placement cost
## that actually limits how many clumps the level-load loop can place in a few seconds.
## UV.y = 1 at the root, 0 at the tip (the gradient/wind shaders sway the tip and colour by UV.y).
static func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := [[0.0, 0.015], [0.11, 0.011], [0.20, 0.0]]  # [height, half width]
	var top: float = rows[rows.size() - 1][0]
	var idx := 0
	var blade_count := 9
	for k in range(blade_count):
		var yaw := k * (TAU / blade_count) + 0.3
		var basis := Basis(Vector3.UP, yaw)
		var offset := basis * Vector3(0.0, 0.0, 0.05)
		var lean_dir := basis * Vector3(0.0, 0.0, 1.0)
		var bend := 0.05
		var nrm := (basis * Vector3(0, 0.2, 1)).normalized()
		for i in range(rows.size()):
			var h: float = rows[i][0]
			var w: float = rows[i][1]
			var lean := bend * h * h / (top * top)
			var v := float(i) / (rows.size() - 1)
			var right := basis * Vector3(w, 0, 0)
			var base := Vector3(0, h, 0) + lean_dir * lean + offset
			st.set_normal(nrm)
			st.set_uv(Vector2(0.0, 1.0 - v))
			st.set_color(Color.WHITE)
			st.add_vertex(base - right)
			st.set_normal(nrm)
			st.set_uv(Vector2(1.0, 1.0 - v))
			st.set_color(Color.WHITE)
			st.add_vertex(base + right)
		for i in range(rows.size() - 1):
			var a := idx + i * 2
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + 2)
			st.add_index(a + 1)
			st.add_index(a + 3)
			st.add_index(a + 2)
		idx += rows.size() * 2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	return mesh


## Two crossed textured quads (like SimpleGrassTextured's default mesh).
static func _cross_quad_mesh() -> Mesh:
	if ResourceLoader.exists(SGT_MESH):
		var m: Mesh = load(SGT_MESH)
		if m != null:
			return m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	for rot in [0.0, PI * 0.5]:
		var right := Vector3(cos(rot), 0, sin(rot)) * 0.18
		var quad := [Vector3(-right.x, 0, -right.z), Vector3(right.x, 0, right.z), Vector3(right.x, 0.3, right.z), Vector3(-right.x, 0.3, -right.z)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in range(4):
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			st.set_color(Color.WHITE)
			st.add_vertex(quad[k])
		for t in [0, 1, 2, 0, 2, 3]:
			st.add_index(idx + t)
		idx += 4
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	return mesh


## Parse the "Trava Kolosok" OBJ: every face is a quad card with atlas UVs.
static func _load_kolosok_cards() -> void:
	if not _kolosok_cards.is_empty():
		return
	var text := FileAccess.get_file_as_string(KOLOSOK_OBJ)
	if text == "":
		push_warning("RoughGrass: missing " + KOLOSOK_OBJ)
		return
	var vs: Array[Vector3] = []
	var vts: Array[Vector2] = []
	for line in text.split("\n"):
		var p := line.strip_edges().split(" ", false)
		if p.is_empty():
			continue
		if p[0] == "v" and p.size() >= 4:
			vs.append(Vector3(float(p[1]), float(p[2]), float(p[3])) * KOLOSOK_SCALE)
		elif p[0] == "vt" and p.size() >= 3:
			vts.append(Vector2(float(p[1]), 1.0 - float(p[2])))  # OBJ v is bottom-up
		elif p[0] == "f" and p.size() == 5:
			var pos: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for k in range(1, 5):
				var idx := p[k].split("/")
				pos.append(vs[int(idx[0]) - 1])
				uv.append(vts[int(idx[1]) - 1] if idx.size() > 1 and idx[1] != "" else Vector2.ZERO)
			_kolosok_cards.append([pos, uv])
	# drop the clump to y = 0
	var min_y := INF
	for c in _kolosok_cards:
		for v in c[0]:
			min_y = minf(min_y, v.y)
	for c in _kolosok_cards:
		for i in range(4):
			c[0][i] = c[0][i] - Vector3(0, min_y, 0)


## A clump: `KOLOSOK_CARDS_PER_CLUMP` random cards from the OBJ, pulled into a tight tuft.
static func _kolosok_mesh(variant: int) -> Mesh:
	_load_kolosok_cards()
	while _kolosok_meshes.size() <= variant:
		_kolosok_meshes.append(null)
	if _kolosok_meshes[variant] != null:
		return _kolosok_meshes[variant]
	if _kolosok_cards.is_empty():
		return _blade_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	var picked: Array = []
	for i in range(KOLOSOK_CARDS_PER_CLUMP):
		picked.append(_kolosok_cards[rng.randi_range(0, _kolosok_cards.size() - 1)])
	var centre := Vector3.ZERO
	for c in picked:
		for v in c[0]:
			centre += Vector3(v.x, 0.0, v.z)
	centre /= float(picked.size() * 4)
	for c in picked:
		var pos: Array = c[0]
		var uv: Array = c[1]
		var card_c := Vector3.ZERO
		for v in pos:
			card_c += Vector3(v.x, 0.0, v.z)
		card_c /= 4.0
		var shift: Vector3 = (card_c - centre) * 0.35 - card_c  # keep 35% of the spread
		shift += Vector3(rng.randf_range(-0.05, 0.05), 0.0, rng.randf_range(-0.05, 0.05))
		var e1: Vector3 = pos[1] - pos[0]
		var e2: Vector3 = pos[3] - pos[0]
		var nrm: Vector3 = e1.cross(e2).normalized()
		var mid: Vector3 = (pos[0] + pos[1] + pos[2] + pos[3]) * 0.25
		for k in range(4):
			var v: Vector3 = pos[k]
			# widen across the card (keep height)
			var across := Vector3(v.x - mid.x, 0.0, v.z - mid.z)
			v = Vector3(mid.x, v.y, mid.z) + across * KOLOSOK_WIDEN
			st.set_normal(nrm)
			st.set_uv(uv[k])
			st.set_color(Color.WHITE)
			st.add_vertex(v + shift)
		for t in [0, 1, 2, 0, 2, 3]:
			st.add_index(idx + t)
		idx += 4
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, 0)
	_kolosok_meshes[variant] = mesh
	return mesh


# ---- materials ----------------------------------------------------------------

static func _noise_tex(seed_v: int, frequency: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = frequency
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	return t


## Vertical gradient (bottom_color -> top_color) sampled by grass_wind.gdshader's ALBEDO.
static func _ramp_tex(bottom: Color, top: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([bottom, top])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 2
	return t


## Identity falloff curve (push strength == raw distance falloff) for grass_wind.gdshader's
## character_distance_falloff_curve. A plain Curve/CurveTexture, same as an artist would
## author by hand, so the push shape is easy to reshape later without touching the shader.
static func _curve_tex() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _material(mode: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if mode == "wind":
		mat.shader = load("res://shaders/grass_wind.gdshader")
		# Kept clearly darker than the fairway's mowed-stripe greens
		# (terrain_builder.gd's COL_FAIRWAY_A/B, ~(0.44,0.70,0.24)/(0.35,0.60,0.20)) at both
		# ends of the ramp, so the rough always reads as rough next to it.
		mat.set_shader_parameter("color_ramp", _ramp_tex(Color(0.05, 0.13, 0.04), Color(0.24, 0.38, 0.14)))
		mat.set_shader_parameter("wind_noise", _noise_tex(33, 0.03))
		mat.set_shader_parameter("character_distance_falloff_curve", _curve_tex())
		mat.set_shader_parameter("character_position", Vector3(0, -1000, 0))
		return mat
	if mode == "kolosok":
		mat.shader = load("res://shaders/grass_cards.gdshader")
		mat.set_shader_parameter("main_texture", load(KOLOSOK_ATLAS))
		mat.set_shader_parameter("tint", Color(0.82, 0.92, 0.72))
		mat.set_shader_parameter("base_darken", Color(0.5, 0.6, 0.4))
		mat.set_shader_parameter("interracting_object_pos", Vector3(0, -1000, 0))
		return mat
	if mode == "atlas":
		mat.shader = load("res://shaders/grass_atlas.gdshader")
		mat.set_shader_parameter("texture_count", Vector2(1.0, 1.0))
		mat.set_shader_parameter("character_height", 1.85)
		if ResourceLoader.exists(SGT_TEXTURE):
			mat.set_shader_parameter("main_texture", load(SGT_TEXTURE))
		return mat
	mat.shader = load("res://shaders/grass_gradient.gdshader")
	# Rough reference: dense, saturated green blades, darker at the base, a few paler tips
	mat.set_shader_parameter("bottom_color", Color(0.10, 0.27, 0.06))
	mat.set_shader_parameter("top_color", Color(0.42, 0.68, 0.20))
	mat.set_shader_parameter("color_variation_1", Color(0.55, 0.66, 0.22))
	mat.set_shader_parameter("color_variation_2", Color(0.24, 0.50, 0.14))
	mat.set_shader_parameter("noise_variation_1", _noise_tex(31, 0.02))
	mat.set_shader_parameter("noise_variation_2", _noise_tex(32, 0.05))
	mat.set_shader_parameter("wind_noise", _noise_tex(33, 0.03))
	mat.set_shader_parameter("Noise1Scale", 24.0)
	mat.set_shader_parameter("Noise2Scale", 9.0)
	mat.set_shader_parameter("windNoiseScale", 18.0)
	mat.set_shader_parameter("windNoisePanSpeed", Vector2(0.06, 0.04))
	mat.set_shader_parameter("windSpeed", 2.2)
	mat.set_shader_parameter("windDis", 0.12)
	mat.set_shader_parameter("noiseStrength", 0.5)
	mat.set_shader_parameter("displaceStrength", 2.5)
	mat.set_shader_parameter("wind_noise_scale_strength", 0.15)
	mat.set_shader_parameter("combined_noise_min_scale", 0.6)
	mat.set_shader_parameter("combined_noise_max_scale", 1.4)
	mat.set_shader_parameter("flatten_radius", 0.5)
	mat.set_shader_parameter("flatten_strength", 3.0)
	mat.set_shader_parameter("flatten_floor", 0.25)
	mat.set_shader_parameter("interracting_object_pos", Vector3(0, -1000, 0))
	return mat
