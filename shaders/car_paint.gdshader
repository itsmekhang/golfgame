// A car body (the user's car pack: the paint baked into its texture, one colour a model) in a
// paint of its own: every texel of the model's own paint -- its hue, and from a third as bright
// to a few times brighter, its shading -- in the new colour at the same shading; the trim, the
// grille, the chrome and the rubber as they are. The new colour (linear) comes from the
// instance's `paint` (a = 1) or, in a batch of parked cars, its MultiMesh instance colour.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 base_paint : source_color = vec3(1.0);
uniform float roughness = 0.4;
uniform float metallic = 0.2;
// The black SUV's finish map separates paint (low roughness, nonmetal) from
// chrome and trim even where its baked albedo is almost black.
uniform bool use_finish_mask = false;
uniform sampler2D finish_tex : filter_linear_mipmap, repeat_enable;
instance uniform vec4 paint = vec4(1.0, 1.0, 1.0, 0.0);

varying vec3 batch_paint;

void vertex() {
	batch_paint = COLOR.rgb;
}

void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb;
	vec3 want = paint.a > 0.5 ? paint.rgb : batch_paint;
	float st = t.r + t.g + t.b + 1e-4;
	float sb = base_paint.r + base_paint.g + base_paint.b + 1e-4;
	float hue = length(t / st - base_paint / sb);  // (how far from the paint's own tint)
	float ratio = st / sb;  // (its shading: lighter or darker than the paint's own)
	float mask = (1.0 - smoothstep(0.06, 0.14, hue)) * smoothstep(0.3, 0.5, ratio) * (1.0 - smoothstep(2.6, 4.0, ratio));
	vec2 finish = vec2(roughness, metallic);
	if (use_finish_mask) {
		finish = texture(finish_tex, UV).gb;
		mask = (1.0 - smoothstep(0.18, 0.4, finish.x)) * (1.0 - smoothstep(0.15, 0.35, finish.y));
		// Dark baked paint shading must not turn the new colour back to black.
		ratio = clamp(sqrt(max(ratio, 0.0)), 0.65, 1.25);
	}
	ALBEDO = mix(t, want * ratio, mask);
	ROUGHNESS = mix(finish.x, 0.32, mask);  // (fresh paint: a little glossier than the trim)
	METALLIC = finish.y;
}
