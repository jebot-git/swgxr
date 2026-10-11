extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Live=preload("res://combat/live_world.gd")
class Menu extends Node3D:
	var menu_open:=false
	func close()->void:menu_open=false
class Weapon extends RefCounted:
	var profile:Dictionary={"item_id":"42"}
	var swing_feedback:Dictionary={"engaged":true}
	func certified()->bool:return true
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
var checks:=0
var errors:Array=[]
var calls:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func pump(rig:Node3D,head_tracked:=true)->void:
	var controller:XRController3D=rig.origin.get_node("RightHand")
	for y:float in [0.,.1,.2,.3,.4,.5,.4,.3,.2,.3,.4,.5]:
		controller.position=Vector3(.2,1.7+y,-.2);rig.sample_overhead_warcry(.05,head_tracked)
func run()->void:
	var origin:=XROrigin3D.new();root.add_child(origin);origin.position=Vector3(20,0,30);origin.rotation.y=.8
	var head:=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	var trackers:Array=[]
	for side:String in ["left","right"]:
		var t:=XRControllerTracker.new();t.type=XRServer.TRACKER_CONTROLLER;t.name=side+"_hand"
		t.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);t.set_input("grip",1.);t.set_input("trigger",0.);XRServer.add_tracker(t);trackers.append(t)
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=t.name;controller.pose="grip";origin.add_child(controller)
	var rig:=Rig.new();root.add_child(rig);rig.set_process(false);rig.set_physics_process(false);rig.origin=origin;rig.head=head;rig.allowed=true;rig.ability_ui=Menu.new();rig.add_child(rig.ability_ui);rig.selected=0;rig.weapons.append({"state":Weapon.new()})
	var context:Dictionary={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"action_cost":80,"mind_cost":40}
	rig.configure_warcry(context,func(pose:Transform3D,hand:String)->bool:calls.append({"pose":pose,"hand":hand});return true)
	await process_frame
	pump(rig)
	check(calls.size()==1 and calls[0].hand=="right" and calls[0].pose==head.global_transform,"Actual rig routes overhead gesture with world transform and held weapon")
	check(rig.warcry_input_captured and rig.physical_guard.current.mode=="none","Gesture captures combat input and releases physical guard")
	for mode:String in ["learned","conditions_met","cooldown","menu","head","stowed","blocked_inventory"]:
		rig.overhead_warcry.clear();rig.warcry_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.selected=0;rig.interaction_blocker=Callable();calls.clear()
		if mode in ["learned","conditions_met"]:rig.warcry_context[mode]=false
		if mode=="cooldown":rig.warcry_context.cooldown_remaining_seconds=3
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="stowed":rig.selected=-1
		if mode=="blocked_inventory":rig.interaction_blocker=func()->bool:return true
		pump(rig,mode!="head");check(calls.is_empty(),"Production permission gate: "+mode)
	rig.selected=0;rig.interaction_blocker=Callable()
	var live:=Live.new();root.add_child(live);live.set_process(false);live.rig=rig;live.app=Host.new();root.add_child(live.app);live.live=true;live.native_ready=true;live.session_id="test-session";live.owner_account="test";live.owner_character="1";live.weapon={"item_id":"42","certified":true,"ability_loadout":{"slots":["","","",""],"ultimate":""}};live.player_state={"warcry":context.duplicate(true),"ham":[3000,1000,1000]}
	check(live.register_warcry(head.global_transform,"right"),"Learned gesture creates native request with all targeting slots empty")
	check(live.queue.size()==1 and live.queue[0].kind=="warcry" and live.queue[0].payload.item_id=="42" and not live.queue[0].payload.has("target_id"),"Native request carries weapon/pose, no client target authority")
	check(not live.register_warcry(head.global_transform,"right"),"Shared cadence prevents immediate duplicate")
	live.next_launch_usec=0;live.player_state.ham[1]=80
	check(not live.register_warcry(head.global_transform,"right"),"SAC gate rejects insufficient resources")
	live.player_state.ham[1]=1000;live.weapon.item_id="43"
	check(not live.register_warcry(head.global_transform,"right"),"Stale equipped-weapon snapshot rejected")
	var fist:=Weapon.new();fist.profile={"item_id":"99","unarmed":true};rig.unarmed={"right":fist};rig.selected=-1
	rig.native_unarmed_available=false
	check(not rig.unarmed_engaged("right"),"Holstered pistol cannot show an unarmed attack reticle")
	live.weapon={"item_id":"42","unarmed":false,"certified":true};live.next_launch_usec=0
	check(not live.register_warcry(head.global_transform,"right"),"Holstered pistol cannot route fist warcry")
	rig.native_unarmed_available=true;rig.warcry_context=context.duplicate(true);rig.overhead_warcry.clear();calls.clear()
	pump(rig);check(calls.size()==1,"Native unarmed equipment permits raised-fist warcry gesture")
	live.weapon={"item_id":"99","unarmed":true,"certified":true};live.next_launch_usec=0
	check(live.register_warcry(head.global_transform,"right") and live.queue.back().payload.item_id=="99","Unarmed warcry submits the native fist identity")
	rig.selected=0;rig.unarmed.clear();live.weapon={"item_id":"42","unarmed":false,"certified":true};live.next_launch_usec=0
	var buffs:Dictionary={"center_of_being":context.duplicate(true),"berserk":context.duplicate(true)}
	live.player_state.brawler_buffs=buffs;live.next_launch_usec=0
	check(live.register_brawler_buff("center_of_being","left"),"CoB queues native self-buff without a targeting slot")
	check(live.queue.back().kind=="brawler_buff" and live.queue.back().payload.ability_id=="center_of_being","Self-buff request identifies native ability and current weapon")
	live.next_launch_usec=0;live.player_state.brawler_buffs.berserk.conditions_met=false
	check(not live.register_brawler_buff("berserk","left"),"Server-projected weapon/state restriction blocks self buff")
	rig.ability_ui.menu_open=false;rig.configure_brawler(buffs,func(id:String,hand:String)->bool:calls.append({"ability":id,"hand":hand});return true,"42");calls.clear()
	var left:XRController3D=origin.get_node("LeftHand");var right:XRController3D=origin.get_node("RightHand")
	trackers[0].set_input("grip",0.);left.position=Vector3(0,1.4,-.4);right.position=Vector3(.2,1.,-.3)
	for i in range(50):rig.sample_brawler_gestures(.02,true)
	check(calls.size()==1 and calls[0].ability=="center_of_being" and calls[0].hand=="left","Production tracked open offhand hold invokes CoB once")
	rig.brawler_gestures.clear();rig.brawler_context.berserk.conditions_met=true;calls.clear();trackers[0].set_input("grip",1.)
	left.position=Vector3(-.65,1.6,0);right.position=Vector3(.65,1.6,0)
	for i in range(50):rig.sample_brawler_gestures(.02,true)
	check(calls.size()==1 and calls[0].ability=="berserk","Production two spread fist pose invokes Berserk once")
	rig.brawler_gestures.clear();calls.clear();trackers[0].set_input("grip",0.);left.position=Vector3(0,1.4,-.4);right.position=Vector3(.2,1.,-.3)
	for i in range(20):rig.sample_brawler_gestures(.02,true)
	rig.configure_brawler(buffs,rig.brawler_authority,"99")
	for i in range(20):rig.sample_brawler_gestures(.02,true)
	check(calls.is_empty(),"Changing equipped weapon cancels a partial buff gesture")
	live.app.free();live.free();rig.selected=-1;rig.weapons.clear();rig.free();origin.free()
	for t in trackers:XRServer.remove_tracker(t)
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","native_transport":"mocked","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/warcry-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
