extends SceneTree
## Actual HTTPS/Core3 session using existing dedicated test character; no rendering/XR.
class Stage extends Node3D:
	var current_cell:Dictionary={}
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func source_position_at(p:Vector3)->Vector3:return p
var report:Dictionary={"passed":false,"checks":[],"native_execution":true,"XR_tested":false,"rendering":"none"}
var evidence:=""
func check(ok:bool,label:String)->bool:
	report.checks.append({"passed":ok,"label":label});return ok
func _initialize()->void:call_deferred("run")
func run()->void:
	var options:Dictionary={}
	for arg in OS.get_cmdline_user_args():
		var parts:=arg.trim_prefix("--").split("=",true,1)
		if parts.size()==2:options[parts[0]]=parts[1]
	evidence=str(options.get("evidence","res://../runtime/evidence/gameplay-core1/native-godot-session.json"))
	var app:=Host.new();root.add_child(app)
	if not check(app.remote_connection.load_profile(str(options.get("profile",""))),"Verified remote profile loads"):finish(app);return
	if not check(app.remote_connection.account in ["nettest_one","nettest_two"],"Only existing dedicated network-test account permitted"):finish(app);return
	app.backend_url=app.remote_connection.base_url;app.datapad_account=app.remote_connection.account
	var roster:Dictionary=await app.api(HTTPClient.METHOD_GET,"/characters?account="+app.datapad_account)
	if not check(roster.get("ok",false) and not roster.get("characters",[]).is_empty(),"Existing native roster available"):finish(app);return
	app.datapad_character_id=str(roster.characters[0].id)
	var entered:Dictionary=await app.api(HTTPClient.METHOD_POST,"/enter",{"account":app.datapad_account,"character_id":app.datapad_character_id})
	if not check(entered.get("ok",false) and entered.get("source_location") is Dictionary,"Saved native source location read"):finish(app);return
	var location:Dictionary=entered.source_location
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false)
	app.player.position=Vector3(location.position[0],location.position[1],location.position[2]);app.player.rotation.y=-float(location.heading_radians)
	app.stage=Stage.new();app.add_child(app.stage)
	app.stage.current_cell={"cell_id":str(location.building_id)+":"+str(location.cell_index),"building_object_id":str(location.building_id)}
	var session:=preload("res://scripts/gameplay_session.gd").new();app.add_child(session);session.setup(app);session.set_process(false)
	if not check(await session.start(),"Production Godot gameplay session accepts actual native HAM, posture and sequence"):
		report.error=session.last_error;finish(app);return
	var id:String=session.session_id
	var payload:Dictionary=session.identity()
	for path in ["/inventory/status","/services/status","/crafting/status","/gathering/status"]:
		var state:Dictionary=await app.api(HTTPClient.METHOD_POST,path,payload)
		check(state.get("ok",false) and state.get("backend")=="core3","Original "+path+" remains usable through Godot HTTPS")
	await session.update_pose()
	check(session.live and session.session_id==id and session.sequence>=0,"Mixed RPG reads retain original native connection")
	payload.erase("session_id");payload.live_session_id=id;payload.request_id=Crypto.new().generate_random_bytes(16).hex_encode()
	var saved:Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/logout",payload)
	check(saved.get("ok",false) and saved.get("saved",false) and saved.get("session_closed",false),"Actual native location saved before connection closes")
	session.reset()
	report.passed=report.checks.all(func(row):return row.passed)
	finish(app)
func finish(app:Node)->void:
	app.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(evidence,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if report.passed else 1)
