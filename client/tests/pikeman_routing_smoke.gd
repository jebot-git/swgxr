extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Live=preload("res://combat/live_world.gd")
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":29,"max_health":100,"effective_max_health":100,"boss":false,"level":90,"melee_control_available":true,"knockdown_available":true,"fractured_armour":false}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"pikeman-session"}
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
var axis:=Vector3.FORWARD
var support_contact:=true
var facing:=Basis.IDENTITY
func pose(p:=Vector3(.15,-.3,-.3),head_tracked:=true)->void:
	main.global_position=head.global_position+facing*p
	var visual:Node3D=rig.weapons[0].visual
	var longest:int=rig.weapons[0].bounds.size.max_axis_index()
	var turn:Basis=Basis(Quaternion(Basis.IDENTITY[longest],axis))
	visual.global_transform=Transform3D(facing*turn,main.global_position)
	support.global_position=rig.support_point(0)
	var correction:Vector3=head.global_position+facing*p-(main.global_position+support.global_position)*.5
	main.global_position+=correction;support.global_position+=correction;visual.global_position+=correction
	if not support_contact:support.global_position+=Vector3(1,0,0)
	rig.two_hands=support_contact
	rig.sample_pikeman_gestures(.02,head_tracked)
func ready(head_tracked:=true)->void:
	for i in range(24):pose(Vector3(.15,-.3,-.3),head_tracked)
func jab(head_tracked:=true)->void:
	for i in range(6):pose(Vector3(.15,-.3,-.3-.05*i),head_tracked)
	for i in range(6):pose(Vector3(.15,-.3,-.55+.05*i),head_tracked)
func jabs(head_tracked:=true)->void:
	ready(head_tracked);jab(head_tracked);jab(head_tracked)
