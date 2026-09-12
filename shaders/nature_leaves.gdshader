// Nature pack foliage (leaves / needles / petals / grass blades): vertex colour
// albedo, double sided, wind sway weighted by UV2.x. `max_dist` > 0 collapses
// instances farther than that from the camera (their impostor card takes over), so
// the per-tile LOD ranges of the MultiMesh batches never draw a heavy mesh far away.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, world_vertex_coords;

uniform float wind_strength : hint_range(0.0, 0.5) = 0.12;
uniform float wind_speed : hint_range(0.0, 4.0) = 0.85;
uniform vec2 wind_direction = vec2(0.85, 0.35);
uniform float max_dist = 0.0;
uniform float min_dist = 0.0;

void vertex() {
	float cam_dist = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	if ((max_dist > 0.0 && cam_dist > max_dist) || cam_dist < min_dist) {
		VERTEX = vec3(0.0);
	} else {
		float weight = clamp(UV2.x, 0.0, 1.0);
		float phase = dot(VERTEX.xz, vec2(0.16, 0.21));
		float gust = sin(TIME * wind_speed + phase);
		gust += 0.24 * sin(TIME * wind_speed * 2.3 + phase * 2.0);
		VERTEX.xz += wind_direction * gust * wind_strength * weight;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (!FRONT_FACING) { ALBEDO *= vec3(0.93, 1.02, 0.89); }
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
