// Nature pack solid surfaces (bark, stone, wood): vertex colour albedo, back-face
// culled. `max_dist` as in nature_leaves.gdshader.
//
// Bark: the pack paints bark as one flat vertex colour (the pines' reads salmon in sun)
// and its bark UVs don't follow the trunk, so the bark is drawn here in world space,
// projected onto the trunk's sides: a darker brown, with blocky plates split by deep
// cracks up close, long vertical furrows at mid range and broad streaks further out, each
// layer fading to its average before it is small enough to shimmer. The relief also bends
// the normal (surface-gradient bump, no tangents needed). It lands where the vertex colour
// is the pack's dark bark brown. River birch (the pack's pale grey-beige bark, which read as
// a white trunk) gets its own bark instead: cinnamon outer bark peeling in papery horizontal
// sheets to a cream inner layer, dark curled edges and short dark lenticel dashes. Cut log
// ends and mushrooms are warmer or paler still and keep their own colour.
shader_type spatial;
render_mode cull_back, world_vertex_coords;

uniform float max_dist = 0.0;
uniform float min_dist = 0.0;
uniform vec3 bark_color : source_color = vec3(0.149, 0.102, 0.027);  // #261a07, the user's bark brown
uniform float bark_darken = 1.0;     // how far toward bark_color (0 = the pack's own colour)
uniform float bark_scale = 1.0;      // pattern size (bigger = larger plates)
uniform float bark_contrast = 0.8;   // how dark the cracks are next to the plate faces
uniform float bark_bump = 1.0;       // relief strength (1 = cracks about 2 cm deep)
uniform vec3 birch_outer : source_color = vec3(0.58, 0.39, 0.28);  // salmon-brown outer bark
uniform vec3 birch_inner : source_color = vec3(0.74, 0.60, 0.46);  // light tan where it has peeled
uniform vec3 birch_edge : source_color = vec3(0.43, 0.27, 0.20);   // curled edges, lenticels

varying vec3 world_pos;
varying vec3 world_nrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Plates: 0 on a crack between cells, rising to 1 on a plate face (F2 - F1 of a jittered grid).
float plates(vec2 p, float crack) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			float d = length(g + hash22(i + g) * 0.8 + 0.1 - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return smoothstep(0.0, crack, d2 - d1);
}

// Relief layers for a side projection, p.x around the trunk and p.y up it (metres):
// x = plates (~9 cm x 30 cm, ragged edges), y = long furrows (~25 cm x 1 m), z = broad streaks.
vec3 bark_layers(vec2 p, float fine_w, float mid_w) {
	p /= bark_scale;
	float wander = (vnoise(vec2(p.x * 3.0, p.y * 1.2)) - 0.5) * 2.0;
	float fine = 0.85;
	if (fine_w > 0.001) {
		vec2 q = vec2(p.x * 11.0 + wander, p.y * 3.2);
		q += (vec2(vnoise(p * 40.0), vnoise(p * 40.0 + 7.3)) - 0.5) * 0.3;  // ragged plate edges
		fine = plates(q, 0.38) * (0.78 + 0.22 * vnoise(p * vec2(70.0, 30.0)));
	}
	float mid = 0.8;
	if (mid_w > 0.001) {
		mid = plates(vec2(p.x * 4.0 + wander * 0.4, p.y * 1.0), 0.3);
	}
	return vec3(fine, mid, vnoise(vec2(p.x * 2.5, p.y * 0.35)));
}

