shader_type canvas_item;
render_mode unshaded;

uniform vec2 display_size = vec2(116.0, 220.0);

void fragment() {
	// A soft, rounded map edge, with no frame or background plate.
	float radius = min(7.0, display_size.x * 0.12);
	vec2 q = abs((UV - 0.5) * display_size) - (display_size * 0.5 - vec2(radius));
	float edge_distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	COLOR.a *= 1.0 - smoothstep(-1.25, 0.0, edge_distance);
}
