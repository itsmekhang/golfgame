// Nature pack foliage (leaves / needles / petals / grass blades). Follows Godot's
// "Making trees" tutorial: per-axis sway scaled by a per-vertex weight (the pack
// stores it in UV2.x where the tutorial paints COLOR.r), vertex-colour albedo,
// double sided, and back-lit leaves. `min_dist`/`max_dist` collapse instances
// outside this tier's distance band (the per-tile LOD ranges of the MultiMesh
// batches are only a coarse first cut).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, world_vertex_coords;

uniform float sway_speed = 1.0;
uniform float sway_strength = 0.05;
uniform float sway_phase_len = 8.0;
uniform vec3 transmission : source_color = vec3(0.08, 0.12, 0.035);
uniform float max_dist = 0.0;
uniform float min_dist = 0.0;

void vertex() {
	float cam_dist = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	if ((max_dist > 0.0 && cam_dist > max_dist) || cam_dist < min_dist) {
		VERTEX = vec3(0.0);
	} else if (sway_strength > 0.0) {
		float strength = clamp(UV2.x, 0.0, 1.0) * sway_strength;
		VERTEX.x += sin(VERTEX.x * sway_phase_len * 1.123 + TIME * sway_speed) * strength;
		VERTEX.y += sin(VERTEX.y * sway_phase_len + TIME * sway_speed * 1.12412) * strength;
		VERTEX.z += sin(VERTEX.z * sway_phase_len * 0.9123 + TIME * sway_speed * 1.3123) * strength;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * 0.48;
	if (!FRONT_FACING) { ALBEDO *= vec3(0.93, 1.02, 0.89); }
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
	BACKLIGHT = transmission;
}
