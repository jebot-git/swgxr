extends Node
## Persistent native RPG connection without combat-lab actors or weapon assumptions.
signal snapshot_applied(player: Dictionary)
signal life_action_finished(action: String, success: bool, message: String)
signal transport_required(transport: Dictionary)
signal connection_lost(message: String)
var sequence:=-1
var player_state: Dictionary={}
var weapon_state: Dictionary={}
var pending_transport: Dictionary={}
var notified_transport_id:=""
var pending_ack:=""
var life_action_pending:=""
var app: Node
var live:=false
var session_id:=""
var character_id:=""
var busy:=false
var generation:=0
var next_update:=0.0
var last_position:=Vector3.INF
var last_error:=""
var last_confirmed_ms:=0
var last_smuggler_pose:Dictionary={}
var last_guard_mode:="none"
func setup(host: Node) -> void:app=host
func reset() -> void:
	generation+=1;live=false;session_id="";character_id="";busy=false
	last_smuggler_pose={};last_guard_mode="none"
	next_update=0;last_position=Vector3.INF;last_error="";last_confirmed_ms=0
	sequence=-1;player_state={};weapon_state={};pending_transport={};notified_transport_id="";pending_ack="";life_action_pending=""
func identity() -> Dictionary:
	var point: Vector3=app.source_position_at(app.player.global_position)
	var payload: Dictionary={"zone":preload("res://scripts/planet_catalog.gd").current(app),"account":app.datapad_account,"character_id":app.datapad_character_id,"position":[point.x,point.y,point.z],"heading_radians":-app.player.global_rotation.y,"building_id":"0","cell_index":0}
	if is_instance_valid(app.stage) and app.stage.get("current_cell") is Dictionary:
		var cell: Dictionary=app.stage.current_cell
		var key:=str(cell.get("cell_id",""))
		if key.contains(":"):
			payload.building_id=str(cell.get("building_object_id","0"));payload.cell_index=int(key.get_slice(":",1))
	if not session_id.is_empty():payload.session_id=session_id
	return payload # Stamp at dispatch after preceding native receipts are consumed.
func accept(result: Dictionary, starting:=false) -> bool:
	if not result.get("ok",false) or result.get("source_kind")!="core3_gameplay_session" or str(result.get("character_id",""))!=app.datapad_character_id or not result.get("session_live",false) or str(result.get("session_id","")).is_empty():
		last_error=str(result.get("error","Core3 session was not confirmed."));return false
	if not starting and not session_id.is_empty() and str(result.session_id)!=session_id:
		last_error="Core3 returned another session.";return false
	var revision:=int(result.get("sequence",-1))
	if revision<0:last_error="Core3 omitted its player snapshot revision.";return false
	# A valid older receipt can settle an action, but cannot roll back newer vitals.
	if not starting and revision<sequence:return true
	var snapshot: Variant=result.get("snapshot")
	if not snapshot is Dictionary or not snapshot.get("player") is Dictionary or not valid_player(snapshot.player):
		last_error="Incomplete or invalid authoritative player HAM/posture.";return false
	var transport: Variant=snapshot.get("transport",{})
	if not transport is Dictionary or (not transport.is_empty() and (str(transport.get("id","")).is_empty() or not transport.get("destination") is Dictionary or not preload("res://combat/live_transport.gd").new().destination_valid(transport.destination))):
		last_error="Invalid authoritative medical transport.";return false
	live=true;session_id=str(result.session_id);character_id=app.datapad_character_id;sequence=revision
	last_confirmed_ms=Time.get_ticks_msec();last_error=""
	weapon_state=snapshot.weapon.duplicate(true) if snapshot.get("weapon") is Dictionary else {}
	player_state=preload("res://combat/movement_reconciliation.gd").annotate(snapshot.player,result);pending_transport=transport.duplicate(true)
	if snapshot.get("jtl") is Dictionary:player_state.jtl=snapshot.jtl
	var rig:Variant=app.get("combat_rig")
	if is_instance_valid(rig) and rig.has_method("guard_feedback"):rig.guard_feedback(player_state.get("physical_guard",{}))
	if pending_transport.is_empty():pending_ack="";notified_transport_id=""
	if is_instance_valid(app.vehicles) and snapshot.get("vehicles") is Dictionary:app.vehicles.observe(snapshot.vehicles)
	snapshot_applied.emit(player_state.duplicate(true))
	if not starting and not pending_transport.is_empty() and str(pending_transport.id)!=notified_transport_id:
		notified_transport_id=str(pending_transport.id);transport_required.emit(pending_transport.duplicate(true))
	return true
