shader_type sky;
render_mode use_quarter_res_pass, use_half_res_pass;

#define H(p)  fract(sin(mod(dot(p, vec2(12.9898, 78.233)),6.283)) * 43758.5453)

const float EPS = 1e-6;
const float INFINITY = 1.0 / 0.0;
const float PLANET_RADIUS = 6371000.0;
const vec3 PLANET_CENTER = vec3(0.0, -PLANET_RADIUS, 0.0);
const float ATMOSPHERE_HEIGHT = 100000.0;
const float RAYLEIGH_HEIGHT = (ATMOSPHERE_HEIGHT * 0.08);
const float MIE_HEIGHT = (ATMOSPHERE_HEIGHT * 0.012);

uniform bool use_debanding = true;
uniform bool enable_shader = true;

group_uniforms Atmosphere;
uniform int atmosphere_sample_count = 64;
uniform float elevation = 0.0;
uniform float rayleigh_strength : hint_range(0.0, 5.0) = 1.0;
uniform float mie_strength      : hint_range(0.0, 5.0) = 1.0;
uniform float ozone_strength    : hint_range(0.0, 5.0) = 1.0;

const vec3 C_RAYLEIGH = vec3(5.802, 13.558, 33.100) * 1e-6;
const vec3 C_MIE      = vec3(3.996,  3.996,  3.996) * 1e-6;
const vec3 C_OZONE    = vec3(0.650,  1.881,  0.085) * 1e-6;

uniform float mie_anisotropy_factor = 0.75;
uniform float atmosphere_density : hint_range(0.0, 5.0) = 1.0;
uniform float exposure = 10.0;
uniform float sun_disc_feather : hint_range(0.0, 1.0) = 0.5;
uniform float sundisc_intensity = 100.0;

group_uniforms Moon;
uniform float moon_disc_intensity : hint_range(0.0, 50.0) = 4.0;
uniform float moon_disc_feather : hint_range(0.0, 1.0) = 0.35;

group_uniforms NightRealism;
uniform float scotopic_start_energy : hint_range(0.0, 2.0) = 0.35;
uniform float scotopic_full_energy : hint_range(0.0, 2.0) = 0.02;
uniform float night_desaturation : hint_range(0.0, 1.0) = 0.85;
uniform vec3 scotopic_tint : source_color = vec3(0.6, 0.75, 0.95);

group_uniforms Stars;
uniform float stars_density    : hint_range(0.0, 1.0) = 0.5;
uniform float stars_brightness : hint_range(0.0, 10.0) = 3.0;
uniform float stars_size       : hint_range(0.0001, 0.008) = 0.0015;
uniform bool  stars_colored    = true;
uniform bool  dim_stars_at_day = true;
uniform mat3  stars_rotation   = mat3(1.0);
uniform float moon_cull_margin : hint_range(1.0, 6.0) = 3.0;

#define LOWER_PLANE_HEIGHT 3.0

group_uniforms CumulusClouds;
uniform bool  hole_in_center = false;
uniform float hole_radius = 5.0;
uniform float hole_feather = 10.0;
uniform float cloud_falloff_coeff : hint_range(0.0, 1.0) = 0.3;
uniform float clouds_alpha_lower_bound = 0.0;
uniform float clouds_alpha_upper_bound = 0.15;
uniform sampler2D cloud_color_texture : hint_default_white;
uniform vec3  cloud_base_color    : source_color = vec3(.85, .85, .9);
uniform vec3  cloud_overcast_color : source_color = vec3(.35, .4, .45);
uniform float coverage : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_smoothness : hint_range(0.0, 0.2) = 0.05;

group_uniforms CumulusClouds.RayMarchParameters;
uniform bool  apply_stochastic_jitter = false;
uniform float stochastic_jitter_amount : hint_range(0.0, 1.0) = 0.1;
uniform float cloud_base_march_dist = 10.0;
uniform int   cloud_marches : hint_range(4, 64, 1) = 64;
uniform float density_coeff : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_transmittance_cutoff : hint_range(0.0, 0.1) = 0.01;

