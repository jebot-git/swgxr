extends Node3D
## Frozen original animal poses for nearby authoritative Core3 corpse records.
const Assets=preload("res://scripts/inventory_assets.gd")
const Interaction=preload("res://scripts/corpse_interaction.gd")
var actor_provider: Callable
var coin_assets:=Assets.new()
var coins: Dictionary={}
const MAX_VISIBLE:=32
const DISPLAY_DISTANCE:=64.0
var assets:=Assets.new()
var stage: Node3D
var observer: Node3D
var states: Dictionary={}
var visuals: Dictionary={}
var failures: Dictionary={}
var last_error:=""
var refresh_time:=0.0

func configure(path: String="") -> void:
	clear()
	coin_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/loot_marker/catalog.json"))
	assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json") if path.is_empty() else path)
func set_context(source_stage: Node3D,source_observer: Node3D) -> void:
	stage=source_stage; observer=source_observer; refresh_time=1.0
func vector(value: Variant) -> Variant:
	if value is Vector3: return value if value.is_finite() else null
	if value is Dictionary: value=[value.get("x",NAN),value.get("y",NAN),value.get("z",NAN)]
	if not value is Array or value.size()!=3: return null
	var result:=Vector3(float(value[0]),float(value[1]),float(value[2]))
	return result if result.is_finite() else null
func world_position(state: Dictionary) -> Variant:
	if is_instance_valid(stage) and str(state.get("planet",stage.get_meta("planet","tatooine")))!=str(stage.get_meta("planet","tatooine")):return null
	if state.has("world_position"): return vector(state.world_position)
	if not is_instance_valid(stage): return null
	var origin: Variant=vector(stage.get_meta("manifest",{}).get("origin"))
	var position: Variant=vector(state.get("position"))
	if origin==null or position==null: return null
	var local: Vector3=position-origin
	return stage.to_global(Vector3(local.x,local.y,-local.z))
func set_states(confirmed: Array) -> bool:
	var next: Dictionary={}
	for value in confirmed:
		if not value is Dictionary or str(value.get("id","")).is_empty() or next.has(str(value.id)):
			last_error="Missing or duplicate authoritative corpse identity"; return false
		# The endpoint is corpse-only; reject an explicit contradictory alive record.
		if value.get("dead",true)==false:
			last_error="Living creature supplied to corpse presentation"; return false
		next[str(value.id)]=value.duplicate(true)
	states=next
	for id: String in visuals.keys():
		if not states.has(id) or visuals[id].signature!=signature(states[id]): release_visual(id)
	for id: String in failures.keys():
		if not states.has(id): failures.erase(id)
	last_error=""; refresh_time=1.0
	for id: String in coins:
		if not states.has(id) or not Interaction.eligible(states[id]): coins[id].visible=false
	return true
func signature(state: Dictionary) -> String:
	return JSON.stringify([state.get("template",state.get("shared_template","")),state.get("customization",{}),state.get("scale",1.0)])
func release_visual(id: String) -> void:
	if visuals.has(id):
		if not visuals[id].get("external",false):
			visuals[id].node.visible=false; visuals[id].node.queue_free()
		visuals.erase(id)
	if coins.has(id): coins[id].queue_free(); coins.erase(id)
func create_visual(id: String,state: Dictionary) -> bool:
	var actor: Variant = actor_provider.call(id) if actor_provider.is_valid() else null
	if is_instance_valid(actor) and actor.record.get("dead",false):
		visuals[id]={"node":actor,"bounds":actor.visual_bounds(),"signature":signature(state),"external":true}
		return true
	var template:=str(state.get("template",state.get("shared_template","")))
	var mesh:=assets.model(template,state.get("customization",{}))
	if mesh==null:
		failures[id]="Original corpse appearance/pose unavailable: "+template; return false
	var scale_factor:=float(state.get("scale",1.0))
	if not is_finite(scale_factor) or scale_factor<=0 or scale_factor>20:
		failures[id]="Invalid authoritative creature scale"; return false
	var model:=MeshInstance3D.new(); model.mesh=mesh; model.scale=Vector3.ONE*scale_factor
	model.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The source posture origin penetrates a little below zero; keep its actual
	# dimensions while supporting its lowest posed vertex at the source floor.
	var bounds: AABB=model.transform*mesh.get_aabb()
	model.position.y=-bounds.position.y; bounds=model.transform*mesh.get_aabb()
	var body:=StaticBody3D.new(); body.name="OriginalCorpse_"+id.validate_node_name()
	body.collision_layer=32; body.collision_mask=0; body.set_meta("corpse_id",id)
	var collision:=CollisionShape3D.new(); var shape:=BoxShape3D.new()
	shape.size=bounds.size.max(Vector3.ONE*0.01); collision.shape=shape; collision.position=bounds.get_center()
	body.add_child(model); body.add_child(collision); add_child(body)
	visuals[id]={"node":body,"model":model,"bounds":bounds,"signature":signature(state)}
	failures.erase(id); return true
