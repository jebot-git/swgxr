extends SceneTree
## Production admission and live pump; explicit mocked HTTP gate responses.
class Host extends "res://scripts/main.gd":
	var reply:Dictionary={}
	var calls:Array=[]
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func source_position_at(point:Vector3)->Vector3:return point
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
class Poller extends "res://entertainment/native_controller.gd":
	var requests:=0
	func bound()->bool:return true
	func allowed()->bool:return true
	func request(_action:String,_detail:Dictionary={})->Dictionary:requests+=1;return {}
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(20).timeout.connect(func():quit(2))
	var host:=Host.new();root.add_child(host);host.datapad_account="fixture";host.datapad_character_id="123";host.world_ready=true
	host.menu=PanelContainer.new();host.add_child(host.menu);host.menu.hide()
	host.stage=Node3D.new();host.add_child(host.stage);host.player=CharacterBody3D.new();host.add_child(host.player)
	var head:=Camera3D.new();host.add_child(head)
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json")).weapons.pistol_fwg5.duplicate(true);profile.item_id="987";profile.source_kind="core3_weapon_instance";profile.certified=true
	var rig:=preload("res://combat/ranged_rig.gd").new();host.add_child(rig);check(rig.configure(head,host.player,[profile]),"Original ranged rig configures")
	rig.set_process(false);rig.set_physics_process(false)
	var live:=preload("res://combat/live_world.gd").new();host.add_child(live);live.configure(host,rig,host.stage,host.player);live.set_process(false);host.live_combat=live;host.live_combat_reserved=true
	var envelope:Dictionary={"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"123","session_id":"native-session","sequence":1,"session_live":true,"snapshot":{"ready":true,"full":true,"actors":[],"player":{"ham":[1000,900,800],"max_ham":[1000,900,800],"dead":false,"incapacitated":false,"posture":0,"wounds":[0,0,0],"shock_wounds":0},"weapon":{"item_id":"987","certified":true,"fire_interval_seconds":3.0,"max_range_m":50.0,"projectile_speed":100.0}}}
	host.reply=envelope;check(await live.start(Vector3.ZERO,0),"Owned session starts through production pump authority")
	live.busy=true;check(not host.try_background_poll("entertainer"),"Live request blocks optional native polls")
	live.busy=false;check(host.try_background_poll("entertainer") and host.native_poll_budget.interval_ms==1000,"Reserved live mode grants through one-second budget")
	check(not host.try_background_poll("gathering"),"Another subsystem cannot bypass shared live interval")
	host.native_poll_budget.last_grant_ms=Time.get_ticks_msec()-1001
	check(not host.try_background_poll("entertainer") and host.try_background_poll("gathering"),"Oldest waiting subsystem retains fair admission in live mode")
	host.native_poll_budget.last_grant_ms=Time.get_ticks_msec()-1001;host.api_requests_in_flight=1
	check(not host.try_background_poll("entertainer"),"In-flight native service blocks optional live polls")
	host.api_requests_in_flight=0
	host.native_poll_budget.reset()
	var gate:Dictionary={"ok":false,"http_status":503,"backend":"core3","error_code":"backend_busy","mutation_started":false,"retry_after":1,"error":"Core3 request queue is full; retry shortly"}
	host.reply=gate;live.poll_clock=1;live.elapsed_since_snapshot=.5;var epoch:int=live.generation
	await live.pump()
	check(live.live and live.session_id=="native-session" and live.generation==epoch and live.elapsed_since_snapshot==.5,"Explicit unstarted gate rejection retains owner and does not invent a confirmation")
	var count:int=host.calls.size();await live.pump()
	check(host.calls.size()==count and not host.try_background_poll("entertainer"),"Backoff suppresses both live retry and optional poll storm")
	host.native_poll_budget.reset()
	host.player.position=Vector3(4,0,2);live.backend_retry_usec=0;host.reply=envelope.duplicate(true);host.reply.sequence=2
	await live.pump()
	check(host.calls.back().payload.position==[4.0,0.0,2.0] and live.sequence==2 and live.is_ready(),"Rejected pose is discarded; next poll sends fresh tracked position and recovers")
	var command:Dictionary={"shot_id":"shot","request_id":"unchanged","aim_position":[1,2,3]}
	live.shots.shot={"accepted":false};live.queue.append({"kind":"fire","shot_id":"shot","payload":command.duplicate(true)});host.reply=gate
	await live.pump();check(live.queue.size()==1 and live.queue[0].payload==command and live.queue[0].unstarted_retries==1,"Unstarted command retries exact immutable receipt and semantic payload")
	live.backend_retry_usec=0;host.reply=envelope.duplicate(true);host.reply.sequence=3;host.reply.mutation={"success":true,"shot_id":"shot"}
	await live.pump();check(live.shots.shot.accepted and live.queue.is_empty() and host.calls.back().payload==command,"One successful exact retry acknowledges original fire once")
	var performer:=Node.new();host.add_child(performer)
	var poller:=Poller.new();host.add_child(poller);poller.set_process(false);poller.set_physics_process(false);poller.host=host;poller.performer=performer;poller.owner_session="native-session";poller.state={"image_design":{"active":true,"session_id":"design"}}
	host.native_poll_budget.reset();host.native_poll_budget.last_grant_ms=Time.get_ticks_msec();poller._process(.1)
	check(poller.requests==0,"Active Image Designer status cannot bypass shared poll budget")
	host.native_poll_budget.last_grant_ms=Time.get_ticks_msec()-1001;poller._process(.1)
	check(poller.requests==1,"Active Image Designer status resumes when budget admits it")
	live.queue.append({"kind":"life","payload":{"action":"recover","request_id":"bounded"}});host.reply=gate
	for _i in 4:
		live.backend_retry_usec=0
		await live.pump()
	check(not live.live and live.last_error.contains("unstarted command"),"Explicitly unstarted command retries are bounded even without advancing stale timer")
	for _i in 3:await process_frame
	host.reply=envelope;check(await live.start(Vector3.ZERO,0),"Explicit reconnect establishes a fresh owned session after retry limit")
	host.reply=gate.duplicate(true);host.reply.erase("mutation_started");live.poll_clock=1
	await live.pump();check(not live.live and live.queue.is_empty(),"Ambiguous busy response fails closed instead of retrying a possibly started mutation")
	for _i in 3:await process_frame
	host.reply=envelope;check(await live.start(Vector3.ZERO,0),"Session can explicitly reconnect after ambiguous failure")
	host.reply=gate;live.poll_clock=1;await live.pump();live.elapsed_since_snapshot=3.9;live._process(.2)
	check(not live.live and live.last_error.contains("timed out"),"Explicit busy never extends four-second stale-session safety timeout")
	for _i in 3:await process_frame
	host.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"mocked_http":true,"headset_validated":false}
	FileAccess.open("res://../runtime/evidence/live-poll-pressure-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
