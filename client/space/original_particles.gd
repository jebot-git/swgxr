extends Node3D
## Bounded GPU playback for original one-shot space effects. Source curves and
## textures are retained; simulation/rendering stay in Godot's native GPU path.
const Curves=preload("res://combat/source_effect.gd")
static var additive_shader:Shader
var remaining:=0.0
var persistent:=false
func curve_image(definition:Dictionary,channels:Array)->ImageTexture:
	var image:=Image.create(256,1,false,Image.FORMAT_RGBAF)
	for i in range(256):
		var color:=Color(0,0,0,1)
		for k in channels.size():color[k]=Curves.value(definition[channels[k]],float(i)/255)
		image.set_pixel(i,0,color)
	return ImageTexture.create_from_image(image)
func play(source:Dictionary,assets:RefCounted,keep:=false)->void:
	persistent=keep
	var budget:=4096
	for d:Dictionary in source.get("emitters",[]):
		if not d.get("visible",false) or budget<=0:continue
		var c:Dictionary=d.curves
		var node:=GPUParticles3D.new();node.emitting=false
		node.amount=mini(budget,clampi(int(d.count_max) if d.one_shot else ceili(Curves.value(c.rate,0)*float(d.emitter_life_max)),1,512));budget-=node.amount
		node.lifetime=maxf(.01,Curves.value(c.life,0));node.one_shot=not persistent;node.explosiveness=1.0 if d.one_shot else 0.0
		node.local_coords=true;node.visibility_aabb=AABB(Vector3(-200,-200,-200),Vector3(400,400,400));node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var process:=ShaderMaterial.new();process.shader=preload("res://space/original_particles_process.gdshader")
		process.set_shader_parameter("speed",Curves.value(c.speed,0));process.set_shader_parameter("spread",deg_to_rad(Curves.value(c.spread,0)))
		var distance:Array=c.distance.points[0];process.set_shader_parameter("distance_range",Vector2(float(distance[1])-float(distance[3]),float(distance[1])+float(distance[2])))
		process.set_shader_parameter("speed_curve",curve_image(d,["speed_scale"]))
		node.process_material=process
		var draw:=ShaderMaterial.new();draw.shader=preload("res://space/original_particles_draw.gdshader")
		if d.material.get("additive",false):
			if additive_shader==null:
				additive_shader=Shader.new();additive_shader.code=draw.shader.code.replace("render_mode unshaded", "render_mode blend_add,unshaded")
			draw.shader=additive_shader
		draw.set_shader_parameter("velocity_aligned",int(d.orientation)!=0)
		draw.set_shader_parameter("original_texture",assets.texture(d.material.texture));draw.set_shader_parameter("sizes",curve_image(d,["length" if d.linked_size else "width","length","alpha"]))
		var color_image:=Image.create(256,1,false,Image.FORMAT_RGBAF)
		for i in range(256):color_image.set_pixel(i,0,Color(Curves.value(d.color,float(i)/255,1),Curves.value(d.color,float(i)/255,2),Curves.value(d.color,float(i)/255,3),1))
		draw.set_shader_parameter("colors",ImageTexture.create_from_image(color_image))
		var mesh:=QuadMesh.new();mesh.size=Vector2.ONE;mesh.material=draw;node.draw_pass_1=mesh
		node.position=Vector3(Curves.value(c.translation_x,0),Curves.value(c.translation_y,0),-Curves.value(c.translation_z,0))
		node.basis=Basis.from_euler(Vector3(-Curves.value(c.rotation_x,0),-Curves.value(c.rotation_y,0),Curves.value(c.rotation_z,0))*TAU)
		add_child(node);node.emitting=true;remaining=maxf(remaining,node.lifetime+float(d.emitter_life_max)+1)
func _process(delta:float)->void:
	remaining-=delta
	if remaining<=0 and not persistent:queue_free()
