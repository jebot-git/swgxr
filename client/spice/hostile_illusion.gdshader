shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
void fragment() {
 float rim=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
 ALBEDO=vec3(.9,.015,.008);
 ALPHA=.06+rim*.35;
}
