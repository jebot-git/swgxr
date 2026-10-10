extends RefCounted
## Keep the preferred name when a USB/headset microphone temporarily disappears.
var path := "user://swgxr_microphone.cfg"
var device := "Default"

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		device = str(config.get_value("microphone", "device", "Default"))
	if device.is_empty(): device = "Default"

func save_device(value: String) -> Error:
	device = value if not value.is_empty() else "Default"
	var config := ConfigFile.new()
	config.set_value("microphone", "device", device)
	return config.save(path)

func effective_device(available: PackedStringArray) -> String:
	return device if device in available else "Default"
