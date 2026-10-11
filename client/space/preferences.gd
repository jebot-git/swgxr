extends RefCounted
## User hardware bindings stay local; ship authority stays in Core3.
var path:="user://swgxr_flight.cfg"
var mode:="motion_sticks"
var device:=-1
var axis_devices:Dictionary={"pitch":-1,"yaw":-1,"roll":-1,"throttle":-1}
var axes:Dictionary={"pitch":1,"yaw":2,"roll":0,"throttle":3}
var inverted:Dictionary={"pitch":false,"yaw":false,"roll":false,"throttle":false}
var buttons:Dictionary={"primary":0,"look":1,"next":2,"previous":3,"component":4,"fire":5}
var deadzone:=.12
var grip_radius:=.22
func load_preferences()->void:
	var cfg:=ConfigFile.new()
	if cfg.load(path)!=OK:return
	mode=str(cfg.get_value("flight","mode",mode))
	if mode not in ["motion_sticks","virtual_hotas","physical_hotas"]:mode="motion_sticks"
	device=clampi(int(cfg.get_value("flight","device",-1)),-1,15)
	deadzone=clampf(float(cfg.get_value("flight","deadzone",.12)),0,.45)
	for name in axes:
		axes[name]=clampi(int(cfg.get_value("axes",name,axes[name])),0,9)
		axis_devices[name]=clampi(int(cfg.get_value("axis_devices",name,-1)),-1,15)
		inverted[name]=bool(cfg.get_value("invert",name,false))
	for name in buttons:buttons[name]=clampi(int(cfg.get_value("buttons",name,buttons[name])),-1,127)
func save_preferences()->Error:
	var cfg:=ConfigFile.new();cfg.set_value("flight","mode",mode);cfg.set_value("flight","device",device);cfg.set_value("flight","deadzone",deadzone)
	for name in axes:cfg.set_value("axes",name,axes[name]);cfg.set_value("invert",name,inverted[name]);cfg.set_value("axis_devices",name,axis_devices[name])
	for name in buttons:cfg.set_value("buttons",name,buttons[name])
	return cfg.save(path)
func axis(value:float,name:String)->float:
	if not is_finite(value):return 0
	var adjusted:=clampf(value,-1,1)*(-1 if inverted.get(name,false) else 1)
	return signf(adjusted)*maxf(0,(absf(adjusted)-deadzone)/(1-deadzone))
func physical_values()->Dictionary:
	var connected:=Input.get_connected_joypads()
	var chosen:int=connected[0] if device<0 and not connected.is_empty() else device
	if not chosen in connected:return {"available":false}
	var values:Dictionary={"available":true}
	for name in axes:
		var source:int=chosen if int(axis_devices.get(name,-1))<0 else int(axis_devices[name])
		if not source in connected:return {"available":false}
		values[name]=Input.get_joy_axis(source,int(axes[name]))
	return values

func physical_fire()->bool:return physical_button("primary")
func physical_button(action:String)->bool:
	var connected:=Input.get_connected_joypads()
	var chosen:int=connected[0] if device<0 and not connected.is_empty() else device
	var index:int=int(buttons.get(action,-1))
	return chosen in connected and index>=0 and Input.is_joy_button_pressed(chosen,index)
