extends SceneTree
const Sampling=preload("res://bioengineer/sampling.gd")
const Rig=preload("res://combat/ranged_rig.gd")
class World extends Node:
	var actors: Dictionary={}
class App extends Node:
	var datapad_epoch:=1
	var live_combat: Node
	var combat_rig: Node3D
	func source_position_at(p: Vector3) -> Vector3: return Vector3(p.x,p.y,-p.z)
class Target extends Node3D:
	var targetable:=true
	func is_targetable() -> bool: return targetable
	func visual_bounds() -> AABB: return AABB(Vector3(-0.5,0,-0.7),Vector3(1,1.5,1.4))
class Scout extends "res://scout/controller.gd":
	var calls: Array=[]
	func request(action: String, detail: Dictionary={}) -> Dictionary:
		busy=true;calls.append({"action":action,"detail":detail.duplicate(true)})
		await get_tree().process_frame
		busy=false
		return {"ok":true,"mutation":{"sampling_started":true}}
var failures: Array=[]
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func _initialize() -> void:
	create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func tracker(side: String) -> XRControllerTracker:
	var value:=XRControllerTracker.new();value.type=XRServer.TRACKER_CONTROLLER;value.name=side+"_hand"
	value.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	for action in ["primary_click","ax_button","by_button"]: value.set_input(action,false)
	value.set_input("primary",Vector2.ZERO);value.set_input("grip",0.9);value.set_input("trigger",0.0)
	var pose:=Transform3D(Basis.IDENTITY,Vector3(-0.2 if side=="left" else 0.2,1.3,-0.4))
	value.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	value.set_pose("aim",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(value);return value
func run() -> void:
	var input:=Sampling.new()
	check(not input.sample("right",1,true,true,true).attempt,"Initial held trigger is not a click")
	input.sample("right",0,true,true,true)
	check(input.sample("right",1,true,true,true).attempt,"Fresh armed trigger requests sampling")
	check(not input.sample("right",1,true,true,true).attempt,"Held trigger never repeats")
	check(input.sample("right",1,true,true,false).capture,"Sampling retains trigger capture after disarming")
	check(not input.sample("right",0,true,true,false).capture,"Release frees combat trigger")
	input.sample("right",0,false,true,true)
	check(not input.sample("right",1,true,true,true).attempt,"Tracking reacquisition cannot synthesize click")
	input.sample("right",0,true,false,true)
	check(not input.sample("right",1,true,false,true).attempt,"Blocked UI cannot start sampling")
	check(not input.sample("right",1,true,true,true).attempt,"Leaving UI with held trigger cannot defer sample")
	var bounds:=AABB(Vector3(-.5,0,-1),Vector3(1,1.5,2))
	var pose:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(8,0,-4))
	check(Sampling.touches(pose,bounds,pose*Vector3(0,1.6,0)),"Hand slightly above rotated creature is in contact")
	check(not Sampling.touches(pose,bounds,Vector3.ZERO),"World origin is not stale creature contact")
	check(not Sampling.touches(pose,AABB(),pose.origin),"Unknown creature geometry cannot sample")
	var head_tracker:=XRPositionalTracker.new();head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.name="head"
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var left:=tracker("left");var right:=tracker("right")
	var app:=App.new();root.add_child(app);app.live_combat=World.new();app.add_child(app.live_combat)
	var origin: XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(origin)
	var body=origin.get_node("PlayerBody");body.active=true;body.set_physics_process(false)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var combat:=Rig.new();origin.add_child(combat);app.combat_rig=combat
	check(combat.configure(origin.get_node("XRCamera3D"),body,[fixture.weapons.pistol_cdef],"right",origin),"Actual weapon rig configures with original CDEF assets")
	combat.set_physics_process(false);combat.set_process(false);combat.configure_player_combat(fixture.player_combat);combat.set_allowed(true);combat.draw(0)
	var scout:=Scout.new();app.add_child(scout);scout.set_process(false);scout.app=app;scout.rig=origin;scout.body=body;scout.last_reply=0;combat.scout=scout
	body.combat_pools.selection_replaced.connect(scout.selection_replaced)
	scout.state={"sample_dna_available":true,"sample_dna_recovery":11,"targets":[{"id":"10","dna_eligible":true}]}
	var target:=Target.new();app.live_combat.add_child(target);target.position=Vector3(0,0,-.4);app.live_combat.actors["10"]=target
	await process_frame
	check(combat.active_profile().abilities.any(func(a):return a.id=="sample_dna"),"Certified DNA skill joins weapon ability wheel")
	check(scout.dna_target_at(Vector3(.2,1.3,-.4))=="10","Contact targets visible creature independently of reticle")
	target.position.x=5
	check(scout.dna_target_at(Vector3(.2,1.3,-.4)).is_empty(),"Moving creature leaves previous hand contact")
	target.position.x=0;target.targetable=false
	check(scout.dna_target_at(Vector3(.2,1.3,-.4)).is_empty(),"Dead/unavailable live appearance cannot be sampled")
	target.targetable=true
	var wall:=StaticBody3D.new();wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1,.1,1);shape.shape=box;wall.add_child(shape);app.add_child(wall);wall.position=Vector3(0,1.5,-.2)
	await physics_frame
	check(scout.dna_target_at(Vector3(.2,1.3,-.4)).is_empty(),"Stage collision blocks contact through geometry")
	wall.free();await physics_frame
	combat.sample_ability_input(true,Vector2.ZERO,false,true);combat.sample_ability_input(false,Vector2.ZERO,false,true)
	var index: int=combat.ability_ui.entries.find(scout.dna_entry())
	var angle: float=TAU*index/combat.ability_ui.entries.size()
	combat.sample_ability_input(false,Vector2(sin(angle),cos(angle)),false,true)
	check(index>=0 and combat.abilities.selected=="sample_dna" and not combat.abilities.primed,"Wheel selection uses shared weapon ability state without firing")
	combat.sample_ability_input(false,Vector2.ZERO,true,true);combat.sample_ability_input(false,Vector2.ZERO,false,true)
	check(combat.abilities.primed,"A primes DNA like a weapon skill")
	var vitals: Dictionary={"ham":[1000,1000,1000],"max_ham":[1000,1000,1000],"wounds":[0,0,0]}
	check(combat.abilities.apply_authoritative(vitals) and combat.abilities.primed,"Routine native HAM replication preserves primed contact skill while reaching")
	combat._physics_process(.01)
	var rounds: int=combat.weapons[0].state.rounds
	right.set_input("trigger",1.0);await process_frame;combat._physics_process(.01)
	check(scout.calls.size()==1 and scout.calls[0].detail.target_id=="10","Main-hand creature contact plus fresh trigger submits sampling")
	check(scout.calls[0].detail.hand_position==[.2,1.3,.4] or Vector3(scout.calls[0].detail.hand_position[0],scout.calls[0].detail.hand_position[1],scout.calls[0].detail.hand_position[2]).is_equal_approx(Vector3(.2,1.3,.4)),"Request carries hand in source coordinates")
	check(not combat.abilities.primed and combat.weapons[0].state.rounds==rounds,"Sampling consumes prime without firing the held gun")
	await process_frame
	for i in range(4): combat._physics_process(.05)
	check(scout.calls.size()==1 and combat.weapons[0].state.rounds==rounds,"Held sampling trigger cannot repeat sampling or fire after response")
	right.set_input("trigger",0.0);await process_frame;combat._physics_process(.01)
	combat.abilities.primed=true;left.set_input("trigger",1.0);await process_frame;combat._physics_process(.01)
	check(scout.calls.size()==2,"Offhand trigger samples creature under offhand")
	await process_frame
	left.set_input("trigger",0.0);await process_frame;combat._physics_process(.01)
	combat.abilities.primed=true;scout.busy=true;right.set_input("trigger",1.0);await process_frame;combat._physics_process(.01);scout.busy=false;combat._physics_process(.01)
	check(scout.calls.size()==2,"Busy native request cannot queue a delayed sampling click")
	right.set_input("trigger",0.0);left.set_input("trigger",0.0);await process_frame;combat._physics_process(.01)
	scout.state.sample_dna_pending=true;combat.abilities.primed=true
	left.set_input("trigger",1.0);await process_frame;combat._physics_process(.01)
	check(scout.calls.size()==2,"Pending native sampling blocks a second attempt")
	scout.state.sample_dna_pending=false;left.set_input("trigger",0.0);await process_frame;combat._physics_process(.01)
	combat.offhand_occupied=true;left.set_input("trigger",1.0);await process_frame;combat._physics_process(.01)
	check(scout.calls.size()==2,"A hand occupied by another tool cannot also sample")
	combat.offhand_occupied=false;left.set_input("trigger",0.0);await process_frame;combat._physics_process(.01)
	target.position.x=5;right.set_input("trigger",1.0);await process_frame;combat._physics_process(.01)
	check(scout.calls.size()==2 and combat.abilities.primed,"Invalid contact keeps the prime and never sends a remote sample")
	target.position.x=0
	combat.selected=-1
	check(combat.active_profile().abilities.any(func(a):return a.id=="sample_dna"),"DNA skill remains available without a held weapon")
	combat.selected=0
	scout.last_reply=13
	check(scout.dna_entry().is_empty(),"Stale native eligibility removes sampling from menu")
	scout.last_reply=0;combat.abilities.primed=true;combat.abilities.replace_selection({"id":"other"})
	check(combat.abilities.cooldowns.sample_dna==11 and scout.cooldown_queue==["discard_sample_dna"],"Replacing primed DNA applies recovery without triggering it")
	check(combat.ability_ui.texture("sampledna")!=null,"Original Sample DNA command icon loaded")
	app.queue_free();XRServer.remove_tracker(left);XRServer.remove_tracker(right);XRServer.remove_tracker(head_tracker)
	await process_frame;await process_frame
	var report: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"mocked","backend":"mocked","renderer":"headless dummy","live_headset":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/bioengineer-sampling-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if failures.is_empty() else 1)
