extends SceneTree
const Fixtures=preload("res://tests/services_controller_smoke.gd")
const Progress=preload("res://tests/trainer_services_smoke.gd")
class Host extends Fixtures.Host:
	var gameplay_session: Node
	var vehicles: Node
	var medic: Node
var failures: Array=[]
var checks:=0
func check(value: bool,label: String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func native(revision: int, transport: Dictionary={}) -> Dictionary:
	return {"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"1000","session_id":"normal","session_live":true,"sequence":revision,"snapshot":{"player":{"ham":[900,800,700],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":0,"dead":false,"incapacitated":false,"shock_wounds":0},"transport":transport,"actors":[{"id":"must-not-project"}]}}
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.player=CharacterBody3D.new();app.add_child(app.player)
	app.stage=Fixtures.Stage.new();app.add_child(app.stage)
	app.live_combat=Fixtures.Live.new();app.add_child(app.live_combat)
	app.datapad=Progress.Datapad.new();app.add_child(app.datapad)
	var session:=preload("res://scripts/gameplay_session.gd").new();app.add_child(session);session.setup(app);session.set_process(false);app.gameplay_session=session
	var initial:=native(1);initial.source_kind="core3_gameplay_session"
	check(session.accept(initial,true),"Actual normal session accepts owned initial player state")
	var coordinator:=preload("res://scripts/services_controller.gd").new();app.add_child(coordinator);coordinator.app=app;coordinator.epoch=app.datapad_epoch;coordinator.set_process(false);coordinator.set_allowed(true)
	var notifications: Array=[];session.transport_required.connect(func(value):notifications.append(value.duplicate(true)))
	var transport: Dictionary={"id":"shuttle-native","kind":"shuttle","destination":{"zone":"tatooine","position":[3700,5,-4650],"building_id":"0","cell_index":0}}
	var response:=app.response();response.transport=transport;response.live_response=native(2,transport)
	response.state.skills=["combat_marksman_novice"];response.state.skills_complete=true
	response.state.experience={"pistol":75};response.state.experience_complete=true
	app.next_response=response
	await coordinator.request("travel_board",{"terminal_id":"native-shuttle","ticket_id":"native-ticket"})
	check(app.calls.back().payload.session_id=="normal","Service request retains existing lightweight persistent identity")
	check(notifications.size()==1 and notifications[0].id==transport.id and app.transports.is_empty(),"Confirmed normal travel routes only through session transport+ack, never old direct placement")
	check(session.sequence==2 and session.player_state.ham[0]==900 and session.get_child_count()==0,"Underlying live envelope updates player only without combat actors")
	check(app.datapad.ui.experience_calls.back().values.pistol==75 and app.datapad.ui.skill_calls.back().values==["combat_marksman_novice"],"Normal current service revision publishes native XP and skills")
	var heartbeat:=native(3,transport);heartbeat.source_kind="core3_gameplay_session";session.accept(heartbeat)
	check(notifications.size()==1,"Following normal heartbeat does not place the same transport twice")
	var newer:=response.duplicate(true);newer.live_response=native(5);newer.state.experience.pistol=10;newer.state.skills.append("combat_marksman_pistol_01")
	check(coordinator.accept_response(newer) and session.sequence==5,"Newer service snapshot advances normal revision")
	var skill_count:int=app.datapad.ui.skill_calls.size()
	coordinator.accept_response(response)
	check(app.datapad.ui.experience_calls.back().values.pistol==10 and app.datapad.ui.skill_calls.size()==skill_count and session.sequence==5,"Stale normal service reply cannot roll back XP, learned skills or player state")
	var unversioned:=response.duplicate(true);unversioned.erase("live_response")
	coordinator.accept_response(unversioned)
	check(app.datapad.ui.experience_calls.back().values.pistol==10,"Unversioned normal service receipt cannot replace revisioned player progress")
	var foreign:=response.duplicate(true);foreign.live_response.session_id="other";foreign.live_response.sequence=100
	coordinator.accept_response(foreign)
	check(app.datapad.ui.experience_calls.back().values.pistol==10 and session.session_id=="normal","Foreign session progress is ignored despite higher revision")
	var malformed:=newer.duplicate(true);malformed.live_response.sequence=6;malformed.live_response.snapshot.player.posture=13
	check(not coordinator.accept_response(malformed) and session.sequence==5 and app.datapad.ui.skill_calls.size()==skill_count,"Invalid normal player envelope cannot publish accompanying progress")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"native":"mocked owned envelopes","xr":"off"}));quit(0 if failures.is_empty() else 1)
