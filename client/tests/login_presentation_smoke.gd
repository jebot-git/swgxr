extends SceneTree
const Host=preload("res://tests/main_menu_lifecycle_smoke.gd").Host
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(20).timeout.connect(func():quit(2))
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var app:=Host.new();root.add_child(app);app.backend_url="https://galaxy.example.test"
	app.audio_preferences.path="user://login-presentation-fixture-%d.cfg"%OS.get_process_id();DirAccess.remove_absolute(app.audio_preferences.path)
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false);app.make_ui()
	app.menu.hide();app.account_panel.show();app.mode_label.text="SWG XR / GALACTIC CONNECTION"
	app.account_panel.status.text="";app.account_panel.account_input.text=""
	check(app.enter_button.text=="Enter Galaxy","Main entry action uses galaxy-wide label")
	var presentation=app.login_presentation
	var canvas_code:String=presentation.material.shader.code
	var sky_code:String=presentation.sky_environment.sky.sky_material.shader.code
	check(not canvas_code.contains("TIME") and not sky_code.contains("TIME"),"Login stars remain static in both menu and surrounding sky")
	check(canvas_code.contains("vec3(min(field,1.0))") and sky_code.contains("vec3(star*brightness*step"),"Both login shaders use white points over zero-valued black, without colored background")
	check(presentation.mouse_filter==Control.MOUSE_FILTER_IGNORE and presentation.get_index()==0,"Starfield sits behind UI and cannot intercept controller or mouse input")
	for _i in 180:
		if presentation.audio.playing:break
		await process_frame
	check(presentation.visible and presentation.active and presentation.audio.playing,"Visible login menu starts original login music asynchronously")
	check(presentation.catalog.sound=="sound/music_main_title.snd" and presentation.audio.stream is AudioStreamOggVorbis and presentation.audio.stream.loop and presentation.audio.stream.get_length()>115,"Decoded original main-title cue uses authored looping and source duration")
	check(presentation.audio.bus=="SWG Music" and presentation.catalog.fade_out_seconds==6,"Login music uses shared music bus and original six-second fade")
	check(app.player.get_camera().environment==presentation.sky_environment,"Login starfield also surrounds the camera outside the XR menu rectangle")
	if OS.get_cmdline_user_args().has("--capture"):
		for _i in 8:await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../runtime/evidence/login-starfield-vulkan.png")==OK,"Forward+ login evidence captures")
		app.account_panel.hide();app.menu.show();app.core3_ready=true;app.characters=[{"id":"fixture","name":"Zevrion"}];app.character_list.add_item("Zevrion");app.character_list.select(0);app.update_buttons()
		for _i in 8:await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../runtime/evidence/enter-galaxy-vulkan.png")==OK,"Forward+ Enter Galaxy evidence captures")
	var slider:HSlider=app.ui_root.find_child("MusicVolume",true,false)
	slider.value=.2
	var saved=preload("res://audio/preferences.gd").new();saved.path=app.audio_preferences.path;saved.load_preferences()
	check(is_equal_approx(saved.music,.2) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SWG Music")),linear_to_db(.2)-6),"Existing Music slider saves preference and changes login/world shared gain")
	slider.value=0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SWG Music")),"Zero Music preference actually mutes login and world bus")
	slider.value=.2
	app.world_ready=true;app.account_panel.hide();app.menu.show()
	await create_timer(.15).timeout
	check(not presentation.visible and not presentation.active and presentation.audio.playing and presentation.audio.volume_db<0,"Entering world hides stars and begins original music fade; pause menu cannot restart it")
	check(app.player.get_camera().environment==null,"World entry releases login sky override to the original planet environment")
	await create_timer(6.1).timeout
	check(not presentation.audio.playing,"Login cue stops after original fade while world remains active")
	app.world_ready=false;app.menu.show();await create_timer(.1).timeout
	check(presentation.active and presentation.audio.playing,"Returning to roster resumes original login cue")
	app.creator.show();await process_frame;await process_frame
	check(not presentation.active and not presentation.visible,"Character preview keeps its own original 3D background")
	app.free();await create_timer(.15).timeout
	DirAccess.remove_absolute(saved.path)
	var report:Dictionary={"checks":checks,"errors":errors,"audio":"original imported login cue; Dummy output","renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method(),"driver":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_driver_name(),"headset_validated":false}
	var report_path:="res://../runtime/evidence/login-presentation-vulkan.json" if OS.get_cmdline_user_args().has("--capture") else "res://../runtime/evidence/login-presentation-smoke.json"
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
