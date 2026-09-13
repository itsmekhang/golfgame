// Cross-card impostor for a tree/shrub baked from `views` azimuths
// (tools/bake_impostors.gd). The mesh is three vertical quads fixed in the instance's
// own frame (60 degrees apart, built by NaturePack.impostor) -- nothing turns with the
// camera, so the trees never "spin" as you orbit. Each quad shows the baked view that
// looks along its own facing, mirrored when seen from behind; two or three quads
// overlap from any angle and read as a volume. Instances closer than `near_cut`
// collapse (their real mesh is drawn instead).
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, unshaded;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int views = 8;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;
uniform float near_cut = 450.0;
uniform float far_cut = 900.0;
uniform float color_scale = 1.0;

varying float view_index;
varying float flip;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float yaw_local = UV2.x;  // the quad's facing, stored per vertex by NaturePack
	vec3 n_local = vec3(-sin(yaw_local), 0.0, cos(yaw_local));
	vec3 n = normalize((MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float cam_dist = length(to_cam);
	bool front = dot(n, to_cam) >= 0.0;
	vec3 face = front ? n : -n;
	vec3 inst_x = normalize(MODEL_MATRIX[0].xyz);
	float inst_yaw = atan(inst_x.z, inst_x.x);
	float az = atan(face.z, face.x) - inst_yaw;
	view_index = mod(round(az / (TAU / float(views))), float(views));
	flip = front ? 0.0 : 1.0;
	if (cam_dist < near_cut || cam_dist >= far_cut) {
		VERTEX = vec3(0.0);
	}
	NORMAL = vec3(0.0, 1.0, 0.0);  // lit as from above; the bake carries the shading
}

void fragment() {
	float u = mix(UV.x, 1.0 - UV.x, flip);
	vec4 c = texture(atlas, vec2((u + view_index) / float(views), UV.y));
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = c.rgb * color_scale;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
