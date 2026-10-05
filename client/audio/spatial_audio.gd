extends Node3D
## Adapted from FPSloppa deathmatch/audio/{steam_backend,spatial}.gd at
## 8fbf5c829d356226065868189c615b72c3bc1646, reused with the owner's permission.
## Original SWG recordings only; bounded CPU HRTF, no synthetic replacement SFX.
const MAX_VOICES := 32
var camera: Camera3D
var stage: Node3D
var config: Node3D
var steam_listener: Node3D
var standard_listener: AudioListener3D
var backend := "stereo"
var enabled := false
var active: Array[AudioStreamPlayer3D] = []
var clock := 0.0
var poll := 0.0
var room_poll := 0.0
var reverb: AudioEffectReverb
var played := 0
var retired := 0
var stolen := 0
var variants: Dictionary = {}
var owned_buses: Array[String] = []

func configure(head: Camera3D, collision_stage: Node3D = null, requested := "steam_audio", force_audio := false) -> void:
	clear()
	camera = head; stage = collision_stage
	enabled = force_audio or DisplayServer.get_name() != "headless"
	if not enabled: return
	setup_buses()
	# The HMD viewport is the sole 3D audio listener; spectator cameras must
	# never rotate or translate the listener heard inside the headset.
	if is_instance_valid(standard_listener): standard_listener.free()
	standard_listener = AudioListener3D.new()
	camera.add_child(standard_listener)
	camera.get_viewport().audio_listener_enable_3d = true
	standard_listener.make_current()
	if requested=="steam_audio" and ClassDB.class_exists("SteamAudioPlayer"):
		if not is_instance_valid(config):
			# Match the patched plugin DSP allocation to Godot's 512-frame mixer.
			ProjectSettings.set_setting("audio/driver/mix_rate",int(AudioServer.get_mix_rate()))
			ProjectSettings.set_setting("audio/driver/output_latency",roundi(512000.0/AudioServer.get_mix_rate()))
			config = ClassDB.instantiate("SteamAudioConfig")
			config.set("scene_type",0) # Portable CPU path, independent of Vulkan/XR runtime.
			config.set("global_log_level",2)
			config.set("max_ambisonics_order",1)
			config.set("max_reflection_sources",1); config.set("max_reflection_rays",32)
			config.set("reflection_threads",1); config.set("max_reflection_duration",0.1)
			steam_listener = ClassDB.instantiate("SteamAudioListener")
			steam_listener.set("reflection_rays",32); steam_listener.set("reflection_bounces",1)
			steam_listener.set("reflection_duration",0.1)
			add_child(steam_listener); add_child(config)
		backend = "steam_audio"
	else:
		backend = "stereo"
	sync_listener()
	print("SWG weapon audio: ",backend," · HMD listener · ",MAX_VOICES," voice limit")

func setup_buses() -> void:
	for name in ["SWG Spatial","SWG Effects"]:
		if AudioServer.get_bus_index(name)>=0: continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,name)
		owned_buses.append(name)
	var spatial := AudioServer.get_bus_index("SWG Spatial")
	if reverb == null:
		reverb = AudioEffectReverb.new()
		reverb.predelay_msec=18; reverb.wet=0.0; reverb.dry=1.0; reverb.room_size=0.55; reverb.damping=0.7
		AudioServer.add_bus_effect(spatial,reverb)
	var effects := AudioServer.get_bus_index("SWG Effects")
	AudioServer.set_bus_send(effects,"SWG Spatial")
	if AudioServer.get_bus_effect_count(effects)==0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db=-3; limiter.pre_gain_db=0; limiter.release=0.06
		AudioServer.add_bus_effect(effects,limiter)

func sync_listener() -> void:
	if enabled and is_instance_valid(camera) and is_instance_valid(steam_listener):
		steam_listener.global_transform = camera.global_transform

