extends Node3D
## Source-driven SWG quad particle playback; no synthetic replacement textures.
var assets: RefCounted
var camera: Camera3D
var emitters: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var age := 0.0
var persistent := false
var duration := 10.0
var rng := RandomNumberGenerator.new()

func configure(source: Dictionary, resources: RefCounted, eye: Camera3D, keep := false, lifetime := 10.0) -> void:
	assets = resources; camera = eye; persistent = keep; duration = lifetime
	rng.randomize()
	for definition in source.get("emitters",[]):
		if not definition.visible: continue
		var timing: Array = definition.timing
		emitters.append({"definition":definition,"emitted":false,"carry":0.0,"delay":rng.randf_range(timing[0],timing[1]),"life":rng.randf_range(definition.emitter_life_min,definition.emitter_life_max)})

static func value(curve: Dictionary, t: float, channel := 1) -> float:
	var points: Array = curve.points
	if points.is_empty(): return 0
	var a: Array = points[0]
	for i in range(1,points.size()):
		var b: Array = points[i]
		if float(b[0]) >= t:
			return lerpf(float(a[channel]),float(b[channel]),clampf((t-float(a[0]))/maxf(0.000001,float(b[0])-float(a[0])),0,1))
		a = b
	return float(a[channel])

func _process(delta: float) -> void:
	age += delta
	for emitter in emitters:
		var d: Dictionary = emitter.definition
		var t := age-float(emitter.delay)
		if t<0 or (not persistent and age>duration): continue
		var normalized := clampf(t/maxf(0.001,emitter.life),0,1)
		if d.one_shot and not emitter.emitted:
			for i in range(mini(128,rng.randi_range(d.count_min,d.count_max))): emit_particle(d,normalized)
			emitter.emitted = true
		elif not d.one_shot and t <= float(emitter.life):
			emitter.carry += value(d.curves.rate,normalized)*delta
			var count := mini(128,int(emitter.carry))
			emitter.carry -= count
			for i in range(count): emit_particle(d,normalized)
	for i in range(particles.size()-1,-1,-1):
		var p := particles[i]
		p.age += delta
		if p.age >= p.life:
			p.mesh.queue_free(); particles.remove_at(i); continue
		var t: float = p.age/p.life
		var d: Dictionary = p.definition
		p.position += p.velocity*value(d.speed_scale,t)*delta
		p.velocity.y -= 9.8*float(p.weight)*delta
		var point: Vector3 = global_transform*p.position if d.local_space else p.position
		p.mesh.global_position = point
		var width := value(d.length,t) if d.linked_size else value(d.width,t)
		p.mesh.mesh.size = Vector2(maxf(0.00001,width),maxf(0.00001,value(d.length,t)))
		var color := Color(value(d.color,t,1),value(d.color,t,2),value(d.color,t,3),clampf(value(d.alpha,t),0,1))
		p.material.albedo_color = color
		var spin := float(p.spin)+value(d.rotation,t)*TAU
		if is_instance_valid(camera):
			if int(d.orientation)==0:
				p.mesh.global_basis = camera.global_basis * Basis(Vector3.FORWARD,spin)
			else:
				var up: Vector3 = global_basis*p.velocity if d.local_space else p.velocity
				if up.length_squared()<0.000001: up = -global_basis.z
				up = up.normalized()
				var view := (camera.global_position-point).normalized()
				var side := up.cross(view).normalized()
				if side.length_squared()>0.1: p.mesh.global_basis = Basis(side,up,side.cross(up))
	if not persistent and particles.is_empty() and age>duration: queue_free()

func sample_value(curve: Dictionary, t: float) -> float:
	return value(curve,t)+rng.randf_range(-maxf(0,value(curve,t,3)),maxf(0,value(curve,t,2)))

func emit_particle(d: Dictionary, t: float) -> void:
	if particles.size() >= 512: return
	var c: Dictionary = d.curves
	var translation := Vector3(value(c.translation_x,t),value(c.translation_y,t),-value(c.translation_z,t))
	var rotation_basis := Basis.from_euler(Vector3(-value(c.rotation_x,t),-value(c.rotation_y,t),value(c.rotation_z,t))*TAU)
	var spread := deg_to_rad(sample_value(c.spread,t))
	var azimuth := rng.randf_range(-PI,PI)
	var direction := Vector3(sin(spread)*cos(azimuth),cos(spread),sin(spread)*sin(azimuth))
	if int(d.direction)==0: direction = Vector3(cos(azimuth),0,sin(azimuth))
	direction = rotation_basis*direction
	var ring := rng.randf()*TAU
	var shape := rotation_basis*Vector3(cos(ring),0,sin(ring))*value(c.shape_size,t)
	var point := translation+shape+direction*value(c.distance,t)
	var velocity := direction*sample_value(c.speed,t)
	if not d.local_space:
		point = global_transform*point
		velocity = global_basis*velocity
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if d.material.get("additive",false): material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = assets.texture(d.material.texture)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var spin := rng.randf()*TAU if d.random_rotation else 0.0
	particles.append({"definition":d,"mesh":mesh,"material":material,"age":0.0,"life":maxf(0.01,sample_value(c.life,t)),"weight":sample_value(c.weight,t),"position":point,"velocity":velocity,"spin":spin})

func reset_playback() -> void:
	# Projectile visuals retain their source definitions across pool reuse.
	age = 0.0
	for particle_state in particles:
		if is_instance_valid(particle_state.mesh): particle_state.mesh.queue_free()
	particles.clear()
	for emitter in emitters:
		emitter.emitted = false
		emitter.carry = 0.0
		var definition: Dictionary = emitter.definition
		emitter.delay = rng.randf_range(definition.timing[0],definition.timing[1])
		emitter.life = rng.randf_range(definition.emitter_life_min,definition.emitter_life_max)
