extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Live=preload("res://combat/live_world.gd")
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func sweep(rig:Node3D,head_tracked:=true)->void:
	var left:XRController3D=rig.origin.get_node("LeftHand")
	var right:XRController3D=rig.origin.get_node("RightHand")
	left.position=Vector3(-.25,1.4,-.3);right.position=Vector3(.55,1.4,-.3)
	rig.sample_tka_gestures(.02,head_tracked)
	for i in range(16):right.position.x-=.04;rig.sample_tka_gestures(.02,head_tracked)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var origin:=XROrigin3D.new();world.add_child(origin);origin.position=Vector3(20,0,30);origin.rotation.y=.8
	var head:=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	var trackers:Array=[]
	for side:String in ["left","right"]:
		var t:=XRControllerTracker.new();t.type=XRServer.TRACKER_CONTROLLER;t.name=side+"_hand"
		t.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);t.set_input("grip",1.);t.set_input("trigger",0.);XRServer.add_tracker(t);trackers.append(t)
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=t.name;controller.pose="grip";origin.add_child(controller)
	var body:=CharacterBody3D.new();world.add_child(body)
	var rig:=Rig.new();world.add_child(rig);check(rig.configure(head,body,[],"right",origin),"Production unarmed rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	check(rig.configure_unarmed(catalog.unarmed),"Native unarmed profile configures")
	for state in rig.unarmed.values():state.profile.item_id="88"
	var live:=Live.new();world.add_child(live);live.set_process(false);live.rig=rig;live.app=Host.new();world.add_child(live.app);live.live=true;live.native_ready=true;live.session_id="tka-session";live.owner_account="tka";live.owner_character="1"
	live.weapon={"item_id":"88","certified":true,"unarmed":true,"ability_loadout":{"slots":["","","",""],"ultimate":"indomitable_focus"}}
	var context:Dictionary={}
	for id:String in ["tka_sweep","tka_half_spin","tka_volley","indomitable_focus"]:context[id]={"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0,"action_cost":80,"mind_cost":40,"interval_seconds":1.5}
	live.player_state={"ham":[3000,1000,1000],"tka":context.duplicate(true)}
	rig.configure_tka(context,live.register_tka,"88","indomitable_focus")
	await process_frame
	sweep(rig)
	check(live.queue.size()==1 and live.queue[0].kind=="tka" and live.queue[0].payload.ability_id=="tka_sweep","Production sweep queues owned native ability with four empty targeting slots")
	if live.queue.is_empty():world.free();quit(1);return
	check(live.queue[0].payload.item_id=="88" and not live.queue[0].payload.has("target_ids") and not live.queue[0].payload.has("damage"),"Client supplies no targets or effect authority")
	check(rig.tka_input_captured and rig.physical_guard.current.mode=="none","Area gesture captures ordinary combat and guard")
	check(not live.register_tka("tka_sweep",head.global_transform,"right"),"Shared cadence blocks immediate duplicate")
	for mode:String in ["learned","conditions_met","cooldown","menu","head","occupied","inventory"]:
		rig.tka_gestures.clear();rig.tka_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.offhand_occupied=false;rig.interaction_blocker=Callable();live.queue.clear();live.next_launch_usec=0
		if mode in ["learned","conditions_met"]:
			for row:Dictionary in rig.tka_context.values():row[mode]=false
		if mode=="cooldown":rig.tka_context.tka_sweep.cooldown_remaining_seconds=3
		if mode=="menu":rig.ability_ui.menu_open=true
		if mode=="occupied":rig.offhand_occupied=true
		if mode=="inventory":rig.interaction_blocker=func()->bool:return true
		sweep(rig,mode!="head");check(live.queue.is_empty(),"Production gate: "+mode)
	rig.tka_context=context.duplicate(true);rig.ability_ui.menu_open=false;rig.offhand_occupied=false;rig.interaction_blocker=Callable();rig.tka_gestures.clear();live.next_launch_usec=0
	var left:XRController3D=origin.get_node("LeftHand");var right:XRController3D=origin.get_node("RightHand")
	left.position=Vector3(-.05,1.4,-.3);right.position=Vector3(.05,1.4,-.3);rig.sample_tka_gestures(.02,true)
	trackers[0].set_input("trigger",1.);trackers[1].set_input("trigger",1.);rig.sample_tka_gestures(.02,true)
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="indomitable_focus","Production fists-together chord queues equipped ultimate")
	for i in range(30):rig.sample_tka_gestures(.02,true)
	check(live.queue.size()==1,"Held ultimate inputs cannot repeat native request")
	live.next_launch_usec=0;live.weapon.ability_loadout.ultimate=""
	check(not live.register_tka("indomitable_focus",head.global_transform,"right"),"Native selection projection gates ultimate")
	live.weapon.ability_loadout.ultimate="indomitable_focus";live.player_state.ham[1]=80
	check(not live.register_tka("tka_sweep",head.global_transform,"right"),"Insufficient Action blocks area request")
	live.player_state.ham[1]=1000;live.weapon.item_id="89"
	check(not live.register_tka("tka_sweep",head.global_transform,"right"),"Stale equipped source ID is rejected")
	live.weapon.item_id="88"
	for t in trackers:t.set_input("trigger",0.)
	rig.tka_gestures.clear();live.queue.clear();left.position=Vector3(-.25,1.4,-.3);right.position=Vector3(.25,1.4,-.3);head.rotation=Vector3.ZERO
	for i in range(30):head.rotation.y+=.04;rig.sample_tka_gestures(.02,true)
	check(live.queue.is_empty(),"Looking around with stationary fists cannot trigger area attack")
	head.rotation=Vector3.ZERO;rig.tka_gestures.clear()
	for i in range(30):origin.position.x+=.05;origin.rotation.y+=.02;rig.sample_tka_gestures(.02,true)
	check(live.queue.is_empty(),"Virtual translation and turning supply no gesture movement")
	world.free()
	for t in trackers:XRServer.remove_tracker(t)
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","transport":"mocked","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/tka-routing.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