func create_player(reference_distance: float, maximum_distance: float) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = ClassDB.instantiate("SteamAudioPlayer") if backend=="steam_audio" else AudioStreamPlayer3D.new()
	player.bus="SWG Effects"
	player.unit_size=maxf(0.01,reference_distance); player.max_distance=maxf(player.unit_size,maximum_distance)
	player.max_db=0; player.pitch_scale=1.0
	# Preserve original pitch, including while moving the physical controller.
	player.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.attenuation_filter_db=-18; player.attenuation_filter_cutoff_hz=18000
	if backend=="steam_audio":
		player.set("ambisonics",true); player.set("ambisonics_order",1)
		player.set("distance_attenuation",true); player.set("min_attenuation_distance",player.unit_size)
		player.set("occlusion",false); player.set("reflection",false)
		player.panning_strength=0.0
		player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
	else:
		player.panning_strength=1.0
		player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return player

func play_original(assets: RefCounted, sound: String, position: Vector3, priority := 1) -> AudioStreamPlayer3D:
	if not enabled or not is_instance_valid(camera): return null
	var definition: Dictionary = assets.catalog.sounds.get(sound,{})
	if definition.is_empty() or definition.samples.is_empty(): return null
	if camera.global_position.distance_to(position)>float(definition.max_distance): return null
	# Walk the original variant bank without pitch/timbre alterations or repeat RNG.
	var index: int = int(variants.get(sound,0)) % definition.samples.size()
	variants[sound]=index+1
	var source: AudioStream = assets.sound(definition.samples[index])
	if source==null: return null
	if active.size()>=MAX_VOICES:
		var victim: AudioStreamPlayer3D = active[0]
		for candidate in active:
			if int(candidate.get_meta("priority",1))<int(victim.get_meta("priority",1)): victim=candidate
		if int(victim.get_meta("priority",1))>priority: return null
		retire(victim); stolen+=1
	var player := create_player(float(definition.min_distance),float(definition.max_distance))
	player.stream=source
	var dry_db := linear_to_db(maxf(0.00001,float(definition.volume)))
	player.set_meta("dry_db",dry_db); player.set_meta("priority",priority)
	player.set_meta("expires",clock+source.get_length()+0.15)
	player.set_meta("source_sound",sound); player.set_meta("source_sample",definition.samples[index])
	add_child(player); player.global_position=position
	active.append(player)
	update_source(player)
	player.finished.connect(retire.bind(player))
	player.play(); played+=1
	return player

func blocked(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to)<0.04: return false
	if is_instance_valid(stage):
		var cell := str(stage.classify_world(from).get("cell_id",""))
		var result: Dictionary = stage.combat_collision.trace_segment(from,to,cell,7)
		return result.get("complete",false) and result.get("hit",false)
	var query := PhysicsRayQueryParameters3D.create(from,to,7)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func update_source(player: AudioStreamPlayer3D) -> void:
	var obstruction := blocked(camera.global_position,player.global_position)
	player.volume_db=float(player.get_meta("dry_db",0))-(10.0 if obstruction else 0.0)
	player.attenuation_filter_cutoff_hz=1800 if obstruction else 18000
	player.set_meta("occluded",obstruction)

func _process(_delta: float) -> void: sync_listener()
func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(camera): return
	clock+=delta; poll+=delta; room_poll+=delta
	if poll>=0.1:
		poll=0
		for player in active.duplicate():
			if clock>=float(player.get_meta("expires",INF)): retire(player)
			else: update_source(player)
	if room_poll>=0.5 and reverb!=null:
		room_poll=0
		var count := 0
		for direction in [Vector3.UP,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
			if blocked(camera.global_position,camera.global_position+direction*12): count+=1
		reverb.wet=lerpf(reverb.wet,count*0.025,0.35)

func retire(player: AudioStreamPlayer3D) -> void:
	active.erase(player)
	if is_instance_valid(player) and not player.is_queued_for_deletion():
		player.stop(); player.queue_free(); retired+=1

func clear() -> void:
	for player in active.duplicate(): retire(player)
	active.clear()

func _exit_tree() -> void:
	clear()
	if is_instance_valid(standard_listener): standard_listener.queue_free()
	for name in owned_buses:
		var index := AudioServer.get_bus_index(name)
		if index>=0: AudioServer.remove_bus(index)
