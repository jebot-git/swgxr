extends Node3D
## Diagnostic prototype telegraphs. Never moves the player or tracked devices.
const Timeline=preload("res://combat/action_timeline.gd")
var timeline:=Timeline.new()
var app:Node
var sync:Node
var visuals:Dictionary={}
var pending:Array=[]
var sending:=false
var generation:=0
var confirmed:=0
var rejected:=0
var observations:Array=[]
var integration_ready:=false
var integration_pending:Array=[]
var lock_sent:Dictionary={}
var integration_retry:=0.0
var integration_busy:=false
var action_clock=preload("res://combat/action_clock.gd").new()
var catalog_revision:=""
var integration_outcomes:Array=[]
var cue_textures:Dictionary={}
var targeted_cue:Sprite3D
var diagnostic_stamp:=0.0
var integration_receipts:Array=[]

func setup(host:Node,source:Node)->void:
	app=host;sync=source
	var path:="res://../runtime/assets/combat_actions/catalog.json"
	if FileAccess.file_exists(path):
		var catalog:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if catalog is Dictionary:catalog_revision=str(catalog.get("revision",""))
func clear()->void:
	generation+=1;timeline.clear();pending.clear();sending=false
	integration_receipts.clear();integration_outcomes.clear();integration_ready=false;integration_pending.clear();lock_sent.clear();integration_retry=0;integration_busy=false;action_clock=preload("res://combat/action_clock.gd").new();timeline.clock_ready=false
	for mesh:MeshInstance3D in visuals.values():mesh.queue_free()
	visuals.clear()
	if is_instance_valid(targeted_cue):targeted_cue.queue_free()
func accept(events:Array,rtt:float)->void:
	var stamp:=Time.get_ticks_usec()/1000000.0
	for event:Dictionary in events:
		if event.get("protocol",1)==2 and timeline.clock_ready:event["_server_time_at_receive"]=stamp+timeline.server_offset
		timeline.ingest(event,stamp,rtt*.5)
		if event.get("protocol",1)==2 and event.phase=="windup" and sync.owner_character in event.get("eligible_victim_ids",[]) and integration_ready and can_present(event):
			var warning_key:=timeline.key(event)+":warning"
			if not lock_sent.has(warning_key):
				lock_sent[warning_key]=true;integration_pending.append({"kind":"warning","actor_id":str(event.id),"attack_id":str(event.attack_id),"aim_revision":int(event.aim_revision)})
		if event.get("protocol",1)==2 and event.get("aim_locked",false) and sync.owner_character in event.get("eligible_victim_ids",[]) and event.phase=="windup":
			var key:=timeline.key(event)+":"+str(event.aim_revision)
			if not lock_sent.has(key) and integration_ready and can_present(event):
				lock_sent[key]=true
				integration_pending.append({"kind":"lock","actor_id":str(event.id),"attack_id":str(event.attack_id),"aim_revision":int(event.aim_revision)})
				if lock_sent.size()>256:lock_sent.erase(lock_sent.keys()[0])
func draw_warning(event:Dictionary)->MeshInstance3D:
	var mesh:=ImmediateMesh.new();var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.2,.85,.4) if event.role=="support" else Color(1,.55,.08)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	var center:Array=event.get("geometry_origin",event.origin)
	var o:=Vector3(center[0],center[1]+.08,center[2])
	var shape:=str(event.get("shape","lane" if event.role=="ranged" else "cone"))
	var d:=Vector3(event.direction[0],0,event.direction[2]);var side:=Vector3(d.z,0,-d.x)
	var points:Array[Vector3]=[];var reach:=float(event.range)
	if shape=="lane":
		var width:=float(event.radius)
		points=[o-side*width,o+side*width,o+d*reach+side*width,o+d*reach-side*width,o-side*width]
	else:
		var half:=acos(float(event.cosine)) if shape=="cone" else PI
		points.append(o)
		for i in 25:
			var angle:float=lerpf(-half,half,float(i)/24)
			points.append(o+(d*cos(angle)+side*sin(angle))*reach)
		points.append(o)
	for i in range(points.size()-1):
		var steps:=maxi(1,int(ceil(points[i].distance_to(points[i+1])/.75)))
		for step in steps:
			for f:float in [float(step)/steps,float(step+1)/steps]:mesh.surface_add_vertex(project_warning(points[i].lerp(points[i+1],f),event))
	mesh.surface_end()
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;instance.set_meta("aim_revision",event.get("aim_revision",1));add_child(instance)
	var cue:=Node3D.new();cue.name="TargetCue";instance.add_child(cue)
	cue.position=sync.world([event.origin[0],event.origin[1]+2.0,event.origin[2]])
	for entry in [["Target","ui/target_aim.png",-.13],["Danger","abilities/animalattack.png",.13]]:
		var icon:=Sprite3D.new();icon.name=entry[0];icon.billboard=BaseMaterial3D.BILLBOARD_ENABLED;icon.pixel_size=.0035
		var texture_path:String=entry[1]
		if not cue_textures.has(texture_path):
			var image:=Image.load_from_file(ProjectSettings.globalize_path("res://../runtime/assets/combat/"+texture_path))
			if image!=null:cue_textures[texture_path]=ImageTexture.create_from_image(image)
		icon.texture=cue_textures.get(texture_path)
		icon.position.x=float(entry[2]);cue.add_child(icon)
	var fill:=MeshInstance3D.new();fill.name="ProgressFill";fill.mesh=ImmediateMesh.new()
	var fill_material:=StandardMaterial3D.new();fill_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;fill_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	fill.material_override=fill_material;instance.add_child(fill)
	return instance
