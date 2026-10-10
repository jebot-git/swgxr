extends VBoxContainer
signal device_selected(device: String)
var preferences = preload("res://audio/input_preferences.gd").new()
var choice = preload("res://scripts/frontend_choice.gd").new()
var detail := Label.new()
var devices := PackedStringArray()
var refresh_clock := 0.0

func _ready() -> void:
	preferences.load_preferences()
	var caption := Label.new(); caption.text = "Microphone"; add_child(caption)
	choice.name = "MicrophoneDevice"; choice.custom_minimum_size.y = 44
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(choice)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 16); add_child(detail)
	choice.item_selected.connect(_selected)
	refresh_devices(AudioServer.get_input_device_list(), true)

func refresh_devices(available: PackedStringArray, force := false) -> void:
	if not force and available == devices: return
	devices = available.duplicate()
	choice.clear(); choice.add_item("System default"); choice.set_item_metadata(0, "Default")
	for device in devices:
		if device == "Default": continue
		choice.add_item(device); choice.set_item_metadata(choice.item_count-1, device)
	if preferences.device != "Default" and preferences.device not in devices:
		choice.add_item(preferences.device + " (disconnected)")
		choice.set_item_metadata(choice.item_count-1, preferences.device)
		choice.set_item_disabled(choice.item_count-1, true)
	for index in range(choice.item_count):
		if choice.get_item_metadata(index) == preferences.device: choice.select(index)
	_update_detail()

func _selected(index: int) -> void:
	var device := str(choice.get_item_metadata(index))
	if preferences.save_device(device) != OK:
		detail.text = "Microphone changed for this session; the preference could not be saved."
	else: _update_detail()
	device_selected.emit(device)

func _update_detail() -> void:
	detail.text = "Selected microphone disconnected; using system default." if preferences.device != "Default" and preferences.device not in devices else "Used by voice chat. Selecting a device does not unmute the microphone."

func _process(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock >= 1.0:
		refresh_clock = 0
		if is_visible_in_tree(): refresh_devices(AudioServer.get_input_device_list())
