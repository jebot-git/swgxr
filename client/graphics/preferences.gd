extends RefCounted
## Applied to world-rendering viewports, never the 2D menu render targets.
var path:="user://swgxr_graphics.cfg"
var msaa:=Viewport.MSAA_DISABLED
var foveation_level:=0
var fovea_size:=0
var desktop_mirror:=0 # 0: third-person, 1: standard OpenXR left eye.
func load_preferences()->void:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return
	var value:Variant=config.get_value("graphics","msaa",Viewport.MSAA_DISABLED)
	msaa=int(value) if value is int and value>=Viewport.MSAA_DISABLED and value<=Viewport.MSAA_8X else Viewport.MSAA_DISABLED
	foveation_level=read_choice(config,"foveation_level",3)
	fovea_size=read_choice(config,"fovea_size",3)
	desktop_mirror=read_choice(config,"desktop_mirror",1)
func read_choice(config:ConfigFile,key:String,maximum:int)->int:
	var value:Variant=config.get_value("graphics",key,0)
	return value if value is int and value>=0 and value<=maximum else 0
func set_msaa(value:int)->void:
	msaa=value if value>=Viewport.MSAA_DISABLED and value<=Viewport.MSAA_8X else Viewport.MSAA_DISABLED
func save_preferences()->Error:
	var config:=ConfigFile.new()
	for key:String in ["msaa","foveation_level","fovea_size","desktop_mirror"]:config.set_value("graphics",key,get(key))
	return config.save(path)
func apply(viewports:Array)->void:
	for viewport:Viewport in viewports:
		if is_instance_valid(viewport):viewport.msaa_3d=msaa
