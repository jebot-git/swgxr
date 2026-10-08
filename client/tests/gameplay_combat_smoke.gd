extends SceneTree
class Weapon extends RefCounted:
	var profile:Dictionary={"item_id":"99","kind":"ranged","rpm":60,"abilities":["local_prediction"]}
	var core:Dictionary={"maxRange":10.0}
	var ability_state:Variant=RefCounted.new()
	var wear_per_shot:=1.0
class Rounds extends Node:
	signal authoritative_contact(shot:Dictionary,target:Dictionary,position:Vector3,normal:Vector3,distance:float)
class Rig extends Node3D:
	var authority_gate:Callable
	var shot_authority:Callable
	var weapons:Array=[]
	var unarmed:Dictionary={}
	var haptics:Array=[]
	func action_haptic(kind:String,hand:="")->void:haptics.append([kind,hand])
	var rounds_sim:Rounds
	var abilities=preload("res://combat/ability_state.gd").new()
	func active_profile()->Dictionary:return weapons[0].state.profile if not weapons.is_empty() else {}
	func close_ability_menu()->void:pass
class Actor extends Node3D:
	var record:Dictionary={"health":100.0}
	func is_targetable()->bool:return true
class Entities extends Node:
	var actors:Dictionary={}
class Sync extends Node:
	var entities:Entities
