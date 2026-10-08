extends SceneTree
const Gesture = preload("res://scout/mask_scent_gesture.gd")
class Scout extends "res://scout/controller.gd":
	var calls: Array = []
	func request(action: String, _detail: Dictionary = {}) -> Dictionary:
		calls.append(action); return {}
class Host extends Node:
	var combat_rig: Node3D
	var tracked_avatar: Node3D
	var services: Node
	var world_ready := true
	var loading_stage := false
	var session_leaving := false
	var xr_requested := true
	var xr_focused := true
class Avatar extends Node3D:
	var skeleton: Skeleton3D
class Services extends Node:
	var free := true
	func party_hand_free(_side: String) -> bool: return free
class Bag extends Node3D:
	var allowed := true
class Body extends CharacterBody3D:
	var active := true
	var feedback: Node
	var combat_pools = preload("res://combat/ability_state.gd").new()
class Feedback extends Node:
	var blocked := false
	func combat_blocked() -> bool: return blocked
var errors: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label); push_error(label)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	call_deferred("run")
func arm_at(transform: Transform3D) -> Dictionary:
	return {"wrist":transform * Vector3(-.2,1.15,-.5),"elbow":transform * Vector3(-.2,1.15,-.2)}
func strokes(gesture, hz: float, side: String, mode: String = "rub") -> int:
	var count := 0
	for frame in range(int(hz * 3)):
		var t := frame / hz
		var frame_pose := Transform3D(Basis(Vector3.UP,t*.5),Vector3(t,0,t*.3))
		var arm := arm_at(frame_pose)
		var distance := .145 + .075 * sin(t*TAU*1.7)
		if mode == "jitter": distance = .145 + .01*sin(t*TAU*8)
		if mode == "static": distance = .145
		if mode == "tap": distance = .015
		if mode == "one_way": distance = .055 + minf(t,.9)*.18
		var hand := frame_pose * Vector3(-.2,1.23,-.5+distance)
		if mode == "distant": hand += Vector3.UP*.3
		var fired: bool=gesture.sample(1/hz,arm.wrist if side=="left" else hand,hand if side=="left" else arm.wrist,arm if side=="left" else {},arm if side=="right" else {},mode!="blocked")
		if fired: count += 1
	return count
