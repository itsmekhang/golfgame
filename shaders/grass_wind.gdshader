// Cheap wind-blown rough grass, following the user-supplied vertex-pushed-by-noise recipe
// almost verbatim: unshaded, only a tiling noise texture sampled per vertex (no per-blade
// sin()), and a curve-textured push-away from the ball. Ported to Godot 4 (WORLD_MATRIX
// was renamed MODEL_MATRIX) and with the dead `normalize(bump_wind);` statement from the
// original actually applied. Rough only -- the fairway is a separate flat mesh on
// shaders/terrain.gdshader and never gets this shader.
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform float wind_speed = 0.25;
uniform float wind_strength = 0.05;
// World-space size, in metres, of one tile of the wind noise texture.
uniform float wind_texture_tile_size = 6.0;
uniform float wind_vertical_strength = 0.015;
uniform vec2 wind_horizontal_direction = vec2(1.0, 0.5);

uniform sampler2D color_ramp : source_color, hint_default_black;
uniform sampler2D wind_noise : hint_default_black;

uniform vec3 character_position = vec3(0.0, -1000.0, 0.0);
uniform float character_radius = 0.6;
// Not source_color: this holds a raw 0..1 curve value, not sRGB color data.
uniform sampler2D character_distance_falloff_curve : hint_default_black;
uniform float character_push_strength = 0.15;

void vertex() {
	vec3 world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Every instance's MODEL_MATRIX here is a rotation times a scale (MultiMesh transforms
	// from RoughGrass never shear), so transpose(mat3) rotates a direction exactly as well
	// as the true inverse for our purposes -- both directions below get normalize()'d right
	// after, which absorbs the scale mismatch. inverse(mat4) is one of the most expensive
	// things you can put in a vertex shader; at rough-grass instance counts (100k's of
	// clumps x 9 strands each) doing it twice per vertex was enough to blow frame time past
	// the driver's timeout and crash the whole game (VK_ERROR_DEVICE_LOST).
	mat3 inv_rot = transpose(mat3(MODEL_MATRIX));

	vec2 normalized_wind_direction = normalize(wind_horizontal_direction);
	vec2 world_uv = world_vert.xz / wind_texture_tile_size + normalized_wind_direction * TIME * wind_speed;
	// blade meshes have UV.y = 1 at the root and 0 at the tip, so only the tip sways
	float displacement_affect = (1.0 - UV.y);
	float wind_noise_intensity = (textureLod(wind_noise, world_uv, 0.0).r - 0.5);

	// Convert the wind direction from world space into vertex space, otherwise rotated
	// blades wouldn't all lean the same way.
	vec2 vert_space_horizontal_dir = (inv_rot * vec3(normalized_wind_direction, 0.0)).xy;
	vert_space_horizontal_dir = normalize(vert_space_horizontal_dir);

	vec3 bump_wind = vec3(
		wind_noise_intensity * vert_space_horizontal_dir.x,
		1.0 - wind_noise_intensity,
		wind_noise_intensity * vert_space_horizontal_dir.y
	);
	bump_wind = normalize(bump_wind);
	bump_wind *= vec3(
		wind_strength,
		wind_vertical_strength,
		wind_strength
	);
	VERTEX += bump_wind * displacement_affect;

	vec3 dir_to_character = character_position - MODEL_MATRIX[3].xyz;
	float distance_to_character = length(dir_to_character);
	float falloff = 1.0 - smoothstep(0.0, 1.0, distance_to_character / character_radius);
	// Convert to vertex space too, so pushed blades face away from the ball regardless of rotation.
	dir_to_character = inv_rot * dir_to_character;
	dir_to_character = normalize(dir_to_character);

	float falloff_curve = texture(character_distance_falloff_curve, vec2(falloff, falloff)).x;
	VERTEX += normalize(-dir_to_character) * falloff_curve * character_push_strength * displacement_affect;
}

void fragment() {
	ALBEDO = texture(color_ramp, vec2(1.0 - UV.y, 0.0)).rgb;
}
