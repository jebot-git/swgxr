extends RefCounted
## Applied to world-rendering viewports, never the 2D menu render targets.
var path:="user://swgxr_graphics.cfg"
var msaa:=Viewport.MSAA_DISABLED
func load_preferences()->void:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return
	var value:Variant=config.get_value("graphics","msaa",Viewport.MSAA_DISABLED)
	msaa=int(value) if value is int and value>=Viewport.MSAA_DISABLED and value<=Viewport.MSAA_8X else Viewport.MSAA_DISABLED
func set_msaa(value:int)->void:
	msaa=value if value>=Viewport.MSAA_DISABLED and value<=Viewport.MSAA_8X else Viewport.MSAA_DISABLED
func save_preferences()->Error:
	var config:=ConfigFile.new();config.set_value("graphics","msaa",msaa);return config.save(path)
func apply(viewports:Array)->void:
	for viewport:Viewport in viewports:
		if is_instance_valid(viewport):viewport.msaa_3d=msaa