func accept_native_response(result: Dictionary) -> bool:
	# Shared service commands return the underlying native envelope. Consume only
	# its owned player/transport state, never combat actors or weapon projection.
	if not live or result.get("backend")!="core3" or result.get("source_kind")!="core3_live_combat":
		last_error="Unexpected native gameplay envelope.";return false
	var snapshot: Variant=result.get("snapshot")
	if not snapshot is Dictionary or not snapshot.get("player") is Dictionary:
		last_error="Missing native gameplay player state.";return false
	var lightweight:=result.duplicate(false)
	lightweight.ok=bool(result.get("ok",result.get("session_live",false)))
	lightweight.source_kind="core3_gameplay_session"
	lightweight.snapshot={"player":snapshot.player,"transport":snapshot.get("transport",{}),"vehicles":snapshot.player.get("vehicles",{}),"weapon":snapshot.get("weapon",{})}
	return accept(lightweight)

func valid_player(value: Dictionary) -> bool:
	# Same native primary-pool/posture contract as live_world, without actor/weapon requirements.
	for key in ["ham","max_ham","wounds"]:
		var values: Variant=value.get(key)
		if not values is Array or values.size()!=3:return false
		for component in values:
			if not (component is int or component is float) or not is_finite(float(component)) or float(component)<0:return false
	for i in range(3):
		if float(value.max_ham[i])<=0 or float(value.wounds[i])>float(value.max_ham[i]) or float(value.ham[i])>float(value.max_ham[i])-float(value.wounds[i]):return false
	if not value.get("dead") is bool or not value.get("incapacitated") is bool or not (value.get("posture") is int or value.get("posture") is float):return false
	var posture:=int(value.posture)
	return posture>=0 and posture<=14 and float(value.posture)==posture and bool(value.dead)==(posture==14) and bool(value.incapacitated)==(posture==13 and not bool(value.get("feigning_death",false))) and is_finite(float(value.get("shock_wounds",NAN))) and float(value.shock_wounds)>=0

func request_life_action(action: String) -> bool:
	if not live or not life_action_pending.is_empty() or not pending_transport.is_empty() or bool(player_state.get("cloning",false)):return false
	var posture:=int(player_state.get("posture",0))
	if not ((action in ["recover","force_of_will"] and posture==13) or (action=="medical_transport" and posture in [13,14])):return false
	if action=="force_of_will" and not preload("res://combat/force_of_will.gd").available(player_state):return false
	life_action_pending=action;next_update=0
	return true
func acknowledge_transport(id: String) -> bool:
	if not live or pending_transport.is_empty() or str(pending_transport.get("id",""))!=id:return false
	pending_ack=id;next_update=0
	return true
func send_life_action() -> void:
	busy=true
	var epoch:=generation
	var action:=life_action_pending
	var payload:=identity();payload.action=action
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/life",payload)
	if epoch!=generation:return
	busy=false;life_action_pending="";next_update=0
	var accepted:=accept(result)
	var mutation: Dictionary=result.get("mutation",{})
	life_action_finished.emit(action,accepted and bool(mutation.get("success",false)),str(mutation.get("error",mutation.get("error_code",last_error))))

func start() -> bool:
	if live and character_id==app.datapad_character_id:return true
	if busy or app.datapad_character_id.is_empty():return false
	busy=true
	var epoch:=generation
	var owner: String=app.datapad_character_id
	var deadline:=Time.get_ticks_msec()+16000
	while app.api_requests_in_flight>0 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if epoch!=generation or owner!=app.datapad_character_id:return false
	if app.api_requests_in_flight>0:busy=false;last_error="A previous request is still pending.";return false
	var payload:=identity();payload.erase("session_id")
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/start",payload)
	if epoch!=generation or owner!=app.datapad_character_id:return false
	busy=false;next_update=1.0
	return accept(result,true)
func driving() -> bool:
	return is_instance_valid(app.vehicles) and app.vehicles.seated()
func native_requests_pending() -> bool:
	return app.native_requests_in_flight()>0 if app.has_method("native_requests_in_flight") else app.api_requests_in_flight>0
