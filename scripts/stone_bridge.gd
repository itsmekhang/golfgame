class_name StoneBridge
extends Node3D
## A stone arch footbridge over a creek -- Augusta's Hogan and Nelson bridges around the
## 12th green. Authored per hole as CourseLayout.Hole.bridges entries [a, b, width, arches]
## (a and b on dry ground either side of the water) and built by PropScatter.decorate().
##
## The mesh is generated here: a turf walkway that arches gently from bank to bank, stone
## parapets either side, and `arches` round openings whose legs run down into the water.
## Stone is drawn by shaders/bridge_stone.gdshader from metre UVs (UV = along / height,
## UV2.y = height above the arch soffit for the voussoir ring). A trimesh collider on
## PropScatter.OBSTACLE_LAYER lets a ball clatter off it.

const STONE_SHADER = preload("res://shaders/bridge_stone.gdshader")
const DECK_TEXTURE = preload("res://assets/textures/tiles/fairway_tile.png")
const PARAPET_H := 0.62  # parapet height above the walkway
const WALL_T := 0.38  # parapet / spandrel wall thickness
const CROWN_T := 0.42  # stone between the arch crown and the walkway
const PIER_W := 0.55  # solid stone between neighbouring arches
const ARCH_MARGIN := 0.6  # metres the arches reach past the water's edge onto each bank
const MIN_ABUTMENT := 0.08  # share of the span always left solid at each end


