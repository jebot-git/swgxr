extends SceneTree
## Explicit deployment probe: one dedicated generated account, no character creation.
## Password and opaque sessions remain memory-only and are never written to evidence.
const Connection=preload("res://scripts/remote_connection.gd")
var connection:=Connection.new()
var checks: Array=[]
var failures: Array[String]=[]
var requests: Array=[]
var registration_attempts:=0
var portable_store=preload("res://scripts/portable_login_store.gd").new()
var saved_account:=""
var saved_token:=""
func _initialize() -> void:call_deferred("run")
func check(condition: bool,label: String) -> bool:
	checks.append({"passed":condition,"label":label})
	if not condition:failures.append(label)
	return condition
func request(path: String,method: HTTPClient.Method=HTTPClient.METHOD_GET,payload: Dictionary={}) -> Dictionary:
	var http:=HTTPRequest.new();root.add_child(http);http.timeout=45
	var prepared: Dictionary=connection.apply_to(http,connection.base_url,path,payload)
	if not prepared.get("ok",false):http.queue_free();return {"ok":false,"status":0}
	var start:=Time.get_ticks_msec()
	var error:=http.request(connection.base_url+path,prepared.headers,method,JSON.stringify(payload) if method!=HTTPClient.METHOD_GET else "")
	if error!=OK:http.queue_free();return {"ok":false,"status":0}
	var response: Array=await http.request_completed
	http.queue_free()
	var status:=int(response[1])
	requests.append({"path":path.get_slice("?",0),"status":status,"milliseconds":Time.get_ticks_msec()-start,"transport_ok":response[0]==HTTPRequest.RESULT_SUCCESS})
	if response[0]!=HTTPRequest.RESULT_SUCCESS:return {"ok":false,"status":status}
	var parsed: Variant=JSON.parse_string(response[3].get_string_from_utf8())
	var result: Dictionary=parsed if parsed is Dictionary else {}
	result.ok=status>=200 and status<300;result.status=status
	return result
func exercise() -> void:
	var crypto:=Crypto.new()
	var account:="authprobe_gd_"+crypto.generate_random_bytes(5).hex_encode()
	var password:=crypto.generate_random_bytes(24).hex_encode()
	registration_attempts+=1
	var result:=await request("/auth/register",HTTPClient.METHOD_POST,{"account":account,"password":password})
	if not check(result.get("ok",false) and result.get("account")==account,"Single registration creates dedicated auth account"):return
	if not check(connection.accept_session(result),"Registration returns valid in-memory account session"):return
	result=await request("/auth/session")
	if not check(result.get("ok",false) and result.get("account")==account,"Verified HTTPS session resolves original account"):return
	result=await request("/characters?account="+account)
	if not check(result.get("ok",false) and result.get("backend")=="core3" and result.get("characters") is Array,"Authenticated account reaches original native CoreCU roster"):return
	if not check(result.characters.is_empty(),"Fresh dedicated account has no characters"):return
	result=await request("/auth/logout",HTTPClient.METHOD_POST,{})
	if not check(result.get("ok",false) and result.get("logged_out",false),"Explicit logout revokes first opaque session"):return
	result=await request("/auth/session")
	if not check(result.get("status")==401,"Revoked session is rejected with401"):return
	connection.clear_session()
	result=await request("/auth/login",HTTPClient.METHOD_POST,{"account":account,"password":password})
	password=""
	if not check(result.get("ok",false) and result.get("account")==account and connection.accept_session(result),"Password login restores same account using a new session"):return
	result=await request("/auth/session")
	check(result.get("ok",false) and result.get("account")==account,"Relogged session validates through same HTTPS endpoint")
	result=await request("/auth/remember",HTTPClient.METHOD_POST,{})
	if not check(result.get("ok",false) and portable_store.valid_token(result.get("remember_token")),"Live server issues portable remembered credential"):return
	saved_account=account;saved_token=result.remember_token
	portable_store.path="user://remote-auth-probe-"+str(OS.get_process_id())+".json"
	if not check(portable_store.save_login(connection.base_url,account,result).get("ok",false),"Production store persists token privately"):return
	result=await request("/auth/logout",HTTPClient.METHOD_POST,{})
	if not check(result.get("ok",false),"Normal sign-out succeeds with remembered credential retained"):return
	connection.clear_session()
	var reopened=preload("res://scripts/portable_login_store.gd").new();reopened.path=portable_store.path
	var recovered:Dictionary=reopened.load_login(connection.base_url,account)
	if not check(recovered.get("found",false),"Fresh store instance loads remembered credential"):return
	result=await request("/auth/resume",HTTPClient.METHOD_POST,{"account":account,"remember_token":recovered.remember_token})
	recovered.clear()
	if not check(result.get("ok",false) and connection.accept_session(result),"Persisted credential resumes live HTTPS account"):return
	result=await request("/auth/session")
	check(result.get("ok",false) and result.get("account")==account,"Resumed session resolves same account")
	result=await request("/auth/forget",HTTPClient.METHOD_POST,{"account":account,"remember_token":saved_token})
	if not check(result.get("ok",false),"Forget revokes saved credential on live server"):return
	result=await request("/auth/resume",HTTPClient.METHOD_POST,{"account":account,"remember_token":saved_token})
	check(result.get("status")==401,"Revoked portable credential cannot sign in again")

func run() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		var parts:=argument.trim_prefix("--").split("=",true,1)
		if parts.size()==2:options[parts[0]]=parts[1]
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(str(options.get("profile",""))))
	var endpoint: Dictionary={}
	if parsed is Dictionary:endpoint={"base_url":parsed.get("base_url"),"ca_certificate":parsed.get("ca_certificate")}
	parsed=null
	if check(connection.configure(endpoint),"Pinned endpoint and CA loaded without legacy credential"):
		await exercise()
		if not saved_token.is_empty():
			var revoked:=await request("/auth/forget",HTTPClient.METHOD_POST,{"account":saved_account,"remember_token":saved_token})
			check(revoked.get("ok",false),"Probe cleanup confirms remembered credential revoked")
			saved_token=""
			DirAccess.remove_absolute(portable_store.path)
		if connection.authenticated:
			var cleanup:=await request("/auth/logout",HTTPClient.METHOD_POST,{})
			check(cleanup.get("ok",false) or cleanup.get("status")==401,"Probe leaves no usable opaque session")
		connection.clear_session()
	var report: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"requests":requests,"registration_attempts":registration_attempts,"endpoint":connection.base_url,"native_character_creation":false,"passwords_persisted":false,"temporary_portable_token_revoked_and_removed":saved_token.is_empty(),"xr":"off","transport":"actual Godot verified HTTPS"}
	if options.has("evidence"):
		var file:=FileAccess.open(str(options.evidence),FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify({"passed":report.passed,"checks":checks.size(),"failures":failures,"registration_attempts":registration_attempts,"xr":"off"}))
	quit(0 if failures.is_empty() else 1)
