extends SceneTree
var errors:Array[String]=[]
var checks:=0
var actions:Array[String]=[]
var menus:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func frames(count:int)->void:
	for _i in range(count):await physics_frame
func controller(side:String)->XRControllerTracker:
	var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand"
	tracker.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	tracker.set_input("primary_click",false);tracker.set_input("primary",Vector2.ZERO);tracker.set_input("ax_button",false)
	tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(-0.2 if side=="left" else 0.2,1.2,-0.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker);return tracker
func run()->void:
	create_timer(40).timeout.connect(func():quit(2))
	var head:=XRPositionalTracker.new();head.type=XRServer.TRACKER_HEAD;head.name="head"
	head.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head)
	var left:=controller("left");var right:=controller("right")
	var floor:=StaticBody3D.new();var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.2,20);collision.shape=box;floor.add_child(collision);floor.position.y=-.1;root.add_child(floor)
	var origin=load("res://xr/player_rig.tscn").instantiate();root.add_child(origin)
	var body=origin.get_node("PlayerBody");var camera:XRCamera3D=origin.get_node("XRCamera3D");body.active=true
	body.feedback.life_action_requested.connect(func(action):actions.append(action))
	body.menu_requested.connect(func():menus+=1)
	await frames(8)
	var body_y:float=body.global_position.y;var raw_head:=camera.transform;var raw_right:Transform3D=origin.get_node("RightHand").transform
	body.feedback.observe({"character_id":"life-fixture","posture":0,"locomotion":preload("res://tests/source_locomotion_smoke.gd").profile()})
	left.set_input("primary",Vector2(0,1))
	await frames(20)
	check(body.velocity.length()>.1,"Player is locomoting before native incapacitation")
	var stopped_at:Vector3=body.global_position
	var origin_stopped:Vector3=origin.global_position
	left.set_input("primary_click",true)
	body.feedback.observe({"character_id":"life-fixture","posture":13})
	await frames(8)
	check(body.feedback.life_fade_alpha>.2 and origin.get_node("XRCamera3D/Fade").layers==1,"Forced viewpoint transition uses visible XR fade without hiding raw tracking")
	await frames(67)
	check(body.global_position.distance_to(stopped_at)<.001 and Vector2(origin.global_position.x,origin.global_position.z).distance_to(Vector2(origin_stopped.x,origin_stopped.z))<.001,"Incapacitation immediately anchors body and viewpoint despite held locomotion")
	check(body.velocity==Vector3.ZERO and body.source_movement_velocity==Vector2.ZERO,"Life lock clears stored movement velocities")
	left.set_input("primary",Vector2.ZERO)
	check(actions.is_empty(),"Jump already held at incapacitation cannot request recovery")
	check(body.feedback.life_locked and body.feedback.observed_posture==13,"Only native snapshot enters life lock")
	check(absf(camera.global_position.y-body_y-.28)<.06,"Forced viewpoint settles near original ground pose")
	check(absf(body.global_position.y-body_y)<.02,"Presentation offset never moves collision body through floor")
	check(camera.transform.is_equal_approx(raw_head) and origin.get_node("RightHand").transform.is_equal_approx(raw_right),"Raw head and controller tracking transforms remain unchanged")
	check(body.feedback.life_label.visible and body.feedback.life_label.text.contains("INCAPACITATED"),"Compact life feedback is visible")
	check(not origin.get_node("LeftHand/MovementDirect").enabled and not body.combat_actions_allowed(),"Native life lock blocks locomotion and combat")
	left.set_input("primary_click",false);await frames(3);left.set_input("primary_click",true);await frames(20)
	check(actions.is_empty() and body.feedback.life_readout().hold_progress>0,"Short deliberate hold shows progress without requesting recovery")
	left.set_input("primary_click",false);await frames(3);left.set_input("primary_click",true);await frames(70)
	check(actions==["recover"] and body.feedback.life_action_pending,"Fresh full one-second hold emits one recovery intent")
	check(body.feedback.observed_posture==13 and body.feedback.life_locked,"Recovery intent never changes posture locally")
	right.set_input("ax_button",true);await frames(3)
	check(actions.size()==1 and menus==0,"Pending life action consumes A without duplicate request or menu")
	body.feedback.resolve_life_action(false,"Native rejection fixture")
	check(body.feedback.life_locked and body.feedback.life_readout().status=="Native rejection fixture","Rejected request retains lock and exposes native reason")
	await frames(70);check(actions.size()==1,"Held jump cannot retrigger after rejection without release")
	left.set_input("primary_click",false);right.set_input("ax_button",false);await frames(3)
	body.feedback.observe({"character_id":"life-fixture","posture":13,"recovery_requested":true,"recovery_remaining_seconds":2.5})
	check(body.feedback.life_readout().recovery_remaining_seconds==2.5,"Authoritative recovery countdown retained")
	left.set_input("primary_click",true);await frames(70);check(actions.size()==1,"Confirmed native recovery timer blocks duplicate recovery intents")
	right.set_input("ax_button",true);await frames(3)
	check(actions==["recover","medical_transport"] and menus==0,"Physical right A requests atomic medical transport during incapacitation")
	body.feedback.observe({"character_id":"life-fixture","posture":14,"cloning":true})
	var dead:Dictionary=body.feedback.animation_context()
	check(dead.life_state=="dead" and dead.life_animation=="dead" and dead.life_pose_frozen,"Authoritative death has distinct frozen original pose context")
	check(not body.feedback.request_life_action("recover") and not body.feedback.request_life_action("medical_transport"),"Cloning and death cannot be locally recovered or duplicate transport")
	body.feedback.observe({"character_id":"life-fixture","posture":14,"cloning":false})
	right.set_input("ax_button",false);await frames(3);right.set_input("ax_button",true);await frames(3)
	check(actions.size()==3 and actions.back()=="medical_transport","Dead player uses same authoritative medical transport action")
	body.feedback.resolve_life_action(false,"Retry fixture");right.set_input("ax_button",false);await frames(2)
	head.invalidate_pose("default");await frames(2);right.set_input("ax_button",true);await frames(2)
	check(actions.size()==3,"Lost head tracking rejects life action")
	head.set_pose("default",raw_head,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	body.feedback.observe({"character_id":"life-fixture","posture":0});await frames(30)
	check(not body.feedback.life_locked and absf(body.feedback.applied_offset)<.01 and not body.feedback.life_label.visible,"Only authoritative normal posture restores view and hides life UI")
	check(origin.get_node("LeftHand/MovementDirect").enabled,"Authoritative recovery restores locomotion")
	# Real original player model: full-source manual sampling and desktop selection.
	var avatar=preload("res://scripts/avatar.gd").new();root.add_child(avatar);avatar.load_catalog();var configured:Dictionary=avatar.configure("human_male",{})
	check(str(configured.get("error","")).is_empty(),"Actual original human avatar configures")
	avatar.set_tracking_mode(true)
	var incap:Dictionary=avatar.sample_life_pose("incapacitated",.2)
	check(incap.get("valid",false) and incap.full_body and incap.bones>30 and str(incap.source).ends_with("incapacitated_face_up.ans"),"Tracked life pose samples actual original full skeleton and source clip")
	check(not avatar.animation_player.active and not avatar.animation_player.is_playing(),"Manual source pose cannot enable automatic tracked-player animation")
	var frozen:Dictionary=avatar.sample_life_pose("dead",.5);var root_pose:Transform3D=avatar.skeleton.get_bone_pose(0)
	avatar.sample_life_pose("dead",8)
	check(frozen.frozen and frozen.time==0 and avatar.skeleton.get_bone_pose(0).is_equal_approx(root_pose),"Death freezes original source pose independently of elapsed time")
	avatar.set_tracking_mode(false);avatar.update_motion(.01,0,{"presentation":{"life_locked":true,"life_animation":"incapacitated"}})
	check(avatar.current_animation=="incapacitated","Desktop selects explicit authoritative incapacitated animation")
	avatar.update_motion(.01,0,{"presentation":{"life_locked":true,"life_animation":"dead"}})
	check(avatar.current_animation=="dead" and not avatar.animation_player.is_playing(),"Desktop dead presentation is frozen original pose")
	avatar.queue_free();body.feedback.reset();origin.queue_free();floor.queue_free();await process_frame
	XRServer.remove_tracker(head);XRServer.remove_tracker(left);XRServer.remove_tracker(right)
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"live_core3":false,"gpu_validation":false}
	FileAccess.open("res://../runtime/evidence/player-feedback/life.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
