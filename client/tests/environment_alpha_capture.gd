extends SceneTree
## Production streaming/material paths, original Tatooine scene and source X31.
const World=preload("res://scripts/world_stream.gd")
const Terrain=preload("res://scripts/terrain_stream.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const SourceFont=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":push_error("Desktop Vulkan required");quit(1);return
	root.size=Vector2i(1600,1000)
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE);RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color(.95,.92,.86));RenderingServer.global_shader_parameter_set("swg_daylight",1.0)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("8ba6b4");root.add_child(environment)
	var stream:=World.new();root.add_child(stream);stream.render_distance=160;stream.collision_distance=160
	if not stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json")):push_error("Original world unavailable");quit(1);return
	var center:=Vector3(-313,0,86)
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.fov=66;eye.position=center+Vector3(12,2.1,11);eye.look_at(center+Vector3(-2,1,0));stream.cell_owner.set_observer(eye)
	var ground:=Terrain.new();root.add_child(ground);var origin:Array=stream.manifest.origin
	ground.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(origin[0],origin[1],origin[2]));ground.set_cell_source(stream.cell_owner);ground.update_observer(center);stream.update_observer(center)
	var deadline:=Time.get_ticks_msec()+90000
	while not stream.report.get("ready",false) or not ground.ready_near(center,0):
		if Time.get_ticks_msec()>deadline:push_error("Production world stream did not become ready");quit(1);return
		await process_frame
	var assets:=Assets.new();assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/vehicles/catalog.json"))
	var vehicle:=MeshInstance3D.new();vehicle.mesh=assets.model("object/mobile/vehicle/landspeeder_x31.iff");root.add_child(vehicle);vehicle.position=center+Vector3(4,0,3);vehicle.rotation.y=.7
	var opaque_surfaces:=0
	for index:int in range(vehicle.mesh.get_surface_count()):
		if vehicle.mesh.surface_get_material(index).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:opaque_surfaces+=1
	if opaque_surfaces!=3 or vehicle.mesh.get_surface_count()!=4:push_error("X31 source base surfaces incorrectly cut out");quit(1);return
	var title:=Label.new();root.add_child(title);title.add_theme_font_override("font",SourceFont);title.add_theme_font_size_override("font_size",25);title.position=Vector2(25,20);title.text="PRODUCTION WORLD STREAM · ORIGINAL FOLIAGE + OPAQUE METAL"
	var note:=Label.new();root.add_child(note);note.add_theme_font_override("font",SourceFont);note.add_theme_font_size_override("font_size",20);note.position=Vector2(25,945);note.text="Source Tatooine placement/terrain · X31 art inspection only · Forward+ Vulkan · XR off"
	for frame:int in range(15):await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/environment-vulkan.png");root.get_texture().get_image().save_png(path)
	var report:Dictionary={"passed":true,"world":stream.report,"camera":eye.position,"x31_opaque_surfaces":opaque_surfaces,"source_vehicle":"object/mobile/vehicle/landspeeder_x31.iff","renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"headset_validated":false,"capture":path}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/environment-vulkan.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));ground.queue_free();stream.queue_free();vehicle.queue_free();await process_frame;await process_frame;quit(0)
