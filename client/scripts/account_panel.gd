extends PanelContainer
## Portable saved login tokens; passwords and short-lived sessions remain in memory.
signal submitted(action: String, payload: Dictionary)
signal forget_requested(payload: Dictionary)
var mode := "login"
var legacy_account := ""
var working := false
var account_input: LineEdit
var password_input: LineEdit
var confirmation_input: LineEdit
var confirmation_label: Label
var title: Label
var description: Label
var status: Label
var endpoint_label: Label
var submit_button: Button
var modes: Dictionary={}
var remember_password: CheckBox
var forget_button: Button
var credential_store=preload("res://scripts/portable_login_store.gd").new()
var saved_login:Dictionary={}
var login_preferences_path := "user://login_preferences.cfg"
var endpoint := ""
var credential_epoch := 0
var password_revision := 0
var credential_results: Dictionary={}
var lookup_timer: Timer
func _ready() -> void:
	theme=preload("res://scripts/frontend_theme.gd").build()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-360;offset_top=-365;offset_right=360;offset_bottom=365
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);add_child(column)
	var eyebrow:=Label.new();eyebrow.text="GALACTIC CONNECTION";eyebrow.add_theme_color_override("font_color",Color("67dcea"));column.add_child(eyebrow)
	title=Label.new();title.add_theme_font_size_override("font_size",32);title.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Bold.ttf"));column.add_child(title)
	endpoint_label=Label.new();endpoint_label.add_theme_font_size_override("font_size",16);endpoint_label.add_theme_color_override("font_color",Color("91bdcc"));column.add_child(endpoint_label)
	var navigation:=HBoxContainer.new();column.add_child(navigation)
	for key in ["login","register","claim"]:
		var button:=Button.new();button.text={"login":"Sign in","register":"Create account","claim":"Set password"}[key]
		button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.pressed.connect(func(): set_mode(key))
		navigation.add_child(button);modes[key]=button
	description=Label.new();description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;description.add_theme_font_size_override("font_size",18);column.add_child(description)
	account_input=field(column,"ACCOUNT NAME",false);account_input.max_length=24
	password_input=field(column,"PASSWORD",true);password_input.max_length=128
	confirmation_label=Label.new();confirmation_label.text="CONFIRM PASSWORD";confirmation_label.add_theme_font_size_override("font_size",16);column.add_child(confirmation_label)
	confirmation_input=LineEdit.new();confirmation_input.secret=true;confirmation_input.max_length=128;confirmation_input.custom_minimum_size.y=46;column.add_child(confirmation_input)
	var remember_row:=HBoxContainer.new();column.add_child(remember_row)
	remember_password=CheckBox.new();remember_password.text="Remember login";remember_password.size_flags_horizontal=Control.SIZE_EXPAND_FILL;remember_row.add_child(remember_password)
	remember_password.tooltip_text="Save a revocable login token in the game data folder. Your password is never saved."
	forget_button=Button.new();forget_button.text="Forget saved login";remember_row.add_child(forget_button)
	lookup_timer=Timer.new();lookup_timer.one_shot=true;lookup_timer.wait_time=0.4;add_child(lookup_timer)
	lookup_timer.timeout.connect(_load_remembered_password)
	account_input.text_changed.connect(func(_text):
		_cancel_credentials();clear_passwords()
		if mode=="login" and remember_password.button_pressed:lookup_timer.start())
	password_input.text_changed.connect(func(_text):password_revision+=1)
	remember_password.toggled.connect(func(value):
		if not value:forget_remembered_password())
	forget_button.pressed.connect(forget_remembered_password)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.y=45;status.add_theme_font_size_override("font_size",18);column.add_child(status)
	submit_button=Button.new();submit_button.custom_minimum_size.y=48;submit_button.pressed.connect(submit);column.add_child(submit_button)
	password_input.text_submitted.connect(func(_text): submit())
	confirmation_input.text_submitted.connect(func(_text): submit())
	set_mode("login")
func field(column: VBoxContainer, text: String, secret: bool) -> LineEdit:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",16);label.add_theme_color_override("font_color",Color("67dcea"));column.add_child(label)
	var input:=LineEdit.new();input.secret=secret;input.custom_minimum_size.y=46;column.add_child(input);return input
func configure(endpoint: String, previous_account: String="") -> void:
	_cancel_credentials()
	self.endpoint=endpoint.trim_suffix("/")
	endpoint_label.text=endpoint;legacy_account=previous_account
	modes.claim.visible=not legacy_account.is_empty()
	var preferences:=ConfigFile.new()
	preferences.load(login_preferences_path)
	var saved:=str(preferences.get_value(self.endpoint,"account",""))
	remember_password.set_pressed_no_signal(bool(preferences.get_value(self.endpoint,"remember",false)))
	account_input.text=saved
	set_mode("claim" if not legacy_account.is_empty() else "login")
	remember_password.disabled=false
	forget_button.visible=remember_password.button_pressed
func clear_passwords() -> void:
	password_revision+=1
	password_input.clear();confirmation_input.clear();saved_login.clear();password_input.placeholder_text=""
