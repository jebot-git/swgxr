extends Node3D
## Original asset-driven ambience; static vertex lighting, no Light3D nodes.
var manifest: Dictionary = {}
var game_audio:Dictionary={}
var game_audio_directory:=ProjectSettings.globalize_path("res://../runtime/assets/game_audio")
var last_native_music_state:Dictionary={}
var native_combat:=false
var event_music_active:=false
var water_audio:AudioStreamPlayer
var directory := ""
var phase := 0.25
var cycle_seconds := 7200.0
var family := "moseisley"
var active := false
var observer := Vector3.ZERO
var indoors := false
var terrain: Node3D
var stage: Node3D
var world: WorldEnvironment
var sky_material: ShaderMaterial
var family_names: Dictionary = {}
var audio_cache := preload("res://audio/stream_cache.gd").new()
var variants: Dictionary = {}
var interior_soundscape: Dictionary = {}
var interior_key := ""
var observer_cell: Dictionary = {}
var pending_music := ""
var music_tween: Tween
var ambient: Array[AudioStreamPlayer] = []
var music: Array[AudioStreamPlayer] = []
var emitters: Dictionary = {}
var elapsed := 0.0
var poll := 0.0
var music_index := 0
var next_music := 0.0
var sample_index := 0
var report := {"ready":false,"audio_sources":0,"active_emitters":0,"music_events":0,"dynamic_lights":0,"lighting":"original vertex colors + fixed vertex irradiance bake"}

func _ready() -> void:
	add_to_group("swg_audio_environment")
	world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/tatooine_sky.gdshader")
	sky.sky_material = sky_material
	world.environment.sky = sky
	world.environment.ambient_light_energy = 0.0
	add_child(world)
	# Loading another planet must not reset the menu's shared audio preferences.
	preload("res://audio/preferences.gd").new().load_preferences()
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.bus = "SWG Ambience"
		add_child(player)
		ambient.append(player)
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "SWG Music"
		add_child(player)
		music.append(player)
	water_audio=AudioStreamPlayer.new();water_audio.bus="SWG Ambience";add_child(water_audio)

func configure(path: String) -> bool:
	var cues_path:=game_audio_directory.path_join("catalog.json")
	if FileAccess.file_exists(cues_path):
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(cues_path))
		if value is Dictionary:game_audio=value
	if not FileAccess.file_exists(path):
		report["error"] = "Environment asset manifest is missing."
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("families"):
		report["error"]="Environment asset manifest is invalid."
		return false
	manifest = data
	directory = path.get_base_dir()
	cycle_seconds = maxf(60,float(data.get("cycle_seconds",7200)))
	phase = float(data.get("default_phase",0.25))
	family = str(data.get("default_family","moseisley"))
	sky_material.set_shader_parameter("second_sun",manifest.get("celestials",[]).any(func(row):return row.get("tag","")=="SSUN" and row.get("shader") is Dictionary))
	sky_material.set_shader_parameter("sun_enabled",manifest.get("celestials",[]).any(func(row):return row.get("tag","")=="SUN " and row.get("shader") is Dictionary))
	sky_material.set_shader_parameter("moon_enabled",manifest.get("celestials",[]).any(func(row):return row.get("tag","")=="MOON" and row.get("shader") is Dictionary))
	for celestial in manifest.get("celestials",[]):
		var tag: String = celestial.get("tag","")
		if tag not in ["SUN ","MOON"]:
			continue
		var source_shader:Variant=celestial.get("shader")
		var textures:Array=source_shader.get("textures",[]) if source_shader is Dictionary else []
		if not textures.is_empty():
			var image := Image.load_from_file(directory.path_join(textures[0].path))
			if image != null:
				image.generate_mipmaps()
				sky_material.set_shader_parameter("sun_texture" if tag == "SUN " else "moon_texture",ImageTexture.create_from_image(image))
	report.ready = true
	report.audio_sources = manifest.get("sounds",{}).size()
	report["source_failures"] = manifest.get("failures",[])
	set_phase(phase)
	return true

