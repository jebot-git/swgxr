extends Node3D
## Bounded native presentation, compiled once from the user's original effect assets.
## Deliberately approximates source emitter graphs; this is not original graph playback.
const MAX_SOURCE_PROGRAMS := 32
const MAX_COMPILED_STYLES := 48
var assets: RefCounted
var camera: Camera3D
var batch: Node3D
var styles: Dictionary = {}
var compiled_style_count := 0
var disabled_lights := 0
var rejected_sources := 0
var view_pose := Transform3D.IDENTITY

static func shared(owner_node: Node, resources: RefCounted, eye: Camera3D) -> Node3D:
	# The headset and desktop mirror can share World3D across different viewports.
	# Search live managers by world, so a controller-owned emitter cannot double caps.
	var viewport := owner_node.get_viewport()
	var manager: Node3D
	for candidate in owner_node.get_tree().get_nodes_in_group("swg_particle_managers"):
		if not candidate.is_queued_for_deletion() and candidate.get_world_3d()==viewport.find_world_3d():
			manager = candidate
			break
	if manager == null:
		manager = load("res://combat/optimized_particles.gd").new()
		manager.name = "SwgOptimizedParticles"
		manager.assets = resources
		viewport.add_child(manager)
	if is_instance_valid(eye) and (not is_instance_valid(manager.camera) or eye is XRCamera3D):
		manager.camera = eye
	manager.update_view()
	return manager

func _ready() -> void:
	add_to_group("swg_particle_managers")
	batch = ClassDB.instantiate("SwgParticleBatch")
	add_child(batch)
	# Advance after cameras/weapon orchestration, once per rendered frame.
	process_priority = 100
	# Compile bounded known programs before the first shot; no texture I/O per hit.
	for path in assets.catalog.get("particles",{}):
		var kind := "tracer" if "bolt" in path or "trail.prt" in path else ("muzzle" if "muz" in path else "impact")
		compile_source(path,kind)

static func value(curve: Dictionary, t: float, channel := 1) -> float:
	var points: Array = curve.get("points",[])
	if points.is_empty(): return 0.0
	var a: Array = points[0]
	for i in range(1,points.size()):
		var b: Array = points[i]
		if float(b[0]) >= t:
			return lerpf(float(a[channel]),float(b[channel]),clampf((t-float(a[0]))/maxf(0.000001,float(b[0])-float(a[0])),0,1))
		a = b
	return float(a[channel])

static func tint(d: Dictionary, t: float) -> Color:
	return Color(value(d.color,t,1),value(d.color,t,2),value(d.color,t,3),clampf(value(d.alpha,t),0,1))

