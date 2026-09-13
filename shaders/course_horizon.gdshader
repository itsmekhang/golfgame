shader_type spatial;
render_mode cull_back;
uniform sampler2D rough_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	ALBEDO = texture(rough_texture, UV).rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
	// Extra haze hides the remote apron before the camera's far clipping plane.
	// The surrounding course uses the same environment fog as the playable ground.
	float camera_distance = distance(CAMERA_POSITION_WORLD, world_position);
	float fog = max(1.0 - exp(-camera_distance * 0.00025), smoothstep(1600.0, 5000.0, camera_distance));
	FOG = vec4(vec3(0.448, 0.604, 0.787), fog);
}
