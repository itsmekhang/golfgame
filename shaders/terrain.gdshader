shader_type spatial;
render_mode cull_back;

// Vertex color carries the surface tint (fairway/green/rough/bunker) for procedural
// courses. Scanned courses supply an orthophoto `albedo_map` covering `map_origin`..
// `map_origin + map_size` in world XZ, blended with the vertex tint by `albedo_mix`.
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_map : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform vec2 map_size = vec2(1.0);
uniform float albedo_mix = 0.0;
uniform float detail_scale = 0.9;
uniform float macro_scale = 0.02;
uniform float detail_strength = 0.18;
uniform float macro_strength = 0.10;
// Photo turf texture tiled in world space on the grass surfaces.
uniform sampler2D turf_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float turf_scale = 0.35;      // repeats per metre (rough/green tiling)
uniform float fairway_scale = 1.0;    // repeats per metre for the fairway PBR set specifically -- kept
                                       // separate so tightening its grain doesn't also retile rough/green
uniform float turf_strength = 0.85;   // 0 = tint only, 1 = full texture detail
uniform float turf_mean = 0.45;       // mean luminance of the texture (normalises brightness)
// Full PBR set for the mown fairway turf specifically (normal/roughness/AO), so it
// reads as a real bumpy grass surface under light instead of a flat photo decal.
uniform sampler2D turf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 1 m feature mask over the course bounds holding encoded signed distances
// (v = 0.5 - sd / 16): R sand, G green, B tee, A water bed.
uniform sampler2D feature_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(1.0);
// 2 m signed-distance texture: R turf (fairway/tee/green), G green. Same encoding.
uniform sampler2D turf_sdf : hint_default_black, filter_linear, repeat_disable;
uniform vec2 sdf_size = vec2(1.0);
uniform float edge_soft = 0.7;      // metres of anti-aliasing across every outline
uniform float first_cut_width = 2.5;
uniform float fringe_width = 2.5;
uniform vec3 sand_color : source_color = vec3(0.90, 0.83, 0.62);
uniform vec3 sand_color2 : source_color = vec3(0.84, 0.76, 0.54);
uniform vec3 green_color_a : source_color = vec3(0.70, 0.95, 0.46);
uniform vec3 green_color_b : source_color = vec3(0.62, 0.88, 0.40);
uniform vec3 fringe_color : source_color = vec3(0.48, 0.78, 0.30);
uniform vec3 waterbed_color : source_color = vec3(0.30, 0.36, 0.26);
uniform float green_check = 2.0;
uniform sampler2D green_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rough_mean = 0.2;
uniform float green_mean = 0.7;
uniform sampler2D sand_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sand_scale = 0.15;  // repeats per metre
uniform float sand_mean = 1.0;  // safe no-op with the default white texture until a real one is set
// CPU-painted trail mask (see scripts/sand_trail.gd): 1 = untouched, darker where the ball
// has rolled. Always gated by mask.r (sand coverage) below, so it can never show off-sand.
uniform sampler2D sand_trail : hint_default_white, filter_linear, repeat_disable;
uniform vec2 sand_trail_origin = vec2(0.0);
uniform vec2 sand_trail_size = vec2(1.0);
// Pine-straw beds: coverage mask painted under the tree lines (CourseLayout.paint_straw),
// same origin as feature_mask. Only ever shows on rough, never on mown turf/sand/water.
uniform sampler2D straw_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 straw_size = vec2(1.0);
uniform sampler2D straw_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float straw_scale = 0.5;   // repeats per metre
uniform float straw_mean = 1.0;
uniform vec3 straw_color : source_color = vec3(0.50, 0.34, 0.19);

varying vec3 world_pos;
varying vec4 vcol;

float decode_sd(float v) {
	return (0.5 - v) * 16.0;
}

// coverage of an outline: 1 inside, 0 outside, anti-aliased over edge_soft metres
float cov(float sd) {
	return 1.0 - smoothstep(-edge_soft * 0.5, edge_soft * 0.5, sd);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
}

