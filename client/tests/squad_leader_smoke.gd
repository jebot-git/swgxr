extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="squad"
	var datapad_character_id:="1"
	var session_leaving:=false
	var world_ready:=true
	var datapad_epoch:=1
	var combat_rig:Node3D
	var calls:Array=[]
	var reject:=false
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return {"mutation":{"success":not reject,"shot_id":payload.shot_id,"ability_id":payload.get("ability_id",""),"volley_consumed":payload.has("volley_mark_id"),"volley_mark_id":payload.get("volley_mark_id",""),"volley_target_id":payload.get("volley_target_id",""),"hit":true,"damage":100}}
class EmptyAssets extends RefCounted:
	func instance(_template:String,_size:float,_custom:Dictionary)->Node3D:return null
class ThrowBag extends Node3D:
	var assets:=EmptyAssets.new()
	var held_model:Node3D
	var finished:Array=[]
	func finish_item_action(success:bool)->void:finished.append(success)
	func set_busy(_busy:bool,_message:String)->void:pass
class ThrowScout extends "res://scout/controller.gd":
	var pose:Transform3D
	var accepted:=true
	var calls:Array=[]
	func aim_pose()->Transform3D:return pose
	func request(action:String,detail:Dictionary={})->Dictionary:
		calls.append({"action":action,"detail":detail.duplicate(true)})
		await get_tree().process_frame
		return {"ok":accepted,"mutation":{"volley_consumed":accepted and detail.has("volley_mark_id")}}
class Session extends Node:
	var live:=true
	var busy:=false
	var character_id:="1"
	var session_id:="squad-session"
	var sequence:=1
	var player_state:Dictionary={}
	var weapon_state:Dictionary={}
	var pending_transport:Dictionary={}
	var life_action_pending:=""
	var last_confirmed_ms:=Time.get_ticks_msec()
	var last_error:=""
	func authority_expired()->bool:return false
	func accept_native_response(_response:Dictionary)->bool:sequence+=1;last_confirmed_ms=Time.get_ticks_msec();return true
class Entities extends Node:
	var actors:Dictionary={}
class Sync extends Node:
	var entities:Entities
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":1000,"boss":false,"level":50,"melee_control_available":true,"knockdown_available":true}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"squad-session"}
	func visual_bounds()->AABB:return AABB(Vector3(-.2,0,-.2),Vector3(.4,1.8,.4))
var checks:=0
var errors:Array=[]
var rig:Node3D
var live:Node3D
var app:Host
var session:Session
var actor:Actor
var profiles:Array=[]
var head:Camera3D
var squad:Node3D
var serial:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func context()->Dictionary:
	var entries:Array=[]
	for id:String in ["steady_aim","rally","form_up","boost_morale","retreat"]:entries.append({"id":id,"label":id.capitalize(),"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":45,"action_cost":60,"mind_cost":30,"range_m":48.})
	serial+=1
	return {"group_id":"500","abilities":entries,"targets":[{"id":"2","eligible":true,"dead":false,"incapacitated":false,"height_m":1.8,"position":[2,0,6]}],"volley_fire":{"mark":{"id":"volley_900_"+str(serial),"target_id":"201","position":[0,0,8],"height":1.8,"remaining_seconds":12.}}}
func refresh(value:Dictionary)->void:
	session.player_state.squad_leader=value;session.sequence+=1;session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority()
