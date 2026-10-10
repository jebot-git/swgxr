extends SceneTree
## Actual normal session, main life routing, feedback and loading orchestration.
## Native replies and destination geometry placement are mocked; no server/VR.
class Rig extends Node3D:
	var abilities:=preload("res://combat/ability_state.gd").new()
	var allowed:=true
	func set_allowed(value: bool)->void:allowed=value
class Loading extends Control:
	var messages: Array=[]
	var finished:=false
	var failure:=""
	func begin(message: String)->void:messages.append(message);finished=false
	func set_status(message: String)->void:messages.append(message)
	func finish()->void:finished=true
	func fail(message: String)->void:failure=message
class Placement extends RefCounted:
	var destinations: Array=[]
	func place(app: Node,destination: Dictionary)->Dictionary:
		destinations.append(destination.duplicate(true))
		await app.get_tree().process_frame
		app.player.global_position=Vector3(destination.position[0],destination.position[1],destination.position[2])
		return {"ok":true}
class Host extends "res://scripts/main.gd":
	var calls: Array=[]
	var response: Dictionary={}
	var ack_response: Dictionary={}
	var arrival_response: Dictionary={}
	func _ready()->void:pass
	func _process(_delta: float)->void:pass
	func _physics_process(_delta: float)->void:pass
	func close_menu()->void:player.active=true
	func source_position_at(point: Vector3)->Vector3:return point
	func api(_method: HTTPClient.Method,path: String,payload: Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		var result:=arrival_response.duplicate(true) if path.begins_with("/combat/session?") else ack_response.duplicate(true) if payload.has("transport_ack") else response.duplicate(true)
		await get_tree().process_frame
		return result
var failures: Array=[]
var checks:=0
func check(value: bool,label: String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func reply(posture: int,revision: int,transport: Dictionary={}) -> Dictionary:
	return {"ok":true,"source_kind":"core3_gameplay_session","character_id":"123","session_id":"normal","session_live":true,"sequence":revision,"snapshot":{"player":{"ham":[0 if posture==13 else 300,800,700],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":posture,"dead":posture==14,"incapacitated":posture==13,"shock_wounds":0,"cloning":not transport.is_empty(),"position":[2,3,4],"zone":"tatooine","building_id":"0","cell_index":0},"transport":transport},"mutation":{"success":true}}
func _initialize()->void:
	create_timer(20).timeout.connect(func():quit(2))
	call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.datapad_account="fixture";app.datapad_character_id="123";app.world_ready=true
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false);app.player.active=true
	app.stage=Node3D.new();app.add_child(app.stage)
	app.combat_rig=Rig.new();app.add_child(app.combat_rig)
	app.asset_status=Label.new();app.add_child(app.asset_status)
	app.loading_screen=Loading.new();app.add_child(app.loading_screen)
	app.medical_placement=Placement.new()
	app.response=reply(13,1)
	check(await app.ensure_gameplay_session(),"Normal persistent session starts with original incapacitated player state")
	var session: Node=app.gameplay_session;session.set_process(false)
	check(app.player.feedback.life_locked and app.player.feedback.observed_posture==13 and not app.player.feedback.local_prediction,"Normal snapshot drives shared forced life state with local prediction disabled")
	check(app.combat_rig.abilities.readout()[0].current==0,"Normal authoritative HAM reaches wrist readout")
	app.response={"ok":false,"error":"Unknown native failure"}
	check(app.player.feedback.request_life_action("recover"),"Existing deliberate recovery input routes into normal session")
	session._process(.1)
	for i in range(3):await process_frame
	check(app.calls.back().path=="/session/life" and app.calls.back().payload.action=="recover" and app.calls.back().payload.session_id=="normal","Normal life request uses exact owned lightweight native route")
	check(app.player.feedback.life_locked and not app.player.feedback.life_action_pending and app.player.feedback.life_status.contains("Unknown native failure"),"Unknown native failure releases pending input without granting recovery")
	app.response=reply(13,2);app.response.snapshot.player.recovery_requested=true;app.response.snapshot.player.recovery_remaining_seconds=4;app.response.snapshot.player.force_of_will={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0}
	app.player.feedback.request_life_action("recover");session._process(.1)
	for i in range(3):await process_frame
	check(app.player.feedback.life_locked and app.player.feedback.recovery_requested_authoritatively and app.player.feedback.recovery_remaining_seconds==4,"Accepted recovery intent waits for authoritative posture rather than standing locally")
	check(not app.player.feedback.request_life_action("recover"),"Already requested native recovery cannot be spammed")
	app.response=reply(0,3);app.response.snapshot.player.ham[0]=150
	check(app.player.feedback.request_life_action("force_of_will") and app.player.feedback.life_locked,"Force of Will uses shared main routing without predicted revival")
	session._process(.1)
	for i in range(3):await process_frame
	check(app.calls.back().path=="/session/life" and app.calls.back().payload.action=="force_of_will" and app.calls.back().payload.session_id=="normal","Force of Will sends only the owned life intent")
	check(not app.player.feedback.life_locked and app.combat_rig.abilities.readout()[0].current==150,"Authoritative Force of Will reply restores movement and projects recovered Health")
	check(session.accept(reply(0,3)) and not app.player.feedback.life_locked,"Only newer native awake snapshot releases forced viewpoint lock")
	check(session.accept(reply(13,2)) and not app.player.feedback.life_locked and session.sequence==3,"Older owned response cannot roll life/HAM back")
	var invalid:=reply(13,4);invalid.snapshot.player.dead=true
	check(not session.accept(invalid) and not app.player.feedback.life_locked,"Contradictory native posture/dead flags cannot alter presentation")
	app.combat_rig.free();app.combat_rig=null
	session.accept(reply(14,4))
	check(app.player.feedback.life_locked and app.player.feedback.observed_posture==14,"Normal death without combat rig still applies existing forced death feedback")
	var transport: Dictionary={"id":"medical-1","kind":"medical","destination":{"zone":"tatooine","position":[25,5,-30],"building_id":"0","cell_index":0}}
	app.response=reply(14,5,transport);app.ack_response=reply(14,6)
	app.ack_response.snapshot.player.cloning=true
	app.arrival_response=reply(0,7);app.arrival_response.backend="core3";app.arrival_response.source_kind="core3_live_combat"
	check(app.player.feedback.request_life_action("medical_transport"),"Existing suicide/medical transport action routes from normal death")
	session._process(.1)
	for i in range(20):
		await process_frame
		session._process(.2)
		if not app.live_transport_busy and app.loading_screen.finished:break
	check(app.medical_placement.destinations==[transport.destination],"Medical placement uses only server-returned destination")
	var acks: Array=app.calls.filter(func(call):return call.payload.get("transport_ack","")=="medical-1")
	check(acks.size()==1 and acks[0].path=="/session/update","Arrival acknowledgement pumps while world_ready is false")
	check(app.world_ready and not app.loading_stage and not app.live_transport_busy and app.loading_screen.finished and not app.player.feedback.life_locked,"Normal no-combat-rig loading ends only after confirmed native arrival and awake state")
	check(app.calls.any(func(call):return call.path.begins_with("/combat/session?")),"ACK before scheduled clone recovery keeps read-only native polling alive under loading cover")
	check(session.acknowledge_transport("medical-1") and not session.acknowledge_transport("other"),"Confirmed arrival retries are idempotent only for the acknowledged transport")
	check(not session.arrival_pending and session.pending_transport.is_empty() and session.pending_ack.is_empty(),"Confirmed transport clears acknowledgement state")
	app.player.set_physics_process(false);session.set_process(false)
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"native_replies":"mocked","placement":"mocked geometry","xr":"off"}));quit(0 if failures.is_empty() else 1)