func reset_inputs()->void:
	axis=Vector3.FORWARD;support_contact=true;rig.pikeman_gestures.clear();rig.pikeman_input_captured=false;rig.warcry_input_captured=false;rig.abilities.cooldowns.clear();live.queue.clear();live.shots.clear();live.next_launch_usec=0
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
	var profile:Dictionary=catalog.weapons.lance_staff_wood_s1.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
	profile.ability_loadout={"slots":["knockdown_strike","polearm_stun","pinning_strike","disrupting_jab"],"ultimate":"whirlwind"}
	for id:String in ["knockdown_strike","polearm_stun","pinning_strike","disrupting_jab","whirlwind"]:
		var row:Dictionary={"id":id,"label":id,"activation":"native_melee","base_sac":{"health":0,"action":60,"mind":25},"sac_policy":"fixed","max_range_m":4,"cooldown_seconds":20,"interval_seconds":2,"conditions_met":true,"requires_control_available":id!="pinning_strike","native_family":"pikeman","requires_knockdown_available":id=="knockdown_strike","ultimate":id=="whirlwind","self_only":false}
		profile.abilities.append(row)
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile],"right",origin),"Production polearm rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0);rig.weapons[0].state.ability_state=null
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]})
	live=Live.new();world.add_child(live);live.set_process(false);live.rig=rig;live.app=Host.new();world.add_child(live.app);live.live=true;live.native_ready=true;live.session_id="pikeman-session";live.owner_account="pikeman";live.owner_character="1"
	live.weapon={"kind":"melee","item_id":"99","certified":true,"unarmed":false,"abilities":profile.abilities,"fire_interval_seconds":2,"ability_loadout":profile.ability_loadout.duplicate(true)}
	var context:Dictionary={}
	for id:String in ["driving_jabs","overhead_whirl","sweeping_trip","whirlwind"]:context[id]={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"cooldown_seconds":10,"action_cost":100,"mind_cost":40,"interval_seconds":2}
	live.player_state={"ham":[3000,1000,1000],"pikeman":context.duplicate(true)}
	rig.configure_pikeman(context,live.register_pikeman,"99","whirlwind");rig.shot_authority=live.register_shot
	var actor:=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-2.5);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape)
	live.actors["201"]=actor
	head.look_at(actor.global_position+Vector3.UP)
	await physics_frame;await physics_frame
	jabs()
	check(live.queue.size()==1 and live.queue[0].kind=="pikeman" and live.queue[0].payload.ability_id=="driving_jabs","Production jabs queue native ability")
	if live.queue.is_empty():world.free();quit(1);return
	check(not live.queue[0].payload.has("target_id") and not live.queue[0].payload.has("damage"),"Gesture target and damage stay server-owned")
	check(rig.pikeman_input_captured and rig.physical_guard.current.mode=="none","Completed gesture captures ordinary swings and guard")
	check(not live.register_pikeman("driving_jabs",head.global_transform,"right"),"Shared cadence blocks duplicate")
	live.next_launch_usec=0
	check(not live.register_pikeman("driving_jabs",head.global_transform,"right"),"Predicted cooldown blocks stale-context repeat")
	live.rejected_fire(str(live.queue[0].shot_id))
	check(float(rig.abilities.cooldowns.get("driving_jabs",-1))==0,"Native rejection clears predicted cooldown")
	for mode:String in ["menu","tracking","cooldown","not_learned","inventory","weapon_family","grip","occupied","support"]:
		reset_inputs();rig.pikeman_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable()
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="cooldown":rig.pikeman_context.driving_jabs.cooldown_remaining_seconds=5
		if mode=="not_learned":
			for row:Dictionary in rig.pikeman_context.values():row.learned=false
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		if mode=="weapon_family":rig.weapons[0].state.profile["class"]="melee_2h"
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="support":support_contact=false
		if mode=="grip":trackers[1].set_input("grip",0.)
		jabs(mode!="tracking")
		check(live.queue.is_empty(),"Production gesture gate: "+mode)
		rig.weapons[0].state.profile["class"]="melee_polearm";trackers[1].set_input("grip",1.);rig.offhand_occupied=false
	reset_inputs();rig.pikeman_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.interaction_blocker=Callable()
	ready()
	for i in range(8):pose(Vector3(.15,-.3,-.3).lerp(Vector3(.4,-.65,-.3),i/7.))
	for i in range(12):pose(Vector3(.4-.065*i,-.65,-.3))
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="sweeping_trip","Production low horizontal sweep routes once")
	reset_inputs();ready()
	for i in range(8):pose(Vector3(.15,-.3,-.3).lerp(Vector3(.2,.25,-.35),i/7.))
	for i in range(25):pose(Vector3(.2*cos(i*TAU/24),.25,-.35+.2*sin(i*TAU/24)))
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="overhead_whirl","Production overhead circle routes once")
	reset_inputs();facing=Basis(Vector3.UP,PI/2);head.basis=facing;jabs()
	check(live.queue.size()==1,"Gesture recognition follows player facing")
	facing=Basis.IDENTITY;head.look_at(actor.global_position+Vector3.UP)
	reset_inputs();live.actors.clear();pose()
	trackers[0].set_input("trigger",1.);trackers[1].set_input("trigger",1.);pose()
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="whirlwind" and not live.queue[0].payload.has("target_id"),"Supported two-trigger ultimate leaves area target selection to server")
	for i in range(20):pose()
	check(live.queue.size()==1,"Held ultimate cannot repeat")
	for mode:String in ["no_contact","occupied","unselected","cooldown"]:
		reset_inputs();rig.pikeman_context=context.duplicate(true);rig.pikeman_ultimate="whirlwind";rig.offhand_occupied=false
		if mode=="no_contact":support_contact=false
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="unselected":rig.pikeman_ultimate=""
		if mode=="cooldown":rig.pikeman_context.whirlwind.cooldown_remaining_seconds=10
		pose();trackers[0].set_input("trigger",1.);trackers[1].set_input("trigger",1.);pose()
		check(live.queue.is_empty(),"Ultimate gate: "+mode)
	rig.offhand_occupied=false;rig.pikeman_ultimate="whirlwind";live.actors["201"]=actor
	reset_inputs();var ui:Node3D=rig.target_abilities;ui.target=actor;ui.target_id="201";ui.item_id="99";ui.refresh()
	check(ui.points.size()==4,"Four equipped Pikeman body markers")
	actor.record.boss=true;actor.record.level=151;ui.refresh();check(ui.points.size()==4,"Bosses retain eligible attacks without execution")
	actor.record.knockdown_available=false;ui.refresh();check(ui.points.size()==3,"Native knockdown recovery hides only knockdown marker");actor.record.knockdown_available=true
	actor.record.melee_control_available=false;ui.refresh();check(ui.points.size()==1,"Control recovery retains only soft-slow marker")
	actor.record.melee_control_available=true;ui.refresh()
	var point:Vector3=ui.points.filter(func(p):return p.ability.id=="knockdown_strike")[0].position
	var start:=Vector3(.2,1.2,-.15);var direction:Vector3=(point-start).normalized()
	var hand_pose:=Transform3D(Basis(Vector3.UP,PI/2),start)
	rig.sample(.02,hand_pose,hand_pose,1,0,0,true,true)
	for i in range(12):hand_pose.origin=start+direction*.07*i;rig.sample(.02,hand_pose,hand_pose,1,0,1,true,true)
	check(live.queue.size()==1 and live.queue[0].kind=="pikeman" and live.queue[0].payload.ability_id=="knockdown_strike" and live.queue[0].payload.target_id=="201","Physical punch to marker routes native Pikeman action")
	reset_inputs();live.weapon.ability_loadout.slots=["","","",""]
	check(live.register_melee({"item_id":"99","ability_id":"knockdown_strike","target_id":"201"},head.global_transform).is_empty(),"Direct routing cannot bypass equipped slots")
	live.weapon.ability_loadout=profile.ability_loadout.duplicate(true);live.weapon.ability_loadout.ultimate=""
	check(not live.register_pikeman("whirlwind",head.global_transform,"right"),"Direct routing cannot bypass selected ultimate")
	live.player_state.ham=[3000,100,40];check(not live.register_pikeman("overhead_whirl",head.global_transform,"right"),"Gesture resource floor is strict")
	live.player_state.ham=[3000,1000,1000];live.weapon.item_id="100";check(not live.register_pikeman("overhead_whirl",head.global_transform,"right"),"Stale weapon identity cannot activate")

	world.free()
	for t in trackers:XRServer.remove_tracker(t)
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","transport":"mocked","headset_tested":false}
	var f:=FileAccess.open("res://../runtime/evidence/pikeman-routing.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
