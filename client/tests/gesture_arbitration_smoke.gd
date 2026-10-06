extends SceneTree
## Production recognizers, controller routing and HAM replication with mocked XR.
const Pets = preload("res://tests/creature_handler_integration.gd")
const PetFixture = preload("res://tests/pet_commands_smoke.gd")
const Entertainer = preload("res://tests/entertainer_smoke.gd")
class Main extends "res://scripts/main.gd":
	func _ready() -> void: pass
class Body extends Entertainer.ControlBody:
	var dominant_hand := "right"
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
class Host extends Entertainer.ControlHost:
	var tracked_avatar: Node3D
	var avatar: Node3D
class Bag extends Node3D:
	var is_open := false
	var held_item: Dictionary = {}
class Native extends Entertainer.NativeStub:
	var busy := false
	var pending_actions: Array = []
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	call_deferred("run")
func tracker(side: String) -> XRControllerTracker:
	var value := XRControllerTracker.new()
	value.type = XRServer.TRACKER_CONTROLLER
	value.name = side+"_hand"
	value.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	value.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for button in ["primary_click","ax_button","by_button"]:value.set_input(button,false)
	value.set_input("primary",Vector2.ZERO)
	value.set_input("grip",0.0);value.set_input("trigger",0.0)
	XRServer.add_tracker(value)
	return value
