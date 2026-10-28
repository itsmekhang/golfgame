// Textured blade cards (photo atlas) for the rough. Two-sided, alpha cut-out,
// flattening around the ball (interracting_object_pos). Wind sway was removed: a
// per-vertex texture sample + sin() on every blade of every clump, every frame, was
// a real GPU cost at rough-grass instance counts -- not worth it for a subtle sway.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D main_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 rough_color : source_color = vec3(0.015686, 0.250980, 0.149020);
uniform vec3 base_darken : source_color = vec3(0.45, 0.55, 0.3);
uniform vec3 interracting_object_pos = vec3(0.0, -1000.0, 0.0);
uniform float flatten_radius = 0.5;
uniform float flatten_floor = 0.25;
// Blades in shade are lit by the blue sky alone and turn slate blue against the green
// rough. Grass in shade really gets green light bounced between the blades, so most of
// the sky's ambient is cut and the blade's own colour is added back as that bounce.
uniform float sky_ambient = 0.35;   // share of the sky ambient the blades keep
uniform float blade_bounce = 0.6;   // bounced light, as emission of the blade colour
uniform bool streamed_grass = false;
uniform vec2 grass_focus = vec2(0.0);
uniform float grass_fade_end = 48.0;

varying float height01;
varying float flat_amount;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// height of this vertex within its clump (clump meshes are 0..~0.4 m tall)
	height01 = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	if (streamed_grass) {
		float view_dist = distance(origin, CAMERA_POSITION_WORLD);
		float mid_fade = smoothstep(16.0, 24.0, view_dist);
		float far_fade = smoothstep(28.0, 38.0, view_dist);
		float density = 1.0 - 0.4 * mid_fade - 0.3 * far_fade;
		float clump_fade = 1.0 - smoothstep(density, density + 0.05, COLOR.r);
		float card_fade = UV2.x >= 6.0 ? 1.0 - mid_fade : (UV2.x >= 3.0 ? 1.0 - far_fade : 1.0);
		float edge_fade = 1.0 - smoothstep(grass_fade_end - 10.0, grass_fade_end, distance(origin.xz, grass_focus));
		VERTEX *= clump_fade * card_fade * edge_fade;
	}

	float d = distance(world.xz, interracting_object_pos.xz);
	float flat_f = clamp(1.0 - d / flatten_radius, 0.0, 1.0);
	flat_amount = flat_f;
	VERTEX.y *= mix(1.0, flatten_floor, flat_f);
}

void fragment() {
	vec4 c = texture(main_texture, UV);
	if (c.a < alpha_cut) {
		discard;
	}
	vec3 col = c.rgb * tint;
	// darker towards the root, like dense turf
	col *= mix(base_darken, vec3(1.0), smoothstep(0.0, 0.6, height01));
	col *= mix(1.0, 0.7, flat_amount);
	// Retain the atlas detail and root shading while sharing the ground's hue.
	// 0.0524 is the mean linear luminance of the tinted opaque atlas pixels.
	float grain = clamp(dot(col, vec3(0.2126, 0.7152, 0.0722)) / 0.0524, 0.35, 1.8);
	vec3 albedo = rough_color * grain;
	ALBEDO = albedo;
	AO = sky_ambient;
	EMISSION = albedo * blade_bounce;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
