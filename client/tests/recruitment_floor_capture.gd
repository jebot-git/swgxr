extends SceneTree
## Production streaming/material paths, original Tatooine scene and source X31.
const World=preload("res://scripts/world_stream.gd")
const Terrain=preload("res://scripts/terrain_stream.gd")
const Ambient=preload("res://scripts/ambient_npcs.gd")
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const SourceFont=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1600,1000)
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE);RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color(.95,.92,.86));RenderingServer.global_shader_parameter_set("swg_daylight",1.0)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("8ba6b4");root.add_child(environment)
	var stream:=World.new();root.add_child(stream);stream.render_distance=256;stream.collision_distance=256
	if not stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json")):push_error("Original world unavailable");quit(1);return
	var center:=Vector3(-114,0,-64)
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.fov=66;eye.position=center+Vector3(1,2.1,-5);eye.look_at(center+Vector3(0,.8,0));stream.cell_owner.set_observer(eye)
	var ground:=Terrain.new();root.add_child(ground);var origin:Array=stream.manifest.origin
	ground.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(origin[0],origin[1],origin[2]));ground.set_cell_source(stream.cell_owner);ground.update_observer(center);stream.update_observer(center)
	var deadline:=Time.get_ticks_msec()+90000
	while not stream.report.get("ready",false) or not ground.ready_near(center,0):
		if Time.get_ticks_msec()>deadline:push_error("Production world stream did not become ready");quit(1);return
		await process_frame
	var placements:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")))
	var ambient:=Ambient.new();root.add_child(ambient);ambient.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"),stream.cell_owner,ground)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":push_error("Desktop Forward+ Vulkan required");quit(1);return
	var rows:Array=[]
	for entry:Dictionary in placements.instances:
		if str(entry.get("cell_id",""))!="1280129:2":continue
		ambient.instantiate_entry(entry)
		var result:Dictionary=ambient.records.get(str(entry.id),{})
		if result.is_empty():push_error("Original imperial variant missing");quit(1);return
		rows.append({"id":entry.id,"source":entry.source_world_xyz,"presentation_position":result.avatar.global_position,"ground_adjustment":result.ground_adjustment})
	ambient.set_process(false)
	eye.position=Vector3(-113.1,2.0,-58.5);eye.look_at(Vector3(-119,1.1,-66.5));stream.cell_owner.seed_membership_at(eye.position-Vector3.UP*1.6,"1280129:2")
	var title:=Label.new();root.add_child(title);title.add_theme_font_override("font",SourceFont);title.add_theme_font_size_override("font_size",25);title.position=Vector2(25,20);title.text="ORIGINAL IMPERIAL RECRUITMENT CENTER · AUTHORED CELL FLOOR"
	for i:int in range(15):await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/npc-floating/recruitment-vulkan.png");root.get_texture().get_image().save_png(path)
	var result:Dictionary={"passed":true,"capture":path,"original_source_placements":rows,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"headset_validated":false,"live_server_entities":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/npc-floating/recruitment-vulkan.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));ambient.queue_free();ground.queue_free();stream.queue_free();await process_frame;await process_frame;quit()
