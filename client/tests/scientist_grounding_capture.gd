extends SceneTree
## Production streaming/material paths, original Tatooine scene and source X31.
const World=preload("res://scripts/world_stream.gd")
const Terrain=preload("res://scripts/terrain_stream.gd")
const Actor=preload("res://combat/live_actor.gd")
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
	var center:=Vector3(-150.3818359375,0,-62.9228515625)
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.fov=66;eye.position=center+Vector3(-1,2.1,5);eye.look_at(center+Vector3(0,.8,0));stream.cell_owner.set_observer(eye)
	var ground:=Terrain.new();root.add_child(ground);var origin:Array=stream.manifest.origin
	ground.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(origin[0],origin[1],origin[2]));ground.set_cell_source(stream.cell_owner);ground.update_observer(center);stream.update_observer(center)
	var deadline:=Time.get_ticks_msec()+90000
	while not stream.report.get("ready",false) or not ground.ready_near(center,0):
		if Time.get_ticks_msec()>deadline:push_error("Production world stream did not become ready");quit(1);return
		await process_frame
	var row:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/scientist-native-row.json")))
	if "--second" in OS.get_cmdline_user_args():row.position=[3348.69,5,-4513.14];row.template="object/mobile/dressed_combatmedic_trainer_human_male_01.iff"
	var binding=load("res://combat/live_ambient_bindings.gd").new();binding.configure(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"))));binding.update([row]);print("SOURCE_BINDINGS ",binding.bindings)
	var vehicle:=Actor.new();root.add_child(vehicle);vehicle.configure(row,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));vehicle.apply_record(row,Transform3D(Basis(Vector3.UP,0.0),center),0.1,true)
	for i:int in range(5):await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*2,center-Vector3.UP*2,3)
	print("SOURCE_GROUND_RAY ",vehicle.get_world_3d().direct_space_state.intersect_ray(ray))
	print("SOURCE_GROUND_SUPPORT ",stream.cell_owner.ground_support.sample_support(center,stream.cell_owner.exterior_ids,2.0,2.0,{}))
	var opaque_surfaces:=0
	var title:=Label.new();root.add_child(title);title.add_theme_font_override("font",SourceFont);title.add_theme_font_size_override("font_size",25);title.position=Vector2(25,20);title.text="ORIGINAL SCIENTIST · ACTUAL NATIVE SNAPSHOT POSITION"
	var note:=Label.new();root.add_child(note);note.add_theme_font_override("font",SourceFont);note.add_theme_font_size_override("font_size",20);note.position=Vector2(25,945);note.text="Source Tatooine placement/terrain · native scientist sourceY = 5m · Forward+ Vulkan · XR off"
	for frame:int in range(15):await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/scientist-remote-vulkan.png");root.get_texture().get_image().save_png(path)
	var report:Dictionary={"passed":true,"world":stream.report,"camera":eye.position,"source_template":row.template,"source_position":row.position,"source_binding":binding.bindings,"variant_fixture": "--second" in OS.get_cmdline_user_args(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"headset_validated":false,"capture":path}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/scientist-remote-vulkan.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));ground.queue_free();stream.queue_free();vehicle.queue_free();await process_frame;await process_frame;quit(0)
