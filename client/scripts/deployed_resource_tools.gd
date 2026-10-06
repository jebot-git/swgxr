extends Node3D
## Server-confirmed tool deployments only. Visibility is not deployment capacity.
const MAX_VISIBLE := 32
const DISPLAY_DISTANCE := 64.0
const DISPLAY_EXTENT := 0.28
const MAX_HAND_HEIGHT := 2.0
const HOVER_HEIGHT := 1.2
const WORLD_MASK := 7
const FONT=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
var assets: RefCounted
var stage: Node3D
var observer: Node3D
var terrain: Node3D
var states: Dictionary={}
var visuals: Dictionary={}
var refresh_time:=0.0
var server_clock_offset:=0.0
var beam_material: StandardMaterial3D
var report:={"last_error":"","failures":{},"awaiting_ground":0,"source":"confirmed persistent Core3 deployment states"}

func configure(source_assets: RefCounted) -> void:
	clear()
	assets=source_assets
	beam_material=StandardMaterial3D.new()
	beam_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color=Color("42d8ef")
	beam_material.disable_ambient_light=true

func set_context(source_stage: Node3D, source_observer: Node3D, source_terrain: Node3D=null) -> void:
	stage=source_stage; observer=source_observer; terrain=source_terrain
	refresh_time=1.0

func vector(value: Variant) -> Variant:
	if value is Vector3: return value if value.is_finite() else null
	if value is Array and value.size()==3:
		var result:=Vector3(float(value[0]),float(value[1]),float(value[2]))
		return result if result.is_finite() else null
	if value is Dictionary and value.has("x") and value.has("y") and value.has("z"):
		return vector([value.x,value.y,value.z])
	return null

func world_position(state: Dictionary) -> Variant:
	if is_instance_valid(stage) and str(state.get("planet",stage.get_meta("planet","tatooine")))!=str(stage.get_meta("planet","tatooine")):return null
	if state.has("world_position"): return vector(state.world_position)
	if not is_instance_valid(stage):return null
	var source: Variant=vector(state.get("position"))
	var origin: Variant=vector(stage.get_meta("manifest",{}).get("origin"))
	if source==null or origin==null: return null
	var local: Vector3=source-origin
	return stage.to_global(Vector3(local.x,local.y,-local.z))

func source_position(world: Vector3) -> Dictionary:
	if not world.is_finite() or not is_instance_valid(stage): return {}
	var origin: Variant=vector(stage.get_meta("manifest",{}).get("origin"))
	if origin==null: return {}
	var local:=stage.to_local(world)
	return {"x":local.x+origin.x,"y":local.y+origin.y,"z":origin.z-local.z}

func ground_failure(reason: String) -> Dictionary:
	return {"valid":false,"error":reason}

func support_ray(position: Vector3, rise: float, fall: float) -> Dictionary:
	if not is_inside_tree() or not position.is_finite(): return {}
	var exclude: Array[RID]=[]
	if observer is CollisionObject3D: exclude.append(observer.get_rid())
	var query:=PhysicsRayQueryParameters3D.create(position+Vector3.UP*rise,position-Vector3.UP*fall,WORLD_MASK,exclude)
	query.hit_from_inside=true
	return get_world_3d().direct_space_state.intersect_ray(query)

func original_ground(hit: Dictionary) -> bool:
	if hit.is_empty() or not hit.get("collider") is CollisionObject3D: return false
	var collider: CollisionObject3D=hit.collider
	var source_layer:=int(collider.get_meta("source_layer",0))
	return source_layer==2 or (source_layer==4 and bool(collider.get_meta("authored_floor",false)))

func ground_placement(pose: Transform3D) -> Dictionary:
	return supported_placement(pose,true)

