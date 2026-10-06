extends SceneTree
## Actual saved Core3 state; transport replay is bounded and never sends requests.
const Capture=preload("res://tests/creature_handler_capture.gd")
class Vehicle extends "res://vehicles/controller.gd":
	func observe(value:Dictionary)->void:state=value;age=0
	func native_session()->Node:return null
	func seated()->bool:return false
class Stage extends Node3D:
	var current_cell:Dictionary={}
class App extends Node:
	var datapad_epoch:=1
	var datapad_character_id:=""
	var datapad_account:="recorded"
	var stage:Stage
	var datapad:Node
	var response:Dictionary={}
	func source_position_at(point:Vector3)->Vector3:return point
	func api(_method:int,_path:String,_payload:Dictionary)->Dictionary:
		# main.api adds HTTP success to decoded native bodies in production.
		var value:=response.duplicate(true);value.ok=true;value.http_status=200;return value
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/creature-handler-native.json"))
	var app:=App.new();root.add_child(app);app.stage=Stage.new();app.add_child(app.stage)
	var vehicle:=Vehicle.new();app.add_child(vehicle);vehicle.app=app;vehicle.set_process(false);vehicle.set_physics_process(false);vehicle.body=CharacterBody3D.new();app.add_child(vehicle.body);vehicle.head=Camera3D.new();app.add_child(vehicle.head)
	var host:=Capture.Host.new();app.add_child(host);host.app=app;host.vehicles=vehicle
	var handler:=preload("res://pets/creature_handler.gd").new();app.add_child(handler);handler.setup(host);handler.set_process(false);handler.set_physics_process(false)
	var commands:=preload("res://pets/commands.gd").new()
	var observed:Dictionary={"pending":false,"succeeded":false,"failed_training":false,"trained_mount":false,"buff":false}
	var success_request:="";var records:=0
	for row:Dictionary in evidence.responses.slice(0,160):
		var reply:Dictionary=row.get("response",{});var native:Dictionary=reply.get("state",{})
		if native.get("source_kind","")!="core3_vehicles":continue
		app.datapad_character_id=str(native.character_id);app.response=reply
		await vehicle.request(str(row.path).get_file(),{})
		handler.observe_outcome();records+=1
		check(handler.state()==native.get("creature_handler",{}),"Saved authoritative CH schema reaches handler")
		var taming:Dictionary=handler.state().get("taming",{})
		var phase:=str(taming.get("state",""))
		if phase=="pending" and not observed.pending:
			observed.pending=true;handler.show_progress({"progress":0,"latched":true},"tame",{},true,taming,true)
			check(handler.label.text.contains("Core3 taming") and not handler.label.text.contains("tamed and added"),"Real pending receipt never claims tame completion")
		if phase=="succeeded" and not observed.succeeded:
			observed.succeeded=true;success_request=str(taming.request_id)
			check(handler.status.contains("Core3 confirmed") and not str(taming.device_id) in ["","0"],"Native owned device is required before success text")
		if phase=="failed" and str(taming.get("request_id",""))==success_request and not success_request.is_empty():
			check(not handler.status.begins_with("Taming failed"),"Stored/relogged pet cannot revoke the same completed tame receipt")
		var mutation:Dictionary=reply.get("mutation",{})
		if mutation.get("learned")==false:
			observed.failed_training=true;check(handler.status.contains("not learned"),"Actual failed probability roll visibly reports retry instead of learned command")
		for pet:Dictionary in native.get("pets",[]):
			var available:Array=commands.menu_entries(pet)
			var training:Array=pet.get("creature_handler",{}).get("train_commands",[])
			check(available.size()==pet.get("commands",[]).size()+training.size(),"Native trained commands and remaining trainable commands map to radial exactly")
			if pet.get("pet_kind","")=="droid":check(training.is_empty() and not pet.get("creature_handler",{}).get("train_mount",false),"Native droids never gain creature mount training")
			if pet.get("creature_handler",{}).get("trained_as_mount",false):
				observed.trained_mount=true;check(not pet.creature_handler.train_mount,"Original completed mount flag removes training gesture eligibility")
		if mutation.get("action","") in ["ch_embolden","ch_enrage"] and mutation.get("success",false):observed.buff=true
	for field in observed:check(observed[field],"Recorded native coverage present: "+field)
	check(not handler.taming_pending({"state":"pending","request_id":success_request}),"A stale pending snapshot cannot reopen a completed native tame")
	vehicle.state={"creature_handler":{"taming":{"request_id":"different-failed-request","state":"failed","reason":"New target resisted"}}};handler.observe_outcome()
	check(handler.status.begins_with("Taming failed"),"Terminal success fencing never hides another failed request")
	handler.reset();check(not handler.tame_succeeded and handler.tame_request.is_empty(),"Session reset clears historical tame receipt fence")
	commands.free();app.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"records":records,"source":"recorded real native CH state","native_requests_sent":0,"renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/creature-handler-native-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
