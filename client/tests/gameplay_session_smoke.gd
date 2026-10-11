extends SceneTree
## Persistent lifecycle/poll scheduling fixtures; no native or headset claim.
class Vehicles extends Node:
	var driving:=false
	var observed:=0
	func seated()->bool:return driving
	func drive_payload()->Dictionary:return {"held":true,"throttle":.5,"steer":-.25}
	func observe(_state:Dictionary)->void:observed+=1
class Medic extends Node:
	func tracked_pose()->Dictionary:return {"tracked":true,"hand":[1,2,3],"held":true}
class GuardRig extends Node:
	var value:Dictionary={"mode":"none"}
	var feedback_count:=0
	func guard_payload(_app:Node,_weapon:Dictionary)->Dictionary:return value.duplicate(true)
	func guard_feedback(_value:Dictionary)->void:feedback_count+=1
class Stage extends Node3D:
	var current_cell:Dictionary={"cell_id":"98:2","building_object_id":"98"}
class Host extends Node:
	var datapad_account:="fixture"
	var datapad_character_id:="123"
	var api_requests_in_flight:=0
	var world_ready:=true
	var session_leaving:=false
	var player:Node3D
	var stage:Stage
	var vehicles:Vehicles
	var medic:Medic
	var combat_rig:GuardRig
	var asset_status:Label
	var calls:Array=[]
	var response:Dictionary={"ok":true,"source_kind":"core3_gameplay_session","character_id":"123","session_id":"native-one","session_live":true,"sequence":0,"snapshot":{"vehicles":{},"player":{"ham":[900,800,700],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":0,"dead":false,"incapacitated":false,"shock_wounds":0}}}
	func source_position_at(p:Vector3)->Vector3:return Vector3(100+p.x,p.y,200-p.z)
	func api(_method:HTTPClient.Method,path:String,body:Dictionary={}) -> Dictionary:
		calls.append({"path":path,"payload":body.duplicate(true)})
		await get_tree().process_frame
		return response.duplicate(true)
var errors:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(20).timeout.connect(func():quit(2))
	call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.player=Node3D.new();app.add_child(app.player);app.player.position=Vector3(4,2,3);app.player.rotation.y=.3
	app.stage=Stage.new();app.add_child(app.stage)
	app.vehicles=Vehicles.new();app.add_child(app.vehicles)
	app.medic=Medic.new();app.add_child(app.medic)
	app.asset_status=Label.new();app.add_child(app.asset_status)
	var session:=preload("res://scripts/gameplay_session.gd").new();app.add_child(session);session.setup(app);session.set_process(false)
	check(await session.start(),"Normal RPG session starts without a weapon or combat rig")
	check(app.calls[0].path=="/session/start" and not app.calls[0].payload.has("session_id"),"Start uses owned account/character instead of guessed session")
	var payload:Dictionary=app.calls[0].payload
	check(payload.position==[104.0,2.0,197.0] and payload.building_id=="98" and payload.cell_index==2 and is_equal_approx(payload.heading_radians,-.3),"Persistent session uses original source location, interior, heading")
	check(await session.start() and app.calls.size()==1,"Repeated start reuses confirmed connection")
	app.vehicles.driving=true
	await session.update_pose()
	check(app.calls.back().payload.vehicle_controls==app.vehicles.drive_payload() and session.next_update<=.25,"Seated update carries original vehicle controls within watchdog cadence")
	check(app.calls.back().payload.medic_pose==app.medic.tracked_pose(),"Normal heartbeat includes existing tracked medic pose for native drag continuity")
	check(app.calls.back().payload.session_id=="native-one" and app.vehicles.observed==2,"Updates keep native identity and consume original vehicle state")
	session.busy=true;session._process(.3)
	check(session.next_update<=0,"Heartbeat clock includes in-flight latency")
	session.busy=false
	app.vehicles.driving=false
	app.combat_rig=GuardRig.new();app.add_child(app.combat_rig)
	app.combat_rig.value={"mode":"boxing"}
	await session.update_pose()
	check(app.calls.back().payload.guard_pose.mode=="boxing" and session.next_update<=.35,"Held guard sends through owned native session at guard cadence")
	var before:=app.calls.size()
	session._process(.4)
	await process_frame
	check(app.calls.size()==before+1 and session.last_guard_mode=="boxing","Stationary guard refresh bypasses idle heartbeat suppression")
	app.combat_rig.value={"mode":"none"};session.next_update=1
	before=app.calls.size();session._process(.01)
	await process_frame
	check(app.calls.size()==before+1 and app.calls.back().payload.guard_pose=={"mode":"none"},"Lowering guard sends release without waiting for normal cadence")
	app.vehicles.driving=false;session.last_position=app.player.global_position
	session.last_confirmed_ms=Time.get_ticks_msec()-250;session.next_update=0
	before=app.calls.size();session._process(.01);await process_frame
	check(app.calls.size()==before+1,"Stationary player refreshes authoritative world within 250ms rather than starving NPC movement for three seconds")
	check(app.combat_rig.feedback_count>=3,"Native receipts feed guard feedback")
	var foreign:Dictionary=app.response.duplicate(true);foreign.session_id="another"
	check(not session.accept(foreign) and session.session_id=="native-one","Unsolicited update cannot replace session identity")
	foreign=app.response.duplicate(true);foreign.character_id="foreign"
	check(not session.accept(foreign,true),"Explicit reconnect cannot accept another character")
	session.live=false;app.response.session_id="native-reconnected"
	check(await session.start() and session.session_id=="native-reconnected","Explicit reconnect accepts new same-character session after server loss")
	app.response={"ok":false,"error_code":"backend_busy"};session.last_confirmed_ms=Time.get_ticks_msec()
	await session.update_pose()
	check(session.live,"Transient busy response retains session without fabricating a new confirmation")
	var lost:Array=[];session.connection_lost.connect(func(message):lost.append(message))
	app.response={"ok":false,"error_code":"backend_busy","error":"busy too long"};session.last_confirmed_ms=Time.get_ticks_msec()-20000;await session.update_pose()
	check(lost.size()==1 and str(lost[0])=="busy too long","Lost session preserves recovery error instead of a misleading envelope error")
	check(not session.live and not app.asset_status.text.is_empty() and app.asset_status.text==session.last_error,"Persistent lost connection is visible")
	session.live=true
	check(not session.accept_native_response({"ok":true,"session_live":true,"error_code":"native_response_timeout"}) and session.last_error=="native_response_timeout","HTTP 200 native timeout preserves its actual error without accepting missing authority")
	session.reset();check(session.session_id.is_empty() and not session.live and not session.busy,"Logout reset fences outstanding identity")
	var budget:=preload("res://scripts/native_poll_budget.gd").new();budget.interval_ms=1000
	check(budget.admit("a",0,false),"First optional status receives budget")
	check(not budget.admit("b",100,true) and not budget.admit("c",200,false),"Active requests and spacing defer optional reads")
	check(not budget.admit("c",1000,false) and budget.admit("b",1000,false),"Oldest still-active caller receives fair grant")
	check(budget.admit("d",3001,false),"Inactive queued family expires instead of blocking all polls forever")
	budget.reset();check(budget.waiting.is_empty() and budget.last_seen.is_empty(),"Character change discards poll ownership")
	app.free()
	var report:Dictionary={"checks":checks,"errors":errors,"mocked":true,"XR_tested":false}
	FileAccess.open("res://../runtime/evidence/gameplay-core1/gameplay-session-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
