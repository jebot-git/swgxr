extends SceneTree
## Original weapon render only, without a server or XR initialization.
const Rig=preload("res://combat/ranged_rig.gd")
const State=preload("res://combat/weapon_state.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":quit(1);return
	var view:=SubViewport.new();root.add_child(view);view.size=Vector2i(1500,900);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var world:=Node3D.new();view.add_child(world)
	var environment:=WorldEnvironment.new();world.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("10212d");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=1.5
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(.15,.85,1.65);camera.look_at(Vector3(0,0,-.1));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.7;camera.current=true
	var rig:=Rig.new();world.add_child(rig);rig.set_process(false);rig.set_physics_process(false);rig.assets.load_catalog()
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var keys:=["pistol_cdef","carbine_e11","rifle_t21"]
	for i in range(3):
		var profile:Dictionary=catalog.weapons[keys[i]];var state:=State.new();state.configure(profile,profile.core3.certificationsRequired)
		var visual:Node3D=rig.make_visual(profile);rig.add_child(visual);visual.position.x=(i-1)*.53
		var record:=rig.weapon_presentation(state,visual)
		state.rounds=int(profile.capacity)*[1.0,.5,.2][i];state.mode="semi" if i==0 else "auto";record.readout.update_state(state,true)
		var label:=Label3D.new();world.add_child(label);label.position=Vector3((i-1)*.53,.22,-.25);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=28;label.pixel_size=.0008;label.text=["Pistol · full · single","Carbine · half · automatic","Rifle · low · automatic"][i]
	for i in range(8):await process_frame
	view.get_texture().get_image().save_png("res://../runtime/evidence/weapon-readout-preview.png")
	print(JSON.stringify({"renderer":"Vulkan Forward+","headset_tested":false,"native_connection":false,"capture":"runtime/evidence/weapon-readout-preview.png"}));quit()
