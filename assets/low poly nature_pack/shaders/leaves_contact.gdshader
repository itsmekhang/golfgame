shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap;
#include "res://nature_pack/shaders/foliage_deform.gdshaderinc"
void vertex() {
    VERTEX += foliage_displacement(VERTEX, UV2, MODEL_MATRIX[3].xyz);
}
void fragment() {
    ALBEDO = COLOR.rgb;
    if (!FRONT_FACING) { ALBEDO *= vec3(0.93, 1.02, 0.89); }
    ROUGHNESS = 0.64;
    SPECULAR = 0.30;
}
