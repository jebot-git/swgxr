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
const MAX_UNSTARTED_RETRIES:=3
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
var showdown_volley:Dictionary={}
var status_path:=""
var last_status_usec:=0
var life_action_pending := ""
var pending_transport: Dictionary = {}
var notified_transport_id := ""
var abilities_revision := -1
var backend_retry_usec:=0

func configure(host:Node,combat_rig:Node3D,source_stage:Node3D,observer:CharacterBody3D)->void:
	app=host;rig=combat_rig;stage=source_stage;player=observer
	if app.get("args") is Dictionary:
		var requested:=str(app.args.get("live-combat-status",""))
		if requested.is_absolute_path():status_path=requested
	assets.configure();dead_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	actor_catalog=preload("res://scripts/planet_catalog.gd").context_path(host,"entities","res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	rig.authority_gate=is_ready;rig.shot_authority=register_shot
	rig.rounds_sim.authoritative_contact.connect(contact)
	for entry:Dictionary in rig.weapons:
		saved_states.append({"state":entry.state,"profile":entry.state.profile.duplicate(true),"ability_state":entry.state.ability_state,"wear_per_shot":entry.state.wear_per_shot})
		entry.state.ability_state=null;entry.state.wear_per_shot=0.0
		entry.state.profile["abilities"]=[]
	if rig.get("unarmed") is Dictionary:
		for state in rig.unarmed.values():
			saved_states.append({"state":state,"profile":state.profile.duplicate(true),"ability_state":state.ability_state,"wear_per_shot":state.wear_per_shot})
			state.ability_state=null;state.wear_per_shot=0.0;state.profile["abilities"]=[]
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
			if str(placement.get("mobile",""))=="chassis_dealer":
				projected.append(copy);continue # Native randomized dealer appearance owns this identity.
			copy["source_placement_visual"]={"placement_id":placement_id,"appearance_id":str(placement.get("appearance_id",placement.template)),"catalog":str(ambient_source.catalog_path),"cell_id":str(placement.get("cell_id",""))}
		projected.append(copy)
	return projected

func synchronize_ambient(_snapshot_actors:Array)->void:
	if not is_instance_valid(ambient_source):return
	var presented:Dictionary=ambient_source.live_suppressed.duplicate()
	for id:String in ambient_bindings.bindings:
		if not actors.has(id):continue # Retain already-presented known-dead/range tombstones.
		var placement_id:=str(ambient_bindings.bindings[id]);var report:Dictionary=actors[id].report
		var native_dealer:bool=str(ambient_bindings.placements[placement_id].get("mobile",""))=="chassis_dealer" and report.get("appearance_status","") in ["complete","partial"]
		if native_dealer or (report.get("source_variant_ready",false) and str(report.get("source_placement_id",""))==placement_id):presented[placement_id]=id
		else:presented.erase(placement_id)
	ambient_source.set_live_suppressed(presented)

func owner()->Dictionary:
	return preload("res://combat/movement_reconciliation.gd").stamp_request({"account":owner_account,"character_id":owner_character,"session_id":session_id},player_state)

func discard_movement_commands()->void:
	var discarded_life:bool=queue.any(func(request):return request.get("kind","")=="life")
	queue.clear();shots.clear();native_ready=false
	if discarded_life and not life_action_pending.is_empty():
		var action:=life_action_pending;life_action_pending=""
		life_action_finished.emit(action,false,"Movement corrected; action cancelled.")
	last_error="Movement corrected; queued combat gestures discarded."
	if is_instance_valid(rig) and is_instance_valid(rig.rounds_sim):rig.rounds_sim.clear()

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
	cancel_showdown()
	life_action_pending="";pending_transport={};notified_transport_id=""
	generation+=1;live=false;native_ready=false;busy=false;session_id="";sequence=-1;weapon={};player_state={};queue.clear();shots.clear();next_launch_usec=0;backend_retry_usec=0
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
	return live and native_ready and pending_transport.is_empty() and life_action_pending.is_empty() and not bool(player_state.get("cloning",false)) and not session_id.is_empty() and bool(weapon.get("certified",false)) and not bool(player_state.get("feigning_death",false)) and not bool(player_state.get("dead",false)) and not bool(player_state.get("incapacitated",false)) and int(player_state.get("posture",0)) not in [12,13,14] and elapsed_since_snapshot<SESSION_TIMEOUT

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
	return posture>=0 and posture<=14 and float(value.posture)==posture and bool(value.dead)==(posture==14) and bool(value.incapacitated)==(posture==13 and not bool(value.get("feigning_death",false))) and is_finite(float(value.get("shock_wounds",NAN))) and float(value.shock_wounds)>=0

func accept_response(response:Dictionary,initial:=false)->bool:
	if not bool(response.get("ok",response.get("session_live",false))) or response.get("backend","")!="core3" or response.get("source_kind","")!="core3_live_combat" or str(response.get("character_id",""))!=owner_character or not bool(response.get("session_live",false)):
		last_error=str(response.get("error","Core3 session was lost."));return false
	var incoming:=str(response.get("session_id",""));var revision:=int(response.get("sequence",-1))
	if revision<0 or incoming.is_empty() or (not initial and incoming!=session_id) or revision<sequence:last_error="Stale or mismatched live Core3 snapshot.";return false
	var snapshot:Dictionary=response.get("snapshot",{})
	var ship_player:Dictionary=snapshot.get("player",{}) if snapshot.get("player") is Dictionary else {}
	var ship_state:Variant=ship_player.get("jtl",snapshot.get("jtl",{}))
	var space_active:bool=ship_player.get("space_active",false) and ship_state is Dictionary and ship_state.get("scope","") in ["noncombat_yacht","noncombat_navigation"] and ship_state.get("enabled",false) and ship_state.get("ship") is Dictionary and str(ship_state.ship.get("station","")) in ["pilot","passenger","gunner","interior"]
	if space_active and snapshot.get("weapon")==null:
		snapshot=snapshot.duplicate(false);snapshot.weapon={}
	if not snapshot.get("ready") is bool or not snapshot.get("full",false) or snapshot.get("truncated",false) or not snapshot.get("actors") is Array or snapshot.actors.size()>MAX_ACTORS or not snapshot.get("player") is Dictionary or not snapshot.get("weapon") is Dictionary:last_error="Incomplete live Core3 snapshot.";return false
	if not snapshot.get("transport",{}) is Dictionary:
		last_error="Invalid authoritative medical transport.";return false
	var transport: Dictionary = snapshot.get("transport",{})
	if not transport.is_empty() and (str(transport.get("id","")).is_empty() or not transport.get("destination") is Dictionary or not preload("res://combat/live_transport.gd").new().destination_valid(transport.destination)):
		last_error="Invalid authoritative medical transport.";return false
	var life_locked: bool = space_active or bool(snapshot.player.get("dead",false)) or bool(snapshot.player.get("incapacitated",false)) or not transport.is_empty()
	var incoming_weapon:Dictionary=snapshot.weapon
	if not life_locked and (str(incoming_weapon.get("item_id","")).is_empty() or not incoming_weapon.get("certified",false) or float(incoming_weapon.get("fire_interval_seconds",0))<=0 or float(incoming_weapon.get("max_range_m",0))<=0):last_error="Native equipped weapon is unavailable or uncertified.";return false
	for key in ["fire_interval_seconds","max_range_m","projectile_speed"]:
		if not life_locked and (not is_finite(float(incoming_weapon.get(key,NAN))) or float(incoming_weapon[key])<=0):last_error="Invalid native weapon timing or range.";return false
	if not life_locked and not (bool(incoming_weapon.get("unarmed",false)) and rig.get("unarmed") is Dictionary and not rig.unarmed.is_empty()) and not rig.weapons.any(func(entry):return str(entry.state.profile.get("item_id",""))==str(incoming_weapon.get("item_id",""))):
		last_error="Native equipped weapon has no matching owned client profile.";return false
	var seen:Dictionary={}
	for value in snapshot.actors:
		if not value is Dictionary or not valid_actor(value) or seen.has(str(value.get("id",""))):last_error="Malformed live Core3 actor snapshot.";return false
		seen[str(value.id)]=true
	if not valid_player(snapshot.player):last_error="Incomplete or invalid authoritative player HAM/posture.";return false
	var seconds:=maxf(elapsed_since_snapshot,POLL_INTERVAL)
	session_id=incoming;sequence=revision;native_ready=bool(snapshot.ready);weapon=incoming_weapon.duplicate(true);player_state=preload("res://combat/movement_reconciliation.gd").annotate(snapshot.player,response);pending_transport=transport.duplicate(true)
	if snapshot.get("jtl") is Dictionary:player_state.jtl=snapshot.jtl
	if space_active:
		queue.clear();shots.clear();cancel_showdown()
		if is_instance_valid(rig) and is_instance_valid(rig.rounds_sim):rig.rounds_sim.clear()
	for value:Dictionary in source_visual_records(snapshot.actors):
		if preload("res://scripts/service_world.gd").presents_actor(app,value):
			seen.erase(str(value.id));continue
		var id:=str(value.id);var recreate:bool=not actors.has(id) or bool(actors[id].record.dead)!=bool(value.dead) or str(actors[id].record.template)!=str(value.template) or float(actors[id].record.get("scale",1))!=float(value.get("scale",1)) or actors[id].record.get("customization",{})!=value.get("customization",{}) or actors[id].record.get("source_placement_visual",{})!=value.get("source_placement_visual",{})
		if recreate:
			if actors.has(id):actors[id].collision_layer=0;actors[id].visible=false;actors[id].queue_free();actors.erase(id)
			var actor:=Actor.new();add_child(actor)
			actor.catalog_candidates=app.planet_assets.get("entity_catalogs",[]) if app.get("planet_assets") is Dictionary else []
			if not actor.configure(value,session_id,assets,dead_assets,actor_catalog):last_error=str(actor.report.get("error","Original actor model unavailable"));actor.free();return false
			actors[id]=actor;actor.add_to_group("swg_radar_contacts")
		var pose:=Transform3D(Basis(Vector3.UP,-float(value.heading_radians)),world(value.position))
		if is_instance_valid(stage):pose.basis=stage.global_basis*pose.basis
		actors[id].apply_record(value,pose,seconds,recreate)
		# Keep native pet targeting/health/collision identity while the ride layer
		# owns its visible body. Healing and pet commands must retain this actor.
		if is_instance_valid(actors[id].visual):
			actors[id].visual.visible=not (is_instance_valid(app.get("vehicles")) and app.vehicles.vehicles.has(id))
		floor_projection.apply(actors[id],value,app.get("terrain") if is_instance_valid(app) else null,stage)
	for id:String in actors.keys():
		if not seen.has(id):actors[id].collision_layer=0;actors[id].visible=false;actors[id].queue_free();actors.erase(id)
	for entry:Dictionary in rig.weapons:
		if not weapon.is_empty() and str(entry.state.profile.get("item_id",""))==str(weapon.get("item_id","")) and float(weapon.get("fire_interval_seconds",0))>0 and float(weapon.get("max_range_m",0))>0:
			entry.state.profile.rpm=60.0/float(weapon.fire_interval_seconds)
			# Native cadence already includes the current armour output penalty.
			var captured: Dictionary = entry.state.profile.get("armour_scales", {}).duplicate(true)
			captured["output_scale"] = float(player_state.get("armour", {}).get("output_scale", 1))
			entry.state.profile["armour_scales"] = captured
			entry.state.profile["profession"]={"rpm_scale":1.0}
			entry.state.profile.projectile_speed=float(weapon.get("projectile_speed",100))
			entry.state.core.maxRange=float(weapon.max_range_m)
			sync_commando_profile(entry.state)
			sync_bountyhunter_profile(entry.state)
	sync_native_abilities()
	synchronize_ambient(snapshot.actors)
	var feedback: Variant = player.get("feedback")
	if feedback != null and feedback.get("vital") != null: feedback.vital.observe(player_state.get("vital_feedback",{}))
	live=true;elapsed_since_snapshot=0;last_error="";update_appearance_report();snapshot_applied.emit(player_state.duplicate(true))
	if not initial and not pending_transport.is_empty() and str(pending_transport.id)!=notified_transport_id:
		notified_transport_id=str(pending_transport.id)
		transport_required.emit(pending_transport.duplicate(true))
	write_status();return live and session_id==incoming

func sync_native_abilities() -> void:
	if is_instance_valid(rig.get("squad_leader")):rig.squad_leader.observe(player_state.get("squad_leader",{}),session_id+":"+str(sequence),register_squadleader,world,is_ready)
	rig.commando_authority=register_commando
	if rig.has_method("configure_bountyhunter"):rig.configure_bountyhunter(player_state.get("bountyhunter",{}),register_bountyhunter,str(weapon.get("item_id","")),session_id)
	if rig.has_method("configure_rifleman"):rig.configure_rifleman(player_state.get("rifleman",{}),register_rifleman,str(weapon.get("item_id","")))
	if rig.has_method("configure_carbineer"):rig.configure_carbineer(player_state.get("carbineer",{}),register_carbineer,str(weapon.get("item_id","")))
	if rig.has_method("configure_pistoleer"):
		rig.configure_pistoleer(player_state.get("pistoleer",{}),register_pistoleer,str(weapon.get("item_id","")))
		rig.showdown_gate=showdown_status
	if is_instance_valid(rig.get("inventory")) and rig.inventory.has_method("set_combat_loadout_context"):
		rig.inventory.set_combat_loadout_context(weapon if live else {},request_loadout)
	if rig.has_method("configure_pikeman"):rig.configure_pikeman(player_state.get("pikeman",{}),register_pikeman,str(weapon.get("item_id","")),str(weapon.get("ability_loadout",{}).get("ultimate","")))
	if rig.has_method("configure_fencer"):rig.configure_fencer(player_state.get("fencer",{}),register_fencer,str(weapon.get("item_id","")),str(weapon.get("ability_loadout",{}).get("ultimate","")))
	if rig.has_method("configure_swordsman"):rig.configure_swordsman(player_state.get("swordsman",{}),register_swordsman,str(weapon.get("item_id","")),str(weapon.get("ability_loadout",{}).get("ultimate","")))
	if rig.has_method("configure_tka"):rig.configure_tka(player_state.get("tka",{}),register_tka,str(weapon.get("item_id","")),str(weapon.get("ability_loadout",{}).get("ultimate","")))
	if rig.has_method("configure_brawler"):rig.configure_brawler(player_state.get("brawler_buffs",{}),register_brawler_buff,str(weapon.get("item_id","")))
	if rig.has_method("configure_warcry"):rig.configure_warcry(player_state.get("warcry",{}),register_warcry)
	if rig.has_method("configure_taunt"):rig.configure_taunt(player_state.get("taunt",{}),register_taunt)
	var entries:Array=weapon.get("abilities",[])
	if rig.get("unarmed") is Dictionary:
		for state in rig.unarmed.values():
			state.profile["abilities"]=entries.duplicate(true) if weapon.get("unarmed",false) else []
			state.profile["ability_loadout"]=weapon.get("ability_loadout",{}).duplicate(true) if weapon.get("unarmed",false) else {}
			state.profile["item_id"]=str(weapon.get("item_id","")) if weapon.get("unarmed",false) else ""
	for entry:Dictionary in rig.weapons:
		var matching:bool=str(entry.state.profile.get("item_id",""))==str(weapon.get("item_id",""))
		entry.state.profile["abilities"]=entries.duplicate(true) if matching else []
		entry.state.profile["ability_loadout"]=weapon.get("ability_loadout",{}).duplicate(true) if matching else {}
	if abilities_revision!=sequence:
		abilities_revision=sequence
		for ability:Dictionary in entries:
			var id:=str(ability.get("id",""))
			rig.abilities.cooldowns[id]=maxf(float(rig.abilities.cooldowns.get(id,0)),float(ability.get("cooldown_remaining_seconds",0)))
	rig.abilities.reconcile(rig.active_profile())

func squad_ability(id:String)->Dictionary:
	for entry:Dictionary in player_state.get("squad_leader",{}).get("abilities",[]):
		if str(entry.get("id",""))==id:return entry
	for entry:Dictionary in weapon.get("abilities",[]):
		if str(entry.get("id",""))==id:return entry
	return {}
func register_squadleader(ability:String,target_id:String,pose:Transform3D,hand:String)->bool:
	var entry:=squad_ability(ability);var now:=Time.get_ticks_usec()
	if ability not in ["steady_aim","rally","form_up","boost_morale","retreat","volley_fire"] or not is_ready() or entry.is_empty() or not entry.get("learned",true) or not entry.get("conditions_met",false) or float(entry.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or shots.size()>=MAX_SHOTS or queue.size()>=MAX_QUEUE:return false
	if target_id.is_empty() or not pose.is_finite() or hand not in ["left","right"] or str(rig.active_profile().get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="volley_fire":
		if str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability or not actors.has(target_id) or not is_instance_valid(rig.get("squad_leader")) or not rig.squad_leader.enemy(actors.get(target_id)):return false
	else:
		if not is_instance_valid(rig.get("squad_leader")) or rig.squad_leader.person(target_id).is_empty():return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(entry.get("action_cost",INF)) or float(ham[2])<=float(entry.get("mind_cost",INF)):return false
	var interval:=maxf(.25,float(entry.get("interval_seconds",2)))
	next_launch_usec=now+int(interval*1000000);serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.item_id),"ability_id":ability,"target_id":target_id,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	rig.abilities.cooldowns[ability]=float(entry.get("cooldown_seconds",0))
	queue.append({"kind":"squadleader","payload":payload,"shot_id":id});return true
func attack_range(ability:String)->float:
	for row:Dictionary in weapon.get("abilities",[]):
		if str(row.get("id",""))==ability:return maxf(0,float(row.get("max_range_m",weapon.get("max_range_m",0))))
	return maxf(0,float(weapon.get("max_range_m",0)))
func volley_intent(pose:Transform3D,maximum:float,target_id:="")->Dictionary:
	if not is_ready() or not is_instance_valid(rig.get("squad_leader")):return {}
	return rig.squad_leader.volley_intent(pose,maximum,target_id)

func register_commando(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("commando",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability!="overdrive" or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or context.get("active",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or not rig.two_hands or not rig.support_latched or str(weapon.get("native_family",""))!="commando" or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability:return false
	var state=rig.weapons[rig.selected].state
	if not state.certified() or state.condition_max<2 or state.condition_damage>=state.condition_max:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.is_finite() or hand not in ["left","right"]:return false
	var interval:=float(context.get("interval_seconds",.25))
	next_launch_usec=now+int(interval*1000000);serial+=1
	state.next_shot=maxf(state.next_shot,state.clock+interval)
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000,"ammo_state":state,"ammo_spent":0}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z),"two_hands":true})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",120))
	queue.append({"kind":"commando","payload":payload,"shot_id":id});return true

func sync_commando_profile(state:RefCounted)->void:
	if str(weapon.get("native_family",""))!="commando":return
	for key in ["native_family","commando_family","delivery","charge_limited","cone_angle_degrees","beam_radius_m","area_radius_m","target_cap","area_budget_multiplier","action_cost","mind_cost","normalized_damage"]:
		if weapon.has(key):state.profile[key]=weapon[key]
	if weapon.get("charge_limited",false):
		var reserved:bool=shots.values().any(func(pending:Dictionary):return pending.get("ammo_state")==state and not pending.get("accepted",false) and int(pending.get("ammo_spent",0))>0)
		state.observe_native_charges(int(weapon.get("charges",0)),session_id,sequence,reserved)

func sync_bountyhunter_profile(state:RefCounted)->void:
	for key in ["delivery","pellet_count","half_angle_degrees","acquisition_degrees","turn_degrees_per_second","max_turn_degrees"]:
		if weapon.has(key):state.profile[key]=weapon[key]

func register_bountyhunter(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("bountyhunter",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["duelist_stance","underhand_shot"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or context.get("active",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	var state=rig.weapons[rig.selected].state
	var family:=str(state.profile.get("class",""))
	if state.is_melee() or not state.certified() or state.condition_max<2 or state.condition_damage>=state.condition_max or state.reload_until>=0:return false
	if family not in ["holdout","pistol","heavy_pistol","carbine","burst_carbine"] and str(state.profile.get("id",""))!="rifle_lightning":return false
	if ability=="underhand_shot" and (family not in ["carbine","burst_carbine"] or not rig.two_hands or not rig.support_latched):return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.is_finite() or hand not in ["left","right"]:return false
	var target_id:=""
	if ability=="duelist_stance":
		var hit:Dictionary=rig.target_abilities.query(pose.origin,pose.origin-pose.basis.z*float(weapon.max_range_m)*state.range_scale(rig.two_hands))
		var actor:Variant=hit.get("collider")
		if not hit.get("complete",false) or not rig.target_abilities.actor_eligible(actor):return false
		target_id=str(actor.record.id)
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000,"ammo_state":state,"ammo_spent":0}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.item_id),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z),"two_hands":rig.two_hands})
	if not target_id.is_empty():payload.target_id=target_id
	if ability=="duelist_stance":rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",60))
	else:rig.bountyhunter_arm_pending=str(weapon.item_id);rig.bountyhunter_arm_pending_shot=id;rig.bountyhunter_arm_pending_until=now+8000000
	next_launch_usec=now+100000
	queue.append({"kind":"bountyhunter","payload":payload,"shot_id":id});return true

