extends SceneTree
## Actual local cantina content, streaming responsiveness and interior audio routing.
## --capture adds desktop Vulkan evidence; all invocations require --xr-mode off.
const WorldStream = preload("res://scripts/world_stream.gd")
const EnvironmentPresentation = preload("res://scripts/environment_presentation.gd")
const Terrain = preload("res://scripts/terrain_stream.gd")
const MAIN_ROOM_FEET := Vector3(-190.798396,-0.894992,22.327722) # Original FLR triangle 92 centroid.
var errors: Array[String] = []
var frames: Array[float] = []
var recording := false
var last_frame := 0
var output := "res://../runtime/evidence/cantina-integration.json"
var capture := false
var stream: Node3D
var presentation: Node3D
var observer: CharacterBody3D
var camera: Camera3D
var report := {"test":"actual_cantina_interior_integration","headset_tested":false,"audio_output":"Dummy","audibility_tested":false}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--capture": capture=true
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func _process(_delta: float) -> bool:
	if recording:
		var now := Time.get_ticks_usec()
		if last_frame>0: frames.append((now-last_frame)/1000.0)
		last_frame=now
	return false

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty():return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"samples":sorted.size(),"p50":sorted[ceili(sorted.size()*0.5)-1],"p95":sorted[ceili(sorted.size()*0.95)-1],"max":sorted[-1]}

