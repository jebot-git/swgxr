extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="bountyhunter"
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
		return {"mutation":{"success":not reject,"shot_id":payload.shot_id,"ability_id":payload.get("ability_id",""),"interval_seconds":0.0 if payload.get("ability_id","")=="underhand_shot" and path.ends_with("bountyhunter") else .25,"damage":90,"armed":path.ends_with("bountyhunter") and payload.get("ability_id","")=="underhand_shot","armed_remaining_seconds":1.5}}
class Session extends Node:
	var live:=true
	var busy:=false
	var character_id:="1"
	var session_id:="bountyhunter-session"
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
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"bountyhunter-session"}
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
var catalog:Dictionary
var profile:Dictionary
var context:Dictionary={}
var trackers:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(40).timeout.connect(func():quit(2));call_deferred("run")
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func ability(id:String)->Dictionary:
	return {"id":id,"label":"Torso Shot" if id=="bleeding_shot" else id,"activation":"bountyhunter_gesture" if id in ["duelist_stance","underhand_shot"] else "native_ranged","category":"gesture" if id in ["duelist_stance","underhand_shot"] else "attack","ultimate":id=="fast_blast","sac_policy":"fixed","base_sac":{"health":0,"action":50,"mind":20},"cooldown_seconds":120 if id=="fast_blast" else 18,"max_range_m":64.,"conditions_met":true,"interval_seconds":1.,"anatomical_part":"abdomen" if id=="bleeding_shot" else "","bountyhunter_upgrade":id=="bleeding_shot"}
func equip(key:String)->void:
	profile=catalog.weapons[key].duplicate(true);profile.item_id="99";profile.certified=true
	profile.abilities=[]
	for id:String in ["eye_shot","bleeding_shot","confusion_shot","underhand_shot","duelist_stance","fast_blast","warning_shot","suppression_fire"]:profile.abilities.append(ability(id))
	profile.ability_loadout={"slots":["eye_shot","bleeding_shot","warning_shot","suppression_fire"],"ultimate":"fast_blast"}
	if key.begins_with("carbine"):profile.ability_loadout.slots=["confusion_shot","controlled_burst","warning_shot","suppression_fire"]
	if rig.selected>=0:rig.stow()
	check(rig.weapons[0].state.configure(profile,profile.core3.certificationsRequired),"Native-certified profile configures "+key)
	session.weapon_state={"kind":"ranged","item_id":"99","certified":true,"abilities":profile.abilities,"ability_loadout":profile.ability_loadout.duplicate(true),"fire_interval_seconds":1.,"special_interval_seconds":1.,"max_range_m":float(profile.core3.maxRange),"projectile_speed":160.,"delivery":profile.get("delivery","bolt")}
	live.refresh_authority();rig.draw(0)
func reset()->void:
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;app.reject=false;app.delay=0;rig.abilities.cooldowns.clear();rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable();rig.offhand_occupied=false;rig.support_latched=true;rig.two_hands=true;rig.clear_bountyhunter();rig.bountyhunter_gestures.refractory=0.;rig.target_abilities.reset();rig.rounds_sim.clear()
	if rig.selected<0:rig.draw(0)
	var state=rig.weapons[0].state;state.rounds=int(state.profile.capacity);state.reload_until=-1;state.next_shot=0;state.block()
	session.player_state={"ham":[3000,1000,1000],"bountyhunter":context.duplicate(true)};session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority();rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]})