func run() -> void:
	var main := Main.new();root.add_child(main);main.set_process(false)
	var left_tracker := tracker("left");var right_tracker := tracker("right")
	var head_tracker := XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var host := Host.new();root.add_child(host)
	var rig := XROrigin3D.new();host.add_child(rig)
	var body := Body.new();body.name="PlayerBody";rig.add_child(body)
	var head := XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head);head.position.y=1.7
	body.feedback=Entertainer.GroundedFeedback.new();body.feedback.configure(body,head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;hand.pose="grip";hand.tracker="left_hand" if side=="LeftHand" else "right_hand";rig.add_child(hand)
	var left:XRController3D=rig.get_node("LeftHand");var right:XRController3D=rig.get_node("RightHand")
	left.pose="grip";right.pose="grip"
	await process_frame
	var pad:=preload("res://scripts/xr_datapad.gd").new();host.add_child(pad);pad.configure(rig,body);pad.set_process(false);pad.set_allowed(true);host.datapad=pad
	var performer:=preload("res://entertainment/controller.gd").new();host.add_child(performer);performer.set_process(false);performer.set_physics_process(false)
	performer.native.free();performer.native=Native.new();performer.add_child(performer.native)
	performer.host=host;performer.body=body;performer.origin=rig;performer.head=head;body.feedback.performer=performer
	main.entertainer=performer
	var ham:Dictionary={"ham":[100,100,100],"max_ham":[100,100,100],"wounds":[0,0,0]}
	var open_palms:Dictionary={"main_open":true,"off_open":true,"main_down":true,"off_down":true}
	var music_cases:Dictionary={"slitherhorn":"wind","mandoviol":"strings","bandfill":"percussion","nalargon":"keyboard","":"dance"}
	for instrument:String in music_cases:
		var kind:String=music_cases[instrument]
		performer.context={"complete":true,"entertainer":true,"commands":[instrument,"startMusic+starwars1","startDance+basic"]}
		performer.item={"id":"123","template":"object/tangible/instrument/"+instrument+".iff"} if not instrument.is_empty() else {}
		var choices:Array=performer.assets.performances(performer.context,performer.item)
		check(not choices.is_empty(),kind+" eligible with original mixed-case Core3 command grants")
		if choices.is_empty():continue
		performer.selected=choices[0];performer.primed=true;performer.motion.reset();performer.native.calls.clear()
		pad.set_gesture_reserved(false);pad.update_activation(true,0,0,.02)
		for frame in range(270):
			var t:float=frame/90.0
			var a:=Vector3(.2,1.25,-.4);var b:=Vector3(-.2,1.25,-.4)
			match kind:
				"wind":a=Vector3(0,1.60,-.14)
				"percussion":b=a+Vector3(0,.28+.15*cos(t*TAU*2),0)
				"strings":b=a+Vector3(-.10,.14*sin(t*TAU*2),0)
				"keyboard":a.y+=.08*sin(t*TAU*2);b.y-=.08*sin(t*TAU*2)
				"dance":a=Vector3(.5,1.25+.12*sin(t*TAU*1.5),-.4);b=Vector3(-.5,1.25-.12*sin(t*TAU*1.5),-.4)
			right.global_transform=Transform3D(Basis(Vector3.FORWARD,-PI/2) if kind=="dance" else Basis.IDENTITY,a)
			left.global_transform=Transform3D(Basis(Vector3.FORWARD,PI/2) if kind=="dance" else Basis.IDENTITY,b)
			left_tracker.set_input("grip",0.0 if kind=="dance" else 1.0);left_tracker.set_input("trigger",0.0 if kind=="dance" else 1.0)
			if frame%3==0:body.combat_pools.apply_authoritative(ham)
			performer._physics_process(1.0/90)
			pad.set_gesture_reserved(main.gameplay_gesture_reserved())
			pad.update_activation(true,1.0,1.0,1.0/90)
		check(performer.native.calls.filter(func(row):return row.action=="perform").size()==1,kind+" reaches one native perform despite repeated HAM updates")
		check(not pad.is_open,kind+" gesture never opens datapad, including after dispatch")
		pad.set_gesture_reserved(false);pad.update_activation(true,0,0,.02)
		pad.update_activation(true,1,1,.26)
		check(pad.is_open,"Fresh released chord reclaims datapad after "+kind)
		pad.set_open(false)
	var circle_recognizer:=SwgPerformanceGesture.new()
	var circle_fired:=false
	for frame in range(270):
		var t:float=frame/90.0
		var a:=Vector3(.5+.1*cos(t*TAU*1.5),1.25+.1*sin(t*TAU*1.5),-.4)
		var b:=Vector3(-.5-.1*cos(t*TAU*1.5),1.25-.1*sin(t*TAU*1.5),-.4)
		circle_fired=circle_recognizer.sample(1.0/90,"dance",Transform3D(Basis(Vector3.RIGHT,-.8),Vector3(0,1.7,0)),Transform3D(Basis.IDENTITY,a),Transform3D(Basis.IDENTITY,b),true,open_palms) or circle_fired
	check(circle_fired,"Prop-free bilateral circles start dance while looking down")
	# Dance negative poses use the same native recognizer; no prop or fabricated skill.
	var motion:=SwgPerformanceGesture.new()
	for invalid in ["fists","palms_up","overhead","static","one_hand"]:
		motion.reset();var fired:=false
		for frame in range(220):
			var t:float=frame/90.0;var a:=Vector3(.5,1.25+.12*sin(t*TAU*1.5),-.4);var b:=Vector3(-.5,1.25-.12*sin(t*TAU*1.5),-.4)
			var hands:=open_palms.duplicate()
			if invalid=="fists":hands.main_open=false
			if invalid=="palms_up":hands.off_down=false
			if invalid=="overhead":a.y+=1;b.y+=1
			if invalid=="static":a.y=1.25;b.y=1.25
			if invalid=="one_hand":b.y=1.25
			fired=motion.sample(1.0/90,"dance",head.global_transform,Transform3D(Basis.IDENTITY,a),Transform3D(Basis.IDENTITY,b),true,hands) or fired
		check(not fired,"Dance rejects "+invalid)
	main.entertainer=null
	performer.free()
	# Native two-fist creature gesture competes with the actual datapad hold.
	var pet_app:=PetFixture.App.new();root.add_child(pet_app);pet_app.inventory=PetFixture.Bag.new();pet_app.add_child(pet_app.inventory)
	var vehicle:=Pets.Vehicle.new();pet_app.add_child(vehicle);vehicle.body=body;vehicle.origin=rig;vehicle.head=head;vehicle.left=left;vehicle.right=right
	var pet_host:=Pets.Host.new();pet_app.add_child(pet_host);pet_host.app=pet_app;pet_host.vehicles=vehicle
	var handler:=preload("res://pets/creature_handler.gd").new();pet_host.add_child(handler);pet_host.creature_handler=handler;handler.setup(pet_host);handler.set_process(false);handler.set_physics_process(false)
	main.pets=pet_host
	vehicle.state={"pets":[{"owned":true,"creature_handler":{"embolden":true,"enrage":true}}]}
	left_tracker.set_input("grip",1.0);left_tracker.set_input("trigger",1.0);right_tracker.set_input("grip",1.0);right_tracker.set_input("trigger",1.0)
	for mode in ["ch_embolden","ch_enrage"]:
		handler.reset();vehicle.requests.clear();pad.set_gesture_reserved(false);pad.update_activation(true,0,0,.02)
		left.global_transform=Transform3D(Basis.IDENTITY,Vector3(-.3,2.0 if mode=="ch_enrage" else 1.25,-.4));right.global_transform=Transform3D(Basis.IDENTITY,Vector3(.3,left.position.y,-.4))
		for frame in range(180):
			pet_host.allowed=not pad.is_open
			handler._physics_process(1.0/90)
			pad.set_gesture_reserved(main.gameplay_gesture_reserved());pad.update_activation(true,1,1,1.0/90)
		check(vehicle.requests.filter(func(row):return row.action==mode).size()==1,mode+" survives shorter datapad hold and dispatches once")
		check(not pad.is_open,mode+" keeps datapad closed while fists remain held")
	main.pets=null
	var report:Dictionary={"test":"gesture_input_arbitration","passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","live_xr":false,"native_transport":"mocked"}
	FileAccess.open("res://../runtime/evidence/gesture-arbitration-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	pet_app.free();host.free();main.free()
	for value in [left_tracker,right_tracker,head_tracker]:XRServer.remove_tracker(value)
	await process_frame
	quit(0 if failures.is_empty() else 1)