func guided_target(pose:Transform3D,maximum:float)->String:
	var nearest:=deg_to_rad(5.);var selected:=""
	for id:String in actors:
		var actor:Node3D=actors[id]
		if not rig.target_abilities.actor_eligible(actor):continue
		var point:=actor.global_position+Vector3.UP
		var offset:=point-pose.origin
		if offset.length()>maximum or offset.length_squared()<.01:continue
		var angle:=(-pose.basis.z).angle_to(offset.normalized())
		if angle<=nearest and rig.target_abilities.clear_line(pose.origin,point,actor):nearest=angle;selected=id
	return selected

func register_rifleman(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("rifleman",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability!="rifleman_focus" or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or context.get("active",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or not rig.two_hands or not rig.support_latched or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	var state=rig.weapons[rig.selected].state
	if state.is_melee() or str(state.profile.get("class","")) not in ["rifle","marksman","repeater","bowcaster","slugthrower"] or not state.certified() or state.condition_max<2 or state.condition_damage>=state.condition_max or state.reload_until>=0:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.is_finite() or hand not in ["left","right"]:return false
	var interval:=float(context.get("interval_seconds",.25))
	next_launch_usec=now+int(interval*1000000);serial+=1
	state.next_shot=maxf(state.next_shot,state.clock+interval)
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000,"ammo_state":state,"ammo_spent":0}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z),"two_hands":true})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	queue.append({"kind":"rifleman","payload":payload,"shot_id":id});return true

