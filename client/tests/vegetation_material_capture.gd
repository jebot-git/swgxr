extends SceneTree
const MaterialLoader=preload("res://scripts/stage_loader.gd")
const SourceFont=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":push_error("Requires desktop Forward+ Vulkan with XR off");quit(1);return
	root.size=Vector2i(1720,900)
	var directory:=ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("world.json")))
	var source:="appearance/mesh/thm_tato_orchard_s02_l0.msh"
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(manifest.meshes[source].path)))
	if not data.surfaces[0].get("alpha",false):push_error("Actual orchard source alpha-test metadata missing");quit(1);return
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE);RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color.WHITE)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("071b2c");world.add_child(env)
	var loader:=MaterialLoader.new();var builder:=SwgMeshBuilder.new()
	for index:int in range(2):
		var mesh:=builder.create_mesh(data.surfaces)
		for surface:int in range(mesh.get_surface_count()):
			var material:=loader.make_material(data.surfaces[surface],directory)
			if index==0:material.set_shader_parameter("alpha_cutout",false)
			mesh.surface_set_material(surface,material)
		var model:=MeshInstance3D.new();model.mesh=mesh;model.position.x=5.2 if index==0 else -5.2;world.add_child(model)
		var label:=Label.new();root.add_child(label);label.add_theme_font_override("font",SourceFont);label.add_theme_font_size_override("font_size",25);label.position=Vector2(90 if index==0 else 950,750);label.text="BEFORE · ignored source alpha test" if index==0 else "FIXED · original foliage cutouts"
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=48;camera.position=Vector3(0,5.6,-14.7);camera.look_at(Vector3(0,1.6,0));camera.current=true
	var title:=Label.new();root.add_child(title);title.position=Vector2(30,25);title.add_theme_font_override("font",SourceFont);title.add_theme_font_size_override("font_size",28);title.text="TATOOINE ORCHARD · IDENTICAL ORIGINAL GEOMETRY AND TEXTURE"
	var note:=Label.new();root.add_child(note);note.position=Vector2(30,835);note.add_theme_font_override("font",SourceFont);note.add_theme_font_size_override("font_size",21);note.text="Source PASS0009 alpha-test enabled in MAIN sort · native C++ mesh builder · opaque depth-tested cutouts · desktop Vulkan"
	for frame:int in range(12):await process_frame
	await RenderingServer.frame_post_draw
	var capture:=ProjectSettings.globalize_path("res://../runtime/evidence/core2/vegetation-alpha-vulkan.png");root.get_texture().get_image().save_png(capture)
	var report:Dictionary={"passed":true,"source_mesh":source,"source_shader":data.surfaces[0].shader,"alpha_source":data.surfaces[0].alpha_source,"triangles":manifest.meshes[source].triangles,"geometry_changed":false,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"headset_validated":false,"capture":capture}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/core2/vegetation-alpha-vulkan.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));world.queue_free();await process_frame;quit(0)
