class_name GolfLook
extends RefCounted
## The course's camera look ("broadcast" grade): tonemapping, contact shadows (SSAO), soft
## bloom, a gentle colour grade, aerial haze and sun shadows. One place for every
## post-processing number so the course, the start menu and the course editor share it.
##
## GOLF_LOOK=classic restores the old flat look (Filmic, no AO/glow/grade) for comparison.

## Every tunable, by name. `apply()` takes an optional dictionary of overrides (used by
## tests/screenshot_look.gd to compare variants from one course load).
const DEFAULTS := {
	"tonemap": "agx",
	"exposure": 1.0,
	"agx_white": 6.0,
	"agx_contrast": 1.3,
	"saturation": 1.12,
	"contrast": 1.02,
	"brightness": 1.0,
	"ssao_radius": 1.6,
	"ssao_intensity": 1.6,
	"ssao_power": 1.4,
	"ssil": false,
	"glow_intensity": 0.55,
	"glow_bloom": 0.03,
	"glow_threshold": 1.05,
	"fog_density": 0.0004,
	"fog_aerial": 0.35,
	"fog_sun_scatter": 0.18,
	"fog_color": Color(0.70, 0.79, 0.90),
	"sun_energy": 1.55,
	"sun_color": Color(1.0, 0.955, 0.88),
	"sun_pitch": -28.0,
	"sun_yaw": 35.0,
	"shadow_distance": 120.0,
	"ambient_energy": 0.75,
	"sky_contribution": 0.45,
	"lut": true,
}


static func classic() -> bool:
	return OS.get_environment("GOLF_LOOK") == "classic"


static func apply(e: Environment, sun: DirectionalLight3D = null, overrides: Dictionary = {}) -> void:
	var v := DEFAULTS.duplicate()
	v.merge(overrides, true)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = v["sky_contribution"]
	e.ambient_light_energy = v["ambient_energy"]
	# AgX keeps bright sand, white balls and the sun disc from clipping flat, and rolls the
	# saturated turf greens off the way a camera does.
	e.tonemap_mode = {"agx": Environment.TONE_MAPPER_AGX, "aces": Environment.TONE_MAPPER_ACES, "filmic": Environment.TONE_MAPPER_FILMIC}.get(v["tonemap"], Environment.TONE_MAPPER_AGX)
	e.tonemap_exposure = v["exposure"]
	e.tonemap_agx_white = v["agx_white"]
	e.tonemap_agx_contrast = v["agx_contrast"]
	# Contact shadows: under the golfer's feet, the tee markers, along tree bases and
	# bunker lips. Light-affect stays 0 so open turf in full sun is not dirtied.
	e.ssao_enabled = true
	e.ssao_radius = v["ssao_radius"]
	e.ssao_intensity = v["ssao_intensity"]
	e.ssao_power = v["ssao_power"]
	e.ssao_detail = 0.5
	e.ssao_horizon = 0.06
	e.ssao_sharpness = 0.98
	e.ssao_light_affect = 0.0
	e.ssao_ao_channel_affect = 0.0
	e.ssil_enabled = v["ssil"]
	# Soft bloom on the sun, sky and specular glints only (high threshold).
	e.glow_enabled = true
	e.glow_normalized = true
	for i in range(1, 8):
		e.set("glow_levels/%d" % i, 0.0)
	e.set("glow_levels/3", 0.6)
	e.set("glow_levels/4", 1.0)
	e.set("glow_levels/5", 0.8)
	e.set("glow_levels/6", 0.4)
	e.glow_intensity = v["glow_intensity"]
	e.glow_strength = 1.0
	e.glow_bloom = v["glow_bloom"]
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.glow_hdr_threshold = v["glow_threshold"]
	e.glow_hdr_scale = 2.0
	# Grade: pull the cartoon lime out of the turf, a touch more contrast.
	e.adjustment_enabled = true
	e.adjustment_saturation = v["saturation"]
	e.adjustment_contrast = v["contrast"]
	e.adjustment_color_correction = turf_lut() if v["lut"] else null
	e.adjustment_brightness = v["brightness"]
	# Aerial perspective: distant tree lines pick up the sky colour, so the course reads big.
	e.fog_enabled = OS.get_environment("GOLF_NOFOG") != "1"
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = v["fog_color"]
	e.fog_light_energy = 1.0
	e.fog_density = v["fog_density"]
	e.fog_aerial_perspective = v["fog_aerial"]
	e.fog_sun_scatter = v["fog_sun_scatter"]
	e.fog_sky_affect = 0.0
	if sun != null:
		sun.rotation_degrees = Vector3(v["sun_pitch"], v["sun_yaw"], 0.0)
		sun.light_energy = v["sun_energy"]
		sun.light_color = v["sun_color"]
		# Two cascades: the forest is drawn once per cascade, so more splits cost whole
		# forests of triangles (tests/perf_probe.gd). The first covers the golfer and the
		# ball crisply; the second carries tree shadows down the hole.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = v["shadow_distance"]
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_split_1 = 0.18
		sun.shadow_blur = 1.2
		sun.shadow_normal_bias = 1.2


static var _lut: ImageTexture3D


## Colour-grade LUT (sRGB in -> sRGB out, 32^3): pulls the yellow-lime turf greens toward a
## deeper, cooler green and eases their saturation (the cartoon-lime read), and gives sky
## blues a little more depth. Everything else passes through untouched.
static func turf_lut() -> ImageTexture3D:
	if _lut != null:
		return _lut
	const N := 32
	var layers: Array[Image] = []
	for b in range(N):
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for g in range(N):
			for r in range(N):
				var c := Color(r / float(N - 1), g / float(N - 1), b / float(N - 1))
				var h := c.h * 360.0
				var s := c.s
				var v := c.v
				# yellow-green .. green band, weighted by how saturated the colour is
				var turf := smoothstep(55.0, 75.0, h) * (1.0 - smoothstep(125.0, 150.0, h)) * smoothstep(0.15, 0.45, s)
				h += turf * 9.0
				s *= 1.0 - turf * 0.14
				v *= 1.0 - turf * 0.05
				var sky := smoothstep(190.0, 205.0, h) * (1.0 - smoothstep(235.0, 250.0, h))
				s = minf(s * (1.0 + sky * 0.1), 1.0)
				img.set_pixel(r, g, Color.from_hsv(fposmod(h, 360.0) / 360.0, s, v))
		layers.append(img)
	_lut = ImageTexture3D.new()
	_lut.create(Image.FORMAT_RGB8, N, N, N, false, layers)
	return _lut
