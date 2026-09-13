// Nature pack solid surfaces (bark, stone, wood): vertex colour albedo, back-face
// culled. `max_dist` as in nature_leaves.gdshader.
shader_type spatial;
render_mode cull_back, world_vertex_coords;

uniform float max_dist = 0.0;
uniform float min_dist = 0.0;

void vertex() {
	float cam_dist = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	if ((max_dist > 0.0 && cam_dist > max_dist) || cam_dist < min_dist) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * 0.60;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
