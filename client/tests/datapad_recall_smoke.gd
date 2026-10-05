extends SceneTree
class Host extends Node:
	var datapad:Node3D
	var datapad_epoch:=1
	var datapad_character_id:="42"
class Feedback extends RefCounted:
	var blocked:=false
	func combat_blocked()->bool:return blocked
class Body extends Node:
	var active:=true
	var tracked:=true
	var feedback:=Feedback.new()
	func combat_tracking_context()->Dictionary:return {"tracked":tracked}
class VehicleMock extends Node3D:
	var body:=Body.new()
	var state:Dictionary={}
	var busy:=false
	var age:=0.0
	var left:XRController3D
	var right:XRController3D
	var requests:Array=[]
	func native_session()->Node:return self
	func seated()->bool:return false
	func available(_side:String)->bool:return true
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func source(p:Vector3)->Array:return [p.x,p.y,-p.z]
	func request(action:String,detail:Dictionary={})->void:requests.append({"action":action,"detail":detail})
var errors:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	host.datapad=Node3D.new();host.add_child(host.datapad)
	# The real wrist UI is mounted under a thin Node3D host for this interaction test.
	var pad=preload("res://scripts/xr_datapad.gd").new();host.datapad.free();host.datapad=pad;host.add_child(pad)
	pad.set_process(false);pad.ui=preload("res://scripts/datapad_ui.gd").new();pad.add_child(pad.ui);pad.ui.build_ui()
	var vehicle:=VehicleMock.new();host.add_child(vehicle);vehicle.add_child(vehicle.body)
	var pets=preload("res://pets/controller.gd").new();host.add_child(pets);pets.setup(host,vehicle);pets.set_process(false)
	pad.ui.droid_action_requested.connect(pets.request_entry)
	var signals:Array=[]
	pad.ui.call_vehicle_requested.connect(func(e):signals.append(["call",e.id]))
	pad.ui.recall_vehicle_requested.connect(func(e):signals.append(["recall",e.id]))
	pad.ui.set_entries([{"id":"77","name":"Vehicle","category":"vehicles","spawned":false}]);pad.ui.select_category("vehicles");pad.ui.vehicle_button.pressed.emit()
	check(signals==[["call","77"]],"Stored vehicle button requests native call")
	pad.ui.set_entries([{"id":"77","name":"Vehicle","category":"vehicles","spawned":true}]);pad.ui.select_category("vehicles");pad.ui.vehicle_button.pressed.emit()
	check(signals.back()==["recall","77"] and not pad.ui.vehicle_button.disabled and pad.ui.vehicle_button.text=="Recall vehicle","Called vehicle has enabled Recall action")
	var row:Dictionary={"id":"99","device_id":"88","pet_id":"99","name":"Helper R2","template":"object/mobile/nhelper_droid.iff","position":[0,0,0],"radius":.3,"height":1.0,"owned":true,"in_combat":false,"spawned":true}
	var entry:=row.duplicate(true);entry.id="88";vehicle.state={"pet_datapad":[entry],"pets":[row]}
	pets.merge_datapad();pad.ui.select_category("pets")
	check(pad.ui.selected_entry.id=="88" and pad.ui.vehicle_button.text=="Recall droid","Original native helper control device becomes actionable")
	pad.ui.vehicle_button.pressed.emit()
	check(vehicle.requests.back()=={"action":"pet_recall","detail":{"device_id":"88"}},"Droid button dispatches native recall with actual owned device")
	vehicle.state.pet_datapad[0].spawned=false;pets.merge_datapad();pad.ui.vehicle_button.pressed.emit()
	check(vehicle.requests.back().action=="pet_call" and pad.ui.vehicle_button.text=="Call droid","Stored droid button dispatches native call")
	check(pets.touches(row,Vector3(.2,.7,0)) and not pets.touches(row,Vector3(1,.7,0)) and not pets.touches(row,Vector3(0,2,0)),"Droid contact follows bounded native radius and height")
	var trackers:Array=[]
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side;tracker.set_pose("default",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);tracker.set_input("grip",0.0);XRServer.add_tracker(tracker);trackers.append(tracker)
		var hand:=XRController3D.new();hand.tracker=side;host.add_child(hand);hand.position=Vector3(-.2 if side=="left" else .2,.7,0);vehicle.set(side,hand)
	pets.reset();pets.set_allowed(true);pets.pending_until=0;vehicle.requests.clear();pets._process(.016);trackers[0].set_input("grip",.9);pets._process(.016)
	check(vehicle.requests.is_empty(),"One hand cannot recall a droid")
	trackers[1].set_input("grip",.9);pets._process(.016)
	check(vehicle.requests.size()==1 and vehicle.requests[0].action=="pet_store" and vehicle.requests[0].detail.has("left") and vehicle.requests[0].detail.has("right"),"Both tracked grips submit native contact evidence")
	pets._process(.016);check(vehicle.requests.size()==1,"Holding both grips does not repeatedly recall")
	check(vehicle.state.pets.size()==1,"Pending gesture never locally deletes an unconfirmed droid")
	trackers[0].set_input("grip",0.0);pets._process(.016);vehicle.state.pets[0].owned=false;trackers[0].set_input("grip",.9);pets._process(.016)
	check(vehicle.requests.size()==1,"Other players' droids cannot be grabbed")
	vehicle.state.pets[0].owned=true
	for reason in ["pause","tracking","life","stale","menu"]:
		trackers[0].set_input("grip",0.0);trackers[1].set_input("grip",0.0);pets._process(.016)
		match reason:
			"pause":vehicle.body.active=false
			"tracking":vehicle.body.tracked=false
			"life":vehicle.body.feedback.blocked=true
			"stale":vehicle.age=9
			"menu":pets.set_allowed(false)
		trackers[0].set_input("grip",.9);trackers[1].set_input("grip",.9);pets._process(.016)
		check(vehicle.requests.size()==1,"No droid recall during "+reason)
		vehicle.body.active=true;vehicle.body.tracked=true;vehicle.body.feedback.blocked=false;vehicle.age=0;pets.set_allowed(true);pets._process(.016)
		check(vehicle.requests.size()==1,"Restored "+reason+" requires a new release/regrip")
	for tracker in trackers:XRServer.remove_tracker(tracker)
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","native_execution":false,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/core2/datapad-recall-ui.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));host.free();quit(0 if errors.is_empty() else 1)