group_uniforms CumulusClouds.Wind;
uniform vec2  wind_direction = vec2(1.0, 0.3);
uniform float wind_speed : hint_range(0.0, 50.0) = 2.0;
uniform float wind_loop_period = 2000.0;
uniform vec2  noise_wind_direction = vec2(0.3, 1.0);
uniform float noise_wind_speed_mult : hint_range(0.0, 10.0) = 2.0;

group_uniforms CumulusClouds.Textures;
uniform float     cloud_noise_factor : hint_range(0.0, 1.0) = 0.5;
uniform sampler3D cloud_shape : filter_linear_mipmap, repeat_enable;
uniform float     cloud_shape_size = 1.0;
uniform vec3      cloud_shape_offset = vec3(0.0);
uniform sampler3D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float     cloud_noise_size = 1.0;
uniform vec3      cloud_noise_offset = vec3(0.0);

group_uniforms CumulusClouds.LightPass;
uniform float clouds_anisotropy_factor : hint_range(0.0, 1.0) = 0.25;
uniform int   light_marches : hint_range(4, 32, 1) = 8;
uniform float light_max_dist = 5.0;
uniform float light_strength = 15.0;
uniform float ambient_light_multiplier : hint_range(0.0, 5.0) = 1.0;

group_uniforms CirrusClouds;
uniform bool      use_cirrus = true;
uniform sampler2D cirrus_texture : hint_default_black;
uniform vec2      cirrus_squish = vec2(4.0, 1.0);
uniform float     cirrus_scale = 1.0;
uniform float     cirrus_treshold : hint_range(0.0, 1.0) = .75;
uniform float     cirrus_feather  : hint_range(0.0, 1.0) = .25;
uniform vec2      cirrus_offset = vec2(0.0);
uniform sampler2D cirrus_distortion_texture : hint_default_black;
uniform float     cirrus_distortion_scale = 1.0;
uniform float     cirrus_distortion_strength = .4;
uniform vec2      cirrus_distortion_offset = vec2(0.0);
uniform sampler2D cirrus_mask_texture : hint_default_white;
uniform float     cirrus_mask_scale = 1.0;
uniform float     cirrus_mask_treshold : hint_range(0.0, 1.0) = .6;
uniform float     cirrus_mask_feather  : hint_range(0.0, 1.0) = .4;
uniform float     cirrus_opacity : hint_range(0.0, 1.0) = 0.2;

group_uniforms Rainbow;
uniform bool      use_rainbow = false;
uniform bool      behind_clouds = false;
uniform sampler2D rainbow_gradient : hint_default_white, filter_linear;
uniform float     rainbow_width = .05;
uniform float     rainbow_offset = .65;
uniform float     rainbow_opacity : hint_range(0.0, 1.0) = .1;
uniform bool      double_rainbow = true;

#define saturate(a) clamp(a, 0.0, 1.0)

