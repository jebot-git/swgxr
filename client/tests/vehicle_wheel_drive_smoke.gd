extends "res://tests/vehicles_xr_smoke.gd"
## Actual production driver physics, original X31 handles, mock OpenXR input.
## No Core3 network or live headset; tests steering through movement and seat sync.
var results:Array=[]
var count:=0
func verify(value:bool,label:String)->void:
	count+=1;check(value,label)
func run()->void:
	for scenario in ["wrist_roll","translate_hands","push_straight","physical_half","physical_brake","clockwise","counterclockwise","latched_far"]:
		await scenario_test(scenario)
	verify(results.size()==8 and count>=1000,"All production driver scenarios executed without script abort")
	var report:Dictionary={"passed":failures.is_empty(),"checks":count,"failures":failures,"scenarios":results,"renderer":"headless dummy","hardware_tested":false,"network":"delayed native snapshots; client-authoritative driver motion","source_vehicle":"object/mobile/vehicle/landspeeder_x31.iff"}
	FileAccess.open("res://../runtime/evidence/vehicle-wheel-drive.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report))
	call_deferred("quit",0 if failures.is_empty() else 1)
func scenario_test(scenario:String)->void:
	var app:=Host.new();root.add_child(app);app.gameplay_session=Live.new();app.add_child(app.gameplay_session)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body=rig.get_node("PlayerBody");body.active=true;body.set_physics_process(false);body.set_process(false)
	var camera:XRCamera3D=rig.get_node("XRCamera3D");camera.position=Vector3(.02,1.7,.015)
	var head:=XRPositionalTracker.new();head.name="head";head.type=XRServer.TRACKER_HEAD;head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head);trackers.append(head)
	var lt:=controller("left_hand",XRPositionalTracker.TRACKER_HAND_LEFT,Vector3.ZERO)
	var rt:=controller("right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT,Vector3.ZERO)
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(rig,body,"left");app.inventory.set_process(false)
	var driver=load("res://vehicles/controller.gd").new();app.add_child(driver);driver.setup(app,app.inventory);driver.epoch=app.datapad_epoch;driver.set_physics_process(false);driver.set_process(false)
	var descriptor:Dictionary=driver.assets.descriptor("object/mobile/vehicle/landspeeder_x31.iff")
	var record:Dictionary={"id":"x31","template":"object/mobile/vehicle/landspeeder_x31.iff","position":[0,0,0],"heading_radians":0.0,"owned":true,"device_id":"original-fixture","disabled":false,"kind":"landspeeder","seats":descriptor.seats.duplicate(true),"controls":descriptor.controls,"speed":6.0,"max_speed":11.0,"reverse_speed":5.0,"acceleration":8.0,"turn_rate":1.34}
	for seat:Dictionary in record.seats:seat.occupant_id=""
	driver.observe({"source_kind":"core3_vehicles","driver_motion":"client_pose","character_id":app.datapad_character_id,"vehicles":[record],"seat":{"vehicle_id":"x31","id":"driver"},"datapad":[]})
	var vehicle:Dictionary=driver.vehicles.x31
	var handles:Array=[]
	for point:Array in record.controls:handles.append(Vector3(point[0],point[1],point[2]))
	verify(handles.size()==2 and handles[0].distance_to(handles[1])>.1,scenario+": original two rim handles loaded")
	var pivot:Vector3=(handles[0]+handles[1])*.5
	var initial_head:=camera.transform
	# Grip latches arm at original neutral positions before any input changes.
	for grip in [0.0,1.0]:
		for index in range(2):
			var tracker:XRControllerTracker=lt if index==0 else rt
			var acquire:Vector3=handles[index]+(Vector3(0,0,1.2) if scenario=="latched_far" else Vector3.ZERO)
			var pose:Transform3D=rig.global_transform.affine_inverse()*vehicle.view.global_transform*Transform3D(Basis.IDENTITY,acquire)
			tracker.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",grip)
		await process_frame;driver._physics_process(0);driver._process(0)
	verify(driver.input.left_held and driver.input.right_held,scenario+": both actual tracked hands grab source controls")
	rt.set_input("primary",Vector2(0,.56 if scenario=="physical_half" else (-1.0 if scenario=="physical_brake" else (1.0 if scenario in ["clockwise","counterclockwise","latched_far"] else 0.0))))
	var begin:Transform3D=vehicle.node.global_transform
	var worst_lateral_ratio:=0.0;var max_pose_error:=0.0;var sampled:Dictionary={}
	for frame in range(180 if scenario=="latched_far" else 30):
		var expected:Array=[]
		for index in range(2):
			var point:Vector3=handles[index];var basis:=Basis.IDENTITY
			if scenario=="latched_far":point+=Vector3(0,0,1.0)
			elif scenario=="physical_half":point.z-=.1125
			elif scenario=="physical_brake":point.z+=.2
			elif scenario=="wrist_roll":basis=Basis(Vector3.BACK,-.5)
			elif scenario=="translate_hands":point+=Vector3(.15,.1,0)
			elif scenario=="push_straight":point.z-=.2
			elif scenario in ["clockwise","counterclockwise"]:
				point=pivot+Basis(Vector3.BACK,-.5 if scenario=="clockwise" else .5)*(point-pivot);point.z-=.2
			var pose:Transform3D=rig.global_transform.affine_inverse()*vehicle.view.global_transform*Transform3D(basis,point)
			expected.append(pose)
			var tracker:XRControllerTracker=lt if index==0 else rt
			tracker.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await process_frame
		var before:Transform3D=vehicle.node.global_transform
		driver._physics_process(1.0/90);sampled=driver.drive_payload();driver._process(1.0/90)
		if scenario=="latched_far":
			verify(driver.input.left_held and driver.input.right_held,"Held yoke remains latched outside original reach after %.2fs"%(frame/90.0))
			verify(driver.hand_target("left") is Transform3D,"Latched visual hand remains on original animated yoke")
			if frame==95:
				var retained:Transform3D=vehicle.node.global_transform
				driver.observe({"source_kind":"core3_vehicles","driver_motion":"client_pose","character_id":app.datapad_character_id,"vehicles":[record],"seat":{"vehicle_id":"x31","id":"driver"},"datapad":[]})
				verify(vehicle.node.global_transform.is_equal_approx(retained),"Delayed source snapshot cannot rewind own driver transform")
		var after:Transform3D=vehicle.node.global_transform
		var delta:Vector3=after.origin-before.origin
		var tangent:Vector3=-(before.basis.z+after.basis.z).normalized()
		if delta.length()>.00001:worst_lateral_ratio=maxf(worst_lateral_ratio,delta.slide(tangent).length()/delta.length())
		for index in range(2):
			var actual:Transform3D=rig.get_node("LeftHand" if index==0 else "RightHand").transform
			max_pose_error=maxf(max_pose_error,actual.origin.distance_to(expected[index].origin))
			verify(actual.basis.is_equal_approx(expected[index].basis),scenario+": vehicle cannot overwrite controller orientation frame%d"%frame)
		max_pose_error=maxf(max_pose_error,camera.transform.origin.distance_to(initial_head.origin))
	var final_pose:Transform3D=vehicle.node.global_transform
	var yaw:=atan2(final_pose.basis.z.x,final_pose.basis.z.z)
	var displacement:Vector3=final_pose.origin-begin.origin
	verify(max_pose_error<.00001 and camera.transform.basis.is_equal_approx(initial_head.basis),scenario+": local head/controller tracking stays exact")
	verify(displacement.z<-.5,scenario+": vehicle advances along forward direction")
	if scenario=="latched_far":
		verify(displacement.z< -10 and float(sampled.throttle)>.99,"Local throttle continues beyond one second without server control echoes")
		verify(sampled.mode=="client_pose" and Vector3(sampled.position[0],sampled.position[1],-sampled.position[2]).distance_to(final_pose.origin)<.001,"Published payload contains actual collision-resolved driver pose")
		lt.set_input("grip",0.0);rt.set_input("grip",0.0);await process_frame;driver._physics_process(0)
		verify(not driver.input.held and driver.hand_target("left")==null,"Physical grip release detaches yoke and visual hands")
	elif scenario in ["wrist_roll","translate_hands"]:
		verify(absf(float(sampled.steer))<.001 and absf(yaw)<.001 and absf(displacement.x)<.001,scenario+": input does not create diagonal strafe or steering")
		verify(absf(float(sampled.throttle))<.001,scenario+": reach and wrist roll cannot command throttle")
	elif scenario=="push_straight":
		verify(float(sampled.throttle)>.99 and absf(float(sampled.steer))<.001,"Straight physical push accelerates without steering")
	elif scenario in ["physical_half","physical_brake"]:
		verify(is_equal_approx(float(sampled.throttle),.5 if scenario=="physical_half" else -1.0),scenario+": physical forward/back travel controls throttle/brake")
		verify(absf(float(sampled.steer))<.001,scenario+": physical depth does not steer")
	else:
		var direction:=1.0 if scenario=="clockwise" else -1.0
		verify(float(sampled.steer)*direction>.7 and float(sampled.throttle)>.99,scenario+": wheel rim arc and push/pull produce independent steer/throttle")
		verify(yaw*direction<-.25 and displacement.x*direction>.15,scenario+": clockwise means right and counterclockwise means left through actual physics")
		verify(worst_lateral_ratio<.12,scenario+": changing heading bends forward trajectory rather than lateral strafing")
	results.append({"scenario":scenario,"steer":sampled.steer,"throttle":sampled.throttle,"yaw_radians":yaw,"displacement":[displacement.x,displacement.y,displacement.z],"max_lateral_fraction":worst_lateral_ratio,"max_tracking_error_m":max_pose_error})
	if scenario=="latched_far":
		driver.state.erase("driver_motion")
		var legacy:Dictionary=driver.drive_payload()
		verify(not legacy.has("mode") and legacy.has("held") and legacy.has("throttle"),"Older native servers receive only their legacy control schema")
	app.queue_free();await process_frame
	for tracker in trackers:XRServer.remove_tracker(tracker)
	trackers.clear();await process_frame
