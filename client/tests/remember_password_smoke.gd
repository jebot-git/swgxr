extends SceneTree
## Production account UI/main flow + portable files; auth HTTP is mocked.
class Harness extends "res://scripts/main.gd":
	var calls:Array=[]
	var reject_resume:=false
	var reject_forget:=false
	var serial:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func refresh_backend()->void:core3_ready=true;update_buttons()
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if path=="/auth/remember":return {"ok":true,"account":"fixture","remember_token":"swgr_"+"A".repeat(43),"expires_at":Time.get_unix_time_from_system()+86400}
		if path=="/auth/forget":return {"ok":not reject_forget,"forgotten":not reject_forget}
		if path=="/auth/resume" and reject_resume:return {"ok":false,"http_status":401,"error":"Saved login expired or invalid; enter your password"}
		if path=="/auth/logout":return {"ok":true,"logged_out":true}
		serial+=1
		return {"ok":true,"account":"fixture","token":"synthetic-session-"+str(serial),"expires_at":Time.get_unix_time_from_system()+3600}
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(count:=8)->void:
	for i in count:await process_frame
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:="user://portable-login-test-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var source:Dictionary={"base_url":"https://127.0.0.1:18443","ca_certificate":ProjectSettings.globalize_path("res://../runtime/deploy/credentials/ca.pem")}
	var app:=Harness.new();root.add_child(app);app.remote_connection.configure(source);app.backend_url=source.base_url
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false);app.make_ui()
	var panel=app.account_panel;panel.login_preferences_path=folder+"/preferences.cfg";panel.credential_store.path=folder+"/tokens.json";panel.configure(source.base_url)
	panel.account_input.text="fixture";panel.remember_password.set_pressed_no_signal(true)
	await app.authenticate_account("login",{"account":"fixture","password":"synthetic-fixture-password"})
	check(app.account_ready() and not panel.visible,"Password login still enters authenticated menu")
	check(app.calls.size()==2 and app.calls[1].path=="/auth/remember","Remembered credential is issued only after successful password authentication")
	var bytes:=FileAccess.get_file_as_string(panel.credential_store.path)
	check(not bytes.contains("synthetic-fixture-password") and not bytes.contains("synthetic-session"),"Portable data never includes password or gameplay session")
	check(FileAccess.get_unix_permissions(panel.credential_store.path)==384 or OS.get_name()=="Windows","Token file is private on Unix")
	var store=panel.credential_store
	var saved:Dictionary=store.load_login(source.base_url,"fixture")
	check(saved.get("found",false),"Stored portable token can be loaded")
	check(not store.load_login("https://other.invalid","fixture").get("found",false),"Saved login is bound to exact HTTPS origin")
	check(not store.load_login(source.base_url,"other").get("found",false),"Saved login is account bound")
	check(not store.save_login(source.base_url,"fixture",{"account":"other","remember_token":saved.remember_token,"expires_at":saved.expires_at}).ok,"Foreign-account response cannot overwrite saved login")
	check(not store.save_login(source.base_url,"fixture",{"account":"fixture","remember_token":"invalid","expires_at":saved.expires_at}).ok,"Malformed token cannot overwrite saved login")
	check(not store.save_login(source.base_url,"fixture",{"account":"fixture","remember_token":saved.remember_token,"expires_at":1}).ok,"Expired token cannot overwrite saved login")
	var copied=preload("res://scripts/portable_login_store.gd").new();copied.path=folder+"/copied-installation.json"
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(store.path),ProjectSettings.globalize_path(copied.path))==OK,"Game data file copies to a second installation")
	check(copied.load_login(source.base_url,"fixture").get("remember_token")==saved.remember_token,"Copied installation resumes same login without machine/keyring binding")
	await app.sign_out();panel.lookup_timer.stop();panel._load_remembered_password()
	check(not panel.saved_login.is_empty() and panel.password_input.text.is_empty(),"Saved login is offered without populating a password field")
	check(not app.remote_connection.authenticated,"Loading portable login never signs in automatically")
	panel.submit();await frames()
	check(app.calls[-1].path=="/auth/resume" and app.account_ready(),"Sign-in exchanges saved token for a fresh authenticated session")
	check(not app.calls[-1].payload.has("password"),"Resume sends no password")
	await app.sign_out();panel.lookup_timer.stop();panel._load_remembered_password();panel.password_input.text="manual-password-override"
	var seen:=app.calls.size();panel.submit();await frames()
	check(app.calls[seen].path=="/auth/login","Manual password overrides saved token")
	await app.sign_out();panel.lookup_timer.stop();panel._load_remembered_password();app.reject_resume=true
	panel.submit();await frames()
	check(not app.account_ready() and panel.visible and not store.load_login(source.base_url,"fixture").get("found",false),"Revoked token returns to password login and removes invalid local credential")
	app.reject_resume=false;await app.authenticate_account("login",{"account":"fixture","password":"synthetic-fixture-password"});await app.sign_out();panel.lookup_timer.stop()
	app.reject_forget=true;panel.forget_remembered_password();await frames()
	check(store.load_login(source.base_url,"fixture").get("found",false) and not panel.remember_password.button_pressed,"Failed revocation retains retryable token but disables automatic lookup")
	app.reject_forget=false;panel.forget_remembered_password();await frames()
	check(not store.load_login(source.base_url,"fixture").get("found",false) and panel.status.text.contains("revoked"),"Forget confirms server revocation before removing local token")
	var connection=preload("res://scripts/remote_connection.gd").new();connection.configure(source)
	for path in ["/auth/resume","/auth/forget"]:
		var request:=HTTPRequest.new();var prepared:Dictionary=connection.apply_to(request,source.base_url,path,{"account":"fixture","remember_token":saved.remember_token})
		check(prepared.ok and prepared.headers.size()==1 and request.max_redirects==0,"Portable auth uses trusted endpoint with no bearer or redirects: "+path);request.free()
	app.calls.clear();app.free();await frames(2)
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder+"/"+file)
	DirAccess.remove_absolute(folder)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"auth":"mocked; production main and account UI","xr":"off","password_saved":false}
	FileAccess.open("res://../runtime/evidence/yoke-recall-login/portable-login-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
