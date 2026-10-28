shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled;
// Only the cast shadow is visible. The receiver never writes depth, so it cannot
// obscure a club sole or leave an opaque ground rectangle in a thumbnail.

uniform float shadow_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	ALPHA = 0.0;
}

void light() {
	DIFFUSE_LIGHT = vec3(0.0);
	SPECULAR_LIGHT = vec3(0.0);
	ALPHA = max(ALPHA, shadow_strength * (1.0 - ATTENUATION));
}
