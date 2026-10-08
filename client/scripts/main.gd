extends Node3D
var action_haptics=preload("res://scripts/action_haptics.gd").new()
const FrontendChoice=preload("res://scripts/frontend_choice.gd")

const PlayerScript = preload("res://scripts/player.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")
const CreationPanel = preload("res://scripts/creation_panel.gd")
const Avatar = preload("res://scripts/avatar.gd")
const TrackedAvatar = preload("res://scripts/tracked_avatar.gd")
var live_combat: Node3D
var gameplay_session: Node
var multiplayer_sync: Node
var gameplay_combat: Node3D
var mission_parcels: Node3D
var vendor_placement: Node3D
var vendor_commerce: Node3D
var live_combat_reserved := false
var live_combat_closing := false
var api_requests_in_flight := 0
var api_realtime_requests_in_flight := 0
var native_poll_budget:=preload("res://scripts/native_poll_budget.gd").new()
var vehicle_activation_requests: Dictionary={}
var live_combat_epoch := 0
var active_planet:="tatooine"
var planet_assets:Dictionary={}
var planet_catalog:=preload("res://scripts/planet_catalog.gd").new()
var planet_transition:=preload("res://scripts/planet_transition.gd").new()
var medical_placement = preload("res://combat/live_transport.gd").new()
var live_transport_busy := false
var live_transport_epoch := 0
var retry_transport:Dictionary={}
var retry_transport_service:=false
var live_appearance_text := ""
var live_appearance_label: Label3D
var combat_rig: Node3D
var entertainer: Node3D
var combat_target: Node3D
var tracked_avatar: Node3D
const TerrainStream = preload("res://scripts/terrain_stream.gd")
const WorldStream = preload("res://scripts/world_stream.gd")
const EnvironmentPresentation = preload("res://scripts/environment_presentation.gd")
const AmbientNPCs = preload("res://scripts/ambient_npcs.gd")
var environment_presentation: Node3D
var ambient_npcs: Node3D
var world_stream: Node3D
var terrain: Node3D
const XRMenu = preload("res://scripts/xr_menu.gd")
const StartXR = preload("res://addons/godot-xr-tools/xr/start_xr.tscn")
const VRSettings = preload("res://scripts/vr_settings.gd")
var vr_settings = VRSettings.new()
var xr_viewport: SubViewport
var xr_spectator: CanvasLayer
var calibration_status: Label
var datapad: Node3D
var inventory: Node3D
var inventory_drops: Node3D
var medic: Node3D
var vehicles: Node3D
var pets: Node
var scout: Node3D
var housing: Node3D
var fishing: Node3D
var slicing: Node3D
var spice_world:Node3D
var crafting: Node3D
var services: Node3D
var gathering: Node
var corpse_gathering: Node
var inventory_snapshot: Dictionary = {}
var inventory_request_pending := false
var inventory_hidden_equipment: Dictionary = {}
var inventory_equipment_revision := ""
var inventory_weapon_revision := ""
var inventory_equipment_notice := ""
var radar_contacts := preload("res://scripts/radar_contacts.gd").new()
var datapad_character_id := ""
var datapad_account := ""
var datapad_request_pending := false
var datapad_epoch := 0
var portal_visibility: Node
var xr_requested := false
var xr_initialized := false
var xr_focused := false
var xr_origin: XROrigin3D
var xr_start: XRToolsStartXR
var xr_menu: Node3D
var ui_root: Control
var login_presentation:ColorRect
var audio_preferences=preload("res://audio/preferences.gd").new()
var creator: Control
var avatar: Node3D
var creation_options: Dictionary = {}
var action_pick: FrontendChoice
var action_row: HBoxContainer
var avatar_previous_yaw := 0.0
var backend_url := "http://127.0.0.1:18080"
var remote_connection := preload("res://scripts/remote_connection.gd").new()
var account_panel: PanelContainer
var sign_out_button: Button
var auth_busy := false
var auth_revision := 0
var auth_expiry_reload := false
var voice_chat: Node
var voice_controls: Node3D
var desktop_voice_panel: PanelContainer
var desktop_voice_open := false
var desktop_voice_ptt_armed := false
var desktop_voice_pointer_ptt := false
var stage_path := ""
var player: CharacterBody3D
var stage: Node3D
var loader = StageLoader.new()
var menu: PanelContainer
var status: Label
var asset_status: Label
var roster_hint: Label
var character_list: ItemList
var name_input: LineEdit
var account_input: LineEdit
var create_button: Button
var enter_button: Button
var resume_button: Button
var logoff_button: Button
var quit_button: Button
var session_leaving := false
var logout_payload: Dictionary = {}
var hud: Label
var mode_label: Label
var core3_ready := false
var characters: Array = []
var busy := false
var loading_stage := false
var world_ready := false
var session_mode := ""
var screenshot_path := ""
var smoke_mode := false
var args := {}
var loading_screen: Node
var xr_bottleneck_suite: Node