class Host extends Node:
	var datapad_account:="fixture"
	var datapad_character_id:="101"
	var world_ready:=true
	var session_leaving:=false
	var stage:Node3D
	var player:CharacterBody3D
	var vehicles:Node
	var asset_status:Label
	var gameplay_session:Node
	var gameplay_combat:Node
	var calls:Array=[]
	var reject:=false
	var foreign:=false
	var occupied:=false
	var response_weapon:Dictionary={}
	var melee_hit:=true
	var taunt_applied:=true
	var taunt_context:Dictionary={}
	func source_position_at(point:Vector3)->Vector3:return Vector3(100+point.x,point.y,200-point.z)
	func native_requests_in_flight()->int:return 1 if occupied else 0
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		var result:=envelope()
		result.source_kind="core3_gameplay_session" if path=="/session/update" else "core3_live_combat";result.sequence=gameplay_session.sequence+1
		result.mutation={"success":not reject,"shot_id":payload.get("shot_id",""),"error_code":"native_rejected" if reject else ""}
		if not response_weapon.is_empty():result.snapshot.weapon=response_weapon.duplicate(true)
		if path.ends_with("/melee"):
			result.mutation.hit=melee_hit;result.mutation.damage=10 if melee_hit else 0
		if path.ends_with("/taunt"):result.mutation.taunted=taunt_applied
		if not taunt_context.is_empty():result.snapshot.player.taunt=taunt_context.duplicate(true)
		if foreign:result.session_id="foreign"
		result.snapshot.player.ham=[880,900,900]
		return result
	func envelope()->Dictionary:
		return {"ok":true,"backend":"core3","source_kind":"core3_gameplay_session","character_id":"101","session_id":"owned","session_live":true,"sequence":1,"snapshot":{"player":{"ham":[900,900,900],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":0,"dead":false,"incapacitated":false,"shock_wounds":0},"weapon":{"item_id":"99","certified":true,"fire_interval_seconds":.1,"max_range_m":64,"projectile_speed":100}}}
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(20).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.stage=Node3D.new();app.add_child(app.stage)
	app.player=CharacterBody3D.new();app.add_child(app.player)
	app.asset_status=Label.new();app.add_child(app.asset_status)
	var session:=preload("res://scripts/gameplay_session.gd").new();app.gameplay_session=session;app.add_child(session);session.setup(app);session.set_process(false)
	check(session.accept(app.envelope(),true),"RPG entry accepts native weapon profile without requiring it")
	var rig:=Rig.new();app.add_child(rig);rig.weapons=[{"state":Weapon.new()}];rig.rounds_sim=Rounds.new();rig.add_child(rig.rounds_sim)
	var sync:=Sync.new();app.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	var actor:=Actor.new();sync.entities.add_child(actor);sync.entities.actors["201"]=actor
	var bridge:=preload("res://multiplayer/gameplay_combat.gd").new();app.gameplay_combat=bridge;app.add_child(bridge);bridge.attach(app,rig,session,sync);bridge.set_process(false)
	check(bridge.is_ready() and rig.authority_gate.call(),"Normal gameplay session enables authenticated ranged authority without separate combat login")
	check(rig.weapons[0].state.ability_state==null and rig.weapons[0].state.wear_per_shot==0 and rig.weapons[0].state.profile.abilities.is_empty(),"Native bridge disables local HAM/wear/ability prediction")
	var shot:Dictionary={"item_id":"99","weapon_id":"pistol","sequence":1,"speed":100.0}
	var launched:Dictionary=bridge.register_shot(shot,Transform3D(Basis.IDENTITY,Vector3(1,2,3)),Vector3.ZERO)
	check(not launched.is_empty() and launched.live_session=="owned" and bridge.queue.size()==1,"Shot gets immutable owned-session identity and bounded queued fire")
	check(bridge.queue[0].payload.origin==[101.0,2.0,197.0] and bridge.queue[0].payload.direction==[0.0,0.0,1.0],"Fire sends original source-world origin and reflected forward direction")
	check(bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Native rate interval gates duplicate local trigger samples")
	bridge.contact(launched,{"id":"201","session_id":"owned"},Vector3(2,0,0),Vector3.UP,2)
	check(bridge.queue.size()==2 and bridge.queue[1].kind=="impact","Actual owned native actor contact queues original impact proof")
	app.occupied=true;await bridge.pump()
	check(app.calls.is_empty(),"Native economy request is not interrupted by combat transport")
	app.occupied=false;await bridge.pump()
	check(app.calls.size()==1 and app.calls[0].path=="/combat/session/fire" and bridge.shots[launched.shot_id].accepted,"Fire is confirmed on same persistent session before sending impact")
	check(session.player_state.ham[0]==880 and session.sequence==2,"Native receipt updates ordinary RPG HAM through shared owned revision validator")
	await bridge.pump()
	check(app.calls[1].path=="/combat/session/impact" and bridge.confirmed_contacts==1 and bridge.shots.is_empty(),"Impact resolves native shot receipt and retires local pending proof")
	check(actor.record.health==100,"Bridge cannot fabricate actor damage before authoritative world update")
	bridge.next_launch_usec=0;launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO);app.reject=true;await bridge.pump()
	check(bridge.rejected_shots==1 and bridge.shots.is_empty(),"Rejected native shot never produces accepted damage proof")
	app.reject=false;bridge.next_launch_usec=0;launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO);app.foreign=true;await bridge.pump()
	check(not bridge.is_ready() and session.live and session.session_id=="owned","Uncertain or foreign receipt disarms combat while preserving persistent RPG ownership")
	app.foreign=false
	var restored:=app.envelope();restored.sequence=session.sequence+1;session.accept(restored);bridge.refresh_authority()
	check(bridge.is_ready(),"A later owned authoritative heartbeat can safely rearm after receipt failure")
	var special:=app.envelope();special.sequence=session.sequence+1
	special.snapshot.weapon.abilities=[{"id":"last_ditch","label":"Last Ditch","activation":"native_ranged","base_sac":{"health":0,"action":0,"mind":0},"cooldown_seconds":15.0}]
	session.accept(special);bridge.refresh_authority()
	rig.abilities.apply_authoritative(special.snapshot.player)
	check(rig.abilities.select(rig.active_profile(),"last_ditch") and rig.abilities.toggle_prime(rig.active_profile()),"Native granted Last Ditch uses existing selection and arming")
	rig.abilities.apply_authoritative(special.snapshot.player)
	check(rig.abilities.primed,"Routine native HAM heartbeat preserves prepared ranged ability")
	var pools:Array=rig.abilities.ham.duplicate()
	bridge.next_launch_usec=Time.get_ticks_usec()+1000000
	check(bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO).is_empty() and rig.abilities.primed,"Launch cadence rejection does not consume armed ability")
	bridge.next_launch_usec=0;launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	check(not launched.is_empty() and bridge.queue.back().payload.ability_id=="last_ditch" and not rig.abilities.primed,"One native fire carries and consumes armed ability identity")
	check(rig.abilities.ham==pools,"Native special shot never predicts or fabricates HAM expenditure")
	bridge.next_launch_usec=0;bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	check(not bridge.queue.back().payload.has("ability_id"),"Following ordinary shot cannot reuse consumed Last Ditch")
	var no_weapon:=app.envelope();no_weapon.sequence=session.sequence+1;no_weapon.snapshot.erase("weapon");session.accept(no_weapon);bridge.refresh_authority()
	check(session.live and not bridge.is_ready(),"Missing native weapon leaves session connected with combat disarmed")
	bridge.queue.clear();bridge.shots.clear();bridge.next_launch_usec=0
	rig.weapons[0].state.profile.kind="melee"
	app.response_weapon={"item_id":"99","kind":"melee","unarmed":false,"certified":true,"fire_interval_seconds":.4,"max_range_m":4,"projectile_speed":160}
	var melee_state:=app.envelope();melee_state.sequence=session.sequence+1;melee_state.snapshot.weapon=app.response_weapon.duplicate(true)
	session.accept(melee_state);bridge.refresh_authority()
	check(bridge.is_ready(),"Native melee weapon enables ordinary gameplay authority")
	var swing:Dictionary={"kind":"melee","weapon_id":"sword","item_id":"99","hand":"left","range":4}
	var contacts:int=bridge.confirmed_contacts
	check(not bridge.register_shot(swing,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Qualified melee swing queues a native action")
	check(bridge.queue.back().kind=="melee" and not bridge.queue.back().payload.has("target_id"),"Native cone owns target selection")
	check(bridge.register_shot(swing,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Rapid swing cannot bypass native cadence mirror")
	await bridge.pump()
	check(bridge.shots.is_empty() and bridge.confirmed_contacts==contacts+1 and rig.haptics.back()==["hit","left"],"One melee receipt retires swing and confirms hand-specific impact feedback")
	app.melee_hit=false;bridge.next_launch_usec=0
	var pulse_count:int=rig.haptics.size()
	bridge.register_shot(swing,Transform3D.IDENTITY,Vector3.ZERO);await bridge.pump()
	check(rig.haptics.size()==pulse_count and bridge.shots.is_empty(),"Whiff has no false hit haptic or pending projectile")
	rig.unarmed={"left":Weapon.new(),"right":Weapon.new()};app.response_weapon.unarmed=true;app.response_weapon.item_id="100"
	melee_state=app.envelope();melee_state.sequence=session.sequence+1;melee_state.snapshot.weapon=app.response_weapon.duplicate(true)
	session.accept(melee_state);bridge.refresh_authority();bridge.next_launch_usec=0
	var punch:Dictionary={"kind":"melee","weapon_id":"unarmed","item_id":"","hand":"left"}
	check(bridge.is_ready() and not bridge.register_shot(punch,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Unarmed uses the native default weapon identity")
	punch.hand="right"
	check(bridge.register_shot(punch,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Both fists share one attack cooldown")
	check(bridge.queue.back().payload.item_id=="100" and rig.unarmed.left.ability_state==null,"Unarmed cost prediction disabled and native item carried")
	bridge.queue.clear();bridge.shots.clear();bridge.next_launch_usec=0
	check(not bridge.register_taunt(Transform3D.IDENTITY,"left"),"Ungrant taunt is unavailable")
	app.taunt_context={"learned":true,"cooldown_remaining_seconds":0.0,"interval_seconds":2.0,"range_m":64}
	var taunt_state:=app.envelope();taunt_state.sequence=session.sequence+1;taunt_state.snapshot.weapon=app.response_weapon.duplicate(true);taunt_state.snapshot.player.taunt=app.taunt_context.duplicate(true)
	session.accept(taunt_state);bridge.refresh_authority()
	check(bridge.register_taunt(Transform3D.IDENTITY,"left"),"Learned chest gesture queues taunt through owned session")
	check(bridge.queue.back().kind=="taunt" and not bridge.queue.back().payload.has("target_id") and not bridge.queue.back().payload.has("item_id"),"Server owns first eligible reticle target")
	check(not bridge.register_taunt(Transform3D.IDENTITY,"right") and bridge.register_shot(punch,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Taunt shares combat timing with both fists")
	await bridge.pump()
	check(bridge.shots.is_empty() and rig.haptics.back()==["taunt","left"],"Confirmed native taunt pulses gesture hand and retires intent")
	pulse_count=rig.haptics.size();bridge.next_launch_usec=0;app.taunt_applied=false
	bridge.register_taunt(Transform3D.IDENTITY,"right");await bridge.pump()
	check(rig.haptics.size()==pulse_count,"Resisted taunt gives no success haptic")
	bridge.next_launch_usec=0;app.reject=true
	bridge.register_taunt(Transform3D.IDENTITY,"right");await bridge.pump();app.reject=false
	check(bridge.shots.is_empty() and rig.haptics.size()==pulse_count,"Rejected taunt cannot leave a pending attack or pulse")
	bridge.next_launch_usec=0;bridge.player_state.taunt.cooldown_remaining_seconds=2
	check(not bridge.register_taunt(Transform3D.IDENTITY,"left"),"Native taunt cooldown disables gesture submission")
	# Reproduce the production process ordering: the session heartbeat runs
	# before the combat bridge, while a gesture has waited behind native work.
	app.response_weapon={};app.taunt_context={};rig.weapons[0].state.profile.kind="ranged"
	var fresh:=app.envelope();fresh.sequence=session.sequence+1;session.accept(fresh);bridge.refresh_authority();bridge.next_launch_usec=0
	launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	check(not launched.is_empty(),"Fresh owned authority queues the pending gesture used by the stall regression")
	var before:int=app.calls.size()
	session.next_update=0;session.last_confirmed_ms=Time.get_ticks_msec()-4100
	bridge.refresh_authority()
	check(not bridge.is_ready(),"Four-second authority expiry still prevents firing")
	session._process(.01)
	check(session.busy and app.calls.size()==before+1 and app.calls.back().path=="/session/update","Expired queued combat yields to a production owned heartbeat")
	check(bridge.queue.is_empty() and bridge.shots.is_empty(),"Heartbeat discards stale gestures before its asynchronous reply can rearm combat")
	await process_frame;await process_frame
	bridge._process(.01)
	check(session.live and not session.busy and bridge.is_ready() and app.calls.size()==before+1,"Fresh owned heartbeat restores authority without replaying the expired attack")
	bridge.next_launch_usec=0;launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO);await bridge.pump()
	check(not launched.is_empty() and app.calls.back().path=="/combat/session/fire" and bridge.shots[launched.shot_id].accepted,"A new physical gesture can fire after authority recovery")
	bridge.queue.clear();bridge.shots.clear();bridge.next_launch_usec=0
	launched=bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	before=app.calls.size();bridge.shots[launched.shot_id].expires_usec=Time.get_ticks_usec()-1;await bridge.pump()
	check(app.calls.size()==before and bridge.queue.is_empty() and bridge.shots.is_empty(),"Expired unstarted fire is discarded even with fresh authority")
	bridge.next_launch_usec=0;bridge.register_shot(shot,Transform3D.IDENTITY,Vector3.ZERO)
	session.last_confirmed_ms=Time.get_ticks_msec()-4100;bridge._process(.01)
	check(not bridge.has_pending_commands() and not bridge.is_ready() and session.live,"Combat-first process ordering also clears stale commands without releasing the RPG owner")
	app.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"mocked_transport":true,"reused_native_shot_protocol":true,"live_xr":false}
	FileAccess.open("res://../runtime/evidence/gameplay-combat-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
