shader_type sky;
// Everyday sky (course.gd _build_world): the old ProceduralSkyMaterial look -- top/horizon
// gradient plus the generated cumulus cover texture -- with a visible sun. The disc and its
// glow follow the scene's DirectionalLight ("Sun") through LIGHT0_*, so they always sit
// where the shadows say the sun is. One texture sample and some math: no ray march.

uniform vec3 sky_top_color : source_color = vec3(0.25, 0.48, 0.9);
uniform vec3 sky_horizon_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_bottom_color : source_color = vec3(0.32, 0.36, 0.3);
uniform sampler2D sky_cover : source_color, filter_linear;
uniform vec4 sky_cover_modulate : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform float sun_disc_degrees = 1.4;   // apparent radius of the disc
uniform float sun_glow_degrees = 18.0;  // radius of the warm halo around it
uniform float sun_disc_strength = 8.0;
uniform float sun_glow_strength = 0.55;
uniform vec3 sun_glow_tint : source_color = vec3(1.0, 0.86, 0.62);

void sky() {
	float y = EYEDIR.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(sky_horizon_color, sky_top_color, pow(clamp(y, 0.0, 1.0), 0.55));
		vec4 cover = texture(sky_cover, SKY_COORDS);
		col += cover.rgb * sky_cover_modulate.rgb * cover.a * sky_cover_modulate.a;
	} else {
		col = mix(sky_horizon_color, ground_bottom_color, clamp(-y * 4.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		float disc_r = radians(sun_disc_degrees);
		float disc = 1.0 - smoothstep(disc_r * 0.8, disc_r, angle);
		float glow = pow(max(1.0 - angle / radians(sun_glow_degrees), 0.0), 3.0);
		vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
		// the glow only lights the sky, not the ground below the horizon
		col += sun * sun_glow_tint * glow * sun_glow_strength * step(0.0, y);
		col = mix(col, sun * sun_disc_strength, disc);
	}
	COLOR = col;
}