func register_carbineer(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("carbineer",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["full_auto_sweep","tactical_brace","charge_blast"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or context.get("active",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or not rig.two_hands or not rig.support_latched or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="charge_blast" and str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability:return false
	var state=rig.weapons[rig.selected].state
	if state.is_melee() or str(state.profile.get("class","")) not in ["carbine","burst_carbine"] or not state.certified() or state.condition_max<2 or state.condition_damage>=state.condition_max or state.reload_until>=0:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.is_finite() or hand not in ["left","right"]:return false
	var ammo:=0 if ability=="tactical_brace" else 3
	if ammo>0 and not state.reserve_rounds(ammo):return false
	var interval:=float(context.get("interval_seconds",1))
	next_launch_usec=now+int(interval*1000000);serial+=1
	state.next_shot=maxf(state.next_shot,state.clock+interval)
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability,"area_pose":pose,"area_grip":rig.weapons[rig.selected].visual.global_position,"area_profile":state.ranged_snapshot(true,rig.current_firing_posture())},"accepted":false,"contacted":false,"expires_usec":now+8000000,"ammo_state":state,"ammo_spent":ammo}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z),"two_hands":true})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	if ability in ["full_auto_sweep","charge_blast"]:payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"carbineer","payload":payload,"shot_id":id});return true

