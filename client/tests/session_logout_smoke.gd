extends SceneTree
## Actual main lifecycle with asynchronous mocked HTTP; no native/GPU/XR claim.
class Host extends "res://scripts/main.gd":
	var response: Dictionary={}
	var calls: Array=[]
	var cleared:=0
	var refreshed:=0
	var quit_requested:=false
	func _ready() -> void:pass
	func _process(_delta: float) -> void:pass
	func update_buttons() -> void:pass
	func refresh_characters() -> void:refreshed+=1
	func api(method: HTTPClient.Method,path: String,body: Dictionary={}) -> Dictionary:
		calls.append({"path":path,"payload":body.duplicate(true),"world_present":world_ready,"in_flight":api_requests_in_flight})
		await get_tree().process_frame
		return response.duplicate(true)
	func clear_character_world() -> void:cleared+=1;world_ready=false
	func stop_live_combat() -> void:
		live_combat_reserved=false
	func quit_application() -> void:quit_requested=true
class Services extends Node3D:
	var zone:="tatooine"
	func identity_payload() -> Dictionary:
		return {"account":"fixture","character_id":"123","zone":zone,"position":[0,0,0],"building_id":"987","cell_index":2,"session_id":"alias"}
class Live extends Node3D:
	var session_id:="native-fixture"
	var resets:=0
	func reset(_reason: String) -> void:resets+=1;session_id=""
class ShipScene extends RefCounted:
	func source(_point:Vector3)->Array:return [1.0,.4,20.0]
class Ship extends Node3D:
	var scene:=ShipScene.new()
	func aboard()->bool:return true
class Player extends CharacterBody3D:
	var active:=true
var checks:=0
var errors: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize() -> void:
	create_timer(25).timeout.connect(func():quit(2))
	call_deferred("run")
func host() -> Host:
	var app:=Host.new();root.add_child(app)
	app.player=Player.new();app.add_child(app.player);app.player.position=Vector3(9,2,10);app.player.rotation.y=.4
	app.stage=Node3D.new();app.add_child(app.stage);app.stage.position=Vector3(3,0,4)
	app.loader.report={"origin":[100,5,200]}
	app.menu=PanelContainer.new();app.add_child(app.menu)
	app.creator=Control.new();app.add_child(app.creator)
	app.status=Label.new();app.add_child(app.status)
	app.services=Services.new();app.add_child(app.services)
	app.world_ready=true;app.datapad_account="fixture";app.datapad_character_id="123"
	return app
func run() -> void:
	var app:=host()
	app.response={"ok":false,"request_timeout":true,"error":"Unconfirmed save"}
	app.api_requests_in_flight=1
	get_tree_timer_release(app)
	await app.leave_character()
	check(app.calls.size()==1 and app.calls[0].in_flight==0,"Already-sent requests drain before position save")
	check(app.calls[0].world_present and app.cleared==0 and app.world_ready,"World is retained after unconfirmed save")
	check(app.calls[0].payload.position==[106.0,7.0,194.0],"Stage local feet convert to original source world coordinates")
	check(app.calls[0].payload.building_id=="987" and app.calls[0].payload.cell_index==2 and not app.calls[0].payload.has("session_id"),"Interior identity is preserved without ambiguous service session alias")
	check(is_equal_approx(float(app.calls[0].payload.heading_radians),-.4),"Saved native heading respects coordinate handedness")
	check(not app.player.is_physics_processing() and not app.logout_payload.is_empty(),"Unconfirmed logout freezes movement and retains retry pose")
	var original: Dictionary=app.calls[0].payload.duplicate(true)
	app.player.position=Vector3(99,99,99)
	app.response={"ok":true,"source_kind":"core3_session_logout","character_id":"123","saved":true,"session_closed":true}
	await app.leave_character()
	check(app.calls[1].payload==original,"Explicit retry retains original save location")
	check(app.cleared==1 and app.refreshed==1 and not app.world_ready and app.logout_payload.is_empty(),"Confirmed logoff returns to roster only after save and close")
	check(app.datapad_account=="fixture" and not app.quit_requested,"Log off does not sign out or quit")
	app.free()
	app=host();app.live_combat=Live.new();app.add_child(app.live_combat);app.live_combat_reserved=true
	app.response={"ok":true,"source_kind":"core3_session_logout","character_id":"wrong","saved":true,"session_closed":true}
	await app.leave_character(true)
	check(not app.quit_requested and app.cleared==0,"Foreign-character acknowledgment cannot quit or clear world")
	check(app.calls[0].payload.live_session_id=="native-fixture","Live logout uses existing native session identity")
	app.response.character_id="123"
	await app.leave_character(true)
	check(app.quit_requested and app.cleared==1 and app.live_combat.resets==1,"Quit saves, detaches acknowledged native session, then exits")
	check(app.refreshed==0,"Quit avoids another character login after native logout")
	app.free()
	app=host();app.services.zone="space_tatooine";app.space=Ship.new();app.add_child(app.space);app.live_combat=Live.new();app.add_child(app.live_combat)
	app.response={"ok":false,"error":"Unconfirmed ship save"}
	await app.leave_character()
	var ship_payload:Dictionary=app.calls.back().payload.duplicate(true)
	check(ship_payload.get("zone","")=="space_tatooine" and Vector3(ship_payload.position[0],ship_payload.position[1],ship_payload.position[2]).is_equal_approx(Vector3(1,.4,20)) and not ship_payload.has("space_logout"),"POB logout sends native space context and local pose through the existing logout protocol")
	check(ship_payload.live_session_id=="native-fixture" and app.space.process_mode==Node.PROCESS_MODE_INHERIT,"Ship logout retains native identity and restores process gate after failure")
	app.response={"ok":true,"source_kind":"core3_session_logout","character_id":"123","saved":true,"session_closed":true}
	await app.leave_character()
	check(app.calls.back().payload==ship_payload and app.cleared==1,"POB logout retries retain native landing request identity")
	app.free()
	app=host();app.world_ready=false
	await app.leave_character(true)
	check(app.quit_requested and app.calls.is_empty(),"Quit from initial menu does not invent a character save")
	app.free()
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"HTTP_mocked":true,"XR_tested":false}
	FileAccess.open("res://../runtime/evidence/gameplay-core1/logout-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
func get_tree_timer_release(app: Host) -> void:
	create_timer(.05).timeout.connect(func():app.api_requests_in_flight=0)
