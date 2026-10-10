extends SceneTree
## Original avatar, mocked native loadout. Desktop Forward+ Vulkan; XR disabled.
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("061018");environment.environment=env;world.add_child(environment)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,.35,1.45);camera.fov=38;camera.current=true
	var avatar:=preload("res://scripts/avatar.gd").new();world.add_child(avatar);var report:Dictionary=avatar.configure("human_male");avatar.set_process(false);avatar.hide()
	if not str(report.get("error","")).is_empty():push_error(str(report.error));quit(1);return
	var hologram:=preload("res://scripts/equipment_hologram.gd").new();world.add_child(hologram);hologram.configure(avatar,[])
	var catalog:Array=[]
	for id:String in ["lethal_shot","low_blow","restraining_shot","concussion_shot_improved","last_ditch"]:
		catalog.append({"id":id,"label":id.replace("_"," ").capitalize(),"ultimate":id=="last_ditch","activation":"native_ranged","cooldown_seconds":30,"max_range_m":40})
	catalog.append({"id":"warcry","label":"Warcry","category":"gesture","description":"Delays attacks and reduces enemy damage in a forward cone.","trigger_description":"Raise the held weapon above your head, lower it slightly, then pump upward. Keep both triggers released.","weapon_requirement":"Requires a certified held weapon. Unavailable unarmed."})
	catalog.append({"id":"taunt","label":"Taunt","category":"gesture","trigger_description":"Beat your chest twice with a free clenched hand.","weapon_requirement":"Any certified weapon; requires a free hand."})
	hologram.set_ability_context({"item_id":"99","ability_catalog":catalog,"ability_loadout":{"family":"pistols","slots":["concussion_shot_improved","lethal_shot","low_blow","restraining_shot"],"ultimate":"last_ditch","revision":1}})
	hologram.show_equipment(Transform3D.IDENTITY);hologram.global_transform=Transform3D.IDENTITY;hologram.ability_editor.toggle();hologram.ability_editor.describe("warcry")
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(30,25);caption.text="WEAPON LOADOUT  /  MOCK CORECU STATE  /  DESKTOP VULKAN  /  XR OFF";caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",20)
	for i in range(10):await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/gesture-abilities-vulkan.png");root.get_texture().get_image().save_png(path)
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"mocked_state":true,"slots":4,"live_xr":false,"capture":path}));world.free();quit()
