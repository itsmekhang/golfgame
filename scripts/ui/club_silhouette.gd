class_name ClubSilhouette
extends Control
## Vector-drawn club (head + shaft + grip) in the loading screen's flat-illustration style.
## The `silhouette` id comes from data/club_catalog.json; `finish` / `accent` colour it;
## `condition` adds wear (duller finish, scratches); `ghost` draws the shape as a dark
## cut-out for a cabinet slot that hasn't been filled yet. Placeholder art: swap for sprites
## or 3D previews later without touching the shop or cabinet code.

const INK := Color("193b32")

var silhouette := "iron"
var finish := Color("7d8388")
var accent := Color("b3b9bd")
var condition := 1.0
var ghost := false
var show_shaft := true


static func label_for(sil: String) -> String:
	match sil:
		"driver": return "460cc driver"
		"driver_persimmon": return "Persimmon driver"
		"driver_grenade": return "Grenade driver"
		"wood": return "Fairway wood"
		"wood_persimmon": return "Persimmon wood"
		"hybrid": return "Hybrid"
		"hybrid_iron": return "Utility iron"
		"iron": return "Cavity-back iron set"
		"iron_blade": return "Forged iron set"
		"wedge": return "Wedge"
		"putter_blade": return "Blade putter"
		"putter_flange": return "Flanged blade putter"
		"putter_mallet": return "Mallet putter"
		"putter_heeltoe": return "Heel-toe blade putter"
		"putter_wing": return "Winged putter"
		"putter_tour": return "Tour blade putter"
		"putter_newport": return "Milled blade putter"
		"putter_robot": return "Robotic putter"
	return sil.capitalize()


## What a store that hides brand names calls a club: the silhouette's kind, made specific
## to the club's slot so it always matches the photo ("Gap wedge", "3-wood", "3-hybrid", ...).
static func shop_label(m: Dictionary) -> String:
	var slot := str(m.get("slot", ""))
	var sil := str(m.get("silhouette", ""))
	match str(m.get("type", "")):
		"wedge":
			var kinds := {"PW": "Pitching wedge", "GW": "Gap wedge", "SW": "Sand wedge", "LW": "Lob wedge"}
			return str(kinds.get(slot, "Wedge"))
		"wood":
			var n := slot.trim_suffix("W")
			return ("Persimmon %s-wood" if sil == "wood_persimmon" else "%s-wood") % n if n.is_valid_int() else label_for(sil)
		"hybrid":
			# every hybrid shares the "HY" slot, so the number comes from the name ("3H", "2U")
			var hit := _hybrid_number.search(str(m.get("name", "")))
			if hit != null:
				return ("%sU utility iron" if sil == "hybrid_iron" else "%s-hybrid") % hit.get_string(1)
	return label_for(sil)


static var _hybrid_number := RegEx.create_from_string("\\b(\\d{1,2})\\s*[HU]\\b")


func setup(model: Dictionary, p_condition: float = 1.0, p_ghost: bool = false) -> void:
	silhouette = str(model.get("silhouette", "iron"))
	finish = Color(str(model.get("finish", "7d8388")))
	accent = Color(str(model.get("accent", "b3b9bd")))
	condition = clampf(p_condition, 0.0, 1.0)
	ghost = p_ghost
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(120, 96)


func _p(x: float, y: float) -> Vector2:
	return Vector2(x / 100.0 * size.x, y / 100.0 * size.y)


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(p[0], p[1]))
	return out


