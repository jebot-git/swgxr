extends Node3D
## Bounded persistent Core3 session projection; HTTP and snapshots never grant local HP.
signal state_changed(live:bool,message:String)
signal snapshot_applied(player:Dictionary)
signal appearance_status_changed(report:Dictionary)
signal life_action_finished(action:String,success:bool,message:String)
signal transport_required(transport:Dictionary)
const FloorProjection=preload("res://combat/actor_floor_projection.gd")
const Actor=preload("res://combat/live_actor.gd")
const AmbientBindings=preload("res://combat/live_ambient_bindings.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const MAX_ACTORS:=96
const MAX_SHOTS:=64
const MAX_QUEUE:=128
const POLL_INTERVAL:=0.2
const SESSION_TIMEOUT:=4.0
var app:Node
var rig:Node3D
var stage:Node3D
var player:CharacterBody3D
var assets:=Assets.new()
var dead_assets:=Assets.new()
var actor_catalog:=""
var actors:Dictionary={}
var floor_projection:=FloorProjection.new()
var appearance_report:Dictionary={}
var ambient_source:Node3D
var ambient_bindings:=AmbientBindings.new()
var shots:Dictionary={}
var queue:Array[Dictionary]=[]
var session_id:=""
var sequence:=-1
var live:=false
var native_ready:=false
var busy:=false
var generation:=0
var serial:=0
var poll_clock:=0.0
var elapsed_since_snapshot:=0.0
var weapon:Dictionary={}
var player_state:Dictionary={}
var last_error:=""
var confirmed_contacts:=0
var rejected_shots:=0
var saved_states:Array=[]
var owner_account:=""
var owner_character:=""
var next_launch_usec:=0
var status_path:=""
var last_status_usec:=0
var life_action_pending := ""
var pending_transport: Dictionary = {}
var notified_transport_id := ""

func configure(host:Node,combat_rig:Node3D,source_stage:Node3D,observer:CharacterBody3D)->void:
	app=host;rig=combat_rig;stage=source_stage;player=observer
	if app.get("args") is Dictionary:
		var requested:=str(app.args.get("live-combat-status",""))
		if requested.is_absolute_path():status_path=requested
	assets.configure();dead_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	actor_catalog=ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	rig.authority_gate=is_ready;rig.shot_authority=register_shot
	rig.rounds_sim.authoritative_contact.connect(contact)
	for entry:Dictionary in rig.weapons:
		saved_states.append({"state":entry.state,"profile":entry.state.profile.duplicate(true),"ability_state":entry.state.ability_state,"wear_per_shot":entry.state.wear_per_shot})
		entry.state.ability_state=null;entry.state.wear_per_shot=0.0
		entry.state.profile["abilities"]=[]
	rig.close_ability_menu();rig.abilities.primed=false

func configure_ambient(source_node:Node3D)->void:
	if is_instance_valid(ambient_source):ambient_source.set_live_suppressed({})
	ambient_source=source_node
	ambient_bindings.configure(source_node.manifest if is_instance_valid(source_node) else {})
	if is_instance_valid(ambient_source):ambient_source.set_live_suppressed({})

func source_visual_records(snapshot_actors:Array)->Array:
	if not is_instance_valid(ambient_source):return snapshot_actors
	ambient_bindings.update(snapshot_actors)
	var projected:Array=[]
	for value:Dictionary in snapshot_actors:
		var copy:=value.duplicate(true);var id:=str(copy.id)
		if ambient_bindings.bindings.has(id):
			var placement_id:=str(ambient_bindings.bindings[id])
			var placement:Dictionary=ambient_bindings.placements[placement_id]
			copy["source_placement_visual"]={"placement_id":placement_id,"appearance_id":str(placement.get("appearance_id",placement.template)),"catalog":str(ambient_source.catalog_path),"cell_id":str(placement.get("cell_id",""))}
		projected.append(copy)
	return projected

func synchronize_ambient(_snapshot_actors:Array)->void:
	if not is_instance_valid(ambient_source):return
	var presented:Dictionary=ambient_source.live_suppressed.duplicate()
	for id:String in ambient_bindings.bindings:
		if not actors.has(id):continue # Retain already-presented known-dead/range tombstones.
		var placement_id:=str(ambient_bindings.bindings[id]);var report:Dictionary=actors[id].report
		if report.get("source_variant_ready",false) and str(report.get("source_placement_id",""))==placement_id:presented[placement_id]=id
		else:presented.erase(placement_id)
	ambient_source.set_live_suppressed(presented)

func owner()->Dictionary:
	return {"account":owner_account,"character_id":owner_character,"session_id":session_id}

func source(point:Vector3)->Array:
	var converted:Vector3=app.source_position_at(point)
	return [converted.x,converted.y,converted.z]

func source_direction(direction:Vector3)->Array:
	var local:Vector3=stage.global_basis.inverse()*direction if is_instance_valid(stage) else direction
	local=Vector3(local.x,local.y,-local.z).normalized()
	return [local.x,local.y,local.z]

func world(point:Array)->Vector3:
	var origin:Array=stage.get_meta("manifest",{}).get("origin",[0,0,0]) if is_instance_valid(stage) else [0,0,0]
	var local:=Vector3(float(point[0])-float(origin[0]),float(point[1])-float(origin[1]),-(float(point[2])-float(origin[2])))
	return stage.to_global(local) if is_instance_valid(stage) else local

func start(position:Vector3,heading_radians:float)->bool:
	reset("Connecting to live Core3 combat…")
	owner_account=str(app.datapad_account);owner_character=str(app.datapad_character_id)
	var epoch:=generation;busy=true
	var payload:=owner();payload.erase("session_id");payload.merge({"position":source(position),"heading_radians":heading_radians})
	if app.get("args") is Dictionary and app.args.has("spawn-test-lair"):payload["spawn_test_lair"]=true
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/start",payload)
	if epoch!=generation:return false
	busy=false
	if not accept_response(response,true):fail(str(response.get("error",last_error)));return false
	state_changed.emit(true,"LIVE CORE3 COMBAT TEST")
	print("SWG_LIVE_COMBAT "+JSON.stringify({"connected":true,"native_ready":native_ready,"actors":actors.size(),"sequence":sequence,"item_id":weapon.get("item_id",""),"certified":weapon.get("certified",false)}))
	write_status(true)
	return true

func stop()->void:
	var payload:=owner();var had_session:=not session_id.is_empty()
	reset("Live Core3 session stopped.")
	if had_session:await app.api(HTTPClient.METHOD_POST,"/combat/session/stop",payload)

func reset(reason:="Live Core3 session unavailable.")->void:
	life_action_pending="";pending_transport={};notified_transport_id=""
	generation+=1;live=false;native_ready=false;busy=false;session_id="";sequence=-1;weapon={};player_state={};queue.clear();shots.clear();next_launch_usec=0
	for actor:Node in actors.values():actor.collision_layer=0;actor.visible=false;actor.queue_free()
	actors.clear();last_error=reason
	ambient_bindings.clear()
	if is_instance_valid(ambient_source):ambient_source.set_live_suppressed({})
	update_appearance_report()
	if is_instance_valid(rig):rig.set_allowed(false)
	state_changed.emit(false,reason)

func fail(reason:String)->void:
	print("SWG_LIVE_COMBAT "+JSON.stringify({"connected":false,"reason":reason,"actors":actors.size(),"sequence":sequence}))
	var payload:=owner();var had_session:=not session_id.is_empty()
	reset(reason if not reason.is_empty() else "Live Core3 response unavailable; combat disarmed.")
	write_status(true)
	if had_session:call_deferred("release_failed_session",payload)

func release_failed_session(payload:Dictionary)->void:
	if is_instance_valid(app) and not app.is_queued_for_deletion():
		await app.api(HTTPClient.METHOD_POST,"/combat/session/stop",payload)


func is_ready()->bool:
	return live and native_ready and pending_transport.is_empty() and life_action_pending.is_empty() and not bool(player_state.get("cloning",false)) and not session_id.is_empty() and bool(weapon.get("certified",false)) and not bool(player_state.get("dead",false)) and not bool(player_state.get("incapacitated",false)) and int(player_state.get("posture",0)) not in [12,13,14] and elapsed_since_snapshot<SESSION_TIMEOUT

func finite_vector(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):return false
	return true

func valid_actor(record:Dictionary)->bool:
	if str(record.get("id","")).is_empty() or str(record.get("template","")).is_empty() or str(record.get("kind","")) not in ["creature","lair"]:return false
	if not finite_vector(record.get("position")) or not record.get("dead") is bool:return false
	return is_finite(float(record.get("health",NAN))) and is_finite(float(record.get("max_health",NAN))) and float(record.max_health)>0 and is_finite(float(record.get("heading_radians",NAN))) and is_finite(float(record.get("scale",1))) and float(record.get("scale",1))>0 and float(record.get("scale",1))<=20

func valid_player(value:Dictionary)->bool:
	for key in ["ham","max_ham","wounds"]:
		if not finite_vector(value.get(key)):return false
		for component in value[key]:
			if float(component)<0:return false
	for index in range(3):
		if float(value.max_ham[index])<=0 or float(value.wounds[index])>float(value.max_ham[index]) or float(value.ham[index])>float(value.max_ham[index])-float(value.wounds[index]):return false
	if not value.get("dead") is bool or not value.get("incapacitated") is bool or not (value.get("posture") is float or value.get("posture") is int):return false
	var posture:=int(value.posture)
	return posture>=0 and posture<=14 and float(value.posture)==posture and bool(value.dead)==(posture==14) and bool(value.incapacitated)==(posture==13) and is_finite(float(value.get("shock_wounds",NAN))) and float(value.shock_wounds)>=0

func accept_response(response:Dictionary,initial:=false)->bool:
	if not bool(response.get("ok",false)) or response.get("backend","")!="core3" or response.get("source_kind","")!="core3_live_combat" or str(response.get("character_id",""))!=owner_character or not bool(response.get("session_live",false)):
		last_error=str(response.get("error","Core3 session was lost."));return false
	var incoming:=str(response.get("session_id",""));var revision:=int(response.get("sequence",-1))
	if revision<0 or incoming.is_empty() or (not initial and incoming!=session_id) or revision<sequence:last_error="Stale or mismatched live Core3 snapshot.";return false
	var snapshot:Dictionary=response.get("snapshot",{})
	if not snapshot.get("ready") is bool or not snapshot.get("full",false) or snapshot.get("truncated",false) or not snapshot.get("actors") is Array or snapshot.actors.size()>MAX_ACTORS or not snapshot.get("player") is Dictionary or not snapshot.get("weapon") is Dictionary:last_error="Incomplete live Core3 snapshot.";return false
	if not snapshot.get("transport",{}) is Dictionary:
		last_error="Invalid authoritative medical transport.";return false
	var transport: Dictionary = snapshot.get("transport",{})
	if not transport.is_empty() and (str(transport.get("id","")).is_empty() or not transport.get("destination") is Dictionary or not preload("res://combat/live_transport.gd").new().destination_valid(transport.destination)):
		last_error="Invalid authoritative medical transport.";return false
	var life_locked: bool = bool(snapshot.player.get("dead",false)) or bool(snapshot.player.get("incapacitated",false)) or not transport.is_empty()
	var incoming_weapon:Dictionary=snapshot.weapon
	if not life_locked and (str(incoming_weapon.get("item_id","")).is_empty() or not incoming_weapon.get("certified",false) or float(incoming_weapon.get("fire_interval_seconds",0))<=0 or float(incoming_weapon.get("max_range_m",0))<=0):last_error="Native equipped weapon is unavailable or uncertified.";return false
	for key in ["fire_interval_seconds","max_range_m","projectile_speed"]:
		if not life_locked and (not is_finite(float(incoming_weapon.get(key,NAN))) or float(incoming_weapon[key])<=0):last_error="Invalid native weapon timing or range.";return false
	if not life_locked and not rig.weapons.any(func(entry):return str(entry.state.profile.get("item_id",""))==str(incoming_weapon.get("item_id",""))):
		last_error="Native equipped weapon has no matching owned client profile.";return false
	var seen:Dictionary={}
	for value in snapshot.actors:
		if not value is Dictionary or not valid_actor(value) or seen.has(str(value.get("id",""))):last_error="Malformed live Core3 actor snapshot.";return false
		seen[str(value.id)]=true
	if not valid_player(snapshot.player):last_error="Incomplete or invalid authoritative player HAM/posture.";return false
	var seconds:=maxf(elapsed_since_snapshot,POLL_INTERVAL)
	session_id=incoming;sequence=revision;native_ready=bool(snapshot.ready);weapon=incoming_weapon.duplicate(true);player_state=snapshot.player.duplicate(true);pending_transport=transport.duplicate(true)
	for value:Dictionary in source_visual_records(snapshot.actors):
		var id:=str(value.id);var recreate:bool=not actors.has(id) or bool(actors[id].record.dead)!=bool(value.dead) or str(actors[id].record.template)!=str(value.template) or float(actors[id].record.get("scale",1))!=float(value.get("scale",1)) or actors[id].record.get("customization",{})!=value.get("customization",{}) or actors[id].record.get("source_placement_visual",{})!=value.get("source_placement_visual",{})
		if recreate:
			if actors.has(id):actors[id].collision_layer=0;actors[id].visible=false;actors[id].queue_free();actors.erase(id)
			var actor:=Actor.new();add_child(actor)
			if not actor.configure(value,session_id,assets,dead_assets,actor_catalog):last_error=str(actor.report.get("error","Original actor model unavailable"));actor.free();return false
			actors[id]=actor;actor.add_to_group("swg_radar_contacts")
		var pose:=Transform3D(Basis(Vector3.UP,-float(value.heading_radians)),world(value.position))
		if is_instance_valid(stage):pose.basis=stage.global_basis*pose.basis
		actors[id].apply_record(value,pose,seconds,recreate)
		floor_projection.apply(actors[id],value,app.get("terrain") if is_instance_valid(app) else null,stage)
	for id:String in actors.keys():
		if not seen.has(id):actors[id].collision_layer=0;actors[id].visible=false;actors[id].queue_free();actors.erase(id)
	for entry:Dictionary in rig.weapons:
		if not weapon.is_empty() and str(entry.state.profile.get("item_id",""))==str(weapon.get("item_id","")) and float(weapon.get("fire_interval_seconds",0))>0 and float(weapon.get("max_range_m",0))>0:
			entry.state.profile.rpm=60.0/float(weapon.fire_interval_seconds)
			entry.state.profile["profession"]={"rpm_scale":1.0}
			entry.state.profile.projectile_speed=float(weapon.get("projectile_speed",100))
			entry.state.core.maxRange=float(weapon.max_range_m)
	synchronize_ambient(snapshot.actors)
	var feedback: Variant = player.get("feedback")
	if feedback != null and feedback.get("vital") != null: feedback.vital.observe(player_state.get("vital_feedback",{}))
	live=true;elapsed_since_snapshot=0;last_error="";update_appearance_report();snapshot_applied.emit(player_state.duplicate(true))
	if not initial and not pending_transport.is_empty() and str(pending_transport.id)!=notified_transport_id:
		notified_transport_id=str(pending_transport.id)
		transport_required.emit(pending_transport.duplicate(true))
	write_status();return live and session_id==incoming

func register_shot(shot:Dictionary,pose:Transform3D,grip:Vector3)->Dictionary:
	if not is_ready() or str(shot.get("item_id",""))!=str(weapon.item_id) or shots.size()>=MAX_SHOTS or queue.size()>=MAX_QUEUE:return {}
	var now:=Time.get_ticks_usec()
	if now<next_launch_usec:return {}
	next_launch_usec=now+int(float(weapon.fire_interval_seconds)*1000000)
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	var immutable:=shot.duplicate(true);immutable["shot_id"]=id;immutable["live_session"]=session_id;immutable["launched_usec"]=now
	immutable.range=float(weapon.max_range_m);immutable.speed=float(weapon.get("projectile_speed",shot.speed))
	shots[id]={"shot":immutable.duplicate(true),"accepted":false,"contacted":false,"expires_usec":now+int((float(immutable.range)/maxf(float(immutable.speed),1)+5.0)*1000000)}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.item_id),"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	queue.append({"kind":"fire","payload":payload,"shot_id":id});return immutable

