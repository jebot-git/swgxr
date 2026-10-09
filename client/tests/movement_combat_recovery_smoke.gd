extends SceneTree
const Pressure=preload("res://tests/live_poll_pressure_smoke.gd")
const Fixture=preload("res://tests/gameplay_combat_smoke.gd")
class Host extends Pressure.Host:
	func api(method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		var response:=await super.api(method,path,payload)
		# Production main.api performs this after decoding an HTTP400 body.
		if consume_movement_rejection(response):response._movement_correction_consumed=true
		return response
var checks:=0
var errors:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func envelope(sequence:int=1)->Dictionary:
	return {"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"123","session_id":"owned","sequence":sequence,"session_live":true,"snapshot":{"ready":true,"full":true,"actors":[],"player":{"ham":[1000,900,800],"max_ham":[1000,900,800],"dead":false,"incapacitated":false,"posture":0,"wounds":[0,0,0],"shock_wounds":0,"locomotion":{"movement_revision":sequence}},"weapon":{"item_id":"987","certified":true,"fire_interval_seconds":.1,"max_range_m":50.0,"projectile_speed":100.0}}}
func rejection(sequence:int)->Dictionary:
	var nested:=envelope(sequence);nested.ok=false;nested.mutation={"movement_accepted":false,"error_code":"native_movement_revision"}
	return {"ok":false,"http_status":400,"backend":"core3","error_code":"native_movement_revision","live_response":nested}
func host()->Host:
	var app:=Host.new();root.add_child(app);app.datapad_account="fixture";app.datapad_character_id="123";app.world_ready=true
	app.menu=PanelContainer.new();app.add_child(app.menu);app.menu.hide()
	app.stage=Node3D.new();app.add_child(app.stage);app.player=CharacterBody3D.new();app.add_child(app.player)
	var camera:=Camera3D.new();app.add_child(camera)
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json")).weapons.pistol_fwg5.duplicate(true);profile.item_id="987";profile.source_kind="core3_weapon_instance";profile.certified=true
	app.combat_rig=load("res://combat/ranged_rig.gd").new();app.add_child(app.combat_rig);app.combat_rig.configure(camera,app.player,[profile]);app.combat_rig.set_process(false);app.combat_rig.set_physics_process(false)
	return app
func run()->void:
	create_timer(15).timeout.connect(func():quit(2))
	var app:=host()
	var live:=preload("res://combat/live_world.gd").new();app.add_child(live);live.configure(app,app.combat_rig,app.stage,app.player);live.set_process(false);app.live_combat=live;app.live_combat_reserved=true
	app.reply=envelope();check(await live.start(Vector3.ZERO,0),"Legacy production session starts")
	live.snapshot_applied.connect(func(player):
		if player.has("movement_rejected"):live.discard_movement_commands())
	var shot:Dictionary={"item_id":"987","weapon_id":"pistol_fwg5","sequence":1,"speed":100.0}
	var launched:Dictionary=live.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	check(not launched.is_empty() and live.queue[0].payload.movement_revision==1,"Queued gesture captures revision at input time")
	live.player_state.locomotion.movement_revision=2
	var generation:int=live.generation;app.reply=rejection(2)
	await live.pump()
	check(app.calls.back().payload.movement_revision==1,"Queued fire retains original revision after authority advances")
	check(live.live and live.generation==generation and live.session_id=="owned" and live.sequence==2,"Owned rejection retains legacy persistent session")
	check(live.queue.is_empty() and live.shots.is_empty() and not live.native_ready and not live.busy,"Rejected gesture and pending projectile proof discarded; input disarmed")
	check(live.rejected_shots==1 and live.poll_clock>=live.POLL_INTERVAL,"Failed gesture counts once and schedules fresh heartbeat")
	check(app.calls.all(func(call):return not call.path.ends_with("/stop")),"Correction never releases native session")
	app.reply=envelope(3);await live.pump()
	check(live.is_ready() and app.calls.back().payload.movement_revision==2,"Fresh pose heartbeat rearms with latest native revision")
	var completed:Array=[];live.life_action_finished.connect(func(action,success,message):completed.append([action,success,message]))
	live.life_action_pending="recover";live.queue.append({"kind":"life","payload":{"action":"recover"}});app.reply=rejection(4);await live.pump()
	check(live.live and live.life_action_pending.is_empty() and completed.size()==1 and not completed[0][1],"Rejected life action settles failure without leaving life input pending")
	live.life_action_pending="recover";live.queue.append({"kind":"life","payload":{"action":"recover"}});app.reply=rejection(5)
	await app.api(HTTPClient.METHOD_POST,"/services/status",{})
	check(live.queue.is_empty() and live.life_action_pending.is_empty() and completed.size()==2,"Service correction also settles a queued, unsent life action")

	app.queue_free();await process_frame
	app=host()
	var session:=preload("res://scripts/gameplay_session.gd").new();app.gameplay_session=session;app.add_child(session);session.setup(app);session.set_process(false)
	var initial:=envelope();initial.source_kind="core3_gameplay_session";check(session.accept(initial,true),"Ordinary gameplay session accepts owned fixture")
	var sync:=Fixture.Sync.new();app.add_child(sync);sync.entities=Fixture.Entities.new();sync.add_child(sync.entities)
	var bridge:=preload("res://multiplayer/gameplay_combat.gd").new();app.gameplay_combat=bridge;app.add_child(bridge);bridge.attach(app,app.combat_rig,session,sync);bridge.set_process(false)
	session.snapshot_applied.connect(func(player):
		if player.has("movement_rejected"):bridge.discard_movement_commands())
	launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO);app.reply=rejection(2);await bridge.pump()
	check(not launched.is_empty() and session.live and session.sequence==2 and bridge.live,"Normal combat consumes nested correction without losing RPG ownership")
	check(bridge.shots.is_empty() and bridge.queue.is_empty() and bridge.rejected_shots==1 and not bridge.is_ready(),"Normal rejected shot has no accepted projectile or immediate rearm")
	check(session.last_position==Vector3.INF and session.next_update==0,"Normal combat requests a fresh heartbeat even when standing still")
	app.reply=envelope(3);app.reply.source_kind="core3_gameplay_session";await session.update_pose();bridge.refresh_authority()
	check(bridge.is_ready() and session.live,"A later heartbeat restores normal combat readiness")
	app.queue_free();await process_frame
	var result:Dictionary={"checks":checks,"errors":errors,"passed":errors.is_empty(),"http_mocked":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/movement-combat-recovery.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if errors.is_empty() else 1)
