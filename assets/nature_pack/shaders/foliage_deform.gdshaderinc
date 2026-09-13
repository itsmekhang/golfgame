uniform float wind_strength = 0.035;
uniform float wind_speed = 0.85;
uniform float plant_height = 1.0;
uniform float root_lock_height = 0.02;
uniform bool is_leaf_surface = true;
uniform vec4 contact_0 = vec4(0.0, -10000.0, 0.0, 0.01);
uniform vec4 contact_1 = vec4(0.0, -10000.0, 0.0, 0.01);
uniform vec4 contact_2 = vec4(0.0, -10000.0, 0.0, 0.01);
uniform vec4 contact_3 = vec4(0.0, -10000.0, 0.0, 0.01);
uniform vec3 flex_0 = vec3(0.0);
uniform vec3 flex_1 = vec3(0.0);
uniform vec3 flex_2 = vec3(0.0);
uniform vec3 flex_3 = vec3(0.0);

vec3 local_contact(vec3 rest, vec4 contact, vec3 flex) {
    float distance_ratio = length(rest - contact.xyz) / max(contact.w, 0.01);
    float influence = 1.0 - smoothstep(0.0, 1.0, distance_ratio);
    return flex * influence;
}

vec3 foliage_displacement(vec3 rest, vec2 mask, vec3 origin) {
    float relative_height = max(0.0, rest.y - origin.y);
    float root_weight = smoothstep(root_lock_height, max(plant_height * 0.55, root_lock_height + 0.1), relative_height);
    float phase = dot(rest.xz, vec2(0.17, 0.23));
    vec3 sway = vec3(0.85, 0.0, 0.35) * sin(TIME * wind_speed + phase) * wind_strength * root_weight;
    vec3 contact = local_contact(rest, contact_0, flex_0) + local_contact(rest, contact_1, flex_1);
    contact += local_contact(rest, contact_2, flex_2) + local_contact(rest, contact_3, flex_3);
    sway += contact * root_weight;
    if (is_leaf_surface) {
        float flutter = sin(TIME * 4.8 + mask.y * 19.0 + phase) * 0.007;
        flutter += sin(TIME * 9.0 + mask.y * 27.0) * min(length(contact) * 0.025, 0.02);
        sway.y += flutter * mask.x * root_weight;
    }
    return sway;
}
