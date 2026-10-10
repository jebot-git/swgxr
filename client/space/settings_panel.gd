extends VBoxContainer
var preferences:RefCounted
var notice:Label
func setup(value:RefCounted)->void:
	preferences=value
	var title:=Label.new();title.text="FLIGHT CONTROLS";add_child(title)
	var modes:=preload("res://scripts/frontend_choice.gd").new()
	for label in ["Motion controller sticks","Virtual HOTAS · grip stick and throttle","Physical HOTAS / joystick"]:modes.add_item(label)
	modes.select(["motion_sticks","virtual_hotas","physical_hotas"].find(preferences.mode));add_child(modes)
	var mappings:=VBoxContainer.new();add_child(mappings)
	mappings.visible=preferences.mode=="physical_hotas"
	modes.item_selected.connect(func(index):preferences.mode=["motion_sticks","virtual_hotas","physical_hotas"][index];mappings.visible=index==2;save())
	var devices:=preload("res://scripts/frontend_choice.gd").new();devices.add_item("First connected joystick");devices.set_item_metadata(0,-1)
	for id in Input.get_connected_joypads():devices.add_item(Input.get_joy_name(id));devices.set_item_metadata(devices.item_count-1,id)
	for i in devices.item_count:
		if devices.get_item_metadata(i)==preferences.device:devices.select(i)
	devices.item_selected.connect(func(index):preferences.device=devices.get_item_metadata(index);save());mappings.add_child(devices)
	for name in ["pitch","yaw","roll","throttle"]:
		var row:=HBoxContainer.new();mappings.add_child(row)
		var label:=Label.new();label.text=name.capitalize();label.custom_minimum_size.x=88;row.add_child(label)
		var axis:=SpinBox.new();axis.min_value=0;axis.max_value=9;axis.step=1;axis.prefix="Axis ";axis.value=preferences.axes[name];row.add_child(axis)
		axis.value_changed.connect(func(value):preferences.axes[name]=int(value);save())
		var invert:=CheckBox.new();invert.text="Invert";invert.button_pressed=preferences.inverted[name];row.add_child(invert)
		invert.toggled.connect(func(value):preferences.inverted[name]=value;save())
		var source:=preload("res://scripts/frontend_choice.gd").new();source.add_item("Default device");source.set_item_metadata(0,-1);source.custom_minimum_size.x=130;source.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for id in Input.get_connected_joypads():source.add_item(Input.get_joy_name(id));source.set_item_metadata(source.item_count-1,id)
		for i in source.item_count:
			if source.get_item_metadata(i)==preferences.axis_devices[name]:source.select(i)
		source.item_selected.connect(func(index):preferences.axis_devices[name]=source.get_item_metadata(index);save());row.add_child(source)
	var deadzone:=HSlider.new();deadzone.min_value=0;deadzone.max_value=.45;deadzone.step=.01;deadzone.value=preferences.deadzone;mappings.add_child(deadzone)
	deadzone.tooltip_text="Rotational axis deadzone";deadzone.value_changed.connect(func(value):preferences.deadzone=value;save())
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.text="Pilot: right stick pitches/rolls; left stick adjusts throttle/yaw. Right stick click opens ship commands; left stick click leaves the station. Virtual HOTAS grips are beside the seat.";notice.add_theme_font_size_override("font_size",14);add_child(notice)
func save()->void:
	if preferences.save_preferences()!=OK and is_instance_valid(notice):notice.text="Flight settings updated for this session; could not save preferences."
