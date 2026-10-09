extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="pistoleer"
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
	var session_id:="pistoleer-session"
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
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":1000,"boss":false,"level":50,"melee_control_available":true}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"pistoleer-session"}
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
var last_main:=Vector3(.25,-.4,-.35)
var last_off:=Vector3(-.3,-.4,-.35)
var last_basis:=Basis.IDENTITY
var facing:=Basis.IDENTITY
var head_tracked:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func gesture_frame(p:Vector3,off:Vector3,basis:=Basis.IDENTITY)->void:
	last_main=p;last_off=off;last_basis=basis
	var mirror:=1. if rig.dominant=="right" else -1.;p.x*=mirror;off.x*=mirror
	var main:XRController3D=origin.get_node(rig.dominant.capitalize()+"Hand")
	var support:XRController3D=origin.get_node("LeftHand" if rig.dominant=="right" else "RightHand")
	main.global_transform=Transform3D(facing*basis,head.global_position+facing*p)
	support.global_position=head.global_position+facing*off
	trackers[rig.dominant].set_pose("aim",Transform3D(facing*basis,Vector3.ZERO),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	rig.sample_pistoleer_gestures(.02,head_tracked)
func move_to(p:Vector3,off:Vector3,basis:=Basis.IDENTITY)->void:
	var a:=last_main;var b:=last_off;var c:=last_basis
	for i in range(1,9):gesture_frame(a.lerp(p,i/8.),b.lerp(off,i/8.),c.slerp(basis,i/8.))
func neutral()->void:
	move_to(Vector3(.25,-.4,-.35),Vector3(-.3,-.4,-.35))
	for i in range(12):gesture_frame(last_main,last_off)
func fan()->void:
	var p:=Vector3(.25,-.4,-.35)
	move_to(p,p+Vector3(0,.25,.08))
	for y:float in [.25,.21,.17,.13,.09,.13,.17,.21,.25,.21,.17,.13,.09]:gesture_frame(p,p+Vector3(0,y,.08))
func bond()->void:
	move_to(Vector3(.25,-.65,-.25),Vector3(-.6,-.2,0))
	for i in range(45):gesture_frame(last_main,last_off)
func gangster()->void:
	move_to(Vector3(.25,-.2,-.4),Vector3(-.35,-.5,-.3),Basis(Vector3.FORWARD,PI/2))
	for i in range(45):gesture_frame(last_main,last_off,last_basis)
func reset()->void:
	live.cancel_showdown();live.queue.clear();live.shots.clear();live.next_launch_usec=0;app.reject=false;app.delay=0
	rig.abilities.cooldowns.clear();rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable();rig.offhand_occupied=false;rig.support_latched=false;rig.two_hands=false;rig.pistoleer_gestures.clear();rig.pistoleer_input_captured=false;rig.support_grip_down=false;rig.main_grip_down=false;rig.target_abilities.reset()
	rig.weapons[0].state.rounds=int(rig.weapons[0].state.profile.capacity);rig.weapons[0].state.reload_until=-1;rig.weapons[0].state.next_shot=0;rig.weapons[0].state.block();rig.rounds_sim.clear()
	session.player_state={"ham":[3000,1000,1000],"pistoleer":context.duplicate(true)};session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority()
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]});head_tracked=true;facing=Basis.IDENTITY;head.basis=facing
	for side:String in trackers:trackers[side].set_input("trigger",0.);trackers[side].set_input("grip",1. if side==rig.dominant else 0.)
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func start_showdown()->void:
	reset()
	var gun:=Vector3(.2,1.25,-.3)
	var aim:=pose(gun,actor.global_position+Vector3.UP)
	rig.weapons[0].visual.global_transform=aim
	rig.sample(.02,aim,Transform3D(Basis.IDENTITY,gun+Vector3(.04,0,0)),1,1,0,true,true,false,0)
	rig.sample(.02,aim,Transform3D(Basis.IDENTITY,gun+Vector3(.04,0,0)),1,1,1,true,true,false,1)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	origin=XROrigin3D.new();world.add_child(origin);head=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",1. if side=="right" else 0.);tracker.set_input("trigger",0.);XRServer.add_tracker(tracker);trackers[side]=tracker
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=tracker.name;controller.pose="grip";origin.add_child(controller)
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
	profile.ability_loadout={"family":"pistols","slots":["double_tap","disarming_shot","bleeding_shot","warning_shot"],"ultimate":"showdown"}
	for id:String in ["double_tap","disarming_shot","bleeding_shot","warning_shot","showdown"]:
		profile.abilities.append({"id":id,"label":id,"activation":"native_ranged","ultimate":id=="showdown","sac_policy":"fixed","base_sac":{"health":0,"action":150 if id=="showdown" else 75,"mind":75 if id=="showdown" else 20},"cooldown_seconds":120 if id=="showdown" else 18,"max_range_m":float(profile.core3.maxRange),"conditions_met":true,"ammo_cost":2 if id=="double_tap" else 1,"interval_seconds":1.})
	for id:String in ["fan_shot","run_and_gun"]:
		context[id]={"learned":true,"conditions_met":true,"cooldown_seconds":16 if id=="fan_shot" else 60,"cooldown_remaining_seconds":0,"action_cost":80,"mind_cost":25 if id=="fan_shot" else 40,"interval_seconds":1.}
		profile.abilities.append({"id":id,"label":id,"category":"gesture","activation":"pistoleer_gesture"})
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production pistol rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0)
	app=Host.new();world.add_child(app);app.player=body;app.stage=world
	session=Session.new();world.add_child(session);session.weapon_state={"kind":"ranged","item_id":"99","certified":true,"abilities":profile.abilities,"ability_loadout":profile.ability_loadout.duplicate(true),"fire_interval_seconds":.8,"special_interval_seconds":1.,"max_range_m":float(profile.core3.maxRange),"projectile_speed":100.}
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	await physics_frame;await physics_frame
	reset();neutral();fan()
	check(live.queue.size()==1 and live.queue[0].kind=="pistoleer" and live.queue[0].payload.ability_id=="fan_shot","Tracked cock fanning queues one native Fan Shot")
	if live.queue.is_empty():world.free();quit(1);return
	check(not live.queue[0].payload.has("target_id") and not live.queue[0].payload.has("damage"),"Native server owns cone targets and damage")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-3,"One Fan volley reserves three rounds")
	check(rig.weapons[0].state.next_shot-rig.weapons[0].state.clock>=1.,"Gesture recovery reserves ordinary weapon cadence before ammo prediction")
	var request:Dictionary=live.queue[0].duplicate(true)
	app.reject=true;await live.pump()
	check(live.shots.is_empty() and rig.weapons[0].state.rounds==int(profile.capacity) and float(rig.abilities.cooldowns.fan_shot)==0,"Gameplay rejection retires gesture and restores ammo/cooldown once")
	live.combat_receipt(request,{"mutation":{"success":false,"shot_id":request.shot_id}});check(rig.weapons[0].state.rounds==int(profile.capacity),"Repeated rejection cannot mint rounds")
	reset();neutral();fan();var presentations:int=rig.rounds_sim.fired_presentations;await live.pump()
	check(live.shots.is_empty() and rig.weapons[0].state.rounds==int(profile.capacity)-3 and float(rig.abilities.cooldowns.fan_shot)>0,"Gameplay acceptance consumes Fan ammo and retains cooldown")
	check(rig.rounds_sim.fired_presentations==presentations+3,"Native Fan receipt displays a three-bolt cosmetic volley")
	for bolt:Dictionary in rig.rounds_sim.bolts:check(bolt.shot.get("cosmetic_only",false),"Fan cosmetics cannot produce contact damage")
	reset();neutral();bond();check(live.queue.size()==1 and live.queue[0].payload.ability_id=="run_and_gun","Bond pose routes shared self-buff")
	await live.pump();check(live.shots.is_empty(),"Gameplay self-buff receipt retires pending intent")
	check(rig.weapons[0].state.next_shot>rig.weapons[0].state.clock,"Confirmed self-buff recovery blocks premature ordinary ammo consumption")
	live.next_launch_usec=0;gangster();check(live.queue.is_empty(),"Alternating held stances cannot refresh shared buff")
	reset();neutral();gangster();check(live.queue.size()==1 and live.queue[0].payload.ability_id=="run_and_gun","Sideways shoulder pose routes the same buff")
	for mode:String in ["menu","tracking","unlearned","cooldown","occupied","support_grip","main_trigger","off_trigger","weapon_family","inventory"]:
		reset();neutral()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="tracking":head_tracked=false
		if mode=="unlearned":rig.pistoleer_context.fan_shot.learned=false
		if mode=="cooldown":rig.pistoleer_context.fan_shot.cooldown_remaining_seconds=10
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="support_grip":trackers.left.set_input("grip",1.)
		if mode=="main_trigger":trackers.right.set_input("trigger",1.)
		if mode=="off_trigger":trackers.left.set_input("trigger",1.)
		if mode=="weapon_family":rig.weapons[0].state.profile["class"]="carbine"
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		fan();check(live.queue.is_empty(),"Production fan gate: "+mode)
		rig.weapons[0].state.profile["class"]=profile["class"]
	for mode:String in ["left","seated","turned","combined"]:
		rig.dominant="left" if mode=="left" else "right";reset()
		if mode=="seated":head.position.y=1.
		if mode=="turned":facing=Basis(Vector3.UP,PI/2);head.basis=facing
		if mode=="combined":session.weapon_state.ability_loadout.ultimate="last_ditch";live.refresh_authority()
		neutral();fan();check(live.queue.size()==1,"Fan remains available: "+mode)
		head.position.y=1.7;session.weapon_state.ability_loadout.ultimate="showdown"
	reset();var ui:Node3D=rig.target_abilities;var gun:=Vector3(.2,1.25,-.3);ui.toggle(pose(gun,actor.global_position+Vector3.UP))
	check(ui.points.size()==4 and ui.points.any(func(p):return p.ability.id=="double_tap") and ui.points.any(func(p):return p.ability.id=="disarming_shot"),"Four learned VATS slots expose chest/arm/abdomen/feet")
	check(rig.circle_entries(rig.active_profile()).is_empty(),"Gestures and native attacks never leak into selection circle")
	var separated:=true
	for a in range(ui.points.size()):
		for b in range(a+1,ui.points.size()):
			if ui.points[a].position.distance_to(ui.points[b].position)<float(ui.points[a].radius)+float(ui.points[b].radius):separated=false
	check(separated,"Pistoleer chest/arm/abdomen/feet markers do not overlap")
	rig.weapons[0].state.rounds=2
	check(not ui.ability_ready(profile.abilities.filter(func(row):return row.id=="showdown")[0],actor),"Showdown requires three rounds before activation")
	for id:String in ["double_tap","disarming_shot"]:
		reset();ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
		var point:Dictionary=ui.points.filter(func(p):return p.ability.id==id)[0]
		var special:Dictionary=ui.attack(pose(gun,point.position));var state=rig.weapons[0].state
		state.reserve_rounds(1);var shot:Dictionary=state.ranged_snapshot(false,"standing");shot.merge(special)
		check(rig.dispatch_shot(shot,pose(gun,point.position),gun,state.profile,false),"VATS routes "+id)
		check(live.queue.back().payload.ability_id==id and rig.weapons[0].state.rounds==int(profile.capacity)-(2 if id=="double_tap" else 1),"Special ammo routing: "+id)
		check(is_equal_approx(state.next_shot-state.clock,1.),"Run and Gun ordinary cadence does not accelerate special: "+id)
		await live.pump();var pending_id:String=live.shots.keys()[0];var ammo:int=state.rounds;live.rejected_fire(pending_id)
		check(state.rounds==ammo,"A failed impact cannot refund an accepted "+id)
	start_showdown()
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="showdown" and live.queue[0].payload.volley_id==live.queue[0].shot_id and live.queue[0].payload.volley_index==0,"Supported two-trigger chord starts the physical Showdown volley")
	if live.queue.is_empty():world.free();quit(1);return
	var first:Dictionary=live.queue[0].duplicate(true);var ammo_before:int=rig.weapons[0].state.rounds
	for i in range(20):rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and rig.weapons[0].state.rounds==ammo_before,"Pending first acknowledgement cannot spend or queue continuation")
	var bystander:=Actor.new();world.add_child(bystander);bystander.record=bystander.record.duplicate(true);bystander.record.id="202";sync.entities.actors["202"]=bystander
	live.contact(live.shots[first.shot_id].shot,bystander.core3_identity(),Vector3.ZERO,Vector3.UP,2)
	check(live.shots.has(first.shot_id) and live.queue.size()==1,"Intervening actor before acknowledgement suppresses contact while preserving launch")
	app.delay=.3;await live.pump();app.delay=0
	check(not live.shots.has(first.shot_id) and live.showdown_status(first.shot_id)=="pending","Missed first bolt still acknowledges cost and waits full post-receipt cadence")
	for i in range(20):rig.step_showdown(.02,true,"standing")
	check(live.queue.is_empty(),"Backlogged acknowledgement cannot compress the next server interval")
	await create_timer(.27).timeout
	rig.two_hands=false;rig.weapons[0].visual.global_basis=Basis(Vector3.UP,.2);rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and live.queue[0].payload.volley_index==1 and live.queue[0].payload.target_id=="201","Second bolt retains one target after support release")
	var second:Dictionary=live.queue[0].duplicate(true)
	check(second.payload.direction!=first.payload.direction,"Second bolt follows fresh physical muzzle direction")
	await live.pump();await create_timer(.27).timeout
	for i in range(14):rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and live.queue[0].payload.volley_index==2 and rig.showdown.is_empty(),"Third independent bolt completes the bounded volley")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-3 and rig.abilities.cooldowns.showdown==120,"Showdown spends exactly three rounds and reserves one ultimate cooldown")
	await live.pump()
	start_showdown();await live.pump();await create_timer(.27).timeout
	for i in range(14):rig.step_showdown(.02,true,"standing")
	check(live.queue.filter(func(row):return row.kind=="fire" and row.payload.get("volley_index",-1)==1).size()==1,"Committed volley schedules second projectile")
	while not live.queue.is_empty() and live.queue[0].kind=="impact":await live.pump()
	app.reject=true;await live.pump()
	check(rig.showdown.is_empty() and rig.abilities.cooldowns.get("showdown",0)==120 and rig.weapons[0].state.rounds==int(profile.capacity)-1,"Rejected continuation preserves first projectile costs and ultimate cooldown")
	for mode:String in ["tracking","menu","dead_target","weapon","loadout","rejection","stale_authority"]:
		actor.record.dead=false;rig.weapons[0].state.profile.item_id="99";session.weapon_state.ability_loadout.ultimate="showdown";start_showdown()
		if mode=="tracking":rig.step_showdown(.02,false,"standing")
		if mode=="menu":rig.ability_ui.menu_open=true;rig.sample(.02,pose(gun,actor.global_position+Vector3.UP),Transform3D.IDENTITY,1,0,0,true,true)
		if mode=="dead_target":actor.record.dead=true;rig.step_showdown(.02,true,"standing")
		if mode=="weapon":rig.weapons[0].state.profile.item_id="100";rig.step_showdown(.02,true,"standing")
		if mode=="loadout":rig.weapons[0].state.profile.ability_loadout.ultimate="last_ditch";rig.step_showdown(.02,true,"standing")
		if mode=="rejection":app.reject=true;await live.pump()
		if mode=="stale_authority":live.fail("test expired authority")
		check(rig.showdown.is_empty(),"Pending Showdown cancels on "+mode)
		if mode!="rejection":check(float(rig.abilities.cooldowns.get("showdown",0))>0,"Cancellation never refunds reserved ultimate cooldown: "+mode)
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","native_transport":"mocked","production_gameplay_queue":true,"renderer":"dummy","live_xr":false}
	world.free()
	for tracker in trackers.values():XRServer.remove_tracker(tracker)
	FileAccess.open("res://../runtime/evidence/pistoleer-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
