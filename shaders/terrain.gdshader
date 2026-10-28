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
uniform float turf_scale = 0.35;      // repeats per metre (green tiling only -- see rough_scale)
uniform float fairway_scale = 1.0;    // repeats per metre for the fairway PBR set specifically -- kept
                                       // separate so tightening its grain doesn't also retile rough/green
uniform float rough_scale = 1.0;      // repeats per metre for the rough's own photo grass set -- kept
                                       // separate from turf_scale so it doesn't also retile the green
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
// 2 m signed-distance texture: R turf, G green, B tree patches. Same encoding.
uniform sampler2D turf_sdf : hint_default_black, filter_linear, repeat_disable;
uniform vec2 sdf_size = vec2(1.0);
uniform float edge_soft = 2.0;      // metres of anti-aliasing across every outline -- testing
// Authored first-cut banks around hole 11's green, pond and creek.
uniform vec4 greenside_bank_rect = vec4(0.0);
uniform bool greenside_bank_enabled = false;
                                     // showed this alone barely affects the perceived "hard
                                     // edge" (the colour jump between zones is a bigger factor,
                                     // see ROUGH_TINT/ROUGH_COLOR in terrain_builder.gd), but a
                                     // moderate widening from the original 0.4 still helps
uniform float first_cut_width = 2.5;
uniform float fringe_width = 2.5;
// Fairway mowing stripes: bands stripe_width metres long down the hole (UV.x carries the
// distance along the hole). Alternate passes lay the grass toward the green and back
// toward the tee, and blades leaning away from you look lighter, so a band's shade
// depends on which way you look and swaps when you turn around (stripe_view). Looking
// straight down the lean doesn't show, so stripe_top keeps the bands from above.
uniform float stripe_width = 5.0;
uniform float stripe_view = 0.08;
uniform float stripe_top = 0.05;
uniform vec3 sand_color : source_color = vec3(0.90, 0.83, 0.62);
uniform vec3 sand_color2 : source_color = vec3(0.84, 0.76, 0.54);
uniform vec3 green_color_a : source_color = vec3(0.70, 0.95, 0.46);
uniform vec3 green_color_b : source_color = vec3(0.62, 0.88, 0.40);
uniform vec3 fringe_color : source_color = vec3(0.48, 0.78, 0.30);
uniform vec3 waterbed_color : source_color = vec3(0.30, 0.36, 0.26);
uniform float green_check = 2.0;
uniform sampler2D green_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Rough is several photo grass variants (a Texture2DArray layer per variant),
// blended by a large-scale noise field so different patches of rough naturally
// read as different grass instead of one texture repeating everywhere. Source
// albedo is preserved; rough_tint supplies the darker course greens.
uniform sampler2DArray rough_texture_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rough_normal_array : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rough_roughness_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray rough_ao_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rough_mean = 0.2;
uniform vec3 rough_tint : source_color = vec3(0.05388, 0.46005, 0.30597);
uniform vec3 first_cut_tint : source_color = vec3(0.42, 0.53, 0.28);
uniform vec3 fringe_turf_color : source_color = vec3(0.3702, 0.4877, 0.1869);  // fairway grass, slightly lighter
uniform sampler2D fringe_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D first_cut_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int rough_layer_count = 1;
uniform sampler2D rough_variant_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float rough_variant_scale = 0.025;  // world-space frequency of the variant patches
uniform float green_mean = 0.7;
uniform vec3 green_texture_average = vec3(0.5); // linear-light average, for tee shade matching
uniform sampler2D sand_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sand_scale = 0.15;  // repeats per metre
uniform float sand_mean = 1.0;  // safe no-op with the default white texture until a real one is set
// Sand relief and shading. Raked furrows (across sand_rake_dir, with a slow wobble and
// stronger/weaker passes) and fine grain bend the normal, so the sand reads as sand under
// the sun; the strip just inside the edge is darker where the turf lip shades the face.
uniform sampler2D sand_grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sand_grain_scale = 1.6;      // grain normal repeats per metre
uniform float sand_grain_strength = 0.6;   // slope added by the grain
uniform float sand_tone_strength = 0.8;    // how much of sand_texture's mottling shows in the colour
uniform vec2 sand_rake_dir = vec2(0.8, 0.6);  // direction the rake was pulled (world XZ)
uniform float sand_rake_spacing = 0.05;    // metres between furrows
uniform float sand_rake_strength = 0.35;   // peak furrow slope
uniform float sand_lip_width = 0.35;       // metres of contact shadow inside the edge
uniform float sand_lip_shade = 0.18;       // darkening right at the edge
// The terrain mesh (1 m) is too coarse for a bunker's steep face and turf lip, so the
// shading normal fakes them from the sand outline's gradient.
uniform float sand_face_width = 1.0;       // metres over which the sand climbs to the lip
uniform float sand_face_slope = 0.6;       // face steepness (tan of the angle, ~31 deg)
uniform float sand_face_occlusion = 0.12;  // sky light the lip blocks at the foot of the face
uniform float sand_lip_roll = 0.35;        // turf rolling over the lip just outside the sand
// Bright sand bounces light into its own shade; without it the shaded face is lit by the
// blue sky alone and turns navy. A little of the sand's own colour as emission fakes that.
uniform float sand_bounce = 0.06;
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
uniform vec3 straw_color : source_color = vec3(0.59, 0.53, 0.39);

