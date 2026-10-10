extends SceneTree
class MenuApp extends "res://scripts/main.gd":
	func _ready()->void:pass
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,900)
	var app:=MenuApp.new();app.xr_requested=true
	app.graphics_preferences.path="user://graphics-settings-smoke.cfg";DirAccess.remove_absolute(app.graphics_preferences.path)
	root.add_child(app);app.set_process(false);app.set_physics_process(false);app.set_process_input(false);app.set_process_unhandled_input(false)
	app.make_ui();app.login_presentation.set_process(false)
	var navigation=app.find_child("SettingsNavigation",true,false)
	await process_frame;await process_frame
	check(navigation!=null and navigation.pages.keys()==["Audio","Controls","Graphics"],"Three settings submenus in actual main menu")
	var graphics=navigation.pages.Graphics.get_child(0).get_child(0)
	var microphone=navigation.pages.Audio.find_child("MicrophoneDevice",true,false)
	check(microphone!=null and navigation.pages.Controls.find_child("VRTurningSettings",true,false)!=null,"Audio and turning options live in their respective pages")
	app.xr_viewport=SubViewport.new();app.add_child(app.xr_viewport)
	app.xr_spectator=preload("res://scripts/xr_spectator.gd").new();app.add_child(app.xr_spectator);app.xr_spectator.set_physics_process(false)
	app.xr_spectator.viewport=SubViewport.new();app.xr_spectator.add_child(app.xr_spectator.viewport)
	for page:String in ["Audio","Controls","Graphics"]:
		navigation.buttons[page].pressed.emit();await process_frame;await process_frame
		check(navigation.current==page and not navigation.home.visible and navigation.back.visible,"Open "+page+" submenu")
		for key:String in navigation.pages:check(navigation.pages[key].is_visible_in_tree()==(key==page),"Only selected submenu is visible")
		check(app.menu.get_global_rect().end.x<=1440 and app.menu.get_global_rect().end.y<=900,"Settings fit the menu canvas: "+page)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://../runtime/evidence/sector-audit-20261010/settings-"+page.to_lower()+".png")
		if page=="Audio":microphone.open_popup();check(microphone.is_open(),"Audio dropdown opens inside its page")
		navigation.back.pressed.emit();await process_frame
		check(navigation.current.is_empty() and navigation.home.visible,"Back returns to settings categories")
		check(not microphone.is_open(),"Leaving submenu closes detached dropdown overlay")
	navigation.show_page("Graphics")
	for level in range(4):
		graphics.choice.open_popup();graphics.choice._choose(level)
		await process_frame
		check(root.msaa_3d==level and app.xr_viewport.msaa_3d==level and app.xr_spectator.viewport.msaa_3d==level,"MSAA applies to main, headset and spectator viewports: "+str(level))
		var saved=preload("res://graphics/preferences.gd").new();saved.path=app.graphics_preferences.path;saved.load_preferences()
		check(saved.msaa==level,"MSAA survives reload: "+str(level))
	var config:=ConfigFile.new();config.set_value("graphics","msaa",999);config.save(app.graphics_preferences.path);app.graphics_preferences.load_preferences()
	check(app.graphics_preferences.msaa==Viewport.MSAA_DISABLED,"Invalid saved MSAA safely defaults to Off")
	DirAccess.remove_absolute(app.graphics_preferences.path);root.msaa_3d=Viewport.MSAA_DISABLED
	app.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"xr":false,"tracking":"mocked","renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method()}))
	quit(0 if failures.is_empty() else 1)
