shader_type spatial;
render_mode cull_back;
uniform sampler2D rough_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D feature_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 mask_origin;
uniform vec2 mask_size = vec2(1.0);
uniform vec2 active_min;
uniform vec2 active_max;
uniform vec3 fairway_color : source_color = vec3(0.34, 0.47, 0.14);
uniform vec3 green_color : source_color = vec3(0.48, 0.57, 0.24);
uniform vec3 sand_color : source_color = vec3(0.94, 0.94, 0.90);
uniform sampler2D straw_mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D straw_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 straw_origin;
uniform vec2 straw_size = vec2(1.0);
uniform vec3 straw_color : source_color = vec3(0.36, 0.22, 0.14);
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 rough = texture(rough_texture, UV).rgb;
	vec2 p = world_position.xz;
	if (all(greaterThanEqual(p, active_min)) && all(lessThanEqual(p, active_max))) {
		discard;
	}
	float turf = smoothstep(0.45, 0.55, COLOR.r);
	vec2 map_uv = (p - mask_origin) / mask_size;
	vec4 features = vec4(0.0);
	if (all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0)))) {
		features = smoothstep(vec4(0.48), vec4(0.52), texture(feature_mask, map_uv));
	}
	vec3 tint = mix(rough, fairway_color, max(turf, features.b));
	float straw = smoothstep(0.3, 0.65, texture(straw_mask, (p - straw_origin) / straw_size).r) * (1.0 - turf);
	tint = mix(tint, straw_color * texture(straw_texture, p * 0.5).rgb / 0.356, straw);
	tint = mix(tint, green_color, features.g);
	tint = mix(tint, sand_color, features.r);
	ALBEDO = mix(tint, vec3(0.055, 0.095, 0.12), features.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
}
