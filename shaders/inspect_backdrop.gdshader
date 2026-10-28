shader_type canvas_item;
// Full-screen Inspect backdrop (hub_menu.gd _show_inspect): a dark studio lit in the club's
// rarity colour -- a soft halo behind the club, a spotlight pool on the floor beneath it, a
// faint floor horizon, slow light shafts from above, drifting dust motes, a vignette and a
// little grain so the gradients never band.

uniform vec4 accent : source_color = vec4(0.85, 0.55, 0.17, 1.0);
uniform vec2 focus = vec2(0.32, 0.47);  // halo centre in UV (the middle of the 3D stage)
uniform float aspect = 1.7778;          // rect width / height, keeps the halo round
uniform float glow = 0.6;               // halo strength (rarer clubs glow more)
uniform float floor_amount = 1.0;       // 0 drops the floor, horizon and spotlight pool (hub shell)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One layer of motes drifting upward: a sparse dot in some cells of a scrolling grid.
float motes(vec2 uv, float cells, float speed, float seed) {
	vec2 g = vec2(uv.x * aspect, uv.y) * cells;
	g.y += TIME * speed;
	g.x += sin(g.y * 0.35 + TIME * 0.2 + seed) * 0.35;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(cell + seed);
	vec2 off = vec2(hash(cell + 1.3 + seed), hash(cell + 7.1 + seed)) - 0.5;
	float d = length(f - off * 0.6);
	float twinkle = 0.55 + 0.45 * sin(TIME * (0.8 + h * 2.0) + h * 40.0);
	return smoothstep(0.09, 0.0, d) * step(0.86, h) * twinkle;
}

void fragment() {
	vec2 uv = UV;
	vec3 tint = accent.rgb;
	vec3 light = mix(tint, vec3(1.0), 0.6);
	vec2 p = vec2((uv.x - focus.x) * aspect, uv.y - focus.y);
	float r = length(p);

	vec3 col = mix(vec3(0.035, 0.060, 0.052), vec3(0.014, 0.024, 0.021), smoothstep(0.0, 1.0, uv.y));

	// halo: a tight core plus a wide wash
	float halo = exp(-r * r * 6.0) * glow + exp(-r * r * 1.2) * glow * 0.32;
	col += tint * halo * 0.5;

	// floor: slightly darker below a soft horizon, with a lit pool under the club
	float floor_y = focus.y + 0.31;
	float below = smoothstep(floor_y - 0.01, floor_y + 0.06, uv.y);
	col *= mix(1.0, 0.72, below * floor_amount);
	float fade_x = 1.0 - smoothstep(0.0, 0.95, abs(p.x));
	col += light * exp(-pow((uv.y - floor_y) * 55.0, 2.0)) * 0.07 * fade_x * floor_amount;
	vec2 fp = vec2(p.x * 0.75, (uv.y - floor_y - 0.07) * 4.2);
	col += light * exp(-dot(fp, fp) * 4.0) * 0.11 * below * floor_amount;

	// slanted light shafts from the top, drifting very slowly
	float sx = p.x + uv.y * 0.32;
	float shafts = pow(0.5 + 0.5 * sin(sx * 8.0 + TIME * 0.12), 14.0);
	shafts += pow(0.5 + 0.5 * sin(sx * 4.7 - TIME * 0.09 + 1.7), 18.0) * 0.8;
	shafts *= (1.0 - smoothstep(0.0, 0.85, uv.y)) * (1.0 - smoothstep(0.1, 1.1, abs(p.x)));
	col += light * shafts * 0.045;

	// dust motes, two depths, brightest near the light
	float near_light = 0.35 + 0.65 * exp(-r * r * 1.6);
	col += light * (motes(uv, 26.0, 0.30, 0.0) * 0.22 + motes(uv, 14.0, 0.18, 3.7) * 0.32) * near_light;

	// vignette + grain
	vec2 v = (uv - vec2(0.5, 0.48)) * vec2(1.0, 1.15);
	col *= clamp(1.0 - dot(v, v) * 1.05, 0.0, 1.0);
	col += (hash(uv * 977.0 + fract(TIME * 7.0)) - 0.5) * (2.5 / 255.0);
	COLOR = vec4(col, 1.0);
}