vec2 sphere_intersection(vec3 rayStart, vec3 rayDir, vec3 sphereCenter, float sphereRadius) {
    rayStart -= sphereCenter;
    float a = dot(rayDir, rayDir);
    float b = 2.0 * dot(rayStart, rayDir);
    float c = dot(rayStart, rayStart) - (sphereRadius * sphereRadius);
    float d = b * b - 4.0 * a * c;
    if (d < 0.0) return vec2(-1.0);
    d = sqrt(d);
    return vec2(-b - d, -b + d) / (2.0 * a);
}
vec2 planet_intersection(vec3 rayStart, vec3 rayDir) {
    return sphere_intersection(rayStart, rayDir, PLANET_CENTER, PLANET_RADIUS);
}
vec2 atmosphere_intersection(vec3 rayStart, vec3 rayDir) {
    return sphere_intersection(rayStart, rayDir, PLANET_CENTER, PLANET_RADIUS + ATMOSPHERE_HEIGHT);
}
float phase_rayleigh(float costh) {
    return 3.0 * (1.0 + costh * costh) / (16.0 * PI);
}
float phase_mie(float costh) {
    float g = min(mie_anisotropy_factor, 0.9381);
    float k = 1.55 * g - 0.55 * g * g * g;
    float kcosth = k * costh;
    return (1.0 - k * k) / ((4.0 * PI) * (1.0 - kcosth) * (1.0 - kcosth));
}
float atmosphere_height(vec3 position_world_space) {
    return distance(position_world_space, PLANET_CENTER) - PLANET_RADIUS;
}
float density_rayleigh(float h) { return exp(-max(0.0, h / RAYLEIGH_HEIGHT)); }
float density_mie(float h)      { return exp(-max(0.0, h / MIE_HEIGHT)); }
float density_ozone(float h)    { return max(0.0, 1.0 - abs(h - 25000.0) / 15000.0); }
vec3  density_atmosphere(float h) {
    return vec3(density_rayleigh(h), density_mie(h), density_ozone(h));
}
vec3 integrate_optical_depth(vec3 rayStart, vec3 rayDir) {
    vec2  intersection = atmosphere_intersection(rayStart, rayDir);
    float rayLength    = intersection.y;
    int   sampleCount  = 8;
    float stepSize     = rayLength / float(sampleCount);
    vec3  opticalDepth = vec3(0.0);
    for (int i = 0; i < sampleCount; i++) {
        vec3  localPosition = rayStart + rayDir * (float(i) + 0.5) * stepSize;
        float localHeight   = atmosphere_height(localPosition);
        opticalDepth += density_atmosphere(localHeight) * stepSize;
    }
    return opticalDepth;
}
vec3 absorb(vec3 opticalDepth) {
    return exp(-(
        opticalDepth.x * C_RAYLEIGH * rayleigh_strength +
        opticalDepth.y * C_MIE     * mie_strength +
        opticalDepth.z * C_OZONE   * ozone_strength
    ) * atmosphere_density);
}
vec3 integrate_scattering(vec3 rayStart, vec3 rayDir, float rayLength,
        vec3 lightDir, vec3 lightColor, out vec3 transmittance) {
    float rayHeight = atmosphere_height(rayStart);
    float sampleDistributionExponent = 1.0 + saturate(1.0 - rayHeight / ATMOSPHERE_HEIGHT) * 8.0;
    vec2  intersection = atmosphere_intersection(rayStart, rayDir);
    rayLength = min(rayLength, intersection.y);
    if (intersection.x > 0.0) {
        rayStart  += rayDir * intersection.x;
        rayLength -= intersection.x;
    }
    float costh  = dot(rayDir, lightDir);
    float phaseR = phase_rayleigh(costh);
    float phaseM = phase_mie(costh);
    vec3  opticalDepth = vec3(0.0);
    vec3  rayleigh     = vec3(0.0);
    vec3  mie          = vec3(0.0);
    float prevRayTime  = 0.0;
    for (int i = 0; i < atmosphere_sample_count; i++) {
        float rayTime  = pow(float(i) / float(atmosphere_sample_count), sampleDistributionExponent) * rayLength;
        float stepSize = (rayTime - prevRayTime);
        vec3  localPosition = rayStart + rayDir * rayTime;
        float localHeight   = atmosphere_height(localPosition);
        vec3  localDensity  = density_atmosphere(localHeight);
        opticalDepth += localDensity * stepSize;
        vec3 viewTransmittance  = absorb(opticalDepth);
        vec3 opticalDepthlight  = integrate_optical_depth(localPosition, lightDir);
        vec3 lightTransmittance = absorb(opticalDepthlight);
        rayleigh += viewTransmittance * lightTransmittance * phaseR * localDensity.x * stepSize;
        mie      += viewTransmittance * lightTransmittance * phaseM * localDensity.y * stepSize;
        prevRayTime = rayTime;
    }
    transmittance = absorb(opticalDepth);
    return (rayleigh * C_RAYLEIGH * rayleigh_strength + mie * C_MIE * mie_strength) * lightColor * exposure;
}
float celestial_disc(vec3 eyedir, vec3 dir, float theta_r, float feather) {
    float cos_angle = dot(eyedir, dir);
    float cos_inner = cos(theta_r * (1.0 - feather));
    float cos_outer = cos(theta_r * (1.0 + feather));
    return smoothstep(cos_outer, cos_inner, cos_angle);
}
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 apply_scotopic_grading(vec3 col, float total_light_energy) {
    float night_factor = 1.0 - smoothstep(scotopic_full_energy, scotopic_start_energy, total_light_energy);
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    vec3  night_col = lum * scotopic_tint;
    return mix(col, night_col, night_desaturation * night_factor);
}