func _ellipse(cx: float, cy: float, rx: float, ry: float, flat_left: float = 0.0, n: int = 28) -> Array:
	var pts: Array = []
	for i in range(n):
		var a := TAU * float(i) / n
		var x := cx + cos(a) * rx
		var y := cy + sin(a) * ry
		if flat_left > 0.0:
			x = maxf(x, cx - rx + flat_left)
		pts.append([x, y])
	return pts


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return  # not laid out yet; a zero-size polygon is rejected by the canvas renderer
	var fill := finish
	var acc := accent
	var wear := 1.0 - condition
	if ghost:
		fill = Color(INK, 0.22)
		acc = Color(INK, 0.0)
	else:
		# a beat-up club is duller and greyer
		fill = fill.lerp(Color(0.55, 0.55, 0.52), wear * 0.4)
	var outline := Color(INK, 0.9 if not ghost else 0.35)
	var head: Array = []
	var hosel := Vector2(56, 74)
	match silhouette:
		"driver", "driver_grenade":
			head = _ellipse(32, 80, 27, 15, 6.0)
			hosel = Vector2(57, 68)
		"driver_persimmon":
			head = _ellipse(32, 80, 24, 14, 8.0)
			hosel = Vector2(54, 68)
		"wood", "wood_persimmon":
			head = _ellipse(30, 82, 21, 11, 5.0)
			hosel = Vector2(49, 72)
		"hybrid":
			head = [[8, 74], [40, 70], [50, 74], [54, 82], [50, 92], [12, 93], [6, 86]]
			hosel = Vector2(52, 72)
		"hybrid_iron":
			head = [[8, 72], [48, 68], [54, 74], [56, 91], [14, 93], [7, 86]]
			hosel = Vector2(55, 70)
		"iron":
			head = [[6, 72], [48, 67], [56, 74], [58, 92], [14, 94], [6, 86]]
			hosel = Vector2(56, 70)
		"iron_blade":
			head = [[6, 74], [50, 70], [56, 75], [57, 91], [14, 93], [6, 87]]
			hosel = Vector2(56, 72)
		"wedge":
			head = [[8, 68], [50, 66], [58, 72], [60, 93], [18, 95], [6, 88]]
			hosel = Vector2(58, 68)
		"putter_blade", "putter_tour", "putter_newport":
			head = [[6, 78], [54, 78], [56, 82], [56, 90], [6, 90]]
			hosel = Vector2(50, 70)
		"putter_flange":
			head = [[6, 76], [54, 76], [56, 82], [56, 88], [40, 88], [40, 92], [6, 92]]
			hosel = Vector2(50, 68)
		"putter_heeltoe":
			head = [[4, 76], [12, 76], [12, 79], [48, 79], [48, 76], [56, 76], [58, 90], [4, 90]]
			hosel = Vector2(50, 68)
		"putter_mallet":
			# One continuous half ellipse closes across its straight club face.
			# Appending a face to a full ellipse crossed its outline.
			for i in range(21):
				var a := PI * float(i) / 20.0
				head.append([30.0 + cos(a) * 24.0, 80.0 + sin(a) * 15.0])
			hosel = Vector2(48, 70)
		"putter_wing":
			head = [[6, 76], [54, 76], [56, 84], [50, 84], [52, 96], [40, 96], [38, 86], [22, 86], [20, 96], [8, 96], [10, 84], [4, 84]]
			hosel = Vector2(50, 68)
		"putter_robot":
			head = [[8, 74], [54, 74], [56, 92], [6, 92]]
			hosel = Vector2(50, 66)
		_:
			head = [[6, 72], [48, 67], [56, 74], [58, 92], [14, 94], [6, 86]]
	if show_shaft:
		var top := _p(93, 4)
		var grip_end := _p(82, 22)
		var shaft_col := Color(INK, 0.28) if ghost else Color(0.72, 0.72, 0.7)
		draw_line(_p(hosel.x, hosel.y), top, shaft_col, maxf(2.0, size.x * 0.022), true)
		draw_line(grip_end, top, Color(INK, 0.3) if ghost else Color(0.16, 0.16, 0.18), maxf(4.0, size.x * 0.045), true)
	var pts := _poly(head)
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline, 1.5, true)
	if ghost:
		return
	# Accents: what makes each shape recognisable at a glance.
	match silhouette:
		"driver", "wood", "hybrid":
			draw_line(_p(14, 76), _p(44, 74), Color(acc, 0.9), 2.0, true)
			draw_circle(_p(40, 84), size.x * 0.02, Color(acc, 0.8))
		"driver_grenade":
			for gx in [16, 24, 32, 40, 48]:
				draw_line(_p(gx, 68), _p(gx, 92), Color(acc, 0.55), 1.2, true)
			for gy in [72, 78, 84, 90]:
				draw_line(_p(8, gy), _p(56, gy), Color(acc, 0.55), 1.2, true)
			draw_arc(_p(60, 62), size.x * 0.05, 0.0, TAU, 16, acc, 2.0, true)
		"driver_persimmon", "wood_persimmon":
			for i in range(3):
				draw_arc(_p(32, 80), size.x * (0.08 + 0.05 * i), PI * 1.1, PI * 1.9, 12, Color(acc, 0.45), 1.0, true)
			draw_rect(Rect2(_p(18, 90), Vector2(size.x * 0.22, size.y * 0.035)), Color(0.85, 0.7, 0.35, 0.9))
		"hybrid_iron":
			draw_line(_p(12, 78), _p(50, 76), Color(acc, 0.8), 1.5, true)
			draw_line(_p(12, 84), _p(50, 82), Color(acc, 0.5), 1.0, true)
		"iron", "iron_blade":
			for gy in [76, 80, 84, 88]:
				draw_line(_p(12, gy), _p(50, gy - 1), Color(acc, 0.55), 1.0, true)
			if silhouette == "iron":
				draw_rect(Rect2(_p(16, 78), Vector2(size.x * 0.3, size.y * 0.1)), Color(acc, 0.25))
		"wedge":
			for gy in [72, 76, 80, 84, 88]:
				draw_line(_p(14, gy), _p(52, gy - 1), Color(acc, 0.6), 1.0, true)
		"putter_blade":
			draw_line(_p(28, 79), _p(28, 89), Color(acc, 0.8), 1.5, true)
		"putter_flange":
			draw_line(_p(8, 80), _p(54, 80), Color(acc, 0.7), 1.2, true)
			draw_circle(_p(30, 90), size.x * 0.018, Color(acc, 0.9))
		"putter_heeltoe":
			draw_line(_p(30, 80), _p(30, 89), Color(acc, 0.9), 1.5, true)
			draw_line(_p(6, 89), _p(58, 89), Color(acc, 0.5), 1.0, true)
		"putter_mallet":
			for gx in [24, 30, 36]:
				draw_line(_p(gx, 80), _p(gx, 94), Color(acc, 0.9), 2.0, true)
		"putter_wing":
			draw_line(_p(30, 78), _p(30, 95), Color(acc, 0.95), 2.2, true)
			draw_line(_p(8, 77), _p(54, 77), Color(1, 1, 1, 0.35), 1.0, true)
		"putter_tour":
			draw_line(_p(8, 84), _p(54, 84), Color(acc, 0.95), 1.8, true)
			draw_circle(_p(50, 87), size.x * 0.014, Color(acc, 0.9))
		"putter_newport":
			draw_line(_p(8, 81), _p(54, 81), Color(0.55, 0.55, 0.58, 0.9), 1.0, true)
			for gx in [22, 30, 38]:
				draw_circle(_p(gx, 86), size.x * 0.02, acc)
			draw_line(_p(30, 78), _p(30, 84), Color(0.3, 0.3, 0.32, 0.7), 1.5, true)
		"putter_robot":
			draw_circle(_p(22, 83), size.x * 0.05, Color(acc, 0.95))
			draw_circle(_p(22, 83), size.x * 0.02, INK)
			draw_line(_p(44, 74), _p(48, 60), Color(acc, 0.9), 1.5, true)
			draw_circle(_p(48, 60), size.x * 0.02, acc)
	# Wear: scratches and a dull patch scale with how worn the club is.
	if wear > 0.25:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(silhouette) + int(condition * 1000.0)
		var n := int(round(lerpf(0.0, 9.0, (wear - 0.25) / 0.75)))
		for i in range(n):
			var a := _p(rng.randf_range(10, 52), rng.randf_range(72, 92))
			var b := a + Vector2(rng.randf_range(-8, 8), rng.randf_range(-3, 3)) * (size.x / 100.0)
			draw_line(a, b, Color(0.1, 0.08, 0.05, 0.45), 1.0, true)
		if wear > 0.6:
			draw_circle(_p(40, 86), size.x * 0.06, Color(0.35, 0.25, 0.12, 0.28))
