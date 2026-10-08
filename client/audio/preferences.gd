extends RefCounted
## Shared menu/world gains; stored separately from XR-specific preferences.
var path:="user://swgxr_audio.cfg"
var music:=.65
var ambience:=.8
static func ensure_buses()->void:
	for bus in ["SWG Music","SWG Ambience"]:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus();AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
static func apply_gain(bus:String,value:float,offset:float)->void:
	ensure_buses()
	var index:=AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index,linear_to_db(maxf(value,.00001))+offset)
	AudioServer.set_bus_mute(index,value<=0)
func load_preferences()->void:
	var config:=ConfigFile.new()
	if config.load(path)==OK:
		music=clampf(float(config.get_value("audio","music",.65)),0,1)
		ambience=clampf(float(config.get_value("audio","ambience",.8)),0,1)
	apply_gain("SWG Music",music,-6);apply_gain("SWG Ambience",ambience,-8)
func set_volume(channel:String,value:float)->void:
	if not is_finite(value):return
	if channel=="Music":music=clampf(value,0,1);apply_gain("SWG Music",music,-6)
	else:ambience=clampf(value,0,1);apply_gain("SWG Ambience",ambience,-8)
	var config:=ConfigFile.new();config.set_value("audio","music",music);config.set_value("audio","ambience",ambience);config.save(path)