func supported_placement(pose: Transform3D, adjacent: bool) -> Dictionary:
	if not pose.is_finite() or pose.basis.determinant()<0.000001: return ground_failure("Invalid tracked tool pose")
	if not is_instance_valid(stage) or not stage.has_method("classify_world"): return ground_failure("Original world ground context is unavailable")
	if not stage.classify_world(pose.origin).is_empty(): return ground_failure("Sampling tools must be placed outdoors")
	if adjacent and is_instance_valid(observer) and observer.global_position.distance_to(pose.origin)>2.25: return ground_failure("Place the tool beside you")
	var hit:=support_ray(pose.origin,0.08,MAX_HAND_HEIGHT)
	if not original_ground(hit): return ground_failure("No loaded original terrain or floor beside the tool")
	var position: Vector3=hit.position
	var normal: Vector3=hit.normal
	if not normal.is_finite() or normal.dot(Vector3.UP)<0.94: return ground_failure("The ground is too steep for this tool")
	if pose.origin.y-position.y>MAX_HAND_HEIGHT+0.001 or position.y-pose.origin.y>0.08: return ground_failure("Lower the tool close to the ground")
	if not stage.classify_world(position+Vector3.UP*0.03).is_empty(): return ground_failure("Sampling tools must be placed outdoors")
	if int(hit.collider.get_meta("source_layer",0))==2 and is_instance_valid(terrain) and terrain.has_method("ready_near") and not terrain.ready_near(terrain.to_local(position),0):
		return ground_failure("Nearby terrain collision is still loading")
	# Reject ledges/holes or objects underneath any part of the compact footprint.
	for offset in [Vector3(0.12,0,0),Vector3(-0.12,0,0),Vector3(0,0,0.12),Vector3(0,0,-0.12)]:
		var neighbor:=support_ray(position+offset,0.16,0.16)
		if not original_ground(neighbor) or absf(normal.dot(Vector3(neighbor.position)-position))>0.035 or Vector3(neighbor.normal).dot(normal)<0.94:
			return ground_failure("The complete tool footprint needs supported ground")
	var forward:=(-pose.basis.z).slide(normal).normalized()
	if forward.length_squared()<0.5: forward=Vector3.FORWARD.slide(normal).normalized()
	var transform:=Transform3D(Basis(forward.cross(normal).normalized(),normal.normalized(),-forward),position)
	return {"valid":true,"transform":transform,"position":position,"normal":normal,"cell_id":"exterior","source_cell":str(hit.collider.get_meta("source_cell","")),"error":""}

func set_states(confirmed: Array) -> bool:
	var next: Dictionary={}; var tool_ids: Dictionary={}
	for value in confirmed:
		if not value is Dictionary:
			report.last_error="Invalid deployment record"; return false
		var id:=str(value.get("id","")); var tool_id:=str(value.get("tool_id",""))
		if id.is_empty() or tool_id.is_empty() or next.has(id) or tool_ids.has(tool_id):
			report.last_error="Missing or duplicate authoritative deployment/tool identity"; return false
		next[id]=value.duplicate(true); tool_ids[tool_id]=true
	states=next
	for id: String in report.failures.keys():
		if not states.has(id): report.failures.erase(id)
	for id: String in visuals.keys():
		if not states.has(id): release_visual(id)
	report.last_error=""
	refresh_time=1.0
	return true

func release_visual(id: String) -> void:
	if not visuals.has(id): return
	var node: Node3D=visuals[id].node
	if is_instance_valid(node): node.visible=false; node.queue_free()
	visuals.erase(id)

func set_server_time(server_time: float) -> void:
	if is_finite(server_time) and server_time>0:
		server_clock_offset=server_time-Time.get_unix_time_from_system()

func count_text(state: Dictionary, now: float=-1.0) -> String:
	var total:=0
	for entry: Dictionary in state.get("buffer",[]): total+=maxi(0,int(entry.get("quantity",0)))
	var text := "%d units · %s"%[total,str(state.get("resource_name","Resource sample")).left(30)]
	var outcome := str(state.get("sample_status",""))
	var message := str(state.get("sample_message",""))
	if not message.is_empty(): text+="\n"+message.left(120)
	elif not outcome.is_empty(): text+="\n"+outcome.replace("_"," ").capitalize()
	else: text+="\nAwaiting Core3 sample status"
	var current := now if now>=0 else Time.get_unix_time_from_system()+server_clock_offset
	var due := float(state.get("next_sample_at_unix",0))
	if due>0 and outcome!="expired":
		var seconds := maxi(0,ceili(due-current))
		text+="\nNext sample: %ds"%seconds if seconds>0 else "\nWaiting for Core3 sample result"
	var density := float(state.get("recommended_density",state.get("minimum_productive_density",0)))
	if density>0 and outcome in ["trace_amount","density_below_threshold"]:
		text+=" · seek ≥%d%% density"%ceili(density*100.0)
	return text