static func preparation_progress(event:Dictionary,server_now:float)->float:
	var delivery:float=float(event.get("delivery_at",event.active_at))
	return clampf((server_now-float(event.start))/maxf(.001,delivery-float(event.start)),0,1)
func update_fill(instance:MeshInstance3D,event:Dictionary,server_now:float,color:Color)->void:
	var fill:MeshInstance3D=instance.get_node("ProgressFill")
	var material:StandardMaterial3D=fill.material_override;material.albedo_color=Color(color,.32 if server_now<float(event.get("delivery_at",event.active_at)) else .48)
	var progress:=preparation_progress(event,server_now)
	var step:=int(progress*100)
	if fill.get_meta("step",-1)==step:return
	fill.set_meta("step",step)
	var mesh:ImmediateMesh=fill.mesh;mesh.clear_surfaces()
	if progress<=0:return
	var center:Array=event.get("geometry_origin",event.origin)
	var shape:=str(event.get("shape","lane" if event.role=="ranged" else "cone"))
	var o:=Vector3(center[0],center[1]+.065,center[2]);var d:=Vector3(event.direction[0],0,event.direction[2]);var side:=Vector3(d.z,0,-d.x)
	var vertices:Array[Vector3]=[];var reach:=float(event.range)
	if shape=="lane":
		var width:=float(event.radius);reach*=progress
		var steps:=maxi(1,int(ceil(reach/.75)))
		for i in steps:
			var base:=o+d*reach*float(i)/steps;var tip:=o+d*reach*float(i+1)/steps
			var a:=base-side*width;var b:=base+side*width;var c:=tip+side*width;var e:=tip-side*width
			vertices.append_array([a,b,c,a,c,e])
	else:
		reach*=sqrt(progress)
		var half:=acos(float(event.cosine)) if shape=="cone" else PI
		var rings:=maxi(1,int(ceil(reach/.75)))
		for ring in rings:
			var inner:=reach*float(ring)/rings;var outer:=reach*float(ring+1)/rings
			for i in 24:
				var a:=lerpf(-half,half,float(i)/24);var b:=lerpf(-half,half,float(i+1)/24)
				var da:=d*cos(a)+side*sin(a);var db:=d*cos(b)+side*sin(b)
				vertices.append_array([o+da*inner,o+da*outer,o+db*outer,o+da*inner,o+db*outer,o+db*inner])
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p:Vector3 in vertices:mesh.surface_add_vertex(project_warning(p,event))
	mesh.surface_end()
