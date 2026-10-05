extends SceneTree
## Real audio mixing required: --headless --xr-mode off --audio-driver PulseAudio.
## Adapted from FPSloppa's HRTF/level/lifetime regression at 8fbf5c8.
var errors: Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: errors.append(label); push_error(label)
func energy(capture: AudioEffectCapture) -> Vector2:
	var frames:=capture.get_buffer(capture.get_frames_available()); var sum:=Vector2.ZERO
	for sample in frames:
		if not sample.is_finite(): return Vector2.INF
		sum+=sample*sample
	return sum/maxi(1,frames.size())
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var camera:=Camera3D.new(); world.add_child(camera); camera.make_current()
	var audio = root.get_node("SWGSpatialAudio")
	audio.configure(camera,null,"steam_audio",true)
	check(audio.backend=="steam_audio","Pinned native Steam Audio loads with current Godot")
	var silent:=AudioServer.bus_count; AudioServer.add_bus(); AudioServer.set_bus_name(silent,"TestSilent"); AudioServer.set_bus_volume_db(silent,-80)
	var capture_bus:=AudioServer.bus_count; AudioServer.add_bus(); AudioServer.set_bus_name(capture_bus,"HRTFTest"); AudioServer.set_bus_send(capture_bus,"TestSilent")
	var capture:=AudioEffectCapture.new(); capture.buffer_length=1; AudioServer.add_bus_effect(capture_bus,capture)
	var tone:=AudioStreamWAV.new(); tone.format=AudioStreamWAV.FORMAT_16_BITS; tone.mix_rate=48000
	var bytes:=PackedByteArray(); bytes.resize(96000)
	for i in range(48000): bytes.encode_s16(i*2,roundi(1800*sin(i*TAU*660/48000.0)))
	tone.data=bytes; tone.loop_mode=AudioStreamWAV.LOOP_FORWARD; tone.loop_end=48000
	var player: AudioStreamPlayer3D=audio.create_player(20,160)
	player.bus="HRTFTest"; player.stream=tone; world.add_child(player); player.position=Vector3(-3,0,0); player.play()
	await create_timer(0.3).timeout; capture.clear_buffer(); await create_timer(0.3).timeout
	var left:=energy(capture)
	check(left.is_finite() and left.x>0.000001 and left.x>left.y*1.05,"HRTF produces directional left-ear output")
	camera.rotation.y=PI; audio.sync_listener(); capture.clear_buffer(); await create_timer(0.4).timeout
	var right:=energy(capture)
	check(right.is_finite() and right.y>right.x*1.05,"HMD rotation reverses ear direction")
	player.stop(); player.free(); camera.rotation.y=0
	audio.configure(camera,null,"stereo",true)
	player=audio.create_player(20,160); player.bus="HRTFTest"; player.stream=tone; world.add_child(player); player.position=Vector3(-3,0,0); player.play()
	await create_timer(0.15).timeout; capture.clear_buffer(); await create_timer(0.3).timeout
	var standard:=energy(capture)
	check(standard.is_finite() and standard.length()>0.000001,"Standard fallback produces actual audio")
	check(left.x+left.y>=(standard.x+standard.y)*0.25,"Native reference-distance gain remains within 6 dB of fallback")
	player.stop(); player.free()
	audio.configure(camera,null,"steam_audio",true)
	var assets=preload("res://combat/original_assets.gd").new(); check(assets.load_catalog(),"Original SWG sound manifest loads")
	var source: String=assets.catalog.effects[assets.catalog.weapons.pistol_cdef.effects.fire].sounds[0]
	# Source records stay untouched; route test playback to the inaudible output bus.
	AudioServer.set_bus_send(AudioServer.get_bus_index("SWG Spatial"),"TestSilent")
	var shot: AudioStreamPlayer3D=audio.play_original(assets,source,Vector3(0,0,-1),2)
	check(shot!=null and shot.get_meta("source_sample")==assets.catalog.sounds[source].samples[0] and shot.pitch_scale==1.0,"CDEF emits original recording at original pitch")
	var wall:=StaticBody3D.new(); world.add_child(wall); wall.position=Vector3(0,0,-0.5)
	var collider:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=Vector3(2,2,0.05); collider.shape=shape; wall.add_child(collider)
	await physics_frame; await physics_frame
	audio.update_source(shot)
	check(shot.get_meta("occluded") and is_equal_approx(shot.volume_db,float(shot.get_meta("dry_db"))-10) and shot.attenuation_filter_cutoff_hz==1800,"World obstruction muffles original shot")
	wall.free(); await physics_frame; audio.update_source(shot)
	check(not shot.get_meta("occluded") and shot.attenuation_filter_cutoff_hz==18000,"Removing obstruction restores shot clarity")
	audio.clear(); await process_frame
	for i in range(40): audio.play_original(assets,source,Vector3(0,0,-1),1)
	check(audio.active.size()<=32 and audio.stolen>0,"Automatic-fire tails have bounded voice count")
	audio.clear(); await process_frame
	for batch in range(24):
		for i in range(12):
			var voice: AudioStreamPlayer3D=audio.create_player(20,160)
			voice.stream=tone; voice.bus="HRTFTest"; world.add_child(voice); voice.play()
			if i%3==0: voice.free()
			else: voice.queue_free()
		await create_timer(0.025).timeout
	check(audio.active.is_empty(),"288 rapidly retired native sources leave no live weapon voices")
	camera.position=Vector3(2,1.7,3); audio.sync_listener()
	check(audio.steam_listener.global_transform==camera.global_transform,"Listener follows physical HMD translation")
	var report:={"test":"weapon_audio_hrtf","passed":errors.is_empty(),"checks":checks,"errors":errors,"left_energy":str(left),"rotated_energy":str(right),"standard_energy":str(standard),"audio_mixed":true,"hardware_listening_tested":false}
	FileAccess.open("res://../runtime/evidence/weapon-audio-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	audio.clear(); AudioServer.set_bus_send(AudioServer.get_bus_index("SWG Spatial"),"Master")
	AudioServer.remove_bus(AudioServer.get_bus_index("HRTFTest")); AudioServer.remove_bus(AudioServer.get_bus_index("TestSilent"))
	world.queue_free(); await create_timer(0.15).timeout; quit(0 if errors.is_empty() else 1)
