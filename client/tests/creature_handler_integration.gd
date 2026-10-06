extends SceneTree
const Fixture=preload("res://tests/pet_commands_smoke.gd")
class Host extends Fixture.Host:
	var commands:Node3D
	var creature_handler:Node3D
class Vehicle extends Fixture.Vehicle:
	var status:="Native action accepted"
	func seated()->bool:return false
	func source(point:Vector3)->Array:return [point.x,point.y,-point.z]
	func request(action:String,detail:Dictionary={})->void:
		super(action,detail)
		if action=="ch_status":age=0
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func tracker(side:String)->XRControllerTracker:
	var value:=XRControllerTracker.new();value.type=XRServer.TRACKER_CONTROLLER;value.name=side+"_hand";value.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	value.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(0,1.2,-.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);value.set_input("grip",0.0);value.set_input("trigger",0.0);value.set_input("primary",Vector2.ZERO);XRServer.add_tracker(value);return value
func run()->void:
	var left:=tracker("left");var right:=tracker("right")
	var head:=XRPositionalTracker.new();head.type=XRServer.TRACKER_HEAD;head.name="head";head.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head)
	var app:=Fixture.App.new();root.add_child(app);app.inventory=Fixture.Bag.new();app.add_child(app.inventory);app.multiplayer_sync=Fixture.Sync.new();app.add_child(app.multiplayer_sync);app.multiplayer_sync.entities=Fixture.World.new();app.add_child(app.multiplayer_sync.entities)
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(origin)
	var body=origin.get_node("PlayerBody");body.active=true;body.set_physics_process(false)
	var vehicle:=Vehicle.new();app.add_child(vehicle);vehicle.body=body;vehicle.origin=origin;vehicle.head=origin.get_node("XRCamera3D");vehicle.left=origin.get_node("LeftHand");vehicle.right=origin.get_node("RightHand")
	var host:=Host.new();app.add_child(host);host.app=app;host.vehicles=vehicle
	host.commands=preload("res://pets/commands.gd").new();host.add_child(host.commands);host.commands.setup(host);host.commands.set_physics_process(false);host.commands.set_process(false)
	var handler:=preload("res://pets/creature_handler.gd").new();host.add_child(handler);host.creature_handler=handler;handler.setup(host);handler.set_process(false);handler.set_physics_process(false)
	var animal:=Fixture.Actor.new();app.add_child(animal);animal.position=Vector3(0,0,-2);animal.scale=Vector3(1,1.4,1);app.multiplayer_sync.entities.actors["42"]=animal
	vehicle.state={"creature_handler":{"candidates":[{"id":"42","name":"Native baby","eligible":true,"can_tame":true}],"taming":{}},"pets":[]}
	await process_frame
	vehicle.head.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
	for i in range(1020):
		var t:float=i/90.0;var half:float=.18+.13*cos(t*TAU*1.7)
		vehicle.left.global_position=Vector3(-half,1.25,-.4);vehicle.right.global_position=Vector3(half,1.25,-.4)
		vehicle.age+=1.0/90;handler._process(1.0/90);handler._physics_process(1.0/90)
	check(vehicle.requests.filter(func(row):return row.action=="ch_status").size()>=5,"Production status polling keeps a ten-second hold fresh")
	check(vehicle.requests.filter(func(row):return row.action=="ch_tame").size()==1,"Actual tracked controller loop emits one native tame after motion")
	var tame:Array=vehicle.requests.filter(func(row):return row.action=="ch_tame")
	check(not tame.is_empty() and tame[0].detail.target_id=="42" and str(tame[0].detail.request_id).begins_with("ch-"),"Native tame is bound to selected ID and stable mutation receipt")
	vehicle.state.creature_handler.taming={"state":"pending"}
	for i in range(100):handler._physics_process(1.0/90)
	check(handler.label.text.contains("Core3 taming") and vehicle.requests.filter(func(row):return row.action=="ch_tame").size()==1,"Native asynchronous taming remains pending without reissuing")
	vehicle.state.creature_handler.taming={"request_id":"tame-1","state":"failed","reason":"The creature resisted"};handler.observe_outcome();handler._physics_process(1.0/90)
	check(handler.label.text.contains("Taming failed") and not handler.label.text.contains("tamed and added"),"Native failed tame is displayed without claiming acquisition")
	vehicle.state.creature_handler.taming={"request_id":"tame-2","state":"succeeded"};handler.observe_outcome();handler._physics_process(1.0/90)
	check(handler.label.text.contains("Core3 confirmed"),"Only native succeeded state displays tame success")
	handler.status_until=Time.get_ticks_msec()-1;handler.observe_outcome()
	check(handler.status.is_empty(),"Native outcome text expires rather than remaining forever")
	vehicle.state.creature_handler.taming={};handler.reset();host.allowed=false
	for i in range(100):handler._physics_process(1.0/90)
	check(handler.progress==0 and not handler.claims,"Production global menu/focus gate releases creature input capture")
	host.allowed=true;vehicle.free_hand=false;check(not handler.permitted(),"Weapon or held inventory ownership blocks gestures")
	vehicle.free_hand=true
	var pet:Dictionary={"id":"42","device_id":"82","owned":true,"dead":false,"incapacitated":false,"commands":[],"creature_handler":{"train_commands":[{"command_id":7,"label":"Guard"}],"embolden":true,"enrage":true}}
	vehicle.state.pets=[pet]
	var entries:Array=host.commands.menu_entries(pet)
	check(entries.size()==1 and entries[0].action=="ch_train_command","Native eligible pet training extends existing radial")
	host.commands.state.select(entries[0],"82","42");host.commands.frame(0,Vector2.ZERO,true,{});host.commands.frame(1,Vector2.ZERO,true,{})
	check(vehicle.requests.back().action=="ch_train_command" and vehicle.requests.back().detail.command_id==7,"Training uses native attempt route instead of executing unlearned command")
	handler.status="";handler.progress=.5;handler.selected={}
	handler.show_progress({"progress":.5,"latched":false,"mode":"ch_embolden"},"buff",{},false,{},true)
	check(handler.label.text.contains("Embolden pets"),"Forward-fist progress names the native embolden ability")
	handler.show_progress({"progress":.5,"latched":false,"mode":"ch_enrage"},"buff",{},false,{},true)
	check(handler.label.text.contains("Enrage pets"),"Raised-fist progress names the native enrage ability")
	app.free();XRServer.remove_tracker(left);XRServer.remove_tracker(right);XRServer.remove_tracker(head);await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"mocked XR trackers","controller":"production","native":"mocked transport","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/creature-handler-integration.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
