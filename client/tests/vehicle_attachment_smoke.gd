extends "res://tests/vehicles_xr_smoke.gd"
## Original vehicle sockets + original avatar skin, using mocked OpenXR only.
var checks := 0
var maximum_error := 0.0
func verify(value:bool,label:String)->void:
	checks+=1;check(value,label)
func run()->void:
	for name in ["landspeeder_x31","landspeeder_x34","landspeeder_av21","speederbike_flash","speederbike","speederbike_swoop"]:
		var template:String="object/mobile/vehicle/"+name+".iff"
		await inspect_vehicle(template)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"maximum_hold_error_m":maximum_error,"tracking":"mocked OpenXR","renderer":"dummy","live_xr":false,"original_assets":true}
	FileAccess.open("res://../runtime/evidence/vehicle-rigid-attachment.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
func inspect_vehicle(template:String)->void:
	var app:=Host.new();root.add_child(app);app.gameplay_session=Live.new();app.add_child(app.gameplay_session)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body=rig.get_node("PlayerBody");body.active=true;body.set_process(false);body.set_physics_process(false)
	var camera:XRCamera3D=rig.get_node("XRCamera3D")
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var lt:=controller("left_hand",XRPositionalTracker.TRACKER_HAND_LEFT,Vector3.ZERO)
	var rt:=controller("right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT,Vector3.ZERO)
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(rig,body);app.inventory.set_process(false)
	var driver:=preload("res://vehicles/controller.gd").new();app.add_child(driver);driver.setup(app,app.inventory);driver.epoch=0;driver.set_process(false);driver.set_physics_process(false)
	var descriptor:Dictionary=driver.assets.descriptor(template)
	var record:Dictionary={"id":"ride","template":template,"position":[0,0,0],"heading_radians":1.2,"owned":true,"device_id":"fixture","disabled":false,"kind":descriptor.kind,"seats":descriptor.seats.duplicate(true),"controls":descriptor.controls,"speed":0.0,"max_speed":11.0,"reverse_speed":5.0,"acceleration":8.0,"turn_rate":1.34}
	for seat:Dictionary in record.seats:seat.occupant_id=""
	driver.observe({"source_kind":"core3_vehicles","driver_motion":"client_pose","character_id":app.datapad_character_id,"vehicles":[record],"seat":{"vehicle_id":"ride","id":"driver"},"datapad":[]})
	app.tracked_avatar=preload("res://scripts/tracked_avatar.gd").new();app.add_child(app.tracked_avatar)
	var avatar:=preload("res://scripts/avatar.gd").new();app.tracked_avatar.add_child(avatar)
	avatar.configure("human_male",{"profession":"science_medic"});app.tracked_avatar.configure(avatar,rig);app.tracked_avatar.set_standing_eye_height(1.7);app.tracked_avatar.set_process(false)
	var ride:Dictionary=driver.vehicles.ride
	# Hands intentionally start on the opposite side and metres from the model.
	for i in range(2):
		var tracker:XRControllerTracker=lt if i==0 else rt
		tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(2.0 if i==0 else -2.0,.4,1.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input("grip",0.0)
	await process_frame;driver._physics_process(0)
	lt.set_input("grip",1.0);rt.set_input("grip",1.0)
	await process_frame;driver._physics_process(0);driver._process(0)
	verify(driver.input.left_held and driver.input.right_held,template+": remote seated grip acquires both controls")
	verify(driver.input.left_handle==0 and driver.input.right_handle==1,template+": crossed controllers cannot swap model-left/right handles")
	for lean in [Vector3.ZERO,Vector3(1.4,.2,1.4)]:
		head_tracker.set_pose("default",Transform3D(Basis(Vector3.UP,-.6),Vector3(0,1.7,0)+lean),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await process_frame
		var head_before:=camera.transform;var left_before:Transform3D=rig.get_node("LeftHand").transform;var right_before:Transform3D=rig.get_node("RightHand").transform;var body_before:Transform3D=body.global_transform
		app.tracked_avatar._process(1.0/90)
		for side in ["left","right"]:
			var target:Transform3D=driver.hand_target(side)
			var actual:Transform3D=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("hold_l" if side=="left" else "hold_r"))
			var error:=actual.origin.distance_to(target.origin);maximum_error=maxf(maximum_error,error)
			verify(error<.0001,template+": "+side+" hold socket remains on model grip with lean "+str(lean))
			verify(actual.basis.orthonormalized().is_equal_approx(target.basis.orthonormalized()),template+": grip orientation remains model-defined")
			verify(app.tracked_avatar.last_report[side].attached,template+": vehicle-only rigid attachment requested")
		verify(camera.transform.is_equal_approx(head_before) and rig.get_node("LeftHand").transform.is_equal_approx(left_before) and rig.get_node("RightHand").transform.is_equal_approx(right_before),template+": visual attachment never modifies HMD/controllers")
		verify(body.global_transform.is_equal_approx(body_before),template+": visual attachment never moves physics body")
	lt.set_input("grip",0.0);rt.set_input("grip",0.0);await process_frame;driver._physics_process(0);app.tracked_avatar._process(1.0/90)
	for side in ["left","right"]:
		var wrist:=avatar.skeleton.find_bone("lwrist" if side=="left" else "rwrist")
		verify(driver.hand_target(side)==null and not app.tracked_avatar.last_report[side].attached,template+": physical release returns hand to ordinary IK")
		verify(avatar.skeleton.get_bone_pose_position(wrist).is_equal_approx(avatar.skeleton.get_bone_rest(wrist).origin),template+": no arm extension survives release")
	driver.unseat();app.free();XRServer.remove_tracker(head_tracker);XRServer.remove_tracker(lt);XRServer.remove_tracker(rt);trackers.clear();await process_frame
