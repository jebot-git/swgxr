extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":
		push_error("Requires desktop Forward+ Vulkan, XR disabled"); quit(1); return
	root.size=Vector2i(1280,720)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("18202a");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.8;world.add_child(env)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(50,50);floor.mesh=plane;var material:=StandardMaterial3D.new();material.albedo_color=Color("766954");material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;floor.material_override=material;world.add_child(floor)
	var eye:=Camera3D.new();world.add_child(eye);eye.position=Vector3(13,12,16);eye.look_at(Vector3.ZERO);eye.current=true
	var row: Dictionary = {"id":"fixture","name":"Original SWG avatar · visual fixture","position":Vector3.ZERO,"appearance":{"template":"object/creature/player/human_male.iff","height":1.0,"customization":{},"equipment":[]}}
	var source_path := ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-native-world.json")
	if FileAccess.file_exists(source_path):
		var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
		for record: Dictionary in evidence.get("responses", []):
			if str(record.get("path", "")) == "/session/sync" and not record.get("response", {}).get("world", {}).get("players", []).is_empty():
				row = record.response.world.players[0].duplicate(true); row.position = Vector3.ZERO; row.name = "Native CoreCU appearance · isolated capture"; break
	row.heading_radians = -float(row.get("heading_radians", 0.0))
	var peer:=preload("res://multiplayer/remote_player.gd").new();world.add_child(peer);peer.configure();peer.apply_peer(row);peer.advance(0.01)
	var pulse:=preload("res://multiplayer/survey_pulse.gd").shared(world,eye);pulse.set_process(false);pulse.play_confirmed(Vector3.ZERO,"visual-fixture")
	var title:=Label.new();root.add_child(title);title.position=Vector2(28,20);title.add_theme_font_size_override("font_size",24);title.text="SURVEY PULSE · source-style bounded approximation"
	var note:=Label.new();root.add_child(note);note.position=Vector2(28,670);note.add_theme_font_size_override("font_size",18);note.text="Desktop Vulkan · fixed 12 m presentation radius · no survey/yield simulation · no dynamic lights"
	var paths:Array=[]
	for age in [0.35,1.05]:
		pulse.advance(age-(0.0 if paths.is_empty() else 0.35))
		title.text="SURVEY PULSE · %0.2f s · source-style bounded approximation"%age
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var path:=ProjectSettings.globalize_path("res://../runtime/evidence/survey-pulse-%03dms.png"%int(age*1000))
		root.get_texture().get_image().save_png(path);paths.append(path)
	pulse.clear()
	eye.position=-peer.global_basis.z*3.5+Vector3.UP*1.7;eye.look_at(Vector3(0,1.0,0))
	title.text="ACTUAL CORECU PEER · original appearance and equipment"
	note.text="Recorded native snapshot · source shirt, pants and shoes · isolated desktop Vulkan replay"
	peer.label.visible=false
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var avatar_path:=ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-native-avatar.png")
	root.get_texture().get_image().save_png(avatar_path);paths.append(avatar_path)
	var cache:=preload("res://multiplayer/avatar_instance_cache.gd").new();cache.remember(row.appearance,peer.avatar)
	var cached_peer:=preload("res://multiplayer/remote_player.gd").new();world.add_child(cached_peer);cached_peer.configure();cached_peer.appearance_cache=cache
	var copied_row:=row.duplicate(true);copied_row.id="cache-presentation-fixture";copied_row.position=peer.global_basis.x*2.0
	cached_peer.apply_peer(copied_row);cached_peer.advance(0.05);cached_peer.label.visible=false
	var wrist:Transform3D=cached_peer.avatar.skeleton.global_transform*cached_peer.avatar.skeleton.get_bone_global_pose(cached_peer.avatar.skeleton.find_bone("lwrist"))
	wrist.origin+=Vector3.UP*0.65-peer.global_basis.z*0.15
	copied_row.tracking={"left_hand":wrist};cached_peer.apply_peer(copied_row);cached_peer.advance(0.1)
	var center:Vector3=peer.global_basis.x
	eye.position=center-peer.global_basis.z*5.3+Vector3.UP*1.8;eye.look_at(center+Vector3.UP)
	title.text="ORIGINAL + CACHED INSTANCE · independent tracked arm"
	note.text="Shared source geometry · separate skeletons/materials/animation · one cached player raises its left hand"
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var cached_path:=ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-cached-avatar.png")
	root.get_texture().get_image().save_png(cached_path);paths.append(cached_path)
	var report:={"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"captures":paths,"statistics":pulse.statistics(),"headset_validated":false,"original_reference":"CoreCU SurveySessionImplementation broadcasts activeSurveyTool.getSurveyAnimation; mineral tool uses clienteffect/survey_tool_mineral.cef. Analytic ground ring is a bounded style approximation, not decoded original CEF playback."}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/survey-pulse-capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	cache.clear();pulse.queue_free();world.queue_free();await process_frame;await process_frame;quit(0)
