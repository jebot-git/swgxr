extends CompositorEffect
## Camera-local per-view color processing. Never samples or moves tracked poses.
const SOURCE:="""
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform image2D scene_color;
layout(push_constant,std430) uniform Parameters {
 vec4 raster;
 vec4 modes;
 vec4 tint;
 vec4 pulse;
} p;
float noise(vec2 v) { return fract(sin(dot(v,vec2(12.9898,78.233)))*43758.5453); }
void main() {
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 if(any(greaterThanEqual(pixel,ivec2(p.raster.xy)))) return;
 vec4 source=imageLoad(scene_color,pixel);
 vec3 color=source.rgb;
 float luminance=dot(color,vec3(.2126,.7152,.0722));
 color=mix(color,vec3(luminance),p.modes.x);
 if(p.modes.y>0.0) {
  vec3 shift=.5+.5*cos(vec3(0.0,2.094395,4.18879)+p.modes.w*.42);
  vec3 transformed=mix(color.gbr,color.brg,.5+.5*sin(p.modes.w*.29));
  color=mix(color,transformed*(.5+shift*1.1),p.modes.y);
 }
 color=mix(color,color*p.tint.rgb,p.tint.a);
 float grain=(noise(vec2(pixel)+floor(p.modes.w*12.0))-0.5)*p.modes.z;
 color=max(vec3(0.0),color+grain);
 vec2 uv=(vec2(pixel)+.5)/p.raster.xy;
 float edge=smoothstep(.4,1.0,length((uv-.5)*2.0));
 color=mix(color,vec3(.48,.035,.025),p.pulse.y*edge);
 color*=1.0-p.pulse.x;
 imageStore(scene_color,pixel,vec4(color,source.a));
}
"""
var rd:RenderingDevice
var shader:RID
var pipeline:RID
var mutex:=Mutex.new()
var parameters:=PackedFloat32Array([0,0,0,0,1,1,1,0,0,0,0,0])
var failed:=false
func _init()->void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd=RenderingServer.get_rendering_device();enabled=false
func attach(camera:Camera3D)->void:
	var compositor:Compositor=camera.compositor.duplicate() if camera.compositor!=null else Compositor.new()
	var effects:Array[CompositorEffect]=compositor.compositor_effects.duplicate();effects.append(self);compositor.compositor_effects=effects;camera.compositor=compositor
func set_policy(value:Dictionary)->void:
	var tint:Color=value.tint
	mutex.lock()
	parameters=PackedFloat32Array([value.monochrome,value.psychedelic,value.noise,value.elapsed,tint.r,tint.g,tint.b,value.tint_amount,value.darkness,value.pain,0,0])
	mutex.unlock()
	enabled=value.monochrome>0 or value.psychedelic>0 or value.noise>0 or value.tint_amount>0 or value.darkness>0 or value.pain>0
func prepare()->bool:
	if rd==null or failed:return false
	if pipeline.is_valid():return true
	var source:=RDShaderSource.new();source.language=RenderingDevice.SHADER_LANGUAGE_GLSL;source.source_compute=SOURCE
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():failed=true;push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	return pipeline.is_valid()
func _render_callback(kind:int,data:RenderData)->void:
	if kind!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not prepare():return
	var buffers:RenderSceneBuffersRD=data.get_render_scene_buffers()
	if buffers==null:return
	var size:=buffers.get_internal_size()
	if size.x<=0 or size.y<=0:return
	mutex.lock();var values:=parameters.duplicate();mutex.unlock()
	var push:=PackedFloat32Array([size.x,size.y,0,0]);push.append_array(values)
	for view in range(buffers.get_view_count()):
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=0;uniform.add_id(buffers.get_color_layer(view))
		var set:=UniformSetCacheRD.get_cache(shader,0,[uniform])
		var commands:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(commands,pipeline);rd.compute_list_bind_uniform_set(commands,set,0)
		rd.compute_list_set_push_constant(commands,push.to_byte_array(),push.size()*4);rd.compute_list_dispatch(commands,ceili(size.x/8.0),ceili(size.y/8.0),1);rd.compute_list_end()
func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE and rd!=null and shader.is_valid():rd.free_rid(shader)
