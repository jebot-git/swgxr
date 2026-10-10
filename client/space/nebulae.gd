extends Node3D
## ClientNebula density, paired facing quads, colour and orientation rules.
## Layout randomness is deterministic here, not SWG's global random stream.
var assets=preload("res://combat/original_assets.gd").new()
func build(fields:Array,lights:Array=[])->void:
	assets.directory=ProjectSettings.globalize_path("res://../runtime/assets/space_effects")
	if not assets.load_catalog():return
	var light_direction:=Vector3.ZERO;var intensity:=-1.0
	for light:Dictionary in lights:
		var v:Array=light.values;var brightness:=float(v[1])+float(v[2])+float(v[3])
		if brightness>=intensity:intensity=brightness;light_direction=Vector3(v[8],v[9],-v[10]).normalized()
	var rng:=RandomNumberGenerator.new();rng.seed=0x535747
	for field:Dictionary in fields:
		if float(field.density)<=0:continue
		var shader_index:=str(int(field.get("shaderIndex",0)))
		var textures:Dictionary=assets.catalog.nebula.get(shader_index,{})
		var original:Dictionary=textures.get("MAIN",{})
		if original.is_empty():continue
		var radius:=float(field.radius);var center:=Vector3(field.x,field.y,-field.z)
		var count:=clampi(int(float(field.density)*float(field.density)*40),1,100)
		var positions:Array[Vector3]=[]
		for i in range(count):
			var style:=rng.randi_range(0,3)
			var direction:=Vector3(rng.randfn(),rng.randfn(),rng.randfn()).normalized()
			var distance:=rng.randf()*.9*radius;var point:=center+direction*distance
			if positions.any(func(p:Vector3):return p.distance_squared_to(point)<10):continue
			positions.append(point)
			var low:float=(radius-distance)*.05
			var size:=rng.randf_range(low,maxf(low+1,low*20))
			var facing:=rng.randf()<float(field.facingPercent)
			var prefix:="facing" if facing else "oriented"
			var color:=Color(field[prefix+"R"],field[prefix+"G"],field[prefix+"B"],field[prefix+"A"])
			var ramp:=Color(field[prefix+"RampR"],field[prefix+"RampG"],field[prefix+"RampB"],field[prefix+"RampA"])
			var dark:=clampf(light_direction.dot(direction),0,1)*distance/maxf(.001,radius*.9)
			var colors:Array[Color]=[]
			for corner in range(4):colors.append(color.lerp(ramp,rng.randf()).lerp(Color.BLACK,dark))
			var rotation:=Vector3(rng.randfn(),rng.randfn(),rng.randfn()).normalized()*rng.randf()*TAU
			for axis:Vector3 in ([Vector3.UP,Vector3.RIGHT] if facing else [Vector3.ZERO]):
				var material:=ShaderMaterial.new();material.shader=preload("res://space/nebula_add.gdshader") if shader_index=="0" else preload("res://space/nebula.gdshader")
				material.set_shader_parameter("original_texture",assets.texture(str(original.path)))
				material.set_shader_parameter("style",style);material.set_shader_parameter("corner_colors",colors)
				material.set_shader_parameter("facing_axis",axis)
				var node:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2.ONE*size*2;node.mesh=mesh;node.material_override=material
				node.position=point
				if not facing:node.basis=Basis(Vector3.UP,-rotation.x)*Basis(Vector3.RIGHT,-rotation.y)*Basis(Vector3.BACK,rotation.z)
				# Shader-facing geometry can rotate outside the original flat AABB.
				node.custom_aabb=AABB(Vector3.ONE*-size*1.5,Vector3.ONE*size*3)
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
