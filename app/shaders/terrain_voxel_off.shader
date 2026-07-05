// Discards every fragment: applied to the live terrain's materials while a
// saved animation frame is displayed by frame mesh instances instead.
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,unshaded;

void fragment() {
  discard;
}