func contact(shot:Dictionary,target:Dictionary,position:Vector3,_normal:Vector3,_distance:float)->void:
	var id:=str(shot.get("shot_id",""));var target_id:=str(target.get("id",""))
	if not is_ready() or str(shot.get("live_session",""))!=session_id or str(target.get("session_id",""))!=session_id or not shots.has(id) or not actors.has(target_id) or not actors[target_id].is_targetable() or shots[id].contacted:return
	if queue.size()>=MAX_QUEUE:fail("Live combat request budget exceeded; session disarmed.");return
	shots[id].contacted=true
	var age:=float(Time.get_ticks_usec()-int(shots[id].shot.launched_usec))/1000000.0
	var payload:=owner();payload.merge({"shot_id":id,"target_id":target_id,"hit_position":source(position),"projectile_age_seconds":age})
	queue.append({"kind":"impact","payload":payload,"shot_id":id})

func movement_payload() -> Dictionary:
	var payload:=owner()
	if is_instance_valid(app.get("vehicles")):payload["vehicle_controls"]=app.vehicles.drive_payload()
	if is_instance_valid(app.get("medic")):payload["medic_pose"]=app.medic.tracked_pose()
	payload.merge({"position":source(player.global_position),"heading_radians":-player.global_rotation.y,"ready":bool(app.world_ready) and (not bool(app.get("xr_requested")) or bool(app.get("xr_focused")))})
	if is_instance_valid(stage) and stage.get("current_cell") is Dictionary:
		var cell: Dictionary=stage.current_cell
		var key:=str(cell.get("cell_id",""))
		var index:=int(key.get_slice(":",1)) if key.contains(":") else 0
		payload["building_id"]=str(int(cell.get("building_object_id",0))) if index>0 else "0"
		payload["cell_index"]=index
	return payload

