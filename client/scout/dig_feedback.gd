extends CPUParticles3D
## Local input feedback; rewards and cooldowns still come from CoreCU.
func emit_at(ground:Vector3)->void:
	global_position=ground+Vector3.UP*.025
	local_coords=false
	amount=18;lifetime=.65;one_shot=true;explosiveness=1.0
	emission_shape=CPUParticles3D.EMISSION_SHAPE_SPHERE;emission_sphere_radius=.045
	direction=Vector3.UP;spread=65;gravity=Vector3(0,-2,0)
	initial_velocity_min=.3;initial_velocity_max=.65
	scale_amount_min=.6;scale_amount_max=1.5
	var grain:=SphereMesh.new();grain.radius=.012;grain.height=.024;grain.radial_segments=6;grain.rings=3
	var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	grain.material=material;mesh=grain
	var ramp:=Gradient.new();ramp.colors=PackedColorArray([Color(.45,.30,.13,.9),Color(.32,.22,.12,0)])
	color_ramp=ramp
	emitting=true;restart()
	get_tree().create_timer(lifetime+.15).timeout.connect(queue_free)
