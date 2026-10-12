shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,fog_disabled;
uniform sampler2D original_texture:source_color,filter_linear_mipmap;
uniform sampler2D sizes;
uniform sampler2D colors;
uniform bool velocity_aligned=false;
uniform int atlas_columns=1;
uniform int frame_start=0;
uniform int frame_end=0;
uniform float frames_per_second=-1.0;
uniform vec3 fixed_world_axis=vec3(0.0);
varying float age;
varying float elapsed;
void vertex(){
 age=INSTANCE_CUSTOM.y;elapsed=INSTANCE_CUSTOM.x;
 VERTEX.xy*=texture(sizes,vec2(age,.5)).rg;
 if(velocity_aligned){
  vec3 up=length(fixed_world_axis)>.5?normalize(fixed_world_axis):normalize(MODEL_MATRIX[1].xyz);vec3 view=normalize(MAIN_CAM_INV_VIEW_MATRIX[3].xyz-MODEL_MATRIX[3].xyz);
  vec3 side=normalize(cross(up,view));
  MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(side,0),vec4(up,0),vec4(cross(side,up),0),MODEL_MATRIX[3]);
 }else MODELVIEW_MATRIX=VIEW_MATRIX*mat4(MAIN_CAM_INV_VIEW_MATRIX[0],MAIN_CAM_INV_VIEW_MATRIX[1],MAIN_CAM_INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
 int count=max(1,frame_end-frame_start+1);
 int frame=frame_start+(frames_per_second<0.0?min(count-1,int(age*float(count))):int(elapsed*frames_per_second)%count);
 vec2 atlas_uv=(UV+vec2(float(frame%atlas_columns),float(frame/atlas_columns)))/float(atlas_columns);
 vec4 original=texture(original_texture,atlas_uv);
 ALBEDO=original.rgb*texture(colors,vec2(age,.5)).rgb;
 ALPHA=original.a*texture(sizes,vec2(age,.5)).b;
}
