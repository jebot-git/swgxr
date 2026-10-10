shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,fog_disabled;
uniform sampler2D original_texture:source_color;
uniform vec4 tint:source_color=vec4(1.0);
uniform int style=0;
void fragment(){
 vec2 tile=vec2(float(style==1 || style==2),float(style>=2));
 vec4 gas=texture(original_texture,(UV+tile)*.5);
 ALBEDO=gas.rgb*tint.rgb;ALPHA=gas.a*tint.a;
}