float take_cloud_sample(vec3 coord) {
    vec3 shape_wind_offset = vec3(normalize(wind_direction), 0.0).xzy
        * mod(TIME * wind_speed, wind_loop_period);
    vec3 noise_wind_offset = vec3(normalize(noise_wind_direction), 0.0).xzy
        * mod(TIME * wind_speed * noise_wind_speed_mult, wind_loop_period);

    float shape_sample = texture(cloud_shape, ((coord + shape_wind_offset) * cloud_shape_size * 0.01) + cloud_shape_offset).r;
    float noise_sample = texture(cloud_noise, ((coord + noise_wind_offset) * cloud_noise_size * 0.01) + cloud_noise_offset).r;
    float mixed_sample = shape_sample * (1.0 - cloud_noise_factor) + noise_sample * cloud_noise_factor;
    if (hole_in_center) {
        float hole_factor = smoothstep(hole_radius - hole_feather, hole_radius + hole_feather, length(coord.xz));
        mixed_sample *= hole_factor;
    }
    float invert_coverage = 1.0 - coverage;
    return smoothstep(invert_coverage - cloud_smoothness, invert_coverage + cloud_smoothness, mixed_sample);
}
float henyey_greenstein(float a, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * a, 1.5));
}
float light_march(vec3 ray_origin, vec3 ray_direction, vec3 sun_direction) {
    float optical_depth = 0.0;
    float step_size     = light_max_dist / float(light_marches);
    for (float total_dist = 0.0; total_dist < light_max_dist; total_dist += step_size) {
        vec3  coords         = ray_origin + sun_direction * total_dist;
        float density_sample = take_cloud_sample(coords);
        optical_depth += density_sample * step_size;
    }
    return exp(-optical_depth);
}
vec4 ray_march_clouds(vec3 start_point, vec3 direction, vec3 ambient_color, vec2 uv,
        vec3 light_dir, vec3 light_color, float light_energy, float total_light_energy) {
    vec3  scattered_light = vec3(0.0);
    float transmittance = 1.0;
    float march_dist    = cloud_base_march_dist
        / clamp(pow(dot(direction, vec3(0.0, 1.0, 0.0)), cloud_falloff_coeff), 0.05, 1.0);
    float step_size  = (march_dist / float(cloud_marches)) - EPS;
    float cos_theta  = dot(direction, light_dir);
    float phase_cloud = henyey_greenstein(cos_theta, clouds_anisotropy_factor);
    if (apply_stochastic_jitter)
        start_point += direction * (H(uv) - 0.5) * stochastic_jitter_amount;
    vec3 cloud_color = vec3(0.0);
    int  color_samples = 0;
    for (float total_dist = 0.0; total_dist < march_dist; total_dist += step_size) {
        if (transmittance < cloud_transmittance_cutoff) break;

        vec3  coords         = start_point + direction * total_dist;
        float density_sample = take_cloud_sample(coords);
        cloud_color += mix(
            cloud_base_color,
            cloud_overcast_color,
            smoothstep(.4, .8, texture(cloud_color_texture, coords.xz * .01).r)
        );
        color_samples++;
        if (density_sample > 0.01) {
            transmittance *= exp(-density_sample * density_coeff * step_size);
            float luminance = light_march(coords, direction, light_dir);
            scattered_light += density_sample * transmittance * density_coeff
                * step_size * luminance * phase_cloud * light_strength;
        }
    }
    cloud_color /= float(max(color_samples, 1));

    vec3  ambient_term = ambient_color * ambient_light_multiplier;
    vec3  direct_term  = scattered_light * light_color * light_energy;
    vec3  cloud_col    = cloud_color * (ambient_term + direct_term);

    cloud_col = apply_scotopic_grading(cloud_col, total_light_energy);

    transmittance = clamp(1.0 - transmittance, 0.0, 1.0);
    return vec4(cloud_col, transmittance);
}
vec3 jitter_ray_origin(vec3 origin, vec3 direction, vec2 noise_sample, float amount) {
    vec3 up       = abs(direction.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent  = normalize(cross(up, direction));
    vec3 bitangent = normalize(cross(direction, tangent));
    vec2 offset2D = (noise_sample - 0.5) * amount;
    return origin + tangent * offset2D.x + bitangent * offset2D.y;
}
vec3 rainbow(vec3 eyedir, vec3 transmittance, vec4 clouds) {
    vec3 res = vec3(0.0);
    {
        float lower_bound = rainbow_offset - rainbow_width;
        float upper_bound = rainbow_offset + rainbow_width;
        res += texture(rainbow_gradient, vec2(smoothstep(lower_bound, upper_bound, eyedir.x), 0.0)).rgb
            * smoothstep(lower_bound, lower_bound + .02, eyedir.x)
            * smoothstep(upper_bound, upper_bound - .02, eyedir.x)
            * rainbow_opacity * transmittance
            * (behind_clouds ? (1.0 - clouds.a) : 1.0);
    }
    if (double_rainbow) {
        float lower_bound = rainbow_offset * 0.9 - rainbow_width * 1.5;
        float upper_bound = rainbow_offset * 0.9 + rainbow_width * 1.5;
        res += texture(rainbow_gradient, vec2(smoothstep(lower_bound, upper_bound, eyedir.x), 0.0)).rgb
            * smoothstep(lower_bound, lower_bound + .02, eyedir.x)
            * smoothstep(upper_bound, upper_bound - .02, eyedir.x)
            * rainbow_opacity * .15 * transmittance
            * (behind_clouds ? (1.0 - clouds.a) : 1.0);
    }
    return res;
}

float _h(vec3 p) {
    p  = fract(p * vec3(127.1, 311.7,  74.7));
    p += dot(p, p.zxy + 31.41);
    p  = fract(p * vec3(269.5, 183.3, 461.1));
    return fract(dot(p, vec3(1.0, 7.0, 3.0)));
}

vec3 _star_tint(float t) {
    return mix(
        vec3(1.0, 0.75, 0.5),
        mix(vec3(1.0, 0.98, 0.95), vec3(0.75, 0.88, 1.0), t),
        sqrt(t)
    );
}

vec3 _rot_x(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}
vec3 _rot_y(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}
vec3 _rot_z(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c * v.x - s * v.y, s * v.x + c * v.y, v.z);
}