func _ready() -> void:
	if not preload("res://scripts/render_policy.gd").current().supported:
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			args[parts[0]] = parts[1] if parts.size() > 1 else true
	get_tree().auto_accept_quit = false
	Avatar.animation_cache_enabled_default = not args.has("no-animation-cache")
	if args.has("xr-bottleneck-suite"):
		xr_bottleneck_suite = preload("res://diagnostics/xr_bottleneck_suite.gd").new()
		add_child(xr_bottleneck_suite)
		if not xr_bottleneck_suite.configure(self,str(args["xr-bottleneck-suite"])):
			xr_bottleneck_suite.queue_free()
	elif args.has("runtime-profile"):
		var diagnostic := preload("res://diagnostics/runtime_profile.gd").new()
		add_child(diagnostic)
		if not diagnostic.configure(self,str(args["runtime-profile"])):
			diagnostic.queue_free()
	backend_url = str(args.get("backend", backend_url)).trim_suffix("/")
	if not configure_backend_connection():
		push_error(remote_connection.error)
		get_tree().quit(2)
		return
	vr_settings.load_preferences()
	if args.has("turn-mode"):
		vr_settings.set_turn_mode(str(args["turn-mode"]))
	if args.has("turn-speed"):
		vr_settings.set_turn_speed(float(args["turn-speed"]))
	stage_path = str(args.get("stage", ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")))
	screenshot_path = str(args.get("screenshot", ""))
	smoke_mode = args.has("smoke-test") or args.has("integration-test")
	xr_requested = not args.has("desktop") and not smoke_mode and screenshot_path.is_empty() and DisplayServer.get_name() != "headless"
	configure_inputs()
	busy = true
	ensure_loading_screen()
	loading_screen.begin("Starting the client…")
	await present_loading_frame()
	if xr_requested:
		xr_origin = load("res://xr/player_rig.tscn").instantiate()
		add_child(xr_origin)
		vr_settings.apply(xr_origin)
		player = xr_origin.get_node("PlayerBody")
		player.set_physics_process(false)
		player.menu_requested.connect(toggle_xr_menu)
	else:
		player = PlayerScript.new()
		add_child(player)
		player.global_position = Vector3(0, 2, 8)
	make_ui()
	if xr_requested:
		if not initialize_xr():
			status.text = "OpenXR is unavailable. Connect your headset through an OpenXR runtime, then restart. Use ./run.sh --desktop for desktop inspection."
			create_button.disabled = true
			enter_button.disabled = true
			loading_screen.finish()
			busy = false
			return
		loading_screen.attach_head(player.get_camera())
	loading_screen.set_status("Preparing the environment…")
	await present_loading_frame()
	make_environment()
	ensure_voice_chat()
	loading_screen.finish()
	busy = false
	var readiness_timer := Timer.new()
	readiness_timer.wait_time = 5.0
	readiness_timer.timeout.connect(func():
		if menu.visible and not busy and not core3_ready and not smoke_mode and screenshot_path.is_empty():
			refresh_backend()
	)
	add_child(readiness_timer)
	readiness_timer.start()
	if args.has("creation-preview"):
		open_creator()
		if args.has("creation-options"):
			creator.set_options(Avatar.read_json(str(args["creation-options"])))
		creator.select_race_id(str(args["creation-preview"]))
		if args.has("creation-tab"):
			creator.tabs.current_tab = int(args["creation-tab"])
		if not screenshot_path.is_empty():
			await take_screenshot()
	elif args.has("integration-test"):
		await integration_test()
	elif args.has("offline") or smoke_mode:
		await enter_stage(true)
		if not world_ready:
			if smoke_mode or not screenshot_path.is_empty(): get_tree().quit(1)
			return
		if smoke_mode:
			await stage_smoke()
		elif not screenshot_path.is_empty():
			await take_screenshot()
	else:
		await refresh_backend()
		if args.has("show-creator"):
			open_creator()
		if core3_ready and args.has("enter-character"):
			for i in range(characters.size()):
				if str(characters[i].get("name", "")).to_lower() == str(args["enter-character"]).to_lower():
					character_list.select(i)
					await enter_character()
					break
		if not screenshot_path.is_empty():
			await take_screenshot()

func configure_inputs() -> void:
	var mappings := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "reset_spawn": KEY_R}
	for action in mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = mappings[action]
			InputMap.action_add_event(action, key)

func make_environment() -> void:
	if planet_assets.is_empty():planet_assets=planet_catalog.descriptor(active_planet)
	environment_presentation = EnvironmentPresentation.new()
	add_child(environment_presentation)
	environment_presentation.configure(str(planet_assets.get("environment",ProjectSettings.globalize_path("res://../runtime/assets/tatooine_environment/environment.json"))))
	if args.has("time-of-day"):
		environment_presentation.set_phase(float(args["time-of-day"]))
	if args.has("day-seconds"):
		environment_presentation.cycle_seconds = maxf(60,float(args["day-seconds"]))

func make_ui() -> void:
	audio_preferences.load_preferences()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui_root = ui
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	ui.theme = preload("res://scripts/frontend_theme.gd").build()
	login_presentation=preload("res://scripts/login_presentation.gd").new();ui.add_child(login_presentation);login_presentation.configure(self)
	mode_label = Label.new()
	mode_label.position = Vector2(28, 24)
	mode_label.text = "SWG XR   /   GALACTIC CONNECTION"
	mode_label.add_theme_color_override("font_color", Color("67dcea"))
	mode_label.add_theme_font_size_override("font_size", 19)
	ui.add_child(mode_label)
	hud = Label.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hud.position = Vector2(28, -76)
	hud.size = Vector2(1100, 60)
	hud.add_theme_color_override("font_color", Color("c9fbff"))
	ui.add_child(hud)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(5, 12)
	ui.add_child(crosshair)
	crosshair.visible = not xr_requested and not args.has("combat-lab")
	hud.visible = not xr_requested
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.position = Vector2(-624, -370)
	menu.size = Vector2(1248, 740)
	ui.add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	menu.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	add_label(heading, "GALAXY  /  CHARACTER SELECT", 16, Color("67dcea"))
	add_label(heading, "Choose your character", 34, Color("c9fbff"))
	var location := add_label(header, "CHARACTERS\nContinue your journey", 18, Color("91bdcc"))
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	var roster := VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.size_flags_stretch_ratio = 1.1
	columns.add_child(roster)
	add_label(roster, "CHARACTERS", 16, Color("67dcea"))
	var account_row := HBoxContainer.new()
	roster.add_child(account_row)
	add_label(account_row, "Account", 18, Color("91bdcc"))
	account_input = LineEdit.new()
	account_input.placeholder_text = "Account name"
	account_input.editable = not remote_connection.configured
	if remote_connection.configured:
		account_input.focus_mode = Control.FOCUS_NONE
	account_input.text = str(args.get("account", "prototype"))
	account_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_row.add_child(account_input)
	add_button(account_row, "Refresh", refresh_backend)
	sign_out_button=add_button(account_row,"Sign out",sign_out)
	sign_out_button.visible=remote_connection.configured
	status = add_label(roster, "Connecting to the galaxy…", 16, Color("91bdcc"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_input = LineEdit.new()
	name_input.max_length = 24
	roster.add_child(name_input)
	name_input.hide()
	character_list = ItemList.new()
	character_list.custom_minimum_size.y = 160
	character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_list.item_selected.connect(func(_index): update_buttons())
	roster.add_child(character_list)
	roster_hint = add_label(roster, "Connect to load your characters.", 18, Color("91bdcc"))
	roster_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	roster.add_child(buttons)
	create_button = add_button(buttons, "Create character", open_creator)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter_button = add_button(buttons, "Enter Galaxy", enter_character)
	enter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_button = add_button(roster, "Resume exploration", close_menu)
	resume_button.visible = false
	var session_buttons:=HBoxContainer.new()
	roster.add_child(session_buttons)
	logoff_button=add_button(session_buttons,"Log off",func(): leave_character(false))
	logoff_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	quit_button=add_button(session_buttons,"Quit",func(): leave_character(true))
	quit_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action_row = HBoxContainer.new()
	action_row.visible = false
	roster.add_child(action_row)
	action_pick = preload("res://scripts/frontend_choice.gd").new()
	action_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_pick)
	add_button(action_row, "Play", func():
		if avatar != null and action_pick.item_count > 0:
			if play_avatar_action(str(action_pick.get_selected_metadata())):
				close_menu()
	)
	var settings_panel := PanelContainer.new()
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_panel.custom_minimum_size.x = 550
	settings_panel.add_theme_stylebox_override("panel", preload("res://scripts/datapad_theme.gd").frame(18))
	columns.add_child(settings_panel)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 14)
	settings_panel.add_child(settings)
	add_label(settings, "VIEW & AUDIO", 16, Color("67dcea"))
	for channel in ["Music", "Ambience"]:
		var audio_row := HBoxContainer.new()
		settings.add_child(audio_row)
		var caption := add_label(audio_row, channel, 18, Color("c9fbff"))
		caption.custom_minimum_size.x = 100
		var slider := HSlider.new()
		slider.name=channel+"Volume"
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = audio_preferences.music if channel == "Music" else audio_preferences.ambience
		slider.custom_minimum_size.y = 36
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		audio_row.add_child(slider)
		slider.value_changed.connect(func(value):audio_preferences.set_volume(channel,value))
	if xr_requested:
		settings.add_child(HSeparator.new())
		make_vr_settings(settings)
	var help := add_label(settings, "Left stick · Move\nRight stick · Turn    Menu button · Menu\nOffhand stick click · Jump / recover\nCrouch physically\nPalm-up offhand · Voice controls" if xr_requested else "WASD · Move    Mouse · Look\nShift · Run    Space · Jump\nEsc · Menu    R · Return to entry\nF12 · Voice controls    B · Push to talk", 18, Color("91bdcc"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_child(spacer)
	if args.has("combat-items"):
		add_button(settings, "Refresh weapon statistics", refresh_weapon_statistics)
	settings.add_child(HSeparator.new())
	add_button(settings, "Offline asset viewer", func(): enter_stage(true))
	var asset_scroll := preload("res://scripts/frontend_scroll.gd").new()
	asset_scroll.custom_minimum_size.y = 56
	asset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings.add_child(asset_scroll)
	asset_status = add_label(asset_scroll, "Explore your imported environments offline.", 16, Color("91bdcc"))
	asset_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creator = CreationPanel.new()
	creator.visible = false
	ui.add_child(creator)
	creator.closed.connect(close_creator)
	creator.create_requested.connect(create_character)
	account_panel=preload("res://scripts/account_panel.gd").new()
	ui.add_child(account_panel)
	account_panel.submitted.connect(authenticate_account)
	account_panel.forget_requested.connect(forget_saved_login)
	account_panel.configure(backend_url,remote_connection.account if remote_connection.legacy_profile else "")
	account_panel.visible=remote_connection.configured and not account_ready()
	if account_panel.visible: menu.hide()
	if not remote_connection.configured: mode_label.text="SWG XR / LOCAL DEBUG · trusted loopback"
	update_buttons()

func make_vr_settings(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "VRTurningSettings"
	box.add_child(row)
	add_label(row, "Turning", 18)
	var group := ButtonGroup.new()
	var snap := Button.new()
	snap.name = "SnapTurn"
	snap.text = "Snap · 30°"
	snap.toggle_mode = true
	snap.button_group = group
	snap.button_pressed = vr_settings.turn_mode == "snap"
	snap.custom_minimum_size.y = 38
	row.add_child(snap)
	var smooth := Button.new()
	smooth.name = "SmoothTurn"
	smooth.text = "Smooth"
	smooth.toggle_mode = true
	smooth.button_group = group
	smooth.button_pressed = vr_settings.turn_mode == "smooth"
	smooth.custom_minimum_size.y = 38
	row.add_child(smooth)
	var speed := HSlider.new()
	speed.name = "SmoothTurnSpeed"
	speed.min_value = 30
	speed.max_value = 180
	speed.step = 15
	speed.value = vr_settings.turn_speed_degrees
	speed.custom_minimum_size.x = 140
	speed.editable = vr_settings.turn_mode == "smooth"
	row.add_child(speed)
	var rate := add_label(row, "%d°/s" % vr_settings.turn_speed_degrees, 16)
	snap.pressed.connect(func():
		vr_settings.set_turn_mode("snap")
		speed.editable = false
		save_vr_settings()
	)
	smooth.pressed.connect(func():
		vr_settings.set_turn_mode("smooth")
		speed.editable = true
		save_vr_settings()
	)
	speed.value_changed.connect(func(value):
		vr_settings.set_turn_speed(value)
		rate.text = "%d°/s" % vr_settings.turn_speed_degrees
		save_vr_settings()
	)
	var calibration_row := HBoxContainer.new()
	box.add_child(calibration_row)
	var calibrate := add_button(calibration_row, "Calibrate standing height", calibrate_player_height)
	calibrate.name = "CalibrateHeight"
	calibrate.custom_minimum_size.y = 38
	calibration_status = add_label(calibration_row, "Stand upright, then calibrate", 16)
	calibration_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calibration_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func calibrate_player_height() -> void:
	if not world_ready or (not is_instance_valid(tracked_avatar) and not is_instance_valid(combat_rig)):
		calibration_status.text = "Enter with your character or open the combat lab first."
		return
	var result: Dictionary = tracked_avatar.calibrate_standing_height() if is_instance_valid(tracked_avatar) else combat_rig.calibrate_standing_height()
	if not result.get("valid", false):
		calibration_status.text = str(result.get("reason", "Stand on the floor with tracking active."))
		return
	vr_settings.standing_eye_height = float(result.standing_eye_height)
	player.feedback.stance.set_standing_eye_height(vr_settings.standing_eye_height)
	if is_instance_valid(combat_rig):
		combat_rig.set_standing_eye_height(vr_settings.standing_eye_height)
	var saved: bool = vr_settings.save_preferences() == OK
	calibration_status.text = "Eye height %.2f m%s" % [vr_settings.standing_eye_height, " · saved" if saved else " · this session"]

func save_vr_settings() -> void:
	vr_settings.apply(xr_origin)
	if vr_settings.save_preferences() != OK:
		status.text = "Turning updated for this session; preferences could not be saved."

func add_label(parent: Node, text: String, font_size := 17, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 26: label.add_theme_font_override("font", preload("res://resources/fonts/Jupiteroid-Bold.ttf"))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func update_buttons() -> void:
	if is_instance_valid(resume_button):resume_button.disabled=session_leaving or not logout_payload.is_empty()
	if is_instance_valid(logoff_button):logoff_button.disabled=busy or loading_stage or session_leaving or not world_ready
	if is_instance_valid(quit_button):quit_button.disabled=busy or loading_stage or session_leaving
	if is_instance_valid(sign_out_button):
		sign_out_button.disabled=busy or auth_busy or world_ready or loading_stage or live_combat_reserved
		sign_out_button.tooltip_text="Leave the current session to sign out." if world_ready or loading_stage or live_combat_reserved else "End this account session"
	create_button.disabled = busy or world_ready or session_leaving or not account_ready()
	if roster_hint != null:
		roster_hint.text = "Select a character to continue." if character_list.item_count > 0 else ("No characters yet. Create one to begin your journey." if core3_ready else "Connect to load your characters.")
	if creator != null:
		creator.set_backend_state(core3_ready)
	enter_button.disabled = busy or world_ready or session_leaving or not core3_ready or character_list.get_selected_items().is_empty()

func configure_backend_connection() -> bool:
	remote_connection.reset()
	if args.has("local") or args.has("offline"):
		if args.has("connection-profile"): return remote_connection.fail("A remote profile cannot be combined with --local or --offline.")
		return true
	var profile:=str(args.get("connection-profile",ProjectSettings.globalize_path("res://../runtime/client/connection.json")))
	if not args.has("connection-profile") and not FileAccess.file_exists(profile): return true
	if not remote_connection.load_profile(profile): return false
	if args.has("backend") and str(args.backend).trim_suffix("/")!=remote_connection.base_url: return remote_connection.fail("Remote profile conflicts with the requested backend.")
	if args.has("account") and not remote_connection.account.is_empty() and str(args.account)!=remote_connection.account: return remote_connection.fail("Remote profile conflicts with the requested account.")
	backend_url=remote_connection.base_url
	args.account=remote_connection.account
	return true

func api(method: HTTPClient.Method, path: String, body := {}) -> Dictionary:
	if session_leaving and path!="/session/logout":return {"ok":false,"error":"Logging off; background request cancelled.","cancelled":true}
	if body is Dictionary and str(body.get("character_id",""))==datapad_character_id and not datapad_character_id.is_empty():
		body=body.duplicate(true);body.zone=active_planet
		# Capture before any asynchronous request. Already queued commands retain
		# their original revision instead of borrowing newer movement authority.
		if body.get("position") is Array and not path.ends_with("/start"):
			if is_instance_valid(gameplay_session) and gameplay_session.live and gameplay_session.character_id==datapad_character_id:
				body=preload("res://combat/movement_reconciliation.gd").stamp_request(body,gameplay_session.player_state)
			elif live_combat_reserved and is_instance_valid(live_combat) and live_combat.live and live_combat.owner_character==datapad_character_id:
				body=preload("res://combat/movement_reconciliation.gd").stamp_request(body,live_combat.player_state)
	var revision:=auth_revision
	var haptic_character:=datapad_character_id
	var haptic_hand:=action_haptics.choose_hand(xr_origin,"right" if vr_settings.offhand=="left" else "left")
	if path not in remote_connection.PUBLIC_AUTH and remote_connection.configured and remote_connection.authenticated and remote_connection.expires_at>0 and Time.get_unix_time_from_system()>=remote_connection.expires_at:
		expire_account()
		return {"ok":false,"error":"Your session expired. Sign in again."}
	# Legacy RPCs reconnect this character and would evict its persistent zone session.
	# The owner weapon-profile read borrows the existing native session in the adapter.
	if live_combat_reserved and not (method==HTTPClient.METHOD_GET and path.begins_with("/weapons?")) and not (method==HTTPClient.METHOD_POST and (path.begins_with("/entertainer/") or path in ["/performance","/inventory/equip","/inventory/unequip"])) and path!="/session/logout" and path!="/session/sync" and path!="/inventory/status" and not path.begins_with("/voice/") and not path.begins_with("/auth/") and not path.begins_with("/combat/session") and not path.begins_with("/vehicles/") and not path.begins_with("/medic/") and not path.begins_with("/scout/") and not path.begins_with("/services/") and not path.begins_with("/crafting/") and not path.begins_with("/gathering/"):
		return {"ok":false,"error":"Inventory and character RPCs are suspended during the live ranged test."}
	var request := HTTPRequest.new()
	request.timeout = (30.0 if path.ends_with("/start") else 4.0) if path.begins_with("/combat/session") else 75.0
	for prefix in ["/gathering","/inventory","/services","/crafting","/vehicles"]:
		if path.begins_with(prefix):request.timeout=15.0;break
	if path == "/services/presence": request.timeout = 2.0
	if path == "/session/logout":request.timeout=30.0
	if path == "/session/start":request.timeout=30.0
	if path == "/session/update":request.timeout=8.0
	if path == "/session/life":request.timeout=15.0
	if path == "/session/sync":request.timeout=2.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if remote_connection.configured:
		var settings: Dictionary=remote_connection.apply_to(request,backend_url,path,body)
		if not settings.get("ok",false):
			request.queue_free()
			return settings
		headers=settings.headers
	var error := request.request(backend_url + path, headers, method, JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if error != OK:
		request.queue_free()
		return {"ok": false, "error": "Cannot request Core3 service: " + error_string(error)}
	api_requests_in_flight += 1
	var realtime:=path in ["/session/sync","/services/presence","/performance"]
	if realtime:api_realtime_requests_in_flight+=1
	var result: Array = await request.request_completed
	api_requests_in_flight -= 1
	if realtime:api_realtime_requests_in_flight-=1
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		if result[0]==HTTPRequest.RESULT_TIMEOUT:
			return {"ok":false,"request_timeout":true,"error":"Core3 request timed out; the result is not confirmed. Refresh before retrying."}
		return {"ok": false, "error": "Core3 service unavailable at " + backend_url}
	if remote_connection.configured and revision!=auth_revision: return {"ok":false,"error":"Account session changed."}
	if int(result[1])==401 and remote_connection.configured and path not in remote_connection.PUBLIC_AUTH:
		expire_account()
		return {"ok":false,"error":"Your session expired. Sign in again."}
	var parsed = JSON.parse_string(result[3].get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	data["ok"] = int(result[1]) >= 200 and int(result[1]) < 300
	data["http_status"] = int(result[1])
	if not data.ok and not data.has("error"):
		data.error = "Service returned HTTP " + str(result[1])
	if consume_movement_rejection(data):data["_movement_correction_consumed"]=true
	if method==HTTPClient.METHOD_POST and haptic_character==datapad_character_id and revision==auth_revision:
		action_haptics.receipt(xr_origin,xr_requested and xr_focused,path,body,data,haptic_hand)
	return data

func consume_movement_rejection(data:Dictionary)->bool:
	var original:Variant=data.get("live_response")
	if data.get("backend","")!="core3" or not original is Dictionary:return false
	var mutation:Dictionary=original.get("mutation",{})
	var reason:=str(mutation.get("error_code",original.get("error_code","")))
	if not mutation.get("movement_accepted") is bool or mutation.movement_accepted or not reason.begins_with("native_movement_"):return false
	if original.get("backend","")!="core3" or original.get("source_kind","")!="core3_live_combat" or not original.get("session_live",false) or str(original.get("character_id",""))!=datapad_character_id:return false
	# A rejected action still carries authoritative placement. Adopt only its
	# explicitly fenced snapshot; never turn the outer mutation into success.
	var snapshot:Dictionary=original.duplicate(true);snapshot.ok=true
	if is_instance_valid(gameplay_session) and gameplay_session.live:return gameplay_session.accept_native_response(snapshot)
	if live_combat_reserved and is_instance_valid(live_combat) and live_combat.live:
		# A newer owned service snapshot may already have superseded this failed
		# movement receipt. Settle it without rolling back or closing the session.
		var sequence_value:=int(snapshot.get("sequence",-1))
		if str(snapshot.get("session_id",""))==live_combat.session_id and sequence_value>=0 and sequence_value<live_combat.sequence:return true
		return live_combat.accept_response(snapshot)
	return false

func native_requests_in_flight() -> int:
	return maxi(0,api_requests_in_flight-api_realtime_requests_in_flight)

func try_background_poll(family: String) -> bool:
	if is_instance_valid(gameplay_combat) and gameplay_combat.has_pending_commands():return false
	if not world_ready or session_leaving or loading_stage or busy or menu.visible:return false
	var occupied:bool=native_requests_in_flight()>0 or inventory_request_pending or datapad_request_pending
	if live_combat_reserved:
		if not is_instance_valid(live_combat):return false
		occupied=occupied or live_combat.busy or live_combat.backend_retry_usec>Time.get_ticks_usec()
		native_poll_budget.interval_ms=1000
	elif is_instance_valid(gameplay_session):
		if gameplay_session.busy or (gameplay_session.live and is_instance_valid(vehicles) and vehicles.seated()):return false
		native_poll_budget.interval_ms=1000 if gameplay_session.live else 3000
	return native_poll_budget.admit(family,Time.get_ticks_msec(),occupied)

func yield_live_poll_to_background() -> bool:
	# A slower-than-POLL_INTERVAL heartbeat otherwise retakes the gate every
	# frame before later-priority service controllers can receive a fair slot.
	if not live_combat_reserved or not world_ready or session_leaving or loading_stage or busy or menu.visible:return false
	if native_requests_in_flight()>0 or inventory_request_pending or datapad_request_pending:return false
	return native_poll_budget.has_ready_waiters(Time.get_ticks_msec())

func ensure_gameplay_session() -> bool:
	if is_instance_valid(live_combat) and live_combat.live:return true
	if not is_instance_valid(gameplay_session):
		gameplay_session=preload("res://scripts/gameplay_session.gd").new();add_child(gameplay_session);gameplay_session.setup(self)
		gameplay_session.snapshot_applied.connect(apply_live_player)
		gameplay_session.life_action_finished.connect(live_life_action_finished)
		gameplay_session.transport_required.connect(handle_live_transport)
	if not player.feedback.life_action_requested.is_connected(request_live_life_action):player.feedback.life_action_requested.connect(request_live_life_action)
	player.feedback.local_prediction=false
	return await gameplay_session.start()

func refresh_backend() -> void:
	if not account_ready():
		show_account_panel()
		return
	if busy:
		return
	busy = true
	update_buttons()
	var response := await api(HTTPClient.METHOD_GET, "/health")
	if not account_ready():
		busy=false
		update_buttons()
		return
	var core = response.get("core3", {})
	core3_ready = response.get("ok", false) and core is Dictionary and core.get("ready", false) and response.get("backend", "") == "core3"
	if core3_ready:
		status.text = ("REMOTE GALAXY" if remote_connection.configured else "LOCAL GALAXY")+" · Connected"
		status.add_theme_color_override("font_color", Color("b3d9b0"))
		if creation_options.is_empty():
			var option_response := await api(HTTPClient.METHOD_GET, "/creation-options")
			if option_response.get("ok", false):
				creation_options = option_response
				creator.set_options(creation_options)
		await refresh_characters()
	else:
		var detail: String = str(core.get("detail", response.get("error", response.get("detail", "Core3 is not ready.")))) if core is Dictionary else "Core3 is not ready."
		status.text = "CORE3 UNAVAILABLE · " + detail
		status.add_theme_color_override("font_color", Color("e4bb86"))
	busy = false
	update_buttons()

func refresh_characters() -> void:
	if not account_ready():return
	var revision:=auth_revision
	var response := await api(HTTPClient.METHOD_GET, "/characters?account=" + account_input.text.strip_edges().uri_encode())
	if revision!=auth_revision or not account_ready():return
	characters = response.get("characters", [])
	character_list.clear()
	for character in characters:
		character_list.add_item(str(character.get("name", "Unnamed")) + "   ·   " + str(character.get("species", "human")).replace("_", " ").capitalize())
	if not characters.is_empty():
		character_list.select(0)
	if not response.get("ok", false):
		status.text = str(response.get("error", "Could not list characters."))

func open_creator() -> void:
	if not account_ready():
		show_account_panel()
		return
	menu.visible = false
	creator.visible = true
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	creator.set_backend_state(core3_ready)

func close_creator() -> void:
	creator.visible = false
	menu.visible = true

func create_character(payload: Dictionary) -> void:
	if busy or not core3_ready or not account_ready():
		return
	busy = true
	creator.set_working(true, "Saving your character…")
	update_buttons()
	payload["account"] = account_input.text.strip_edges()
	var result := await api(HTTPClient.METHOD_POST, "/characters", payload)
	if result.get("ok", false):
		status.text = "Character saved to the galaxy."
		await refresh_characters()
		var created: Dictionary = result.get("character", {})
		for i in range(characters.size()):
			if str(characters[i].get("id", "")) == str(created.get("id", "")):
				character_list.select(i)
				break
		creator.set_working(false, "Character created.")
		close_creator()
	else:
		creator.set_working(false, str(result.get("error", "Character creation failed.")))
	busy = false
	update_buttons()

func enter_character() -> void:
	if busy or not core3_ready or not account_ready() or character_list.get_selected_items().is_empty():
		return
	busy = true
	update_buttons()
	await stop_live_combat()
	var character: Dictionary = characters[character_list.get_selected_items()[0]]
	var result := await api(HTTPClient.METHOD_POST, "/enter", {"account": account_input.text.strip_edges(), "character_id": character.get("id", character.get("character_id", ""))})
	if result.get("ok", false) and result.get("backend", "") == "core3":
		await enter_stage(false, result)
	else:
		status.text = str(result.get("error", "Core3 did not confirm world entry."))
	busy = false
	update_buttons()

func enter_stage(offline: bool, entry := {}) -> void:
	if world_ready:
		status.text="Log off before entering another character or the offline viewer."
		return
	if loading_stage or (xr_requested and not xr_initialized):
		return
	if args.has("live-combat") and (offline or not args.has("combat-items")):
		status.text = "Live combat requires a real Core3 character and --combat-items."
		return
	await stop_live_combat()
	var desired_zone:=str(entry.get("source_location",{}).get("zone",entry.get("zone",entry.get("character",{}).get("zone","tatooine")))) if not offline else str(args.get("planet","tatooine"))
	planet_catalog.configure(str(args.get("planet-catalog",preload("res://scripts/planet_catalog.gd").DEFAULT_PATH)))
	var availability:=planet_catalog.readiness(desired_zone)
	if not availability.get("ok",false):status.text=str(availability.error);return
	active_planet=desired_zone;planet_assets=availability.descriptor
	if desired_zone!="tatooine" or stage_path.is_empty():stage_path=str(planet_assets.get("stage",""))
	if is_instance_valid(environment_presentation):retire_world_node(environment_presentation);environment_presentation=null
	make_environment()
	loading_stage = true
	desktop_voice_open=false
	if is_instance_valid(voice_chat):voice_chat.set_allowed(false)
	ensure_loading_screen()
	loading_screen.begin("Loading "+active_planet.capitalize()+"…")
	if is_instance_valid(xr_menu): xr_menu.set_open(false)
	if ambient_npcs != null:
		ambient_npcs.queue_free()
		ambient_npcs = null
	if environment_presentation != null:
		environment_presentation.set_active(false)
	world_ready = false
	native_poll_budget.reset()
	if is_instance_valid(inventory): inventory.set_allowed(false)
	if is_instance_valid(inventory_drops): inventory_drops.clear()
	if is_instance_valid(services): services.reset()
	if is_instance_valid(crafting): crafting.reset()
	if is_instance_valid(housing): housing.reset()
	if is_instance_valid(fishing): fishing.reset()
	if is_instance_valid(slicing): slicing.reset()
	if is_instance_valid(spice_world):spice_world.reset()
	if is_instance_valid(medic): medic.reset()
	if is_instance_valid(vehicles): vehicles.reset()
	if is_instance_valid(pets): pets.reset()
	if is_instance_valid(gathering): gathering.reset()
	if is_instance_valid(corpse_gathering): corpse_gathering.reset()
	inventory_snapshot.clear()
	inventory_equipment_revision=""; inventory_weapon_revision=""
	inventory_equipment_notice=""
	if is_instance_valid(combat_rig):
		combat_rig.queue_free()
		combat_rig = null
	if is_instance_valid(combat_target):
		combat_target.queue_free()
		combat_target = null
	datapad_epoch += 1
	datapad_character_id = "" if offline else str(entry.get("character_id", entry.get("character", {}).get("id", "")))
	datapad_account = account_input.text.strip_edges()
	if player.has_method("configure_player_combat"):
		player.feedback.reset()
		player.configure_player_combat(entry.get("weapon_snapshot", {}).get("player_combat", {}))
	if not is_instance_valid(entertainer):
		entertainer = preload("res://entertainment/controller.gd").new()
		add_child(entertainer)
	entertainer.configure(self,player,xr_origin if xr_requested else null,entry.get("entertainment",{}),datapad_account)
	entertainer.sync_equipment(inventory_snapshot.get("equipment",[]))
	if is_instance_valid(datapad):
		datapad.set_allowed(false)
		update_datapad_summary({})
		datapad.ui.set_entries([])
		datapad.ui.set_skills([], false)
		datapad.ui.set_experience({}, false)
	player.active = false
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	asset_status.text = "Loading original "+active_planet.capitalize()+" geometry…"
	loading_screen.set_status(asset_status.text)
	await present_loading_frame()
	if stage == null:
		stage = loader.load_stage(stage_path) if not stage_path.is_empty() else loader.empty_stream_stage(planet_assets,planet_default_spawn())
		if stage == null:
			fail_loading(str(loader.report.error))
			return
		stage.set_meta("planet",active_planet)
		add_child(stage)
	player.ground_provider = stage
	player.spawn_point = loader.vec(loader.report.get("spawn", [0, 2, 0]))
	player.spawn_yaw = float(args.get("yaw", loader.report.get("spawn_yaw", 0.0)))
	var saved_location: Dictionary=entry.get("source_location",{}) if not offline else {}
	if not saved_location.is_empty():
		if not medical_placement.destination_valid(saved_location):
			fail_loading("Core3 returned an unsupported saved location.");return
		var source: Array=saved_location.position
		var origin:=loader.vec(loader.report.origin)
		player.spawn_point=stage.to_global(Vector3(float(source[0])-origin.x,float(source[1])-origin.y,-(float(source[2])-origin.z)))
		player.spawn_yaw=-float(saved_location.get("heading_radians",0.0))
	if args.has("position"):
		var coordinates := str(args.position).split(",")
		if coordinates.size() == 3:
			player.spawn_point = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
			saved_location={}
	player.reset_spawn()
	if not offline:
		loading_screen.set_status("Preparing your character…")
		await present_loading_frame()
		# Capture any intentional avatar head-layer mask changes while keeping
		# the rendered loading cover isolated on the next frame.
		loading_screen.restore_camera()
		configure_player_avatar(entry)
		loading_screen.isolate_camera()
	loading_screen.set_status("Preparing nearby world and terrain…")
	await present_loading_frame()
	if world_stream == null and not args.has("no-world"):
		world_stream = WorldStream.new()
		add_child(world_stream)
		if not world_stream.configure(str(args.get("world-manifest",planet_assets.world)), stage):
			var error := str(world_stream.report.get("error","World manifest could not be loaded."))
			world_stream.set_process(false)
			world_stream.queue_free()
			world_stream = null
			fail_loading(error)
			return
	if terrain == null and not args.has("no-terrain"):
		terrain = TerrainStream.new()
		add_child(terrain)
		if not terrain.configure(str(planet_assets.terrain), loader.vec(loader.report.origin)):
			terrain.set_process(false)
			terrain.queue_free()
			terrain = null
			fail_loading(active_planet.capitalize()+" terrain could not be loaded. Check the original assets.")
			return
	if terrain != null:
		terrain.set_cell_source(stage)
		if player.get("step_solver") != null:
			player.step_solver.configure_terrain(terrain.evaluator,terrain.origin,0.0)
			terrain.bind_movement_solver(player.step_solver)
		player.void_floor_y = -4096.0
		if args.has("world-position"):
			var swg_coordinates := str(args["world-position"]).split(",")
			if swg_coordinates.size() == 2:
				player.spawn_point = terrain.terrain_position(Vector2(clampf(float(swg_coordinates[0]), -8190, 8190), clampf(float(swg_coordinates[1]), -8190, 8190)))
				saved_location={}
				player.reset_spawn()
		terrain.update_observer(player.global_position)
		player.set_physics_process(false)
		while not terrain.ready_near(player.global_position):
			asset_status.text = "Streaming %s ground… %d chunks" % [active_planet.capitalize(),terrain.chunks.size()]
			loading_screen.set_status(asset_status.text)
			await get_tree().process_frame
	if world_stream != null:
		world_stream.update_observer(player.global_position)
		player.set_physics_process(false)
		while not world_stream.report.get("ready", false):
			if not str(world_stream.report.get("error", "")).is_empty():
				fail_loading("World loading stopped: " + str(world_stream.report.error))
				return
			asset_status.text = "Loading nearby %s scenery… %d objects remaining" % [active_planet.capitalize(),world_stream.report.pending_instances]
			loading_screen.set_status(asset_status.text)
			await get_tree().process_frame
	loading_screen.set_status("Synchronizing collision and placing your character…")
	await present_loading_frame()
	if xr_requested:
		player.prepare_tracked_body()
	stage.set_observer(player)
	if not saved_location.is_empty():
		var saved_cell: String=medical_placement.source_cell(saved_location)
		if not saved_cell.is_empty() and not stage.definitions.has(saved_cell):
			fail_loading("The original saved interior is unavailable: "+saved_cell);return
		stage.seed_membership_at(player.global_position,saved_cell if not saved_cell.is_empty() else "exterior")
	else:seed_spawn_membership()
	# Newly installed Jolt collision must be synchronized before the spawn sweep.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if xr_requested and not ground_xr_spawn():
		fail_loading("No safe ground under the VR spawn. Select an entry point with a floor.")
		return
	stage.update_cell()
	if portal_visibility == null:
		portal_visibility = load("res://scripts/portal_visibility.gd").new()
		add_child(portal_visibility)
		portal_visibility.culling_enabled = not args.has("no-portal-culling")
		portal_visibility.configure(stage, player.get_camera(), xr_spectator.camera if is_instance_valid(xr_spectator) and xr_spectator.enabled else null)
	if environment_presentation != null:
		environment_presentation.bind_world(terrain,stage)
		environment_presentation.update_observer(player.global_position)
		environment_presentation.set_active(true)
	loading_screen.set_status("Preparing inhabitants and ambience…")
	await present_loading_frame()
	if ambient_npcs != null:
		ambient_npcs.queue_free()
	ambient_npcs = AmbientNPCs.new()
	radar_contacts.clear()
	ambient_npcs.animation_cache_enabled = not args.has("no-animation-cache")
	ambient_npcs.hidden_animation_enabled = not args.has("no-hidden-animation")
	add_child(ambient_npcs)
	ambient_npcs.set_visibility_provider(portal_visibility)
	if ambient_npcs.configure(str(planet_assets.ambient_placements),stage,terrain):
		radar_contacts.configure(ambient_npcs)
		ambient_npcs.update_observer(player.global_position)
		while not ambient_npcs.report.get("ready",false):
			loading_screen.set_status("Preparing inhabitants… %d remaining" % int(ambient_npcs.report.get("pending",0)))
			await get_tree().process_frame
	get_node("/root/SWGSpatialAudio").configure(player.get_camera(),stage,str(args.get("spatial-audio","steam_audio")))
	player.testing = smoke_mode or not screenshot_path.is_empty()
	session_mode = "OFFLINE ASSET INSPECTION" if offline else "CORE3 CHARACTER · LOCAL MOVEMENT · " + str(entry.get("name", "Character"))
	mode_label.text = active_planet.to_upper()+"   /   " + session_mode
	asset_status.text = "%d mesh instances · %d collision bodies\nLocomotion is local to this prototype." % [loader.report.instances, loader.report.collision_bodies]
	resume_button.visible = true
	if args.has("combat-lab"):
		configure_combat_lab()
	elif args.has("combat-items") and not offline:
		configure_combat_lab(entry.get("weapon_snapshot",{}))
	if is_instance_valid(datapad):
		datapad.avatar = tracked_avatar
		datapad.ui.set_planet(active_planet)
		await refresh_datapad()
	if is_instance_valid(inventory):
		inventory.avatar = tracked_avatar
		loading_screen.set_status("Reading Core3 inventory…")
		await refresh_inventory()
	if args.has("live-combat"):
		loading_screen.set_status("Connecting to live Core3 combat…")
		if not await start_live_combat():
			fail_loading("Live Core3 combat could not start: " + (live_combat.last_error if is_instance_valid(live_combat) else "No authenticated ranged weapon."))
			return
	elif not offline:
		loading_screen.set_status("Keeping your Core3 character connected…")
		if not await ensure_gameplay_session():
			fail_loading("Core3 gameplay connection failed: "+gameplay_session.last_error);return
		if not gameplay_session.pending_transport.is_empty():
			if not await perform_live_transport(gameplay_session.pending_transport,true):return
		elif gameplay_session.player_state.get("position") is Array:
			var native_destination: Dictionary=gameplay_session.player_state.duplicate(true)
			var native_placement: Dictionary=await medical_placement.place(self,native_destination)
			if not native_placement.get("ok",false):fail_loading(str(native_placement.get("error","Native character placement failed.")));return
	if not is_instance_valid(services):
		services = preload("res://scripts/services_controller.gd").new()
		add_child(services)
		services.setup(self)
	else:
		services.reset()
	if not offline and not is_instance_valid(multiplayer_sync):
		multiplayer_sync=preload("res://multiplayer/client_sync.gd").new();add_child(multiplayer_sync);multiplayer_sync.setup(self)
	if not offline and is_instance_valid(multiplayer_sync):
		loading_screen.set_status("Synchronizing nearby players and entities…")
		var synchronized:bool=await multiplayer_sync.prime()
		session_mode="CORE3 MULTIPLAYER · "+str(entry.get("name","Character"))
		mode_label.text=active_planet.to_upper()+" / "+session_mode
		asset_status.text="Persistent Core3 character · shared nearby players and entities · tracked local locomotion" if synchronized else "Core3 connected · waiting for multiplayer world sync: "+multiplayer_sync.last_error
	if not offline and not is_instance_valid(mission_parcels):
		mission_parcels=preload("res://scripts/mission_parcels.gd").new();add_child(mission_parcels);mission_parcels.setup(self)
	if not offline and not is_instance_valid(vendor_placement):
		vendor_placement=preload("res://scripts/vendor_placement.gd").new();add_child(vendor_placement);vendor_placement.setup(self)
	if not offline and not is_instance_valid(vendor_commerce):
		vendor_commerce=preload("res://scripts/vendor_commerce.gd").new();add_child(vendor_commerce);vendor_commerce.setup(self)
	loading_screen.set_status("Ready to enter "+active_planet.capitalize()+"")
	await present_loading_frame()
	world_ready = true
	loading_stage = false
	player.set_physics_process(true)
	loading_screen.finish()
	close_menu()
	if args.has("freeze-camera") and not screenshot_path.is_empty():
		player.active = false
	if not xr_requested and args.has("third-person"):
		player.third_person = true
		player.camera_orbit_yaw = float(args.get("orbit-yaw", args.get("orbit", 0.0)))
	if not xr_requested and args.has("pitch"):
		player.camera_pitch = float(args.pitch)

func planet_default_spawn()->Vector3:
	var source:Variant=planet_assets.get("default_entry",[])
	if source.is_empty() and not planet_assets.get("travel_points",[]).is_empty():source=planet_assets.travel_points[0]
	var point:Variant=source.get("position",[0,2,0]) if source is Dictionary else source if source is Array and source.size()==3 else [0,2,0]
	var position:Vector3=loader.vec(point)-loader.vec(planet_assets.get("origin",[0,0,0]))
	return Vector3(position.x,position.y+1,-position.z)

func prepare_destination_world(destination:Dictionary)->Dictionary:
	return await planet_transition.prepare(self,destination)

func install_planet_world(destination:Dictionary)->Dictionary:
	return await planet_transition.install(self,destination)

func ensure_loading_screen() -> void:
	if is_instance_valid(loading_screen): return
	loading_screen = preload("res://scripts/loading_screen.gd").new()
	add_child(loading_screen)
	if xr_requested and is_instance_valid(player): loading_screen.attach_head(player.get_camera())

func present_loading_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw

func fail_loading(message: String) -> void:
	world_ready = false
	loading_stage = false
	player.active = false
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	asset_status.text = message
	loading_screen.fail(message)
	push_error(message)

func dismiss_loading_error() -> bool:
	if loading_screen==null or not loading_screen.failed or not loading_screen.active: return false
	if not retry_transport.is_empty():
		planet_catalog.configure(str(args.get("planet-catalog",preload("res://scripts/planet_catalog.gd").DEFAULT_PATH)))
		loading_stage=false
		if retry_transport_service:perform_service_transport(retry_transport)
		else:perform_live_transport(retry_transport,false)
		return true
	loading_screen.finish()
	menu.visible = true
	player.active = false
	if is_instance_valid(xr_menu): xr_menu.set_open(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

func close_menu() -> void:
	if stage == null or loading_stage or not world_ready or session_leaving or not logout_payload.is_empty():
		return
	menu.visible = false
	player.active = not xr_diagnostic_active()
	if xr_requested:
		xr_menu.set_open(false)
		sync_xr_activity()
	if not xr_requested and not smoke_mode and screenshot_path.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if session_leaving or not logout_payload.is_empty():return
	if not xr_requested and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F12 and world_ready and not menu.visible:
		desktop_voice_open=not desktop_voice_open
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if desktop_voice_open else Input.MOUSE_MODE_CAPTURED
		player.active=not desktop_voice_open
		get_viewport().set_input_as_handled()
		return
	if xr_diagnostic_active() and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		xr_bottleneck_suite.cancel("Cancelled with Escape")
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if dismiss_loading_error(): return
	if loading_stage or (is_instance_valid(loading_screen) and loading_screen.active): return
	if not is_instance_valid(player) or not is_instance_valid(menu): return
	if xr_requested:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			toggle_xr_menu()
		return
	if smoke_mode or not screenshot_path.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if stage == null or not world_ready:
				return
			menu.visible = not menu.visible
			player.active = not menu.visible and stage != null
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_V and stage != null and not menu.visible:
			player.third_person = not player.third_person
		elif event.keycode in [KEY_C, KEY_P, KEY_X] and stage != null and not menu.visible:
			var desired: int = {KEY_C: 1, KEY_P: 2, KEY_X: 3}[event.keycode]
			player.request_posture(0 if player.posture == desired else desired)
		elif event.keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4] and avatar != null and not menu.visible:
			var action: String = {KEY_F1: "emote_wave1", KEY_F2: "emote_bow", KEY_F3: "face_smile", KEY_F4: "face_blink"}[event.keycode]
			play_avatar_action(action)
		elif event.keycode == KEY_R and stage != null and not menu.visible:
			player.reset_spawn()

func play_avatar_action(action: String) -> bool:
	if xr_requested:
		return false
	if avatar == null:
		return false
	if action.begins_with("emote_"):
		if not player.request_posture(0):
			status.text = "Find standing room before using that emote."
			return false
		# Keep the animation state in sync when an emote explicitly stands up;
		# otherwise the next frame would replace it with a posture transition.
		avatar.previous_posture = 0
	return avatar.play_action(action)

func entertainer_interaction_blocks() -> bool:
	return (is_instance_valid(entertainer) and entertainer.has_method("blocks_interactions") and entertainer.blocks_interactions()) or (is_instance_valid(scout) and scout.has_method("blocks_interactions") and scout.blocks_interactions())

func gameplay_gesture_reserved() -> bool:
	if is_instance_valid(pets) and is_instance_valid(pets.creature_handler) and pets.creature_handler.reserves_datapad():
		return true
	return is_instance_valid(entertainer) and entertainer.reserves_datapad()

func corpse_interaction_blocks() -> bool:
	if entertainer_interaction_blocks():return true
	if is_instance_valid(vendor_commerce) and vendor_commerce.blocks_interactions():return true
	if is_instance_valid(vendor_placement) and vendor_placement.blocks_interactions():return true
	if is_instance_valid(mission_parcels) and mission_parcels.blocks_interactions():return true
	if (is_instance_valid(voice_controls) and voice_controls.blocks_combat()) or (is_instance_valid(desktop_voice_panel) and desktop_voice_panel.visible):return true
	return (is_instance_valid(corpse_gathering) and corpse_gathering.blocks_combat()) or (is_instance_valid(services) and services.blocks_combat())

func xr_diagnostic_active() -> bool:
	return is_instance_valid(xr_bottleneck_suite) and xr_bottleneck_suite.active

func ensure_gameplay_combat() -> void:
	if live_combat_reserved or not world_ready or not is_instance_valid(gameplay_session) or not gameplay_session.live or not is_instance_valid(multiplayer_sync) or not is_instance_valid(combat_rig):return
	if not is_instance_valid(gameplay_combat):
		gameplay_combat=preload("res://multiplayer/gameplay_combat.gd").new();add_child(gameplay_combat)
		gameplay_combat.attach(self,combat_rig,gameplay_session,multiplayer_sync)
		if is_instance_valid(combat_target):combat_target.queue_free();combat_target=null
		session_mode="CORE3 MULTIPLAYER · "+str(gameplay_session.player_state.get("name","Character"));mode_label.text=active_planet.to_upper()+" / "+session_mode
		asset_status.text="Persistent Core3 session · equipped ranged attacks use native combat authority."

func interface_button(button: String, side: String) -> bool:
	if button!="primary_click" or not xr_focused or not world_ready or menu.visible:return false
	var hand:XRController3D=xr_origin.get_node(side.capitalize()+"Hand")
	if not preload("res://scripts/tracked_hand_input.gd").controller_tracked(hand) or not bool(player.combat_tracking_context().tracked):return false
	if is_instance_valid(crafting) and crafting.is_open:return crafting.confirm_button(side)
	if is_instance_valid(services) and is_instance_valid(services.ui):return services.ui.confirm_button(side)
	return false

func _process(_delta: float) -> void:
	ensure_gameplay_combat()
	update_voice_chat()
	var diagnostic_active := xr_diagnostic_active()
	if diagnostic_active and is_instance_valid(player): player.active = false
	var parcel_blocks:bool=entertainer_interaction_blocks() or (is_instance_valid(mission_parcels) and mission_parcels.blocks_interactions()) or (is_instance_valid(vendor_placement) and vendor_placement.blocks_interactions()) or (is_instance_valid(vendor_commerce) and vendor_commerce.blocks_interactions())
	var service_blocks: bool = (is_instance_valid(services) and services.blocks_combat()) or parcel_blocks
	if is_instance_valid(services):
		services.set_allowed(not diagnostic_active and (not xr_requested or xr_focused) and world_ready and not loading_stage and not menu.visible and not creator.visible and not player.feedback.life_locked and not (is_instance_valid(crafting) and crafting.is_open) and not (is_instance_valid(inventory) and inventory.blocks_services() and not services.inventory_accessible()) and not (is_instance_valid(datapad) and datapad.is_open))
	if (entertainer_interaction_blocks() or (is_instance_valid(vendor_placement) and vendor_placement.blocks_interactions()) or (is_instance_valid(vendor_commerce) and vendor_commerce.blocks_interactions())) and is_instance_valid(services) and is_instance_valid(services.ui):services.ui.set_allowed(false)
	if is_instance_valid(services) and is_instance_valid(services.ui):services.ui.set_inventory_focus(is_instance_valid(inventory) and inventory.blocks_services())
	var inventory_available:bool=not parcel_blocks and not (is_instance_valid(services) and services.blocks_inventory()) and not diagnostic_active and xr_focused and world_ready and not loading_stage and not menu.visible and not creator.visible
	if is_instance_valid(inventory):
		inventory.set_allowed(inventory_available and not (is_instance_valid(datapad) and datapad.is_open))
	if is_instance_valid(housing):
		# Choosing a source blueprint suspends the factory controls but retains its panel.
		var factory_datapad_overlay:bool=is_instance_valid(housing.factory_panel) and housing.factory_panel.is_open and is_instance_valid(datapad) and datapad.is_open
		housing.set_allowed(is_instance_valid(inventory) and inventory_available and (inventory.allowed or factory_datapad_overlay) and not player.feedback.life_locked)
	if is_instance_valid(fishing):fishing.set_allowed(is_instance_valid(inventory) and inventory.allowed and not player.feedback.life_locked)
	if is_instance_valid(slicing):slicing.set_allowed(is_instance_valid(inventory) and inventory.allowed and not session_leaving)
	if is_instance_valid(pets):
		pets.set_allowed(not service_blocks and not diagnostic_active and xr_focused and world_ready and not loading_stage and not menu.visible and not creator.visible and not player.feedback.life_locked and not (is_instance_valid(datapad) and datapad.is_open) and not (is_instance_valid(inventory) and inventory.interaction_active))
	if is_instance_valid(corpse_gathering):
		corpse_gathering.set_allowed(not parcel_blocks and not live_combat_reserved and not diagnostic_active and xr_focused and world_ready and not loading_stage and not menu.visible and not creator.visible and not (is_instance_valid(datapad) and datapad.is_open) and not (is_instance_valid(inventory) and inventory.interaction_active))
	var inventory_blocks: bool = is_instance_valid(inventory) and inventory.blocks_combat()
	if is_instance_valid(housing) and ((is_instance_valid(housing.harvester_panel) and housing.harvester_panel.is_open) or (is_instance_valid(housing.factory_panel) and housing.factory_panel.is_open)):inventory_blocks=true
	if is_instance_valid(combat_rig):
		combat_rig.set_allowed(not service_blocks and not player.feedback.life_locked and (not live_combat_reserved or (is_instance_valid(live_combat) and live_combat.is_ready())) and not diagnostic_active and not inventory_blocks and not inventory_request_pending and world_ready and not loading_stage and not menu.visible and not creator.visible and (not xr_requested or xr_focused) and not (is_instance_valid(datapad) and datapad.is_open))
	if is_instance_valid(datapad):
		datapad.set_gesture_reserved(gameplay_gesture_reserved())
		datapad.set_allowed(not datapad.gesture_reserved and not service_blocks and not live_combat_reserved and not diagnostic_active and not (is_instance_valid(inventory) and inventory.interaction_active) and xr_focused and world_ready and not loading_stage and not menu.visible and not creator.visible)
		if world_ready:
			datapad.ui.set_player_position(datapad_source_position())
	if player != null and (loading_stage or not world_ready):
		# Loading owns the physics gate. Streaming readiness must not override it
		# while scenery/cell collision or spawn grounding are still pending.
		player.set_physics_process(false)
		return
	if environment_presentation != null:
		environment_presentation.update_observer(player.global_position)
	if ambient_npcs != null and not (diagnostic_active and xr_bottleneck_suite.npc_frozen):
		ambient_npcs.update_observer(player.global_position)
	if avatar != null and avatar.get("meshes") is Array:
		for mesh in avatar.meshes:
			mesh.set_instance_shader_parameter("swg_indoor", 1.0 if stage != null and not stage.current_cell.is_empty() else 0.0)
	if world_stream != null and stage != null:
		world_stream.update_observer(player.global_position)
	if terrain != null and stage != null:
		var bounded: Vector3 = terrain.constrain_position(player.global_position)
		if bounded != player.global_position:
			if xr_requested:
				player.apply_world_correction(bounded-player.global_position)
			else:
				player.global_position = bounded
			player.velocity.x = 0.0
			player.velocity.z = 0.0
		terrain.update_observer(player.global_position)
		# Wait for nearby support after a reset/teleport; prefetch covers normal traversal.
		player.set_physics_process(terrain.ready_near(player.global_position, 0))
	if not xr_requested and avatar != null and stage != null:
		var turning: float = angle_difference(avatar_previous_yaw, player.rotation.y) / maxf(_delta, 0.001)
		avatar_previous_yaw = player.rotation.y
		avatar.update_motion(_delta, Vector2(player.velocity.x, player.velocity.z).length(), {"velocity": player.global_basis.inverse() * player.velocity, "grounded": player.get_grounded() if player.has_method("get_grounded") else player.is_on_floor(), "posture": player.posture, "turn_rate": turning, "presentation":player.feedback.animation_context()})
	if stage != null:
		hud.text = "WASD move  ·  Mouse look  ·  Shift run  ·  Space jump/recover  ·  V view  ·  Alt+mouse orbit  ·  Esc menu  ·  R reset\nC crouch · P prone · X sit · F1 wave · F2 bow · F3 smile · F4 blink\n%s · Streamed terrain   /   Position  %.1f  /  %.1f  /  %.1f   ·   %d FPS" % [active_planet.capitalize(),player.global_position.x, player.global_position.y, player.global_position.z, Engine.get_frames_per_second()]
		if not live_appearance_text.is_empty(): hud.text += "\n" + live_appearance_text

func stage_smoke() -> void:
	if stage == null:
		print("STAGE_SMOKE_FAIL: " + str(loader.report.get("error", "stage unavailable")))
		get_tree().quit(1)
		return
	player.testing = true
	for i in range(180):
		await get_tree().physics_frame
	var grounded: bool = player.get_grounded() if player.has_method("get_grounded") else player.is_on_floor()
	var start: Vector3 = player.global_position
	player.test_input = Vector2(1, 0)
	for i in range(30):
		await get_tree().physics_frame
	player.test_input = Vector2.ZERO
	var moved := player.global_position.distance_to(start)
	player.reset_spawn()
	for i in range(90):
		await get_tree().physics_frame
	var wall_origin: Vector3 = player.global_position + Vector3.UP * 0.9
	var nearest_distance := 30.0
	var wall_direction := Vector3.ZERO
	var wall_hit_position := Vector3.ZERO
	var wall_normal := Vector3.ZERO
	for i in range(16):
		var direction := Vector3(sin(i * TAU / 16), 0, cos(i * TAU / 16))
		var query := PhysicsRayQueryParameters3D.create(wall_origin, wall_origin + direction * 25)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var distance: float = wall_origin.distance_to(hit.position)
			if distance < nearest_distance and absf(hit.normal.y) < 0.25:
				nearest_distance = distance
				wall_direction = direction
				wall_hit_position = hit.position
				wall_normal = hit.normal
	var wall_start: Vector3 = player.global_position
	var local_direction: Vector3 = player.global_basis.inverse() * wall_direction
	player.test_input = Vector2(local_direction.x, local_direction.z)
	var wall_source := ""
	for i in range(int((nearest_distance + 2) / player.speed * 60)):
		await get_tree().physics_frame
		for collision_index in range(player.get_slide_collision_count()):
			var collision: KinematicCollision3D = player.get_slide_collision(collision_index)
			if absf(collision.get_normal().y) < 0.25:
				var collider = collision.get_collider()
				if collider is StaticBody3D and collider.get_parent() is MeshInstance3D:
					wall_source = str(collider.get_parent().get_meta("source_template", "imported_mesh"))
	player.test_input = Vector2.ZERO
	var wall_travel: float = (player.global_position - wall_start).dot(wall_direction)
	var wall_clearance: float = (player.global_position - wall_hit_position).dot(wall_normal)
	var wall_stopped: bool = wall_direction != Vector3.ZERO and wall_clearance >= -0.03 and wall_travel > 0.05 and not wall_source.is_empty()
	var result := {"test": "stage_spawn_locomotion_and_imported_wall", "controller": player.get_class(), "mesh_builder": loader.native_builder.get_class(), "native": player is SwgFirstPersonController and loader.native_builder is SwgMeshBuilder, "mesh_count": loader.report.meshes, "grounded": grounded, "spawn": str(player.spawn_point), "settled_position": str(start), "movement_distance": moved, "wall_ray_distance": nearest_distance, "wall_actual_travel": wall_travel, "wall_clearance": wall_clearance, "wall_stopped": wall_stopped, "wall_source": wall_source, "instances": loader.report.instances, "collision_bodies": loader.report.collision_bodies}
	write_evidence(result)
	print(JSON.stringify(result))
	var passed: bool = grounded and moved > 0.1 and wall_stopped and loader.report.collision_bodies > 0
	print("STAGE_SMOKE_PASS" if passed else "STAGE_SMOKE_FAIL: grounding, movement, or actual imported wall failed")
	get_tree().quit(0 if passed else 1)

func take_screenshot(quit_when_done := true) -> void:
	await get_tree().create_timer(2.0).timeout
	for i in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(screenshot_path)
	print("SCREENSHOT " + screenshot_path + " " + error_string(result))
	if quit_when_done:
		get_tree().quit(0 if result == OK else 1)

func integration_test() -> void:
	await refresh_backend()
	if not core3_ready:
		print("INTEGRATION_FAIL: " + status.text)
		get_tree().quit(1)
		return
	var generated_name := ""
	for i in range(8):
		generated_name += char(97 + randi_range(0, 25))
	if not args.has("account"):
		account_input.text = "probe" + generated_name
	var requested_name: String = str(args.get("character", generated_name.capitalize()))
	var result := await api(HTTPClient.METHOD_POST, "/characters", {"account": account_input.text, "name": requested_name, "species": "human"})
	if not result.get("ok", false):
		print("INTEGRATION_FAIL_CREATE: " + JSON.stringify(result))
		get_tree().quit(1)
		return
	await refresh_characters()
	var found := {}
	for character in characters:
		if str(character.get("name", "")).to_lower() == requested_name.to_lower():
			found = character
			break
	if found.is_empty():
		print("INTEGRATION_FAIL_LIST: created character absent")
		get_tree().quit(1)
		return
	var entered := await api(HTTPClient.METHOD_POST, "/enter", {"account": account_input.text, "character_id": found.get("id", found.get("character_id", ""))})
	if not entered.get("ok", false) or entered.get("backend", "") != "core3":
		print("INTEGRATION_FAIL_ENTER: " + JSON.stringify(entered))
		get_tree().quit(1)
		return
	write_evidence({"test": "core3_character_created_listed_entered", "account": account_input.text, "entry": entered})
	var entry_evidence: Dictionary = entered.duplicate(true)
	if entry_evidence.has("entertainment"): entry_evidence.entertainment.erase("token")
	print("CORE3_CHARACTER_CREATED_LISTED_ENTERED " + JSON.stringify(entry_evidence))
	await enter_stage(false, entered)
	if not screenshot_path.is_empty():
		await take_screenshot(false)
	await stage_smoke()

func write_evidence(value: Dictionary) -> void:
	if not args.has("evidence"):
		return
	var path: String = str(args.evidence)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(value))
		file.close()

func apply_native_appearance(value: Dictionary) -> void:
	if not is_instance_valid(avatar) or value.is_empty():return
	var current:Dictionary=avatar.appearance
	var hair:Dictionary=value.get("hair",{}) if value.get("hair") is Dictionary else {}
	var incoming:Array=[value.get("customization",{}),float(value.get("height",1.0)),hair.get("template",""),hair.get("customization",{})]
	var previous:Array=[current.get("customization",{}),float(current.get("height",1.0)),current.get("hair_template",""),current.get("hair_customization",{})]
	# Inventory owns equipment updates; only changed body/hair data rebuilds the rig.
	if incoming==previous:return
	var appearance:Dictionary=value.duplicate(true)
	appearance.hair_template=hair.get("template","");appearance.hair_customization=hair.get("customization",{})
	var hidden_ids:Array=avatar.hidden_equipment_ids.duplicate()
	var hidden_templates:Array=avatar.hidden_equipment_templates.duplicate()
	var result:Dictionary=avatar.configure(str(value.get("race",avatar.race_id)),appearance,value.get("equipment",[]))
	if not str(result.get("error","")).is_empty():
		asset_status.text="Avatar appearance: "+str(result.error);return
	avatar.set_equipment_visual_hidden(hidden_ids,hidden_templates)
	if is_instance_valid(tracked_avatar):
		var original_mask:int=tracked_avatar.original_cull_mask
		tracked_avatar.configure(avatar,xr_origin)
		tracked_avatar.original_cull_mask=original_mask
		if vr_settings.standing_eye_height>=.8:tracked_avatar.set_standing_eye_height(vr_settings.standing_eye_height)
	elif player.has_method("set_avatar_height"):player.set_avatar_height(avatar.height_meters)

func configure_player_avatar(entry: Dictionary) -> void:
	if tracked_avatar != null:
		tracked_avatar.free()
		tracked_avatar = null
		avatar = null
	if avatar != null:
		avatar.free()
	avatar = null
	if xr_requested:
		player.set_meta("core3_character", entry.get("character", {}))
	var character: Dictionary = entry.get("character", {})
	var appearance: Dictionary = character.get("appearance", {}).duplicate(true)
	if appearance.is_empty():
		asset_status.text = "Core3 supplied no appearance data; avatar unavailable."
		return
	var race: String = appearance.get("race", "")
	if race.begins_with("object/"):
		race = race.get_file().trim_suffix(".iff").trim_prefix("shared_")
	if race.is_empty():
		race = str(appearance.get("species", "human")) + "_" + str(appearance.get("sex", "male"))
	var hair = appearance.get("hair")
	if hair is Dictionary:
		appearance["hair_template"] = hair.get("template", "")
		appearance["hair_customization"] = hair.get("customization", {})
	avatar = Avatar.new()
	if xr_requested:
		tracked_avatar = TrackedAvatar.new()
		add_child(tracked_avatar)
		tracked_avatar.add_child(avatar)
	else:
		player.add_child(avatar)
	var result: Dictionary = avatar.configure(race, appearance, appearance.get("equipment", entry.get("equipment", [])))
	if not str(result.get("error", "")).is_empty():
		asset_status.text = "Avatar: " + str(result.error)
		if tracked_avatar != null:
			tracked_avatar.free()
			tracked_avatar = null
			avatar = null
	elif xr_requested:
		if not tracked_avatar.configure(avatar, xr_origin):
			asset_status.text = "Avatar skeleton cannot be retargeted to tracked poses."
			tracked_avatar.free()
			tracked_avatar = null
			avatar = null
		else:
			if vr_settings.standing_eye_height >= 0.8:
				tracked_avatar.set_standing_eye_height(vr_settings.standing_eye_height)
			action_row.visible = false
			write_evidence({"test":"authoritative_tracked_avatar", "character_id":entry.get("character_id", ""), "avatar":result})
	else:
		if player.has_method("set_avatar_height"):
			player.set_avatar_height(avatar.height_meters)
		avatar_previous_yaw = player.rotation.y
		avatar.preview_animation = str(args.get("animation", ""))
		avatar.preview_time = float(args.get("animation-time", 0.4))
		action_pick.clear()
		for key in avatar.animation_library:
			action_pick.add_item(str(key).replace("emote_", "").replace("_", " ").capitalize())
			action_pick.set_item_metadata(action_pick.item_count - 1, key)
		action_row.visible = action_pick.item_count > 0
		write_evidence({"test": "authoritative_player_avatar", "character_id": entry.get("character_id", ""), "appearance_source": appearance.get("source", ""), "avatar": result})

func initialize_xr() -> bool:
	prepare_xr_viewport()
	xr_start = StartXR.instantiate()
	xr_start.viewport = xr_viewport
	xr_start.xr_started.connect(func():
		xr_focused = true
		if xr_menu != null and xr_menu.visible:
			xr_menu.place_in_front()
		sync_xr_activity()
	)
	xr_start.xr_ended.connect(func():
		xr_focused = false
		sync_xr_activity()
	)
	add_child(xr_start)
	xr_initialized = xr_start.xr_interface != null and xr_start.xr_interface.is_initialized()
	if not xr_initialized:
		xr_origin.reparent(self, true)
		xr_viewport.queue_free()
		xr_viewport = null
		get_viewport().audio_listener_enable_3d = true
		return false
	if xr_start.xr_interface is OpenXRInterface:
		xr_start.xr_interface.pose_recentered.connect(recenter_xr)
		xr_start.xr_interface.session_stopping.connect(func():
			xr_focused = false
			sync_xr_activity()
		)
	xr_menu = XRMenu.new()
	add_child(xr_menu)
	xr_menu.configure(ui_root, player.get_camera())
	xr_spectator = load("res://xr/spectator.tscn").instantiate()
	add_child(xr_spectator)
	xr_spectator.configure(xr_origin, player)
	xr_spectator.enabled = not args.has("no-spectator")
	datapad = load("res://scripts/xr_datapad.gd").new()
	add_child(datapad)
	datapad.configure(xr_origin,player,vr_settings.offhand)
	player.dominant_hand = "right" if vr_settings.offhand == "left" else "left"
	player.interface_button_handler=interface_button
	if vr_settings.standing_eye_height >= 0.8:
		player.feedback.stance.set_standing_eye_height(vr_settings.standing_eye_height)
	datapad.radar_contacts_provider = get_radar_contacts
	datapad.opened.connect(refresh_datapad)
	datapad.new_waypoint_requested.connect(create_datapad_waypoint)
	datapad.delete_entry_requested.connect(delete_datapad_entry)
	inventory = load("res://scripts/xr_inventory.gd").new()
	add_child(inventory)
	inventory.configure(xr_origin,player,vr_settings.offhand)
	datapad.summary_ui.equipment_requested.connect(open_datapad_equipment)
	inventory.external_grab_blocker=func()->bool:return is_instance_valid(services) and services.blocks_inventory()
	inventory_drops = load("res://scripts/local_inventory_drops.gd").new()
	add_child(inventory_drops)
	inventory_drops.configure(inventory.assets)
	inventory.world_pickup_provider = inventory_pickup_candidate
	inventory.refresh_requested.connect(refresh_inventory)
	inventory.stack_split_requested.connect(split_inventory_stack)
	inventory.equip_requested.connect(equip_inventory_item)
	inventory.unequip_requested.connect(unequip_inventory_item)
	inventory.consume_requested.connect(consume_inventory_item)
	inventory.vehicle_deed_requested.connect(activate_inventory_vehicle_deed)
	inventory.item_drop_requested.connect(drop_inventory_item)
	inventory.item_take_requested.connect(take_inventory_item)
	inventory.item_held_changed.connect(inventory_held_changed)
	inventory.item_ready_for_use.connect(ready_inventory_item)
	inventory.opened.connect(func():
		if is_instance_valid(combat_rig): combat_rig.stop_inventory_item())
	inventory.backpack_presentation_changed.connect(show_equipped_backpack)
	gathering=load("res://scripts/resource_gathering.gd").new()
	add_child(gathering)
	gathering.configure(self,inventory)
	crafting=load("res://scripts/crafting_controller.gd").new()
	add_child(crafting)
	crafting.setup(self,inventory)
	housing=load("res://housing/controller.gd").new();add_child(housing);housing.setup(self,inventory)
	fishing=load("res://fishing/controller.gd").new();add_child(fishing);fishing.setup(self,inventory)
	slicing=load("res://slicing/controller.gd").new();add_child(slicing);slicing.setup(self,inventory)
	spice_world=preload("res://spice/world_effects.gd").new();add_child(spice_world);spice_world.setup(self)
	scout=load("res://scout/controller.gd").new();add_child(scout);scout.setup(self,inventory)
	medic=load("res://medic/controller.gd").new();add_child(medic);medic.setup(self,inventory)
	vehicles=load("res://vehicles/controller.gd").new();add_child(vehicles);vehicles.setup(self,inventory)
	datapad.ui.call_vehicle_requested.connect(vehicles.call_vehicle)
	datapad.ui.recall_vehicle_requested.connect(vehicles.recall_vehicle)
	pets=load("res://pets/controller.gd").new();add_child(pets);pets.setup(self,vehicles)
	datapad.ui.droid_action_requested.connect(pets.request_entry)
	corpse_gathering=load("res://scripts/corpse_gathering_controller.gd").new()
	add_child(corpse_gathering)
	corpse_gathering.configure(self,inventory)
	# Stereo goes only to the headset viewport. The desktop draws the mono
	# spectator texture and never selects a different camera for the HMD.
	get_viewport().use_xr = false
	get_viewport().disable_3d = true
	# No desktop mouse capture in XR: pointers route input to the UI viewport.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	xr_focused = XRToolsStartXR.is_xr_active()
	return true

func prepare_xr_viewport() -> void:
	if is_instance_valid(xr_viewport):
		return
	xr_viewport = SubViewport.new()
	xr_viewport.name = "HeadsetViewport"
	xr_viewport.world_3d = get_world_3d()
	xr_viewport.audio_listener_enable_3d = true
	get_viewport().audio_listener_enable_3d = false
	xr_viewport.size = Vector2i(1440, 900)
	xr_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(xr_viewport)
	xr_origin.reparent(xr_viewport, true)

func toggle_xr_menu() -> void:
	if not account_ready():
		show_account_panel()
		return
	if xr_diagnostic_active():
		xr_bottleneck_suite.cancel("Cancelled with controller menu button")
		return
	if dismiss_loading_error(): return
	if not xr_initialized or xr_menu == null or busy or loading_stage:
		return
	if creator.visible:
		close_creator()
	elif menu.visible and stage != null:
		close_menu()
	else:
		menu.visible = true
		xr_menu.set_open(true)
		sync_xr_activity()

func sync_xr_activity() -> void:
	if is_instance_valid(xr_menu):xr_menu.set_input_active(xr_focused)
	if xr_requested and is_instance_valid(player):
		player.active = not xr_diagnostic_active() and xr_focused and world_ready and not loading_stage and stage != null and not menu.visible and not creator.visible

func recenter_xr() -> void:
	# Stage-space recenter changes yaw about the tracked head, never world position
	# or physical height. The XR Tools primitive preserves the camera pivot.
	if not xr_initialized:
		return
	player.rotate_player(player.get_camera().global_rotation.y - player.spawn_yaw)
	if xr_menu != null and xr_menu.visible:
		xr_menu.place_in_front()

func seed_spawn_membership() -> void:
	# Loading may begin metres above an authored floor. This explicit placement
	# query is broader than normal portal traversal, but cannot select a buried
	# room below exterior terrain when spawning above that terrain.
	var point := player.global_position
	var candidate: Dictionary = stage.ground_support.sample_support(point, stage.definitions.keys(), 0.1, 8.0, {})
	player.set_meta("spawn_support", candidate)
	if not candidate.get("valid", false):
		stage.seed_membership_at(point)
		return
	var floor_y := float(candidate.height)
	if terrain != null:
		var ground: Vector3 = terrain.terrain_position(terrain.source_position(point), 0.0)
		if point.y >= ground.y and floor_y < ground.y - 0.05:
			stage.seed_membership_at(point, "exterior")
			return
	stage.seed_membership_at(Vector3(point.x, floor_y, point.z), str(candidate.cell_id))

func ground_xr_spawn() -> bool:
	# Terrain is a height field, including logical swimming support. A rounded
	# capsule's contact on a steep hill must not impose a separate slope limit.
	var source:Dictionary=player._source_support(player.global_position,0.1,8.0)
	if source.get("valid",false) and source.get("terrain",false):
		var delta:=Vector3(0,float(source.body_height)-player.global_position.y,0)
		var mask:int=player.collision_mask
		player.collision_mask=mask & ~2
		var obstructed:bool=player.test_move(player.global_transform,delta)
		player.collision_mask=mask
		if not obstructed:
			player.apply_world_correction(delta)
			player.velocity=Vector3.ZERO
			player.ground_control_velocity=Vector2.ZERO
			player.spawn_point=player.global_position
			return true
	# Sweep the actual tracked-body capsule, using the cell's collision mask so
	# interior floors below terrain are selected correctly. No visible gravity settle.
	var hit := KinematicCollision3D.new()
	if not player.test_move(player.global_transform, Vector3.DOWN * 8.0, hit, 0.002):
		return false
	if hit.get_collision_count() == 0 or hit.get_normal().dot(Vector3.UP) < cos(player.floor_max_angle):
		return false
	player.apply_world_correction(hit.get_travel())
	player.velocity = Vector3.ZERO
	player.ground_control_velocity = Vector2.ZERO
	player.spawn_point = player.global_position
	return true

func refresh_inventory() -> void:
	if not is_instance_valid(inventory) or inventory_request_pending: return
	if datapad_character_id.is_empty():
		inventory.set_snapshot({"error":"Offline · Core3 inventory unavailable"})
		return
	var epoch := datapad_epoch
	inventory_request_pending=true
	inventory.set_busy(true,"Reading Core3 inventory…")
	var result: Dictionary
	if live_combat_reserved and is_instance_valid(live_combat) and not live_combat.session_id.is_empty():
		result=await api(HTTPClient.METHOD_POST,"/inventory/status",{"account":datapad_account,"character_id":datapad_character_id,"live_session_id":live_combat.session_id})
	else:result=await api(HTTPClient.METHOD_GET,"/inventory?account="+datapad_account.uri_encode()+"&character_id="+datapad_character_id.uri_encode())
	inventory_request_pending=false
	if epoch!=datapad_epoch:
		refresh_inventory()
		return
	if not is_instance_valid(inventory): return
	if result.get("ok",false) and result.get("source_kind","")=="core3_inventory":
		inventory_snapshot=result.duplicate(true)
		reconcile_inventory_presentations()
		update_inventory_presentation()
		# The bag can display its confirmed inventory immediately. Resource and
		# equipment reads must not keep browsing blocked after this read completes.
		await sync_inventory_equipment()
		if epoch==datapad_epoch:update_inventory_presentation()
	else: inventory.set_busy(false,str(result.get("error","Core3 inventory unavailable")))

func owned_inventory_item(id: String) -> Dictionary:
	for item: Dictionary in inventory_snapshot.get("items",[]):
		if str(item.get("id",""))==id: return item
	if is_instance_valid(gathering): return gathering.owned_hip_item(id)
	return {}

func reconcile_inventory_presentations() -> void:
	# A refreshed server snapshot may remove an item transferred by another session.
	if is_instance_valid(inventory_drops):
		for id in inventory_drops.reserved_ids():
			if owned_inventory_item(str(id)).is_empty(): inventory_drops.remove(str(id))
	if is_instance_valid(inventory) and not inventory.held_item.is_empty():
		var current:=owned_inventory_item(str(inventory.held_item.get("id","")))
		if current.is_empty() and is_instance_valid(housing):current=housing.owned_blueprint(str(inventory.held_item.get("id","")))
		if current.is_empty() or (current.get("equipped",false) and not (is_instance_valid(fishing) and fishing.owns(str(current.id)))): inventory.clear_held()
		else: inventory.held_item=current.duplicate(true)

func update_inventory_presentation() -> void:
	if not is_instance_valid(inventory): return
	var value := inventory_snapshot.duplicate(true)
	var reserved: Array = Array(inventory_drops.reserved_ids()) if is_instance_valid(inventory_drops) else []
	if is_instance_valid(slicing) and not slicing.locked_target.is_empty():reserved.append(slicing.locked_target)
	var held_id := str(inventory.held_item.get("id",""))
	var medical_id := str(medic.held.get("id","")) if is_instance_valid(medic) else ""
	if not medical_id.is_empty():reserved.append(medical_id)
	for item: Dictionary in value.get("items",[]):
		if str(item.id) in [held_id,medical_id]: item["local_state"]="held"
		elif reserved.has(str(item.id)): item["local_state"]="dropped"
	inventory.set_snapshot(value)
	inventory.set_equipment_context(avatar,value.get("equipment",[]))
	if not inventory_equipment_notice.is_empty(): inventory.set_busy(false,inventory_equipment_notice)
	if inventory.is_open: show_equipped_backpack(true,inventory.bag_template)
	if not held_id.is_empty(): reserved.append(held_id)
	if is_instance_valid(combat_rig): combat_rig.set_inventory_reserved(reserved)

func split_inventory_stack(item: Dictionary, quantity: int) -> void:
	if inventory_request_pending or datapad_character_id.is_empty():
		inventory.set_busy(false,"Wait for the current inventory request.")
		return
	if not inventory.held_item.is_empty():
		inventory.set_busy(false,"Return the held item before splitting a stack.")
		return
	if owned_inventory_item(str(item.get("id",""))).is_empty() or (is_instance_valid(inventory_drops) and inventory_drops.reserved_ids().has(str(item.get("id","")))):
		inventory.set_busy(false,"Recover the item into the bag before splitting it.")
		return
	var epoch := datapad_epoch
	inventory_request_pending=true
	inventory.begin_mutation("Splitting stack in Core3…")
	var result := await api(HTTPClient.METHOD_POST,"/inventory/split",{"account":datapad_account,"character_id":datapad_character_id,"item_id":str(item.get("id","")),"quantity":quantity})
	inventory_request_pending=false
	if epoch!=datapad_epoch:
		refresh_inventory()
		return
	if result.get("ok",false) and result.get("source_kind","")=="core3_inventory_split":
		inventory_snapshot=result.inventory.duplicate(true)
		update_inventory_presentation()
	else:
		inventory.set_busy(false,str(result.get("error","Stack split was not confirmed. Refresh inventory before retrying.")))

func inventory_pickup_candidate(pose: Transform3D) -> Dictionary:
	if is_instance_valid(gathering):
		var tool: Dictionary=gathering.pickup_candidate(pose)
		if not tool.is_empty(): return tool
	if not world_ready or not is_instance_valid(inventory_drops): return {}
	var candidate: Dictionary=inventory_drops.pickup_candidate(pose)
	if candidate.is_empty(): return {}
	var item: Dictionary=owned_inventory_item(str(candidate.id)).duplicate(true)
	if item.is_empty():
		inventory_drops.remove(str(candidate.id))
		return {}
	item.erase("local_state")
	return item

func take_inventory_item(item: Dictionary) -> void:
	if is_instance_valid(inventory_drops): inventory_drops.remove(str(item.get("id","")))

func activate_inventory_vehicle_deed(item: Dictionary) -> void:
	if not is_instance_valid(inventory):return
	var id:=str(item.get("id",""))
	if inventory_request_pending or datapad_character_id.is_empty() or owned_inventory_item(id).is_empty():
		inventory.finish_consumable_action({},false)
		inventory.set_busy(false,"Wait for inventory to finish refreshing, then try again.")
		return
	var epoch:=datapad_epoch
	var payload: Dictionary=services.identity_payload() if is_instance_valid(services) else {"account":datapad_account,"character_id":datapad_character_id,"position":[0,0,0],"building_id":"0","cell_index":0}
	if not is_instance_valid(services):
		var source:=source_position_at(player.global_position)
		payload.position=[source.x,source.y,source.z]
	payload.erase("session_id")
	var key:=datapad_character_id+":"+id
	if not vehicle_activation_requests.has(key):
		if vehicle_activation_requests.size()>=128:
			inventory.finish_consumable_action({},false)
			inventory.set_busy(false,"Too many unconfirmed registrations. Refresh inventory before retrying.")
			return
		payload.item_id=id;payload.request_id=Crypto.new().generate_random_bytes(16).hex_encode()
		vehicle_activation_requests[key]={"payload":payload.duplicate(true),"uncertain":false}
	# Native receipts include location. An unconfirmed retry must carry exactly
	# the same semantic request even if the player has moved since sending it.
	payload=vehicle_activation_requests[key].payload.duplicate(true)
	if is_instance_valid(live_combat) and live_combat.live:payload.live_session_id=live_combat.session_id
	inventory_request_pending=true;inventory.begin_mutation("Registering deed in Core3…")
	var result: Dictionary=await api(HTTPClient.METHOD_POST,"/vehicles/activate",payload)
	inventory_request_pending=false
	if epoch!=datapad_epoch or not is_instance_valid(inventory):return
	var confirmed: bool=result.get("ok",false) and result.get("source_kind")=="core3_vehicles" and result.get("mutation",{}).get("success",false) and str(result.get("mutation",{}).get("item_id",""))==id and result.get("inventory",{}).get("source_kind")=="core3_inventory" and str(result.get("inventory",{}).get("character_id",""))==datapad_character_id
	if confirmed:
		vehicle_activation_requests.erase(key)
		inventory_snapshot=result.inventory.duplicate(true)
		inventory.finish_consumable_action(owned_inventory_item(id),true)
		reconcile_inventory_presentations();update_inventory_presentation()
		if is_instance_valid(live_combat) and live_combat.live and is_instance_valid(vehicles):vehicles.observe(result.get("state",{}))
		else:await refresh_datapad()
		if epoch==datapad_epoch:inventory.set_busy(false,"Deed registered in datapad.")
	else:
		inventory.finish_consumable_action({},false)
		# Retain the request ID after ambiguous failure; never blindly repeat a mutation.
		if result.get("confirmed_rejection",false):
			vehicle_activation_requests.erase(key)
		elif result.get("mutation_started",true)==false:
			if not vehicle_activation_requests[key].uncertain:vehicle_activation_requests.erase(key)
		else:vehicle_activation_requests[key].uncertain=true
		inventory.set_busy(false,str(result.get("error","Deed registration was not confirmed. Refresh inventory before retrying.")))

func inventory_held_changed(_item: Dictionary) -> void:
	if is_instance_valid(combat_rig): combat_rig.stop_inventory_item()
	if is_instance_valid(entertainer): entertainer.set_item(_item)
	update_inventory_presentation()

func drop_inventory_item(item: Dictionary, pose: Transform3D) -> void:
	if is_instance_valid(vendor_commerce) and vendor_commerce.try_drop(item,pose):return
	if is_instance_valid(fishing) and fishing.try_drop(item):return
	if is_instance_valid(scout) and scout.try_throw(item): return
	# A drawn hip tool still owns its escrow slot; releasing it restores that
	# presentation. It must not become a second session-local inventory drop.
	if item.get("gathering_hip",false):
		inventory.finish_item_action(true)
		update_inventory_presentation()
		return
	if is_instance_valid(housing) and housing.try_drop(item,pose):return
	if not world_ready or not is_instance_valid(inventory_drops) or owned_inventory_item(str(item.get("id",""))).is_empty():
		inventory.finish_item_action(false)
		return
	var success: bool=inventory_drops.drop(item,pose)
	inventory.finish_item_action(success)
	if not success: inventory.set_busy(false,str(inventory_drops.report.get("last_error","Cannot drop item here.")))
	update_inventory_presentation()

func ready_inventory_item(item: Dictionary) -> void:
	# Inventory-held equippables reserve trigger for the equipment hologram.
	# Weapons become combat equipment only after the server confirms equipping.
	if item.is_empty() or not is_instance_valid(inventory): return
	if is_instance_valid(combat_rig): combat_rig.stop_inventory_item()
	inventory.set_external_use_active(false)
	if is_instance_valid(entertainer) and not entertainer.item.is_empty(): inventory.set_held_visual_enabled(false)

func equip_inventory_item(item: Dictionary, arrangement: int) -> void:
	await mutate_inventory_item("equip",item,{"arrangement":arrangement})

func unequip_inventory_item(item: Dictionary, side: String="") -> void:
	if not is_instance_valid(inventory) or inventory_request_pending:return
	var id:=str(item.get("id",""));var current:=owned_inventory_item(id)
	if current.is_empty() or not current.get("equipped",false) or not current.get("unequip_available",false):
		inventory.set_busy(false,str(current.get("unequip_block_reason","This item is no longer equipped.")));return
	var epoch:=datapad_epoch
	inventory_request_pending=true;inventory.begin_mutation("Removing equipment in Core3…")
	var result:=await api(HTTPClient.METHOD_POST,"/inventory/unequip",{"account":datapad_account,"character_id":datapad_character_id,"item_id":id})
	if epoch!=datapad_epoch:inventory_request_pending=false;return
	var confirmed:bool=result.get("ok",false) and result.get("source_kind","")=="core3_inventory_unequip" and result.get("mutation",{}).get("success",false) and str(result.get("inventory",{}).get("character_id",""))==datapad_character_id
	if confirmed:
		inventory_snapshot=result.inventory.duplicate(true);inventory.finish_item_action(true)
		reconcile_inventory_presentations();update_inventory_presentation();await sync_inventory_equipment(true)
		if epoch!=datapad_epoch:inventory_request_pending=false;return
		var returned:=owned_inventory_item(id)
		if side in ["left","right"] and not returned.is_empty() and not returned.get("equipped",false):inventory.take_item(returned,side)
		inventory.set_busy(false,"Returned to inventory.")
	else:
		inventory.finish_item_action(false);inventory_request_pending=false;await refresh_inventory()
		if epoch==datapad_epoch:inventory.set_busy(false,str(result.get("error","Core3 did not confirm removing this item.")))
	inventory_request_pending=false

func consume_inventory_item(item: Dictionary) -> void:
	if bool(item.get("medical_item",false)) or bool(item.get("wound_medpack",false)):
		await medic.use_medical_item(item);return
	await mutate_inventory_item("consume",item,{})

func mutate_inventory_item(operation: String, item: Dictionary, extra: Dictionary) -> void:
	if not is_instance_valid(inventory): return
	if inventory_request_pending:
		inventory.set_busy(true,"Wait for the current inventory request.")
		return
	var id:=str(item.get("id",""))
	if datapad_character_id.is_empty() or id.is_empty() or str(inventory.held_item.get("id",""))!=id or owned_inventory_item(id).is_empty():
		inventory.finish_equipment_action(false)
		inventory.set_busy(false,"This item is no longer held in your inventory.")
		return
	var epoch:=datapad_epoch
	var body: Dictionary={"account":datapad_account,"character_id":datapad_character_id,"item_id":id}
	body.merge(extra)
	inventory_request_pending=true
	inventory.begin_mutation("Equipping in Core3…" if operation=="equip" else "Using item in Core3…")
	var result:=await api(HTTPClient.METHOD_POST,"/inventory/"+operation,body)
	if epoch!=datapad_epoch:
		inventory_request_pending=false; refresh_inventory(); return
	if not is_instance_valid(inventory): inventory_request_pending=false; return
	var confirmed: bool=result.get("ok",false) and result.get("source_kind","")=="core3_inventory_"+operation and result.get("mutation",{}).get("success",false) and str(result.get("inventory",{}).get("character_id",""))==datapad_character_id
	if confirmed:
		inventory_snapshot=result.get("inventory",{}).duplicate(true)
		apply_inventory_stat_delta(result.get("mutation",{}))
		if operation=="equip": inventory.finish_equipment_action(true)
		else: inventory.finish_consumable_action(owned_inventory_item(id).duplicate(true),true)
		reconcile_inventory_presentations()
		update_inventory_presentation()
		await sync_inventory_equipment(true)
		if epoch!=datapad_epoch: inventory_request_pending=false; refresh_inventory(); return
		update_inventory_presentation()
	else:
		if operation=="equip": inventory.finish_equipment_action(false)
		else: inventory.finish_consumable_action({},false)
		var message:=str(result.get("error","Core3 did not confirm the action. Reopen the bag to refresh before retrying."))
		# A timeout may happen after Core3 committed. Reconcile with one read,
		# never another mutation, before presenting the remaining held object.
		inventory_request_pending=false
		await refresh_inventory()
		if epoch!=datapad_epoch: return
		inventory.set_busy(false,message)
	inventory_request_pending=false

func apply_inventory_stat_delta(mutation: Dictionary) -> void:
	# Ordinary disconnected profile refreshes cannot refill locally spent HAM.
	# A confirmed item action can apply its precise native cost/benefit once.
	if not is_instance_valid(combat_rig) or combat_rig.get("abilities")==null: return
	var pools: RefCounted=combat_rig.abilities
	if str(pools.character_id)!=datapad_character_id or pools.ham.size()!=9: return
	var before: Dictionary=mutation.get("before_stats",{})
	var after: Dictionary=mutation.get("after_stats",{})
	if not mutation.get("success",false) or before.get("source_kind","")!="core3_player_stats" or after.get("source_kind","")!="core3_player_stats": return
	for values: Array in [before.get("ham",[]),after.get("ham",[]),after.get("max_ham",[])]:
		if values.size()!=9: return
		for value in values:
			if not is_finite(float(value)) or float(value)<0: return
	for index in range(9):
		pools.ham[index]=clampf(float(pools.ham[index])+float(after.ham[index])-float(before.ham[index]),0.0,float(after.max_ham[index]))
	pools.update_vitals(after)

func sync_inventory_equipment(force_statistics := false) -> void:
	if not inventory_snapshot.has("equipment"): return
	var equipment: Array=inventory_snapshot.get("equipment",[])
	if is_instance_valid(entertainer):entertainer.sync_equipment(equipment)
	var revision:=JSON.stringify(equipment)
	if revision!=inventory_equipment_revision and is_instance_valid(avatar):
		var rendered: Dictionary=avatar.refresh_equipment(equipment)
		inventory_equipment_notice="" if rendered.get("complete",false) else "Some equipped original appearances are unavailable."
		if rendered.get("ok",false): inventory_equipment_revision=revision
	var weapon_ids: Array=[]
	for entry: Dictionary in equipment:
		if entry.get("tool_kind","")!="fishing" and (entry.get("equip_slots",[]).has("hold_r") or entry.get("equipped_slots",[]).has("hold_r") or str(entry.get("template","")).begins_with("object/weapon/")):
			weapon_ids.append(str(entry.get("id","")))
	var weapon_revision:=JSON.stringify(weapon_ids)
	if force_statistics or weapon_revision!=inventory_weapon_revision:
		var epoch:=datapad_epoch
		var profiles: Array=[]
		# Old holster permissions expire immediately when equipment changes,
		# even if fetching the newly equipped weapon's profile later fails.
		if is_instance_valid(combat_rig): combat_rig.set_equipped_inventory_weapons([])
		var unarmed_profile: Dictionary={}
		var player_combat: Dictionary={}
		if not datapad_character_id.is_empty():
			var result:=await api(HTTPClient.METHOD_GET,"/weapons?account="+datapad_account.uri_encode()+"&character_id="+datapad_character_id.uri_encode())
			if epoch!=datapad_epoch: return
			if not result.get("ok",false): return
			unarmed_profile=result.get("unarmed",{})
			player_combat=result.get("player_combat",{})
			for profile: Dictionary in result.get("weapons",[]):
				if weapon_ids.has(str(profile.get("item_id",""))): profiles.append(profile)
		if (not profiles.is_empty() or not unarmed_profile.is_empty()) and not is_instance_valid(combat_rig):
			combat_rig=load("res://combat/ranged_rig.gd").new(); add_child(combat_rig)
			if not combat_rig.configure(player.get_camera(),player,[],"right" if vr_settings.offhand=="left" else "left",xr_origin):
				combat_rig.queue_free(); combat_rig=null; return
			combat_rig.datapad=datapad; combat_rig.inventory=inventory; combat_rig.tracked_avatar=tracked_avatar
			combat_rig.interaction_blocker=corpse_interaction_blocks
			if is_instance_valid(tracked_avatar): tracked_avatar.combat_rig=combat_rig
			combat_rig.rounds_sim.configure_collision(stage,player)
			get_node("/root/SWGSpatialAudio").configure(player.get_camera(),stage,str(args.get("spatial-audio","steam_audio")))
		if is_instance_valid(combat_rig):
			if not player_combat.is_empty(): combat_rig.configure_player_combat(player_combat)
			combat_rig.set_equipped_inventory_weapons(profiles)
			if combat_rig.unarmed.is_empty() and not unarmed_profile.is_empty():combat_rig.configure_unarmed(unarmed_profile)
			for state in combat_rig.unarmed.values():
				if not unarmed_profile.is_empty(): state.refresh_player(unarmed_profile)
		inventory_weapon_revision=weapon_revision
	if is_instance_valid(avatar):
		var rendered_ids: Array=[]
		if is_instance_valid(combat_rig):
			for weapon in combat_rig.weapons:
				if not weapon.get("inventory_only",false): rendered_ids.append(str(weapon.state.profile.get("item_id","")))
		if is_instance_valid(fishing) and not fishing.rod.is_empty():rendered_ids.append(str(fishing.rod.id))
		if is_instance_valid(entertainer) and not entertainer.equipped_instrument.is_empty():rendered_ids.append(str(entertainer.equipped_instrument.id))
		for item:Dictionary in equipment:
			if item.get("tool_kind","")=="slicing" and "hold_r" in item.get("equipped_slots",[]):rendered_ids.append(str(item.get("id","")))
		avatar.set_equipment_visual_hidden(rendered_ids)

func show_equipped_backpack(hidden: bool, template: String) -> void:
	if not hidden:
		for mesh in inventory_hidden_equipment:
			if is_instance_valid(mesh): mesh.visible=inventory_hidden_equipment[mesh]
		inventory_hidden_equipment.clear()
		return
	if template.is_empty() or not is_instance_valid(avatar): return
	for mesh in avatar.meshes:
		if str(mesh.get_meta("equipment_template",""))!=template and str(mesh.get_meta("equipment_shared_template",""))!=template: continue
		if not inventory_hidden_equipment.has(mesh): inventory_hidden_equipment[mesh]=mesh.visible
		mesh.visible=false

func get_radar_contacts(center: Vector3, radius: float) -> Array[Dictionary]:
	if not world_ready or loading_stage: return []
	var contacts:=radar_contacts.query(center,radius)
	if is_instance_valid(player) and player.feedback.spice.policy().hostile_illusion:
		for contact:Dictionary in contacts:contact.relation="hostile"
	return contacts

func datapad_source_position() -> Vector3:
	return source_position_at(player.global_position)

func source_position_at(world_position: Vector3) -> Vector3:
	var origin := loader.vec(loader.report.get("origin",[0,0,0]))
	var point: Vector3=stage.to_local(world_position) if is_instance_valid(stage) and stage is Node3D else world_position
	return Vector3(origin.x+point.x,origin.y+point.y,origin.z-point.z)

func open_datapad_equipment()->void:
	if not is_instance_valid(inventory) or not is_instance_valid(datapad) or inventory_request_pending:return
	datapad.set_open(false)
	inventory.set_allowed(true)
	inventory.browse_equipment(xr_origin.get_node("XRCamera3D").global_transform)

func update_datapad_summary(value:Variant)->void:
	if not is_instance_valid(datapad) or not is_instance_valid(datapad.summary_ui):return
	var summary:Dictionary=value if value is Dictionary and value.get("version",0)==1 and str(value.get("character_id",""))==datapad_character_id and not datapad_character_id.is_empty() else {}
	datapad.summary_ui.set_summary(summary)
	if summary.is_empty():datapad.summary_ui.set_character(null,"")
	elif is_instance_valid(inventory):datapad.summary_ui.set_character(inventory.equipment_avatar,inventory.equipment_context_key())

func refresh_datapad() -> void:
	if not is_instance_valid(datapad) or datapad_request_pending: return
	if live_combat_reserved:
		# Reuse the native session; a legacy datapad login would disconnect it.
		if is_instance_valid(services): await services.request("status")
		datapad.ui.set_busy(false,"Core3 · live skills and XP")
		return
	if datapad_character_id.is_empty():
		datapad.ui.set_entries([])
		datapad.ui.set_busy(true,"Offline · reference map")
		return
	var epoch := datapad_epoch
	datapad_request_pending = true
	datapad.ui.set_busy(true,"Reading Core3…")
	var result := await api(HTTPClient.METHOD_GET,"/datapad?account="+datapad_account.uri_encode()+"&character_id="+datapad_character_id.uri_encode())
	datapad_request_pending = false
	if epoch != datapad_epoch:
		refresh_datapad()
		return
	if result.get("ok",false) and result.get("backend","") == "core3":
		update_datapad_summary(result.get("player_summary",{}) if str(result.get("character_id",""))==datapad_character_id else {})
		datapad.ui.set_entries(result.get("entries",[]))
		datapad.ui.set_skills(result.get("skills", []), result.get("skills_complete", false))
		datapad.ui.set_experience(result.get("experience", {}), result.get("experience_complete", false))
		datapad.ui.set_busy(false,"Core3 · character datapad")
	else:
		datapad.ui.set_busy(true,str(result.get("error","Datapad unavailable")))

func create_datapad_waypoint(point: Vector3, label: String) -> void:
	if datapad_request_pending or datapad_character_id.is_empty(): return
	if not point.is_finite(): return
	point.x = clampf(point.x,-8192,8192)
	point.z = clampf(point.z,-8192,8192)
	# Map positions have no interior elevation; resolve against original terrain.
	if label == "Map waypoint" and is_instance_valid(terrain):
		point.y = terrain.evaluator.sample_height(point.x,point.z)
	var epoch := datapad_epoch
	datapad_request_pending = true
	datapad.ui.set_busy(true,"Saving waypoint…")
	var result := await api(HTTPClient.METHOD_POST,"/waypoints",{"account":datapad_account,"character_id":datapad_character_id,"name":label,"planet":active_planet,"position":{"x":point.x,"y":point.y,"z":point.z}})
	datapad_request_pending = false
	if epoch != datapad_epoch:
		refresh_datapad()
		return
	if result.get("ok",false) and result.get("backend","") == "core3":
		datapad.ui.set_entries(result.get("datapad",{}).get("entries",[]))
		datapad.ui.set_busy(false,"Waypoint saved in Core3")
	else:
		datapad.ui.set_busy(false,str(result.get("error","Waypoint was not saved")))

func configure_combat_lab(snapshot: Dictionary = {}) -> void:
	if args.has("offline") and xr_requested and not is_instance_valid(tracked_avatar):
		# Explicit synthetic test avatar; never presented as a Core3 character.
		avatar = Avatar.new()
		tracked_avatar = TrackedAvatar.new()
		add_child(tracked_avatar)
		tracked_avatar.add_child(avatar)
		var result: Dictionary = avatar.configure("human_male",{"height":1.0,"profession":"crafting_artisan","customization":{}},[])
		if not str(result.get("error","")).is_empty() or not tracked_avatar.configure(avatar,xr_origin):
			push_error("Local combat test avatar unavailable")
			tracked_avatar.queue_free(); tracked_avatar = null; avatar = null
		elif vr_settings.standing_eye_height >= 0.8:
			tracked_avatar.set_standing_eye_height(vr_settings.standing_eye_height)
	var path := ProjectSettings.globalize_path("res://../runtime/combat/catalog.json")
	var catalog: Dictionary = Avatar.read_json(path)
	if args.has("combat-profession-lab") and not args.has("combat-items"):
		var fixture := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/evidence/professions/fixture.json"))
		if fixture.get("source", "") != "synthetic_profession_lab":
			asset_status.text = "Run python3 tools/server/profession_smoke.py to prepare the profession lab."
			return
		catalog = fixture
		snapshot = {"player_combat":fixture.player_combat}
	var profiles: Array = []
	if args.has("combat-items"):
		if snapshot.get("backend","")!="core3" or snapshot.get("source","")!="authenticated_core3_attributes":
			asset_status.text = "Core3 weapon snapshot unavailable."
			return
		# One actual item at each mount. Explicit IDs select among owned items.
		for hands in [1,2]:
			var requested := str(args.get("sidearm-item" if hands==1 else "longarm-item",""))
			for item in snapshot.get("weapons",[]):
				if int(item.hands)==hands and (requested.is_empty() or str(item.item_id)==requested):
					profiles.append(item)
					break
		if profiles.is_empty() and snapshot.get("unarmed",{}).is_empty():
			asset_status.text = "No supported Core3 weapons in this character's inventory."
			return
	else:
		for key in [str(args.get("combat-sidearm","pistol_dl44")),str(args.get("combat-longarm","rifle_e11"))]:
			if not catalog.get("weapons",{}).has(key):
				asset_status.text = "Combat lab profile missing: " + key + ". Run python3 tools/combat/export_catalog.py."
				push_error(asset_status.text)
				return
			profiles.append(catalog.weapons[key])
		if int(profiles[0].hands) != 1 or int(profiles[1].hands) != 2:
			push_error("Combat lab requires a one-handed sidearm and two-handed longarm")
			return
	combat_rig = load("res://combat/ranged_rig.gd").new()
	add_child(combat_rig)
	var dominant := str(args.get("dominant-hand", "right" if vr_settings.offhand=="left" else "left"))
	if not combat_rig.configure(player.get_camera(),player,profiles,dominant,xr_origin):
		push_error(combat_rig.last_error)
		combat_rig.queue_free()
		combat_rig = null
		return
	var unarmed_profile: Dictionary=snapshot.get("unarmed",{}) if args.has("combat-items") else catalog.get("unarmed",{})
	if not unarmed_profile.is_empty(): combat_rig.configure_unarmed(unarmed_profile)
	combat_rig.configure_player_combat(snapshot.get("player_combat", {}))
	combat_rig.datapad = datapad
	combat_rig.inventory = inventory
	combat_rig.interaction_blocker=corpse_interaction_blocks
	if is_instance_valid(tracked_avatar):
		tracked_avatar.combat_rig = combat_rig
		combat_rig.tracked_avatar = tracked_avatar
	combat_rig.rounds_sim.configure_collision(stage,player)
	get_node("/root/SWGSpatialAudio").configure(player.get_camera(),stage,str(args.get("spatial-audio","steam_audio")))
	if vr_settings.standing_eye_height >= 0.8:
		combat_rig.set_standing_eye_height(vr_settings.standing_eye_height)
	if args.has("live-combat"):
		combat_rig.unarmed.clear()
		combat_rig.set_allowed(false)
		return
	combat_target = load("res://combat/training_target.gd").new()
	add_child(combat_target)
	var camera: Camera3D = player.get_camera()
	var forward := -camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var melee_equipped := profiles.is_empty() or profiles.any(func(p): return p.get("kind","")=="melee")
	var target_point := player.global_position + forward*(2.5 if melee_equipped else 6.0)
	var floor_query := PhysicsRayQueryParameters3D.create(target_point+Vector3.UP*2,target_point-Vector3.UP*12,7)
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_query)
	combat_target.global_position = (floor_hit.position if not floor_hit.is_empty() else target_point) + Vector3.UP*0.65
	combat_target.look_at(combat_target.global_position-forward)
	session_mode += " · CORE3 WEAPONS · LOCAL COMBAT" if args.has("combat-items") else " · LOCAL COMBAT LAB · NON-PERSISTENT"
	mode_label.text = active_planet.to_upper()+" / " + session_mode
	asset_status.text = "Combat: dominant grip at hip / over shoulder to draw; keep grip held.
Melee/unarmed: hold trigger for combat ready; release for peace. Swing and recover distance to attack.
Ranged: trigger fires; support steadies; B/Y changes mode; empty capacity starts cooling.
Abilities: click main-hand stick, move it to select; A primes the next attack. The controller Menu button opens the system menu.
Desktop debug: F4 stow, F5/F6 draw, F7 support, F8 mode, F9 reload, left mouse fire / combat ready, F10 debug melee swing; F11 ability menu, Up selects, F12 primes."

func refresh_weapon_statistics() -> void:
	if not is_instance_valid(combat_rig) or datapad_character_id.is_empty(): return
	var epoch := datapad_epoch
	var result := await api(HTTPClient.METHOD_GET,"/weapons?account="+datapad_account.uri_encode()+"&character_id="+datapad_character_id.uri_encode())
	if epoch!=datapad_epoch or not is_instance_valid(combat_rig): return
	if not result.get("ok",false) or result.get("backend","")!="core3":
		asset_status.text = str(result.get("error","Weapon refresh failed"))
		return
	var previews := PackedStringArray()
	combat_rig.configure_player_combat(result.get("player_combat", {}))
	var unarmed_profile: Dictionary=result.get("unarmed",{})
	for state in combat_rig.unarmed.values():
		if not state.refresh_player(unarmed_profile):
			state.block(); combat_rig.unarmed.clear(); break
	if not combat_rig.unarmed.is_empty(): previews.append("Unarmed\n"+combat_rig.unarmed[combat_rig.dominant].crafting_preview(unarmed_profile))
	for weapon in combat_rig.weapons:
		var state = weapon.state
		var matched := false
		for item in result.get("weapons",[]):
			if str(item.item_id)!=str(state.profile.get("item_id","")): continue
			var previous: Dictionary = state.profile.duplicate(true)
			matched = state.refresh_instance(item)
			if matched: previews.append(str(item.label)+"\n"+state.crafting_preview(item,previous))
			break
		if not matched:
			# Transferred/deleted/unsupported items cannot continue firing locally.
			state.certificates.clear()
			state.block()
			previews.append("Weapon no longer available")
	combat_rig.stow()
	asset_status.text = "\n\n".join(previews)

func delete_datapad_entry(entry: Dictionary) -> void:
	if datapad_request_pending or datapad_character_id.is_empty() or not datapad.ui.can_delete(entry): return
	var epoch := datapad_epoch
	datapad_request_pending = true
	datapad.ui.set_busy(true,"Deleting entry…")
	var result := await api(HTTPClient.METHOD_POST,"/datapad/delete",{"account":datapad_account,"character_id":datapad_character_id,"entry_id":str(entry.get("id",""))})
	datapad_request_pending = false
	if epoch!=datapad_epoch: return
	if result.get("ok",false) and result.get("backend","")=="core3":
		datapad.ui.set_entries(result.get("datapad",{}).get("entries",[]))
		datapad.ui.set_busy(false,"Entry deleted")
	else:
		datapad.ui.set_busy(false,str(result.get("error","Core3 did not confirm deletion")))

func start_live_combat() -> bool:
	if not is_instance_valid(combat_rig) or combat_rig.weapons.is_empty(): return false
	live_combat_epoch += 1
	var epoch := live_combat_epoch
	live_combat_reserved = true
	for controller in [gathering, corpse_gathering, entertainer]:
		if is_instance_valid(controller): controller.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(corpse_gathering): corpse_gathering.reset()
	# Let already-issued one-shot logins finish before claiming the persistent session.
	var drain_deadline := Time.get_ticks_msec() + 80000
	while api_requests_in_flight > 0:
		if Time.get_ticks_msec() > drain_deadline: return false
		await get_tree().process_frame
		if epoch != live_combat_epoch or not live_combat_reserved: return false
	if not is_instance_valid(combat_rig): return false
	combat_rig.unarmed.clear()
	live_combat = preload("res://combat/live_world.gd").new()
	add_child(live_combat)
	live_combat.configure(self, combat_rig, stage, player)
	live_combat.configure_ambient(ambient_npcs)
	live_combat.snapshot_applied.connect(apply_live_player)
	live_combat.appearance_status_changed.connect(live_appearance_status_changed)
	live_combat.state_changed.connect(live_combat_state_changed)
	live_combat.life_action_finished.connect(live_life_action_finished)
	live_combat.transport_required.connect(handle_live_transport)
	if player.feedback.has_signal("life_action_requested") and not player.feedback.life_action_requested.is_connected(request_live_life_action):
		player.feedback.life_action_requested.connect(request_live_life_action)
	player.feedback.local_prediction = false
	var started: bool = await live_combat.start(player.global_position, -player.global_rotation.y)
	if epoch != live_combat_epoch or not is_instance_valid(live_combat): return false
	started = started and live_combat.live
	if started:
		# An immobilized reconnect must resume at its real native location, not
		# the launcher's requested spawn. No revive or movement is inferred.
		var native: Dictionary=live_combat.player_state
		var transport: Dictionary=live_combat.pending_transport
		if not transport.is_empty():
			started=await perform_live_transport(transport,true)
		elif native.get("position") is Array:
			var destination:=native.duplicate(true)
			if str(native.get("zone",active_planet))!=active_planet or live_combat.world(native.position).distance_to(player.global_position)>0.05 or int(native.get("cell_index",0))>0:
				var placed: Dictionary=await medical_placement.place(self,destination)
				started=bool(placed.get("ok",false))
				if not started:live_combat.last_error=str(placed.get("error","Native character placement failed."))
	if started:
		# Native entertainer commands share this persistent session. Its prop and
		# tracked input must resume too; only legacy corpse gathering stays paused.
		for controller in [gathering,entertainer]:
			if is_instance_valid(controller):controller.process_mode=Node.PROCESS_MODE_INHERIT
		session_mode = "LIVE CORE3 · RANGED COMBAT TEST"
		mode_label.text = active_planet.to_upper()+" / " + session_mode
		asset_status.text = "Live Core3 creatures, HAM, retaliation and deaths. Grip at dominant hip to draw; trigger fires.
Terminals, wallet, gathering and crafting use the live Core3 session. Legacy inventory RPCs remain suspended during this ranged test. Core3 stays running after exit."
	return started

func apply_live_player(snapshot: Dictionary) -> void:
	if preload("res://scripts/native_session_identity.gd").id(self).is_empty(): return
	if is_instance_valid(combat_rig) and not combat_rig.abilities.apply_authoritative(snapshot):
		if live_combat_reserved and is_instance_valid(live_combat):live_combat.fail("Malformed authoritative player vitals; combat disarmed.")
		else:
			combat_rig.set_allowed(false)
			if is_instance_valid(asset_status):asset_status.text="Malformed authoritative player vitals; interactions paused."
		return
	var context := snapshot.duplicate(true)
	context["character_id"] = datapad_character_id
	player.feedback.observe(context)
	if snapshot.get("player_summary") is Dictionary:update_datapad_summary(snapshot.player_summary)
	preload("res://combat/movement_reconciliation.gd").apply(self,snapshot)
	if is_instance_valid(datapad) and snapshot.get("experience") is Dictionary and bool(snapshot.get("experience_complete",false)):
		datapad.ui.set_experience(snapshot.experience,true)
	if is_instance_valid(medic):medic.observe_drag(snapshot.get("medical_drag",{}))
	if is_instance_valid(vehicles):vehicles.observe(snapshot.get("vehicles",{}))

func request_live_life_action(action: String) -> void:
	var session: Node=live_combat if live_combat_reserved else gameplay_session
	if not is_instance_valid(session) or not session.request_life_action(action):
		if is_instance_valid(player) and player.feedback.has_method("resolve_life_action"):
			player.feedback.resolve_life_action(false,"Core3 cannot accept that action right now.")

func live_life_action_finished(_action: String, success: bool, message: String) -> void:
	if is_instance_valid(player) and player.feedback.has_method("resolve_life_action"):
		player.feedback.resolve_life_action(success,message)

func handle_live_transport(transport: Dictionary) -> void:
	await perform_live_transport(transport,false)

func perform_service_transport(transport: Dictionary) -> bool:
	# A non-combat client still travels only to a destination returned by Core3.
	if loading_stage or not transport.get("destination") is Dictionary: return false
	retry_transport=transport.duplicate(true);retry_transport_service=true
	var epoch := live_transport_epoch
	loading_stage=true; world_ready=false; player.active=false
	player.set_physics_process(false)
	if is_instance_valid(services): services.set_allowed(false)
	ensure_loading_screen()
	if loading_screen.has_method("set_failure_hint"):loading_screen.set_failure_hint("Press Menu / Esc to retry loading this destination.")
	loading_screen.begin("Travelling to the Core3 shuttle destination…")
	var placed: Dictionary = await medical_placement.place(self,transport.destination)
	if epoch != live_transport_epoch: return false
	if not placed.get("ok",false):
		loading_screen.fail(str(placed.get("error","The destination could not be loaded.")))
		return false
	await complete_planet_arrival()
	retry_transport={}
	loading_stage=false; world_ready=true
	player.set_physics_process(true)
	loading_screen.finish()
	if is_instance_valid(services): services.have_previous=false; services.poll_clock=0
	close_menu()
	return true

func perform_live_transport(transport: Dictionary, initial: bool) -> bool:
	var session: Node=live_combat if live_combat_reserved else gameplay_session
	if live_transport_busy or not is_instance_valid(session): return false
	var id:=str(transport.get("id",""))
	if id.is_empty() or not transport.get("destination") is Dictionary: return false
	retry_transport=transport.duplicate(true);retry_transport_service=false
	live_transport_busy=true;live_transport_epoch+=1
	var epoch:=live_transport_epoch
	session.notified_transport_id=id
	loading_stage=true;world_ready=false;player.active=false
	player.set_physics_process(false)
	if is_instance_valid(combat_rig):combat_rig.set_allowed(false)
	if loading_screen.has_method("set_failure_hint"):loading_screen.set_failure_hint("Press Menu / Esc to retry loading this destination.")
	loading_screen.begin("Travelling to the Core3 destination…" if str(transport.get("kind", ""))=="shuttle" else "Transporting to the Core3 medical bay…")
	var placed: Dictionary=await medical_placement.place(self,transport.destination)
	if epoch!=live_transport_epoch or not is_instance_valid(session) or session!=(live_combat if live_combat_reserved else gameplay_session):return false
	if not placed.get("ok",false):
		live_transport_busy=false
		loading_screen.fail(str(placed.get("error","Medical transport placement cancelled.")))
		return false
	loading_screen.set_status("Confirming arrival with Core3…")
	if not session.acknowledge_transport(id):
		live_transport_busy=false;loading_screen.fail("Core3 medical transport is no longer available.");return false
	var deadline:=Time.get_ticks_msec()+20000
	while session.live and (not session.pending_transport.is_empty() or bool(session.player_state.get("cloning",false))):
		if epoch!=live_transport_epoch or Time.get_ticks_msec()>deadline:
			live_transport_busy=false;loading_screen.fail("Core3 medical arrival confirmation timed out.");return false
		await get_tree().process_frame
	if not session.live:
		live_transport_busy=false;loading_screen.fail("Core3 disconnected during medical transport.");return false
	await complete_planet_arrival()
	retry_transport={}
	live_transport_busy=false
	if not initial:
		loading_stage=false;world_ready=true
		player.set_physics_process(true)
		loading_screen.finish()
		close_menu()
	return true

func complete_planet_arrival()->void:
	# A failed initial transport can be retried after its entry coroutine ended.
	# Complete the same service ownership setup before exposing the destination.
	if not is_instance_valid(stage) or not stage.has_meta("manifest"):return
	if not is_instance_valid(services):
		services=preload("res://scripts/services_controller.gd").new();add_child(services);services.setup(self)
	if is_instance_valid(gameplay_session) and gameplay_session.live:
		if not is_instance_valid(multiplayer_sync):
			multiplayer_sync=preload("res://multiplayer/client_sync.gd").new();add_child(multiplayer_sync);multiplayer_sync.setup(self)
		if not is_instance_valid(mission_parcels):
			mission_parcels=preload("res://scripts/mission_parcels.gd").new();add_child(mission_parcels);mission_parcels.setup(self)
		if not is_instance_valid(vendor_placement):
			vendor_placement=preload("res://scripts/vendor_placement.gd").new();add_child(vendor_placement);vendor_placement.setup(self)
		if not is_instance_valid(vendor_commerce):
			vendor_commerce=preload("res://scripts/vendor_commerce.gd").new();add_child(vendor_commerce);vendor_commerce.setup(self)
	if is_instance_valid(datapad):
		datapad.ui.set_planet(active_planet)
		await refresh_datapad()
	if is_instance_valid(services):services.have_previous=false;services.poll_clock=0
	if is_instance_valid(multiplayer_sync):await multiplayer_sync.prime()
	if is_instance_valid(mode_label):mode_label.text=active_planet.to_upper()+" / "+session_mode

func live_combat_state_changed(connected: bool, message: String) -> void:
	if not connected and is_instance_valid(player) and player.feedback.has_method("resolve_life_action"):
		player.feedback.resolve_life_action(false,message)
	if not connected and is_instance_valid(combat_rig):
		combat_rig.abilities.pools_valid = false
		combat_rig.set_allowed(false)
	if is_instance_valid(asset_status): asset_status.text = message

func stop_live_combat() -> void:
	retry_transport={}
	live_transport_epoch+=1;live_transport_busy=false;medical_placement.cancel()
	live_combat_epoch += 1
	var epoch := live_combat_epoch
	var session := live_combat
	live_combat = null
	if is_instance_valid(session):
		await session.stop()
		if is_instance_valid(session): session.queue_free()
	if epoch != live_combat_epoch: return
	live_combat_reserved = false
	for controller in [gathering, corpse_gathering, entertainer]:
		if is_instance_valid(controller): controller.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(player) and is_instance_valid(player.feedback): player.feedback.local_prediction = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:leave_character(true)

func leave_character(quit_after: bool=false) -> void:
	if session_leaving or loading_stage or busy:return
	if not world_ready:
		if quit_after:quit_application()
		return
	session_leaving=true
	menu.show();creator.hide();player.active=false;player.velocity=Vector3.ZERO;player.set_physics_process(false)
	if is_instance_valid(xr_menu):xr_menu.set_open(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	update_buttons()
	status.text="Saving your location and logging off…"
	var paused: Dictionary={}
	for node in [services,gathering,crafting,fishing,housing,medic,vehicles,pets,scout,entertainer,corpse_gathering,live_combat,gameplay_session,multiplayer_sync,gameplay_combat,mission_parcels,vendor_placement,vendor_commerce]:
		if is_instance_valid(node):paused[node]=node.process_mode;node.process_mode=Node.PROCESS_MODE_DISABLED
	if is_instance_valid(voice_chat):voice_chat.set_allowed(false)
	# Freeze new work, then let already-sent transactions settle before the save.
	var deadline:=Time.get_ticks_msec()+16000
	while api_requests_in_flight>0 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	var result: Dictionary={"ok":true,"saved":true,"session_closed":true}
	if api_requests_in_flight>0:
		result={"ok":false,"error":"An earlier request is still pending. Retry Log off shortly."}
	elif not datapad_character_id.is_empty():
		if logout_payload.is_empty():
			logout_payload=services.identity_payload() if is_instance_valid(services) else {"account":datapad_account,"character_id":datapad_character_id,"building_id":"0","cell_index":0}
			var point:=source_position_at(player.global_position)
			logout_payload.position=[point.x,point.y,point.z]
			logout_payload.heading_radians=-player.global_rotation.y
			logout_payload.request_id=Crypto.new().generate_random_bytes(16).hex_encode()
			logout_payload.erase("session_id")
		if is_instance_valid(live_combat) and not live_combat.session_id.is_empty():logout_payload.live_session_id=live_combat.session_id
		elif is_instance_valid(gameplay_session) and not gameplay_session.session_id.is_empty():logout_payload.live_session_id=gameplay_session.session_id
		result=await api(HTTPClient.METHOD_POST,"/session/logout",logout_payload)
		if result.get("source_kind")!="core3_session_logout" or str(result.get("character_id",""))!=datapad_character_id:result.ok=false
	for node in paused:
		if is_instance_valid(node):node.process_mode=paused[node]
	if not result.get("ok",false) or not result.get("saved",false) or not result.get("session_closed",false):
		session_leaving=false
		if logout_payload.is_empty():player.set_physics_process(true)
		status.text=str(result.get("error","Location save is unconfirmed. Retry Log off or Quit; your location request is retained."))
		update_buttons()
		return
	# The server closed the persistent session after saving. Do not reconnect or
	# send a second stop that could overwrite the authoritative logout location.
	if is_instance_valid(live_combat):live_combat.reset("Character logged off.")
	if is_instance_valid(gameplay_session):gameplay_session.reset()
	await stop_live_combat()
	clear_character_world()
	logout_payload.clear();session_leaving=false
	if quit_after:quit_application();return
	status.text="Logged off. Location saved."
	update_buttons()
	await refresh_characters()

func quit_application() -> void:
	get_tree().quit()

func retire_world_node(node:Node)->void:
	# Logout can finish inside this node's signal/coroutine. Disable presentation
	# immediately, then release it once Godot has unwound the locked callback.
	node.process_mode=Node.PROCESS_MODE_DISABLED
	if node is Node3D:node.hide()
	node.queue_free()

func clear_character_world() -> void:
	planet_transition.cancel()
	world_ready=false;datapad_epoch+=1
	if is_instance_valid(mission_parcels):mission_parcels.reset();mission_parcels.queue_free();mission_parcels=null
	if is_instance_valid(vendor_commerce):vendor_commerce.reset();vendor_commerce.queue_free();vendor_commerce=null
	if is_instance_valid(vendor_placement):vendor_placement.reset();vendor_placement.queue_free();vendor_placement=null
	if is_instance_valid(gameplay_combat):gameplay_combat.reset();gameplay_combat.queue_free();gameplay_combat=null
	if is_instance_valid(multiplayer_sync):multiplayer_sync.reset();multiplayer_sync.queue_free();multiplayer_sync=null
	native_poll_budget.reset()
	datapad_character_id="";datapad_account="";inventory_snapshot.clear()
	inventory_request_pending=false;datapad_request_pending=false;vehicle_activation_requests.clear()
	if is_instance_valid(voice_chat):voice_chat.set_allowed(false)
	if is_instance_valid(environment_presentation):environment_presentation.set_active(false)
	if is_instance_valid(inventory):inventory.set_allowed(false);inventory.clear_held();inventory.set_snapshot({})
	if is_instance_valid(inventory_drops):inventory_drops.clear()
	for controller in [services,gathering,crafting,fishing,slicing,spice_world,housing,medic,vehicles,pets,scout,entertainer,corpse_gathering]:
		if is_instance_valid(controller) and controller.has_method("reset"):controller.reset()
	if is_instance_valid(datapad):datapad.set_allowed(false);datapad.ui.set_entries([]);datapad.ui.set_skills([],false);datapad.ui.set_experience({},false);update_datapad_summary({})
	player.active=false;player.velocity=Vector3.ZERO;player.set_physics_process(false);player.ground_provider=null
	if is_instance_valid(tracked_avatar):retire_world_node(tracked_avatar);avatar=null
	elif is_instance_valid(avatar):retire_world_node(avatar)
	tracked_avatar=null;avatar=null
	for property in ["combat_rig","combat_target","ambient_npcs","portal_visibility","world_stream","terrain","stage"]:
		var node=get(property)
		if is_instance_valid(node):retire_world_node(node)
		set(property,null)
	loader=StageLoader.new();radar_contacts.clear()
	resume_button.hide();action_row.hide();menu.show()
	if is_instance_valid(xr_menu):xr_menu.set_open(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func live_appearance_status_changed(report: Dictionary) -> void:
	live_appearance_text = str(report.get("notice", ""))
	if not xr_requested: return
	if not is_instance_valid(live_appearance_label) and not live_appearance_text.is_empty():
		live_appearance_label = Label3D.new()
		live_appearance_label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		live_appearance_label.font_size = 22
		live_appearance_label.pixel_size = 0.00055
		live_appearance_label.modulate = Color("ffe2a0")
		live_appearance_label.no_depth_test = true
		player.get_camera().add_child(live_appearance_label)
		live_appearance_label.position = Vector3(0, -0.28, -0.85)
	if is_instance_valid(live_appearance_label):
		live_appearance_label.text = live_appearance_text
		live_appearance_label.visible = not live_appearance_text.is_empty()


func account_ready() -> bool:
	return not remote_connection.configured or (remote_connection.authenticated and not remote_connection.legacy_profile)

func clear_account_data() -> void:
	vehicle_activation_requests.clear()
	if is_instance_valid(voice_chat):voice_chat.shutdown()
	if is_instance_valid(voice_controls):voice_controls.set_allowed(false)
	if is_instance_valid(desktop_voice_panel):desktop_voice_panel.hide()
	desktop_voice_open=false;desktop_voice_ptt_armed=false;desktop_voice_pointer_ptt=false
	auth_revision+=1;core3_ready=false;characters=[];creation_options={}
	datapad_epoch+=1;datapad_account="";datapad_character_id="";inventory_snapshot={}
	if is_instance_valid(character_list):character_list.clear()
	if is_instance_valid(account_input):account_input.text=""
	if is_instance_valid(creator):
		creator.hide();creator.set_options({});creator.name_input.clear();creator.biography.clear();creator.set_backend_state(false)
	if is_instance_valid(status):status.text="Sign in to load your characters."

func show_account_panel(message: String="") -> void:
	if not is_instance_valid(account_panel):return
	menu.hide();creator.hide();account_panel.show()
	if is_instance_valid(player):player.active=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(xr_menu):xr_menu.set_open(true)
	if not message.is_empty():account_panel.status.text=message

func authenticate_account(action: String, payload: Dictionary) -> void:
	if auth_busy or world_ready or loading_stage or live_combat_reserved:return
	if action not in ["login","register","claim","resume"]:return
	var expected_account:=remote_connection.account if action=="claim" else str(payload.get("account",""))
	auth_busy=true;account_panel.set_working(true,"Connecting securely…")
	var result:=await api(HTTPClient.METHOD_POST,"/auth/"+action,payload)
	payload.clear() # Release the request's password reference as soon as it completes.
	if not result.get("ok",false):
		if action=="resume" and int(result.get("http_status",0))==401:account_panel.invalidate_saved_login(expected_account)
		auth_busy=false;account_panel.set_working(false)
		account_panel.status.text=str(result.get("error","Could not sign in."))
		return
	if result.get("account","")!=expected_account:
		auth_busy=false;account_panel.set_working(false)
		account_panel.status.text="Server returned a different account. Sign in again."
		return
	if not remote_connection.accept_session(result):
		auth_busy=false;account_panel.set_working(false)
		account_panel.status.text=remote_connection.error
		return
	account_panel.status.text="Signed in. Updating saved login…"
	var remember_notice: String=""
	if account_panel.remember_password.button_pressed and action!="resume":
		var previous:Dictionary=account_panel.credential_store.load_login(backend_url,expected_account)
		var remembered:Dictionary=await api(HTTPClient.METHOD_POST,"/auth/remember",{})
		if remembered.get("ok",false):
			remember_notice=account_panel.save_authenticated_login(expected_account,remembered)
			if not remember_notice.is_empty() and account_panel.credential_store.valid_token(remembered.get("remember_token")):
				await api(HTTPClient.METHOD_POST,"/auth/forget",{"account":expected_account,"remember_token":remembered.remember_token})
			elif previous.get("found",false):
				await api(HTTPClient.METHOD_POST,"/auth/forget",{"account":expected_account,"remember_token":previous.remember_token})
		else:remember_notice="Signed in; could not create a saved login."
		remembered.clear();previous.clear()
	elif action!="resume":account_panel._save_preference(expected_account,false)
	auth_busy=false;account_panel.set_working(false)
	var cleaned:=true
	if action=="claim":cleaned=remote_connection.remove_legacy_profile_credentials()
	clear_account_data()
	args.account=remote_connection.account;account_input.text=remote_connection.account
	account_panel.clear_passwords();account_panel.hide();menu.show()
	account_panel.legacy_account="";account_panel.modes.claim.hide()
	await refresh_backend()
	if not cleaned:status.text="Signed in. Old profile could not be cleared; use Sign in on your next launch."
	elif not remember_notice.is_empty():status.text=remember_notice

func forget_saved_login(payload:Dictionary)->void:
	var name:=str(payload.get("account",""))
	var result:=await api(HTTPClient.METHOD_POST,"/auth/forget",payload)
	payload.clear()
	account_panel.complete_forget(name,result)

func sign_out() -> void:
	if auth_busy or busy or world_ready or loading_stage or live_combat_reserved:return
	if not remote_connection.configured:return
	auth_busy=true
	var result:=await api(HTTPClient.METHOD_POST,"/auth/logout",{})
	auth_busy=false
	if not result.get("ok",false) and remote_connection.authenticated:
		status.text="Could not sign out securely. Check the connection and try again."
		return
	remote_connection.clear_session();clear_account_data()
	account_panel.configure(backend_url);show_account_panel("Signed out.");update_buttons()

func expire_account() -> void:
	if not remote_connection.configured:return
	remote_connection.clear_session();clear_account_data()
	if is_instance_valid(account_panel):account_panel.configure(backend_url)
	show_account_panel("Your session expired. Sign in again.")
	# Never attach a different account to a loaded world. Rebuild the application
	# to discard every account-owned controller, item and pending callback.
	if world_ready or loading_stage or live_combat_reserved:
		world_ready=false
		loading_stage=false
		if is_instance_valid(player):player.active=false;player.set_physics_process(false)
		if not auth_expiry_reload:
			auth_expiry_reload=true
			get_tree().call_deferred("reload_current_scene")


func ensure_voice_chat() -> void:
	if is_instance_valid(voice_chat):return
	voice_chat=load("res://scripts/voice_chat.gd").new();add_child(voice_chat)
	voice_chat.status_changed.connect(voice_state_changed)
	voice_chat.configure(self)
	if xr_requested and is_instance_valid(xr_origin):
		voice_controls=preload("res://scripts/xr_voice_controls.gd").new();add_child(voice_controls)
		voice_controls.configure(xr_origin,vr_settings.offhand)
		voice_controls.channel_requested.connect(voice_chat.set_channel)
		voice_controls.mode_requested.connect(voice_chat.set_mic_mode)
		voice_controls.ptt_changed.connect(voice_chat.set_ptt)
	else:
		desktop_voice_panel=preload("res://scripts/voice_panel.gd").new();ui_root.add_child(desktop_voice_panel)
		desktop_voice_panel.position=Vector2(40,100)
		desktop_voice_panel.channel_requested.connect(voice_chat.set_channel)
		desktop_voice_panel.mode_requested.connect(voice_chat.set_mic_mode)
		desktop_voice_panel.ptt_changed.connect(func(held: bool):desktop_voice_pointer_ptt=held)
		desktop_voice_panel.hide()
	voice_state_changed(voice_chat.get_state())

func voice_state_changed(value: Dictionary) -> void:
	if is_instance_valid(voice_controls):voice_controls.apply_state(value)
	if is_instance_valid(desktop_voice_panel):desktop_voice_panel.apply_state(value)

func update_voice_chat() -> void:
	if not is_instance_valid(voice_chat) or not is_instance_valid(player):return
	var session_id: String=preload("res://scripts/native_session_identity.gd").id(self)
	voice_chat.set_context(datapad_account,datapad_character_id,auth_revision,session_id)
	var tracked:=true
	if xr_requested:
		var head=XRServer.get_tracker("head")
		var pose: XRPose=head.get_pose("default") if head!=null else null
		tracked=pose!=null and pose.has_tracking_data
		for side in ["LeftHand","RightHand"]:
			var hand:=xr_origin.get_node_or_null(side) as XRController3D
			tracked=tracked and hand!=null and preload("res://scripts/tracked_hand_input.gd").controller_tracked(hand)
	var gate:=preload("res://scripts/voice_lifecycle.gd").evaluate({"authenticated":account_ready(),"character":not datapad_character_id.is_empty(),
		"world":world_ready,"loading":loading_stage,"alive":not player.feedback.life_locked,
		"focused":xr_focused if xr_requested else DisplayServer.window_is_focused(),"tracked":tracked,
		"menu":menu.visible or creator.visible or (is_instance_valid(account_panel) and account_panel.visible) or xr_diagnostic_active()})
	voice_chat.set_allowed(gate.allowed)
	if is_instance_valid(voice_controls):
		voice_controls.avatar=tracked_avatar
		if voice_controls.offhand!=vr_settings.offhand:voice_controls.set_offhand(vr_settings.offhand)
		# Item/tool triggers retain their original behavior; voice never steals grips
		# or drops a held item. Listening/VOX continue while these controls are busy.
		var hands_free: bool=not (is_instance_valid(inventory) and (inventory.interaction_active or not inventory.held_item.is_empty()))
		hands_free=hands_free and not (is_instance_valid(datapad) and datapad.is_open) and not (is_instance_valid(crafting) and crafting.is_open)
		hands_free=hands_free and not (is_instance_valid(services) and services.blocks_combat())
		voice_controls.set_allowed(gate.allowed,hands_free,gate.reason if not gate.allowed else ("Free your main hand to change voice controls" if not hands_free else ""))
	if is_instance_valid(desktop_voice_panel):
		desktop_voice_panel.visible=desktop_voice_open and world_ready and not menu.visible
		if not desktop_voice_panel.visible:desktop_voice_pointer_ptt=false
		desktop_voice_panel.set_active(gate.allowed,gate.reason)
		if desktop_voice_panel.visible:player.active=false
		var held:=Input.is_physical_key_pressed(KEY_B)
		if not held:desktop_voice_ptt_armed=true
		if not gate.allowed:desktop_voice_ptt_armed=false
		voice_chat.set_ptt(gate.allowed and ((held and desktop_voice_ptt_armed) or desktop_voice_pointer_ptt))