func register_pistoleer(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("pistoleer",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["fan_shot","run_and_gun"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or context.get("active",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	var state=rig.weapons[rig.selected].state
	if state.is_melee() or str(state.profile.get("class","")) not in ["holdout","pistol","heavy_pistol"] or not state.certified():return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.is_finite() or hand not in ["left","right"]:return false
	var ammo:=3 if ability=="fan_shot" else 0
	if ammo>0 and not state.reserve_rounds(ammo):return false
	next_launch_usec=now+int(float(context.get("interval_seconds",1))*1000000);serial+=1
	state.next_shot=maxf(state.next_shot,state.clock+float(context.get("interval_seconds",1)))
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability,"fan_pose":pose,"fan_grip":rig.weapons[rig.selected].visual.global_position,"fan_profile":state.ranged_snapshot(false,rig.current_firing_posture())},"accepted":false,"contacted":false,"expires_usec":now+8000000,"ammo_state":state,"ammo_spent":ammo}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	if ability=="fan_shot":payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"pistoleer","payload":payload,"shot_id":id});return true

func showdown_status(id:String)->String:
	if not is_ready() or showdown_volley.is_empty() or str(showdown_volley.id)!=id or Time.get_ticks_usec()>int(showdown_volley.expires_usec) or str(weapon.get("item_id",""))!=str(showdown_volley.item_id) :return "invalid"
	var volley_ability:=str(showdown_volley.get("ability_id","showdown"))
	var definition:Dictionary={}
	for entry:Dictionary in weapon.get("abilities",[]):
		if str(entry.get("id",""))==volley_ability:definition=entry;break
	if not preload("res://combat/loadout.gd").equipped(definition,weapon.get("ability_loadout",{})) or showdown_volley.get("loadout",{})!=weapon.get("ability_loadout",{}):return "invalid"
	var actor:Variant=actors.get(str(showdown_volley.target_id))
	if not is_instance_valid(actor) or not actor.is_targetable() or actor.record.get("dead",false) or actor.record.get("incapacitated",false):return "invalid"
	return "ready" if showdown_volley.get("accepted",false) and Time.get_ticks_usec()>=next_launch_usec else "pending"

func cancel_showdown()->void:
	showdown_volley.clear()
	if is_instance_valid(rig) and rig.has_method("cancel_showdown"):rig.cancel_showdown()

