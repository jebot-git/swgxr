extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="rifleman"
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
	var session_id:="rifleman-session"
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
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"rifleman-session"}
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
var hand:=Vector3(0,-.015,-.25)
var facing:=Basis.IDENTITY
var head_tracked:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(40).timeout.connect(func():quit(2));call_deferred("run")
func frame(local:Vector3,grip:float)->void:
	hand=local
	var mirror:=1. if rig.dominant=="right" else -1.
	var main:XRController3D=origin.get_node(rig.dominant.capitalize()+"Hand")
	var offhand:="left" if rig.dominant=="right" else "right"
	var support:XRController3D=origin.get_node(offhand.capitalize()+"Hand")
	main.global_transform=Transform3D(facing,head.global_position+facing*Vector3(.12*mirror,-.4,-.25))
	support.global_position=main.global_transform*Vector3(local.x*mirror,local.y,local.z)
	trackers[rig.dominant].set_pose("aim",Transform3D(facing,Vector3.ZERO),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	trackers[offhand].set_input("grip",grip)
	rig.sample_rifleman_gestures(.02,head_tracked)
	rig.sample(.02,rig.controller_weapon_pose(main),support.global_transform,main.get_float("grip"),grip,main.get_float("trigger"),head_tracked,true,false,support.get_float("trigger"))
func move(to:Vector3,grip:float)->void:
	var start:=hand
	for i in range(1,11):frame(start.lerp(to,i/10.),grip)
func neutral()->void:
	frame(Vector3(0,-.015,-.25),0.)
	for i in range(16):frame(Vector3(0,-.015,-.25),1.)
func approach()->void:
	frame(hand,0.);move(Vector3(.09,.06,-.04),0.);frame(hand,1.)
func cycle()->void:
	move(Vector3(.09,.06,.10),1.);move(Vector3(.09,.06,-.04),1.);frame(hand,0.);move(Vector3(0,-.015,-.25),0.);frame(hand,1.);frame(hand,1.)
func bolt()->void:approach();cycle()
func reset()->void:
	live.cancel_showdown();live.queue.clear();live.shots.clear();live.next_launch_usec=0;app.reject=false;app.delay=0
	rig.abilities.cooldowns.clear();rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable();rig.offhand_occupied=false;rig.support_latched=true;rig.two_hands=true;rig.rifleman_gestures.clear();rig.rifleman_input_captured=false;rig.support_grip_down=true;rig.main_grip_down=true;rig.target_abilities.reset()
	rig.weapons[0].state.rounds=int(rig.weapons[0].state.profile.capacity);rig.weapons[0].state.reload_until=-1;rig.weapons[0].state.next_shot=0;rig.weapons[0].state.block();rig.rounds_sim.clear()
	if rig.selected<0:rig.draw(0)
	session.player_state={"ham":[3000,1000,1000],"rifleman":context.duplicate(true)};session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority()
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]});head_tracked=true;facing=Basis.IDENTITY;head.basis=facing
	for side:String in trackers:trackers[side].set_input("trigger",0.);trackers[side].set_input("grip",1.)
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func start_sniper()->void:
	var gun:=Vector3(.12,1.3,-.25)
	var aim:=pose(gun,actor.global_position+Vector3.UP)
	rig.weapons[0].visual.global_transform=aim
	var support:=Transform3D(Basis.IDENTITY,rig.support_point(0))
	rig.sample(.02,aim,support,1,1,0,true,true,false,0)
	rig.sample(.02,aim,support,1,1,1,true,true,false,1)
