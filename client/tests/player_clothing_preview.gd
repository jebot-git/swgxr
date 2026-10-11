extends SceneTree
## Standalone original-asset render, no connection or headset initialization.
const Avatar=preload("res://scripts/avatar.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":quit(1);return
	var view:=SubViewport.new();root.add_child(view);view.size=Vector2i(1600,1000);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var world:=Node3D.new();view.add_child(world)
	var environment:=WorldEnvironment.new();world.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("10212d");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.75
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=1.6
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,1.15,-5.3);camera.look_at(Vector3(0,1,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.5;camera.current=true
	var clothes:Array=[{"template":"object/tangible/wearables/shirt/shirt_s14.iff"},{"template":"object/tangible/wearables/pants/pants_s05.iff"},{"template":"object/tangible/wearables/armor/zam/armor_zam_wesell_boots.iff"}]
	var mabari:Array=[]
	for part in ["boots","pants","chest_plate","gloves","belt","helmet"]:mabari.append({"template":"object/tangible/wearables/armor/zam/armor_zam_wesell_"+part+".iff"})
	for i in range(3):
		var avatar:=Avatar.new();world.add_child(avatar);avatar.position.x=(i-1)*1.25
		var report:Dictionary=avatar.configure("rodian_male",{},clothes if i==0 else mabari)
		if not report.get("equipment_complete",false):push_error(str(report));quit(1);return
		avatar.set_tracking_mode(true)
		if i==2:avatar.rotation.y=PI
		var label:=Label3D.new();world.add_child(label);label.position=Vector3((i-1)*1.25,2.2,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=26;label.pixel_size=.0015;label.text=["Rodian · clothing + Mabari boots","Rodian · full Mabari set","Rodian · rear view"][i]
	for i in range(8):await process_frame
	view.get_texture().get_image().save_png("res://../runtime/evidence/rodian-mabari-preview.png")
	print(JSON.stringify({"renderer":"Vulkan Forward+","headset_tested":false,"native_connection":false,"capture":"runtime/evidence/rodian-mabari-preview.png"}));quit()