func authority_expired() -> bool:
	return Time.get_ticks_msec()-last_confirmed_ms>=preload("res://combat/live_world.gd").SESSION_TIMEOUT*1000.0
func movement_corrected()->void:
	# Force one fresh pose even while stationary; otherwise the idle throttle
	# delays rearming combat for three seconds after a corrected service action.
	last_position=Vector3.INF;next_update=0.1
func _process(delta: float) -> void:
	if not is_instance_valid(app) or app.session_leaving or not live:return
	if character_id!=app.datapad_character_id:reset();return
	next_update-=delta
	if str(guard_pose().get("mode","none"))!=last_guard_mode:next_update=0
	if busy or next_update>0 or native_requests_pending():return
	# Medical placement temporarily disables world_ready; its native arrival
	# acknowledgement must still run or the loading screen would deadlock.
	if not pending_ack.is_empty():update_pose();return
	if not life_action_pending.is_empty():send_life_action();return
	if not app.world_ready:return
	if is_instance_valid(app.get("space")) and app.space.aboard():return
	var combat:Variant=app.get("gameplay_combat")
	# Stale combat cannot submit its commands. Give the owned heartbeat priority
	# so that the queued gestures cannot prevent their own authority recovery.
	if is_instance_valid(combat) and combat.has_pending_commands() and not authority_expired():return
	if is_instance_valid(combat) and authority_expired():combat.fail("Core3 authority expired; queued combat gestures discarded.")
	var moved:=last_position.distance_squared_to(app.player.global_position)>.01
	if not driving() and not moved and smuggler_pose()==last_smuggler_pose and str(guard_pose().get("mode","none"))=="none" and last_guard_mode=="none" and Time.get_ticks_msec()-last_confirmed_ms<3000:return
	update_pose()
func smuggler_pose() -> Dictionary:
	var feedback:Variant=app.player.get("feedback")
	return feedback.feign_pose.payload() if feedback!=null and feedback.get("feign_pose")!=null and (feedback.feign_available or feedback.feigning_death) else {"tracked":false,"feign":false,"upright":false}

func guard_pose()->Dictionary:
	var rig:Variant=app.get("combat_rig")
	return rig.guard_payload(app,weapon_state) if is_instance_valid(rig) and rig.has_method("guard_payload") else {"mode":"none"}

func update_pose() -> void:
	var guard:=guard_pose()
	busy=true;next_update=0.15 if driving() else .2
	var epoch:=generation
	var payload:=identity()
	var pose:=smuggler_pose();payload.smuggler_pose=pose;payload.guard_pose=guard
	if driving():payload.vehicle_controls=app.vehicles.drive_payload()
	var medic: Variant=app.get("medic")
	if is_instance_valid(medic) and medic.has_method("tracked_pose"):payload.medic_pose=medic.tracked_pose()
	if not pending_ack.is_empty():payload.transport_ack=pending_ack
	payload.ready=bool(app.world_ready) or not pending_ack.is_empty()
	var sent_position: Vector3=app.player.global_position
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/update",payload)
	if epoch!=generation:return
	busy=false
	if accept(result):last_position=sent_position;last_smuggler_pose=pose;last_guard_mode=str(guard.mode)
	elif result.get("_movement_correction_consumed",false):
		# The API already adopted the owned rejection and moved the origin. Do
		# not queue the rejected position again or perform a redundant discovery.
		movement_corrected()
	elif result.get("error_code","")!="backend_busy" or Time.get_ticks_msec()-last_confirmed_ms>15000:
		# A boarding reply can be lost after Core3 has switched zones. Discover
		# transport through the read-only native snapshot; never omit the zone
		# fence from a pose update or resend an old source-world position.
		busy=true
		var discovered:Dictionary=await app.api(HTTPClient.METHOD_GET,"/combat/session?account="+str(app.datapad_account).uri_encode()+"&character_id="+str(app.datapad_character_id).uri_encode()+"&session_id="+session_id.uri_encode())
		if epoch!=generation:return
		busy=false
		if accept_native_response(discovered):return
		if Time.get_ticks_msec()-last_confirmed_ms<=15000:return
		live=false
		if is_instance_valid(app.asset_status):app.asset_status.text=last_error
		connection_lost.emit(last_error)