func set_mode(value: String) -> void:
	if working or (value=="claim" and legacy_account.is_empty()):return
	_cancel_credentials()
	mode=value;clear_passwords();status.text=""
	for key in modes:modes[key].button_pressed=key==mode
	title.text={"login":"Welcome back","register":"Join the galaxy","claim":"Secure your existing account"}[mode]
	description.text="Choose a password of 12–128 characters. Saved logins are portable with the game data folder." if mode!="login" else "Sign in to view your characters. Remember login saves a revocable token; sign-in stays under your control."
	account_input.editable=mode!="claim"
	if mode=="claim":account_input.text=legacy_account
	confirmation_input.visible=mode!="login";confirmation_label.visible=mode!="login"
	submit_button.text={"login":"Sign in","register":"Create account","claim":"Set password and sign in"}[mode]
	if mode=="login" and remember_password.button_pressed:lookup_timer.start()
func set_working(value: bool, message: String="") -> void:
	working=value;submit_button.disabled=value
	account_input.editable=not value and mode!="claim";password_input.editable=not value;confirmation_input.editable=not value
	for button in modes.values():button.disabled=value
	remember_password.disabled=value
	forget_button.disabled=value
	if not message.is_empty():status.text=message
func submit() -> void:
	if working:return
	_cancel_credentials()
	var name:=account_input.text.strip_edges().to_lower()
	var expression:=RegEx.new();expression.compile("^[a-z][a-z0-9_]{2,23}$")
	if expression.search(name)==null:status.text="Use 3–24 lowercase letters, digits or underscores, starting with a letter.";return
	var password:=password_input.text
	if mode=="login" and password.is_empty() and not saved_login.is_empty():
		var payload:Dictionary={"account":name,"remember_token":saved_login.remember_token}
		clear_passwords();submitted.emit("resume",payload);return
	if password.length()<12 or password.length()>128 or password.to_utf8_buffer().size()>512:status.text="Use a password of 12–128 characters.";return
	if mode!="login" and password!=confirmation_input.text:status.text="Passwords do not match.";return
	var payload: Dictionary={"password":password}
	if mode!="claim":payload.account=name
	clear_passwords()
	submitted.emit(mode,payload)

func _cancel_credentials() -> void:
	credential_epoch+=1
	if is_instance_valid(lookup_timer):lookup_timer.stop()

func _save_preference(name: String, remember: bool) -> bool:
	var preferences:=ConfigFile.new()
	preferences.load(login_preferences_path)
	preferences.set_value(endpoint,"account",name)
	preferences.set_value(endpoint,"remember",remember)
	if preferences.save(login_preferences_path)!=OK:return false
	if OS.get_name()!="Windows":FileAccess.set_unix_permissions(login_preferences_path,384)
	return true

func _load_remembered_password() -> void:
	if working or mode!="login" or not visible or not remember_password.button_pressed or not password_input.text.is_empty():return
	var name:=account_input.text.strip_edges().to_lower()
	if name.is_empty():return
	var result:Dictionary=credential_store.load_login(endpoint,name)
	if result.get("ok",false) and result.get("found",false):
		saved_login=result;password_input.placeholder_text="Saved login ready";forget_button.show()
	elif not result.get("ok",false):status.text=str(result.get("error","Cannot read saved login. Enter your password."))
	elif result.get("expired",false):status.text="Saved login expired. Enter your password."

func save_authenticated_login(name:String,value:Dictionary)->String:
	var result:Dictionary=credential_store.save_login(endpoint,name,value)
	if not result.ok:return "Signed in; saved login could not be stored. "+str(result.error)
	forget_button.show()
	if not _save_preference(name,true):
		credential_store.remove_login(endpoint,name)
		return "Signed in; remember preference could not be saved. Saved login cancelled."
	return ""

func invalidate_saved_login(name:String)->void:
	credential_store.remove_login(endpoint,name);saved_login.clear();password_input.placeholder_text=""

func forget_remembered_password() -> void:
	if working:return
	_cancel_credentials();clear_passwords();remember_password.set_pressed_no_signal(false)
	var name:=account_input.text.strip_edges().to_lower()
	_save_preference(name,false)
	if name.is_empty():forget_button.hide();return
	var result:Dictionary=credential_store.load_login(endpoint,name)
	if not result.get("ok",false):status.text=str(result.error);return
	if not result.get("found",false):
		credential_store.remove_login(endpoint,name);forget_button.hide();status.text="No saved login for this account.";return
	set_working(true,"Revoking saved login…")
	forget_requested.emit({"account":name,"remember_token":result.remember_token})

func complete_forget(name:String,result:Dictionary)->void:
	set_working(false)
	if not result.get("ok",false):
		forget_button.show();status.text="Could not revoke saved login. Check the connection and try Forget again.";return
	var removed:Dictionary=credential_store.remove_login(endpoint,name)
	if removed.ok:forget_button.hide();status.text="Saved login revoked and removed."
	else:status.text="Saved login revoked; local file could not be updated."

func _exit_tree() -> void:_cancel_credentials()
