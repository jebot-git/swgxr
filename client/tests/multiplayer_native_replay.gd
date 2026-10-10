extends SceneTree
## Reads captured real two-client native responses. No mock native world, and no
## claim that replay is a new live network or headset session.
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="res://../runtime/evidence/multiplayer-native-world.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):path=argument.trim_prefix("--capture=")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary and parsed.get("native_execution",false),"Capture records actual CoreCU execution")
	var states:Dictionary={}
	var peers:=0
	var events:=0
	for receipt:Dictionary in parsed.get("responses",[]):
		if receipt.get("path")!="/session/sync":continue
		var response:Dictionary=receipt.response
		if not response.get("ok",false):continue
		var key:=str(response.session_id)
		if not states.has(key):states[key]=preload("res://multiplayer/replication_state.gd").new()
		var state:RefCounted=states[key]
		check(state.accept(response,str(response.character_id),key,int(response.sequence)),"Native sync envelope accepted: "+state.error)
		peers+=state.players.size();events+=state.events.size()
	check(states.size()>=2 and peers>=2,"Mutual native visibility survives actual Godot replication validator")
	var report:Dictionary={"checks":checks,"errors":errors,"captured_native_replay":true,"native_sessions":states.size(),"remote_player_observations":peers,"native_events":events,"live_xr":false}
	FileAccess.open("res://../runtime/evidence/multiplayer-native-client-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
