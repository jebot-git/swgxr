extends Node3D
## Original ClientNebula density/radius rules and original gas textures. The
## random layout is deterministic here; it is not a bit-identical SWG RNG stream.
var assets=preload("res://combat/original_assets.gd").new()
func build(fields:Array)->void:
	assets.directory=ProjectSettings.globalize_path("res://../runtime/assets/space_effects")
	if not assets.load_catalog():return
	var rng:=RandomNumberGenerator.new();rng.seed=0x535747
	for field:Dictionary in fields:
		var shader_index:=str(int(field.get("shaderIndex",0)))
		var textures:Dictionary=assets.catalog.nebula.get(shader_index,{})
		var original:Dictionary=textures.get("MAIN",{})
		if original.is_empty():continue
		var radius:=float(field.radius);var center:=Vector3(field.x,field.y,-field.z)
		# Original UI exposes a global density preference; use its bounded high detail value.
		var count:=clampi(int(float(field.density)*float(field.density)*40),1,100)
		for i in range(count):
			var direction:=Vector3(rng.randfn(),rng.randfn(),rng.randfn()).normalized()
			var distance:=rng.randf()*radius;var low:float=(radius-distance)*.05
			var size:=rng.randf_range(low,maxf(low+1,low*20))
			var material:=ShaderMaterial.new();material.shader=preload("res://space/nebula_add.gdshader") if shader_index=="0" else preload("res://space/nebula.gdshader")
			material.set_shader_parameter("original_texture",assets.texture(str(original.path)))
			material.set_shader_parameter("style",rng.randi_range(0,3))
			var prefix:="facing" if rng.randf()<float(field.facingPercent) else "oriented"
			var color:=Color(field[prefix+"R"],field[prefix+"G"],field[prefix+"B"],field[prefix+"A"])
			var ramp:=Color(field[prefix+"RampR"],field[prefix+"RampG"],field[prefix+"RampB"],field[prefix+"RampA"])
			material.set_shader_parameter("tint",color.lerp(ramp,rng.randf()))
			var node:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2.ONE*size*2;node.mesh=mesh;node.material_override=material
			node.position=center+direction*distance;node.rotation=Vector3(rng.randf(),rng.randf(),rng.randf())*TAU
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