static func build(layout: CourseLayout, a: Vector2, b: Vector2, width: float, arches: int = 1) -> StoneBridge:
	var br := StoneBridge.new()
	br.name = "StoneBridge"
	var span := a.distance_to(b)
	var dir := (b - a) / maxf(span, 0.001)
	var side := Vector2(-dir.y, dir.x)
	var ha := layout.height_at(a.x, a.y)
	var hb := layout.height_at(b.x, b.y)
	# Water and bed under the crossing, and where along the span the water lies.
	var level := -INF
	var bed := INF
	var wet0 := 1.0
	var wet1 := 0.0
	for i in range(81):
		var t := i / 80.0
		var p := a.lerp(b, t)
		bed = minf(bed, layout.height_at(p.x, p.y))
		var hz := layout.hazard_at(p)
		if hz != null:
			level = maxf(level, hz.water_level_at(p))
			wet0 = minf(wet0, t)
			wet1 = maxf(wet1, t)
	if level == -INF:
		level = bed + 0.2
		wet0 = 0.3
		wet1 = 0.7
	var deep := minf(bed, level) - 1.2
	var rise := clampf(span * 0.11, 0.9, 1.9)
	var deck := func(t: float) -> float:
		return lerpf(ha, hb, t) + 0.12 + rise * pow(sin(PI * t), 0.85)

	# Arches over the water only (anything over the banks would just be buried in them),
	# reaching a little onto each bank.
	var margin_t := ARCH_MARGIN / maxf(span, 0.001)
	var open0 := clampf(wet0 - margin_t, MIN_ABUTMENT, 0.5)
	var open1 := clampf(wet1 + margin_t, 0.5, 1.0 - MIN_ABUTMENT)
	var pier_t := PIER_W / maxf(span, 0.001)
	var arch_w := (open1 - open0 - pier_t * (arches - 1)) / arches
	var arch_ranges: Array = []  # [start t, end t, crown y]
	for k in range(arches):
		var s := open0 + k * (arch_w + pier_t)
		var e := s + arch_w
		var crown: float = deck.call((s + e) * 0.5) - CROWN_T
		crown = maxf(crown, level + 0.9)
		arch_ranges.append([s, e, crown])
	var soffit := func(t: float) -> float:
		for r in arch_ranges:
			if t > r[0] and t < r[1]:
				var u: float = (t - (r[0] + r[1]) * 0.5) / ((r[1] - r[0]) * 0.5)
				return deep + (float(r[2]) - deep) * sqrt(maxf(0.0, 1.0 - u * u))
		return deep

	# Sample stations: even steps plus angle steps round each arch (its legs are steep).
	var ts: Array = []
	for i in range(81):
		ts.append(i / 80.0)
	for r in arch_ranges:
		for j in range(1, 24):
			var th := PI * j / 24.0
			ts.append((r[0] + r[1]) * 0.5 - (r[1] - r[0]) * 0.5 * cos(th))
		ts.append(float(r[0]) + 0.0001)
		ts.append(float(r[1]) - 0.0001)
	ts.sort()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var turf := SurfaceTool.new()
	turf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var ho := hw + WALL_T
	var to3 := func(t: float, lateral: float, y: float) -> Vector3:
		var p := a + dir * (span * t) + side * lateral
		return Vector3(p.x, y, p.y)
	# quad helper: corners in order, all sharing one normal; uv/uv2 per corner. Godot's
	# front faces wind clockwise, so flip the order whenever it would face away from `n`.
	var quad := func(tool: SurfaceTool, v: Array, n: Vector3, uv: Array, uv2: Array) -> void:
		var e1: Vector3 = v[1] - v[0]
		var e2: Vector3 = v[2] - v[0]
		var order := [0, 1, 2, 0, 2, 3] if e2.cross(e1).dot(n) >= 0.0 else [0, 2, 1, 0, 3, 2]
		for idx in order:
			tool.set_normal(n)
			tool.set_uv(uv[idx])
			tool.set_uv2(uv2[idx])
			tool.add_vertex(v[idx])
	var n_side := Vector3(side.x, 0.0, side.y)
	var no_ring := Vector2(-1.0, 99.0)
	for i in range(ts.size() - 1):
		var t0: float = ts[i]
		var t1: float = ts[i + 1]
		if t1 - t0 < 0.00001:
			continue
		var s0 := t0 * span
		var s1 := t1 * span
		var d0: float = deck.call(t0)
		var d1: float = deck.call(t1)
		var b0: float = soffit.call(t0)
		var b1: float = soffit.call(t1)
		var top0 := d0 + PARAPET_H
		var top1 := d1 + PARAPET_H
		var in_arch := b0 > deep + 0.01 or b1 > deep + 0.01
		for sgn in [-1.0, 1.0]:
			var lat: float = ho * sgn
			var n: Vector3 = n_side * sgn
			# outer spandrel wall, soffit to parapet top
			var v := [to3.call(t0, lat, b0), to3.call(t0, lat, top0), to3.call(t1, lat, top1), to3.call(t1, lat, b1)]
			var uv := [Vector2(s0, b0), Vector2(s0, top0), Vector2(s1, top1), Vector2(s1, b1)]
			var uv2 := [Vector2(s0, 0.0), Vector2(s0, top0 - b0), Vector2(s1, top1 - b1), Vector2(s1, 0.0)] if in_arch else [no_ring, no_ring, no_ring, no_ring]
			if sgn < 0.0:
				v.reverse()
				uv.reverse()
				uv2.reverse()
			quad.call(st, v, n, uv, uv2)
			# parapet inner face, walkway to top
			var il: float = hw * sgn
			var vi := [to3.call(t0, il, d0), to3.call(t1, il, d1), to3.call(t1, il, top1), to3.call(t0, il, top0)]
			var uvi := [Vector2(s0, d0), Vector2(s1, d1), Vector2(s1, top1), Vector2(s0, top0)]
			if sgn < 0.0:
				vi.reverse()
				uvi.reverse()
			quad.call(st, vi, -n, uvi, [no_ring, no_ring, no_ring, no_ring])
			# parapet coping
			var lo: float = minf(il, lat)
			var hi: float = maxf(il, lat)
			var vt := [to3.call(t0, lo, top0), to3.call(t0, hi, top0), to3.call(t1, hi, top1), to3.call(t1, lo, top1)]
			quad.call(st, vt, Vector3.UP, [Vector2(s0, lo), Vector2(s0, hi), Vector2(s1, hi), Vector2(s1, lo)], [no_ring, no_ring, no_ring, no_ring])
		# turf walkway
		var vd := [to3.call(t0, -hw, d0), to3.call(t0, hw, d0), to3.call(t1, hw, d1), to3.call(t1, -hw, d1)]
		quad.call(turf, vd, Vector3.UP, [Vector2(s0, -hw), Vector2(s0, hw), Vector2(s1, hw), Vector2(s1, -hw)], [no_ring, no_ring, no_ring, no_ring])
		# arch soffit, facing down into the opening
		if in_arch:
			var vs := [to3.call(t0, ho, b0), to3.call(t0, -ho, b0), to3.call(t1, -ho, b1), to3.call(t1, ho, b1)]
			quad.call(st, vs, Vector3.DOWN, [Vector2(s0, -ho), Vector2(s0, ho), Vector2(s1, ho), Vector2(s1, -ho)], [Vector2(s0, 0.0), Vector2(s0, 0.0), Vector2(s1, 0.0), Vector2(s1, 0.0)])
	# end faces, sunk into the banks
	for t in [0.0, 1.0]:
		var d: float = deck.call(t)
		var n := Vector3(-dir.x, 0.0, -dir.y) if t == 0.0 else Vector3(dir.x, 0.0, dir.y)
		var v := [to3.call(t, -ho, deep), to3.call(t, ho, deep), to3.call(t, ho, d + PARAPET_H), to3.call(t, -ho, d + PARAPET_H)]
		var uv := [Vector2(-ho, deep), Vector2(ho, deep), Vector2(ho, d + PARAPET_H), Vector2(-ho, d + PARAPET_H)]
		if t == 0.0:
			v.reverse()
			uv.reverse()
		quad.call(st, v, n, uv, [no_ring, no_ring, no_ring, no_ring])

	var mesh := ArrayMesh.new()
	st.commit(mesh)
	var stone := ShaderMaterial.new()
	stone.shader = STONE_SHADER
	stone.set_shader_parameter("water_level", level)
	mesh.surface_set_material(0, stone)
	turf.commit(mesh)
	var grass := StandardMaterial3D.new()
	grass.albedo_texture = DECK_TEXTURE
	grass.albedo_color = Color(0.78, 0.9, 0.72)
	grass.uv1_scale = Vector3(0.25, 0.25, 0.25)
	grass.roughness = 0.95
	mesh.surface_set_material(1, grass)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	br.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Collider"
	body.collision_layer = PropScatter.OBSTACLE_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	br.add_child(body)
	return br