void fragment() {
	float d = texture(detail_noise, world_pos.xz * detail_scale).r - 0.5;
	float m = texture(macro_noise, world_pos.xz * macro_scale).r - 0.5;
	vec3 tint = vcol.rgb;
	vec4 mask_raw = texture(feature_mask, (world_pos.xz - mask_origin) / mask_size);
	vec2 sdf_raw = texture(turf_sdf, (world_pos.xz - mask_origin) / sdf_size).rg;
	float sd_sand = decode_sd(mask_raw.r);
	float sd_green = min(decode_sd(mask_raw.g), decode_sd(sdf_raw.g));
	float sd_water = decode_sd(mask_raw.a);
	float sd_turf = min(decode_sd(sdf_raw.r), decode_sd(mask_raw.b));
	float green_w = cov(sd_green);
	float fringe_w = cov(sd_green - fringe_width) * (1.0 - green_w);
	float turf_w = cov(sd_turf);                       // mown turf (fairway / tee / green)
	float first_cut_w = cov(sd_turf - first_cut_width) * (1.0 - turf_w);
	float rough_w = 1.0 - turf_w - first_cut_w * 0.5;  // first cut is half way to rough
	rough_w = max(rough_w, 0.0);
	vec4 mask = vec4(cov(sd_sand), green_w, fringe_w, cov(sd_water));
	vec3 green_tint = green_color_a;
	tint = mix(tint, fringe_color, fringe_w);
	tint = mix(tint, green_tint, mask.g);
	vec3 col = tint * (1.0 + d * detail_strength * 2.0 + m * macro_strength * 2.0);
	vec3 turf = texture(turf_texture, world_pos.xz * fairway_scale).rgb / max(turf_mean, 0.05);
	vec3 rough_t = texture(rough_texture, world_pos.xz * turf_scale).rgb / max(rough_mean, 0.05);
	vec3 green_t = texture(green_texture, world_pos.xz * turf_scale * 2.0).rgb / max(green_mean, 0.05);
	// rough weight from the turf distance field (1 deep in the rough, 0 on mown turf)
	vec3 grass_tex = mix(turf, rough_t, rough_w);
	grass_tex = mix(grass_tex, green_t, mask.g);
	vec3 textured = tint * grass_tex;
	col = mix(col, textured * (1.0 + m * macro_strength), turf_strength);
	// pine straw under the trees: the mask's soft disc edges plus detail noise break
	// the outline up so beds read as raked needles thinning into the rough
	float straw_raw = texture(straw_mask, (world_pos.xz - mask_origin) / straw_size).r;
	float straw_w = smoothstep(0.30, 0.65, straw_raw + d * 0.35) * rough_w * (1.0 - first_cut_w);
	vec3 straw_tex = texture(straw_texture, world_pos.xz * straw_scale).rgb / max(straw_mean, 0.05);
	vec3 straw = straw_color * straw_tex * (1.0 + m * macro_strength * 2.0);
	col = mix(col, straw, straw_w);
	// sand and water bed from the mask (soft, polygon-accurate edges)
	vec3 sand_tex = texture(sand_texture, world_pos.xz * sand_scale).rgb / max(sand_mean, 0.05);
	vec3 sand = mix(sand_color, sand_color2, d + 0.5) * sand_tex * (1.0 + m * macro_strength);
	col = mix(col, sand, mask.r);
	col = mix(col, waterbed_color * (1.0 + d * 0.3), mask.a);
	float trail = texture(sand_trail, (world_pos.xz - sand_trail_origin) / sand_trail_size).r;
	col = mix(col, col * trail, mask.r);
	ALBEDO = col;
	// Pure mown fairway only (not rough/green/fringe/sand/water): where the PBR normal
	// map, roughness and AO apply. NORMAL_MAP_DEPTH fades it to flat elsewhere so the
	// blend at every edge stays soft, matching the colour blend above.
	float fairway_w = turf_strength * (1.0 - rough_w) * (1.0 - mask.g) * (1.0 - fringe_w) * (1.0 - mask.r) * (1.0 - mask.a) * (1.0 - straw_w);
	vec3 turf_n = texture(turf_normal, world_pos.xz * fairway_scale).rgb;
	float turf_rough_v = texture(turf_roughness, world_pos.xz * fairway_scale).r;
	float turf_ao_v = texture(turf_ao, world_pos.xz * fairway_scale).r;
	NORMAL_MAP = turf_n;
	NORMAL_MAP_DEPTH = fairway_w;
	ROUGHNESS = mix(mix(1.0, 0.85, mask.r), turf_rough_v, fairway_w);
	AO = mix(1.0, turf_ao_v, fairway_w);
	SPECULAR = mix(0.04, 0.15, mask.r);
}
