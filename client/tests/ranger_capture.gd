extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1160,760);root.content_scale_size=root.size
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/ranger-preview.json"))
	var background:=ColorRect.new();background.color=Color("101d27");background.size=Vector2(1160,760);root.add_child(background)
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(24,24);caption.text="RANGER · DESKTOP INSPECTION\nRecorded native search results / original owned kit · no live headset";caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",21)
	var panel:=preload("res://scout/ranger_panel.gd").new();root.add_child(panel);panel.position=Vector2(20,130);panel.apply(source.ranger)
	var container:=SubViewportContainer.new();root.add_child(container);container.position=Vector2(900,150);container.size=Vector2(240,350)
	var view:=SubViewport.new();container.add_child(view);view.size=Vector2i(240,350);view.own_world_3d=true;view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var environment:=WorldEnvironment.new();view.add_child(environment);environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("dae6e7");environment.environment.ambient_light_energy=.8
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure();var mesh:ArrayMesh=assets.model(str(source.kit_template))
	if mesh==null:push_error("Recorded native kit has no original source model");quit(2);return
	var item:=MeshInstance3D.new();item.mesh=mesh;view.add_child(item)
	var bounds:=mesh.get_aabb();item.rotation=Vector3(.2,.45,0);item.position=-(item.basis*bounds.get_center())
	var camera:=Camera3D.new();view.add_child(camera);camera.position=Vector3(0,0,maxf(.1,bounds.size.length()*2.4));camera.look_at(Vector3.ZERO);camera.fov=38;camera.current=true
	var label:=Label.new();root.add_child(label);label.position=Vector2(900,520);label.size=Vector2(240,120);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.text="Original camouflage kit\n"+str(source.kit_template).get_file().trim_suffix(".iff").replace("_"," ");label.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));label.add_theme_font_size_override("font_size",19)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://../runtime/evidence/ranger-vulkan.png";var saved:=root.get_texture().get_image().save_png(path)==OK
	var report:Dictionary={"passed":saved and mesh!=null,"renderer":RenderingServer.get_current_rendering_method(),"source":source.source,"kit_template":source.kit_template,"live_xr":false,"native_requests_sent":0};FileAccess.open("res://../runtime/evidence/ranger-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	for child in root.get_children():child.free()
	assets=null;await process_frame;quit(0 if report.passed else 1)