func request_life_action(action: String) -> bool:
	if not live or not life_action_pending.is_empty() or not pending_transport.is_empty() or action not in ["recover","medical_transport"]:return false
	var posture:=int(player_state.get("posture",0))
	if action=="recover" and posture!=13:return false
	if action=="medical_transport" and posture not in [13,14]:return false
	# A life transition invalidates pending shots, never an opportunity to fire
	# after dying or from the old location while a transport is loading.
	queue.clear();shots.clear();rig.rounds_sim.clear();rig.set_allowed(false)
	life_action_pending=action
	var payload:=owner();payload["action"]=action
	queue.append({"kind":"life","payload":payload})
	return true

func acknowledge_transport(id: String) -> bool:
	if not live or pending_transport.is_empty() or str(pending_transport.id)!=id:return false
	if queue.any(func(request):return request.payload.get("transport_ack","")==id):return true
	var payload:=movement_payload();payload["transport_ack"]=id
	queue.push_front({"kind":"update","payload":payload})
	return true

func pump()->void:
	if busy or not live:return
	var request:Dictionary
	if not queue.is_empty():request=queue.pop_front()
	elif poll_clock>=POLL_INTERVAL:
		poll_clock=0
		var payload:=movement_payload()
		request={"kind":"update","payload":payload}
	else:return
	var id:=str(request.get("shot_id",""))
	if request.kind=="impact" and (not shots.has(id) or not shots[id].accepted):return
	busy=true;var epoch:=generation
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/"+str(request.kind),request.payload)
	if epoch!=generation:return
	busy=false
	# Services share this native session but use a separate HTTP request. A newer
	# service observation may arrive first; keep the older command's receipt
	# without rolling back its already-applied authoritative state.
	var older_owned: bool = bool(response.get("ok",false)) and response.get("backend","")=="core3" and response.get("source_kind","")=="core3_live_combat" and str(response.get("character_id",""))==owner_character and str(response.get("session_id",""))==session_id and bool(response.get("session_live",false)) and int(response.get("sequence",-1))>=0 and int(response.get("sequence",-1))<sequence
	if not older_owned and not accept_response(response):fail(last_error);return
	if request.kind=="life":
		var action := str(request.payload.action)
		life_action_pending=""
		var mutation: Dictionary=response.get("mutation",{})
		life_action_finished.emit(action,bool(mutation.get("success",false)),str(mutation.get("error_code",response.get("error_code",""))))
	if request.kind in ["fire","impact"]:
		var mutation:Dictionary=response.get("mutation",{})
		if not mutation.get("success",false) or str(mutation.get("shot_id",""))!=id:
			rejected_shots+=1;shots.erase(id);return
		if request.kind=="fire" and shots.has(id):shots[id].accepted=true
		elif request.kind=="impact":confirmed_contacts+=1;shots.erase(id)

