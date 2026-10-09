extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Live=preload("res://combat/live_world.gd")
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":29,"max_health":100,"effective_max_health":100,"boss":false,"level":90,"melee_control_available":true,"fractured_armour":false}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"sword-session"}
	func visual_bounds()->AABB:return AABB(Vector3(-.3,0,-.2),Vector3(.6,1.8,.4))
var checks:=0
var errors:Array=[]
var rig:Node3D
var live:Node3D
var head:Camera3D
var trackers:Array=[]
var main:XRController3D
var support:XRController3D
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func pose(y:float,head_tracked:=true)->void:
	main.position=Vector3(.15,1.7+y,-.3)
	rig.weapons[0].visual.global_transform=main.global_transform
	support.global_position=rig.support_point(0)
	rig.two_hands=true
	rig.sample_swordsman_gestures(.02,head_tracked)
func ready()->void:
	for i in range(12):pose(-.3)
func overhead()->void:
	ready()
	for i in range(10):pose(-.3+i*.075)
	for i in range(14):pose(.375-i*.065)
func reset_inputs()->void:
	rig.swordsman_gestures.clear();rig.swordsman_input_captured=false;rig.warcry_input_captured=false;rig.abilities.cooldowns.clear();live.queue.clear();live.shots.clear();live.next_launch_usec=0
	for t in trackers:t.set_input("trigger",0.)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var origin:=XROrigin3D.new();world.add_child(origin)
	head=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	for side:String in ["left","right"]:
		var t:=XRControllerTracker.new();t.type=XRServer.TRACKER_CONTROLLER;t.name=side+"_hand";t.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);t.set_input("grip",1.);t.set_input("trigger",0.);XRServer.add_tracker(t);trackers.append(t)
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=t.name;controller.pose="grip";origin.add_child(controller)
	main=origin.get_node("RightHand");support=origin.get_node("LeftHand")
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.axe_vibroaxe.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
	profile.ability_loadout={"slots":["rending_cut","disrupting_blow","hamstring","decisive_strike"],"ultimate":"armour_break"}
	for id:String in ["rending_cut","disrupting_blow","hamstring","decisive_strike","armour_break"]:
		var row:Dictionary={"id":id,"label":id,"activation":"native_melee","base_sac":{"health":0,"action":60,"mind":25},"sac_policy":"fixed","max_range_m":4,"cooldown_seconds":20,"interval_seconds":2,"conditions_met":true,"requires_control_available":id in ["disrupting_blow","hamstring"],"ultimate":id=="armour_break"}
		if id=="decisive_strike":row.merge({"excludes_bosses":true,"target_health_below":.3})
		profile.abilities.append(row)
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production two-handed rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0);rig.weapons[0].state.ability_state=null
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]})
	live=Live.new();world.add_child(live);live.set_process(false);live.rig=rig;live.app=Host.new();world.add_child(live.app);live.live=true;live.native_ready=true;live.session_id="sword-session";live.owner_account="sword";live.owner_character="1"
	live.weapon={"kind":"melee","item_id":"99","certified":true,"unarmed":false,"abilities":profile.abilities,"fire_interval_seconds":2,"ability_loadout":profile.ability_loadout.duplicate(true)}
	var context:Dictionary={}
	for id:String in ["overhead_cleave","ground_slam","armour_break"]:context[id]={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":10,"action_cost":100,"mind_cost":40,"interval_seconds":2}
	live.player_state={"ham":[3000,1000,1000],"swordsman":context.duplicate(true)}
	rig.configure_swordsman(context,live.register_swordsman,"99","armour_break");rig.shot_authority=live.register_shot
	var actor:=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-2.5);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape)
	live.actors["201"]=actor
	head.look_at(actor.global_position+Vector3.UP)
	await physics_frame;await physics_frame
	overhead()
	check(live.queue.size()==1 and live.queue[0].kind=="swordsman" and live.queue[0].payload.ability_id=="overhead_cleave","Production overhead queues native ability")
	if live.queue.is_empty():world.free();quit(1);return
	check(not live.queue[0].payload.has("target_id") and not live.queue[0].payload.has("damage"),"Gesture target and damage stay server-owned")
	check(rig.swordsman_input_captured and rig.physical_guard.current.mode=="none","Completed strike captures ordinary swings and guard")
	check(not live.register_swordsman("overhead_cleave",head.global_transform,"right"),"Shared cadence blocks duplicate")
	live.next_launch_usec=0
	check(not live.register_swordsman("overhead_cleave",head.global_transform,"right"),"Predicted cooldown blocks stale-context repeat")
	live.rejected_fire(str(live.queue[0].shot_id))
	check(float(rig.abilities.cooldowns.get("overhead_cleave",-1))==0,"Native gesture rejection clears only predicted cooldown")
	for mode:String in ["menu","tracking","occupied","cooldown","not_learned","inventory"]:
		reset_inputs();rig.swordsman_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.offhand_occupied=false;rig.interaction_blocker=Callable()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="cooldown":rig.swordsman_context.overhead_cleave.cooldown_remaining_seconds=5
		if mode=="not_learned":
			for row:Dictionary in rig.swordsman_context.values():row.learned=false
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		if mode=="tracking":
			for i in range(12):pose(-.3,false)
			for i in range(10):pose(-.3+i*.075,false)
			for i in range(14):pose(.375-i*.065,false)
		else:overhead()
		check(live.queue.is_empty(),"Production gesture gate: "+mode)
	reset_inputs();rig.swordsman_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.offhand_occupied=false;rig.interaction_blocker=Callable()
	ready();for i in range(12):pose(-.3-i*.055)
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="ground_slam","Production low-start slam routes once")
	reset_inputs();pose(-.3)
	trackers[0].set_input("trigger",1.);trackers[1].set_input("trigger",1.);pose(-.3)
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="armour_break" and live.queue[0].payload.target_id=="201","Two-trigger melee ultimate binds aimed actor")
	for i in range(20):pose(-.3)
	check(live.queue.size()==1,"Held ultimate cannot repeat")
	reset_inputs();actor.record.fractured_armour=true;pose(-.3);trackers[0].set_input("trigger",1.);trackers[1].set_input("trigger",1.);pose(-.3)
	check(live.queue.is_empty(),"Existing fracture prevents ultimate refresh");actor.record.fractured_armour=false
	reset_inputs();var ui:Node3D=rig.target_abilities;ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
	check(ui.points.size()==4,"Four equipped Swordsman body markers")
	actor.record.health=30;ui.refresh();check(ui.points.size()==3,"Exact 30 percent hides execution marker")
	actor.record.health=29;actor.record.boss=true;ui.refresh();check(ui.points.size()==3,"Low-level tagged boss hides execution")
	actor.record.boss=false;actor.record.level=151;ui.refresh();check(ui.points.size()==3,"Boss combat-level band hides execution")
	actor.record.level=150;ui.refresh();check(ui.points.size()==4,"High-level nonboss retains weaker execution")
	actor.record.melee_control_available=false;ui.refresh();check(ui.points.size()==2,"Control immunity hides only disrupt and hamstring")
	actor.record.melee_control_available=true;ui.refresh()
	var point:Vector3=ui.points.filter(func(p):return p.ability.id=="rending_cut")[0].position
	var start:=Vector3(.2,1.2,-.15);var direction:Vector3=(point-start).normalized()
	var hand_pose:=Transform3D(Basis(Vector3.UP,PI/2),start)
	rig.sample(.02,hand_pose,hand_pose,1,0,0,true,true)
	for i in range(12):hand_pose.origin=start+direction*.07*i;rig.sample(.02,hand_pose,hand_pose,1,0,1,true,true)
	check(live.queue.size()==1 and live.queue[0].kind=="swordsman" and live.queue[0].payload.ability_id=="rending_cut" and live.queue[0].payload.target_id=="201","Physical punch to marker routes through production native authority")
	reset_inputs();live.weapon.ability_loadout.slots=["","","",""]
	check(live.register_melee({"item_id":"99","ability_id":"rending_cut","target_id":"201"},head.global_transform).is_empty(),"Direct routing cannot bypass equipped slots")
	live.weapon.ability_loadout=profile.ability_loadout.duplicate(true)
	live.player_state.ham=[3000,100,40];check(not live.register_swordsman("ground_slam",head.global_transform,"right"),"Gesture resource floor is strict")
	live.player_state.ham=[3000,1000,1000];live.weapon.item_id="100";check(not live.register_swordsman("ground_slam",head.global_transform,"right"),"Stale weapon identity cannot activate")
	world.free()
	for t in trackers:XRServer.remove_tracker(t)
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","transport":"mocked","headset_tested":false}
	var f:=FileAccess.open("res://../runtime/evidence/swordsman-routing.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
