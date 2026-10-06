extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1200,850);root.content_scale_size=root.size
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();stage.add_child(env);env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("132634");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("fff0dc");env.environment.ambient_light_energy=.85
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(40,26,-48);camera.look_at(Vector3(0,15,9));camera.current=true;camera.fov=55
	var actor:=preload("res://combat/live_actor.gd").new();stage.add_child(actor);var row:Dictionary={"id":"42","kind":"creature","template":preload("res://gcw/carrier_animation.gd").TEMPLATE,"dead":false,"name":"Lambda shuttle · original ground loop","health":100,"max_health":100,"scale":1.0,"posture":2}
	var passed:=actor.configure(row,"mocked",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));actor.label.hide();actor.set_process(false)
	var label:=Label.new();root.add_child(label);label.position=Vector2(25,20);label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",20);label.text="GCW CRACKDOWN CARRIER · DESKTOP VULKAN INSPECTION\nOriginal Lambda model, rig and ground animation · mocked native posture · no live headset"
	for i in range(12):await process_frame
	await RenderingServer.frame_post_draw
	passed=passed and actor.rigid_equipment.size()==11 and actor.visual_bounds().size.x>20 and actor.report.get("carrier_animation_ready",false) and root.get_texture().get_image().save_png("res://../runtime/evidence/gcw-carrier-vulkan.png")==OK
	var report:Dictionary={"passed":passed,"renderer":RenderingServer.get_current_rendering_method(),"native":"mocked posture","original_assets":true,"live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-carrier-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));stage.free();await process_frame;quit(0 if passed else 1)