func run() -> void:
	for hz in [45.0,72.0,90.0,120.0]:
		for side in ["left","right"]:
			check(strokes(Gesture.new(),hz,side)==1,"Repeated rub on %s arm at %d Hz fires once while translating/turning"%[side,hz])
	for mode in ["jitter","static","tap","one_way","distant","blocked"]:
		check(strokes(Gesture.new(),90,"left",mode)==0,"Reject "+mode)
	var gesture = Gesture.new()
	check(strokes(gesture,90,"left")==1,"Initial gesture fires")
	gesture.sample(.02,Vector3.ZERO,Vector3.ZERO,{},{},false)
	check(strokes(gesture,90,"left")==0,"Lost tracking cannot rearm")
	for i in range(40): gesture.sample(.01,Vector3.ZERO,Vector3.ZERO,{},{},true)
	check(strokes(gesture,90,"right")==1,"Separating hands rearms either arm")
	gesture.reset()
	check(not gesture.sample(.5,Vector3.ZERO,Vector3.ZERO,arm_at(Transform3D.IDENTITY),{},true),"Long frame cannot count as stroke")
	check(is_inf(Gesture.contact(Vector3.ZERO,{"wrist":Vector3.ZERO,"elbow":Vector3.ZERO})),"Invalid forearm rejected")
	# Actual controller routing with mocked tracked hardware and native transport.
	var host := Host.new(); root.add_child(host)
	var body := Body.new(); host.add_child(body)
	body.feedback=Feedback.new(); body.add_child(body.feedback)
	var bag := Bag.new(); host.add_child(bag)
	var services := Services.new(); host.add_child(services); host.services=services
	var avatar := Avatar.new(); host.add_child(avatar); host.tracked_avatar=avatar
	avatar.skeleton=Skeleton3D.new(); avatar.add_child(avatar.skeleton)
	for bone in ["lforearm","lwrist","rforearm","rwrist"]: avatar.skeleton.add_bone(bone)
	avatar.skeleton.set_bone_pose_position(0,Vector3(-.2,1.15,-.2))
	avatar.skeleton.set_bone_pose_position(1,Vector3(-.2,1.15,-.5))
	avatar.skeleton.set_bone_pose_position(2,Vector3(.4,1.15,-.2))
	avatar.skeleton.set_bone_pose_position(3,Vector3(.4,1.15,-.5))
	check(Gesture.forearm(avatar.skeleton,"left").wrist.is_equal_approx(Vector3(-.2,1.15,-.5)),"Uses rendered original skeleton forearm")
	var trackers: Array = []
	var controllers: Array[XRController3D] = []
	var head := XRPositionalTracker.new(); head.name="head"; head.type=XRServer.TRACKER_HEAD
	head.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH); XRServer.add_tracker(head); trackers.append(head)
	for side in ["left","right"]:
		var tracker := XRControllerTracker.new(); tracker.name=side+"_hand"; tracker.type=XRServer.TRACKER_CONTROLLER
		tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input("grip",0.0); tracker.set_input("trigger",0.0); XRServer.add_tracker(tracker); trackers.append(tracker)
		var hand := XRController3D.new(); hand.tracker=tracker.name; hand.pose="grip"; host.add_child(hand); controllers.append(hand)
	var scout := Scout.new(); host.add_child(scout); scout.set_process(false)
	scout.app=host; scout.body=body; scout.bag=bag; scout.last_reply=0; scout.state={"mask_scent_available":true}
	for mode in ["normal","cooldown","active","unlearned","stale","busy","queued","occupied","unfocused","blocked","untracked","fist","loading"]:
		scout.calls.clear(); scout.mask_gesture.reset(); scout.last_reply=20 if mode=="stale" else 0
		scout.state={"mask_scent_available":mode!="unlearned","mask_scent_active":mode=="active"}
		scout.busy=mode=="busy"; scout.cooldown_queue=["discard_mask_scent"] if mode=="queued" else []
		body.combat_pools.cooldowns={"mask_scent":10} if mode=="cooldown" else {}
		services.free=mode!="occupied"; host.xr_focused=mode!="unfocused"; host.loading_stage=mode=="loading"; body.feedback.blocked=mode=="blocked"
		trackers[2].set_input("grip",1.0 if mode=="fist" else 0.0)
		trackers[2].set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		if mode=="untracked": trackers[2].invalidate_pose("grip")
		for frame in range(270):
			controllers[0].position=Vector3(-.2,1.15,-.5)
			controllers[1].position=Vector3(-.2,1.23,-.355+.075*sin(frame/90.0*TAU*1.7))
			scout.sample_mask_gesture(1.0/90,controllers[0],controllers[1])
		check(scout.calls==(["mask_scent"] if mode=="normal" else []),"Controller dispatch/gate: "+mode)
	scout.state={"mask_scent_available":true}; scout.last_reply=0; scout.busy=false; scout.cooldown_queue.clear(); body.combat_pools.cooldowns.clear()
	body.combat_pools.selected="other"; body.combat_pools.primed=true; scout.activate_mask(true)
	check(body.combat_pools.selected=="other" and body.combat_pools.primed,"Direct gesture preserves another prepared ability")
	body.combat_pools.selected="mask_scent"; scout.activate_mask(true)
	check(not body.combat_pools.primed,"Gesture consumes selected Mask Scent priming")
	body.combat_pools.primed=true; scout.calls.clear(); scout.activate_mask()
	check(scout.calls==["mask_scent"] and not body.combat_pools.primed,"Existing circle activation still works")
	host.free()
	for tracker in trackers: XRServer.remove_tracker(tracker)
	await process_frame
	var report := {"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"headset_tested":false,"live_core3":false}
	print(JSON.stringify(report)); FileAccess.open("res://../runtime/evidence/mask-scent-gesture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if errors.is_empty() else 1)
