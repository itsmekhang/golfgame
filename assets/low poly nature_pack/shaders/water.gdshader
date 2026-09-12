shader_type spatial;
render_mode diffuse_burley;

uniform float ripple_strength : hint_range(0.0, 0.15) = 0.035;
uniform float ripple_speed : hint_range(0.0, 3.0) = 0.55;
varying vec2 water_position;

void vertex() {
    water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    float a = water_position.x * 2.6 + water_position.y * 1.8 + TIME * ripple_speed;
    float b = water_position.x * -1.5 + water_position.y * 3.3 + TIME * ripple_speed * 1.4;
    float shimmer = sin(a) * sin(b);
    ALBEDO = COLOR.rgb * (1.0 + ripple_strength * shimmer);
    NORMAL = normalize(NORMAL + vec3(cos(a), sin(b), 0.0) * ripple_strength);
    ROUGHNESS = 0.28;
    SPECULAR = 0.55;
}
