extends "res://tests/vehicles_xr_smoke.gd"
var count:=0
class MountHost extends Host:
	var requests:Array=[]
	func api(_method,path,payload)->Dictionary:
		requests.append({"path":path,"payload":payload});return {"ok":false,"error":"Mocked transport"}
func verify(value:bool,label:String)->void:
	count+=1;check(value,label)
func run()->void:
	var control:=SwgVehicleControls.new();var pose:=Transform3D.IDENTITY
	for grips in [Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
		control.reset()
		var result:=control.sample_reins(pose,pose,pose,grips.x,grips.y,true,true,true,Vector2(.7,1))
		verify(result.held and result.throttle==1 and result.steer>0,"Either/both rein grips enable joystick control: "+str(grips))
		var moved:=Transform3D(Basis(Vector3.UP,1),Vector3(2,3,4))
		result=control.sample_reins(pose,moved,moved,grips.x,grips.y,true,true,true,Vector2.ZERO)
		verify(result.throttle==0 and result.steer==0,"Moving hands cannot throttle or steer")
		result=control.sample_reins(pose,pose,pose,grips.x,grips.y,true,true,false,Vector2.ONE)
		verify(not result.held and result.throttle==0 and result.steer==0,"Tracking loss suppresses rein input")
		result=control.sample_reins(pose,pose,pose,0,0,true,true,true,Vector2.ONE)
		verify(not result.held and result.throttle==0,"Releasing both grips stops control")
	var app:=MountHost.new();root.add_child(app);app.gameplay_session=Live.new();app.add_child(app.gameplay_session)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body=rig.get_node("PlayerBody");body.active=true;body.set_physics_process(false);body.set_process(false)
	var camera:XRCamera3D=rig.get_node("XRCamera3D");camera.position=Vector3(0,1.7,0)
	var head:=XRPositionalTracker.new();head.name="head";head.type=XRServer.TRACKER_HEAD;head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head)
	var lt:=controller("left_hand",XRPositionalTracker.TRACKER_HAND_LEFT,Vector3(-.2,1,-.4));var rt:=controller("right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT,Vector3(.2,1,-.4))
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(rig,body);app.inventory.set_process(false)
	var driver=load("res://vehicles/controller.gd").new();app.add_child(driver);driver.setup(app,app.inventory);driver.epoch=0;driver.set_process(false);driver.set_physics_process(false)
	var template:="object/mobile/dewback_hue.iff";var descriptor:Dictionary=driver.mounts.descriptor(template)
	verify(not descriptor.is_empty(),"Original dewback saddle data loaded")
	var record:Dictionary={"id":"mount","template":template,"kind":"creature_mount","position":[0,0,0],"heading_radians":0.0,"owned":true,"device_id":"native-trained-pet","disabled":false,"seats":descriptor.seats.duplicate(true),"controls":descriptor.controls,"speed":0.0,"max_speed":11.0,"reverse_speed":3.0,"acceleration":8.0,"turn_rate":1.34}
	for seat:Dictionary in record.seats:seat.occupant_id=""
	driver.observe({"source_kind":"core3_vehicles","driver_motion":"client_pose","character_id":app.datapad_character_id,"vehicles":[record],"seat":{"vehicle_id":"mount","id":"driver"},"datapad":[]})
	verify(driver.seated(),"Trained mount uses reserved driver seat")
	verify(not driver.rider_pose("human_male").is_empty(),"Original creature rider pose available")
	var mount:Dictionary=driver.vehicles.mount
	rt.set_input("grip",1.0);lt.set_input("primary",Vector2(.8,1));await process_frame
	var initial_head:=camera.transform;var initial_left:Transform3D=driver.left.transform
	for frame in range(60):
		var before:Vector3=mount.node.global_position
		driver._physics_process(1.0/90);driver._process(1.0/90)
		var move:Vector3=mount.node.global_position-before
		verify(absf(move.dot(mount.node.global_basis.x))<.000001,"Mount cannot sidestep")
	verify(mount.node.global_position.length()>.5 and absf(mount.node.rotation.y)>.01,"Locomotion stick moves and steers mount")
	verify(camera.transform.is_equal_approx(initial_head) and driver.left.transform.is_equal_approx(initial_left),"Seat motion preserves physical HMD/controller poses")
	verify(driver.hand_target("right") is Transform3D and driver.hand_target("left")==null,"Only gripping hand occupies original rein socket")
	body.interface_move_captured=true;driver._physics_process(.01)
	verify(driver.input.throttle==0 and driver.input.steer==0,"UI capture suppresses mount joystick")
	body.interface_move_captured=false;driver.age=5;driver._physics_process(.01)
	verify(not driver.input.held and driver.input.throttle==0,"Stale connection suspends rein drive")
	driver.age=0;rt.set_input("grip",0.0);await process_frame;driver._physics_process(.01)
	verify(not driver.input.held and driver.hand_target("right")==null,"Physical release frees hand")
	body.request_jump();await process_frame
	verify(app.requests.size()==1 and app.requests[0].path=="/vehicles/dismount","Jump retains native dismount action")
	driver.unseat();app.free();XRServer.remove_tracker(head);XRServer.remove_tracker(lt);XRServer.remove_tracker(rt)
	print(JSON.stringify({"passed":failures.is_empty(),"checks":count,"failures":failures,"renderer":"dummy","hardware_tested":false}))
	quit(0 if failures.is_empty() else 1)
