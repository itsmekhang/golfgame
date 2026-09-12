shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

group_uniforms WaterWaves;
uniform float wave_amplitude : hint_range(0.0, 0.3) = 0.03;
uniform float wave_frequency : hint_range(0.0, 20.0) = 6.0;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.5;
group_uniforms;

group_uniforms WaterAppearance;
uniform bool seamless = true;
uniform float _speed = 1.0;
uniform float _scale = 3.0;
uniform vec4 color_deep : source_color = vec4(0.05, 0.25, 0.55, 0.85);
uniform vec4 color_shallow : source_color = vec4(0.4, 0.85, 0.95, 0.6);
uniform float color_threshold : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms ToonOutline;
uniform bool outline_enabled = true;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.15) = 0.04;
group_uniforms;

varying vec3 world_pos;

void vertex() {
    vec3 n = NORMAL;
    float wobble = sin(dot(n, vec3(1.0)) * wave_frequency + TIME * wave_speed) * wave_amplitude;
    VERTEX += NORMAL * wobble;
    world_pos = VERTEX;
}

vec3 mod2893(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod2893(i);
    vec4 p = permute(permute(permute(
        i.z + vec4(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// non seamless
float getNoise(vec2 uv, float t) {
    float SCALE = _scale;
    float noise = snoise(vec3(uv.x * SCALE + t * _speed, uv.y * SCALE + t * _speed * 0.5, 0.0));
    SCALE = 8.0;
    noise += snoise(vec3(uv.x * SCALE - t * _speed, uv.y * SCALE, 0.0)) * 0.2;
    return noise / 2.0 + 0.5;
}

// seamless
float getNoise(vec3 pos, float t) {
    float SCALE = _scale;
    float noise = snoise(pos * SCALE + vec3(t * _speed, t * _speed * 0.5, 0.0));
    SCALE = 8.0;
    noise += snoise(pos * SCALE - vec3(t * _speed, 0.0, 0.0)) * 0.2;
    return noise / 2.0 + 0.5;
}

float getDepth(float n, float steps) {
    return floor(n * steps) / steps;
}

void fragment() {
    float steps = 4.0;
    float t = TIME;

    vec3 pos = normalize(world_pos);
    vec2 uv = UV;

    float noise = seamless ? getNoise(pos, t) : getNoise(uv, t);
    float d = getDepth(noise, steps);
    vec3 col = d >= color_threshold ? color_shallow.rgb : color_deep.rgb;
    float alpha = d >= color_threshold ? color_shallow.a : color_deep.a;

    bool is_edge = false;

    if (outline_enabled) {
        float delta = outline_thickness;
        if (seamless) {
            float n_x1 = getDepth(getNoise(pos + vec3(delta, 0.0, 0.0), t), steps);
            float n_x2 = getDepth(getNoise(pos - vec3(delta, 0.0, 0.0), t), steps);
            float n_y1 = getDepth(getNoise(pos + vec3(0.0, delta, 0.0), t), steps);
            float n_y2 = getDepth(getNoise(pos - vec3(0.0, delta, 0.0), t), steps);
            float n_z1 = getDepth(getNoise(pos + vec3(0.0, 0.0, delta), t), steps);
            float n_z2 = getDepth(getNoise(pos - vec3(0.0, 0.0, delta), t), steps);
            is_edge = (n_x1 != d) || (n_x2 != d) || (n_y1 != d) || (n_y2 != d) || (n_z1 != d) || (n_z2 != d);
        } else {
            float n_up    = getDepth(getNoise(uv + vec2(0.0,  delta), t), steps);
            float n_down  = getDepth(getNoise(uv + vec2(0.0, -delta), t), steps);
            float n_left  = getDepth(getNoise(uv + vec2(-delta, 0.0), t), steps);
            float n_right = getDepth(getNoise(uv + vec2( delta, 0.0), t), steps);
            is_edge = (n_up != d) || (n_down != d) || (n_left != d) || (n_right != d);
        }
    }

    if (is_edge) {
        ALBEDO = outline_color.rgb;
        ALPHA = outline_color.a;
    } else {
        ALBEDO = col;
        ALPHA = alpha;
    }
}
