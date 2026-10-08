extends SceneTree
var errors: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)
func pump_audio(presentation: Node3D) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		presentation._process(0.0)
		if presentation.audio_cache.workers.is_empty() and presentation.audio_cache.queued.is_empty() and presentation.pending_music.is_empty(): return
		await create_timer(0.01).timeout
	check(false,"Background audio load timed out")

func decode_sound(presentation: Node3D, sound: String) -> AudioStream:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var audio: AudioStream = presentation.stream(sound)
		if audio!=null: return audio
		presentation.audio_cache.poll()
		await create_timer(0.005).timeout
	return null

func run() -> void:
	var presentation := preload("res://scripts/environment_presentation.gd").new()
	root.add_child(presentation)
	presentation.set_process(false)
	check(presentation.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_environment/environment.json")),"Original environment manifest failed")
	var terrain := preload("res://scripts/terrain_stream.gd").new()
	root.add_child(terrain)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain/tatooine.json"))
	terrain.evaluator.configure(source)
	terrain.source_manifest = source
	terrain.origin = Vector3(3618.9838867,5,-4801.0859375)
	terrain.configured = true
	presentation.bind_world(terrain,null)
	presentation.update_observer(Vector3.ZERO)
	presentation.set_active(true)
	presentation.refresh_region_and_emitters()
	await pump_audio(presentation)
	check(presentation.family == "moseisley","Source AENV rules did not select Mos Eisley")
	presentation.set_phase(0.25)
	var noon: float = presentation.report.daylight
	presentation.set_phase(0.75)
	var night: float = presentation.report.daylight
	check(noon > 0.99 and night < 0.01,"Day/night lighting weights do not cycle")
	var events: int = presentation.report.music_events
	presentation.set_phase(0.49999)
	presentation._process(1.0)
	await pump_audio(presentation)
	check(presentation.report.music_events > events and str(presentation.report.music).contains("sunset"),"Sunset did not start source music cue")
	presentation.set_phase(0.99999)
	presentation._process(1.0)
	await pump_audio(presentation)
	check(str(presentation.report.music).contains("sunrise"),"Sunrise did not start source music cue")
	var loaded := 0
	for sound in presentation.manifest.sounds:
		var audio: AudioStream = await decode_sound(presentation,sound)
		check(audio != null and audio.get_length() > 0, "Original audio failed to decode: " + sound)
		if audio != null:
			loaded += 1
	check(presentation.audio_cache.cached.size()<=32 and presentation.audio_cache.evicted>0,"Decoded audio cache must evict above 32 retained streams")
	check(presentation.audio_cache.workers.size()<=2 and presentation.audio_cache.peak_pending<=32,"Background decode concurrency and queue must remain bounded")
	presentation.set_phase(0.25)
	presentation._process(0.1)
	check(presentation.ambient[0].playing and presentation.music[presentation.music_index].playing,"Source audio did not enter playback")
	presentation.update_observer(terrain.terrain_position(Vector2(-1244,-3596)))
	presentation.refresh_region_and_emitters()
	await pump_audio(presentation)
	check(presentation.family == "bestinetownship","Source AENV rules did not switch regional environment")
	check(presentation.emitters.size() <= 12,"Ambient sound emitter residency unbounded")
	check(presentation.find_children("*","Light3D",true,false).is_empty(),"Environment added dynamic lights")
	presentation.set_active(false)
	check(not presentation.ambient[0].playing and presentation.emitters.is_empty(),"Environment audio did not stop")
	var report := {"test":"source_environment_cycle_audio_regions", "passed":errors.is_empty(), "errors":errors, "decoded_sounds":loaded,"source_families":presentation.manifest.families.size(),"source_emitters":presentation.manifest.emitters.size(),"no_dynamic_lights":true,"hardware_tested":false,"audio_output":"Dummy","background_audio":presentation.audio_cache.statistics()}
	FileAccess.open("res://../runtime/evidence/environment-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	presentation.queue_free()
	terrain.queue_free()
	await create_timer(0.25).timeout
	quit(0 if errors.is_empty() else 1)