func _process(delta:float)->void:
	if not live:return
	elapsed_since_snapshot+=delta;poll_clock+=delta
	if elapsed_since_snapshot>SESSION_TIMEOUT:fail("Live Core3 updates timed out; combat disarmed.");return
	for id:String in shots.keys():
		if Time.get_ticks_usec()>int(shots[id].expires_usec):shots.erase(id)
	if is_instance_valid(app):pump()

func update_appearance_report()->void:
	var report:Dictionary={"total":actors.size(),"complete":0,"partial":0,"unavailable":0,"actor_errors":[],"source_equipment_actors":[],"notice":""}
	for id:String in actors:
		var actor=actors[id]
		var status:=str(actor.report.get("appearance_status","unavailable"))
		report[status]=int(report.get(status,0))+1
		if actor.report.get("equipment_provenance","")=="source_placement_equipment":report.source_equipment_actors.append({"id":id,"template":str(actor.record.template),"appearance_id":actor.report.get("source_appearance",""),"placement_id":actor.report.get("source_placement_id",""),"provenance":"source_placement_equipment","native_equipment_authoritative":false})
		if status!="complete":report.actor_errors.append({"id":id,"template":str(actor.record.template),"status":status,"missing_components":actor.report.get("missing_components",[]).duplicate(true)})
	if report.unavailable>0 or report.partial>0:
		report.notice="%d incomplete / %d unavailable original appearances.\nSee entity labels; unavailable entities cannot be targeted."%[report.partial,report.unavailable]
	if report!=appearance_report:
		appearance_report=report
		appearance_status_changed.emit(appearance_report.duplicate(true))

