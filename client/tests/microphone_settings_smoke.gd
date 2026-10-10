extends SceneTree
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var panel = preload("res://audio/input_settings.gd").new()
	panel.preferences.path = "user://microphone-settings-smoke.cfg"
	DirAccess.remove_absolute(panel.preferences.path)
	root.add_child(panel); panel.set_process(false)
	panel.refresh_devices(PackedStringArray(["Default", "Headset microphone", "USB microphone"]), true)
	check(panel.choice.item_count == 3, "System default appears once alongside named inputs")
	panel.choice.open_popup(); panel.choice._choose(2)
	var saved = preload("res://audio/input_preferences.gd").new()
	saved.path = panel.preferences.path; saved.load_preferences()
	check(saved.device == "USB microphone", "Dropdown selection survives preference reload")
	panel.refresh_devices(PackedStringArray(["Default", "Headset microphone"]))
	check(panel.choice.get_selected_metadata() == "USB microphone" and panel.choice.is_item_disabled(panel.choice.selected), "Disconnected preference remains visible")
	check(saved.effective_device(PackedStringArray(["Default"])) == "Default", "Missing microphone falls back to system default")
	check(panel.detail.text.contains("disconnected"), "Fallback is explained in settings")
	panel.refresh_devices(PackedStringArray(["Default", "USB microphone"]))
	check(not panel.choice.is_item_disabled(panel.choice.selected) and saved.effective_device(panel.devices) == "USB microphone", "Reconnected microphone restores saved choice")
	var codec = preload("res://scripts/voice_codec.gd").new(); root.add_child(codec)
	codec.set_input_device("Disconnected test device")
	check(not codec.capture_enabled and not codec.transmitting, "Changing input never activates capture or transmission")
	codec.queue_free(); panel.queue_free(); DirAccess.remove_absolute(saved.path)
	await process_frame
	print(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "microphone_capture": false, "renderer": "dummy", "xr": "off"}))
	quit(0 if failures.is_empty() else 1)