vec3 _star_layer(vec3 dir, float scale, float thresh, float sz_mult, float br_mult) {
    vec3 nc = floor(dir * scale);

    float hd = _h(nc + vec3(71.3, 53.9, 97.1));
    if (hd > thresh) return vec3(0.0);

    float h1 = _h(nc + vec3( 3.7,  0.0,  0.0));
    float h2 = _h(nc + vec3( 0.0, 17.3,  0.0));
    float h3 = _h(nc + vec3( 0.0,  0.0, 31.7));
    float hb = _h(nc + vec3(43.1, 19.3,  7.5));
    float hc = _h(nc + vec3(59.3, 37.1, 23.9));

    vec3 star = normalize(nc + vec3(h1, h2, h3) - 0.5);

    float cos_a = dot(dir, star);
    if (cos_a < 0.9985) return vec3(0.0);

    float d2     = 1.0 - cos_a;
    float r      = stars_size * sz_mult * (hb * 0.6 + 0.4);
    float sigma2 = r * r * 0.5;

    vec3 col = stars_colored ? _star_tint(hc) : vec3(1.0);
    return col * (hb * hb) * br_mult * exp(-d2 / sigma2);
}

vec3 procedural_stars(vec3 dir) {
    vec3 d = normalize(stars_rotation * dir);

    vec3 c = _star_layer(d, 80.0, stars_density * 0.25, 2.2, 1.0);

    vec3 d2 = _rot_y(_rot_x(d, 0.65), 0.52);
    c += _star_layer(d2, 220.0, stars_density * 0.55, 1.0, 0.55);

    vec3 d3 = _rot_x(_rot_z(d, 1.04), 0.70);
    c += _star_layer(d3, 520.0, stars_density, 0.45, 0.2);

    return c * stars_brightness;
}

