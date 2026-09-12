shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 fabric_color : source_color = vec4(0.06,0.16,0.45,1.0);
uniform vec4 fabric_color_b : source_color = vec4(1.0,1.0,1.0,1.0);
uniform float checker_columns = 8.0;
uniform float checker_rows = 5.0;
uniform bool distant_mode = false;
uniform float wind_speed = 3.0;
uniform float phase_offset = 0.0;

void vertex() {
    if (distant_mode) {
        float u = UV.x;
        float bend = mix(-2.4,-0.12,wind_speed/(wind_speed+1.4))*u;
        float span = 0.55*u;
        VERTEX.x = 0.015 + span * sin(bend) / min(-0.0001,bend);
        VERTEX.y = 2.07+UV.y*0.35 + span*(1.0-cos(bend))/min(-0.0001,bend);
        float flap = min(wind_speed/5.0,1.0)*0.025*u*u;
        VERTEX.z = flap*(sin(u*11.0-TIME*(2.0+wind_speed*.6)+phase_offset)+0.35*sin(UV.y*8.0+u*16.0-TIME*4.3));
    }
}

void fragment() {
    float edge = min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
    float hem = smoothstep(0.007,0.019,edge);
    float checker = mod(floor(UV.x*checker_columns)+floor(UV.y*checker_rows),2.0);
    vec3 checkered = mix(fabric_color.rgb,fabric_color_b.rgb,checker);
    vec3 color = checkered * mix(0.65,1.0,hem);
    // UV-bound seams move with the cloth rather than floating over it.
    float seam = 1.0-smoothstep(0.001,0.003,abs(edge-0.023));
    float along = (UV.y<0.05 || UV.y>0.95) ? UV.x : UV.y;
    float dash = 1.0-step(0.56,fract(along*62.0));
    float footprint = max(length(dFdx(UV)),length(dFdy(UV)));
    float detailed = 1.0-smoothstep(0.008,0.025,footprint);
    color = mix(color,color*0.68,seam*dash*detailed*0.6);
    float weave = sin(UV.x*1900.0)*sin(UV.y*1200.0)*0.018*detailed;
    ALBEDO = color*(1.0+weave);
    ROUGHNESS = 0.88;
    SPECULAR = 0.23;
    METALLIC = 0.0;
    if (distant_mode) {
        NORMAL = normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
    }
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
