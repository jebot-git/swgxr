extends RefCounted
## Owner-only native event pulses. HAM costs and passive regen are not events.
const ATTACK := 0.14
const DURATION := 0.9
var initialized := false
var sequence := {"damage":0,"heal":0}
var elapsed := {"damage":DURATION,"heal":DURATION}
var mesh: MeshInstance3D
var material: ShaderMaterial
func configure(camera: Camera3D) -> void:
	mesh=MeshInstance3D.new();mesh.name="LocalVitalFeedback"
	var quad:=QuadMesh.new();quad.size=Vector2.ONE;mesh.mesh=quad
	material=ShaderMaterial.new();material.shader=preload("res://combat/vital_effect.gdshader")
	material.render_priority=120;mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.ignore_occlusion_culling=true;mesh.extra_cull_margin=4096;mesh.position.z=-0.5
	camera.add_child(mesh);mesh.visible=false
func reset() -> void:
	initialized=false;sequence={"damage":0,"heal":0};elapsed={"damage":DURATION,"heal":DURATION}
	if is_instance_valid(mesh):mesh.visible=false
func observe(value: Dictionary) -> void:
	if not value.has_all(["damage","heal","age_seconds"]):return
	var age:=float(value.age_seconds)
	if not is_finite(age) or age<0:return
	for kind in ["damage","heal"]:
		var incoming:=int(value[kind])
		if incoming<0:continue
		if initialized and incoming>int(sequence[kind]) and age<2.0:
			# A burst extends an existing pulse without stacking opacity or strobing.
			elapsed[kind]=minf(float(elapsed[kind]),ATTACK) if float(elapsed[kind])<DURATION else 0.0
		sequence[kind]=maxi(int(sequence[kind]),incoming)
	initialized=true
func strength(kind: String) -> float:
	var t:=float(elapsed[kind])
	if t<ATTACK:return smoothstep(0,ATTACK,t)
	return 1.0-smoothstep(ATTACK,DURATION,t)
func advance(delta: float) -> void:
	for kind in ["damage","heal"]:elapsed[kind]=minf(DURATION,float(elapsed[kind])+clampf(delta,0,0.1))
	if not is_instance_valid(mesh):return
	mesh.visible=float(elapsed.damage)<DURATION or float(elapsed.heal)<DURATION
	material.set_shader_parameter("damage_amount",strength("damage"))
	material.set_shader_parameter("heal_amount",strength("heal"))
