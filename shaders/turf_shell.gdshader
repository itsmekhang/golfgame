// Turf shells: one slice of short grass drawn over the terrain tiles near the camera
// (TurfShells chains several of these on a distance-culled overlay of the terrain, each a
// little higher). Together they read as dense living turf instead of a painted floor: ~3 cm
// on fairways and tees, ~4.5 cm in the first cut, a 7 cm under-layer in the rough between
// the grass cards, nothing on greens, sand, water or pine straw.
//
// Colour comes from the lit terrain right behind each strand (the screen texture), so the
// blades carry the mowing stripes, the shadows and the exact turf colour; they only add
// root-to-tip shading and per-blade variation on top.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D turf_sdf : filter_linear, repeat_disable;   // CourseLayout.sdf_texture
uniform vec2 sdf_origin;
uniform vec2 sdf_size;
uniform sampler2D feature_mask : filter_linear, repeat_disable;  // CourseLayout.mask_texture
uniform vec2 mask_size;
uniform sampler2D straw_mask : filter_linear, repeat_disable;  // CourseLayout.straw_texture
uniform vec2 straw_size;
uniform float sdf_range = 8.0;
// The club's building plots (Course Manager): the turf grows on them but not through their
// paving, floors and beds. xy = centre (world XZ), zw = half size, in the plot's own frame
// turned by pad_rot; pad_mask holds each plot's paving mask in a square slot, top to bottom.
uniform int pad_count = 0;
uniform vec4 pads[4];
uniform float pad_rot[4];
uniform sampler2D pad_mask : filter_nearest, repeat_disable;
uniform float first_cut = 2.5;
uniform float fringe = 2.5;

uniform float shell_t = 0.5;        // this slice's height, 0..1 of max_h
uniform float max_h = 0.1;
uniform float fairway_h = 0.042;
uniform float fringe_h = 0.024;
uniform float cut_h = 0.065;
uniform float rough_h = 0.1;
uniform float strand_size = 0.022;  // metres between blades
uniform float near_full = 9.0;      // full strength inside this range
uniform float max_dist = 26.0;      // gone beyond this
uniform float root_dark = 0.5;
uniform float tip_bright = 1.25;

varying vec3 wpos;
varying float keep;

float decode(float e) {
	return (0.5 - e) * sdf_range * 2.0;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(w, CAMERA_POSITION_WORLD);
	keep = d < max_dist + 6.0 ? 1.0 : 0.0;
	if (keep < 0.5) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += NORMAL * (shell_t * max_h);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (keep < 0.999) {
		discard;
	}
	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(near_full, max_dist, dist);
	if (fade <= 0.0) {
		discard;
	}
	vec3 s = texture(turf_sdf, (wpos.xz - sdf_origin) / sdf_size).rgb;
	float turf_sd = decode(s.r);
	float green_sd = decode(s.g);
	float h;
	if (green_sd < 0.0) {
		discard;  // putting surface: smooth
	} else if (green_sd < fringe) {
		h = fringe_h;
	} else if (turf_sd < 0.0) {
		h = fairway_h;
	} else if (turf_sd < first_cut) {
		h = cut_h;
	} else {
		h = rough_h;
	}
	float z = shell_t * max_h;
	if (z > h) {
		discard;
	}
	for (int i = 0; i < pad_count; i++) {
		vec2 d = wpos.xz - pads[i].xy;
		float c = cos(pad_rot[i]);
		float sn = sin(pad_rot[i]);
		vec2 uv = (vec2(d.x * c - d.y * sn, d.x * sn + d.y * c) + pads[i].zw) / (2.0 * pads[i].zw);
		if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			int slot = textureSize(pad_mask, 0).x;
			if (texelFetch(pad_mask, ivec2(uv * float(slot)) + ivec2(0, i * slot), 0).r > 0.5) {
				discard;
			}
		}
	}
	vec4 m = texture(feature_mask, (wpos.xz - sdf_origin) / mask_size);
	if (m.r > 0.45 || m.a > 0.4) {
		discard;  // sand / water
	}
	if (texture(straw_mask, (wpos.xz - sdf_origin) / straw_size).r > 0.45) {
		discard;  // pine straw beds
	}
	// blades: one per cell, random height and lean, tapering to the tip
	vec2 g = wpos.xz / strand_size;
	vec2 cell = floor(g);
	float r1 = hash(cell);
	float r2 = hash(cell + 17.31);
	float r3 = hash(cell + 41.7);
	// clumps: the turf grows in patches a hand or two across, not as an even pile
	vec2 q = wpos.xz * 1.7;
	vec2 qi = floor(q);
	vec2 qf = fract(q);
	qf = qf * qf * (3.0 - 2.0 * qf);
	float clump = mix(mix(hash(qi), hash(qi + vec2(1, 0)), qf.x), mix(hash(qi + vec2(0, 1)), hash(qi + vec2(1, 1)), qf.x), qf.y);
	float blade_h = h * mix(0.5, 1.0, r1) * mix(0.65, 1.15, clump);
	float t = z / blade_h;
	if (t > 1.0) {
		discard;
	}
	vec2 lean = (vec2(r2, r3) - 0.5) * 0.5 * t;
	vec2 f = fract(g) - 0.5 - (vec2(r3, r1) - 0.5) * 0.4 - lean;
	float radius = 0.42 * (1.0 - t * 0.85);
	float dd = length(f);
	float aa = fwidth(dd) * 1.5;
	float cover = 1.0 - smoothstep(radius - aa, radius + aa, dd);
	if (cover <= 0.01) {
		discard;
	}
	vec3 base = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float shade = mix(root_dark, tip_bright, t) * (0.9 + 0.2 * r2);
	ALBEDO = base * shade;
	ALPHA = cover * fade;
}