func bind_world(source_terrain: Node3D, source_stage: Node3D) -> void:
	terrain = source_terrain
	stage = source_stage
	family_names.clear()
	var source:Variant=source_terrain.get("source_manifest") if is_instance_valid(source_terrain) else null
	if source is Dictionary:
		for entry in source.get("environment_families",[]):family_names[int(entry.id)]=entry.name

func set_active(value: bool) -> void:
	active = value
	if active:
		refresh_region_and_emitters()
		refresh_water_audio()
		select_audio_context()
	else:
		pending_music = ""
		if music_tween!=null and music_tween.is_valid(): music_tween.kill()
		if is_instance_valid(water_audio):water_audio.stop()
		last_native_music_state={};native_combat=false;event_music_active=false
		for player in ambient + music:
			player.stop()
		for player in emitters.values():
			player.queue_free()
		emitters.clear()

func update_observer(position: Vector3) -> void:
	observer = position

func set_music_volume(value: float) -> void:
	preload("res://audio/preferences.gd").apply_gain("SWG Music",value,-6)

func set_ambient_volume(value: float) -> void:
	preload("res://audio/preferences.gd").apply_gain("SWG Ambience",value,-8)

func set_phase(value: float) -> void:
	phase = fposmod(value,1.0)
	var daylight := smoothstep(-0.12,0.16,sin(phase*TAU))
	var samples: Array = manifest.get("families",{}).get(family,{}).get("lighting_samples",[])
	if not samples.is_empty():
		var scaled := phase*samples.size()
		var index := int(scaled)%samples.size()
		var next := (index+1)%samples.size()
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[next]
		var fraction := scaled-floorf(scaled)
		var ambient_color := color(a.ambient).lerp(color(b.ambient),fraction)
		var sun_color := color(a.sun).lerp(color(b.sun),fraction)
		var tint := ambient_color*0.7 + sun_color*0.65*daylight
		# Baked materials keep readability at night, without any runtime light.
		tint.r = maxf(tint.r,0.12)
		tint.g = maxf(tint.g,0.15)
		tint.b = maxf(tint.b,0.22)
		tint.a = 1.0
		RenderingServer.global_shader_parameter_set("swg_environment_tint",tint)
		sky_material.set_shader_parameter("top_color",color(a.sky_top).lerp(color(b.sky_top),fraction))
		sky_material.set_shader_parameter("horizon_color",color(a.sky_horizon).lerp(color(b.sky_horizon),fraction))
	RenderingServer.global_shader_parameter_set("swg_daylight",daylight)
	RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color(0.95,0.92,0.86))
	sky_material.set_shader_parameter("phase",phase)
	sky_material.set_shader_parameter("daylight",daylight)
	report["phase"] = phase
	report["daylight"] = daylight
	report["family"] = family

func color(value: Array) -> Color:
	return Color(float(value[0]),float(value[1]),float(value[2]))

func definition(sound: String) -> Dictionary:
	return manifest.get("sounds",{}).get(sound,game_audio.get("sounds",{}).get(sound,{}))

func stream(sound: String) -> AudioStream:
	var source := definition(sound)
	var samples: Array = source.get("samples",[])
	if samples.is_empty(): return null
	var variant := int(variants.get(sound,0))%samples.size()
	var path: String = samples[variant]
	var audio: AudioStream = audio_cache.request((game_audio_directory if game_audio.get("sounds",{}).has(sound) else directory).path_join(path),bool(source.get("loop",false)))
	if audio!=null: variants[sound] = variant+1
	return audio

func prefetch_sound(sound: String) -> void:
	var source := definition(sound)
	for path in source.get("samples",[]):
		audio_cache.request((game_audio_directory if game_audio.get("sounds",{}).has(sound) else directory).path_join(path),bool(source.get("loop",false)))

func source_volume(sound: String) -> float:
	return float(definition(sound).get("volume",0.5))

func delay(sound: String) -> float:
	var range_value: Array = definition(sound).get("delay_seconds",[5,15])
	return maxf(0.5,(float(range_value[0])+float(range_value[-1]))*0.5)

func select_family(value: String, force := false) -> void:
	if not manifest.get("families",{}).has(value) or (value==family and not force): return
	family = value
	if not indoors: select_audio_context()