func write_status(force:=false)->void:
	if status_path.is_empty():return
	var now:=Time.get_ticks_usec()
	if not force and now-last_status_usec<1000000:return
	last_status_usec=now
	var status:Dictionary={"ticks_usec":now,"live":live,"native_ready":native_ready,"ready":is_ready(),"life_action_pending":life_action_pending,"transport":pending_transport.duplicate(true),"sequence":sequence,"actors":actors.size(),"queued":queue.size(),"confirmed_contacts":confirmed_contacts,"rejected_shots":rejected_shots,"last_error":last_error,"weapon":weapon.duplicate(true),"player":player_state.duplicate(true),"appearances":appearance_report.duplicate(true),"ambient_bindings":ambient_bindings.bindings.size(),"projectiles":rig.rounds_sim.statistics() if is_instance_valid(rig) and is_instance_valid(rig.rounds_sim) else {}}
	DirAccess.make_dir_recursive_absolute(status_path.get_base_dir())
	var file:=FileAccess.open(status_path+".tmp",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(status,"  "));file.close();DirAccess.rename_absolute(status_path+".tmp",status_path)

func statistics()->Dictionary:
	return {"live":live,"native_ready":native_ready,"session_bound":not session_id.is_empty(),"sequence":sequence,"actors":actors.size(),"max_actors":MAX_ACTORS,"queued":queue.size(),"shots":shots.size(),"confirmed_contacts":confirmed_contacts,"rejected_shots":rejected_shots,"last_error":last_error,"appearances":appearance_report.duplicate(true),"ambient_bindings":ambient_bindings.bindings.size(),"projectiles":rig.rounds_sim.statistics() if is_instance_valid(rig) and is_instance_valid(rig.rounds_sim) else {}}

func _exit_tree()->void:
	if is_instance_valid(ambient_source) and not ambient_source.is_queued_for_deletion():ambient_source.set_live_suppressed({})
	for saved:Dictionary in saved_states:
		if is_instance_valid(saved.state):saved.state.profile=saved.profile;saved.state.core=saved.profile.core3;saved.state.ability_state=saved.ability_state;saved.state.wear_per_shot=saved.wear_per_shot
	if is_instance_valid(rig):rig.authority_gate=Callable();rig.shot_authority=Callable()
