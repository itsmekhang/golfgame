class_name Landforms
extends RefCounted
## Named terrain features (assets/course/augusta_landforms.json) as smooth additive
## height primitives: mounds/hollows, terrace shelves, tilts and ridges. Authored in a
## hole's green or route frame, compiled once into world space, then summed on top of
## the shaped terrain by CourseLayout.base_height_from.

const DATA_PATH := "res://assets/course/augusta_landforms.json"

static var _data: Dictionary = {}


static func _specs(hole_number: int) -> Array:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f != null else {"holes": {}}
	return _data["holes"].get(str(hole_number), [])


## World-space landforms for one hole. `green` = [centre, approach dir]; the route
## frame is sampled from the hole's waypoints.
static func compile(hole: CourseLayout.Hole) -> Array:
	var out: Array = []
	var wps := hole.waypoints
	var gc := Vector2(wps[wps.size() - 1].x, wps[wps.size() - 1].z)
	var prev := Vector2(wps[wps.size() - 2].x, wps[wps.size() - 2].z)
	var gdir := (gc - prev).normalized()
	for spec in _specs(hole.index + 1):
		var origin: Vector2
		var fx: Vector2
		if spec.get("at", "green") == "route":
			var rp := _route_point(wps, float(spec.get("s", 0.5)))
			origin = rp[0]
			fx = rp[1]
		else:
			origin = gc
			fx = gdir
		var fy := Vector2(-fx.y, fx.x)
		var lf := {"id": spec["id"], "type": spec["type"], "h": float(spec.get("h", 0.0))}
		match spec["type"]:
			"mound", "plateau":
				lf["c"] = origin + fx * float(spec["x"]) + fy * float(spec["y"])
				lf["rx"] = float(spec["rx"])
				lf["ry"] = float(spec["ry"])
				lf["flat"] = float(spec.get("flat", 0.55))
				var rot := deg_to_rad(float(spec.get("rot", 0.0)))
				lf["ax"] = fx.rotated(rot)
				lf["ay"] = fy.rotated(rot)
				lf["r"] = maxf(lf["rx"], lf["ry"])
			"shelf", "tilt":
				lf["c"] = origin + fx * float(spec["x"]) + fy * float(spec["y"])
				lf["dir"] = fx.rotated(deg_to_rad(float(spec.get("dir", 0.0))))
				lf["w"] = float(spec.get("w", 8.0))
				lf["grade"] = float(spec.get("grade", 0.0))
				lf["r"] = float(spec.get("r", 20.0))
			"ridge":
				lf["a"] = origin + fx * float(spec["x0"]) + fy * float(spec["y0"])
				lf["b"] = origin + fx * float(spec["x1"]) + fy * float(spec["y1"])
				lf["w"] = float(spec.get("w", 5.0))
				lf["c"] = (lf["a"] + lf["b"]) * 0.5
				lf["r"] = (lf["a"] as Vector2).distance_to(lf["b"]) * 0.5 + lf["w"] * 2.0
		var c: Vector2 = lf["c"]
		var r: float = lf["r"] * (1.6 if spec["type"] in ["shelf", "tilt"] else 1.0)
		lf["bounds"] = Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0)
		out.append(lf)
	return out


static func _route_point(wps: Array[Vector3], s: float) -> Array:
	var total := 0.0
	for i in range(1, wps.size()):
		total += (wps[i] - wps[i - 1]).length()
	var want := clampf(s, 0.0, 1.0) * total
	var acc := 0.0
	for i in range(1, wps.size()):
		var a := Vector2(wps[i - 1].x, wps[i - 1].z)
		var b := Vector2(wps[i].x, wps[i].z)
		var l := a.distance_to(b)
		if acc + l >= want or i == wps.size() - 1:
			var t := clampf((want - acc) / maxf(l, 0.001), 0.0, 1.0)
			return [a.lerp(b, t), (b - a).normalized()]
		acc += l
	return [Vector2(wps[0].x, wps[0].z), Vector2(0, -1)]


## Sum of every landform's height at `p`.
static func offset(list: Array, p: Vector2) -> float:
	var s := offset_split(list, p)
	return s.x + s.y


## Landform height at `p` split into (bumps, gentle): bumps are mounds, hollows and
## ridges -- surround features a putting surface must be shielded from -- while
## plateaus, shelves and tilts are the gentle grading a green is allowed to carry.
static func offset_split(list: Array, p: Vector2) -> Vector2:
	var bumps := 0.0
	var gentle := 0.0
	for lf in list:
		if not (lf["bounds"] as Rect2).has_point(p):
			continue
		var d: Vector2 = p - (lf["c"] as Vector2)
		var amp: float = lf["h"]
		match lf["type"]:
			"mound":
				var u: float = d.dot(lf["ax"]) / float(lf["rx"])
				var v: float = d.dot(lf["ay"]) / float(lf["ry"])
				var q: float = u * u + v * v
				if q < 1.0:
					var t: float = 1.0 - q
					bumps += amp * t * t * (3.0 - 2.0 * t)
			"plateau":
				# flat top out to `flat` of the radius, then a rounded fall to the edge
				var u: float = d.dot(lf["ax"]) / float(lf["rx"])
				var v: float = d.dot(lf["ay"]) / float(lf["ry"])
				var q: float = sqrt(u * u + v * v)
				if q < 1.0:
					gentle += amp * (1.0 - smoothstep(float(lf["flat"]), 1.0, q))
			"shelf":
				# full strength inside r, eased out over the next half radius so the
				# plateau's far edge blends into the surroundings well past the feature
				var r: float = lf["r"]
				var w: float = lf["w"]
				var m: float = 1.0 - smoothstep(r, r * 1.5, d.length())
				if m > 0.0:
					gentle += amp * smoothstep(-w * 0.5, w * 0.5, d.dot(lf["dir"])) * m
			"tilt":
				# a plane of the given grade across ±r, held flat beyond it
				var r: float = lf["r"]
				var m: float = 1.0 - smoothstep(r, r * 1.6, d.length())
				if m > 0.0:
					gentle += float(lf["grade"]) * clampf(d.dot(lf["dir"]), -r, r) * m
			"ridge":
				var dist: float = CourseArea.dist_to_segment(p, lf["a"], lf["b"])
				var w: float = lf["w"]
				if dist < w:
					var t: float = 1.0 - dist / w
					bumps += amp * t * t * (3.0 - 2.0 * t)
	return Vector2(bumps, gentle)
