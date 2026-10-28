shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rough_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tee_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 rough_color : source_color = vec3(0.02,0.231,0.141);
uniform vec3 tee_color : source_color = vec3(0.459,0.576,0.294);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float grain=dot(texture(rough_texture,world_position.xz/2.0).rgb,vec3(.2126,.7152,.0722))/.246;
 vec3 rough=rough_color*mix(1.0,grain,.6);
 vec3 tee=texture(tee_texture,UV*vec2(4.5,6.0)).rgb*tee_color;
 vec2 edges=min(UV,vec2(1.0)-UV)*vec2(9.0,12.0);
 float blend=smoothstep(0.0,.65,min(edges.x,edges.y));
 ALBEDO=mix(rough,tee,blend);
 ROUGHNESS=1.0; SPECULAR=.5;
}