func tracking_frame(main_pose:Transform3D,off_position:Vector3,off_grip:float,trigger:=0.,head_tracked:=true)->void:
	var primary:XRController3D=origin.get_node(rig.dominant.capitalize()+"Hand")
	var side:="left" if rig.dominant=="right" else "right"
	var support:XRController3D=origin.get_node(side.capitalize()+"Hand")
	primary.global_transform=main_pose;support.global_position=off_position
	trackers[rig.dominant].set_pose("aim",Transform3D(main_pose.basis,Vector3.ZERO),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	trackers[rig.dominant].set_input("grip",1.);trackers[rig.dominant].set_input("trigger",trigger);trackers[side].set_input("grip",off_grip);trackers[side].set_input("trigger",0.)
	rig.sample_bountyhunter_gestures(.02,head_tracked)
	rig.sample_pistoleer_gestures(.02,head_tracked);rig.sample_carbineer_gestures(.02,head_tracked);rig.sample_brawler_gestures(.02,head_tracked);rig.sample_chest_taunt(.02,head_tracked)
	rig.sample(.02,rig.controller_weapon_pose(primary),support.global_transform,1.,off_grip,trigger,head_tracked,true,false,0.)
func tracked_taps(grip:=0.,tracked:=true)->void:
	rig.support_latched=false;rig.two_hands=false
	var gun:=head.global_position+Vector3(.12 if rig.dominant=="right" else -.12,-.4,-.35)
	var aim:=pose(gun,actor.global_position+Vector3.UP)
	var current:=-.43
	tracking_frame(aim,head.global_position+Vector3(0,-.37,current),grip,0.,tracked)
	for z:float in [-.19,-.43,-.19]:
		var start:=current
		for i in range(1,9):current=lerpf(start,z,i/8.);tracking_frame(aim,head.global_position+Vector3(0,-.37,current),grip,0.,tracked)
func tracked_arc()->void:
	rig.support_latched=true;rig.two_hands=true
	var gun:=Transform3D(Basis(Vector3.RIGHT,-.4),head.global_position+Vector3(.12,-.75,-.35))
	for i in range(15):tracking_frame(gun,gun*Vector3(0,-.015,-.25),1.)
	for i in range(1,13):gun.basis=Basis(Vector3.RIGHT,lerpf(-.4,.5,i/12.));gun.origin.y=head.global_position.y+lerpf(-.75,-.52,i/12.);tracking_frame(gun,gun*Vector3(0,-.015,-.25),1.)
	for i in range(1,13):gun.basis=Basis(Vector3.RIGHT,lerpf(.5,0.,i/12.));tracking_frame(gun,gun*Vector3(0,-.015,-.25),1.)
func run()->void:
	var world:=Node3D.new();root.add_child(world);origin=XROrigin3D.new();world.add_child(origin);head=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",1.);tracker.set_input("trigger",0.);XRServer.add_tracker(tracker);trackers[side]=tracker
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=tracker.name;controller.pose="grip";origin.add_child(controller)
	var body:=CharacterBody3D.new();world.add_child(body)
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	profile=catalog.weapons.pistol_scatter.duplicate(true);profile.item_id="99";profile.certified=true
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production BH rig configures original scatter asset");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true)
	app=Host.new();world.add_child(app);app.player=body;app.stage=world;session=Session.new();world.add_child(session)
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	for id:String in ["duelist_stance","underhand_shot"]:context[id]={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":60 if id=="duelist_stance" else 24,"action_cost":60,"mind_cost":30}
	equip("pistol_scatter");reset();await physics_frame;await physics_frame
	var gun:=Vector3(.12,1.2,-.3);var aim:=pose(gun,actor.global_position+Vector3.UP)
	check(live.register_bountyhunter("duelist_stance",aim,"right"),"Duelist binds directly aimed visible opponent")
	check(live.queue[0].payload.target_id=="201" and live.queue[0].kind=="bountyhunter" and not live.queue[0].payload.has("damage"),"Duelist sends target-bound native intent")
	await live.pump();check(rig.abilities.cooldowns.duelist_stance==60 and live.shots.is_empty(),"Duelist accepted once without projectile/ammunition")
	reset();check(not live.register_bountyhunter("duelist_stance",Transform3D(Basis.IDENTITY,Vector3(9,1,0)),"right"),"Duelist requires visible target under physical aim")
	for mode:String in ["unlearned","cooldown","active","uncertified","reload","item","ham"]:
		reset()
		if mode=="unlearned":live.player_state.bountyhunter.duelist_stance.learned=false
		if mode=="cooldown":live.player_state.bountyhunter.duelist_stance.cooldown_remaining_seconds=5
		if mode=="active":live.player_state.bountyhunter.duelist_stance.active=true
		if mode=="uncertified":rig.weapons[0].state.profile.certified=false;rig.weapons[0].state.certificates=[]
		if mode=="reload":rig.weapons[0].state.reload_until=10000
		if mode=="item":rig.weapons[0].state.profile.item_id="100"
		if mode=="ham":live.player_state.ham=[100,1,1]
		check(not live.register_bountyhunter("duelist_stance",aim,"right"),"Native intent gate "+mode)
		rig.weapons[0].state.profile.item_id="99";rig.weapons[0].state.profile.certified=true;rig.weapons[0].state.certificates=profile.core3.certificationsRequired.duplicate()
	reset();live.register_bountyhunter("duelist_stance",aim,"right");app.reject=true;await live.pump();check(rig.abilities.cooldowns.duelist_stance==0,"Rejected Duelist restores authoritative cooldown")
	reset();var ui:Node3D=rig.target_abilities;ui.toggle(aim)
	check(ui.points.size()==4 and ui.points.any(func(p):return p.ability.id=="eye_shot") and ui.widgets.bleeding_shot.get_node("Label").text=="Torso Shot" and ui.widgets.bleeding_shot.get_meta("part")=="abdomen","Pistol exposes Eye and one native-ranked Torso VATS slot")
	check(rig.circle_entries(rig.active_profile()).is_empty(),"Native BH VATS/gestures stay outside selection circle")
	for id:String in ["eye_shot","bleeding_shot","fast_blast"]:
		reset();var shot:Dictionary=rig.weapons[0].state.ranged_snapshot(true,"standing");shot.merge({"ability_id":id,"target_id":"201","item_id":"99","local_ammo_spent":1});rig.weapons[0].state.reserve_rounds(1)
		var out:Dictionary=live.register_shot(shot,aim,gun)
		check(not out.is_empty() and out.get("delivery","")=="scatter" and live.queue.back().payload.ability_id==id,"Target-bound physical scatter launch "+id)
		app.reject=true;await live.pump();check(rig.weapons[0].state.rounds==int(profile.capacity),"Rejected BH discharge restores local round "+id)
	equip("carbine_dh17");reset();ui.toggle(aim);check(ui.points.any(func(p):return p.ability.id=="confusion_shot"),"Carbine Confusion anatomical VATS available")
	check(live.register_bountyhunter("underhand_shot",aim,"right"),"Underhand native arming intent accepted")
	check(not live.queue[0].payload.has("target_id") and live.queue[0].payload.two_hands,"Underhand arm is targetless and supported")
	await live.pump();check(rig.bountyhunter_armed_until>Time.get_ticks_usec() and rig.bountyhunter_arm_item=="99" and rig.abilities.cooldowns.get("underhand_shot",0)==0,"Arm receipt grants bounded window without premature cost/cooldown")
	live.next_launch_usec=0
	var state=rig.weapons[0].state;var shot:Dictionary=state.ranged_snapshot(true,"standing");shot.merge({"ability_id":"underhand_shot","item_id":"99","local_ammo_spent":1});state.reserve_rounds(1)
	check(not live.register_shot(shot,aim,gun).is_empty() and not live.queue.back().payload.has("target_id"),"Underhand follows ordinary targetless physical fire route")
	rig.stow();check(rig.bountyhunter_armed_until==0,"Stowing cancels armed Underhand")
	rig.draw(0);rig.bountyhunter_feedback({"ability_id":"underhand_shot","armed":true,"armed_remaining_seconds":1.5});session.session_id="new-session";live.refresh_authority();check(rig.bountyhunter_armed_until==0,"Reconnect does not recreate stale gesture arm")
	reset();rig.bountyhunter_feedback({"ability_id":"underhand_shot","armed":true});rig.interaction_blocker=func():return true;rig.sample_bountyhunter_gestures(.02,true);check(rig.bountyhunter_armed_until==0,"Inventory occupation cancels armed Underhand")
	equip("rifle_lightning");reset();var discharge:Dictionary=state.ranged_snapshot(true,"standing");discharge.merge({"item_id":"99"});var guided:Dictionary=live.register_shot(discharge,aim,gun)
	check(guided.get("guided_target_id","")=="201" and live.queue.back().payload.guided_target_id=="201" and guided.delivery=="guided_bolt","Lightning locks one visible nearby aim target")
	reset();var away:=pose(gun,actor.global_position+Vector3(3,1,0));guided=live.register_shot(discharge,away,gun);check(not guided.has("guided_target_id"),"Lightning outside five-degree cone receives no guidance")
	equip("pistol_scatter")
	for side:String in ["left","right"]:
		rig.dominant=side;reset();tracked_taps();check(live.queue.size()==1 and live.queue[0].kind=="bountyhunter" and live.queue[0].payload.ability_id=="duelist_stance","Tracked open palm chest taps route once "+side)
	rig.dominant="right"
	for mode:String in ["clenched","head_tracking","menu","inventory","occupied"]:
		reset()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="inventory":rig.interaction_blocker=func():return true
		if mode=="occupied":rig.offhand_occupied=true
		tracked_taps(1. if mode=="clenched" else 0.,mode!="head_tracking")
		check(not live.queue.any(func(row):return row.kind=="bountyhunter"),"Tracked Duelist gate "+mode)
	reset();rig.configure_taunt({"learned":true,"cooldown_remaining_seconds":0},func(_pose,_hand):return true)
	rig.configure_pistoleer({"fan_shot":{"learned":true,"conditions_met":true}},func(_id,_pose,_hand):return true,"99")
	tracked_taps();check(live.queue.size()==1 and not rig.taunt_input_captured and not rig.pistoleer_input_captured,"Mixed open-palm gesture cannot also Taunt or Fan")
	reset();head.position.y=1.;tracked_taps();check(live.queue.size()==1,"Seated open-palm gesture remains head-relative");head.position.y=1.7
	equip("carbine_dh17");reset();tracked_arc();check(live.queue.size()==1 and live.queue[0].kind=="bountyhunter" and live.queue[0].payload.ability_id=="underhand_shot","Tracked lowcarbine arc arms through production queue")
	if not live.queue.is_empty():
		await live.pump();check(rig.bountyhunter_armed_until>Time.get_ticks_usec(),"Tracked Underhand arm waits for accepted native receipt")
		live.next_launch_usec=0;var gun_pose:=pose(Vector3(.12,1.2,-.35),actor.global_position+Vector3.UP)
		tracking_frame(gun_pose,gun_pose*Vector3(0,-.015,-.25),1.,0.)
		for i in range(12):tracking_frame(gun_pose,gun_pose*Vector3(0,-.015,-.25),1.,1.)
		check(live.queue.size()==1 and live.queue[0].kind=="fire" and live.queue[0].payload.ability_id=="underhand_shot" and rig.bountyhunter_armed_until==0,"Deliberate trigger consumes one armed physical Underhand discharge")
	reset();tracked_arc();rig.clear_bountyhunter();await live.pump();check(rig.bountyhunter_armed_until==0,"Canceled pending arm cannot reappear from delayed acknowledgment")
	var report:={"checks":checks,"errors":errors,"native_transport":"mocked","production_gameplay_queue":true,"renderer":"dummy","tracking":"mocked","live_xr":false}
	print(JSON.stringify(report));var f:=FileAccess.open("res://../runtime/evidence/bounty/combat-routing.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));world.free();for tracker:XRControllerTracker in trackers.values():XRServer.remove_tracker(tracker)
	quit(0 if errors.is_empty() else 1)
