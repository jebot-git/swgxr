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
	var rounds_sim:Rounds
	var abilities:Dictionary={"primed":true}
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
	func source_position_at(point:Vector3)->Vector3:return Vector3(100+point.x,point.y,200-point.z)
	func native_requests_in_flight()->int:return 1 if occupied else 0
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		var result:=envelope()
		result.source_kind="core3_live_combat";result.sequence=gameplay_session.sequence+1
		result.mutation={"success":not reject,"shot_id":payload.get("shot_id",""),"error_code":"native_rejected" if reject else ""}
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
	var no_weapon:=app.envelope();no_weapon.sequence=session.sequence+1;no_weapon.snapshot.erase("weapon");session.accept(no_weapon);bridge.refresh_authority()
	check(session.live and not bridge.is_ready(),"Unequipped or unarmed normal player stays connected with ranged bridge disarmed")
	app.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"mocked_transport":true,"reused_native_shot_protocol":true,"live_xr":false}
	FileAccess.open("res://../runtime/evidence/gameplay-combat-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
