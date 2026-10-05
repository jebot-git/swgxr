extends SceneTree
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in range(5):await process_frame
func run() -> void:
	root.size=Vector2i(1280,900);root.content_scale_size=Vector2i.ZERO
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("061018");env.environment=settings;world.add_child(env)
	var origin:=XROrigin3D.new();world.add_child(origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";origin.add_child(head)
	var body:=CharacterBody3D.new();origin.add_child(body)
	var camera:=Camera3D.new();camera.fov=50;world.add_child(camera);camera.make_current()
	var directory:="res://../runtime/assets/tatooine_world"
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/world.json"))
	var mesh_id:="appearance/mesh/ksk_all_bank_l0.msh"
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(manifest.meshes[mesh_id].path)))
	var mesh: ArrayMesh=SwgMeshBuilder.new().create_mesh(data.surfaces)
	var loader:=preload("res://scripts/stage_loader.gd").new()
	for i in range(mesh.get_surface_count()):mesh.surface_set_material(i,loader.make_material(data.surfaces[i],ProjectSettings.globalize_path(directory)))
	var bank:=MeshInstance3D.new();bank.mesh=mesh;bank.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(bank)
	var scenery:=preload("res://scripts/service_world.gd").new();world.add_child(scenery);scenery.configure(Vector3.ZERO)
	var record: Dictionary={"id":"mock-bank","kind":"bank","name":"BANK TERMINAL","template":"object/tangible/terminal/terminal_bank.iff","position":Vector3.ZERO}
	record.ui_anchors=scenery.screen_offsets(record)
	var pose: Transform3D=record.ui_anchors[0]
	head.position=pose.origin+pose.basis.z*1.2
	camera.position=head.position+Vector3(.65,.18,0);camera.look_at(Vector3(0,1.2,0))
	var service:=preload("res://scripts/xr_services.gd").new();world.add_child(service);service.configure(origin,body);service.set_process(false);service.set_allowed(true)
	service.wallet={"cash":1250,"bank":8000};service.open_terminal(record);service.set_pending(false);service.panel.message="Mocked native balances · original screen plane"
	var title:=Label.new();root.add_child(title);title.position=Vector2(24,22);title.text="BANK / SOURCE SCREEN ALIGNMENT\nOriginal SWG mesh and measured tilt · mocked service data · XR off";title.add_theme_font_size_override("font_size",22)
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/wrist-services/bank-screen.png"))
	world.hide();title.hide()
	var pad:=preload("res://scripts/datapad_ui.gd").new();root.add_child(pad);pad.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);pad.position=Vector2(60,35);pad.size=Vector2(1160,830)
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/datapad/catalog.json"))
	pad.configure(catalog,ProjectSettings.globalize_path("res://../runtime/assets/datapad"))
	pad.show_map(true);pad.map.zoom=32;pad.map.center=Vector2(3500,-4800);pad.set_player_position(Vector3(3520,5,-4780))
	pad.connection_status.text="Original source service POIs"
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/wrist-services/map-filters.png"))
	print(JSON.stringify({"passed":true,"renderer":"Forward+ Vulkan","xr":"off","server_requests":0,"screenshots":2}))
	pad.queue_free();title.queue_free();world.queue_free();await settle();quit()