func sync_visuals() -> void:
	var candidates: Array=[]
	var center:=observer.global_position if is_instance_valid(observer) else global_position
	for id: String in states:
		var position: Variant=world_position(states[id])
		if position==null: continue
		var distance: float=position.distance_squared_to(center)
		if distance<=DISPLAY_DISTANCE*DISPLAY_DISTANCE: candidates.append({"id":id,"position":position,"distance":distance})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	if candidates.size()>MAX_VISIBLE: candidates.resize(MAX_VISIBLE)
	var wanted: Dictionary={}; var created:=0
	for candidate: Dictionary in candidates:
		var id: String=candidate.id; wanted[id]=true
		if visuals.has(id) and not is_instance_valid(visuals[id].node): release_visual(id)
		if visuals.has(id) and not visuals[id].get("external",false) and actor_provider.is_valid():
			var actor: Variant=actor_provider.call(id)
			if is_instance_valid(actor) and actor.record.get("dead",false): release_visual(id)
		if not visuals.has(id):
			if created>=2: continue
			if not create_visual(id,states[id]): continue
			created+=1
		var heading:=float(states[id].get("heading_radians",0))
		if not is_finite(heading): release_visual(id); failures[id]="Nonfinite corpse heading"; continue
		# SWG Z is mirrored, reversing source heading handedness.
		var facing:=Basis(Vector3.UP,-heading)
		if is_instance_valid(stage): facing=stage.global_basis*facing
		if not visuals[id].get("external",false): visuals[id].node.global_transform=Transform3D(facing,candidate.position)
		else: visuals[id].bounds=visuals[id].node.visual_bounds()
		update_coin(id)
	for id: String in visuals.keys():
		if not wanted.has(id): release_visual(id)
func interaction_record(id: String) -> Dictionary:
	var record: Dictionary=visuals[id]
	var result: Dictionary=states[id].duplicate(true)
	result.world_position=record.node.global_position
	result.bounds=record.node.global_transform*record.bounds
	result.hologram_position=Interaction.coin_position(result.bounds)
	return result

func update_coin(id: String) -> void:
	var eligible: bool=Interaction.eligible(states[id]) and visuals[id].node.is_visible_in_tree()
	if eligible and not coins.has(id):
		var mesh: MeshInstance3D=coin_assets.instance("loot_coin",.24)
		if mesh==null: return
		var marker:=Node3D.new();add_child(marker);marker.add_child(mesh)
		for surface in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D=mesh.get_active_material(surface)
			var material:=ShaderMaterial.new();material.shader=preload("res://shaders/loot_coin.gdshader")
			material.set_shader_parameter("source_texture",original.albedo_texture)
			mesh.set_surface_override_material(surface,material)
		var label:=Label3D.new();marker.add_child(label);label.text="Loot All";label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size=26;label.pixel_size=.0015;label.position.y=.20;label.modulate=Color("ffda68");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		coins[id]=marker
	if coins.has(id):
		coins[id].visible=eligible
		coins[id].global_position=Interaction.coin_position(interaction_record(id).bounds)

func nearest_loot(hand: Transform3D) -> Dictionary:
	if not hand.origin.is_finite(): return {}
	var best:=INF;var result:Dictionary={}
	for id: String in coins:
		if not coins[id].visible or not states.has(id) or not Interaction.eligible(states[id]): continue
		var offset: Vector3=coins[id].global_position-hand.origin
		var distance:=offset.length()
		var along:=offset.dot(-hand.basis.z.normalized())
		var miss: float=(offset+hand.basis.z.normalized()*along).length()
		# Broad direct pickup, plus a short forgiving aim target for large bodies.
		if distance>Interaction.COIN_RADIUS and not (along>0 and along<=2.5 and miss<=.25+along*.08): continue
		if distance>=best: continue
		var query:=PhysicsRayQueryParameters3D.create(hand.origin,coins[id].global_position,7)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		best=distance;result=interaction_record(id)
	return result

func nearest(hand: Vector3,_radius: float=Interaction.BODY_MARGIN) -> Dictionary:
	if not hand.is_finite(): return {}
	var result: Dictionary={};var best:=INF
	for id: String in visuals:
		if not is_instance_valid(visuals[id].node) or not visuals[id].node.is_visible_in_tree(): continue
		var candidate:=interaction_record(id)
		if not Interaction.above_body(candidate,hand): continue
		var distance: float=hand.distance_to(candidate.bounds.get_center())
		if distance<best: best=distance;result=candidate
	return result

func _process(delta: float) -> void:
	for marker: Node3D in coins.values():
		marker.get_child(0).rotate_y(delta*2.0)

func clear() -> void:
	for id: String in visuals.keys(): release_visual(id)
	states.clear(); failures.clear(); last_error=""
func statistics() -> Dictionary:
	return {"confirmed_corpses":states.size(),"visible_models":visuals.size(),"max_visible":MAX_VISIBLE,"render_distance":DISPLAY_DISTANCE,"failures":failures.duplicate(true),"last_error":last_error,"pose_policy":"Frozen original incapacitated ANS frame, source skeleton and skin weights","source":"CoreCU corpse query; no local reward authority"}
func _physics_process(delta: float) -> void:
	refresh_time+=delta
	if refresh_time>=0.25: refresh_time=0.0; sync_visuals()
func _exit_tree() -> void: clear()