varying vec3 world_pos;
varying vec4 vcol;
varying float along_m;

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
	along_m = UV.x;  // TerrainBuilder: metres along the hole
}

void fragment() {
	// Preserve fine turf at the ball, but let slopes read smoothly down the hole.
	float ground_detail = 1.0 - smoothstep(8.0, 65.0, distance(CAMERA_POSITION_WORLD, world_pos));
	float d = texture(detail_noise, world_pos.xz * detail_scale).r - 0.5;
	float m = texture(macro_noise, world_pos.xz * macro_scale).r - 0.5;
	vec3 tint = vcol.rgb;
	// CPU samples sit at grid points, while texture samples sit at texel centers.
	// Without the half-texel offset, sand moves 0.5 m and turf moves 1 m from its lie.
	vec2 feature_uv = (world_pos.xz - mask_origin) / mask_size + 0.5 / vec2(textureSize(feature_mask, 0));
	vec2 turf_uv = (world_pos.xz - mask_origin) / sdf_size + 0.5 / vec2(textureSize(turf_sdf, 0));
	vec4 mask_raw = texture(feature_mask, feature_uv);
	vec3 sdf_raw = texture(turf_sdf, turf_uv).rgb;
	float sd_sand = decode_sd(mask_raw.r);
	// A crisp cut lip is easier to judge beside the ball. Widen only as needed
	// for a screen pixel at distance, keeping the same 50% boundary as ball lies.
	float sand_edge = max(0.08, fwidth(sd_sand));
	float sd_green = min(decode_sd(mask_raw.g), decode_sd(sdf_raw.g));
	float sd_water = decode_sd(mask_raw.a);
	float sd_turf = min(decode_sd(sdf_raw.r), decode_sd(mask_raw.b));
	bool in_bank_region = greenside_bank_enabled && all(greaterThanEqual(world_pos.xz, greenside_bank_rect.xy)) && all(lessThanEqual(world_pos.xz, greenside_bank_rect.zw));
	float bank_grass_w = in_bank_region ? 1.0 - smoothstep(2.5, 3.0, sd_water) : 0.0;
	float green_w = cov(sd_green);
	bank_grass_w *= 1.0 - green_w;
	float fringe_w = cov(sd_green - fringe_width) * (1.0 - green_w);
	float turf_w = cov(sd_turf);                       // mown turf (fairway / tee / green)
	// Tree islands in the fairway (rough ring included) go straight from fairway to rough:
	// no first-cut band round them and no first-cut grass under their trees.
	float sd_tree_island = decode_sd(sdf_raw.b);
	float first_cut_w = cov(sd_turf - first_cut_width) * (1.0 - turf_w) * (1.0 - cov(sd_tree_island - edge_soft));
	first_cut_w = max(first_cut_w, bank_grass_w);
	float rough_w = 1.0 - turf_w - first_cut_w * 0.5;  // first cut is half way to rough
	rough_w = max(rough_w, 0.0);
	float sand_w = 1.0 - smoothstep(-sand_edge * 0.5, sand_edge * 0.5, sd_sand);
	float water_w = cov(sd_water);
	if (in_bank_region) {
		float water_edge = max(0.08, fwidth(sd_water));
		water_w = 1.0 - smoothstep(-water_edge * 0.5, water_edge * 0.5, sd_water);
	}
	vec4 mask = vec4(sand_w, green_w, fringe_w, water_w);
	vec3 green_tint = green_color_a;
	tint = mix(tint, fringe_color, fringe_w);
	tint = mix(tint, green_tint, mask.g);
	vec3 col = tint * (1.0 + d * detail_strength * 2.0 * ground_detail + m * macro_strength * 2.0);
	// Pick two adjacent rough-variant layers and a cross-fade factor from a single
	// large-scale noise sample -- organic patches of each variant, smooth transitions
	// only between neighbouring layers (never a hard jump across the whole set).
	float rough_layer_max = max(float(rough_layer_count) - 1.0, 0.0);
	float rough_idx_f = clamp(texture(rough_variant_noise, world_pos.xz * rough_variant_scale).r, 0.0, 1.0) * rough_layer_max;
	float rough_idx0 = floor(rough_idx_f);
	float rough_idx1 = min(rough_idx0 + 1.0, rough_layer_max);
	float rough_variant_blend = rough_idx_f - rough_idx0;
	vec2 rough_uv = world_pos.xz * rough_scale;
	vec3 rough_raw = mix(
		texture(rough_texture_array, vec3(rough_uv, rough_idx0)).rgb,
		texture(rough_texture_array, vec3(rough_uv, rough_idx1)).rgb,
		rough_variant_blend);

	vec3 turf = texture(turf_texture, world_pos.xz * fairway_scale).rgb / max(turf_mean, 0.05);
	vec3 rough_t = rough_raw / max(rough_mean, 0.05);
	vec3 green_t = texture(green_texture, world_pos.xz * turf_scale * 2.0).rgb / max(green_mean, 0.05);
	// rough weight from the turf distance field (1 deep in the rough, 0 on mown turf)
	vec3 grass_tex = mix(turf, rough_t, rough_w);
	grass_tex = mix(grass_tex, green_t, mask.g);
	vec3 textured = tint * grass_tex;
	col = mix(col, textured * (1.0 + m * macro_strength), turf_strength * mix(0.15, 1.0, ground_detail));
	// Preserve the supplied rough tile's dark green albedo instead of whitening it
	// through luminance normalization and a mostly untextured fairway tint.
	col = mix(col, rough_raw * rough_tint, rough_w);
	// Short grass from the new pack on tees, first cut and green surrounds.
	// Exact green/fairway interiors retain their existing texture path.
	float tee_w = cov(decode_sd(mask_raw.b)) * (1.0 - green_w);
	vec3 first_cut_grass = texture(first_cut_texture, world_pos.xz).rgb * first_cut_tint;
	col = mix(col, first_cut_grass, first_cut_w * (1.0 - green_w));
	// Fringe wins where the green surround meets the first-cut band.
	vec3 fringe_raw = texture(fringe_texture, world_pos.xz).rgb;  // tees keep this grain (below)
	// The fringe is fairway grass cut round the green: the fairway's own texture (and its
	// normal map, see fairway_w), slightly lighter and without the mowing stripes.
	vec3 fringe_grass = fringe_turf_color * mix(vec3(1.0), turf, turf_strength * mix(0.15, 1.0, ground_detail)) * (1.0 + m * macro_strength);
	col = mix(col, fringe_grass, fringe_w * (1.0 - green_w));
	col = mix(col, first_cut_grass, bank_grass_w);
	// Tees carry the fringe's grain, but match the green's average shade.
	vec3 green_average = green_texture_average / max(green_mean, 0.05);
	vec3 tee_base = mix(
		green_color_a * (1.0 + d * detail_strength * 2.0 * ground_detail + m * macro_strength * 2.0),
		green_color_a * green_average * (1.0 + m * macro_strength),
		turf_strength * mix(0.15, 1.0, ground_detail));
	float fringe_average = dot(textureLod(fringe_texture, vec2(0.5), 12.0).rgb, vec3(0.2126, 0.7152, 0.0722));
	float tee_grain = dot(fringe_raw, vec3(0.2126, 0.7152, 0.0722)) / max(fringe_average, 0.02);
	col = mix(col, tee_base * mix(1.0, clamp(tee_grain, 0.6, 1.4), 0.5 * ground_detail), tee_w);
	// pine straw under the trees: the mask's soft disc edges plus detail noise break
	// the outline up so beds read as raked needles thinning into the rough
	float straw_raw = texture(straw_mask, (world_pos.xz - mask_origin) / straw_size).r;
	// Island trees stand in their own pine-straw beds, like the woods (painted per tree).
	float straw_w = smoothstep(0.30, 0.65, straw_raw + d * 0.35) * rough_w * (1.0 - first_cut_w);
	vec3 straw_tex = texture(straw_texture, world_pos.xz * straw_scale).rgb / max(straw_mean, 0.05);
	vec3 straw = straw_color * straw_tex * (1.0 + m * macro_strength * 2.0);
	col = mix(col, straw, straw_w);
	// sand and water bed from the mask (soft, polygon-accurate edges)
	vec3 sand_tex = texture(sand_texture, world_pos.xz * sand_scale).rgb / max(sand_mean, 0.05);
	// Keep the source sand grain without its yellow photographic color cast.
	float sand_grain = dot(sand_tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 sand = mix(sand_color, sand_color2, d + 0.5) * mix(1.0, sand_grain, sand_tone_strength) * (1.0 + m * macro_strength);
	sand *= 1.0 - sand_lip_shade * (1.0 - smoothstep(0.0, sand_lip_width, -sd_sand));
	col = mix(col, sand, mask.r);
	EMISSION = sand * sand_bounce * mask.r;
	col = mix(col, waterbed_color * (1.0 + d * 0.3), mask.a);
	float trail = texture(sand_trail, (world_pos.xz - sand_trail_origin) / sand_trail_size).r;
	col = mix(col, col * trail, mask.r);
	// Mowing stripes. The down-the-hole direction is the gradient of along_m, solved from
	// its screen-space derivatives, so no extra vertex data is needed.
	float stripe_w = turf_w * (1.0 - mask.g) * (1.0 - fringe_w) * (1.0 - tee_w) * (1.0 - mask.r) * (1.0 - mask.a) * (1.0 - straw_w);
	float band = along_m / stripe_width;
	// +1 on even bands, -1 on odd ones, anti-aliased; far away the bands average out.
	float parity = clamp(sin(3.14159265 * band) / (3.14159265 * max(fwidth(band), 1e-4)), -1.0, 1.0);
	vec2 wx = dFdx(world_pos.xz);
	vec2 wy = dFdy(world_pos.xz);
	float ax = dFdx(along_m);
	float ay = dFdy(along_m);
	float det = wx.x * wy.y - wx.y * wy.x;
	vec2 down_hole = vec2(ax * wy.y - ay * wx.y, ay * wx.x - ax * wy.x) * sign(det);
	down_hole /= max(length(down_hole), 1e-6);
	vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	// +1 looking toward the green, -1 back toward the tee, ~0 from straight above
	float lean = dot(view_dir.xz, down_hole);
	col *= 1.0 + parity * (stripe_view * lean + stripe_top * abs(view_dir.y)) * stripe_w;
	ALBEDO = col;
	// Mown fairway and fringe (not rough/green/sand/water): where the PBR normal
	// map, roughness and AO apply. NORMAL_MAP_DEPTH fades it to flat elsewhere so the
	// blend at every edge stays soft, matching the colour blend above.
	float fairway_w = turf_strength * (1.0 - rough_w) * (1.0 - mask.g) * (1.0 - mask.r) * (1.0 - mask.a) * (1.0 - straw_w);
	// Same idea as fairway_w above, but for the rough's own PBR set -- excludes
	// sand/water/green/straw so bunkers and greens sitting inside the rough's
	// distance field don't pick up its normal/roughness/AO.
	float rough_pbr_w = rough_w * (1.0 - mask.g) * (1.0 - fringe_w) * (1.0 - mask.r) * (1.0 - mask.a) * (1.0 - straw_w);
	vec3 turf_n = texture(turf_normal, world_pos.xz * fairway_scale).rgb;
	float turf_rough_v = texture(turf_roughness, world_pos.xz * fairway_scale).r;
	float turf_ao_v = texture(turf_ao, world_pos.xz * fairway_scale).r;
	vec3 rough_n = mix(
		texture(rough_normal_array, vec3(rough_uv, rough_idx0)).rgb,
		texture(rough_normal_array, vec3(rough_uv, rough_idx1)).rgb,
		rough_variant_blend);
	float rough_rough_v = mix(
		texture(rough_roughness_array, vec3(rough_uv, rough_idx0)).r,
		texture(rough_roughness_array, vec3(rough_uv, rough_idx1)).r,
		rough_variant_blend);
	float rough_ao_v = mix(
		texture(rough_ao_array, vec3(rough_uv, rough_idx0)).r,
		texture(rough_ao_array, vec3(rough_uv, rough_idx1)).r,
		rough_variant_blend);
	float grass_pbr_w = fairway_w + rough_pbr_w;
	float rough_share = grass_pbr_w > 0.0001 ? rough_pbr_w / grass_pbr_w : 0.0;
	// Rake furrows fade out once a furrow is only a few pixels wide, so distant bunkers
	// stay clean instead of shimmering.
	vec2 rake_across = normalize(vec2(-sand_rake_dir.y, sand_rake_dir.x));
	float rake_wobble = (texture(macro_noise, world_pos.xz * 0.03).r - 0.5) * 3.0;
	float rake_u = dot(world_pos.xz, rake_across) / sand_rake_spacing + rake_wobble;
	float rake_pass = texture(macro_noise, vec2(dot(world_pos.xz, rake_across) * 0.08, dot(world_pos.xz, normalize(sand_rake_dir)) * 0.01)).r;
	float rake_w = sand_rake_strength * mix(0.35, 1.0, smoothstep(0.3, 0.7, rake_pass)) * (1.0 - smoothstep(0.12, 0.3, fwidth(rake_u)));
	vec2 sand_slope = rake_across * rake_w * cos(6.2831853 * rake_u);
	vec3 grain_n = texture(sand_grain_normal, world_pos.xz * sand_grain_scale).rgb * 2.0 - 1.0;
	sand_slope += grain_n.xy / max(grain_n.z, 0.25) * sand_grain_strength;
	// Faked face and lip: the sand climbs toward the edge (normal tilted inward) and the turf
	// rolls away outside it (tilted outward), so the real sun lights one side of every bunker
	// and shades the other, and the edge itself catches a highlight or a shadow line.
	vec2 sd_grad = vec2(0.0);
	if (sd_sand > -sand_face_width - 1.0 && sd_sand < 1.0) {
		vec2 ex = vec2(0.75 / mask_size.x, 0.0);
		vec2 ez = vec2(0.0, 0.75 / mask_size.y);
		sd_grad = vec2(
			decode_sd(texture(feature_mask, feature_uv + ex).r) - decode_sd(texture(feature_mask, feature_uv - ex).r),
			decode_sd(texture(feature_mask, feature_uv + ez).r) - decode_sd(texture(feature_mask, feature_uv - ez).r));
		sd_grad /= max(length(sd_grad), 1e-4);
	}
	float sand_face = (1.0 - smoothstep(0.0, sand_face_width, -sd_sand)) * step(sd_sand, 0.0);
	float lip_roll = (1.0 - smoothstep(0.0, 0.35, sd_sand)) * step(0.0, sd_sand);
	sand_slope += sd_grad * sand_face * sand_face_slope;
	vec2 lip_slope = -sd_grad * lip_roll * sand_lip_roll;
	vec3 geo_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sand_n = normalize(geo_n - vec3(sand_slope.x, 0.0, sand_slope.y) * mask.r - vec3(lip_slope.x, 0.0, lip_slope.y) * (1.0 - mask.r));
	NORMAL = normalize((VIEW_MATRIX * vec4(sand_n, 0.0)).xyz);
	NORMAL_MAP = mix(turf_n, rough_n, rough_share);
	NORMAL_MAP_DEPTH = (fairway_w * 0.25 + rough_pbr_w * 0.08) * ground_detail * (1.0 - tee_w);
	float grass_rough_v = mix(turf_rough_v, rough_rough_v, rough_share);
	ROUGHNESS = mix(mix(1.0, 0.90, mask.r), max(grass_rough_v, 0.88), grass_pbr_w);
	float grass_ao_v = mix(turf_ao_v, rough_ao_v, rough_share);
	AO = mix(1.0, grass_ao_v, (fairway_w * 0.3 + rough_pbr_w * 0.10) * ground_detail * (1.0 - tee_w));
	AO *= 1.0 - sand_face_occlusion * sand_face * mask.r;
	SPECULAR = mix(0.04, 0.15, mask.r);
}
