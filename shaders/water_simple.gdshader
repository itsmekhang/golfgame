shader_type spatial;
render_mode cull_back;

uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.10, 0.17, 0.14, 1.0);
// A touch deeper/bluer at distance so a far hazard still reads as its own body of
// water instead of just a paler version of the near-water colour.
uniform vec4 color_far : source_color = vec4(0.05, 0.11, 0.17, 1.0);
uniform float rapid = 0.008;
// A flat, glossy METALLIC surface is physically correct but that's exactly the
// problem: real water at a grazing angle (which is what "far away" mostly is,
// looking nearly along the surface) reflects ~100% of the sky regardless of
// roughness, so the whole hazard washes out to sky-blue and reads as "not
// rendering." Fresnel is computed by hand instead of via METALLIC so the sky's
// contribution can be capped -- the water keeps its own colour showing through
// even at a shallow viewing angle.
// A winding creek/pond puts near and far stretches of the SAME body of water in
// one shot; both this and color_far's distance blend used to ramp up well
// within normal play/viewing distance (~150-250 m), so one continuous hazard
// visibly split into two different-looking ponds at a bend -- reported as
// hole 11 and 12's creeks "not connecting naturally" even though geometrically
// they already touched. Both effects now only kick in much further out, and
// the fresnel curve is steeper so moderate angles stay near the base colour
// and only near-horizon grazing angles pick up real sky reflection.
uniform float fresnel_power = 5.0;
uniform float max_sky_mix = 0.35;
uniform vec3 sky_tint : source_color = vec3(0.55, 0.68, 0.78);

void fragment() {
    // Quiet pond/creek surface: opaque so it does not sort against grass or
    // amplify the bed texture through a highly metallic transparent layer.
    vec2 drift = vec2(TIME * rapid, TIME * rapid * 0.37);
    vec3 a = texture(normal_map, UV + drift).rgb;
    vec3 b = texture(normal_map, UV * 0.73 - drift * 0.6).rgb;
    NORMAL_MAP = mix(a, b, 0.5);
    NORMAL_MAP_DEPTH = 0.18;

    // VERTEX in fragment() is view-space (camera-relative), so its length is
    // already the distance to camera -- no world-position varying needed.
    float far_t = clamp(length(VERTEX) / 550.0, 0.0, 1.0);
    vec3 base = mix(color.rgb, color_far.rgb, far_t);

    float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - ndotv, fresnel_power) * max_sky_mix;
    ALBEDO = mix(base, sky_tint, fresnel);
    METALLIC = 0.0;
    ROUGHNESS = mix(0.16, 0.32, fresnel);
    SPECULAR = 0.5;
}
