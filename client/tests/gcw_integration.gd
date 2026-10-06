extends SceneTree
const Fixture=preload("res://tests/ranger_inventory_integration.gd")
const Pets=preload("res://tests/pet_commands_smoke.gd")
class PanelState extends Node3D:
	var is_open:=true
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func reply(state:Dictionary,operation:String="")->Dictionary:return {"ok":true,"source_kind":"core3_services","character_id":"123","state":state.duplicate(true),"mutation":{"operation":operation,"success":true}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Fixture.Host.new();root.add_child(host);host.world_ready=true;host.loading_stage=false;host.xr_requested=true;host.xr_focused=true;host.datapad_character_id="123";host.datapad_account="fixture"
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig);host.xr_origin=rig;host.player=rig.get_node("PlayerBody");host.player.active=true;host.player.set_physics_process(false)
	var helper:=Pets.new();var right:=helper.tracker("right");helper.free()
	var head_tracker:=XRPositionalTracker.new();head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.name="head";head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var head:Camera3D=rig.get_node("XRCamera3D");head.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0));rig.get_node("RightHand").global_position=Vector3(.23,1.74,-.05)
	var sync:=Pets.Sync.new();host.add_child(sync);host.multiplayer_sync=sync;sync.entities=Pets.World.new();sync.add_child(sync.entities)
	var actor:=preload("res://combat/live_actor.gd").new();host.add_child(actor)
	check(actor.configure({"id":"42","kind":"creature","template":"object/mobile/dressed_rebel_recruiter_human_female_02.iff","dead":false,"name":"Rebel recruiter","health":100,"max_health":100,"scale":1.0},"fixture",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json")),"Original recruiter body and head skeleton load")
	actor.position=Vector3(0,0,-2);actor.set_process(false);sync.entities.actors["42"]=actor
	var services:=preload("res://scripts/services_controller.gd").new();host.add_child(services);host.services=services;services.app=host;services.epoch=host.datapad_epoch;services.set_process(false)
	services.ui=preload("res://scripts/xr_services.gd").new();services.add_child(services.ui);services.ui.configure(rig,host.player,"left");services.ui.set_process(false);services.ui.action_requested.connect(services.request)
	services.gcw=preload("res://gcw/controller.gd").new();services.add_child(services.gcw);services.gcw.setup(services);services.gcw.set_physics_process(false);services.set_allowed(true)
	var row:Dictionary={"id":"42","kind":"recruiter","faction":"rebel","can_salute":true,"position":[0,0,2]}
	var state:Dictionary={"character_id":"123","wallet":{"cash":1000,"bank":2000},"gcw":{"faction":"rebel","status":1,"status_name":"combatant","changing":false,"recruiters":[row],"scan":{}},"terminals":[row]}
	services.accept_response(reply(state));check(services.gcw.target(head.global_transform).get("id","")=="42","Head gaze selects actual source recruiter within3m")
	services.state.gcw.recruiters[0].faction="imperial";check(services.gcw.target(head.global_transform).is_empty(),"Enemy recruiter cannot trigger own duty salute");services.state.gcw.recruiters[0].faction="rebel"
	actor.position.z=-4;check(services.gcw.target(head.global_transform).is_empty(),"Out-of-range recruiter cannot be saluted");actor.position.z=-2
	var wall:=StaticBody3D.new();wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,3,.12);shape.shape=box;wall.add_child(shape);host.add_child(wall);wall.position=Vector3(0,1.5,-1);await physics_frame;await physics_frame
	check(services.gcw.target(head.global_transform).is_empty(),"World collision blocks saluting through wall");wall.free();await physics_frame
	var shown:=row.duplicate(true);shown.position=actor.global_position;host.reply=reply(state);services.ui.open_terminal(shown);await process_frame;await process_frame;host.calls.clear()
	check(services.gcw.permitted("right"),"Own recruiter menu permits steady empty-hand salute as advertised")
	services.ui.terminal.id="other";check(services.gcw.target(head.global_transform).is_empty(),"Open recruiter menu cannot redirect salute to a different recruiter");services.ui.terminal.id="42"
	services.ui.pointer_pressed=true;check(not services.gcw.permitted("right"),"Pressed recruiter UI blocks salute during click or drag");services.ui.pointer_pressed=false
	var pending:=state.duplicate(true);pending.gcw.changing=true;pending.gcw.pending_status=0;pending.gcw.cooldown_remaining_ms=300000;host.reply=reply(pending,"recruiter_status_toggle")
	for i in range(95):services.gcw._physics_process(1.0/90)
	await process_frame;await process_frame
	check(host.calls.size()==1 and host.calls[0].path=="/services/recruiter_status_toggle" and host.calls[0].body.terminal_id=="42" and host.calls[0].body.expected_status==1,"Production tracked temple salute submits one exact native status request")
	check(int(services.state.gcw.status)==1 and services.gcw.message.contains("queued") and services.gcw.message.contains("300s"),"Native operation receipt shows queued five-minute transition without changing actual duty")
	check(not services.gcw.permitted("right"),"Queued native transition prevents another salute")
	services.state_age=301;check(services.gcw.pending_text().contains("Awaiting native"),"Expired display timer never invents completed duty")
	services.ui.close_interface();services.accept_response(reply(state));services.gcw.reset();var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);host.inventory=bag;bag.configure(rig,host.player);bag.set_process(false);bag.held_item={"id":"held"}
	check(not services.gcw.permitted("right"),"Held dominant item blocks salute");bag.held_item={}
	var menu:=PanelContainer.new();host.add_child(menu);host.menu=menu;check(not services.gcw.permitted("right"),"Open menu blocks salute");menu.hide()
	var datapad:=PanelState.new();host.add_child(datapad);host.datapad=datapad;check(not services.gcw.permitted("right"),"Datapad wrist interface prevents accidental salute before orchestration catches up");datapad.is_open=false
	services.ui.allowed=false;check(not services.gcw.permitted("right"),"Mutually exclusive image design or vendor UI disables salute with service surface");services.ui.allowed=true
	head.global_position=Vector3(1.4,1.7,.7);var scan:=state.duplicate(true);scan.gcw.scan={"id":"scan77","active":true,"answer_pending":true,"fine":500}
	var before:=host.calls.size();services.accept_response(reply(scan));var pose:Transform3D=services.ui.surface.global_transform
	check(host.calls.size()==before and services.ui.terminal.kind=="contraband","Native inspection opens local prompt without requesting fictitious terminal")
	check(pose.origin.distance_to(head.global_position+Vector3(0,-.18,-1))<.001 and services.ui.terminal_origin.distance_to(Vector3(1.4,host.player.global_position.y,.7))<.001,"Inspection prompt opens one meter before roomscale-offset headset with consistent close origin")
	head.global_position+=Vector3(.3,0,.1);services.accept_response(reply(scan));check(services.ui.surface.global_transform.is_equal_approx(pose),"Inspection popup remains statically positioned across native updates and head movement")
	services.ui.close_interface();services.accept_response(reply(scan));check(services.ui.terminal.is_empty(),"Dismissed native scan does not reopen on every status poll")
	services.gcw.scan_shown="";services.accept_response(reply(scan));host.reply=reply(scan,"contraband_answer");services.ui.panel.click_at(services.ui.panel.REFRESH_RECT.get_center());await process_frame;await process_frame
	check(host.calls.back().path=="/services/contraband_answer" and host.calls.back().body.scan_id=="scan77" and host.calls.back().body.accept,"Explicit pay routes exact native scan identity through actual services coordinator")
	check(services.state.wallet.cash==1000 and services.gcw.message.contains("awaiting Core3"),"Fine receipt waits for native patrol outcome and does not locally deduct credits")
	scan.gcw.scan.answer_pending=false;services.accept_response(reply(scan));check(services.ui.terminal.is_empty(),"Native answered scan closes prompt")
	services.gcw.reset();check(services.gcw.scan_shown.is_empty() and services.gcw.message.is_empty(),"Session reset clears scan identity and gesture feedback")
	XRServer.remove_tracker(right);XRServer.remove_tracker(head_tracker);host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"mocked OpenXR controller","native_api":"mocked responses","original_recruiter":true,"production_services":true,"renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-integration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
