shader_type spatial;
render_mode cull_back;

uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.10, 0.17, 0.14, 1.0);
uniform float rapid = 0.008;

void fragment() {
    // Quiet pond/creek surface: opaque so it does not sort against grass or
    // amplify the bed texture through a highly metallic transparent layer.
    vec2 drift = vec2(TIME * rapid, TIME * rapid * 0.37);
    vec3 a = texture(normal_map, UV + drift).rgb;
    vec3 b = texture(normal_map, UV * 0.73 - drift * 0.6).rgb;
    NORMAL_MAP = mix(a, b, 0.5);
    NORMAL_MAP_DEPTH = 0.18;
    ALBEDO = color.rgb;
    METALLIC = 0.15;
    ROUGHNESS = 0.16;
    SPECULAR = 0.65;
}
