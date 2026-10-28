shader_type spatial;
// Predicted landing spot (course.gd landing_marker): one plain ring on the ground. Drawn as a
// camera-facing quad squashed by how steeply the camera looks down at it -- round from
// overhead, a flat ellipse from the tee, where a ring lying truly flat would foreshorten to
// nothing 200 m away -- and lifted so the bottom of the ellipse rests on the landing point.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.2, 1.0);
uniform float min_squash = 0.3;  // flattest the ellipse gets at grazing view angles
uniform float line_width = 0.09; // ring thickness as a share of the radius
uniform float lift = 0.08;       // metres above the ground, so it doesn't z-fight the turf

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	// sine of the camera's elevation above the spot: 1 straight overhead, ~0 at the horizon
	float squash = clamp(normalize(CAMERA_POSITION_WORLD - centre).y, min_squash, 1.0);
	centre.y += s * squash * max(up.y, 0.0) + lift;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0), vec4(up * s * squash, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), vec4(centre, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float w = fwidth(r);
	// at least ~1.5 px wide however far away the ring is
	float half_line = max(line_width * 0.5, w * 0.75);
	float ring = 1.0 - smoothstep(half_line, half_line + w, abs(r - (1.0 - half_line - w)));
	ALBEDO = tint.rgb;
	ALPHA = ring * tint.a;
}
