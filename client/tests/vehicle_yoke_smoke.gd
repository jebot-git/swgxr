extends "res://tests/vehicles_xr_smoke.gd"
var count:=0
func verify(value:bool,label:String)->void:
	count+=1;check(value,label)
func triangles(mesh:ArrayMesh)->int:
	var total:=0
	for i in range(mesh.get_surface_count()):total+=mesh.surface_get_array_index_len(i)/3
	return total
func run()->void:
	var app:=Host.new();root.add_child(app);app.gameplay_session=Live.new();app.add_child(app.gameplay_session)
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body=rig.get_node("PlayerBody");body.active=true;body.set_process(false);body.set_physics_process(false)
	var camera:XRCamera3D=rig.get_node("XRCamera3D");camera.position=Vector3(0,1.7,0)
	var head:=XRPositionalTracker.new();head.name="head";head.type=XRServer.TRACKER_HEAD;head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head);trackers.append(head)
	var lt:=controller("left_hand",XRPositionalTracker.TRACKER_HAND_LEFT,Vector3.ZERO)
	var rt:=controller("right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT,Vector3.ZERO)
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(rig,body);app.inventory.set_process(false)
	var driver:=preload("res://vehicles/controller.gd").new();app.add_child(driver);driver.setup(app,app.inventory);driver.epoch=0;driver.set_process(false);driver.set_physics_process(false)
	var catalog:Dictionary=driver.assets.catalog
	for template:String in catalog.items:
		var descriptor:Dictionary=catalog.items[template];var mesh:ArrayMesh=driver.assets.model(template)
		var before:=triangles(mesh);var split:Dictionary=driver.yokes.meshes(template,mesh,descriptor)
		verify(descriptor.control_bases.size()==2,template+": original hand socket orientations retained")
		if descriptor.get("steering_geometry",{}).get("status","")=="ready":
			verify(triangles(split.body)+triangles(split.yoke)==before and triangles(mesh)==before,template+": original hull/yoke split conserves every triangle without changing shared source")
			verify(split.yoke.surface_get_material(0)==mesh.surface_get_material(int(descriptor.steering_geometry.surface)),template+": yoke keeps source material")
		elif descriptor.kind=="landspeeder":verify(not descriptor.steering_geometry.reason.is_empty() and split.is_empty(),template+": connected source yoke is explicitly unsupported; no substitute mesh")
	var descriptor:Dictionary=driver.assets.descriptor("object/mobile/vehicle/landspeeder_x31.iff")
	var record:Dictionary={"id":"car","template":"object/mobile/vehicle/landspeeder_x31.iff","position":[0,0,0],"heading_radians":0.0,"owned":true,"device_id":"fixture","disabled":false,"kind":"landspeeder","seats":descriptor.seats.duplicate(true),"controls":descriptor.controls,"speed":0.0,"max_speed":11.0,"reverse_speed":5.0,"acceleration":8.0,"turn_rate":1.34}
	for seat:Dictionary in record.seats:seat.occupant_id=""
	driver.observe({"source_kind":"core3_vehicles","character_id":app.datapad_character_id,"vehicles":[record],"seat":{"vehicle_id":"car","id":"driver"},"datapad":[]})
	app.tracked_avatar=preload("res://scripts/tracked_avatar.gd").new();app.add_child(app.tracked_avatar)
	var avatar:=preload("res://scripts/avatar.gd").new();app.tracked_avatar.add_child(avatar);avatar.configure("human_male",{"profession":"science_medic"});app.tracked_avatar.configure(avatar,rig);app.tracked_avatar.set_standing_eye_height(1.7);app.tracked_avatar.set_process(false)
	var vehicle:Dictionary=driver.vehicles.car
	var handles:Array=[]
	for point:Array in record.controls:handles.append(Vector3(point[0],point[1],point[2]))
	var pivot:Vector3=(handles[0]+handles[1])*.5
	for grip in [0.0,1.0]:
		for index in range(2):
			var tracker:XRControllerTracker=lt if index==0 else rt
			var pose:Transform3D=rig.global_transform.affine_inverse()*vehicle.view.global_transform*Transform3D(Basis.IDENTITY,handles[index])
			tracker.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",grip)
		await process_frame;driver._physics_process(0);driver._process(0)
	verify(driver.input.left_held and driver.input.right_held,"Both source yoke grips acquired")
	var original_head:=camera.transform
	var physical:Array=[]
	for index in range(2):
		var point:Vector3=pivot+Basis(Vector3.BACK,-.4)*(handles[index]-pivot)+Vector3(0,0,-.1125)
		var pose:Transform3D=rig.global_transform.affine_inverse()*vehicle.view.global_transform*Transform3D(Basis.from_euler(Vector3(.7,.2,.6)),point)
		physical.append(pose)
		(lt if index==0 else rt).set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	rt.set_input("primary",Vector2(0,.56));await process_frame
	driver._physics_process(0);driver._process(0);app.tracked_avatar._process(1.0/90)
	verify(is_equal_approx(float(driver.input.throttle),.5) and driver.input.steer>.5,"Production controller uses physical push independently of wheel steering")
	verify(is_equal_approx(float(driver.input.wheel_angle),-.4) and not vehicle.yoke.transform.basis.is_equal_approx(Basis.IDENTITY),"Original steering component visibly rotates with grabbed wheel arc")
	var errors:Array=[]
	for index in range(2):
		var side:String="left" if index==0 else "right";var hand:XRController3D=rig.get_node(side.capitalize()+"Hand")
		var target:Transform3D=driver.hand_target(side)
		var expected:Vector3=vehicle.view.global_transform*driver.yoke_transform()*handles[index]
		verify(target.origin.distance_to(expected)<.00001,side+": attachment follows actual animated source yoke grip")
		var actual:Transform3D=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("hold_l" if side=="left" else "hold_r"))
		errors.append(actual.origin.distance_to(target.origin))
		verify(actual.origin.distance_to(target.origin)<.015,side+": original avatar hold socket reaches rotating yoke (%.4fm)"%actual.origin.distance_to(target.origin))
		verify(actual.basis.orthonormalized().is_equal_approx(target.basis.orthonormalized()),side+": original hand socket orientation locks to animated yoke")
		verify(hand.transform.is_equal_approx(physical[index]),side+": IK never changes real tracked controller")
		verify(app.tracked_avatar.last_report.fingers[side].mode=="vehicle_grip",side+": fingers retain closed yoke grip")
	verify(camera.transform.is_equal_approx(original_head),"Yoke input and IK never alter HMD tracking")
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1280,850)
		var env:=WorldEnvironment.new();var config:=Environment.new();config.background_mode=Environment.BG_COLOR;config.background_color=Color("172332");config.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;config.ambient_light_color=Color.WHITE;config.ambient_light_energy=.8;env.environment=config;app.add_child(env)
		var observer:=Camera3D.new();app.add_child(observer);observer.position=Vector3(-1.05,1.60,-.48);observer.look_at(Vector3(-.4,1.05,.08));observer.near=.01;observer.fov=58;observer.make_current()
		var label:=Label.new();label.position=Vector2(20,20);label.text="Original X31 yoke and avatar hands · physical push/pull throttle\nDesktop Forward+ Vulkan · mocked OpenXR tracking";app.add_child(label)
		for frame in range(8):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/vehicle-yoke-vulkan.png")
	body.dominant_hand="left";lt.set_input("primary",Vector2(0,-.56));rt.set_input("primary",Vector2(0,1))
	driver._physics_process(0)
	verify(is_equal_approx(float(driver.drive_payload().throttle),.5),"Joystick and handedness changes do not alter held physical throttle")
	body.dominant_hand="right";lt.set_input("primary",Vector2.ZERO)
	lt.set_input("grip",0.0);await process_frame;driver._physics_process(0);driver._process(0);app.tracked_avatar._process(1.0/90)
	verify(driver.hand_target("left")==null and app.tracked_avatar.hand_target(rig.get_node("LeftHand"),"left")==rig.get_node("LeftHand").global_transform,"Released grip immediately restores visual hand tracking")
	rt.invalidate_pose("grip");await process_frame;driver._physics_process(0);driver._process(0)
	verify(driver.hand_target("right") is Transform3D and driver.input.suspended and not driver.input.held and driver.drive_payload().throttle==0,"Tracking loss suspends output while retaining the yoke attachment")
	driver.unseat();verify(driver.hand_target("left")==null and vehicle.yoke.transform.is_equal_approx(Transform3D.IDENTITY),"Dismount clears hand attachments and yoke pose")
	var report:Dictionary={"passed":failures.is_empty(),"checks":count,"failures":failures,"hand_error_m":errors,"original_assets":true,"hardware_tested":false,"renderer":"headless dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method()}
	FileAccess.open("res://../runtime/evidence/vehicle-yoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	app.free();for tracker in trackers:XRServer.remove_tracker(tracker)
	quit(0 if failures.is_empty() else 1)
