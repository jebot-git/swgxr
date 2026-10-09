extends SceneTree
## Real source geometry and client collision; explicit mock HTTP authority, no live claim.
const Live=preload("res://combat/live_world.gd")
const Rig=preload("res://combat/ranged_rig.gd")
class Host extends Node3D:
	var args:Dictionary={}
	var datapad_account:="fixture"
	var datapad_character_id:="123"
	var world_ready:=false
	var xr_requested:=false
	var xr_focused:=false
	var reply:Dictionary={}
	var calls:Array=[]
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x+3500,point.y+5,-point.z-4800)
	func api(method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"method":method,"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
var errors:Array[String]=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	var stage:=Node3D.new();host.add_child(stage);stage.set_meta("manifest",{"origin":[3500,5,-4800]})
	var body:=CharacterBody3D.new();host.add_child(body)
	var head:=Camera3D.new();host.add_child(head);head.position=Vector3(0,1.7,0)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id="987";profile.source_kind="core3_weapon_instance";profile.certified=true
	var rig:=Rig.new();host.add_child(rig);check(rig.configure(head,body,[profile]),"Original FWG5 rig configures")
	rig.set_process(false);rig.set_physics_process(false)
	var live:=Live.new();host.add_child(live);live.configure(host,rig,stage,body);live.set_process(false)
	var mob:Dictionary={"id":"101","kind":"creature","template":"object/mobile/worrt_hue.iff","name":"Worrt","position":[3500,5,-4790],"heading_radians":0.0,"scale":1.0,"health":100,"max_health":100,"ham":[100,80,60],"max_ham":[100,80,60],"dead":false,"passive":true,"lair_id":"102"}
	var lair:Dictionary={"id":"102","kind":"lair","template":"object/tangible/lair/base/poi_all_lair_dead_log_small.iff","name":"Worrt lair","position":[3503,5,-4790],"heading_radians":0.0,"scale":1.0,"health":500,"max_health":500,"dead":false}
	var snapshot:Dictionary={"ready":false,"full":true,"actors":[mob,lair],"player":{"position":[3500,5,-4800],"ham":[1000,900,800],"max_ham":[1000,900,800],"dead":false,"incapacitated":false,"posture":0,"wounds":[0,0,0],"shock_wounds":0,"weapon_item_id":"987"},"weapon":{"item_id":"987","certified":true,"fire_interval_seconds":3.0,"max_range_m":50.0,"projectile_speed":100.0}}
	var envelope:Dictionary={"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"123","session_id":"native-session","sequence":1,"session_live":true,"snapshot":snapshot}
	host.reply=envelope
	check(await live.start(body.global_position,0),"Owner's live envelope admits session")
	check(not live.is_ready() and live.live and live.actors.size()==2,"Protected session projects native actors but disarms before readiness")
	live.poll_clock=1;host.reply=envelope.duplicate(true);host.reply.sequence=2
	await live.pump();check(not host.calls[-1].payload.ready,"Loading client never clears native load-screen protection")
	host.world_ready=true;host.xr_requested=true;live.poll_clock=1;host.reply.sequence=3
	await live.pump();check(not host.calls[-1].payload.ready,"Unfocused headset retains initial native load-screen protection")
	host.xr_focused=true;live.poll_clock=1;host.reply.sequence=4;host.reply.snapshot.ready=true
	await live.pump();check(host.calls[-1].payload.ready and live.is_ready(),"Ready focused client activates through confirmed native ready response")
	envelope.sequence=4;envelope.snapshot.ready=true

	check(live.actors["101"].visual.skeleton.get_bone_count()==30,"Living creature uses original animated skeleton")
	check(live.actors["101"].visual.meshes.all(func(mesh):return mesh.layers==1),"Remote creature head/body parts share the visible NPC layer, never the hidden local-player head layer")
	check(live.actors["102"].visual.position.y==0,"Original lair authored origin is not bottom-aligned")
	check(live.actors["101"].global_position.is_equal_approx(Vector3(0,0,-10)),"SWG source Z reflects to actual stage coordinates")
	check(is_equal_approx(rig.weapons[0].state.effective_rpm(),20) and rig.weapons[0].state.ability_state==null,"Native cadence overrides prototype RPM and local HAM costs")
	var shot:Dictionary={"item_id":"987","weapon_id":"pistol_fwg5","sequence":1,"range":100.0,"speed":100.0,"core3":profile.core3,"range_scale":1.1,"two_hands":true,"firing_posture":"prone","condition_fraction":1.0}
	var registered:=live.register_shot(shot,Transform3D(Basis.IDENTITY,Vector3(0,0.3,0)),Vector3.ZERO)
	shot.item_id="wrong";shot.core3.minDamage=999999
	check(not registered.is_empty() and live.shots[registered.shot_id].shot.item_id=="987" and is_equal_approx(registered.range,55),"Launch snapshot preserves server base range and two-handed pistol scaling")
	check(live.register_shot(registered,Transform3D.IDENTITY,Vector3.ZERO).is_empty(),"Native3s cooldown rejects immediate duplicate launch")
	var hit:Dictionary={"collider":live.actors["101"],"position":Vector3(0,0.3,-10),"normal":Vector3.BACK}
	rig.rounds_sim.resolve_hit(registered,hit,10)
	check(live.actors["101"].record.health==100 and not live.actors["101"].record.dead,"Local projectile contact cannot mutate live HP or death")
	check(live.queue.size()==2 and live.queue[0].kind=="fire" and live.queue[1].kind=="impact","Contact queues behind registration with same immutable shot ID")
	check(live.queue[0].payload.two_hands and live.queue[0].payload.firing_posture=="prone" and not live.queue[0].payload.has("damage"),"Server receives launch pose/grip, never client damage")
	var response:=envelope.duplicate(true);response.sequence=5;response.mutation={"success":true,"operation":"fire","shot_id":registered.shot_id};host.reply=response
	await live.pump()
	check(live.shots[registered.shot_id].accepted and host.calls[-1].path.ends_with("/fire"),"Fire acknowledgement precedes impact transport")
	response=response.duplicate(true);response.sequence=6;response.mutation={"success":true,"operation":"impact","shot_id":registered.shot_id,"target_id":"101","damage":100};response.snapshot.actors[0].health=0;host.reply=response
	await live.pump()
	check(live.actors["101"].record.health==0 and not live.actors["101"].record.dead,"Zero health alone never invents native death")
	check(live.confirmed_contacts==1 and live.shots.is_empty(),"Confirmed contact consumes one registered shot")
	response=response.duplicate(true);response.sequence=7;response.snapshot.actors[0].dead=true
	check(live.accept_response(response) and live.actors["101"].record.dead and live.actors["101"].collision_layer==0,"Only authoritative dead state replaces living skin with source frozen pose")
	check(live.actors["101"].visual is MeshInstance3D,"Confirmed death uses original corpse appearance")
	live.next_launch_usec=0
	var rejected:=live.register_shot(registered,Transform3D.IDENTITY,Vector3.ZERO)
	live.contact(rejected,live.actors["102"].core3_identity(),Vector3(3,0,-10),Vector3.BACK,10)
	var cadence:=response.duplicate(true);cadence.sequence=8;cadence.error_code="cadence";cadence.mutation={"success":false,"operation":"fire","error_code":"cadence"};host.reply=cadence
	await live.pump()
	var count:=host.calls.size();await live.pump()
	check(live.is_ready() and live.rejected_shots==1 and host.calls.size()==count,"Native cadence rejection discards queued contact without ending session or retry")
	var stale:=response.duplicate(true);stale.sequence=2
	check(not live.accept_response(stale),"Older sequence cannot rewind confirmed death")
	var malformed:=response.duplicate(true);malformed.sequence=9;malformed.snapshot.actors[0].position=[NAN,0,0]
	check(not live.accept_response(malformed),"Nonfinite network transforms rejected before actor mutation")
	var invalid_vitals:=cadence.duplicate(true);invalid_vitals.sequence=9;invalid_vitals.snapshot.player.wounds=[0,-1,0]
	check(not live.accept_response(invalid_vitals),"Negative wounds rejected before authorizing shots")
	var incap:=cadence.duplicate(true);incap.sequence=9;incap.snapshot.player.posture=13;incap.snapshot.player.incapacitated=true
	check(live.accept_response(incap) and not live.is_ready(),"Authoritative incapacitation blocks ranged launch while snapshots stay live")
	var mixed:=cadence.duplicate(true);mixed.sequence=10
	var missing:=mob.duplicate(true);missing.id="103";missing.template="object/mobile/source_appearance_not_imported.iff"
	mixed.snapshot.actors.append(missing)
	var known_lair=live.actors["102"]
	check(live.accept_response(mixed) and live.is_ready() and live.actors.size()==3 and live.actors["102"]==known_lair,"One unavailable appearance preserves healthy session and all known original actors")
	check(live.actors["103"].record.id=="103" and live.actors["103"].collider==null and live.actors["103"].collision_layer==0,"Wholly missing appearance retains native identity without invented collision")
	check(live.statistics().appearances.unavailable==1 and live.statistics().appearances.actor_errors.size()==1 and not live.statistics().appearances.notice.is_empty(),"Missing appearance has explicit bounded status and user notice")
	live.next_launch_usec=0
	var guarded:=live.register_shot(registered,Transform3D.IDENTITY,Vector3.ZERO)
	var queued:=live.queue.size()
	live.contact(guarded,live.actors["103"].core3_identity(),Vector3.ZERO,Vector3.UP,0)
	check(live.queue.size()==queued and not live.shots[guarded.shot_id].contacted,"Unavailable entity cannot receive even a forged client contact")
	var space:=envelope.duplicate(true);space.sequence=11;space.snapshot.actors=[];space.snapshot.weapon=null;space.snapshot.player.space_active=true
	space.snapshot.player.jtl={"scope":"noncombat_yacht","enabled":true,"ship":{"id":"1234","station":"pilot"}}
	check(live.accept_response(space) and not live.is_ready() and live.weapon.is_empty() and live.queue.is_empty(),"Validated noncombat yacht snapshot accepts absent weapon and discards ground attacks")
	var guest:=space.duplicate(true);guest.sequence=12;guest.snapshot.player.jtl.scope="noncombat_navigation";guest.snapshot.player.jtl.ship.owner_id="999999";guest.snapshot.player.jtl.ship.station="gunner"
	check(live.accept_response(guest) and live.weapon.is_empty() and not live.is_ready(),"Authenticated guest gunner accepts native noncombat state without owning the ship")
	var unproven:=space.duplicate(true);unproven.sequence=13;unproven.snapshot.player.erase("jtl")
	check(not live.accept_response(unproven),"Space flag alone cannot bypass combat weapon validation")
	live.fail("Transport lost")
	check(not live.is_ready() and live.actors.is_empty() and live.queue.is_empty() and not rig.allowed,"Transport failure removes hit targets and disarms player")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"gpu_tested":false,"headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/live-combat-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	host.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
