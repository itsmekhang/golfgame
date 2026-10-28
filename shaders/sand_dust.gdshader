shader_type spatial;
// Bunker-shot dust puffs (course.gd _spawn_sand_blast): soft camera-facing billboards in a
// sand tint that fade in fast and out slowly over each particle's life. The fade is driven by
// the particle's age (INSTANCE_CUSTOM.y, set by CPUParticles3D), not by per-particle colour --
// CPUParticles3D can hand a just-spawned particle a black colour for its first frames.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.76, 0.67, 0.5, 0.38);
uniform sampler2D puff : filter_linear, hint_default_white;

varying float life;

void vertex() {
	// camera-facing billboard keeping the particle's scale and spin (as BILLBOARD_PARTICLES)
	mat4 face = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	face = face * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	life = INSTANCE_CUSTOM.y;
}

void fragment() {
	ALBEDO = tint.rgb;
	float fade = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.25, 1.0, life));
	ALPHA = texture(puff, UV).a * tint.a * fade;
}
