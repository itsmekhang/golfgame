shader_type spatial;
// Weathered ashlar for the stone footbridges (scripts/stone_bridge.gd). UV is in metres
// (along the bridge, height) so courses run level; UV2.y is the height above the arch soffit,
// which draws a ring of voussoirs round each opening. Stones vary in tone, joints are recessed
// (dark mortar + AO), and everything darkens and greens toward the waterline.
render_mode cull_disabled;

uniform vec3 stone_light : source_color = vec3(0.50, 0.49, 0.46);
uniform vec3 stone_dark : source_color = vec3(0.34, 0.33, 0.31);
uniform vec3 mortar : source_color = vec3(0.22, 0.21, 0.20);
uniform vec3 moss : source_color = vec3(0.22, 0.27, 0.15);
uniform float water_level = 0.0;
uniform float course_h = 0.32;    // stone course height (m)
uniform float block_w = 0.64;     // typical stone length (m)
uniform float ring_depth = 0.46;  // voussoir ring thickness round the arches (m)

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float row;
	vec2 f;
	vec2 cell;
	vec2 size;
	bool ring = UV2.x >= 0.0 && UV2.y >= 0.0 && UV2.y < ring_depth;
	if (ring) {
		// voussoirs: narrow wedge stones standing round the opening
		float bx = UV2.x / 0.36;
		cell = vec2(floor(bx), 91.0);
		f = vec2(fract(bx), UV2.y / ring_depth);
		size = vec2(0.36, ring_depth);
	} else {
		row = floor(uv.y / course_h);
		float off = hash(vec2(row, 3.1)) * block_w;
		float w = block_w * (0.8 + 0.4 * hash(vec2(row, 9.7)));
		float bx = (uv.x + off) / w;
		cell = vec2(floor(bx), row);
		f = vec2(fract(bx), fract(uv.y / course_h));
		size = vec2(w, course_h);
	}
	vec2 edge = min(f, 1.0 - f) * size;  // metres to the nearest joint
	float joint = 1.0 - smoothstep(0.01, 0.028, min(edge.x, edge.y));
	float h = hash(cell);
	vec3 c = mix(stone_light, stone_dark, h);
	c *= 0.88 + 0.24 * hash(cell + 7.0);
	c *= 0.9 + 0.1 * noise(uv * 7.0 + cell * 3.0);
	if (ring) {
		c *= 0.93;
	}
	// rounded stone faces: a little darker toward each stone's edges
	float bevel = smoothstep(0.0, 0.07, min(edge.x, edge.y));
	c *= 0.82 + 0.18 * bevel;
	c = mix(c, mortar, joint);
	// waterline: wet and dark at the surface, mossy just above it
	float wet = 1.0 - smoothstep(water_level - 0.05, water_level + 0.45, world_pos.y);
	float mossy = (1.0 - smoothstep(water_level + 0.1, water_level + 1.3, world_pos.y)) * smoothstep(0.35, 0.75, noise(world_pos.xz * 1.7 + world_pos.y * 2.0));
	c = mix(c, moss, mossy * 0.55);
	c = mix(c, c * 0.42, wet);
	ALBEDO = c;
	ROUGHNESS = mix(0.92, 0.35, wet);
	SPECULAR = 0.3;
	AO = 1.0 - joint * 0.55 - (1.0 - bevel) * 0.15;
	AO_LIGHT_AFFECT = 0.4;
}
