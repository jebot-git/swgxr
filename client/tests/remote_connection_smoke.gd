extends SceneTree
## Isolated HTTPRequest TLS verification; no game scene, asset loading, or headset.
const Connection=preload("res://scripts/remote_connection.gd")
class ClientHarness extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
var checks:=0
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func perform(connection: RefCounted, path: String) -> Array:
	var request:=HTTPRequest.new();root.add_child(request);request.timeout=5
	var settings: Dictionary=connection.apply_to(request,connection.base_url,path)
	if not settings.get("ok",false): request.queue_free();return [-1,0,PackedStringArray(),PackedByteArray()]
	check(request.max_redirects==0,"Authenticated request never follows redirects")
	var sent:=request.request(connection.base_url+path,settings.headers,HTTPClient.METHOD_GET)
	if sent!=OK: request.queue_free();return [sent,0,PackedStringArray(),PackedByteArray()]
	var result: Array=await request.request_completed
	request.queue_free()
	return result
func run() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		var pieces:=argument.trim_prefix("--").split("=",true,1)
		if pieces.size()==2: options[pieces[0]]=pieces[1]
	var connection:=Connection.new()
	check(connection.load_profile(str(options.get("profile",""))),"Valid isolated HTTPS profile loads")
	if not connection.configured: print(JSON.stringify({"passed":false,"checks":checks,"failures":failures}));quit(1);return
	check(connection.validate_request(connection.base_url,"/health").is_empty(),"Configured-origin health path permitted")
	check(not connection.validate_request("https://untrusted.example:18443","/health").is_empty(),"Credentials cannot attach to a different origin")
	for path in ["//untrusted.example/health","https://untrusted.example/health","/health\r\nInjected: bad","/health#fragment","/\\untrusted.example","/characters?account=other","/characters?account=fixture&account=fixture"]:
		check(not connection.validate_request(connection.base_url,path).is_empty(),"Unsafe or mismatched request rejected")
	check(not connection.validate_request(connection.base_url,"/services/pay",{"account":"other"}).is_empty(),"Mismatched body account rejected")
	check(not connection.validate_request(connection.base_url,"/services/pay",{"text":"x".repeat(17000)}).is_empty(),"Gateway body limit enforced before sending")
	var healthy:=await perform(connection,"/health")
	check(healthy[0]==HTTPRequest.RESULT_SUCCESS and healthy[1]==200,"Original Godot HTTPRequest verifies configured CA and IP SAN")
	var response: Variant=JSON.parse_string(healthy[3].get_string_from_utf8())
	check(response is Dictionary and bool(response.get("authorized",false)),"Per-account bearer reaches only the configured TLS server")
	var redirect:=await perform(connection,"/redirect")
	check(redirect[0]!=HTTPRequest.RESULT_SUCCESS or int(redirect[1]) in [301,302,303,307,308],"Server redirect is surfaced rather than followed")
	var wrong:=Connection.new();check(wrong.load_profile(str(options.get("wrong-san-profile",""))),"Wrong-SAN fixture profile loads trusted CA")
	var rejected:=await perform(wrong,"/health")
	check(rejected[0]!=HTTPRequest.RESULT_SUCCESS,"TLS rejects trusted certificate with wrong IP SAN")
	var unknown:=Connection.new();check(unknown.load_profile(str(options.get("unknown-ca-profile",""))),"Unknown-CA fixture profile loads independently valid CA")
	rejected=await perform(unknown,"/health")
	check(rejected[0]!=HTTPRequest.RESULT_SUCCESS,"TLS rejects server not signed by configured CA")
	var invalid:=Connection.new()
	var value: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.profile)))
	for origin in ["http://127.0.0.1:18080","https://user:secret@127.0.0.1","https://127.0.0.1/path","https://127.0.0.1?token=secret","https://127.0.0.1:0","https://127.0.0.1:65536","https://127.0.0.1\n"]:
		var copy:=value.duplicate(true);copy.base_url=origin
		check(not invalid.configure(copy),"Insecure or non-origin profile endpoint rejected")
	var injected:=value.duplicate(true);injected.token="secret\r\nInjected: value"
	check(not invalid.configure(injected) and not invalid.error.contains("secret"),"Invalid credential rejected without echoing it")
	injected=value.duplicate(true);injected.token="secret\n"
	check(not invalid.configure(injected),"Trailing newline cannot bypass credential validation")
	var client:=ClientHarness.new();root.add_child(client)
	client.args={"connection-profile":str(options.profile)}
	check(client.configure_backend_connection(),"Actual client selects explicit private remote profile")
	check(client.backend_url==connection.base_url and client.args.account==connection.account,"Actual client binds endpoint and account to the profile")
	var main_health: Dictionary=await client.api(HTTPClient.METHOD_GET,"/health")
	check(main_health.get("ok",false) and main_health.get("authorized",false),"Actual main API authenticates verified HTTPS request")
	check(client.api_requests_in_flight==0,"Actual main API clears request accounting after HTTPS completion")
	var forbidden: Dictionary=await client.api(HTTPClient.METHOD_GET,"/characters?account=other")
	check(not forbidden.get("ok",true),"Actual main API refuses mismatched account before transport")
	client.live_combat_reserved=true
	forbidden=await client.api(HTTPClient.METHOD_GET,"/characters?account=fixture")
	check(not forbidden.get("ok",true),"Remote integration preserves persistent live-session legacy RPC guard")
	client.args={"local":true};client.backend_url="http://127.0.0.1:18080"
	check(client.configure_backend_connection() and not client.remote_connection.configured,"Actual client --local bypasses private default profile")
	check(client.backend_url=="http://127.0.0.1:18080","Local override retains loopback endpoint")
	client.args={"local":true,"connection-profile":str(options.profile)}
	check(not client.configure_backend_connection(),"Actual client rejects ambiguous local and remote configuration")
	client.queue_free()
	var result: Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"transport":"actual isolated Godot HTTPS","rendering":"headless dummy; XR disabled"}
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
