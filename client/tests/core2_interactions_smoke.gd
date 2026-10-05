extends SceneTree
const Inventory=preload("res://scripts/xr_inventory.gd")
const Finger=preload("res://scripts/rendered_finger_pointer.gd")
class Player extends CharacterBody3D:
	var active:=true
	var ground_provider:Variant
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
class Host extends Node:
	var world_ready:=true
class Main extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
class EmittingAvatar extends Node3D:
	signal logout_finished
	var callback_returned:=false
	func finish()->void:logout_finished.emit();callback_returned=true
var checks:=0
var failures:Array=[]
var trackers:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head);head.position=Vector3(0,1.7,0)
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER;XRServer.add_tracker(tracker);trackers.append(tracker)
		tracker.set_input("trigger",0.0)
		var hand:=XRController3D.new();hand.name=side.capitalize()+"Hand";hand.tracker=tracker.name;rig.add_child(hand)
	var player:=Player.new();world.add_child(player)
	var bag:=Inventory.new();world.add_child(bag);bag.configure(rig,player);bag.set_process(false);bag.set_allowed(true)
	var app:=Host.new();world.add_child(app)
	var gather:=preload("res://scripts/resource_gathering.gd").new();world.add_child(gather);gather.set_process(false);gather.app=app;gather.bag=bag
	var tool:Dictionary={"id":"101","template":"object/tangible/survey_tool/survey_tool_mineral.iff","tool_kind":"survey","name":"Native survey tool"}
	gather.state={"hip_tool":tool};bag.set_hip_tool(tool)
	bag.tool_pickup_requested.connect(gather.pickup)
	var deployments:Array=[];bag.deploy_requested.connect(func(item,pose):deployments.append([item,pose]))
	var returns:Array=[];bag.return_tool_requested.connect(func(item):returns.append(item))
	var surveys:Array=[];bag.survey_requested.connect(func(item,resource):surveys.append([item,resource]))
	for side in ["left","right"]:
		bag.clear_held();bag.set_open(false);bag.offhand=side;bag.grip_armed=false;bag.main_grip_armed=false;bag.off_hip_grip_armed=false
		head.rotation=Vector3(.4,-1.4 if side=="left" else 1.4,.2)
		var head_yaw:=Basis(Vector3.UP,head.rotation.y)
		var off:=bag.controller_for(side);var main:=bag.controller_for(bag.main_side())
		off.global_transform=Transform3D(Basis.IDENTITY,head.global_position+head_yaw*Vector3(-.22 if side=="left" else .22,-.75,0));main.position=Vector3(0,1.2,-.5)
		trackers[0 if side=="left" else 1].set_pose("default",off.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		check(not bag.blocks_combat(),side+" idle offhand at headset-facing tool hip cannot block weapon recovery")
		bag.update_gestures(true,head.global_transform,off.global_transform,0,0,{},main.global_transform)
		bag.update_gestures(true,head.global_transform,off.global_transform,.8,0,{},main.global_transform)
		check(bag.held_item.get("id")=="101" and bag.held_hand_side()==side,side+" offhand grip actually retrieves the owned hip tool through gathering coordinator")
		bag.refresh_hand_presentations()
		check(bag.held_model.global_position.is_equal_approx(off.global_position),side+" retrieved model follows retrieving hand, not dominant controller")
		bag.update_gestures(true,head.global_transform,off.global_transform,.8,0,{},main.global_transform)
		check(deployments.is_empty() and bag.held_item.get("id")=="101",side+" free-hand grip release cannot drop/deploy offhand tool")
		check(bag.tool_pointer_controller()==main and bag.bag_hand_side()==bag.main_side(),side+" free hand is assigned survey pointing and bag pickup")
		main.global_position=head.global_position+head_yaw*Vector3(.19 if bag.main_side()=="right" else -.19,-.16,.12)
		bag.update_gestures(true,head.global_transform,off.global_transform,.8,.8,{},main.global_transform)
		check(bag.is_open and bag.surfaces[0].mesh.visible and bag.surfaces[1].mesh.visible,side+" free-hand shoulder grab renders complete bag while survey tool remains held")
		check(not bag.surfaces[bag.survey_surface].mesh.visible and not bag.surfaces[bag.resource_surface].mesh.visible,side+" bag takes display priority over survey panes")
		bag.survey_ui.selected_resource_id="777";bag.update_held_trigger(0,head.global_transform);bag.update_held_trigger(.9,head.global_transform)
		check(surveys.is_empty(),side+" inventory click cannot also fire survey command")
		bag.update_gestures(true,head.global_transform,off.global_transform,0,.8,{},main.global_transform)
		check(returns.size()==(1 if side=="left" else 2) and bag.action_pending,side+" releasing tool into open bag requests authoritative holster return")
		bag.finish_item_action(true)
		bag.update_gestures(true,head.global_transform,off.global_transform,0,.8,{},main.global_transform)
		check(bag.is_open and bag.bag_hand_side()==bag.main_side(),side+" native tool-return acknowledgment cannot move or close the bag still held in free hand")
		bag.set_open(false)
	bag.offhand="left";bag.take_item(tool)
	bag.set_open(true)
	check(bag.surfaces[0].mesh.visible and bag.surfaces[1].mesh.visible and not bag.surfaces[bag.survey_surface].mesh.visible,"Original main-hand survey tool also permits inventory readout")
	bag.set_open(false)
	check(bag.surfaces[bag.survey_surface].mesh.visible and bag.surfaces[bag.resource_surface].mesh.visible,"Stowing bag restores selected survey map and resource pane")
	bag.clear_held()
	var avatar:=preload("res://scripts/avatar.gd").new();world.add_child(avatar);avatar.configure("human_male");avatar.set_tracking_mode(true)
	for side in ["left","right"]:
		var tracker:XRControllerTracker=trackers[0 if side=="left" else 1]
		var hand:=bag.controller_for(side);tracker.set_input("trigger",0.0)
		var first:=Finger.pose(avatar,side,rig,hand)
		var bone:int=first.bone;var rotation:Quaternion=avatar.skeleton.get_bone_pose_rotation(bone)
		tracker.set_input("trigger",.9);avatar.skeleton.set_bone_pose_rotation(bone,rotation*Quaternion(Vector3.UP,1.2));avatar.skeleton.force_update_all_bone_transforms()
		var curled:=Finger.pose(avatar,side,rig,hand)
		check(Vector3(curled.tip).distance_to(first.tip)>.01,side+" source fingertip truly curls in original skeleton during click")
		check(Vector3(curled.ray_origin).is_equal_approx(first.tip) and Vector3(curled.direction).is_equal_approx(first.direction),side+" mathematical click ray is stable despite actual finger curl")
		check(Vector3(curled.tip).distance_to((avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(bone))*Vector3(first.local_tip))<.00001,side+" visible laser still originates at actual rendered fingertip")
		var transform:=avatar.global_transform;avatar.global_transform=Transform3D(Basis(Vector3.UP,.4),Vector3(.2,.1,-.2))*transform
		var moved:=Finger.pose(avatar,side,rig,hand)
		check(Vector3(moved.direction).is_equal_approx(Basis(Vector3.UP,.4)*Vector3(first.direction)) and Vector3(moved.ray_origin).distance_to(first.ray_origin)>.05,side+" click stabilization follows tracked wrist motion instead of freezing aim in world")
		avatar.global_transform=transform;tracker.set_input("trigger",0.0);avatar.skeleton.set_bone_pose_rotation(bone,rotation);avatar.skeleton.force_update_all_bone_transforms()
	# Actual main cleanup invoked while the removed avatar is emitting a signal.
	var main_app:=Main.new();root.add_child(main_app);main_app.player=Player.new();main_app.add_child(main_app.player)
	main_app.menu=PanelContainer.new();main_app.add_child(main_app.menu)
	main_app.resume_button=Button.new();main_app.add_child(main_app.resume_button)
	main_app.action_row=HBoxContainer.new();main_app.add_child(main_app.action_row)
	var emitter:=EmittingAvatar.new();main_app.add_child(emitter);main_app.tracked_avatar=emitter
	main_app.stage=Node3D.new();main_app.add_child(main_app.stage)
	emitter.logout_finished.connect(main_app.clear_character_world);emitter.finish()
	check(emitter.callback_returned and emitter.is_queued_for_deletion() and not emitter.visible,"Logoff safely retires locked emitting avatar after hiding it")
	check(main_app.tracked_avatar==null and main_app.stage==null and not main_app.world_ready,"Actual world cleanup clears ownership immediately before deferred destruction")
	await process_frame;await process_frame
	check(not is_instance_valid(emitter),"Locked callback unwinds and avatar is freed without cleanup exception")
	main_app.queue_free();world.queue_free()
	for tracker in trackers:XRServer.remove_tracker(tracker)
	await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"original_assets":true,"mocked_tracking":true,"headset_tested":false,"gpu_tested":false}
	FileAccess.open("res://../runtime/evidence/core2/interactions.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