func run() -> void:
	root.size=Vector2i(1280,800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("world.json")))
	var chunk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(manifest.chunks["-1:0"].path)))
	var expected := {}
	var expected_instances := 0
	for entry in chunk.instances:
		if int(entry.get("building_object_id",0))==1082874 and entry.has("source_layout"):
			expected[str(int(entry.object_id))]=true
			expected_instances+=1
	check(expected_instances>0,"Cantina manifest has no imported ILF decorations")
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	observer=CharacterBody3D.new()
	root.add_child(observer)
	observer.position=MAIN_ROOM_FEET
	camera=Camera3D.new()
	observer.add_child(camera)
	camera.position=Vector3(0,1.7,0)
	camera.fov=85
	camera.make_current()
	camera.look_at(Vector3(-174,0.805,29))
	stream=WorldStream.new()
	stream.render_distance=128.0
	root.add_child(stream)
	var start := Time.get_ticks_usec()
	check(stream.configure(directory.path_join("world.json"),scene),"World configure failed")
	var configure_ms := (Time.get_ticks_usec()-start)/1000.0
	start=Time.get_ticks_usec()
	stream.set_observer(observer)
	var request_ms := (Time.get_ticks_usec()-start)/1000.0
	start=Time.get_ticks_usec()
	recording=true
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if stream.report.get("ready",false):break
		if not str(stream.report.get("error","")).is_empty():break
	recording=false
	check(stream.report.get("ready",false),"World did not finish loading: "+str(stream.report.get("error","")))
	report["streaming"]={"configure_ms":configure_ms,"request_ms":request_ms,"settle_ms":(Time.get_ticks_usec()-start)/1000.0,"frame_interval_ms":stats(frames),"state":stream.report.duplicate(true)}
	var observed := {}
	var loaded_instances := 0
	for region in stream.chunks.values():
		for record in region.instances:
			var id := str(int(record.instance.get_meta("object_id",0)))
			if expected.has(id):
				observed[id]=true
				loaded_instances+=1
	check(observed.size()==expected.size(),"Some expected cantina decoration objects did not load")
	check(loaded_instances==expected_instances,"Cantina decoration mesh instance count differs from source manifest")
	report["decorations"]={"expected_objects":expected.size(),"loaded_objects":observed.size(),"expected_mesh_instances":expected_instances,"loaded_mesh_instances":loaded_instances}
	stream.cell_owner.seed_membership_at(observer.global_position,"1082874:3")
	stream.cell_owner.update_cell(true)
	check(str(stream.cell_owner.current_cell.get("cell_id",""))=="1082874:3","Observer failed to enter original cantina cell")
	var support: Dictionary = stream.cell_owner.ground_support.sample_support(observer.global_position,["1082874:3"],0.1,0.1)
	check(support.get("valid",false),"Cantina fixture is not on its original walkable floor")
	report["authored_floor_support"]=support.get("valid",false)
	var terrain := Terrain.new()
	root.add_child(terrain)
	terrain.origin=Vector3(scene.origin[0],scene.origin[1],scene.origin[2])
	terrain.evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain/tatooine.json")))
	terrain.configured=true
	presentation=EnvironmentPresentation.new()
	root.add_child(presentation)
	check(presentation.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_environment/environment.json")),"Environment configure failed")
	presentation.bind_world(terrain,stream.cell_owner)
	presentation.update_observer(observer.global_position)
	presentation.set_active(true)
	presentation.refresh_region_and_emitters()
	await create_timer(5).timeout
	check(presentation.indoors,"Cantina observer was not treated as indoors")
	check(str(presentation.report.get("selected_soundscape"," ")).contains("cantina"),"Original cantina soundscape was not selected")
	check(not presentation.report.get("emitter_sounds",[]).is_empty(),"No authored cantina emitters entered playback residency")
	for cue in ["sound/amb_cantina_large_lp.snd","sound/music_figrin_dan_song_1.snd"]:
		var playing := false
		for emitter in presentation.emitters.values():
			if emitter.get_meta("sound","")==cue and emitter.playing and emitter.stream!=null: playing=true
		check(playing,"Authored cantina cue did not start playback: "+cue)
	report["interior_audio"]=presentation.report.duplicate(true)
	var band_before: Node
	for emitter in presentation.emitters.values():
		if emitter.get_meta("sound","")=="sound/music_figrin_dan_song_1.snd": band_before=emitter
	observer.position=Vector3(-189.86885,-0.895,30.64273)
	stream.cell_owner.seed_membership_at(observer.global_position,"1082874:6")
	stream.cell_owner.update_cell(true)
	presentation.update_observer(observer.global_position)
	presentation.refresh_region_and_emitters()
	await create_timer(0.25).timeout
	var continuous := false
	for emitter in presentation.emitters.values():
		if emitter==band_before and emitter.playing: continuous=true
	check(continuous,"Band playback restarted or stopped when entering an adjacent cantina alcove")
	report["adjacent_room_band_continuity"]=continuous
	observer.position=MAIN_ROOM_FEET
	stream.cell_owner.seed_membership_at(observer.global_position,"1082874:3")
	stream.cell_owner.update_cell(true)
	presentation.update_observer(observer.global_position)
	presentation.refresh_region_and_emitters()
	if capture:
		check(DisplayServer.get_name()!="headless","Capture requires desktop Forward+ Vulkan")
		for index in range(2):
			camera.global_position=MAIN_ROOM_FEET+Vector3.UP*1.7 if index==0 else Vector3(-170.7493,0.805,23.8010)
			camera.look_at(Vector3(-174,0.805,29) if index==0 else Vector3(-190,0.805,24))
			await create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/cantina-interior-%d.png" % index))
	observer.position=Vector3(-140,0.1,60)
	stream.cell_owner.seed_membership_at(observer.global_position,"")
	stream.cell_owner.update_cell(true)
	presentation.update_observer(observer.global_position)
	presentation.refresh_region_and_emitters()
	await create_timer(2).timeout
	check(not presentation.indoors,"Cantina soundscape remained indoors after leaving")
	for emitter in presentation.emitters.values():
		check(emitter.get_meta("sound","") not in ["sound/amb_cantina_large_lp.snd","sound/music_figrin_dan_song_1.snd"],"Cantina cue remained resident outside its building")
	report["exterior_audio"]=presentation.report.duplicate(true)
	presentation.set_active(false)
	report["gpu_capture"]=capture
	report["asset_manifest_sha256"]={"world":FileAccess.get_sha256(directory.path_join("world.json")),"environment":FileAccess.get_sha256(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_environment/environment.json"))}
	report["passed"]=errors.is_empty()
	report["errors"]=errors
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CANTINA_INTEGRATION "+JSON.stringify(report))
	stream.queue_free()
	presentation.queue_free()
	terrain.queue_free()
	observer.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