func compile_source(path: String, kind := "impact") -> Array:
	if kind not in ["tracer","muzzle","impact"] or not assets.catalog.get("particles",{}).has(path):
		rejected_sources += 1
		return []
	var key := path+":"+kind
	if styles.has(key): return styles[key]
	if styles.size()>=MAX_SOURCE_PROGRAMS or compiled_style_count>=MAX_COMPILED_STYLES:
		rejected_sources += 1
		return []
	var selected: Array = []
	for d in assets.catalog.get("particles",{}).get(path,{}).get("emitters",[]):
		if d.get("visible",false): selected.append(d)
	# Keep the recognizable luminous flash/bolt, then at most one secondary layer.
	selected.sort_custom(func(a,b): return emitter_score(a,kind)>emitter_score(b,kind))
	var compiled: Array = []
	for i in range(mini(1 if kind=="tracer" else 2,selected.size())):
		if compiled_style_count>=MAX_COMPILED_STYLES: break
		var d: Dictionary = selected[i]
		var c: Dictionary = d.curves
		var smoke := "smoke" in str(d.name) or "dust" in str(d.name)
		var secondary := i>0
		var width_curve: Dictionary = d.length if d.linked_size else d.width
		var source_texture: Texture2D = assets.texture(str(d.material.texture))
		if source_texture==null:
			rejected_sources += 1
			continue
		var definition := {
			"texture":source_texture,"kind":kind,
			"blend":"additive" if d.material.get("additive",false) else "alpha",
			"color":tint(d,0.05),"color_end":tint(d,0.9),
			"width":value(width_curve,0.05),"length":value(d.length,0.05),
			"width_end":value(width_curve,0.9),"length_end":value(d.length,0.9),
			"life":clampf(value(c.life,0.0),0.016,1.2 if smoke else 0.75),
			"speed":value(c.speed,0.0)*value(d.speed_scale,0.0),
			"spread":deg_to_rad(clampf(value(c.spread,0.0),0,180)),
			"gravity":value(c.weight,0.0)*9.8,"secondary":secondary,
			"max_distance":20.0 if smoke else (50.0 if kind=="muzzle" or secondary else 100.0)}
		if kind=="tracer":
			for layer in selected:
				if str(layer.name)=="bolt center":
					definition["core_color"] = tint(layer,0.05)
					definition["core_ratio"] = clampf(value(layer.width,0.05)/maxf(float(definition.width),0.001),0.05,1.0)
		var style_id: int = batch.register_style(definition)
		if style_id<0: continue
		compiled_style_count += 1
		var rotation := Basis.from_euler(Vector3(-value(c.rotation_x,0),-value(c.rotation_y,0),value(c.rotation_z,0))*TAU)
		var offset := Vector3(value(c.translation_x,0),value(c.translation_y,0),-value(c.translation_z,0))
		var count := int(d.count_max) if d.one_shot else ceili(value(c.rate,0)*minf(float(d.emitter_life_max),0.18))
		compiled.append({"id":style_id,"count":clampi(count,1,8 if secondary else 12),"pose":Transform3D(rotation,offset),"definition":definition,"source_emitter":d.name})
	styles[key] = compiled
	if compiled.is_empty(): rejected_sources += 1
	return compiled

static func emitter_score(d: Dictionary, kind: String) -> int:
	var name := str(d.name)
	if kind=="tracer": return 100 if name=="bolt" else (80 if int(d.orientation)==2 else 0)
	return (100 if name=="flash" else 0)+(50 if "spark" in name else 0)+(20 if d.material.get("additive",false) else 0)

func burst(path: String, pose: Transform3D, _duration := 1.0, kind := "") -> bool:
	if kind.is_empty(): kind = "muzzle" if "muz" in path else "impact"
	var accepted := false
	for style in compile_source(path,kind):
		accepted = batch.emit_burst(style.id,pose*style.pose,style.count) or accepted
	return accepted

func tracer(path: String, pose: Transform3D) -> int:
	var source := compile_source(path,"tracer")
	return -1 if source.is_empty() else batch.create_tracer(source[0].id,pose)

func move_tracer(handle: int, pose: Transform3D) -> void:
	if handle>=0: batch.update_tracer(handle,pose)

func release_tracer(handle: int) -> void:
	if handle>=0: batch.release_tracer(handle)

func set_view(pose: Transform3D, fov := 110.0, aspect := 1.4) -> void:
	view_pose = pose
	batch.set_view(pose,fov,aspect)

func update_view() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(batch): return
	# XR culling uses the tracked HMD, never the desktop spectator. Wide guard FOV
	# covers both eyes; ordinary cameras use their real projection plus native guard.
	var xr := camera is XRCamera3D
	var size := camera.get_viewport().get_visible_rect().size
	set_view(camera.global_transform,120.0 if xr else camera.fov,1.5 if xr else size.x/maxf(size.y,1))

func advance(delta: float) -> void:
	batch.advance(delta)

func _process(delta: float) -> void:
	update_view()
	advance(delta)

func statistics() -> Dictionary:
	var result: Dictionary = batch.statistics()
	result.merge({"source_programs":styles.size(),"dynamic_lights":0,"omitted_source_lights":disabled_lights,"rejected_sources":rejected_sources,"source_graph_approximation":true,"culling_counter_semantics":"Visibility decisions, including repeated tracer checks; not unique effects"})
	return result

func clear() -> void:
	batch.clear()