// River birch, for a side projection (p.x around the trunk, p.y up it, metres): rgb is the
// albedo, a the relief (1 = outer bark). `fine_w` fades the small lenticel dashes.
vec4 birch_bark(vec2 p, float fine_w) {
	p /= bark_scale;
	vec2 q = vec2(p.x * 1.6 + vnoise(p * vec2(3.0, 10.0)) * 0.8, p.y * 7.0);
	float sheet = vnoise(q) * 0.65 + vnoise(q * 2.3 + 11.0) * 0.35;
	float peeled = smoothstep(0.6, 0.64, sheet);  // inner layer showing
	float curl = smoothstep(0.54, 0.6, sheet) * (1.0 - peeled);  // the lifted edge around it
	vec3 col = mix(birch_outer, birch_inner, peeled);
	col = mix(col, birch_edge, curl * 0.75);
	float r = vnoise(vec2(p.x * 6.0, p.y * 55.0));
	float dash = (1.0 - smoothstep(0.0, 0.05, abs(r - 0.5))) * smoothstep(0.55, 0.7, vnoise(p * 9.0)) * fine_w;
	col = mix(col, birch_edge * 0.6, dash);
	return vec4(col, 1.0 - peeled * 0.35 - curl * 0.25 - dash * 0.2);
}

void vertex() {
	float cam_dist = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	if ((max_dist > 0.0 && cam_dist > max_dist) || cam_dist < min_dist) {
		VERTEX = vec3(0.0);
	}
	world_pos = VERTEX;
	world_nrm = NORMAL;
}

void fragment() {
	float lum = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float warmth = COLOR.r - COLOR.b;
	float dark_bark = smoothstep(0.03, 0.07, warmth) * (1.0 - smoothstep(0.28, 0.4, lum));
	// birch: pale and only slightly warm; mushrooms (whiter) and cut wood (warmer) fall outside
	float birch = smoothstep(0.05, 0.08, warmth) * (1.0 - smoothstep(0.17, 0.22, warmth)) * smoothstep(0.28, 0.34, lum) * (1.0 - smoothstep(0.68, 0.75, lum));
	float bark = max(dark_bark, birch);
	vec3 base = mix(COLOR.rgb * 0.60, bark_color, bark_darken * dark_bark);
	base = mix(base, mix(birch_outer, birch_inner, 0.15), birch);  // birch's average tone
	ALBEDO = base;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	float px = max(length(dpdx), length(dpdy));  // metres per pixel
	// each layer shows only while its cells span a few pixels
	float fine_w = bark * (1.0 - smoothstep(0.012, 0.025, px));
	float mid_w = bark * (1.0 - smoothstep(0.04, 0.08, px));
	float far_w = bark * (1.0 - smoothstep(0.12, 0.25, px));
	vec3 n = normalize(world_nrm);
	float h = 1.0;
	if (far_w > 0.001) {
		vec3 w = pow(abs(n), vec3(4.0));
		w /= max(w.x + w.y + w.z, 1e-4);
		if (birch > 0.5) {
			vec4 b = birch_bark(world_pos.zy, fine_w) * w.x + birch_bark(world_pos.xy, fine_w) * w.z + vec4(base, 0.9) * w.y;
			h = b.a;
			ALBEDO = mix(base, b.rgb, far_w);
			ROUGHNESS = mix(0.92, mix(0.85, 0.95, h), far_w);
		} else {
			vec3 l = bark_layers(world_pos.zy, fine_w, mid_w) * w.x + bark_layers(world_pos.xy, fine_w, mid_w) * w.z + vec3(0.85, 0.8, 0.5) * w.y;
			// faded layers fall back to their average, so the trunk's overall tone stays put
			float fine = mix(0.85, l.x, fine_w);
			float mid = mix(0.8, l.y, mid_w);
			h = fine * (0.55 + 0.45 * mid);
			vec3 c = base * (0.8 + 0.4 * l.z * far_w + 0.2 * (1.0 - far_w));
			c *= mix(1.0 - bark_contrast, 1.15, h) / mix(1.0 - bark_contrast, 1.15, 0.85 * (0.55 + 0.45 * 0.8));
			ALBEDO = mix(base, c, far_w);
			ROUGHNESS = mix(0.92, mix(0.98, 0.84, h), far_w);
		}
	}
	// Bump from the relief. The derivatives stay outside the branches above so they're
	// always defined.
	float hb = (h - 1.0) * 0.02 * bark_bump * max(fine_w, mid_w * 0.6);
	float dhdx = dFdx(hb);
	float dhdy = dFdy(hb);
	if (mid_w > 0.001) {
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(abs(det) * n - grad), 0.0)).xyz);
	}
}