func register_pikeman(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("pikeman",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["overhead_whirl","sweeping_trip","driving_jabs","whirlwind"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="whirlwind" and str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+int(float(context.get("interval_seconds",1))*1000000);serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"pikeman","payload":payload,"shot_id":id});return true

func register_fencer(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("fencer",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["probing_jabs","raking_slash","guard_bash","flawless_assault"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="flawless_assault" and str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+int(float(context.get("interval_seconds",1))*1000000);serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"fencer","payload":payload,"shot_id":id});return true

func register_swordsman(ability:String,pose:Transform3D,hand:String,target_id:="")->bool:
	var context:Dictionary=player_state.get("swordsman",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["overhead_cleave","ground_slam","armour_break"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or float(rig.abilities.cooldowns.get(ability,0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="armour_break" and (target_id.is_empty() or str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability):return false
	if ability!="armour_break" and not target_id.is_empty():return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+int(float(context.get("interval_seconds",1))*1000000);serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand,"ability_id":ability},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	if ability=="armour_break":payload["target_id"]=target_id
	rig.abilities.cooldowns[ability]=float(context.get("cooldown_seconds",0))
	payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"swordsman","payload":payload,"shot_id":id});return true

func register_tka(ability:String,pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("tka",{}).get(ability,{})
	var now:=Time.get_ticks_usec()
	if ability not in ["tka_sweep","tka_half_spin","tka_volley","indomitable_focus"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if not weapon.get("unarmed",false) or rig.selected>=0:return false
	if not rig.unarmed.has(rig.dominant) or str(rig.unarmed[rig.dominant].profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if ability=="indomitable_focus" and str(weapon.get("ability_loadout",{}).get("ultimate",""))!=ability:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+int(float(context.get("interval_seconds",1))*1000000);serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	if ability!="indomitable_focus":payload.merge(volley_intent(pose,attack_range(ability),str(payload.get("target_id",""))))
	queue.append({"kind":"tka","payload":payload,"shot_id":id});return true

func register_brawler_buff(ability:String,hand:String)->bool:
	var context:Dictionary=player_state.get("brawler_buffs",{}).get(ability,{})
	var ham:Array=player_state.get("ham",[])
	var now:=Time.get_ticks_usec()
	if ability not in ["center_of_being","berserk"] or not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	next_launch_usec=now+1000000;serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"ability_id":ability})
	queue.append({"kind":"brawler_buff","payload":payload,"shot_id":id});return true

func register_warcry(pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("warcry",{})
	var now:=Time.get_ticks_usec()
	if not is_ready() or not context.get("learned",false) or not context.get("conditions_met",false) or float(context.get("cooldown_remaining_seconds",0))>0 or now<next_launch_usec or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	var ham:Array=player_state.get("ham",[])
	if ham.size()!=3 or float(ham[1])<=float(context.get("action_cost",INF)) or float(ham[2])<=float(context.get("mind_cost",INF)):return false
	if rig.selected<0 or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=str(weapon.get("item_id","")):return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+1000000
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.get("item_id","")),"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	queue.append({"kind":"warcry","payload":payload,"shot_id":id})
	return true

func register_taunt(pose:Transform3D,hand:String)->bool:
	var context:Dictionary=player_state.get("taunt",{})
	var now:=Time.get_ticks_usec()
	if not is_ready() or not bool(context.get("learned",false)) or float(context.get("cooldown_remaining_seconds",0))>0 or now<next_launch_usec or int(player_state.get("posture",0))!=0 or queue.size()>=MAX_QUEUE or shots.size()>=MAX_SHOTS:return false
	if not pose.origin.is_finite() or not pose.basis.is_finite() or hand not in ["left","right"]:return false
	next_launch_usec=now+int(maxf(1,float(context.get("interval_seconds",1)))*1000000)
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	shots[id]={"shot":{"hand":hand},"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	queue.append({"kind":"taunt","payload":payload,"shot_id":id})
	return true

func taunt_receipt(id:String,mutation:Dictionary)->void:
	if mutation.get("taunted",false) and rig.has_method("action_haptic"):rig.action_haptic("taunt",str(shots.get(id,{}).get("shot",{}).get("hand","")))
	shots.erase(id)

func register_melee(shot:Dictionary,pose:Transform3D)->Dictionary:
	if not is_ready() or str(weapon.get("kind",""))!="melee" or queue.size()>=MAX_QUEUE:return {}
	var item:=str(weapon.get("item_id",""))
	if not bool(weapon.get("unarmed",false)) and str(shot.get("item_id",""))!=item:return {}
	if bool(weapon.get("unarmed",false)) and str(shot.get("weapon_id",""))!="unarmed":return {}
	var requested:=str(shot.get("ability_id",""))
	var ability:Dictionary={}
	if not requested.is_empty():
		for entry:Dictionary in weapon.get("abilities",[]):
			if str(entry.id)==requested and entry.get("activation","")=="native_melee":ability=entry;break
		if ability.is_empty() or not preload("res://combat/loadout.gd").equipped(ability,weapon.get("ability_loadout",{})) or not ability.get("conditions_met",true) or str(shot.get("target_id","")).is_empty() or float(rig.abilities.cooldowns.get(requested,0))>0:return {}
		var cost:Array=rig.abilities.costs(ability)
		if cost.size()!=3:return {}
		for i in range(3):
			if rig.abilities.ham[i*3]<=float(cost[i]):return {}
	var now:=Time.get_ticks_usec()
	if now<next_launch_usec or shots.size()>=MAX_SHOTS:return {}
	next_launch_usec=now+int(float(ability.get("interval_seconds",weapon.fire_interval_seconds))*1000000)
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	var immutable:=shot.duplicate(true);immutable["item_id"]=item;immutable["shot_id"]=id;immutable["live_session"]=session_id
	var volley:=volley_intent(pose,float(ability.get("max_range_m",weapon.max_range_m)),str(shot.get("target_id",shot.get("volley_target_id",""))));immutable.erase("volley_mark_id");immutable.erase("volley_target_id");immutable.merge(volley)
	shots[id]={"shot":immutable.duplicate(true),"accepted":false,"contacted":false,"expires_usec":now+8000000}
	var payload:=owner();payload.merge({"shot_id":id,"item_id":item,"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)});payload.merge(volley)
	if not ability.is_empty():
		payload.merge({"ability_id":requested,"target_id":str(shot.target_id)})
		rig.abilities.cooldowns[requested]=float(ability.get("cooldown_seconds",0))
	queue.append({"kind":"pikeman" if ability.get("native_family","")=="pikeman" else "fencer" if requested in ["arterial_cut","nerve_strike","disorienting_thrust","exposing_thrust"] else "swordsman" if requested in ["rending_cut","disrupting_blow","hamstring","decisive_strike"] else "melee","payload":payload,"shot_id":id})
	return immutable

func melee_receipt(id:String,mutation:Dictionary)->void:
	if mutation.get("hit",false):
		confirmed_contacts+=1
		if rig.has_method("action_haptic"):rig.action_haptic("hit",str(shots.get(id,{}).get("shot",{}).get("hand","")))
	shots.erase(id)

func register_shot(shot:Dictionary,pose:Transform3D,grip:Vector3)->Dictionary:
	if str(shot.get("kind",""))=="melee":return register_melee(shot,pose)
	if not is_ready() or str(shot.get("item_id",""))!=str(weapon.item_id) or shots.size()>=MAX_SHOTS or queue.size()>=MAX_QUEUE:return {}
	var ability:Dictionary={}
	var requested:=str(shot.get("ability_id",""));var target_id:=str(shot.get("target_id",""))
	var heavy:bool=weapon.get("native_family","")=="commando"
	var direct:bool=heavy and (weapon.get("delivery","") in ["cone","beam"] or requested=="acid_spray")
	if heavy and weapon.get("commando_family","")!="pistol_launcher" and not shot.get("two_hands",false):return {}
	if heavy and weapon.get("charge_limited",false) and int(weapon.get("charges",0))<=0:return {}
	var volley_index:=int(shot.get("volley_index",0))
	var continuation:=requested in ["showdown","flurry_shot"] and volley_index>0
	if continuation and (volley_index not in [1,2] or showdown_status(str(shot.get("volley_id","")))!="ready" or int(showdown_volley.get("next_index",-1))!=volley_index or str(showdown_volley.get("ability_id","showdown"))!=requested or str(showdown_volley.get("target_id",""))!=target_id):return {}
	if not requested.is_empty():
		for entry:Dictionary in weapon.get("abilities",[]):
			if str(entry.get("id",""))==requested:ability=entry;break
		if requested!="underhand_shot" and not preload("res://combat/loadout.gd").equipped(ability,weapon.get("ability_loadout",{})):return {}
		if requested=="underhand_shot":
			if ability.is_empty() or not ability.get("conditions_met",false) or not shot.get("two_hands",false):return {}
			if float(rig.abilities.cooldowns.get(requested,0))>0:return {}
		else:
			if ability.is_empty() or not actors.has(target_id) or not actors[target_id].is_targetable() or (not continuation and not ability.get("conditions_met",true)):return {}
			var record:Dictionary=actors[target_id].record
			if record.get("relation","") not in ["hostile","attackable"] or record.get("dead",false) or record.get("incapacitated",false):return {}
			if not record.get("ability_target_available",{}).get(requested,true):return {}
			if ability.get("requires_control_available",false) and not record.get("melee_control_available",true):return {}
			if ability.get("excludes_bosses",false) and (record.get("boss",true) or int(record.get("level",151))>150):return {}
			if not continuation and float(rig.abilities.cooldowns.get(requested,0))>0:return {}
			var cost:Array=[0,0,0] if continuation else rig.abilities.costs(ability)
			if cost.size()!=3:return {}
			for index in range(3):
				if float(rig.abilities.ham[index*3])<=float(cost[index]):return {}
			if requested=="last_ditch" and (rig.abilities.ham[3]<=1 or rig.abilities.ham[6]<=1):return {}
			var distance:float=player.global_position.distance_to(actors[target_id].global_position)
			var limit:=float(ability.get("max_range_m",weapon.max_range_m))
			if is_equal_approx(limit,float(weapon.max_range_m)):limit*=float(shot.get("range_scale",1.0))
			if distance>minf(float(weapon.max_range_m)*float(shot.get("range_scale",1.0)),limit) or distance<float(ability.get("min_range_m",0)):return {}
	var now:=Time.get_ticks_usec()
	if now<next_launch_usec:return {}
	var interval:=float(weapon.get("special_interval_seconds",weapon.fire_interval_seconds)) if not requested.is_empty() else float(weapon.fire_interval_seconds)
	if requested in ["showdown","flurry_shot"] and volley_index<2:interval=.25
	elif requested=="flurry_shot":interval=float(weapon.fire_interval_seconds)
	elif not ability.is_empty():interval=float(ability.get("interval_seconds",interval))
	if requested=="sniper_shot" and not bool(shot.get("two_hands",false)):return {}
	var ammo_state:RefCounted=rig.weapons[rig.selected].state if (heavy or weapon.get("delivery","") in ["scatter","guided_bolt"] or requested in ["double_tap","disarming_shot","showdown","crippling_shot","wild_shot","charge_shot","suppression_fire","lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot","eye_shot","confusion_shot","fast_blast","underhand_shot","bleeding_shot"]) and rig.get("selected") is int and rig.selected>=0 else null
	var extra_ammo:=maxi(0,int(ability.get("ammo_cost",1))-1) if requested not in ["showdown","flurry_shot"] else 0
	if extra_ammo>0 and (ammo_state==null or not ammo_state.reserve_rounds(extra_ammo)):return {}
	next_launch_usec=now+int(interval*1000000)
	serial+=1
	var id:="%s-%d"%[session_id,serial]
	var immutable:=shot.duplicate(true);immutable["shot_id"]=id;immutable["live_session"]=session_id;immutable["launched_usec"]=now
	immutable.range=float(weapon.max_range_m)*float(shot.get("range_scale",1.0));immutable.speed=float(weapon.get("projectile_speed",shot.speed))
	var volley:=volley_intent(pose,minf(float(immutable.range),float(ability.get("max_range_m",immutable.range))),target_id if not target_id.is_empty() else str(shot.get("volley_target_id","")))
	immutable.erase("volley_mark_id");immutable.erase("volley_target_id");immutable.merge(volley)
	if not volley.is_empty():
		immutable["cosmetic_only"]=true
		if ammo_state==null and rig.selected>=0:ammo_state=rig.weapons[rig.selected].state
	if str(weapon.get("delivery","")) in ["scatter","guided_bolt"]:
		immutable["delivery"]=str(weapon.delivery)
		for key in ["pellet_count","half_angle_degrees","acquisition_degrees","turn_degrees_per_second","max_turn_degrees"]:
			if weapon.has(key):immutable[key]=weapon[key]
	if heavy:
		immutable["delivery"]=str(weapon.get("delivery",""))
	if direct:
		immutable["native_direct"]=true;immutable["heavy_pose"]=pose;immutable["heavy_grip"]=grip;immutable["heavy_profile"]=rig.active_profile().duplicate(true)
		immutable["heavy_profile"]["delivery"]="cone" if requested=="acid_spray" else "beam" if requested=="focused_discharge" else str(weapon.delivery)
		if requested=="acid_spray":immutable.heavy_profile.cone_angle_degrees=30.;immutable.range=minf(14,immutable.range)
	var payload:=owner();payload.merge({"shot_id":id,"item_id":str(weapon.item_id),"origin":source(pose.origin),"direction":source_direction(-pose.basis.z)})
	payload["two_hands"]=bool(shot.get("two_hands",float(shot.get("range_scale",1.0))>1.0 if int(rig.active_profile().get("hands",2))==1 else float(shot.get("range_scale",1.0))>.3));payload["firing_posture"]=str(shot.get("firing_posture","standing"));payload.merge(volley)
	if not ability.is_empty():
		payload.ability_id=str(ability.id)
		if not target_id.is_empty():payload.target_id=target_id
		immutable["ability"]=ability.duplicate(true)
		if not continuation:rig.abilities.cooldowns[str(ability.id)]=float(ability.get("cooldown_seconds",0))
	if immutable.get("delivery","")=="guided_bolt":
		var guidance:=target_id if not target_id.is_empty() else guided_target(pose,float(immutable.range))
		if not guidance.is_empty():
			payload["guided_target_id"]=guidance;immutable["guided_target_id"]=guidance
			immutable["guidance_actor"]=actors.get(guidance)
	if requested in ["showdown","flurry_shot"]:
		var volley_id:=str(shot.get("volley_id","")) if continuation else id
		payload.merge({"volley_id":volley_id,"volley_index":volley_index});immutable.merge({"volley_id":volley_id,"volley_index":volley_index})
		if not continuation:showdown_volley={"ability_id":requested,"loadout":weapon.get("ability_loadout",{}).duplicate(true),"id":id,"item_id":str(weapon.item_id),"target_id":target_id,"next_index":1,"accepted":false,"expires_usec":now+(2000000 if requested=="flurry_shot" else 2500000)}
		else:showdown_volley.next_index=volley_index+1;showdown_volley.accepted=false
		immutable.ability.interval_seconds=interval
	shots[id]={"shot":immutable.duplicate(true),"ammo_state":ammo_state,"ammo_spent":int(shot.get("local_ammo_spent",0))+extra_ammo,"accepted":false,"contacted":false,"expires_usec":now+int((float(immutable.range)/maxf(float(immutable.speed),1)+5.0)*1000000)}
	if direct:payload["ability_id"]=requested
	queue.append({"kind":"commando" if direct else "fire","payload":payload,"shot_id":id});return immutable

func contact(shot:Dictionary,target:Dictionary,position:Vector3,_normal:Vector3,_distance:float)->void:
	var id:=str(shot.get("shot_id",""));var target_id:=str(target.get("id",""))
	var world_rocket:bool=target_id=="0" and shot.get("delivery","")=="rocket"
	if shot.has("volley_mark_id"):return
	if not is_ready() or str(shot.get("live_session",""))!=session_id or str(target.get("session_id",""))!=session_id or not shots.has(id) or (not world_rocket and (not actors.has(target_id) or not actors[target_id].is_targetable())) or shots[id].contacted:return
	var bound_target:=str(shots[id].shot.get("target_id",shots[id].shot.get("guided_target_id","")))
	if not bound_target.is_empty() and target_id!=bound_target:
		shots[id].contacted=true;shots[id]["discard_contact"]=true
		if shots[id].accepted:shots.erase(id)
		return # Preserve an unacknowledged launch and its cost; never transfer damage.
	if queue.size()>=MAX_QUEUE:fail("Live combat request budget exceeded; session disarmed.");return
	shots[id].contacted=true
	var age:=float(shot.get("projectile_age_seconds",float(Time.get_ticks_usec()-int(shots[id].shot.launched_usec))/1000000.0))
	var payload:=owner();payload.merge({"shot_id":id,"target_id":target_id,"hit_position":source(position),"projectile_age_seconds":age})
	if shot.get("delivery","")=="scatter":
		var contacts:Array=[]
		for pellet:Dictionary in shot.get("pellet_contacts",[]):contacts.append({"pellet_index":int(pellet.pellet_index),"hit_position":source(pellet.hit_position),"projectile_age_seconds":float(pellet.projectile_age_seconds)})
		if contacts.is_empty():return
		payload["pellet_contacts"]=contacts
	queue.append({"kind":"impact","payload":payload,"shot_id":id})

func rejected_fire(id:String)->void:
	# A confirmed failed launch paid no SAC/cooldown. Replace only the local
	# reservation with the latest native value, never alter player resources.
	var pending:Dictionary=shots.get(id,{})
	if pending.get("accepted",false):return # Failed impacts never refund committed discharges.
	var state:Variant=pending.get("ammo_state")
	if state!=null and int(pending.get("ammo_spent",0))>0:state.refund_rounds(int(pending.ammo_spent));pending.ammo_spent=0
	var ability_id:=str(pending.get("shot",{}).get("ability_id",""))
	if ability_id in ["showdown","flurry_shot"]:
		cancel_showdown()
		if int(pending.get("shot",{}).get("volley_index",0))>0:return
	if ability_id.is_empty():return
	if ability_id=="underhand_shot" and rig.has_method("clear_bountyhunter"):rig.clear_bountyhunter()
	if ability_id in ["steady_aim","rally","form_up","boost_morale","retreat","volley_fire"]:
		rig.abilities.cooldowns[ability_id]=float(squad_ability(ability_id).get("cooldown_remaining_seconds",0));return
	if player_state.get("commando",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.commando[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("bountyhunter",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.bountyhunter[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("rifleman",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.rifleman[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("carbineer",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.carbineer[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("pistoleer",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.pistoleer[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("pikeman",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.pikeman[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("fencer",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.fencer[ability_id].get("cooldown_remaining_seconds",0));return
	if player_state.get("swordsman",{}).has(ability_id):
		rig.abilities.cooldowns[ability_id]=float(player_state.swordsman[ability_id].get("cooldown_remaining_seconds",0));return
	for entry:Dictionary in weapon.get("abilities",[]):
		if str(entry.get("id",""))==ability_id:
			rig.abilities.cooldowns[ability_id]=float(entry.get("cooldown_remaining_seconds",0));return

func movement_payload() -> Dictionary:
	var payload:=owner()
	if is_instance_valid(rig) and rig.has_method("guard_payload"):payload.guard_pose=rig.guard_payload(app,weapon)
	var feedback:Variant=player.get("feedback")
	if feedback!=null and feedback.get("feign_pose")!=null and (feedback.feign_available or feedback.feigning_death):payload.smuggler_pose=feedback.feign_pose.payload()
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
	if not live or not life_action_pending.is_empty() or not pending_transport.is_empty() or action not in ["recover","force_of_will","medical_transport"]:return false
	var posture:=int(player_state.get("posture",0))
	if action in ["recover","force_of_will"] and posture!=13:return false
	if action=="force_of_will" and not preload("res://combat/force_of_will.gd").available(player_state):return false
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

func settle_movement_rejection(response:Dictionary,request:Dictionary)->bool:
	# Only the global API's owned-envelope validator may mark this. The action
	# failed, but the same persistent session has already supplied its correction.
	if not response.get("_movement_correction_consumed",false):return false
	discard_movement_commands()
	poll_clock=POLL_INTERVAL;backend_retry_usec=0
	if request.kind=="life":
		var action:=str(request.payload.get("action",life_action_pending))
		life_action_pending=""
		life_action_finished.emit(action,false,str(response.get("error",response.get("error_code","Movement corrected."))))
	elif request.kind in ["fire","impact","melee","taunt","warcry","pikeman","fencer","swordsman","tka","brawler_buff","pistoleer","carbineer","rifleman","bountyhunter","commando"]:rejected_fire(str(request.get("shot_id","")));rejected_shots+=1
	return true

func pump()->void:
	if busy or not live or Time.get_ticks_usec()<backend_retry_usec:return
	var request:Dictionary
	if not queue.is_empty():request=queue.pop_front()
	elif poll_clock>=POLL_INTERVAL:
		if app.has_method("yield_live_poll_to_background") and app.yield_live_poll_to_background():return
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
	if settle_movement_rejection(response,request):return
	# This explicit gate rejection guarantees that this attempt never entered
	# Core3. Transport failures or uncertain mutations must still fail closed.
	if int(response.get("http_status",0))==503 and response.get("backend","")=="core3" and response.get("error_code","")=="backend_busy" and response.get("mutation_started") is bool and not response.mutation_started:
		backend_retry_usec=Time.get_ticks_usec()+int(clampf(float(response.get("retry_after",1)),.25,1.0)*1000000)
		if request.kind=="update" and not request.payload.has("transport_ack"):
			# Regenerate physical pose at the next poll instead of replaying old
			# movement after the shared native gate becomes available.
			poll_clock=POLL_INTERVAL
		else:
			var retries:=int(request.get("unstarted_retries",0))+1
			if retries>MAX_UNSTARTED_RETRIES or queue.size()>=MAX_QUEUE:
				fail("Core3 remained busy; the unstarted command could not be completed.");return
			request["unstarted_retries"]=retries
			queue.push_front(request)
		return
	backend_retry_usec=0
	# Services share this native session but use a separate HTTP request. A newer
	# service observation may arrive first; keep the older command's receipt
	# without rolling back its already-applied authoritative state.
	var older_owned: bool = bool(response.get("ok",response.get("session_live",false))) and response.get("backend","")=="core3" and response.get("source_kind","")=="core3_live_combat" and str(response.get("character_id",""))==owner_character and str(response.get("session_id",""))==session_id and bool(response.get("session_live",false)) and int(response.get("sequence",-1))>=0 and int(response.get("sequence",-1))<sequence
	if not older_owned and not accept_response(response):fail(last_error);return
	if request.kind=="life":
		var action := str(request.payload.action)
		life_action_pending=""
		var mutation: Dictionary=response.get("mutation",{})
		life_action_finished.emit(action,bool(mutation.get("success",false)),str(mutation.get("error_code",response.get("error_code",""))))
	combat_receipt(request,response)

func combat_receipt(request:Dictionary,response:Dictionary)->void:
	var id:=str(request.get("shot_id",""))
	if request.kind in ["fire","impact","melee","taunt","warcry","pikeman","fencer","swordsman","tka","brawler_buff","pistoleer","carbineer","rifleman","bountyhunter","commando","squadleader"]:
		var mutation:Dictionary=response.get("mutation",{})
		if not mutation.get("success",false) or str(mutation.get("shot_id",""))!=id:
			if request.kind in ["fire","melee","swordsman","fencer","pikeman","pistoleer","carbineer","rifleman","bountyhunter","commando","squadleader"]:rejected_fire(id)
			rejected_shots+=1;shots.erase(id);last_error=str(mutation.get("error_code",response.get("error","Core3 rejected the shot.")));return
		if mutation.get("volley_consumed",false):
			if is_instance_valid(rig.get("squad_leader")):rig.squad_leader.consumed(str(request.payload.get("volley_mark_id","")))
			confirmed_contacts+=1
			if rig.has_method("action_haptic"):rig.action_haptic("hit")
		if request.kind=="squadleader":
			next_launch_usec=maxi(next_launch_usec,Time.get_ticks_usec()+int(maxf(0,float(mutation.get("interval_seconds",2)))*1000000))
			if rig.has_method("action_haptic"):rig.action_haptic("hit",str(shots.get(id,{}).get("shot",{}).get("hand","")))
			shots.erase(id)
		elif request.kind=="fire" and shots.has(id):
			shots[id].accepted=true
			var discharge_recovery:=maxf(0,float(mutation.get("interval_seconds",0)))
			var discharge_state:Variant=shots[id].get("ammo_state")
			if discharge_state!=null:discharge_state.next_shot=maxf(discharge_state.next_shot,discharge_state.clock+discharge_recovery)
			next_launch_usec=maxi(next_launch_usec,Time.get_ticks_usec()+int(discharge_recovery*1000000))
			if shots[id].shot.get("ability_id","") in ["showdown","flurry_shot"] and showdown_volley.get("id","")==shots[id].shot.get("volley_id",""):
				showdown_volley.accepted=true
				# Space receipt-to-launch, so backlog cannot compress native cadence.
				next_launch_usec=Time.get_ticks_usec()+int(float(mutation.get("interval_seconds",.25))*1000000)
			if shots[id].get("discard_contact",false) or mutation.get("volley_consumed",false):shots.erase(id)
		elif request.kind=="impact":
			confirmed_contacts+=1;shots.erase(id)
			if int(mutation.get("damage",0))>0 and rig.has_method("action_haptic"):rig.action_haptic("hit")
		elif request.kind=="fencer" and str(mutation.get("ability_id",""))=="flawless_assault":
			if rig.has_method("action_haptic"):rig.action_haptic("hit",str(shots.get(id,{}).get("shot",{}).get("hand","")))
			shots.erase(id)
		elif request.kind in ["melee","swordsman","fencer","pikeman"]:melee_receipt(id,mutation)
		elif request.kind=="taunt":taunt_receipt(id,mutation)
		elif request.kind in ["pistoleer","carbineer","rifleman","bountyhunter","commando"]:
			var recovery:=maxf(0,float(mutation.get("interval_seconds",0)))
			var state:Variant=shots.get(id,{}).get("ammo_state")
			if state!=null:state.next_shot=maxf(state.next_shot,state.clock+recovery)
			next_launch_usec=maxi(next_launch_usec,Time.get_ticks_usec()+int(recovery*1000000))
			if str(mutation.get("ability_id",""))=="fan_shot" and rig.has_method("fan_shot_feedback"):rig.fan_shot_feedback(shots.get(id,{}).get("shot",{}))
			if request.kind=="bountyhunter" and rig.has_method("bountyhunter_feedback"):rig.bountyhunter_feedback(mutation)
			if request.kind=="carbineer" and rig.has_method("carbineer_feedback"):rig.carbineer_feedback(shots.get(id,{}).get("shot",{}))
			if request.kind=="commando" and str(mutation.get("ability_id",""))!="overdrive" and rig.has_method("commando_feedback"):rig.commando_feedback(shots.get(id,{}).get("shot",{}))
			shots.erase(id)
		elif request.kind in ["brawler_buff","tka"]:
			if rig.has_method("action_haptic"):rig.action_haptic("hit",str(shots.get(id,{}).get("shot",{}).get("hand","")))
			shots.erase(id)
		elif request.kind=="warcry":
			if int(mutation.get("affected",0))>0 and rig.has_method("action_haptic"):rig.action_haptic("hit",str(shots.get(id,{}).get("shot",{}).get("hand","")))
			shots.erase(id)

func _process(delta:float)->void:
	if not live:return
	if is_instance_valid(app.get("space")) and app.space.aboard():return
	if not pending_transport.is_empty() and bool(app.get("loading_stage")):
		elapsed_since_snapshot=0.0
		if queue.any(func(request):return request.payload.has("transport_ack")):pump()
		return
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

func request_loadout(proposal:Dictionary)->Dictionary:
	if busy or not live or not native_ready or elapsed_since_snapshot>=SESSION_TIMEOUT or not queue.is_empty():return {"success":false,"error":"Wait for the current Core3 action to finish."}
	if str(proposal.get("item_id",""))!=str(weapon.get("item_id","")):return {"success":false,"error":"Equipped weapon changed; select again."}
	var payload:=owner();payload.merge(proposal,true)
	var epoch:=generation;busy=true
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/loadout",payload)
	busy=false
	if epoch!=generation:return {"success":false,"error":"Character session changed."}
	if not apply_loadout_response(response):return {"success":false,"error":str(response.get("error",response.get("error_code","Core3 loadout response unavailable.")))}
	return {"success":bool(response.get("mutation",{}).get("success",false)),"error":str(response.get("mutation",{}).get("error_code","Loadout not saved."))}

func apply_loadout_response(response:Dictionary)->bool:
	return accept_response(response)
