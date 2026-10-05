extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Mount=preload("res://scripts/forearm_mount.gd")
const Finger=preload("res://scripts/rendered_finger_pointer.gd")
const Services=preload("res://scripts/xr_services.gd")
class Body extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
var checks:=0
var failures: Array=[]
var trackers: Array=[]
func check(value: bool,label: String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func hand(rig: XROrigin3D,side: String)->XRControllerTracker:
	var tracker:=XRControllerTracker.new();tracker.name=side+"_hand";tracker.type=XRServer.TRACKER_CONTROLLER
	tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("trigger",0.0);tracker.set_input("grip",0.0);tracker.set_input("primary",Vector2.ZERO)
	XRServer.add_tracker(tracker);trackers.append(tracker)
	var node:=XRController3D.new();node.name="LeftHand" if side=="left" else "RightHand";node.tracker=tracker.name;node.pose="grip";rig.add_child(node);node.position=Vector3(.2,1.2,-.3)
	return tracker
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var avatar:=Avatar.new();world.add_child(avatar);avatar.configure("human_male");avatar.set_tracking_mode(true)
	var skeleton: Skeleton3D=avatar.skeleton
	var solver:=SwgTrackedIK.new();solver.configure(skeleton)
	for side in ["left","right"]:
		var prefix:="l" if side=="left" else "r"
		var wrist:=skeleton.find_bone(prefix+"wrist")
		var target:=skeleton.get_bone_global_rest(wrist)
		target.origin=skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"arm")).origin+Vector3(-.16 if side=="left" else .16,-.20,-.4)
		solver.solve({side+"_hand":target},1.0/90)
		var mount:=Mount.new();var before: Transform3D=mount.resolve(skeleton,side,Transform3D.IDENTITY)
		var axis: Vector3=skeleton.global_basis.inverse()*before.basis.x
		var arm_before:=skeleton.get_bone_global_pose(mount.bone)
		target.basis=Basis(axis,1.0)*target.basis
		solver.solve({side+"_hand":target},1.0/90)
		var after: Transform3D=mount.resolve(skeleton,side,Transform3D.IDENTITY)
		check(skeleton.get_bone_global_pose(mount.bone).basis.is_equal_approx(arm_before.basis),side+" native IK keeps forearm swing unchanged for pure tracked wrist roll")
		check(after.basis.z.distance_to(Basis(before.basis.x,1.0)*before.basis.z)<.002,side+" actual tracked wrist roll exposes forearm overlay")
		check(after.basis.x.dot(before.basis.x)>.999,side+" panel remains lengthwise and unmirrored")
		check((after.origin-after.basis.z*.085).distance_to(before.origin-before.basis.z*.085)<.0001,side+" arm roll retains physical forearm anchor")
		var tip:=Finger.pose(avatar,side)
		check(tip.source=="rendered_skin" and Vector3(tip.local_tip).length()>.015 and Vector3(tip.local_tip).length()<.08,side+" pointer endpoint measured from original distal finger skin")
		var distal:int=tip.bone;var rotation:=skeleton.get_bone_pose_rotation(distal)
		skeleton.set_bone_pose_rotation(distal,rotation*Quaternion(Vector3.UP,.5));skeleton.force_update_all_bone_transforms()
		var curled:=Finger.pose(avatar,side)
		check(Vector3(tip.direction).distance_to(curled.direction)>.1 and Vector3(curled.tip).distance_to((skeleton.global_transform*skeleton.get_bone_global_pose(distal))*Vector3(tip.local_tip))<.0001,side+" pointer follows rendered distal articulation")
		skeleton.set_bone_pose_rotation(distal,rotation)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position=Vector3(0,1.7,0)
	var head:=XRPositionalTracker.new();head.name="head";head.type=XRServer.TRACKER_HEAD;head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head);trackers.append(head)
	hand(rig,"left");var right:=hand(rig,"right")
	var body:=Body.new();world.add_child(body)
	var ui:=Services.new();world.add_child(ui);ui.configure(rig,body);ui.set_process(false);ui.avatar=avatar;ui.set_allowed(true)
	var rows: Array=[]
	for i in range(36):rows.append({"id":str(i),"name":"Mission "+str(i),"supported":true})
	ui.open_terminal({"id":"terminal","kind":"mission","position":Vector3.ZERO})
	ui.apply_response({"terminal":{"id":"terminal","kind":"mission","missions":rows}})
	var finger:=Finger.pose(avatar,"right")
	var normal: Vector3=-finger.direction
	var x:=Vector3.UP.cross(normal).normalized();var y:=normal.cross(x).normalized()
	# Place the actual plane under the rendered fingertip at list row zero.
	var pixel:=Vector2(300,150)
	var local:=Vector3((pixel.x/860-.5)*Services.PANEL_METERS.x,(.5-pixel.y/580)*Services.PANEL_METERS.y,0)
	ui.surface.global_transform=Transform3D(Basis(x,y,normal),finger.tip+finger.direction*.08-Basis(x,y,normal)*local)
	for i in range(2):await process_frame
	ui._process(.016)
	check(ui.pointer_visual.visible,"Rendered fingertip produces visible terminal contact")
	var distal:int=finger.bone;var rotation:=skeleton.get_bone_pose_rotation(distal)
	skeleton.set_bone_pose_rotation(distal,rotation*Quaternion(Vector3.UP,1.2));skeleton.force_update_all_bone_transforms()
	right.set_input("grip",.9);right.set_input("trigger",.8);await process_frame;ui._process(.016)
	check(ui.pointer_pressed and ui.pointer_button=="trigger","Trigger click captures even when grip is held")
	right.set_input("trigger",0.0);await process_frame;ui._process(.016)
	check(ui.panel.selected==0 and not ui.pointer_pressed,"Trigger release selects original row despite index curl and held grip")
	skeleton.set_bone_pose_rotation(distal,rotation);skeleton.force_update_all_bone_transforms()
	right.set_input("primary",Vector2(0,-1));await process_frame
	for i in range(20):ui._process(.05)
	check(ui.panel.offset>=10,"Main joystick scrolls mission list through actual controller process path")
	var previous: float=ui.panel.offset
	right.set_input("primary",Vector2.ZERO);await process_frame;ui._process(.1)
	check(ui.panel.offset==previous,"Joystick neutral stops scrolling")
	# Grip drag uses captured hand translation and cannot turn into a row click.
	right.set_input("grip",0.0);await process_frame;ui._process(.016)
	right.set_input("grip",.9);await process_frame;ui._process(.016)
	var old_offset: float=ui.panel.offset
	var moved:=Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.3)-ui.surface.global_basis.y*.09)
	right.set_pose("grip",moved,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	rig.get_node("RightHand").global_transform=moved # XR-off has no interface to apply tracker poses.
	await process_frame;ui._process(.016)
	right.set_input("grip",0.0);await process_frame;ui._process(.016)
	check(ui.panel.offset<old_offset and ui.panel.selected==0,"Physical grip drag scrolls without accidentally selecting final row")
	var requests: Array=[];ui.action_requested.connect(func(action,payload):requests.append([action,payload]))
	var confirm: Vector2=ui.panel.CONFIRM_RECT.get_center()
	var contact:=ui.surface.global_transform*Vector3((confirm.x/860-.5)*Services.PANEL_METERS.x,(.5-confirm.y/580)*Services.PANEL_METERS.y,.002)
	# Move rendered avatar with its finger to the button (controller ray stays elsewhere).
	avatar.global_position+=contact-Finger.pose(avatar,"right").tip
	ui._process(.016);right.set_input("trigger",.8);await process_frame;ui._process(.016)
	right.set_input("trigger",0.0);await process_frame;ui._process(.016)
	check(requests.size()==1 and requests[0][0]=="mission_accept" and requests[0][1].mission_id=="0","Real contact+controller edges emit selected native mission exactly once")
	ui.set_allowed(false);check(not ui.pointer_visual.visible and not ui.pointer_pressed,"Lifecycle close clears pointer and drag")
	var head_pose:=camera.global_transform
	var anchor:=preload("res://scripts/body_grab_anchor.gd").from_pose(head_pose,rig.global_transform,Vector3(0,-.5,.25)).origin
	head_pose.basis=Basis(Vector3.UP,PI)
	check(not ui.back_contains(head_pose,anchor),"Wallet old location leaves activation range after headset turn")
	anchor=preload("res://scripts/body_grab_anchor.gd").from_pose(head_pose,rig.global_transform,Vector3(0,-.5,.25)).origin
	check(ui.back_contains(head_pose,anchor),"Wallet pickup follows headset facing after turn")
	ui.set_allowed(true)
	for side in ["left","right"]:
		ui.offhand=side
		for yaw in [-1.5,1.5]:
			head_pose=Transform3D(Basis.from_euler(Vector3(.5,yaw,.3)),Vector3(.4,1.4,-.2))
			var hand_pose:=Transform3D(Basis.IDENTITY,head_pose.origin+Basis(Vector3.UP,yaw)*Vector3(0,-.5,.25))
			ui.update_wallet_gesture(true,head_pose,hand_pose,0)
			ui.update_wallet_gesture(true,head_pose,hand_pose,.9)
			check(ui.wallet_held,"Actual wallet grab works with %s offhand and headset yaw %.1f"%[side,yaw])
			ui.update_wallet_gesture(true,head_pose,hand_pose,0)
			check(not ui.wallet_held,"Release returns wallet before next acquisition")
	var bag:=preload("res://scripts/xr_inventory.gd").new();world.add_child(bag);bag.configure(rig,body);bag.set_process(false);bag.set_allowed(true)
	bag.external_grab_blocker=ui.blocks_combat
	for side in ["left","right"]:
		bag.offhand=side;ui.offhand=side;bag.set_allowed(true)
		# Both original activation spheres include this point between shoulder/back.
		var overlap:=Transform3D(Basis.IDENTITY,camera.global_position+Vector3(-.10 if side=="left" else .10,-.32,.18))
		bag.update_gestures(true,camera.global_transform,overlap,0,0,{},Transform3D.IDENTITY)
		check(bag.shoulder_candidate and bag.interaction_active and not bag.blocks_services(),side+" overlapping shoulder hover leaves wallet service enabled")
		ui.avatar=null # Direct tracked controller input for wallet, no finger hit required.
		var off_tracker:XRControllerTracker=XRServer.get_tracker(side+"_hand")
		var other_tracker:XRControllerTracker=XRServer.get_tracker(("right" if side=="left" else "left")+"_hand")
		other_tracker.set_input("grip",0.0);other_tracker.set_input("trigger",0.0)
		off_tracker.set_pose("grip",overlap,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		rig.get_node(side.capitalize()+"Hand").global_transform=overlap
		off_tracker.set_input("grip",0.0);off_tracker.set_input("trigger",0.0)
		ui.set_allowed(not bag.blocks_services());ui._process(.016)
		off_tracker.set_input("grip",.9);ui._process(.016);bag._process(.016)
		check(ui.wallet_held and not bag.is_open and not bag.action_pending,side+" wallet claims overlapping grip before backpack in same frame")
		ui.set_allowed(not bag.blocks_services());ui.update_wallet_gesture(true,camera.global_transform,overlap,.9)
		check(ui.wallet_held,side+" next service gate preserves held wallet instead of alternating bag/wallet ownership")
		ui.update_wallet_gesture(true,camera.global_transform,overlap,0)
	world.queue_free()
	for tracker in trackers:XRServer.remove_tracker(tracker)
	for i in range(3):await process_frame
	print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"native_ik":true,"original_skin":true,"xr":"off; mocked controllers"}));quit(0 if failures.is_empty() else 1)
