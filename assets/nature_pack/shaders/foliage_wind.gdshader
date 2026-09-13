shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, world_vertex_coords;

uniform float wind_strength : hint_range(0.0, 0.5) = 0.12;
uniform float wind_speed : hint_range(0.0, 4.0) = 0.85;
uniform vec2 wind_direction = vec2(0.85, 0.35);

void vertex() {
    float weight = clamp(UV2.x, 0.0, 1.0);
    float phase = dot(VERTEX.xz, vec2(0.16, 0.21));
    float gust = sin(TIME * wind_speed + phase);
    gust += 0.24 * sin(TIME * wind_speed * 2.3 + phase * 2.0);
    VERTEX.xz += wind_direction * gust * wind_strength * weight;
}

void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 0.92;
    SPECULAR = 0.15;
}
