extends Node3D
## Frozen original animal poses for nearby authoritative Core3 corpse records.
const Assets=preload("res://scripts/inventory_assets.gd")
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
	if str(state.get("planet","tatooine"))!="tatooine": return null
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
	return true
func signature(state: Dictionary) -> String:
	return JSON.stringify([state.get("template",state.get("shared_template","")),state.get("customization",{}),state.get("scale",1.0)])
func release_visual(id: String) -> void:
	if visuals.has(id):
		visuals[id].node.visible=false; visuals[id].node.queue_free(); visuals.erase(id)
func create_visual(id: String,state: Dictionary) -> bool:
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
		if not visuals.has(id):
			if created>=2: continue
			if not create_visual(id,states[id]): continue
			created+=1
		var heading:=float(states[id].get("heading_radians",0))
		if not is_finite(heading): release_visual(id); failures[id]="Nonfinite corpse heading"; continue
		# SWG Z is mirrored, reversing source heading handedness.
		var facing:=Basis(Vector3.UP,-heading)
		if is_instance_valid(stage): facing=stage.global_basis*facing
		visuals[id].node.global_transform=Transform3D(facing,candidate.position)
	for id: String in visuals.keys():
		if not wanted.has(id): release_visual(id)
func nearest(hand: Vector3,radius: float=0.25) -> Dictionary:
	if not hand.is_finite() or not is_finite(radius) or radius<0: return {}
	var result: Dictionary={}; var best:=INF
	for id: String in visuals:
		var record: Dictionary=visuals[id]; var bounds: AABB=record.bounds
		var local: Vector3=record.node.to_local(hand)
		var x:=clampf(local.x,bounds.position.x,bounds.end.x); var z:=clampf(local.z,bounds.position.z,bounds.end.z)
		var horizontal:=Vector2(local.x-x,local.z-z).length()
		var above:=local.y-bounds.end.y
		if horizontal>radius or above< -0.12 or above>0.7: continue
		var distance:=Vector2(horizontal,above).length()
		if distance>=best: continue
		best=distance; result=states[id].duplicate(true)
		result.world_position=record.node.global_position
		result.bounds=record.node.global_transform*bounds
		result.hologram_position=record.node.to_global(Vector3(bounds.get_center().x,bounds.end.y+0.25,bounds.get_center().z))
		result.distance=distance
	return result
func clear() -> void:
	for id: String in visuals.keys(): release_visual(id)
	states.clear(); failures.clear(); last_error=""
func statistics() -> Dictionary:
	return {"confirmed_corpses":states.size(),"visible_models":visuals.size(),"max_visible":MAX_VISIBLE,"render_distance":DISPLAY_DISTANCE,"failures":failures.duplicate(true),"last_error":last_error,"pose_policy":"Frozen original incapacitated ANS frame, source skeleton and skin weights","source":"Core3 corpse query; no local reward authority"}
func _physics_process(delta: float) -> void:
	refresh_time+=delta
	if refresh_time>=0.25: refresh_time=0.0; sync_visuals()
func _exit_tree() -> void: clear()