func select_audio_context() -> void:
	var info: Dictionary = interior_soundscape if indoors else manifest.families.get(family,{})
	for i in range(4):
		var sound: String = info.get(["day_ambient","night_ambient","day_ambient_secondary","night_ambient_secondary"][i],"")
		ambient[i].stop()
		ambient[i].stream = null
		ambient[i].set_meta("sound",sound)
		ambient[i].set_meta("next",elapsed)
		prefetch_sound(sound)
	report["selected_ambient"] = ambient.map(func(player): return str(player.get_meta("sound","")))
	if event_music_active:return
	pending_music = ""
	if music_tween!=null and music_tween.is_valid(): music_tween.kill()
	for player in music: player.stop()
	next_music = elapsed+90.0
	report["music"] = ""
	report["selected_ambient"] = ambient.map(func(player): return str(player.get_meta("sound","")))
	play_music(str(info.get("first_music","")))

func resolved_observer_cell() -> Dictionary:
	if not is_instance_valid(stage): return {}
	# Portal membership is authoritative during stairs/jumps and room transitions.
	if is_instance_valid(stage.observer) and observer.distance_squared_to(stage.observer.global_position)<0.25:
		return stage.current_cell.duplicate()
	return stage.classify_world(observer)

func select_interior(cell: Dictionary) -> void:
	var previous_indoors := indoors
	var previous_soundscape := str(report.get("selected_soundscape",""))
	observer_cell = cell
	indoors = not str(cell.get("cell_id","")).is_empty()
	var source: Dictionary = stage.definitions.get(str(cell.get("cell_id","")),{}) if is_instance_valid(stage) else {}
	var pob := str(source.get("source_pob","")).get_file().get_basename()
	var room := str(source.get("name",cell.get("name","")))
	var key := pob+":"+room if indoors else ""
	report["interior_cell"] = str(cell.get("cell_id",""))
	if key==interior_key: return
	interior_key = key
	var soundscapes: Dictionary = manifest.get("interior_soundscapes",{})
	var selected := key if soundscapes.has(key) else (pob+":default" if soundscapes.has(pob+":default") else "default:default")
	interior_soundscape = soundscapes.get(selected,{}) if indoors else {}
	report["selected_soundscape"] = selected if indoors else ""
	if previous_indoors!=indoors or previous_soundscape!=str(report.selected_soundscape):
		select_audio_context()
	report["interior_key"] = key
	report["interior_soundscape"] = interior_soundscape

func play_music(sound: String) -> void:
	var audio := stream(sound)
	if not active: return
	if audio==null:
		var source := definition(sound)
		var samples: Array = source.get("samples",[])
		var can_load := false
		for path in samples:
			if not audio_cache.is_failed((game_audio_directory if game_audio.get("sounds",{}).has(sound) else directory).path_join(path),bool(source.get("loop",false))): can_load = true
		pending_music = sound if can_load else ""
		next_music = elapsed+90.0
		return
	pending_music = ""
	var previous := music[music_index]
	music_index = 1-music_index
	var player := music[music_index]
	player.stop()
	player.stream = audio
	player.volume_db = -60
	player.play()
	if music_tween!=null and music_tween.is_valid(): music_tween.kill()
	music_tween = create_tween().set_parallel(true)
	music_tween.tween_property(previous,"volume_db",-60.0,2.0)
	music_tween.tween_property(player,"volume_db",linear_to_db(maxf(source_volume(sound),0.001)),2.0)
	next_music = elapsed+audio.get_length()+90.0
	report.music_events += 1
	report["music"] = sound

