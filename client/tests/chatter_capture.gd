extends SceneTree
const Fixture=preload("res://tests/chatter_smoke.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,900);root.content_scale_size=root.size
	var host:=Fixture.Host.new();root.add_child(host);host.stage=Fixture.Stage.new();host.add_child(host.stage);host.player=Fixture.Player.new();host.add_child(host.player)
	host.player.eye=Camera3D.new();host.player.add_child(host.player.eye);host.player.eye.position=Vector3(0,1.65,5.3);host.player.eye.look_at(Vector3(0,1.25,0));host.player.eye.current=true;host.player.eye.fov=58
	host.multiplayer_sync=Fixture.Sync.new();host.add_child(host.multiplayer_sync);host.multiplayer_sync.entities=Fixture.Entities.new();host.add_child(host.multiplayer_sync.entities)
	var env:=WorldEnvironment.new();host.add_child(env);env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("101d27");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("f6e6c9");env.environment.ambient_light_energy=.9
	var bubbles:=preload("res://chatter/controller.gd").new();host.add_child(bubbles);bubbles.setup(host)
	var passed:=true
	var recording:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/chatter-native-preview.json")) if FileAccess.file_exists("res://../runtime/evidence/chatter-native-preview.json") else {}
	var recorded:Array=recording.get("rows",[])
	for i in range(2):
		var actor:=preload("res://combat/live_actor.gd").new();host.add_child(actor)
		var template:="object/mobile/dressed_commoner_tatooine_rodian_male_01.iff" if i==0 else "object/mobile/dressed_commoner_old_human_male_02.iff"
		var source:Dictionary=recorded[i].actor.duplicate(true) if recorded.size()>i else {"id":str(i+42),"kind":"creature","template":template,"dead":false,"name":"Source NPC","health":100,"max_health":100,"scale":1.0}
		passed=actor.configure(source,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json")) and passed
		actor.set_process(false);actor.position=Vector3(-1.15 if i==0 else 1.15,0,0);actor.rotation.y=PI;host.multiplayer_sync.entities.actors[str(source.id)]=actor
		var event:Dictionary={"id":str(i+1),"actor_id":str(i+42),"zone":"tatooine","building_id":"0","cell_index":0,"language_name":"Rodese" if i==0 else "Galactic Basic","text":"Nehka lo ronn cha?" if i==0 else "Quiet day at the starport.","age_ms":0,"lifetime_ms":6000}
		if recorded.size()>i:event=recorded[i].event.duplicate(true)
		bubbles.accept({"sequence":i+1,"events":[event],"languages":[]})
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(24,24);caption.text="NPC SPEECH · DESKTOP PRESENTATION TEST\nOriginal NPC bodies and animated head anchors · mocked speech · no live headset";caption.text="NPC SPEECH · DESKTOP PRESENTATION TEST\nRecorded native speech and original actors · arranged inspection · no live headset" if not recorded.is_empty() else caption.text;caption.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Regular.ttf"));caption.add_theme_font_size_override("font_size",20)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	passed=root.get_texture().get_image().save_png("res://../runtime/evidence/chatter-vulkan.png")==OK and passed
	var report:Dictionary={"passed":passed,"renderer":RenderingServer.get_current_rendering_method(),"speech":"recorded native" if not recorded.is_empty() else "mocked","layout":"arranged desktop inspection","original_assets":true,"live_xr":false,"bubbles":bubbles.statistics()};FileAccess.open("res://../runtime/evidence/chatter-vulkan.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));host.free();caption.free();await process_frame;quit(0 if passed else 1)
