shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wear_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec3 oxidation_color : source_color = vec3(0.38, 0.16, 0.055);
uniform float condition : hint_range(0.0, 1.0) = 1.0;
uniform float chip_strength : hint_range(0.0, 1.0) = 0.7;
uniform float corrosion_strength : hint_range(0.0, 1.0) = 0.5;
uniform bool use_orm = true;
uniform float constant_roughness = 0.5;
uniform float constant_metallic = 0.0;
uniform float normal_strength = 0.42;

void fragment() {
    vec3 color = texture(albedo_tex, UV).rgb * base_color.rgb;
    vec3 orm = texture(orm_tex, UV).rgb;
    vec3 mask = texture(wear_tex, UV).rgb;
    float damage = 1.0 - clamp(condition, 0.0, 1.0);
    float grime = damage * mask.r * 0.56;
    float chips = smoothstep(0.16, 0.90, damage) * mask.g * chip_strength;
    float rust = smoothstep(0.30, 1.0, damage) * mask.b * corrosion_strength;
    color = mix(color, color * vec3(0.33, 0.30, 0.24), grime);
    color = mix(color, vec3(0.25, 0.28, 0.27), chips);
    color = mix(color, oxidation_color, rust);
    ALBEDO = color;
    float r = use_orm ? orm.g : constant_roughness;
    float m = use_orm ? orm.b : constant_metallic;
    ROUGHNESS = clamp(mix(r, 0.90, grime + rust * 0.6) + damage * mask.g * 0.10, 0.05, 0.98);
    METALLIC = m * (1.0 - rust * 0.78);
    AO = use_orm ? orm.r : 1.0;
    NORMAL_MAP = texture(normal_tex, UV).rgb;
    NORMAL_MAP_DEPTH = normal_strength;
}