func start_flurry()->void:
	var ui:Node3D=rig.target_abilities
	ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
	var points:Array=ui.points.filter(func(p):return p.ability.id=="flurry_shot")
	if points.is_empty():return
	var gun:=Vector3(.2,1.25,-.3)
	var aim:=pose(gun,points[0].position)
	rig.weapons[0].visual.global_transform=aim
	# Physical support is placed on the muzzle axis to keep marker aim stable.
	var support:=Transform3D(Basis.IDENTITY,gun-aim.basis.z*.25)
	rig.sample(.02,aim,support,1,1,0,true,true,false,0)
	for i in range(8):rig.sample(.02,aim,support,1,1,1,true,true,false,0)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	origin=XROrigin3D.new();world.add_child(origin);head=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side:String in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand";tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_pose("aim",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",1.);tracker.set_input("trigger",0.);XRServer.add_tracker(tracker);trackers[side]=tracker
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=tracker.name;controller.pose="grip";origin.add_child(controller)
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.rifle_e11.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
	profile.ability_loadout={"family":"rifles","slots":["lethal_shot","piercing_shot","flurry_shot","surprise_shot"],"ultimate":"sniper_shot"}
	for id:String in ["lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot"]:
		profile.abilities.append({"id":id,"label":"Head Shot" if id=="lethal_shot" else id,"rifleman_upgrade":id=="lethal_shot","anatomical_part":"head" if id=="lethal_shot" else "","activation":"native_ranged","ultimate":id=="sniper_shot","sac_policy":"fixed","base_sac":{"health":0,"action":150 if id=="sniper_shot" else 75,"mind":90 if id=="sniper_shot" else 30},"cooldown_seconds":120 if id=="sniper_shot" else 18,"max_range_m":float(profile.core3.maxRange),"conditions_met":true,"ammo_cost":3 if id=="flurry_shot" else 1,"interval_seconds":2.5 if id=="sniper_shot" else 2. if id=="lethal_shot" else .25 if id=="flurry_shot" else 1.})
	context.rifleman_focus={"learned":true,"conditions_met":true,"cooldown_seconds":60,"cooldown_remaining_seconds":0,"action_cost":50,"mind_cost":25,"interval_seconds":.25}
	profile.abilities.append({"id":"rifleman_focus","label":"Rifleman's Focus","category":"gesture","activation":"rifleman_gesture"})
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production rifle rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0)
	app=Host.new();world.add_child(app);app.player=body;app.stage=world
	session=Session.new();world.add_child(session);session.weapon_state={"kind":"ranged","item_id":"99","certified":true,"abilities":profile.abilities,"ability_loadout":profile.ability_loadout.duplicate(true),"fire_interval_seconds":1.,"special_interval_seconds":1.,"max_range_m":float(profile.core3.maxRange),"projectile_speed":100.}
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	await physics_frame;await physics_frame
	reset();neutral();approach();check(rig.rifleman_input_captured and not rig.support_latched,"Receiver grasp captures input while fore-end is released")
	rig.sample_brawler_gestures(.02,true);rig.sample_overhead_warcry(.02,true);rig.sample_chest_taunt(.02,true)
	check(not rig.brawler_input_captured and not rig.warcry_input_captured and not rig.taunt_input_captured,"Bolting arbitrates competing combat gestures")
	cycle();check(live.queue.size()==1 and live.queue[0].kind=="rifleman" and live.queue[0].payload.ability_id=="rifleman_focus","Pull-return-release-fresh-regrip queues Focus")
	if live.queue.is_empty():world.free();quit(1);return
	check(live.queue[0].payload.two_hands and not live.queue[0].payload.has("target_id") and not live.queue[0].payload.has("damage") and not live.queue[0].payload.has("volley_id"),"Focus sends supported target-free intent without client damage")
	check(rig.weapons[0].state.rounds==int(profile.capacity),"Focus uses no ammunition")
	await live.pump();check(app.calls.back().path=="/combat/session/rifleman" and live.shots.is_empty() and rig.abilities.cooldowns.rifleman_focus==60,"Gameplay HTTP commits Focus cooldown once")
	for i in range(60):frame(hand,1.)
	check(live.queue.is_empty(),"Held support cannot refresh Focus")
	reset();neutral();frame(hand,0.);move(Vector3(.09,.06,-.12),0.);frame(hand,1.)
	check(not rig.support_latched and rig.rifleman_gestures.phase=="pull","Receiver squeeze near fore-end cannot latch support early")
	move(Vector3(.09,.06,.02),1.);move(Vector3(.09,.06,-.12),1.);frame(hand,0.);move(Vector3(0,-.015,-.25),0.);frame(hand,1.);frame(hand,1.)
	check(live.queue.size()==1 and rig.support_latched,"Only fresh completed fore-end regrip restores support and fires Focus")
	reset();neutral();bolt();app.reject=true;await live.pump();check(rig.abilities.cooldowns.rifleman_focus==0 and rig.weapons[0].state.rounds==int(profile.capacity),"Rejected Focus restores authoritative cooldown without ammo minting")
	for mode:String in ["menu","head_tracking","off_tracking","unlearned","cooldown","active","occupied","main_grip","main_trigger","off_trigger","weapon_family","uncertified","inventory","reload"]:
		reset();neutral()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="head_tracking":head_tracked=false
		if mode=="off_tracking":trackers.left.invalidate_pose("grip")
		if mode=="unlearned":rig.rifleman_context.rifleman_focus.learned=false
		if mode=="cooldown":rig.rifleman_context.rifleman_focus.cooldown_remaining_seconds=10
		if mode=="active":rig.rifleman_context.rifleman_focus.active=true
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="main_grip":trackers.right.set_input("grip",0.)
		if mode=="main_trigger":trackers.right.set_input("trigger",1.)
		if mode=="off_trigger":trackers.left.set_input("trigger",1.)
		if mode=="weapon_family":rig.weapons[0].state.profile["class"]="carbine"
		if mode=="uncertified":rig.weapons[0].state.profile.certified=false;rig.weapons[0].state.certificates=[]
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		if mode=="reload":rig.weapons[0].state.reload_until=10000
		bolt();check(not live.queue.any(func(row):return row.kind=="rifleman"),"Production Focus gate: "+mode)
		rig.weapons[0].state.profile["class"]=profile["class"];rig.weapons[0].state.profile.certified=true;rig.weapons[0].state.certificates=profile.core3.certificationsRequired.duplicate();trackers.left.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for mode:String in ["left","seated","turned","combined"]:
		rig.dominant="left" if mode=="left" else "right";reset()
		if mode=="seated":head.position.y=1.
		if mode=="turned":facing=Basis(Vector3.UP,PI/2);head.basis=facing
		if mode=="combined":session.weapon_state.ability_loadout.ultimate="last_ditch";session.weapon_state.ability_loadout.slots=["a","b","c","d"];live.refresh_authority()
		neutral();bolt();check(live.queue.size()==1,"Slot-free Focus usable: "+mode)
		head.position.y=1.7;session.weapon_state.ability_loadout=profile.ability_loadout.duplicate(true)
	for source_id:String in ["rifle_cdef","rifle_dlt20a","rifle_t21","rifle_bowcaster","rifle_tusken"]:
		var alternate:Dictionary=catalog.weapons[source_id].duplicate(true);alternate.item_id="99";alternate.certified=true;alternate.abilities=profile.abilities.duplicate(true);alternate.ability_loadout=profile.ability_loadout.duplicate(true)
		check(rig.weapons[0].state.configure(alternate,alternate.core3.certificationsRequired),"Original rifle family configures: "+source_id)
		reset();neutral();bolt();check(live.queue.size()==1,"Original rifle family bolting recognized: "+source_id)
	rig.weapons[0].state.configure(profile,profile.core3.certificationsRequired)
	reset();var ui:Node3D=rig.target_abilities;var gun:=Vector3(.2,1.25,-.3);ui.toggle(pose(gun,actor.global_position+Vector3.UP))
	check(ui.points.size()==4,"Four rifle VATS slots expose head, chest, abdomen and shoulder")
	check(rig.circle_entries(rig.active_profile()).is_empty(),"Native rifle attacks and bolting stay outside selection circle")
	var separated:=true
	for a in range(ui.points.size()):
		for b in range(a+1,ui.points.size()):
			if ui.points[a].position.distance_to(ui.points[b].position)<float(ui.points[a].radius)+float(ui.points[b].radius):separated=false
	check(separated,"Rifle VATS markers do not overlap")
	check(ui.definition({"id":"lethal_shot","label":"Head Shot","rifleman_upgrade":true,"anatomical_part":"head"}).part=="head" and ui.definition({"id":"lethal_shot","label":"Lethal Shot"}).part=="heart","Only upgraded Head Shot changes legacy Lethal anchor")
	check(ui.widgets.lethal_shot.get_meta("part","")=="head" and ui.widgets.lethal_shot.get_node("Label").text=="Head Shot","Head Shot displays the native head icon and name")
	rig.weapons[0].state.profile.abilities[0]["rifleman_upgrade"]=false;ui.refresh()
	check(ui.widgets.lethal_shot.get_meta("part","")=="heart","Shared Lethal widget restores heart icon when rifle upgrade is absent")
	live.refresh_authority()
	for id:String in ["lethal_shot","piercing_shot","surprise_shot"]:
		reset();ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
		var point:Dictionary=ui.points.filter(func(p):return p.ability.id==id)[0]
		var special:Dictionary=ui.attack(pose(gun,point.position));var state=rig.weapons[0].state
		state.reserve_rounds(1);var shot:Dictionary=state.ranged_snapshot(true,"standing");shot.merge(special)
		check(rig.dispatch_shot(shot,pose(gun,point.position),gun,state.profile,false),"VATS routes "+id)
		check(live.queue.back().payload.ability_id==id and live.queue.back().payload.target_id=="201" and state.rounds==int(profile.capacity)-1,"Single projectile native route: "+id)
		if id=="lethal_shot":check(is_equal_approx(state.next_shot-state.clock,2.),"Head Shot preserves doubled native recovery")
		app.reject=true;await live.pump();check(state.rounds==int(profile.capacity),"Rejected launch restores one round: "+id)
	reset();start_flurry();check(live.queue.size()==1 and live.queue[0].payload.get("ability_id","")=="flurry_shot" and live.queue[0].payload.volley_index==0,"VATS trigger starts physical Flurry volley")
	if live.queue.is_empty():world.free();quit(1);return
	var first:Dictionary=live.queue[0].duplicate(true)
	check(first.payload.volley_id==first.shot_id and rig.showdown.get("ability_id","")=="flurry_shot","Flurry uses explicit native volley identity")
	for i in range(20):rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and rig.weapons[0].state.rounds==int(profile.capacity)-1,"Flurry waits for first native receipt before spending second round")
	var bystander:=Actor.new();world.add_child(bystander);bystander.record=bystander.record.duplicate(true);bystander.record.id="202";sync.entities.actors["202"]=bystander
	live.contact(live.shots[first.shot_id].shot,bystander.core3_identity(),Vector3.ZERO,Vector3.UP,2)
	check(live.queue.size()==1 and live.shots[first.shot_id].get("discard_contact",false),"Flurry cannot transfer damage to intervening actor")
	await live.pump();check(live.showdown_status(first.shot_id)=="pending","Accepted Flurry still waits full post-receipt cadence")
	await create_timer(.27).timeout
	rig.weapons[0].visual.global_basis=Basis(Vector3.UP,.2);rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and live.queue[0].payload.volley_index==1 and live.queue[0].payload.target_id=="201" and live.queue[0].payload.direction!=first.payload.direction,"Second Flurry projectile retains target but uses fresh physical muzzle")
	await live.pump();await create_timer(.27).timeout
	for i in range(14):rig.step_showdown(.02,true,"standing")
	check(live.queue.size()==1 and live.queue[0].payload.volley_index==2 and rig.showdown.is_empty(),"Third Flurry projectile completes bounded volley")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-3 and rig.abilities.cooldowns.flurry_shot==18,"Flurry spends three rounds and one cooldown")
	check(is_equal_approx(rig.weapons[0].state.next_shot-rig.weapons[0].state.clock,1.),"Final Flurry discharge restores ordinary native recovery despite .25 start row")
	await live.pump()
	reset();start_flurry();await live.pump();await create_timer(.27).timeout
	for i in range(14):rig.step_showdown(.02,true,"standing")
	app.reject=true;await live.pump();check(rig.showdown.is_empty() and rig.weapons[0].state.rounds==int(profile.capacity)-1 and rig.abilities.cooldowns.flurry_shot==18,"Rejected continuation refunds only uncommitted round and preserves first cost")
	for mode:String in ["tracking","dead_target","weapon","loadout","rejection"]:
		actor.record.dead=false;rig.weapons[0].state.profile.item_id="99";session.weapon_state.ability_loadout=profile.ability_loadout.duplicate(true);reset();start_flurry()
		if mode=="tracking":rig.step_showdown(.02,false,"standing")
		if mode=="dead_target":actor.record.dead=true;rig.step_showdown(.02,true,"standing")
		if mode=="weapon":rig.weapons[0].state.profile.item_id="98";rig.step_showdown(.02,true,"standing")
		if mode=="loadout":session.weapon_state.ability_loadout.slots[2]="controlled_burst";live.refresh_authority();rig.step_showdown(.02,true,"standing")
		if mode=="rejection":app.reject=true;await live.pump()
		check(rig.showdown.is_empty(),"Flurry cancels on "+mode)
	actor.record.dead=false;rig.weapons[0].state.profile.item_id="99";session.weapon_state.ability_loadout=profile.ability_loadout.duplicate(true)
	reset();start_sniper();check(live.queue.size()==1 and live.queue[0].payload.get("ability_id","")=="sniper_shot" and live.queue[0].payload.two_hands and live.queue[0].payload.target_id=="201","Supported both-trigger chord routes targeted Sniper Shot")
	check(rig.weapons[0].state.rounds==int(profile.capacity)-1 and rig.showdown.is_empty(),"Sniper launches one physical projectile")
	check(rig.weapons[0].state.next_shot-rig.weapons[0].state.clock>=2.5,"Sniper reserves minimum 2.5-second recovery")
	app.reject=true;await live.pump();check(rig.weapons[0].state.rounds==int(profile.capacity) and rig.abilities.cooldowns.sniper_shot==0,"Rejected Sniper restores one round and native cooldown")
	reset();rig.two_hands=false;check(not ui.ability_ready(profile.abilities.filter(func(a):return a.id=="sniper_shot")[0],actor),"Unsupported Sniper cannot be selected")
	reset();actor.record.boss=true;check(ui.ability_ready(profile.abilities.filter(func(a):return a.id=="sniper_shot")[0],actor),"Eligible bosses remain valid Sniper targets")
	rig.rifleman_context.rifleman_focus.active=true;rig.update_visuals();check("Rifleman’s Focus" in rig.weapons[0].label.text,"Rifle readout exposes native Focus state")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","native_transport":"mocked","production_gameplay_queue":true,"renderer":"dummy","live_xr":false}
	world.free()
	for tracker in trackers.values():XRServer.remove_tracker(tracker)
	FileAccess.open("res://../runtime/evidence/rifleman-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
