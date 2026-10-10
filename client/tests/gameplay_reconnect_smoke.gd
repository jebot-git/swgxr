extends SceneTree
## Production disconnect/reconnect UI and request gate, with native placement mocked.
class Host extends "res://scripts/main.gd":
	var reconnect_ok:=false
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func update_buttons()->void:pass
	func ensure_gameplay_session()->bool:
		await get_tree().process_frame
		gameplay_session.live=reconnect_ok
		if reconnect_ok:gameplay_session.session_id="new-owner"
		return reconnect_ok
class Body extends CharacterBody3D:
	var active:=true
class Session extends Node:
	var live:=false
	var busy:=false
	var session_id:="old-owner"
	var last_error:="Native connection lost"
	var pending_transport:Dictionary={}
	var player_state:Dictionary={"position":[4,5,6],"zone":"tatooine"}
class Placement extends RefCounted:
	var received:Dictionary={}
	func place(_host:Node,destination:Dictionary)->Dictionary:
		received=destination.duplicate(true)
		return {"ok":true}
class Loader extends Node:
	func begin(_message:String)->void:pass
	func finish()->void:pass
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.player=Body.new();app.add_child(app.player)
	app.stage=Node3D.new();app.add_child(app.stage)
	app.gameplay_session=Session.new();app.add_child(app.gameplay_session)
	app.menu=PanelContainer.new();app.add_child(app.menu);app.menu.hide()
	app.resume_button=Button.new();app.add_child(app.resume_button)
	app.status=Label.new();app.add_child(app.status)
	app.loading_screen=Loader.new();app.add_child(app.loading_screen)
	app.medical_placement=Placement.new();app.world_ready=true
	app.gameplay_connection_lost("Test disconnect")
	check(app.menu.visible and not app.player.active and app.resume_button.text=="Reconnect","Connection loss freezes locomotion and exposes explicit reconnect")
	check(not app.try_background_poll("scout"),"Lost owner cannot poll legacy services")
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/vehicles/activate",{})
	check(response.get("session_unavailable",false) and app.api_requests_in_flight==0,"Deed request is blocked locally without a native owner")
	await app.reconnect_gameplay()
	check(app.menu.visible and not app.gameplay_session.live and not app.loading_stage and app.world_ready,"Failed reconnect leaves a retryable menu")
	app.reconnect_ok=true
	await app.reconnect_gameplay()
	check(app.gameplay_session.session_id=="new-owner" and app.medical_placement.received==app.gameplay_session.player_state,"Reconnect places only freshly confirmed native location")
	check(not app.menu.visible and app.player.active and app.player.is_physics_processing() and app.datapad_epoch==1,"Successful reconnect restores movement and invalidates dependent service state")
	app.free()
	print(JSON.stringify({"checks":checks,"errors":errors,"native":"mocked","renderer":"dummy","xr":"off"}))
	quit(0 if errors.is_empty() else 1)