func _process(_delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(sync) or sync.owner_session.is_empty():
		if is_instance_valid(targeted_cue):targeted_cue.visible=false
		return
	var stamp:=Time.get_ticks_usec()/1000000.0
	var valid:bool=app.world_ready and not app.loading_stage and not app.session_leaving and (not app.xr_requested or app.xr_focused)
	var feet:Vector3=app.source_position_at(app.player.global_position)
	for intent:Dictionary in timeline.sample(stamp,feet,sync.owner_character,valid):
		if intent.get("protocol",1)==2:
			intent.erase("protocol");intent.erase("action");intent.erase("encounter_id");intent.kind="contact"
			if integration_pending.size()<256:integration_pending.append(intent)
		else:pending.append({"intent":intent,"queued_at":stamp})
	for id:String in visuals.keys():
		if not timeline.attacks.has(id):visuals[id].queue_free();visuals.erase(id)
	var explicit_threat:=false;var threat_progress:=0.0
	for id:String in timeline.attacks:
		var row:Dictionary=timeline.attacks[id];var event:Dictionary=row.event
		if visuals.has(id) and visuals[id].get_meta("aim_revision",1)!=event.get("aim_revision",1):
			visuals[id].queue_free();visuals.erase(id)
		if not visuals.has(id):visuals[id]=draw_warning(event)
		var material:StandardMaterial3D=visuals[id].material_override
		material.albedo_color=Color(.2,.85,.4) if event.role=="support" else Color(1,.12,.08) if timeline.server_time(row,stamp)>=float(event.get("delivery_at",event.active_at)) else Color(.8,.3,1) if event.get("special",false) else Color(1,.55,.08)
		update_fill(visuals[id],event,timeline.server_time(row,stamp),material.albedo_color)
		var tracking:bool=str(event.target_id)==sync.owner_character and event.role!="support"
		var danger:bool=event.role!="support" and timeline.eligible(event,sync.owner_character) and timeline.contact(event,feet)
		update_cues(visuals[id],tracking,danger,bool(event.get("aim_locked",false)))
		if tracking and event.get("target_required",false) and event.phase!="cancelled" and timeline.server_time(row,stamp)<=float(event.end_at):
			explicit_threat=true;threat_progress=maxf(threat_progress,preparation_progress(event,timeline.server_time(row,stamp)))
		visuals[id].visible=valid and event.phase!="cancelled" and timeline.server_time(row,stamp)<=maxf(float(event.end_at),float(event.get("animation_end_at",event.end_at)))
	update_targeted_cue(valid and explicit_threat,threat_progress)
	if not sending and not pending.is_empty():send_contact()
	if not integration_busy and not catalog_revision.is_empty() and stamp>=integration_retry and (not integration_ready or not integration_pending.is_empty() or stamp>=integration_retry+2):send_integration()
func update_cues(instance: MeshInstance3D, tracking: bool, danger: bool, locked: bool) -> void:
	var target: Sprite3D=instance.get_node("TargetCue/Target")
	var path: Sprite3D=instance.get_node("TargetCue/Danger")
	target.visible=tracking;target.modulate=Color.WHITE if locked else Color(1,.72,.15)
	path.visible=danger;path.modulate=Color(1,.2,.1)

func update_targeted_cue(show_cue:bool,progress:float)->void:
	if not is_instance_valid(targeted_cue):
		if not show_cue:return
		targeted_cue=Sprite3D.new();targeted_cue.name="IncomingTargetedSpecial";targeted_cue.texture=cue_textures.get("ui/target_aim.png")
		targeted_cue.pixel_size=.0008;targeted_cue.no_depth_test=true;targeted_cue.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(targeted_cue)
	var camera:=get_viewport().get_camera_3d()
	targeted_cue.visible=show_cue and is_instance_valid(camera)
	if not targeted_cue.visible:return
	targeted_cue.global_position=camera.global_position-camera.global_basis.z*.65+camera.global_basis.x*.22-camera.global_basis.y*.18
	targeted_cue.modulate=Color(.8,.3,1).lerp(Color(1,.12,.08),progress)
	targeted_cue.scale=Vector3.ONE*(1.+.15*progress*sin(Time.get_ticks_msec()*.012))

func send_contact()->void:
	sending=true;var epoch:=generation;var queued:Dictionary=pending.pop_front();var intent:Dictionary=queued.intent
	var started:=Time.get_ticks_usec()/1000000.0
	var payload:Dictionary={"account":app.datapad_account,"character_id":sync.owner_character,"session_id":sync.owner_session,"zone":"tatooine","action_combat":intent}
	var reply:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/action_combat",payload)
	if epoch!=generation:return
	sending=false
	if reply.get("mutation",{}).get("accepted",false):confirmed+=1
	else:rejected+=1
	var row:Dictionary={"attack_id":intent.attack_id,"aim_revision":intent.aim_revision,"contact":intent.contact,"controller_queue_ms":(started-float(queued.queued_at))*1000,"total_request_ms":(Time.get_ticks_usec()/1000000.0-started)*1000,"accepted":reply.get("mutation",{}).get("accepted",false),"error_code":reply.get("error_code",reply.get("mutation",{}).get("error_code",""))}
	for field in ["adapter_queue_ms","adapter_rate_wait_ms","native_bridge_roundtrip_ms","native_action_ms"]:
		if reply.has(field):row[field]=reply[field]
	observations.append(row)
	if observations.size()>256:observations.pop_front()

func can_present(event:Dictionary)->bool:
	if not is_instance_valid(app) or not app.world_ready or app.loading_stage or app.session_leaving or (app.xr_requested and not app.xr_focused):return false
	var projection:Variant=app.get("live_combat") if app.get("live_combat_reserved") else sync.get("entities")
	if not is_instance_valid(projection):return false
	var actors:Dictionary=projection.actors;var actor:Variant=actors.get(str(event.id))
	if not is_instance_valid(actor):return false
	var visual:Variant=actor.get("visual")
	return is_instance_valid(visual) and visual.has_method("ensure_animation") and visual.ensure_animation(str(event.animation))
func project_warning(p:Vector3,event:Dictionary)->Vector3:
	# Footprint and timing stay in source X/Z. Only the drawn elevation changes.
	if is_instance_valid(app):
		if str(event.get("cell_id","0"))=="0":
			var terrain:Variant=app.get("terrain")
			if is_instance_valid(terrain) and terrain.get("evaluator")!=null:
				p.y=float(terrain.evaluator.sample_height(p.x,p.z))+.065
		else:
			var world:Vector3=sync.world([p.x,p.y,p.z])
			var query:=PhysicsRayQueryParameters3D.create(world+Vector3.UP*.4,world-Vector3.UP*1.5,1)
			var hit:=get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():return hit.position+Vector3.UP*.065
	return sync.world([p.x,p.y,p.z])
func send_integration()->void:
	integration_busy=true;var epoch:=generation;var started:=Time.get_ticks_usec()/1000000.0
	var batch:Array=[]
	while not integration_pending.is_empty() and batch.size()<32:batch.append(integration_pending.pop_front())
	var intent:Dictionary={"action":"batch","receipts":batch} if integration_ready else {"action":"negotiate","protocol":2,"catalog_revision":catalog_revision}
	var payload:Dictionary={"account":app.datapad_account,"character_id":sync.owner_character,"session_id":sync.owner_session,"action_combat":intent}
	var reply:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/action_combat",payload)
	if epoch!=generation:return
	integration_busy=false;var finished:=Time.get_ticks_usec()/1000000.0;var mutation:Dictionary=reply.get("mutation",{})
	if mutation.get("success",false) and mutation.get("protocol",0)==2:
		integration_ready=true;integration_retry=finished+.025
		var rtt:=finished-started
		# Prefer the least queued clock exchange. Keep each attack's clock anchor
		# immutable, so later estimates cannot make a visible countdown jump.
		if action_clock.observe(started,float(mutation.server_received),float(mutation.server_sent),finished):
			timeline.server_offset=action_clock.offset;timeline.clock_ready=true
		var events:Array=mutation.get("action_events",[]);accept(events,rtt)
		if sync.has_method("apply_motion"):
			var projection:Variant=app.get("live_combat") if app.get("live_combat_reserved") else sync.entities
			if is_instance_valid(projection):sync.apply_motion({"source_kind":"core3_motion_v1","epoch":sync.motion_epoch,"action_events":events},projection.actors)
		integration_outcomes=mutation.get("outcomes",[])
		for result:Dictionary in mutation.get("receipts",[]):
			integration_receipts.append(result.duplicate(true))
			if integration_receipts.size()>128:integration_receipts.pop_front()
			if result.kind=="contact":
				if result.accepted:confirmed+=1
				else:rejected+=1
		if finished-diagnostic_stamp>=2 and (not integration_receipts.is_empty() or not integration_outcomes.is_empty()):
			diagnostic_stamp=finished
			var file:=FileAccess.open("user://combat-diagnostics.json",FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify({"schema":1,"updated_at":Time.get_unix_time_from_system(),"clock_ready":timeline.clock_ready,"late_warnings":timeline.rejected_late,"late_locks":timeline.late_locks,"contact_reports":timeline.receipts,"receipts":integration_receipts,"outcomes":integration_outcomes},"  "))
	else:
		integration_retry=finished+(.1 if integration_ready else 10)
		# Exactly-once native receipts permit bounded retries after a lost reply.
		if integration_ready:
			for row:Dictionary in batch:
				if integration_pending.size()<256:integration_pending.append(row)
		if mutation.get("error_code","")=="ground_capability_required":integration_ready=false
