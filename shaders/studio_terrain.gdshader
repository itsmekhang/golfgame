// Course Studio terrain: one grid mesh displaced by the painted height field, surfaces blended
// from the two splat layers (PaintedCourse: A = fairway/green/tee/bunker, B = water/woods),
// bunkers and water shown dug in, and the brush ring drawn on the ground.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D splat_a : filter_linear, repeat_disable;
uniform sampler2D splat_b : filter_linear, repeat_disable;
uniform vec2 canvas_origin = vec2(-300.0);
uniform vec2 canvas_size = vec2(600.0);
uniform float texel = 1.0;

uniform sampler2D fairway_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D green_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D straw_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 fairway_a : source_color = vec3(0.34, 0.47, 0.14);
uniform vec3 fairway_b : source_color = vec3(0.30, 0.43, 0.12);
uniform vec3 green_a : source_color = vec3(0.45, 0.56, 0.22);
uniform vec3 green_b : source_color = vec3(0.42, 0.53, 0.20);
// The rough: one even colour, the game's dark rough green (TerrainBuilder.ROUGH_COLOR), carrying
// only the dense grass photo's fine grain (its luminance over rough_lum, its mean).
uniform vec3 rough_col : source_color = vec3(0.02, 0.231, 0.141);
uniform float rough_lum = 0.246;
uniform float rough_tile = 2.0;  // metres per repeat of rough_tex
uniform vec3 sand_col : source_color = vec3(0.86, 0.84, 0.76);
uniform vec3 water_deep : source_color = vec3(0.06, 0.20, 0.24);
uniform vec3 water_shallow : source_color = vec3(0.16, 0.36, 0.36);
uniform vec3 woods_floor : source_color = vec3(0.16, 0.17, 0.07);
uniform float stripe_width = 5.0;
uniform vec2 stripe_dir = vec2(0.0, 1.0);

uniform vec3 brush_pos = vec3(0.0, -1000.0, 0.0);
uniform float brush_radius = 10.0;
uniform float brush_hardness = 0.5;
uniform vec4 brush_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform bool brush_square = false;           // square stamp (tee boxes), squared to brush_dir
uniform vec2 brush_dir = vec2(0.0, -1.0);
uniform vec2 brush_box = vec2(0.0);          // with brush_square: a box this half-size (across, along brush_dir) instead (a facility's site)
uniform bool show_grid = false;

varying vec3 world_pos;
varying float bunker_cov;
varying float water_cov;

vec2 canvas_uv(vec2 xz) {
	return (xz - canvas_origin) / canvas_size;
}

float height_at(vec2 xz) {
	return texture(height_tex, canvas_uv(xz)).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = canvas_uv(w.xz);
	float h = texture(height_tex, uv).r;
	vec4 a = texture(splat_a, uv);
	vec4 b = texture(splat_b, uv);
	bunker_cov = a.a;
	water_cov = b.r;
	// preview the dig the game will do: bunkers ~0.6 m, water ~1.4 m
	h -= smoothstep(0.3, 0.9, a.a) * 0.6 + smoothstep(0.2, 0.9, b.r) * 1.4;
	VERTEX.y = h;
	float e = texel;
	float hl = height_at(w.xz - vec2(e, 0.0));
	float hr = height_at(w.xz + vec2(e, 0.0));
	float hd = height_at(w.xz - vec2(0.0, e));
	float hu = height_at(w.xz + vec2(0.0, e));
	NORMAL = normalize(vec3(hl - hr, 2.0 * e, hd - hu));
	world_pos = vec3(w.x, h, w.z);
}

float edge(float cov) {
	float w = fwidth(cov) * 1.2 + 0.02;
	return smoothstep(0.5 - w, 0.5 + w, cov);
}

void fragment() {
	vec2 uv = canvas_uv(world_pos.xz);
	vec4 a = texture(splat_a, uv);
	vec4 b = texture(splat_b, uv);
	vec2 tuv = world_pos.xz * 0.25;
	const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
	float grain = dot(texture(rough_tex, world_pos.xz / rough_tile).rgb, LUM) / rough_lum;
	vec3 rough = rough_col * mix(1.0, grain, 0.6);
	vec3 col = rough;
	// woods floor: pine straw under the trees
	col = mix(col, woods_floor * (texture(straw_tex, tuv).rgb * 1.6), edge(b.g) * 0.7);
	float along = dot(world_pos.xz, normalize(stripe_dir));
	float stripe = step(0.5, fract(along / (stripe_width * 2.0)));
	vec3 fw = mix(fairway_a, fairway_b, stripe) * (texture(fairway_tex, tuv).rgb * 2.0);
	vec3 gr = mix(green_a, green_b, stripe) * (texture(green_tex, tuv * 2.0).rgb * 1.8);
	col = mix(col, fw, edge(a.r));
	col = mix(col, gr, edge(a.b));
	col = mix(col, gr * 1.03, edge(a.g));
	vec3 sand = sand_col * (0.85 + 0.3 * texture(sand_tex, tuv).r);
	col = mix(col, sand, edge(a.a));
	float rough_v = 0.92;
	float spec = 0.3;
	float wet = edge(b.r);
	if (wet > 0.0) {
		float depth = smoothstep(0.5, 1.0, b.r);
		vec3 water = mix(water_shallow, water_deep, depth);
		col = mix(col, water, wet);
		rough_v = mix(rough_v, 0.04, wet);
		spec = mix(spec, 0.6, wet);
	}
	// brush ring + soft fill
	float d = distance(world_pos.xz, brush_pos.xz);
	if (brush_square) {
		// square outline squared to the line of play (Chebyshev distance in that frame)
		vec2 o = world_pos.xz - brush_pos.xz;
		vec2 dir = normalize(brush_dir);
		vec2 across = vec2(-dir.y, dir.x);
		d = max(abs(dot(o, across)), abs(dot(o, dir)));
		if (brush_box.x > 0.0) {
			// the box's own outline: its signed distance, the edge at brush_radius
			vec2 q = abs(vec2(dot(o, across), dot(o, dir))) - brush_box;
			d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) + brush_radius;
		}
	}
	float px = fwidth(d) * 1.5;
	float reach = brush_box.x > 0.0 ? max(brush_box.x, brush_box.y) : brush_radius;
	float ring = 1.0 - smoothstep(0.0, px + 0.05 * reach * 0.02, abs(d - brush_radius));
	float inner = 1.0 - smoothstep(0.0, px, abs(d - brush_radius * brush_hardness));
	float fill = (1.0 - smoothstep(brush_radius * brush_hardness, brush_radius, d)) * 0.12;
	vec3 bc = brush_color.rgb;
	// a brush parked far below the ground (brush_pos.y; the Studio and Course Manager hide it so)
	// is hidden: the ring itself only measures across the ground
	float ba = brush_pos.y > -500.0 ? brush_color.a : 0.0;
	col = mix(col, bc, clamp(fill * ba, 0.0, 1.0));
	EMISSION = bc * (ring * 0.9 + inner * 0.25) * ba;
	if (show_grid) {
		vec2 g = abs(fract(world_pos.xz / 10.0 - 0.5) - 0.5) / fwidth(world_pos.xz / 10.0);
		float line = 1.0 - min(min(g.x, g.y), 1.0);
		col = mix(col, vec3(1.0), line * 0.08);
	}
	ALBEDO = col;
	ROUGHNESS = rough_v;
	SPECULAR = spec;
}
