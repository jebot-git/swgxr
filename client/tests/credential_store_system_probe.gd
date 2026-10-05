extends SceneTree
## Real OS Secret Service roundtrip in an explicitly isolated synthetic origin.
## Invoke store, load, isolation, forget, absent as separate Godot processes.
const PASSWORD:="SWGXR synthetic 🔑 probe\n exact bytes "
const ACCOUNT:="remember_probe"
var phase:=""
var origin:=""
var prefs:=""
var checks:=0
var failures:Array=[]
var results:Dictionary={}
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		elif arg.begins_with("--origin="):origin=arg.trim_prefix("--origin=")
		elif arg.begins_with("--prefs="):prefs=arg.trim_prefix("--prefs=")
	create_timer(35).timeout.connect(func():print(JSON.stringify({"phase":phase,"passed":false,"error":"probe watchdog","secrets_logged":false}));quit(2))
	call_deferred("run")
func wait_result(store:Node,id:int)->Dictionary:
	while not results.has(id):await process_frame
	var result:Dictionary=results[id];results.erase(id);return result
func run()->void:
	if not origin.begins_with("https://swgxr-remember-probe-") or not origin.ends_with(".invalid:18443") or not prefs.is_absolute_path() or not prefs.contains("/runtime/evidence/remember-system/"):
		print("Synthetic isolated origin/preferences required");quit(2);return
	var panel:=preload("res://scripts/account_panel.gd").new()
	panel.login_preferences_path=prefs
	root.add_child(panel)
	panel.configure(origin)
	if phase!="load":panel.lookup_timer.stop()
	panel.credential_store.completed.connect(func(id:int,_operation:String,result:Dictionary):results[id]=result)
	check(panel.credential_store.available,"Real secret-tool helper is available")
	if phase=="store":
		panel.account_input.text=ACCOUNT;panel.remember_password.set_pressed_no_signal(true)
		var notice:String=await panel.remember_authenticated_password(ACCOUNT,PASSWORD)
		check(notice.is_empty(),"Actual OS credential store confirms save")
		var settings:=ConfigFile.new();settings.load(prefs)
		check(settings.get_value(origin,"remember",false),"Remember preference committed only after successful OS save")
		var text:=FileAccess.get_file_as_string(prefs)
		check(not text.contains(PASSWORD) and not text.contains("exact bytes"),"Disk preferences contain no synthetic password")
	elif phase=="load":
		check(panel.account_input.text==ACCOUNT and panel.remember_password.button_pressed,"New process restores account and remember choice")
		var deadline:=Time.get_ticks_msec()+12000
		while panel.password_input.text.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(panel.password_input.secret and panel.password_input.text==PASSWORD,"New process fills masked password with exact Unicode and whitespace bytes")
	elif phase=="isolation":
		var result:Dictionary=await wait_result(panel.credential_store,panel.credential_store.load_password(origin,"another_probe"))
		check(result.get("ok",false) and not result.get("found",false),"Other account cannot retrieve remembered password")
		result=await wait_result(panel.credential_store,panel.credential_store.load_password(origin.replace(":18443",":19443"),ACCOUNT))
		check(result.get("ok",false) and not result.get("found",false),"Other server port cannot retrieve remembered password")
	elif phase=="forget":
		panel.account_input.text=ACCOUNT
		await panel.forget_remembered_password()
		check(not panel.working and not panel.forget_button.visible and not panel.remember_password.button_pressed,"Actual Forget removes secret and clears remember preference")
		check(panel.password_input.text.is_empty(),"Forget clears masked form")
	elif phase in ["absent","cleanup"]:
		if phase=="cleanup":
			var deleted:Dictionary=await wait_result(panel.credential_store,panel.credential_store.delete_password(origin,ACCOUNT))
			check(deleted.get("ok",false),"Synthetic credential cleanup succeeds")
		var result:Dictionary=await wait_result(panel.credential_store,panel.credential_store.load_password(origin,ACCOUNT))
		check(result.get("ok",false) and not result.get("found",false),"Fresh process confirms no synthetic credential remains")
	else:check(false,"Unknown probe phase")
	results.clear();panel.free()
	print(JSON.stringify({"phase":phase,"checks":checks,"failures":failures,"passed":failures.is_empty(),"real_os_keyring":true,"actual_user_credentials_accessed":false,"secrets_logged":false,"live_xr":false}))
	quit(0 if failures.is_empty() else 1)