func create_visual(id: String, state: Dictionary, pose: Transform3D) -> bool:
	if assets==null or not assets.has_method("instance"): return false
	var tool: Dictionary=state.get("tool",{})
	var template:=str(state.get("template",tool.get("template",state.get("shared_template",""))))
	var customization: Dictionary=tool.get("customization",{})
	var model: MeshInstance3D=assets.call("instance",template,DISPLAY_EXTENT,customization)
	if model==null:
		report.failures[id]="Original deployed survey-tool appearance unavailable: "+template
		return false
	var bounds: AABB=model.transform*model.mesh.get_aabb()
	model.position.y-=bounds.position.y
	bounds=model.transform*model.mesh.get_aabb()
	var body:=StaticBody3D.new()
	body.name="ConfirmedResourceTool_"+id.validate_node_name()
	body.collision_layer=32; body.collision_mask=0
	body.set_meta("deployment_id",id); body.set_meta("tool_id",str(state.tool_id))
	body.set_meta("source_template",template)
	var collider:=CollisionShape3D.new(); var shape:=BoxShape3D.new()
	shape.size=bounds.size.max(Vector3.ONE*0.012); collider.shape=shape; collider.position=bounds.get_center()
	body.add_child(collider); body.add_child(model)
	var label:=Label3D.new()
	label.font=FONT; label.font_size=20; label.pixel_size=0.0014
	label.width=420; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.modulate=Color("8ae8ff"); label.outline_modulate=Color("093040"); label.outline_size=4
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false; label.shaded=false
	label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end=8.0
	label.position=Vector3(0,bounds.end.y+0.09,0)
	body.add_child(label)
	var beam:=MeshInstance3D.new(); var cylinder:=CylinderMesh.new()
	cylinder.top_radius=0.009; cylinder.bottom_radius=0.016
	cylinder.height=HOVER_HEIGHT; cylinder.radial_segments=6; cylinder.rings=1
	beam.mesh=cylinder; beam.material_override=beam_material
	beam.position=Vector3(0,-HOVER_HEIGHT*0.5,0)
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(beam); add_child(body)
	body.global_transform=pose.translated(Vector3.UP*HOVER_HEIGHT)
	visuals[id]={"node":body,"model":model,"label":label,"beam":beam,"center":bounds.get_center(),"template":template,"sampling_position":pose.origin}
	report.failures.erase(id)
	return true

func sync_visuals() -> void:
	var candidates: Array=[]
	var center:=observer.global_position if is_instance_valid(observer) else global_position
	for id: String in states:
		var position: Variant=world_position(states[id])
		if position==null: continue
		var distance: float=center.distance_squared_to(position)
		if distance<=DISPLAY_DISTANCE*DISPLAY_DISTANCE: candidates.append({"id":id,"position":position,"distance":distance})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	if candidates.size()>MAX_VISIBLE: candidates.resize(MAX_VISIBLE)
	var wanted: Dictionary={}; var created:=0
	report.awaiting_ground=0
	for candidate: Dictionary in candidates:
		var id: String=candidate.id
		# Persistent source positions still require loaded local support; do not
		# hang a device in the air while streamed terrain/cells are absent.
		var grounded:=supported_placement(Transform3D(Basis.IDENTITY,candidate.position+Vector3.UP*0.04),false)
		if not grounded.get("valid",false):
			report.awaiting_ground+=1; continue
		wanted[id]=true
		if not visuals.has(id):
			if created>=4: continue
			if not create_visual(id,states[id],grounded.transform): continue
			created+=1
		# Source position remains the ground sampling point, never the hovering visual.
		var hover: Transform3D=grounded.transform
		hover.basis=Basis.IDENTITY
		hover.origin+=Vector3.UP*HOVER_HEIGHT
		visuals[id].node.global_transform=hover
		visuals[id].sampling_position=grounded.position
		visuals[id].label.text=count_text(states[id])
	for id: String in visuals.keys():
		if not wanted.has(id): release_visual(id)

func nearest(position: Vector3, radius: float=0.22) -> Dictionary:
	if not position.is_finite() or not is_finite(radius) or radius<0: return {}
	var best: Dictionary={}; var distance:=radius
	for id: String in visuals:
		var record: Dictionary=visuals[id]
		if not is_instance_valid(record.node) or not states.has(id): continue
		var current: float=position.distance_to(record.node.to_global(record.center))
		if current>distance: continue
		distance=current; best=states[id].duplicate(true)
		best["world_position"]=record.node.global_position; best["sampling_position"]=record.sampling_position; best["distance"]=current
	return best

func reserved_ids() -> Array:
	var result: Array=[]
	for state: Dictionary in states.values():
		var id:=str(state.get("tool_id",""))
		if not result.has(id): result.append(id)
	return result

func clear() -> void:
	for id: String in visuals.keys(): release_visual(id)
	states.clear(); report.failures.clear()

func statistics() -> Dictionary:
	var value:=report.duplicate(true)
	value.merge({"confirmed_deployments":states.size(),"visible_models":visuals.size(),"max_visible":MAX_VISIBLE,"render_distance":DISPLAY_DISTANCE,"capacity_limit":false,"reserved_ids":reserved_ids()})
	return value

func _physics_process(delta: float) -> void:
	refresh_time+=delta
	if refresh_time>=0.25:
		refresh_time=0.0; sync_visuals()

func _exit_tree() -> void:
	clear()
