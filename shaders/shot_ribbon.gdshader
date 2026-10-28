shader_type spatial;
// Shot tracer / flight trail ribbon (course.gd _ribbon_mesh). UV.x runs 0 -> 1 along the
// path, UV.y 0 -> 1 across it, UV2.x is metres along. Soft edges across the width, a colour
// gradient along it, optional dashes that flow downrange, and the vertex alpha for fading.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color_start : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform vec4 color_end : source_color = vec4(0.95, 0.82, 0.49, 0.95);
uniform float dash_m = 0.0;      // dash spacing in metres; 0 = solid
uniform float flow_speed = 6.0;  // metres per second the dashes travel
uniform float end_fade = 0.06;   // share of the length faded in / out at each end
uniform float core_white = 0.35; // how far the centre of the ribbon is lifted toward white

void fragment() {
	float t = UV.x;
	vec4 c = mix(color_start, color_end, t);
	float across = abs(UV.y * 2.0 - 1.0);
	float a = c.a * (1.0 - smoothstep(0.55, 1.0, across)) * COLOR.a;
	if (dash_m > 0.0) {
		float d = fract((UV2.x - TIME * flow_speed) / dash_m);
		a *= mix(0.35, 1.0, smoothstep(0.25, 0.35, d) * (1.0 - smoothstep(0.85, 0.95, d)));
	}
	a *= smoothstep(0.0, end_fade, t) * (1.0 - smoothstep(1.0 - end_fade, 1.0, t));
	ALBEDO = mix(c.rgb, vec3(1.0), (1.0 - across) * core_white);
	ALPHA = a;
}
