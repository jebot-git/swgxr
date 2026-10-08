extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var path:=args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://../runtime/character_exports/equipped-character.vrm")
	var bytes:=FileAccess.get_file_as_bytes(path);var document:=GLTFDocument.new();var state:=GLTFState.new()
	var status:=document.append_from_buffer(bytes,path.get_base_dir(),state)
	if status!=OK:printerr("VRM glTF reimport failed: "+error_string(status));quit(1);return
	var scene:=document.generate_scene(state);root.add_child(scene)
	var meshes:=scene.find_children("*","MeshInstance3D",true,false)
	print(JSON.stringify({"reimport_ok":true,"meshes":meshes.size(),"skinned_meshes":meshes.filter(func(mesh):return mesh.skin!=null).size(),"animations":scene.find_children("*","AnimationPlayer",true,false).size()}))
	if DisplayServer.get_name()=="headless":scene.free();quit();return
	root.size=Vector2i(1024,1024)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1.05,3.2);camera.look_at(Vector3(0,1.05,0));camera.fov=40;camera.current=true
	var light:=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-25,-25,0);light.light_energy=1.4
	var environment:=WorldEnvironment.new();root.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.045,.065,.09);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.75
	for frame in range(12):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/character-vrm-desktop-vulkan.png")
	scene.free();camera.free();light.free();environment.free();quit()
