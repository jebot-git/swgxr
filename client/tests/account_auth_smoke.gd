extends SceneTree
const Connection=preload("res://scripts/remote_connection.gd")
class Harness extends "res://scripts/main.gd":
	var calls: Array=[]
	var next_result: Dictionary={}
	var refreshed:=0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func refresh_backend() -> void:
		refreshed+=1;core3_ready=true;update_buttons()
	func api(_method: HTTPClient.Method,path: String,body: Dictionary={}) -> Dictionary:
		calls.append({"path":path,"account":body.get("account","")})
		await get_tree().process_frame
		return next_result.duplicate(true)
var failures: Array[String]=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func session(name: String="fixture") -> Dictionary:
	return {"ok":true,"account":name,"token":"synthetic-test-session-only","expires_at":Time.get_unix_time_from_system()+3600,"expires_in":3600}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		var parts:=argument.trim_prefix("--").split("=",true,1)
		if parts.size()==2:options[parts[0]]=parts[1]
	var connection:=Connection.new()
	var source: Dictionary={"base_url":"https://127.0.0.1:18443","ca_certificate":ProjectSettings.globalize_path("res://../runtime/deploy/credentials/ca.pem")}
	check(connection.configure(source),"Endpoint-only profile loads trusted CA")
	check(connection.configured and not connection.authenticated,"Server configuration is distinct from account authentication")
	check(not connection.validate_request(connection.base_url,"/health").is_empty(),"Gameplay requests need authenticated account")
	var request:=HTTPRequest.new()
	var prepared: Dictionary=connection.apply_to(request,connection.base_url,"/auth/login",{"account":"fixture","password":"fixture-password"})
	check(prepared.get("ok",false) and prepared.headers.size()==1,"Login uses verified TLS without bearer credentials")
	check(request.max_redirects==0,"Login redirects stay disabled")
	check(connection.accept_session(session()),"Valid native auth session accepted in memory")
	check(not connection.legacy_profile and connection.authenticated,"Password session no longer requires claim")
	check(not connection.validate_request(connection.base_url,"/characters?account=other").is_empty(),"Session remains account-bound")
	check(not connection.accept_session({"account":"fixture","token":"bad","expires_at":1}),"Expired auth envelope rejected")
	connection.clear_session();check(connection.configured and not connection.authenticated,"Sign-out retains endpoint and CA")
	var fixture_path:=ProjectSettings.globalize_path("res://../runtime/evidence/remote-client/auth-profile-fixture.json")
	var file:=FileAccess.open(fixture_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"base_url":source.base_url,"ca_certificate":source.ca_certificate,"account":"fixture","token":"synthetic-legacy"}));file.close()
	check(connection.load_profile(fixture_path) and connection.legacy_profile,"Legacy private profile remains compatible")
	check(connection.accept_session(session()) and connection.remove_legacy_profile_credentials(),"Claim replaces private profile atomically")
	var cleaned: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	check(not cleaned.has("token") and not cleaned.has("account") and cleaned.base_url==source.base_url,"Persisted profile retains only endpoint and trust")
	if OS.get_name()!="Windows":check(FileAccess.get_unix_permissions(fixture_path)==384,"Migrated profile remains mode0600")
	DirAccess.remove_absolute(fixture_path)
	request.free()
	var app:=Harness.new();root.add_child(app)
	app.remote_connection.configure(source)
	app.backend_url=source.base_url
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false)
	app.make_ui()
	check(app.account_panel.visible and not app.menu.visible,"Unsigned remote client gates character selection")
	check(app.create_button.disabled,"Unsigned remote client cannot create characters")
	var panel=app.account_panel
	panel.login_preferences_path="res://../runtime/evidence/remote-client/auth-login-preferences-fixture.cfg"
	DirAccess.remove_absolute(panel.login_preferences_path)
	panel.configure(app.backend_url)
	panel.set_mode("register");panel.account_input.text="FiXtUrE"
	panel.password_input.text="long-fixture-password";panel.confirmation_input.text="mismatch"
	panel.submit();check(app.calls.is_empty(),"Mismatched password confirmation never submits")
	panel.confirmation_input.text="long-fixture-password"
	app.next_result=session();panel.submit()
	check(panel.password_input.text.is_empty() and panel.confirmation_input.text.is_empty(),"Password controls clear immediately on submission")
	for _frame in range(4):await process_frame
	check(app.calls.size()==1 and app.calls[0].account=="fixture" and app.calls[0].path=="/auth/register","Registration normalizes account and uses agreed endpoint")
	check(app.account_ready() and app.menu.visible and not panel.visible,"Successful authentication reveals character selection")
	check(app.account_input.text=="fixture" and app.refreshed==1,"Authenticated account binds roster and refreshes backend")
	app.characters=[{"id":"old"}];app.creation_options={"private":"old"};app.inventory_snapshot={"items":[1]};app.datapad_character_id="old"
	app.world_ready=true;await app.sign_out();check(app.calls.size()==1,"Account switching blocked while world is loaded")
	app.world_ready=false;app.next_result={"ok":true,"logged_out":true};await app.sign_out()
	check(not app.remote_connection.authenticated and panel.visible and not app.menu.visible,"Sign-out revokes session and returns to login")
	check(app.characters.is_empty() and app.creation_options.is_empty() and app.inventory_snapshot.is_empty() and app.datapad_character_id.is_empty(),"Sign-out clears account-owned roster/options/inventory/identity")
	check(app.calls[-1].path=="/auth/logout","Explicit sign-out uses revoke endpoint")
	app.remote_connection.accept_session(session());app.expire_account()
	check(panel.visible and not app.remote_connection.authenticated and not app.account_ready(),"Expiry returns to login without local fallback")
	panel.configure(app.backend_url,"legacyuser")
	check(panel.mode=="claim" and not panel.account_input.editable,"Existing private profile presents explicit password claim")
	panel.set_mode("login");check(panel.mode=="login" and panel.account_input.editable,"Claim gate still offers ordinary login")
	for dimensions in [Vector2i(1280,900),Vector2i(1440,900)]:
		root.size=dimensions;root.content_scale_size=Vector2i.ZERO
		for mode in ["login","register","claim"]:
			panel.set_mode(mode)
			for _frame in range(4):await process_frame
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(panel.get_global_rect()),"Auth panel fits %s %s"%[dimensions,mode])
			if options.has("capture"):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(str(options.capture)+"/account-%d-%s.png"%[dimensions.x,mode])
	DirAccess.remove_absolute(panel.login_preferences_path)
	app.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"auth_api":"mocked; no account mutations","xr":"off"}))
	quit(0 if failures.is_empty() else 1)