func equip(index:int)->void:
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;rig.abilities.cooldowns.clear();rig.rounds_sim.clear();app.reject=false;rig.squad_release_pending=false;squad.ultimate_input.reset()
	rig.draw(index);rig.main_grip_down=true;rig.support_grip_down=true;rig.support_latched=true;rig.two_hands=true
	var state=rig.weapons[index].state
	state.rounds=int(state.profile.get("capacity",0));state.reload_until=-1;state.next_shot=0;state.block()
	var profile:Dictionary=profiles[index].duplicate(true)
	session.weapon_state=profile.duplicate(true);session.weapon_state.merge({"kind":"melee" if state.is_melee() else "ranged","certified":true,"fire_interval_seconds":1.,"max_range_m":float(profile.core3.maxRange),"projectile_speed":45.,"charges":40,"conditions_met":true},true)
	session.player_state={"ham":[3000,1000,1000],"squad_leader":context()}
	session.last_confirmed_ms=Time.get_ticks_msec();session.sequence+=1;live.refresh_authority()
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]})
func pose_at(point:Vector3)->Transform3D:return Transform3D(Basis.looking_at((point-head.global_position).normalized()),head.global_position)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	head=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.7,0)
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	for key:String in ["pistol_cdef","knife_survival","rifle_flame_thrower","heavy_rocket_launcher"]:
		var profile:Dictionary=catalog.weapons[key].duplicate(true);profile.item_id=str(99+profiles.size());profile.certified=true
		profile.abilities=[{"id":"volley_fire","activation":"squad_leader_ultimate","ultimate":true,"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":120,"action_cost":80,"mind_cost":40,"max_range_m":64.}]
		profile.ability_loadout={"family":profile.get("class",""),"slots":["","","",""],"ultimate":"volley_fire"};profiles.append(profile)
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,profiles),"Original pistol, melee, beam and rocket configure")
	rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);squad=rig.squad_leader
	app=Host.new();world.add_child(app);app.player=body;app.stage=world;app.combat_rig=rig
	session=Session.new();world.add_child(session)
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	await physics_frame;await physics_frame
	var manager:Node3D=rig.rounds_sim.effects.manager;manager.set_process(false)
	for index in range(4):
		equip(index)
		check(squad.toggle(pose_at(Vector3(2,.9,-6))),"Any weapon opens group VATS "+str(index))
		check(squad.points.size()==5 and squad.abilities().size()==5,"Every learned support action is available without four-slot competition "+str(index))
		check(squad.widgets.steady_aim.get_node("Label").text.contains("Nearby group"),"Buff recipient scope is visible "+str(index))
		check(live.register_squadleader("steady_aim","2",pose_at(Vector3(2,.9,-6)),"right"),"Any weapon routes native support "+str(index))
		check(live.queue.back().kind=="squadleader" and not live.queue.back().payload.has("damage"),"Support queues intent without local mutation "+str(index))
		await live.pump()
		check(app.calls.back().path=="/combat/session/squadleader" and live.shots.is_empty(),"Support receipt is retired "+str(index));squad.close()
	# Real marker press/release owns input, without changing local weapon costs.
	equip(1);squad.toggle(pose_at(Vector3(2,.9,-6)));var support_point:Vector3=squad.points[0].position
	head.global_transform=pose_at(support_point);var ham_before:Array=rig.abilities.ham.duplicate()
	rig.sample_squad_controls(.02,0,0,true,true);rig.sample_squad_controls(.02,1,0,true,true);rig.sample_squad_controls(.02,0,0,true,true)
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="steady_aim" and rig.squad_input_captured,"Friendly marker press and release dispatches the selected buff and captures combat")
	check(rig.abilities.ham==ham_before,"Support intent leaves all local HAM unchanged")
	squad.close();head.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
	# Membership and weapon changes invalidate a pressed friendly selection.
	equip(0);squad.toggle(pose_at(Vector3(2,.9,-6)));squad.pressing="rally";var value:=context();value.group_id="600";refresh(value)
	check(not squad.active() and squad.pressing.is_empty(),"Party change closes pending support VATS")
	value=context();value.targets[0].eligible=false;refresh(value)
	check(not squad.toggle(pose_at(Vector3(2,.9,-6))) and not live.register_squadleader("rally","2",pose_at(Vector3(2,.9,-6)),"right"),"Native-ineligible party members cannot be targeted")
	value=context();refresh(value);squad.toggle(pose_at(Vector3(2,.9,-6)));rig.draw(1);squad.refresh()
	check(not squad.active(),"Changing the held weapon closes support selection")
	equip(0);squad.observed_usec-=5000000;squad.refresh()
	check(squad.mark.is_empty() and not squad.toggle(pose_at(Vector3(2,.9,-6))),"Expired authority hides markers and refuses support")
	# Each member renders their own authoritative charge, including non-SL users.
	equip(0);value=context();value.abilities=[];refresh(value);squad.refresh()
	check(not squad.mark.is_empty() and squad.volley_widget.visible,"Non-Squad-Leader party member sees their native Volley mark")
	check(squad.volley_widget.get_node("Icon").material_override.no_depth_test and squad.volley_widget.get_node("Label").no_depth_test,"Only native Volley ring and label remain visible through target meshes and cover")
	check(not squad.widgets.steady_aim.get_node("Icon").material_override.no_depth_test and not squad.widgets.steady_aim.get_node("Label").no_depth_test,"Friendly buff markers retain ordinary depth testing")
	value.volley_fire.mark.height=20.;refresh(value);squad.refresh()
	check(squad.volley_widget.visible and not squad.mark.is_empty(),"Large enemy bounds cannot hide the assigned Volley reticle inside the body")
	value.volley_fire.mark.remaining_seconds=0.;refresh(value);squad.refresh()
	check(not squad.volley_widget.visible and squad.mark.is_empty(),"Expired native marks hide even the depth-independent overlay")
	value.volley_fire.mark.remaining_seconds=12.;value.volley_fire.mark.height=1.8;refresh(value);session.live=false;live.refresh_authority();squad.refresh()
	check(not squad.volley_widget.visible and squad.mark.is_empty(),"Loss of native authority hides the depth-independent overlay")
	session.live=true;refresh(value);squad.refresh()
	var mark_id:=str(squad.mark.mark_id);var marked_pose:=pose_at(Vector3(.7,1.08,-8))
	check(squad.volley_intent(marked_pose,40.).get("volley_mark_id","")==mark_id,"Large reticle accepts an intentional physical miss beside the enemy")
	check(squad.volley_intent(marked_pose,3.).is_empty(),"Volley cannot extend weapon range")
	check(squad.volley_intent(marked_pose,40.,"202").is_empty(),"An explicitly different target does not consume Volley")
	check(squad.volley_intent(pose_at(Vector3(4,1,-8)),40.).is_empty(),"An attack elsewhere does not automatically consume Volley")
	var other:=Actor.new();world.add_child(other);other.record=actor.record.duplicate(true);other.record.id="202";other.position=Vector3(.35,0,-4);other.collision_layer=8
	var other_shape:=CollisionShape3D.new();other_shape.shape=box;other_shape.position=actor.visual_bounds().get_center();other.add_child(other_shape)
	await physics_frame;await physics_frame
	check(squad.volley_intent(marked_pose,40.).is_empty(),"A closer enemy under aim takes precedence over a marker behind it")
	other.collision_layer=0;other.queue_free();await physics_frame
	for index in [0,2,3]:
		equip(index);var state=rig.weapons[index].state
		var shot:Dictionary=state.ranged_snapshot(true,"standing");shot.item_id=str(state.profile.item_id)
		var immutable:Dictionary=live.register_shot(shot,marked_pose,marked_pose.origin)
		check(not immutable.is_empty() and immutable.get("cosmetic_only",false) and immutable.has("volley_mark_id"),"Ranged delivery binds mark and cannot create duplicate physical damage "+str(index))
		check(live.queue[0].payload.has("volley_target_id") and not live.queue[0].payload.has("position"),"Launch sends mark intent without fabricated impact coordinates "+str(index))
		var before:int=live.queue.size();live.contact(immutable,{"id":"201","session_id":"squad-session"},actor.position,Vector3.UP,8.)
		check(live.queue.size()==before,"Physical contact cannot enqueue a second impact "+str(index))
		await live.pump()
		check(live.shots.is_empty() and squad.mark.is_empty(),"Accepted guaranteed strike retires receipt and only this viewer's marker "+str(index))
	equip(0);app.reject=true;var rejected_state=rig.weapons[0].state;var rounds_before:int=rejected_state.rounds
	rejected_state.reserve_rounds(1);var rejected_shot:Dictionary=rejected_state.ranged_snapshot(true,"standing");rejected_shot.merge({"item_id":str(rejected_state.profile.item_id),"local_ammo_spent":1})
	check(not live.register_shot(rejected_shot,marked_pose,marked_pose.origin).is_empty(),"A guaranteed shot reserves its ordinary magazine round")
	await live.pump();check(rejected_state.rounds==rounds_before and not squad.mark.is_empty(),"Confirmed rejected guarantee refunds the local round and keeps the mark")
	equip(0);app.reject=true;check(live.register_squadleader("rally","2",pose_at(Vector3(2,.9,-6)),"right"),"Support command reserves its cooldown while awaiting authority")
	await live.pump();check(float(rig.abilities.cooldowns.get("rally",-1))==0,"Rejected support restores the native cooldown instead of retaining prediction")
	# Gesture attacks use their own native ability range, while self buffs never spend marks.
	equip(0);session.player_state.pistoleer={}
	for id:String in ["fan_shot","run_and_gun"]:session.player_state.pistoleer[id]={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":20.,"action_cost":60,"mind_cost":30,"interval_seconds":1.}
	session.weapon_state.abilities.append({"id":"fan_shot","max_range_m":12.});session.sequence+=1;live.refresh_authority()
	check(live.register_pistoleer("fan_shot",marked_pose,"right") and live.queue.back().payload.has("volley_mark_id"),"Fan Shot gesture binds the native Volley guarantee")
	await live.pump();check(squad.mark.is_empty(),"Gesture receipt consumes the viewer's mark")
	refresh(context());live.next_launch_usec=0;rig.abilities.cooldowns.clear()
	check(live.register_pistoleer("run_and_gun",marked_pose,"right") and not live.queue.back().payload.has("volley_mark_id"),"Self-buff gesture cannot consume a guaranteed hit")
	live.queue.clear();live.shots.clear();live.next_launch_usec=0
	var thrower:=ThrowScout.new();world.add_child(thrower);thrower.set_process(false);thrower.app=app;thrower.pose=marked_pose
	var throw_bag:=ThrowBag.new();world.add_child(throw_bag);thrower.bag=throw_bag
	for grenade:bool in [false,true]:
		refresh(context());thrower.accepted=false
		check(thrower.target_under_reticle(grenade)=="201","Throwable reticle accepts native marked target outside its physical body "+str(grenade))
		var item:Dictionary={"id":"81","template":"fixture","tool_kind":"grenade" if grenade else "trap"}
		if grenade:await thrower.throw_grenade(item,"201")
		else:await thrower.throw_trap(item,"201")
		check(not squad.mark.is_empty() and thrower.calls.back().detail.has("volley_mark_id"),"Rejected throwable intent preserves the mark "+str(grenade))
		thrower.accepted=true
		if grenade:await thrower.throw_grenade(item,"201")
		else:await thrower.throw_trap(item,"201")
		check(squad.mark.is_empty() and throw_bag.finished.back(),"Accepted throwable consumes only after native charge acceptance "+str(grenade))
	refresh(context());thrower.pose=pose_at(Vector3(0,1,-40));value=context();value.volley_fire.mark.position=[0,0,40];refresh(value)
	check(thrower.throwable_volley_intent(true,"201").is_empty() and not thrower.throwable_volley_intent(false,"201").is_empty(),"Grenades keep32m range while traps retain64m range")
	refresh(context());squad.consumed(str(session.player_state.squad_leader.volley_fire.mark.id))
	thrower.queue_free();throw_bag.queue_free()
	# A separate member keeps the same mark until their own receipt arrives.
	var peer=preload("res://combat/squad_leader.gd").new();world.add_child(peer);peer.setup(rig)
	value=session.player_state.squad_leader.duplicate(true);peer.observe(value,"other-member",live.register_squadleader,live.world,live.is_ready);peer.refresh()
	check(not peer.mark.is_empty(),"Consuming one member's mark does not erase another member's local charge")
	peer.observe({},"member-left",live.register_squadleader,live.world,live.is_ready);peer.refresh()
	check(peer.mark.is_empty(),"Missing native mark removes it on leave or zone change")
	peer.queue_free()
	# Melee can cast Volley at its command range, then consume only inside melee range.
	equip(1);check(squad.ultimate(pose_at(Vector3(0,1,-8))),"Melee weapon casts selected Volley beyond melee reach")
	check(live.queue.back().payload.ability_id=="volley_fire","Any-weapon ultimate uses support authority route")
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;rig.abilities.cooldowns.clear()
	actor.position=Vector3(0,0,-2);value=context();value.volley_fire.mark.position=[0,0,2];refresh(value)
	var melee_shot:Dictionary={"kind":"melee","item_id":str(rig.weapons[1].state.profile.item_id),"weapon_id":"knife_survival"}
	var melee:Dictionary=live.register_melee(melee_shot,pose_at(Vector3(.7,1.08,-2)))
	check(melee.has("volley_mark_id") and live.queue.back().payload.has("volley_mark_id"),"Valid melee swing sends native guaranteed-hit intent")
	await live.pump();check(squad.mark.is_empty(),"Melee consumes the local mark on the native receipt")
	# Unarmed is another native equipment family and shares the same support path.
	check(rig.configure_unarmed(catalog.unarmed),"Unarmed source profile configures")
	rig.stow();session.weapon_state={"item_id":"88","kind":"melee","certified":true,"unarmed":true,"fire_interval_seconds":1.,"max_range_m":2.,"projectile_speed":45.,"abilities":profiles[0].abilities.duplicate(true),"ability_loadout":{"slots":["","","",""],"ultimate":"volley_fire"}}
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;rig.abilities.cooldowns.clear();refresh(context())
	check(squad.toggle(pose_at(Vector3(2,.9,-6))) and live.register_squadleader("rally","2",pose_at(Vector3(2,.9,-6)),"right"),"Unarmed opens and casts group support")
	squad.close();live.queue.clear();live.shots.clear();live.next_launch_usec=0;rig.abilities.cooldowns.clear()
	check(squad.ultimate(pose_at(Vector3(0,1,-2))),"Unarmed casts selected Volley Fire")
	# Same chord and support capture are used with melee, ranged and heavy weapons.
	actor.position=Vector3(0,0,-8);await physics_frame
	for index in range(4):
		equip(index);head.global_transform=pose_at(Vector3(0,1,-8));rig.weapons[index].visual.global_transform=head.global_transform
		squad.ultimate_input.reset();rig.sample_squad_controls(.02,0,0,true,true);rig.sample_squad_controls(.02,1,1,true,true)
		check(rig.squad_input_captured and live.queue.size()==1 and live.queue[0].payload.ability_id=="volley_fire","Two-trigger chord owns ultimate on every weapon "+str(index))
	# Waiting for the command chord must still permit a normal primary attack.
	equip(0);var primary_pose:=Transform3D(Basis.IDENTITY,Vector3(3,1,-.4));var support_pose:=Transform3D(Basis.IDENTITY,Vector3(3.05,1,-.4))
	rig.sample_squad_controls(.02,0,0,true,true);rig.sample(.02,primary_pose,support_pose,1,1,0,true,true)
	for index in range(10):
		rig.sample_squad_controls(.02,1,0,true,true);rig.sample(.02,primary_pose,support_pose,1,1,1,true,true)
	check(live.queue.size()==1 and live.queue[0].kind=="fire" and not live.queue[0].payload.has("volley_mark_id"),"Selecting Volley preserves normal trigger fire after the deliberate chord window")
	equip(0);squad.toggle(pose_at(Vector3(2,.9,-6)));rig.sample_squad_controls(.02,1,0,true,true)
	squad.close();rig.sample_squad_controls(.02,1,0,true,true)
	check(rig.squad_input_captured,"Closing support VATS requires a trigger release before weapon fire")
	rig.sample_squad_controls(.02,0,0,true,true);rig.sample_squad_controls(.02,0,0,true,true)
	check(not rig.squad_input_captured,"Releasing the support trigger restores normal attacks")
	world.queue_free();manager.queue_free();await process_frame;await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","native_transport":"mocked","live_xr":false};print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/squad-leader-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
