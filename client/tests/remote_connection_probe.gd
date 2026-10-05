extends SceneTree
## Authenticated read-only real-endpoint probe; never initializes the game or XR.
const Connection=preload("res://scripts/remote_connection.gd")
var connection:=Connection.new()
func _initialize() -> void: call_deferred("run")
func fetch(path: String) -> Dictionary:
	var request:=HTTPRequest.new();root.add_child(request);request.timeout=20
	var configuration: Dictionary=connection.apply_to(request,connection.base_url,path)
	if not configuration.get("ok",false): request.queue_free();return {"ok":false,"error":configuration.get("error","Transport setup failed")}
	var error:=request.request(connection.base_url+path,configuration.headers,HTTPClient.METHOD_GET)
	if error!=OK: request.queue_free();return {"ok":false,"error":"HTTP request could not start"}
	var result: Array=await request.request_completed
	request.queue_free()
	if result[0]!=HTTPRequest.RESULT_SUCCESS: return {"ok":false,"error":"Verified HTTPS transport failed","transport_result":int(result[0])}
	var parsed: Variant=JSON.parse_string(result[3].get_string_from_utf8())
	if not parsed is Dictionary: return {"ok":false,"error":"Core3 response is not a JSON object"}
	parsed.ok=int(result[1])>=200 and int(result[1])<300
	return parsed
func run() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		var pieces:=argument.trim_prefix("--").split("=",true,1)
		if pieces.size()==2: options[pieces[0]]=pieces[1]
	var report: Dictionary={"passed":false,"transport":"actual Godot HTTPS with configured CA and hostname/IP SAN validation","xr":"disabled","read_only":true}
	if not connection.load_profile(str(options.get("profile",""))):
		report.error=connection.error
	else:
		report.endpoint=connection.base_url
		var health:=await fetch("/health")
		report.health_http_ok=bool(health.get("ok",false))
		report.native_ready=health.get("backend","")=="core3" and health.get("core3",{}) is Dictionary and bool(health.get("core3",{}).get("ready",false))
		if report.health_http_ok and report.native_ready:
			var characters:=await fetch("/characters?account="+connection.account.uri_encode())
			report.characters_http_ok=bool(characters.get("ok",false))
			report.native_character_list=characters.get("backend","")=="core3" and characters.get("characters") is Array
			report.character_count=characters.get("characters",[]).size() if characters.get("characters") is Array else 0
			report.passed=report.characters_http_ok and report.native_character_list
		else: report.error="Remote native Core3 readiness was not confirmed."
	if options.has("evidence"):
		var output:=FileAccess.open(str(options.evidence),FileAccess.WRITE)
		if output!=null: output.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if report.passed else 1)
