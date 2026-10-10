shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,fog_disabled;
uniform sampler2D original_texture:source_color;
uniform sampler2D sizes;
uniform sampler2D colors;
uniform bool velocity_aligned=false;
varying float age;
void vertex(){
 age=INSTANCE_CUSTOM.y;
 VERTEX.xy*=texture(sizes,vec2(age,.5)).rg;
 if(velocity_aligned){
  vec3 up=normalize(MODEL_MATRIX[1].xyz);vec3 view=normalize(INV_VIEW_MATRIX[3].xyz-MODEL_MATRIX[3].xyz);
  vec3 side=normalize(cross(up,view));
  MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(side,0),vec4(up,0),vec4(cross(side,up),0),MODEL_MATRIX[3]);
 }else MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 vec4 original=texture(original_texture,UV);
 ALBEDO=original.rgb*texture(colors,vec2(age,.5)).rgb;
 ALPHA=original.a*texture(sizes,vec2(age,.5)).b;
}
