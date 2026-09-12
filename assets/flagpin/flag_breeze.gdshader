shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 cloth_color : source_color = vec4(0.929412, 0.258824, 0.137255, 1.0);
uniform float wind_strength : hint_range(0.0, 0.10) = 0.025;
uniform float wind_speed : hint_range(0.0, 3.0) = 0.75;

void vertex() {
    // Anchored sleeve; a small extra ripple over the already curved GLB mesh.
    float u = clamp((VERTEX.x - 0.055) / 1.185, 0.0, 1.0);
    float phase = u * 7.5 - TIME * wind_speed * 3.0;
    float envelope = pow(u, 1.5);
    VERTEX.z += wind_strength * envelope * sin(phase);
    float slope = wind_strength / 1.185 * (1.5 * sqrt(u) * sin(phase) + 7.5 * envelope * cos(phase));
    NORMAL = normalize(vec3(NORMAL.x - slope * NORMAL.z, NORMAL.yz));
}

void fragment() {
    ALBEDO = cloth_color.rgb * COLOR.rgb;
    METALLIC = 0.0;
    ROUGHNESS = 0.80;
    SPECULAR = 0.25;
}