func _process(delta: float) -> void:
	audio_cache.poll()
	report["audio_loading"] = audio_cache.statistics()
	report["pending_music"] = pending_music
	if not active or manifest.is_empty():
		return
	elapsed += delta
	var previous_phase := phase
	set_phase(phase+delta/cycle_seconds)
	if not pending_music.is_empty(): play_music(pending_music)
	if not native_combat and not event_music_active and not indoors and phase < previous_phase:
		play_music(manifest.families[family].get("sunrise_music",""))
	elif not native_combat and not event_music_active and not indoors and previous_phase < 0.5 and phase >= 0.5:
		play_music(manifest.families[family].get("sunset_music",""))
	elif elapsed >= next_music:
		event_music_active=false
		play_music((interior_soundscape if indoors else manifest.families[family]).get("first_music",""))
	var daylight: float = report.get("daylight",1.0)
	for i in range(4):
		var player := ambient[i]
		var sound: String = player.get_meta("sound","")
		var weight := daylight if i%2==0 else 1.0-daylight
		if sound==str(ambient[i ^ 1].get_meta("sound","")):
			weight = 1.0 if i%2==0 else 0.0
		player.volume_db = linear_to_db(maxf(0.00001,source_volume(sound)*weight))
		if player.stream==null: player.stream = stream(sound)
		if player.stream != null and not player.playing and weight > 0.01 and elapsed >= float(player.get_meta("next",0)):
			player.play()
			player.set_meta("next",elapsed+player.stream.get_length()+delay(sound))
	poll += delta
	if poll >= 0.5:
		poll = 0.0
		refresh_region_and_emitters()
		refresh_water_audio()

func refresh_region_and_emitters() -> void:
	var cell := resolved_observer_cell()
	select_interior(cell)
	if is_instance_valid(terrain) and terrain.configured:
		var source: Vector2 = terrain.source_position(observer)
		var sample: Dictionary = terrain.evaluator.sample(source.x,source.y)
		select_family(str(family_names.get(int(sample.get("environment",1)),"global")))
	var nearby: Array = []
	for entry in manifest.get("emitters",[]):
		var location := Vector3(float(entry.position[0]),float(entry.position[1]),float(entry.position[2]))
		var sound: String = entry.sound
		var distance := location.distance_to(observer)
		var emitter_cell := str(entry.get("cell_id",""))
		var spatial := bool(definition(sound).get("spatial",true))
		# Source SD2D ASND is not a positional point emitter. Restrict interior
		# playback to its building, so the band remains audible across alcoves.
		# Exact original portal acoustics are not reconstructed here.
		if (spatial or emitter_cell.is_empty()) and distance>float(definition(sound).get("max_distance",64)): continue
		if not emitter_cell.is_empty() and emitter_cell.get_slice(":",0) != str(cell.get("building_object_id","")):
			continue
		nearby.append({"entry":entry,"distance":distance,"position":location})
	nearby.sort_custom(func(a,b):return a.distance<b.distance)
	var wanted := {}
	var nonspatial_sounds := {}
	for player in ambient:
		var sound := str(player.get_meta("sound",""))
		if not sound.is_empty(): nonspatial_sounds[sound] = true
	for candidate in nearby:
		if wanted.size()>=12: break
		var entry: Dictionary = candidate.entry
		var sound_key := str(entry.sound)
		if not bool(definition(sound_key).get("spatial",true)):
			if nonspatial_sounds.has(sound_key): continue
			nonspatial_sounds[sound_key] = true
		var key := str(entry.object_id)+":"+sound_key
		wanted[key] = true
		if not emitters.has(key):
			var sound: String = entry.sound
			var spatial := bool(definition(sound).get("spatial",true))
			var player = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
			var samples: Array = definition(sound).get("sample_sources",[])
			player.bus = "SWG Music" if samples.any(func(path): return str(path).begins_with("music/")) else "SWG Ambience"
			if spatial:
				player.position = candidate.position
				player.unit_size = float(definition(sound).get("min_distance",8))
				player.max_distance = float(definition(sound).get("max_distance",64))
			player.volume_db = linear_to_db(maxf(source_volume(sound),0.001))
			player.set_meta("sound",sound)
			player.set_meta("next",elapsed)
			player.set_meta("started",false)
			add_child(player)
			emitters[key] = player
		var player = emitters[key]
		if not player.playing and elapsed >= float(player.get_meta("next",0)):
			var sound: String = player.get_meta("sound")
			if player.get_meta("started",false) and not bool(definition(sound).get("repeat",false)): continue
			player.stream = stream(sound)
			if player.stream != null:
				player.play()
				player.set_meta("started",true)
				player.set_meta("next",elapsed+player.stream.get_length()+delay(sound))
	for key in emitters.keys():
		if not wanted.has(key):
			emitters[key].stop()
			emitters[key].queue_free()
			emitters.erase(key)
	report.active_emitters = emitters.size()
	report["indoors"] = indoors
	report["emitter_sounds"] = emitters.values().map(func(player): return str(player.get_meta("sound","")))
	report["interior_audio_scope"] = "SD2D ASND: owning building with duplicate cues suppressed; original portal propagation not reproduced"

