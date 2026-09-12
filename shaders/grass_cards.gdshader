// Textured blade cards (photo atlas) for the rough. Two-sided, alpha cut-out,
// flattening around the ball (interracting_object_pos). Wind sway was removed: a
// per-vertex texture sample + sin() on every blade of every clump, every frame, was
// a real GPU cost at rough-grass instance counts -- not worth it for a subtle sway.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D main_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 base_darken : source_color = vec3(0.45, 0.55, 0.3);
uniform vec3 interracting_object_pos = vec3(0.0, -1000.0, 0.0);
uniform float flatten_radius = 0.5;
uniform float flatten_floor = 0.25;

varying float height01;
varying float flat_amount;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// height of this vertex within its clump (clump meshes are 0..~0.4 m tall)
	height01 = clamp(VERTEX.y / 0.4, 0.0, 1.0);

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
	ALBEDO = col;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
