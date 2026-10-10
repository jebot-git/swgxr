uniform sampler2D original_texture:source_color,filter_linear_mipmap;
uniform vec4 corner_colors[4]:source_color;
uniform vec3 facing_axis=vec3(0.0);
uniform int style=0;
varying float view_alpha;
void vertex(){
 vec3 center=MODEL_MATRIX[3].xyz;
 vec3 to_eye=MAIN_CAM_INV_VIEW_MATRIX[3].xyz-center;
 vec3 direction=normalize(to_eye+vec3(0.0000001));
 vec3 normal=normalize(MODEL_MATRIX[2].xyz);
 float facing_alpha=1.0;
 if(length(facing_axis)>0.0){
  vec3 axis=normalize(mat3(MODEL_MATRIX)*facing_axis);
  vec3 facing=direction+MAIN_CAM_INV_VIEW_MATRIX[2].xyz;
  vec3 right=cross(axis,facing);
  float usable=step(.00001,length(right))*step(.00001,length(to_eye));
  right=normalize(right+vec3(.0000001));normal=normalize(facing+vec3(.0000001));
  vec3 up=normalize(cross(normal,right));
  VERTEX=(VIEW_MATRIX*vec4(center+right*VERTEX.x+up*VERTEX.y,1.0)).xyz;
  NORMAL=(VIEW_MATRIX*vec4(normal,0.0)).xyz;
  float alignment=1.0-abs(dot(axis,direction));
  facing_alpha=alignment*alignment*usable*step(0.0,dot(normal,direction));
 }else{
  VERTEX=(MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
  NORMAL=normalize(MODELVIEW_NORMAL_MATRIX*NORMAL);
 }
 view_alpha=abs(dot(normal,direction))*facing_alpha;
}
void fragment(){
 vec2 tile=vec2(float(style==1 || style==2),float(style>=2));
 vec4 gas=texture(original_texture,(UV+tile)*.5);
 vec4 tint=mix(mix(corner_colors[0],corner_colors[3],UV.x),mix(corner_colors[1],corner_colors[2],UV.x),UV.y);
 ALBEDO=gas.rgb*tint.rgb;ALPHA=gas.a*tint.a*view_alpha;
}
