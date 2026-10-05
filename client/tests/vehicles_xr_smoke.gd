extends SceneTree
## Real XR rig + vehicle presentation with synthetic network/tracking input.
## Optional --capture runs desktop Forward+ Vulkan. Never a live headset claim.
class Host extends Node3D:
	var datapad_epoch:=0
	var datapad_character_id:="test-driver"
	var datapad_account:="mocked"
	var inventory: Node3D
	var combat_rig: Node3D
	var medic: Node3D
	var datapad: Node3D
	var stage: Node3D
	var live_combat: Node
	var gameplay_session: Node
	var tracked_avatar: Node3D
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
	func api(_method,_path,_payload)->Dictionary:return {"ok":false,"error":"Mocked presentation test has no backend"}
class Live extends Node:
	var live:=true
	var session_id:="vehicle-native-fixture"
	func world(p: Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func source(p: Vector3)->Array:return [p.x,p.y,-p.z]
var failures: Array=[]
var trackers: Array=[]
func _initialize()->void:call_deferred("run")
func check(v: bool,label: String)->void:
	if not v:failures.append(label);push_error(label)
func controller(id: String,side: XRPositionalTracker.TrackerHand,p: Vector3)->XRControllerTracker:
	var t:=XRControllerTracker.new();t.name=id;t.type=XRServer.TRACKER_CONTROLLER;t.hand=side;t.set_pose("grip",Transform3D(Basis.IDENTITY,p),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);t.set_input("grip",0.0);t.set_input("trigger",0.0);t.set_input("primary",Vector2.ZERO);XRServer.add_tracker(t);trackers.append(t);return t
func run()->void:
	var capture:=OS.get_cmdline_user_args().has("--capture")
	var driving:=OS.get_cmdline_user_args().has("--driver")
	var app:=Host.new();root.add_child(app)
	app.live_combat=Live.new();app.add_child(app.live_combat)
	if OS.get_cmdline_user_args().has("--gameplay"):
		app.gameplay_session=app.live_combat;app.live_combat=null
	var rig=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body=rig.get_node("PlayerBody");body.active=true
	var camera: XRCamera3D=rig.get_node("XRCamera3D");camera.position=Vector3(0,1.7,0);camera.current=true
	var head:=XRPositionalTracker.new();head.name="head";head.type=XRServer.TRACKER_HEAD;head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head);trackers.append(head)
	var l:=controller("left_hand",XRPositionalTracker.TRACKER_HAND_LEFT,Vector3(-.2,1.3,-.4));controller("right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT,Vector3(.2,1.3,-.4))
	app.inventory=load("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(rig,body,"left");app.inventory.set_process(false)
	var controller_node=load("res://vehicles/controller.gd").new();app.add_child(controller_node);controller_node.setup(app,app.inventory)
	controller_node.epoch=0
	app.tracked_avatar=load("res://scripts/tracked_avatar.gd").new();app.add_child(app.tracked_avatar)
	var avatar=load("res://scripts/avatar.gd").new();app.tracked_avatar.add_child(avatar);avatar.configure("human_male",{"profession":"science_medic"})
	check(app.tracked_avatar.configure(avatar,rig),"Original tracked rider avatar configures")
	app.tracked_avatar.set_standing_eye_height(1.7)
	var descriptor: Dictionary=controller_node.assets.descriptor("object/mobile/vehicle/landspeeder_x34.iff")
	var record: Dictionary={"id":"car","template":"object/mobile/vehicle/landspeeder_x34.iff","position":[0,0,0],"heading_radians":0.0,"owned":true,"device_id":"device","disabled":false,"kind":"landspeeder","seats":descriptor.seats.duplicate(true),"controls":descriptor.controls,"speed":8.0,"max_speed":13.0,"reverse_speed":7.0,"acceleration":8.0,"turn_rate":1.34}
	for s: Dictionary in record.seats:s["occupant_id"]=""
	var snapshot: Dictionary={"source_kind":"core3_vehicles","character_id":"test-driver","vehicles":[record],"seat":{"vehicle_id":"car","id":"driver" if driving else "passenger"},"datapad":[]}
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("7e9aa8");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.7;environment.environment=settings;app.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);app.add_child(light)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(250,250);ground.mesh=plane;ground.position.z=-70;app.add_child(ground)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("b59c74");ground.material_override=material
	for i in range(45):
		for side in [-1,1]:
			var marker:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.15,.6,.15);marker.mesh=mesh;marker.position=Vector3(side*4,.3,-i*4);app.add_child(marker)
	var label:=Label.new();label.position=Vector2(20,18);label.text="Vehicle motion regression · original X34 · mocked tracking/network · desktop Vulkan";app.add_child(label)
	controller_node.observe(snapshot)
	if driving:l.set_input("grip",1.0)
	var had_left_control:=false
	var initial_head:=camera.transform;var maximum_seat_error:=0.0;var maximum_tracking_error:=0.0;var maximum_body_error:=0.0;var maximum_pelvis_error:=0.0
	var eye_in_seat: Transform3D=controller_node.seat_pose().affine_inverse()*camera.global_transform
	var clock:=0.0;var packet_at:=0.0;var index:=0
	# Stick cannot detach or translate a reserved rider; tracked head can move.
	l.set_input("primary",Vector2(0,1))
	for frame in range(480):
		var dt:=1.0/90 if not capture else minf(app.get_process_delta_time(),.04)
		clock+=dt
		if clock>=packet_at:
			index+=1;var delayed: float=clock-[.06,.10,.04,.09][index%4]
			record.position=[sin(delayed*.35)*2,0,delayed*8];record.heading_radians=cos(delayed*.35)*.09
			controller_node.observe(snapshot);packet_at=clock+[.24,.31,.28,.22][index%4]
		# Test moves only the HMD, preserving a small real room-scale lean.
		camera.transform=initial_head;camera.position.x+=sin(clock)*.03
		head.set_pose("default",camera.transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		if not capture:
			controller_node._physics_process(dt);controller_node._process(dt);app.tracked_avatar._process(dt)
		else:
			await process_frame
			await RenderingServer.frame_post_draw
		var seat_pose: Transform3D=controller_node.seat_pose()
		var in_seat: Transform3D=seat_pose.affine_inverse()*camera.global_transform
		maximum_seat_error=maxf(maximum_seat_error,in_seat.origin.distance_to(eye_in_seat.origin+Vector3(sin(clock)*.03,0,0)))
		maximum_tracking_error=maxf(maximum_tracking_error,absf(camera.position.x-sin(clock)*.03))
		maximum_body_error=maxf(maximum_body_error,body.global_position.distance_to(seat_pose.origin))
		had_left_control=had_left_control or bool(controller_node.input.get("left_held",false))
		var pelvis: Vector3=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("root")).origin
		maximum_pelvis_error=maxf(maximum_pelvis_error,pelvis.distance_to(seat_pose.origin))
		if capture and frame in [90,240,420]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../runtime/evidence/vehicles-"+("driver" if driving else "passenger")+"-%d-vulkan.png"%frame)
	if driving:check(had_left_control,"Driver grabs one physical control while other hand stays free")
	check(maximum_seat_error<.0001,"Seat/camera synchronization has no relative render jitter")
	check(maximum_tracking_error<.00001,"Driving does not smooth or overwrite physical head tracking")
	check(maximum_pelvis_error<.002,"Avatar pelvis remains on original seat hardpoint")
	check(maximum_body_error<.0001,"Rider remains locked to seat despite stick locomotion")
	check(camera.transform.basis.is_equal_approx(initial_head.basis),"Driving preserves HMD local orientation")
	var before_exit:=camera.transform
	snapshot.seat={};snapshot["forced_exit"]={"revision":1,"reason":"incapacitated","position":[4,0,20]}
	controller_node.observe(snapshot)
	check(not controller_node.seated() and body.global_position.distance_to(Vector3(4,0,-20))<.00001,"Forced ejection releases seat at authoritative supported exit")
	check(camera.transform.is_equal_approx(before_exit),"Forced ejection preserves local head tracking")
	var exited: Transform3D=rig.global_transform;controller_node.observe(snapshot)
	check(rig.global_transform.is_equal_approx(exited),"Repeated ejection snapshot cannot move view twice")
	var report:={"passed":failures.is_empty(),"errors":failures,"frames":480,"seat_camera_error_m":maximum_seat_error,"head_tracking_error_m":maximum_tracking_error,"body_seat_error_m":maximum_body_error,"pelvis_seat_error_m":maximum_pelvis_error,"capture":capture,"driver":driving,"one_hand_control":had_left_control,"renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method(),"hardware_tested":false,"session_mode":"gameplay" if OS.get_cmdline_user_args().has("--gameplay") else "combat"}
	FileAccess.open("res://../runtime/evidence/vehicles-xr-"+("driver-" if driving else "passenger-")+("vulkan" if capture else "mocked")+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report))
	app.free();for t in trackers:XRServer.remove_tracker(t)
	quit(0 if failures.is_empty() else 1)
