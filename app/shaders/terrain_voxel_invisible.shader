shader_type spatial;
// Invisible-wall material: geometry still meshes (and its collision AABBs still
// generate physics) but nothing is drawn — ALPHA is forced to 0. The `emission`
// / `emission_energy` uniforms are declared but unused so BuildNode's material
// setup (prepare_materials / set_glow / set_highlight) can get/set them without
// hitting a missing param.
render_mode blend_mix, unshaded, depth_draw_alpha_prepass;

uniform vec4 emission : hint_color;
uniform float emission_energy;

void fragment() {
  ALPHA = 0.0;
}
