shader_type spatial;
render_mode cull_back, world_vertex_coords;
#include "res://nature_pack/shaders/foliage_deform.gdshaderinc"
void vertex() {
    VERTEX += foliage_displacement(VERTEX, UV2, MODEL_MATRIX[3].xyz);
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 0.95;
    SPECULAR = 0.12;
}