void sky() {
    if (!enable_shader) {
        if (AT_QUARTER_RES_PASS) {
            COLOR = vec3(1.0);
        } else if (AT_HALF_RES_PASS) {
            COLOR = vec3(0.0);
            ALPHA = 0.0;
        } else {
            COLOR = texture(RADIANCE, EYEDIR).rgb;
        }

    } else if (AT_CUBEMAP_PASS) {
        vec3 transmittance;
        COLOR = integrate_scattering(
            vec3(0.0, elevation, 0.0), EYEDIR, INFINITY,
            LIGHT0_DIRECTION, vec3(1.0, 0.996, 0.98), transmittance
        );

    } else if (AT_QUARTER_RES_PASS) {
        vec3 transmittance;
        integrate_scattering(
            vec3(0.0, elevation, 0.0), EYEDIR, INFINITY,
            LIGHT0_DIRECTION, vec3(1.0, 0.996, 0.98), transmittance
        );
        COLOR = transmittance;

    } else if (AT_HALF_RES_PASS) {
        COLOR = vec3(0.0);
        ALPHA = 0.0;
        if (EYEDIR.y > 0.0) {
            float sun_energy = LIGHT0_ENERGY * smoothstep(-0.02, 0.05, LIGHT0_DIRECTION.y);
            vec3  cloud_light_dir    = LIGHT0_DIRECTION;
            vec3  cloud_light_color  = LIGHT0_COLOR;
            float cloud_light_energy = sun_energy;
            float total_light_energy = sun_energy;

            if (LIGHT1_ENABLED) {
                float moon_energy = LIGHT1_ENERGY * smoothstep(-0.02, 0.05, LIGHT1_DIRECTION.y);
                total_light_energy = sun_energy + moon_energy;
                float moon_weight  = moon_energy / max(sun_energy + moon_energy, 1e-4);
                cloud_light_dir    = normalize(mix(LIGHT0_DIRECTION, LIGHT1_DIRECTION, moon_weight));
                cloud_light_color  = mix(LIGHT0_COLOR, LIGHT1_COLOR, moon_weight);
                cloud_light_energy = mix(sun_energy, moon_energy, moon_weight);
            }

            vec3 lower_plane_point = EYEDIR * (LOWER_PLANE_HEIGHT / EYEDIR.y);
            vec4 clouds = ray_march_clouds(
                lower_plane_point, EYEDIR,
                texture(RADIANCE, EYEDIR).rgb, SCREEN_UV,
                cloud_light_dir, cloud_light_color, cloud_light_energy, total_light_energy
            );
            COLOR.rgb = clouds.rgb;
            ALPHA     = clouds.a;
            ALPHA    *= smoothstep(
                clouds_alpha_lower_bound, clouds_alpha_upper_bound,
                dot(EYEDIR, vec3(0.0, 1.0, 0.0))
            );
        }

    } else {
        vec3 transmittance = QUARTER_RES_COLOR.rgb;
        vec3 radiance      = texture(RADIANCE, EYEDIR).rgb;

        float sun_mask = celestial_disc(EYEDIR, LIGHT0_DIRECTION, LIGHT0_SIZE * 0.5, sun_disc_feather);
        vec3  sundisc  = vec3(sun_mask) * transmittance * sundisc_intensity;

        vec3 moondisc = vec3(0.0);
        if (LIGHT1_ENABLED) {
            float moon_mask = celestial_disc(EYEDIR, LIGHT1_DIRECTION, LIGHT1_SIZE * 0.5, moon_disc_feather);
            moondisc = vec3(moon_mask) * transmittance * LIGHT1_COLOR * moon_disc_intensity;
        }

        vec3  stars = vec3(0.0);
        float night = 1.0;
        if (dim_stars_at_day) {
            night = smoothstep(0.3, -0.1, dot(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)));
        }
        if (!dim_stars_at_day || night > 0.01) {
            stars = procedural_stars(EYEDIR) * transmittance * night;
        }

        COLOR = radiance + sundisc + moondisc + stars;

        if (EYEDIR.y > 0.0 && use_cirrus) {
            float sun_energy = LIGHT0_ENERGY * smoothstep(-0.02, 0.05, LIGHT0_DIRECTION.y);
            vec3  cirrus_light_color  = LIGHT0_COLOR;
            float cirrus_light_energy = sun_energy;
            float cirrus_total_energy = sun_energy;

            if (LIGHT1_ENABLED) {
                float moon_energy = LIGHT1_ENERGY * smoothstep(-0.02, 0.05, LIGHT1_DIRECTION.y);
                cirrus_total_energy = sun_energy + moon_energy;
                float moon_weight   = moon_energy / max(sun_energy + moon_energy, 1e-4);
                cirrus_light_color  = mix(LIGHT0_COLOR, LIGHT1_COLOR, moon_weight);
                cirrus_light_energy = mix(sun_energy, moon_energy, moon_weight);
            }

            vec2  coords = EYEDIR.xz / EYEDIR.y;
            float cirrus_mask_val = smoothstep(
                cirrus_mask_treshold - cirrus_mask_feather,
                cirrus_mask_treshold + cirrus_mask_feather,
                texture(cirrus_mask_texture, coords * cirrus_mask_scale).r
            );
            vec2 cirrus_distortion = texture(
                cirrus_distortion_texture,
                coords * cirrus_distortion_scale + cirrus_distortion_offset
            ).xy * cirrus_distortion_strength;
            float cirrus = smoothstep(
                cirrus_treshold - cirrus_feather,
                cirrus_treshold + cirrus_feather,
                texture(
                    cirrus_texture,
                    (coords * cirrus_scale + cirrus_offset) * cirrus_squish + cirrus_distortion
                ).r
            ) * cirrus_mask_val * cirrus_opacity * smoothstep(.5, 3.0, length(coords));

            vec3 cirrus_ambient_term = radiance * ambient_light_multiplier;
            vec3 cirrus_direct_term  = cirrus_light_color * cirrus_light_energy;
            vec3 cirrus_col          = cirrus * transmittance * (cirrus_ambient_term + cirrus_direct_term);
            cirrus_col = apply_scotopic_grading(cirrus_col, cirrus_total_energy);
            COLOR += cirrus_col;
        }

        vec4 clouds = HALF_RES_COLOR;
        COLOR = mix(COLOR, clouds.rgb, clouds.a);

        if (use_rainbow) COLOR += rainbow(EYEDIR, transmittance, clouds);

        if (use_debanding) COLOR += (rand(SKY_COORDS) - 0.5) * 0.001;
    }
}
