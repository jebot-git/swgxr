shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 outline_color : source_color = vec4(0.95,0.72,0.12,1.0);
void fragment() {
 float rim=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.5);
 ALBEDO=outline_color.rgb*1.3;
 ALPHA=smoothstep(.12,.8,rim)*outline_color.a;
}
