extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="carbineer"
	var datapad_character_id:="1"
	var session_leaving:=false
	var world_ready:=true
	var reject:=false
	var calls:Array=[]
	var delay:=0.0
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		if delay>0:await get_tree().create_timer(delay).timeout
		else:await get_tree().process_frame
		return {"mutation":{"success":not reject,"shot_id":payload.shot_id,"ability_id":payload.get("ability_id",""),"interval_seconds":.25,"damage":90}}
class Session extends Node:
	var live:=true
	var busy:=false
	var character_id:="1"
	var session_id:="carbineer-session"
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
	var snapshot_usec:=Time.get_ticks_usec()
	var session_id:="carbineer-session"
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":1000,"boss":false,"level":50,"melee_control_available":true,"knockdown_available":true}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"carbineer-session"}
	func visual_bounds()->AABB:return AABB(Vector3(-.4,0,-.3),Vector3(.8,1.8,.6))
var checks:=0
var errors:Array=[]
var rig:Node3D
var live:Node3D
var app:Host
var session:Session
var actor:Actor
var head:Camera3D
var origin:XROrigin3D
var trackers:Dictionary={}
var context:Dictionary={}
var last_yaw:=0.
var last_roll:=0.
var facing:=Basis.IDENTITY
var head_tracked:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func gesture_frame(yaw:float,roll:=0.)->void:
	last_yaw=yaw;last_roll=roll
	var mirror:=1. if rig.dominant=="right" else -1.
	var main:XRController3D=origin.get_node(rig.dominant.capitalize()+"Hand")
	var support:XRController3D=origin.get_node("LeftHand" if rig.dominant=="right" else "RightHand")
	var basis:=Basis(Vector3.UP,deg_to_rad(yaw*mirror))*Basis(Vector3.FORWARD,deg_to_rad(roll*mirror))
	main.global_transform=Transform3D(facing*basis,head.global_position+facing*Vector3(.12*mirror,-.4,-.25))
	support.global_position=main.global_position+main.global_basis*Vector3(0,0,-.28)
	trackers[rig.dominant].set_pose("aim",Transform3D(facing*basis,Vector3.ZERO),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	rig.sample_carbineer_gestures(.02,head_tracked)
func move_to(yaw:float,roll:=0.)->void:
	var a:=last_yaw;var b:=last_roll
	for i in range(1,11):gesture_frame(lerpf(a,yaw,i/10.),lerpf(b,roll,i/10.))
func neutral()->void:
	move_to(0)
	for i in range(15):gesture_frame(0)
func sweep()->void:
	move_to(15);move_to(-15);move_to(0)
	for i in range(8):gesture_frame(0)
func brace()->void:
	move_to(0,65)
	for i in range(42):gesture_frame(0,65)
	move_to(0)
func reset()->void:
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;app.reject=false;app.delay=0
	rig.abilities.cooldowns.clear();rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable();rig.offhand_occupied=false;rig.support_latched=true;rig.two_hands=true;rig.carbineer_gestures.clear();rig.carbineer_input_captured=false;rig.support_grip_down=true;rig.main_grip_down=true;rig.target_abilities.reset()
	rig.weapons[0].state.rounds=int(rig.weapons[0].state.profile.capacity);rig.weapons[0].state.reload_until=-1;rig.weapons[0].state.next_shot=0;rig.weapons[0].state.block();rig.rounds_sim.clear()
	session.player_state={"ham":[3000,1000,1000],"carbineer":context.duplicate(true)};session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority()
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]});head_tracked=true;facing=Basis.IDENTITY;head.basis=facing;last_yaw=0;last_roll=0
	for side:String in trackers:trackers[side].set_input("trigger",0.);trackers[side].set_input("grip",1.)
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func start_blast()->void:
	var gun:=Vector3(.12,1.3,-.25)
	var aim:=Transform3D(Basis.IDENTITY,gun)
	rig.weapons[0].visual.global_transform=aim
	var support:=Transform3D(Basis.IDENTITY,rig.support_point(0))
	rig.sample(.02,aim,support,1,1,0,true,true,false,0)
	rig.sample(.02,aim,support,1,1,1,true,true,false,1)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	origin=XROrigin3D.new();world.add_child(origin);head=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",1.);tracker.set_input("trigger",0.);XRServer.add_tracker(tracker);trackers[side]=tracker
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=tracker.name;controller.pose="grip";origin.add_child(controller)
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.carbine_e11.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
	profile.ability_loadout={"family":"carbines","slots":["crippling_shot","wild_shot","suppression_fire","charge_shot"],"ultimate":"charge_blast"}
	for id:String in profile.ability_loadout.slots:
		profile.abilities.append({"id":id,"label":id,"activation":"native_ranged","sac_policy":"fixed","base_sac":{"health":0,"action":60,"mind":25},"cooldown_seconds":18,"max_range_m":float(profile.core3.maxRange),"conditions_met":true,"ammo_cost":1,"interval_seconds":1.})
	for id:String in ["full_auto_sweep","tactical_brace","charge_blast"]:
		context[id]={"learned":true,"conditions_met":true,"cooldown_seconds":120 if id=="charge_blast" else 60 if id=="tactical_brace" else 20,"cooldown_remaining_seconds":0,"action_cost":150 if id=="charge_blast" else 50 if id=="tactical_brace" else 90,"mind_cost":80 if id=="charge_blast" else 25 if id=="tactical_brace" else 30,"interval_seconds":2. if id=="charge_blast" else .25 if id=="tactical_brace" else 1.5}
		profile.abilities.append({"id":id,"label":id,"category":"ultimate" if id=="charge_blast" else "gesture","activation":"carbineer_ultimate" if id=="charge_blast" else "carbineer_gesture","ultimate":id=="charge_blast"})
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production carbine rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0)
	app=Host.new();world.add_child(app);app.player=body;app.stage=world
	session=Session.new();world.add_child(session);session.weapon_state={"kind":"ranged","item_id":"99","certified":true,"abilities":profile.abilities,"ability_loadout":profile.ability_loadout.duplicate(true),"fire_interval_seconds":1.,"special_interval_seconds":1.,"max_range_m":float(profile.core3.maxRange),"projectile_speed":100.}
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	await physics_frame;await physics_frame
	reset();neutral();sweep()
	check(live.queue.size()==1 and live.queue[0].kind=="carbineer" and live.queue[0].payload.ability_id=="full_auto_sweep","Supported sweep queues one native cone")
	if live.queue.is_empty():world.free();quit(1);return
	check(not live.queue[0].payload.has("target_id") and not live.queue[0].payload.has("damage") and live.queue[0].payload.two_hands,"Native server owns cone victims, defenses and damage")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-3,"Sweep reserves three local rounds")
	check(rig.weapons[0].state.next_shot-rig.weapons[0].state.clock>=1.5,"Pending cone recovery blocks premature ordinary ammo")
	check(live.queue[0].payload.direction[2]>.9,"Sweep resolves final forward muzzle instead of swept union")
	var request:Dictionary=live.queue[0].duplicate(true)
	app.reject=true;await live.pump()
	check(live.shots.is_empty() and rig.weapons[0].state.rounds==int(profile.capacity) and float(rig.abilities.cooldowns.full_auto_sweep)==0,"Rejected sweep restores ammo and cooldown once")
	live.combat_receipt(request,{"mutation":{"success":false,"shot_id":request.shot_id}});check(rig.weapons[0].state.rounds==int(profile.capacity),"Duplicate rejection cannot mint rounds")
	reset();neutral();sweep();var presentations:int=rig.rounds_sim.fired_presentations;await live.pump()
	check(app.calls.back().path=="/combat/session/carbineer" and live.shots.is_empty() and rig.weapons[0].state.rounds==int(profile.capacity)-3,"Production Gameplay HTTP path commits sweep ammo")
	check(rig.rounds_sim.fired_presentations==presentations+3,"Accepted area attack presents three cosmetic bolts")
	for bolt:Dictionary in rig.rounds_sim.bolts:check(bolt.shot.get("cosmetic_only",false),"Area presentation cannot emit damage contacts")
	reset();neutral();brace();check(live.queue.size()==1 and live.queue[0].payload.ability_id=="tactical_brace","Cant-hold-return queues self-buff")
	check(rig.weapons[0].state.rounds==int(profile.capacity),"Tactical Brace spends no ammunition")
	await live.pump();check(live.shots.is_empty() and rig.abilities.cooldowns.tactical_brace==60,"Brace receipt retires intent and retains shared cooldown")
	for mode:String in ["menu","head_tracking","off_tracking","unlearned","cooldown","occupied","support_grip","main_grip","unlatched","main_trigger","off_trigger","weapon_family","uncertified","inventory","reload","low_ammo"]:
		reset();neutral()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="head_tracking":head_tracked=false
		if mode=="off_tracking":trackers.left.invalidate_pose("grip")
		if mode=="unlearned":rig.carbineer_context.full_auto_sweep.learned=false
		if mode=="cooldown":rig.carbineer_context.full_auto_sweep.cooldown_remaining_seconds=10
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="support_grip":trackers.left.set_input("grip",0.)
		if mode=="main_grip":trackers.right.set_input("grip",0.)
		if mode=="unlatched":rig.support_latched=false
		if mode=="main_trigger":trackers.right.set_input("trigger",1.)
		if mode=="off_trigger":trackers.left.set_input("trigger",1.)
		if mode=="weapon_family":rig.weapons[0].state.profile["class"]="rifle"
		if mode=="uncertified":rig.weapons[0].state.profile.certified=false;rig.weapons[0].state.certificates=[]
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		if mode=="reload":rig.weapons[0].state.reload_until=10000
		if mode=="low_ammo":rig.weapons[0].state.rounds=2
		sweep();check(live.queue.is_empty(),"Production sweep gate: "+mode)
		rig.weapons[0].state.profile["class"]=profile["class"];rig.weapons[0].state.profile.certified=true;rig.weapons[0].state.certificates=profile.core3.certificationsRequired.duplicate();trackers.left.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for mode:String in ["left","seated","turned","combined"]:
		rig.dominant="left" if mode=="left" else "right";reset()
		if mode=="seated":head.position.y=1.
		if mode=="turned":facing=Basis(Vector3.UP,PI/2);head.basis=facing
		if mode=="combined":session.weapon_state.ability_loadout.ultimate="last_ditch";live.refresh_authority()
		neutral();sweep();check(live.queue.size()==1,"Slot-free sweep remains available: "+mode)
		reset()
		if mode=="seated":head.position.y=1.
		if mode=="turned":facing=Basis(Vector3.UP,PI/2);head.basis=facing
		neutral();brace();check(live.queue.size()==1,"Slot-free brace remains available: "+mode)
		head.position.y=1.7;session.weapon_state.ability_loadout.ultimate="charge_blast"
	reset();var ee3:Dictionary=catalog.weapons.carbine_ee3.duplicate(true);ee3.item_id="99";ee3.certified=true
	ee3.abilities=profile.abilities.duplicate(true);ee3.ability_loadout=profile.ability_loadout.duplicate(true)
	check(rig.weapons[0].state.configure(ee3,ee3.core3.certificationsRequired),"Actual EE-3 burst carbine configures")
	reset();neutral();sweep();check(live.queue.size()==1,"Actual EE-3 recognizes and routes Full Auto Sweep")
	reset();neutral();brace();check(live.queue.size()==1,"Actual EE-3 recognizes and routes Tactical Brace")
	rig.carbineer_context.tactical_brace["active"]=true;rig.update_visuals();check(rig.weapons[0].visual.find_children("*","Label3D",true,false).is_empty(),"EE-3 held display hides Tactical Brace text")
	check(is_equal_approx(preload("res://combat/movement_spread.gd").maximum(ee3),1.2),"EE-3 retains carbine movement spread cap")
	rig.weapons[0].state.configure(profile,profile.core3.certificationsRequired)
	reset();neutral();move_to(16);check(rig.carbineer_input_captured,"Gesture captures competing combat input during sweep")
	rig.sample_brawler_gestures(.02,true);rig.sample_overhead_warcry(.02,true);rig.sample_chest_taunt(.02,true)
	check(not rig.brawler_input_captured and not rig.warcry_input_captured and not rig.taunt_input_captured,"Carbine gesture arbitrates other combat gestures")
	reset();var ui:Node3D=rig.target_abilities;var gun:=Vector3(.2,1.25,-.3);ui.toggle(pose(gun,actor.global_position+Vector3.UP))
	check(ui.points.size()==4 and ui.points.any(func(p):return p.ability.id=="crippling_shot") and ui.points.any(func(p):return p.ability.id=="charge_shot"),"Four VATS slots expose knee, head, weapon arm and pelvis")
	check(rig.circle_entries(rig.active_profile()).is_empty(),"Native attacks and gestures do not leak into selection circle")
	var separated:=true
	for a in range(ui.points.size()):
		for b in range(a+1,ui.points.size()):
			if ui.points[a].position.distance_to(ui.points[b].position)<float(ui.points[a].radius)+float(ui.points[b].radius):separated=false
	check(separated,"Carbine VATS markers do not overlap")
	for id:String in ["crippling_shot","wild_shot","suppression_fire","charge_shot"]:
		reset();ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
		var point:Dictionary=ui.points.filter(func(p):return p.ability.id==id)[0]
		var special:Dictionary=ui.attack(pose(gun,point.position));var state=rig.weapons[0].state
		state.reserve_rounds(1);var shot:Dictionary=state.ranged_snapshot(true,"standing");shot.merge(special)
		check(rig.dispatch_shot(shot,pose(gun,point.position),gun,state.profile,false),"VATS routes "+id)
		check(live.queue.back().payload.ability_id==id and live.queue.back().payload.target_id=="201" and state.rounds==int(profile.capacity)-1,"Targeted special uses native fire: "+id)
		app.reject=true;await live.pump();check(state.rounds==int(profile.capacity),"Rejected targeted special restores one round: "+id)
		reset();state.reserve_rounds(1);shot=state.ranged_snapshot(true,"standing");shot.merge(special)
		rig.dispatch_shot(shot,pose(gun,point.position),gun,state.profile,false);await live.pump()
		var pending_id:String=live.shots.keys()[0];live.rejected_fire(pending_id)
		check(state.rounds==int(profile.capacity)-1,"A failed impact cannot refund accepted "+id)
	reset();sync.entities.actors.clear();actor.collision_layer=0;await physics_frame
	start_blast()
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="charge_blast" and not live.queue[0].payload.has("target_id"),"Supported both-trigger chord starts target-free Charge Blast with no actors")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-3,"Cone ultimate reserves exactly three rounds")
	await live.pump();check(live.shots.is_empty() and rig.abilities.cooldowns.charge_blast==120,"Ultimate receipt commits its cooldown once")
	for i in range(30):rig.sample(.02,Transform3D(Basis.IDENTITY,gun),Transform3D(Basis.IDENTITY,gun+Vector3(0,0,-.25)),1,1,1,true,true,false,1)
	check(live.queue.is_empty(),"Held chord cannot repeat ultimate or discharge ordinary shots")
	reset();rig.weapons[0].state.rounds=2;start_blast();check(live.queue.is_empty() and rig.weapons[0].state.rounds==2,"Insufficient ultimate ammunition fails without ordinary fallback")
	reset();session.weapon_state.ability_loadout.ultimate="last_ditch";live.refresh_authority();start_blast();check(not live.queue.any(func(row):return row.payload.get("ability_id","")=="charge_blast"),"Combined profession's selected ultimate retains chord ownership")
	reset();session.weapon_state.ability_loadout.ultimate="charge_blast";live.refresh_authority();start_blast();app.reject=true;await live.pump();check(rig.weapons[0].state.rounds==int(profile.capacity) and rig.abilities.cooldowns.charge_blast==0,"Rejected ultimate restores exact reservation")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","native_transport":"mocked","production_gameplay_queue":true,"renderer":"dummy","live_xr":false}
	world.free()
	for tracker in trackers.values():XRServer.remove_tracker(tracker)
	FileAccess.open("res://../runtime/evidence/carbineer-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