func _exit_tree() -> void:
	set_active(false)
	audio_cache.shutdown()

func observe_native_music(value:Dictionary)->void:
	if value.get("space_active",false):return
	var current:Dictionary={"dead":bool(value.get("dead",false)),"incapacitated":bool(value.get("incapacitated",false)),"combat":bool(value.get("in_combat",false))}
	if last_native_music_state.is_empty():last_native_music_state=current;native_combat=current.combat;return
	var cue:=""
	if current.incapacitated and not last_native_music_state.incapacitated:cue="incapacitated"
	elif current.dead and not last_native_music_state.dead:cue="dead"
	elif not current.dead and not current.incapacitated and current.combat!=last_native_music_state.combat:cue="enter" if current.combat else "exit"
	last_native_music_state=current;native_combat=current.combat
	var choices:Array=game_audio.get("cues",{}).get(cue,[])
	if choices.is_empty() or not active:return
	event_music_active=true
	play_music(str(choices[randi()%choices.size()]))

func refresh_water_audio()->void:
	var choices:Array=game_audio.get("cues",{}).get("water",[])
	if indoors or not is_instance_valid(terrain) or not terrain.configured or choices.is_empty():
		water_audio.stop();return
	var point:Vector2=terrain.source_position(observer)
	var chunk:=maxf(1,float(terrain.source_manifest.get("source_chunk_size",8)))
	var center:=Vector2(floorf(point.x/chunk)*chunk,floorf(point.y/chunk)*chunk)
	var wet:=0
	# Original GameMusicManager samples a 5x5 terrain-chunk neighborhood and
	# saturates at half the chunks. Use original chunk width, not render LOD.
	for x in range(-2,3):
		for z in range(-2,3):
			var sample:Dictionary=terrain.evaluator.sample(center.x+x*chunk,center.y+z*chunk)
			if sample.get("water_enabled",false) and float(sample.get("water_height",0))>float(sample.get("height",0)):wet+=1
	var volume:=clampf(wet/12.0,0,1)
	if volume==0:water_audio.stop();return
	var sound:=str(choices[0])
	water_audio.volume_db=linear_to_db(maxf(.00001,volume*source_volume(sound)))
	if not water_audio.playing:
		water_audio.stream=stream(sound)
		if water_audio.stream!=null:water_audio.play()

func footstep_surface(position:Vector3)->String:
	# Original interior table overrides terrain; water overrides the ground family.
	if is_instance_valid(stage):
		var cell:Dictionary=stage.classify_world(position)
		if not str(cell.get("cell_id","")).is_empty():
			var source:Dictionary=stage.definitions.get(str(cell.cell_id),{})
			var pob:=str(source.get("source_pob","")).get_file().get_basename()
			var room:=str(source.get("name",cell.get("name","")))
			var rooms:Dictionary=manifest.get("interior_soundscapes",{})
			var info:Dictionary=rooms.get(pob+":"+room,rooms.get(pob+":default",rooms.get("default:default",{})))
			return str(info.get("source_values",{}).get("Surface Type",""))
	if not is_instance_valid(terrain) or not terrain.configured:return ""
	var point:Vector2=terrain.source_position(position)
	var sample:Dictionary=terrain.evaluator.sample(point.x,point.y)
	if sample.get("water_enabled",false) and float(sample.water_height)>position.y+terrain.origin.y:return "surf"
	var ids:PackedFloat32Array=sample.get("shader_ids",PackedFloat32Array())
	var weights:PackedFloat32Array=sample.get("shader_weights",PackedFloat32Array())
	var best:=-1;var weight:=-1.0
	for i in range(mini(ids.size(),weights.size())):
		if weights[i]>weight:best=int(ids[i]);weight=weights[i]
	for family_info:Dictionary in terrain.source_manifest.get("shader_families",[]):
		if int(family_info.id)==best:return str(family_info.get("file","")).get_file().get_basename()
	return ""
