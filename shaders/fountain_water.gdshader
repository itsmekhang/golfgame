shader_type spatial;
// The clubhouse fountain's running water (FacilityBuilder._fountain_water): `fall` 0 for a pool's
// surface -- rings spreading out from where the water drops into it (its middle, or out at
// `ring_start` for a pool fed by a curtain round its edge) over a slow chop -- or 1 for a curtain
// of water falling over a bowl's lip, streaks running down it (UV.y 0 at the lip, 1 at its foot)
// and thinning to spray at its foot. Self-contained: its noise is made here, no textures.
render_mode cull_disabled, depth_draw_opaque;

uniform float fall = 0.0;
uniform vec4 deep : source_color = vec4(0.18, 0.36, 0.42, 0.9);
uniform vec4 foam : source_color = vec4(0.86, 0.93, 0.96, 1.0);
uniform float ring_start = 0.0;  // (pool: where its rings start out from, 0..1 of its radius)
uniform float speed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	if (fall < 0.5) {
		// UV: the disc's own, its middle at (0.5, 0.5)
		vec2 d = UV - vec2(0.5);
		float r = length(d) * 2.0;
		float from = abs(r - ring_start);
		float rings = sin(from * 38.0 - TIME * 4.0 * speed) * exp(-from * 3.2);
		float chop = noise(UV * 26.0 + vec2(TIME * 0.3, -TIME * 0.21)) - 0.5;
		vec2 slope = d / max(r, 0.001) * rings * 0.35 + vec2(chop, noise(UV * 31.0 - TIME * 0.27) - 0.5) * 0.25;
		NORMAL_MAP = normalize(vec3(slope * 0.5 + 0.5, 1.0));
		NORMAL_MAP_DEPTH = 0.6;
		float white = smoothstep(0.55, 1.0, rings * exp(-from * 2.0) + chop * 0.4);
		ALBEDO = mix(deep.rgb, foam.rgb, white * 0.7);
		ALPHA = mix(deep.a, 1.0, white);
		ROUGHNESS = 0.06;
		SPECULAR = 0.7;
	} else {
		// streaks of water running down the curtain, faster as it falls: long thin threads (noise
		// stretched down it), a clear sheet between them
		float y = UV.y;
		float run = y * (1.0 + y) * 1.4 - TIME * 1.6 * speed;
		float threads = noise(vec2(UV.x * 140.0, run * 2.2)) * 0.6 + noise(vec2(UV.x * 55.0 + 3.1, run * 0.9)) * 0.55;
		float sheet = smoothstep(0.45, 0.95, threads);
		ALBEDO = mix(deep.rgb * 1.5, foam.rgb, sheet * 0.85);
		// clear at the lip (a smooth sheet), breaking into threads lower down, gone into spray at its foot
		ALPHA = clamp(mix(0.32, 0.06, y) + sheet * mix(0.35, 0.7, y), 0.0, 0.85) * smoothstep(1.0, 0.85, y);
		ROUGHNESS = 0.1;
		SPECULAR = 0.6;
	}
}
