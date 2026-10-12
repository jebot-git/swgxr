extends Node
## Original environment, POB and CDF audio. No synthesized replacement tracks.
const Cache=preload("res://audio/stream_cache.gd")
var cache:=Cache.new()
var catalog:Dictionary={}
var directory:="res://../runtime/assets/space_audio"
var layers:Dictionary={}
var music:AudioStreamPlayer
var desired:Dictionary={}
var pending_music:=""
var zone:=""
var sector_music:=""
var combat_hold:=0.0
var combat_active:=false
var seen:Dictionary={}
var pending_effects:Array=[]
var engine_moving:=false
var engine_initialized:=false
var effects_played:=0
func _ready()->void:
	preload("res://audio/preferences.gd").ensure_buses()
	var path:=directory.path_join("catalog.json")
	if FileAccess.file_exists(path):
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary:catalog=value
	for key in ["interior","ambient","idle","run"]:
		var player:=AudioStreamPlayer.new();player.bus="SWG Ambience";add_child(player);layers[key]={"player":player,"sound":"","gain":0.0}
	music=AudioStreamPlayer.new();music.bus="SWG Music";add_child(music)
func stream(sound:String)->AudioStream:
	var source:Dictionary=catalog.get("sounds",{}).get(sound,{})
	if source.get("samples",[]).is_empty():return null
	return cache.request(ProjectSettings.globalize_path(directory.path_join(source.samples[0])),bool(source.get("loop",false)))
func request_music(sound:String)->void:
	pending_music=sound;music.stop()
func observe(ship:Dictionary,events:Array=[],ship_pose:=Transform3D.IDENTITY,world_frame:=Transform3D.IDENTITY)->void:
	var next:=str(ship.get("zone",""));var environment:Dictionary=catalog.get("sectors",{}).get(next,{})
	if next!=zone:
		zone=next;combat_hold=0;combat_active=false;sector_music=str(environment.get("music",""));request_music(sector_music)
	var definition:Dictionary=catalog.get("ships",{}).get(str(ship.get("template","")),{})
	var power:=clampf(float(ship.get("speed_mps",0))/maxf(1,float(ship.get("max_speed_mps",1))),0,1)
	var moving:=power>(.015 if engine_moving else .035)
	if engine_initialized and moving!=engine_moving:
		queue_effect(str(definition.get("accel" if moving else "decel","")),Vector3.ZERO,false)
	engine_moving=moving;engine_initialized=true
	desired={"interior":{"sound":definition.get("interior",""),"gain":1.0},"ambient":{"sound":environment.get("ambient",""),"gain":1.0},"idle":{"sound":definition.get("idle",""),"gain":1-power},"run":{"sound":definition.get("run",""),"gain":power}}
	var banks:Array=[]
	var bindings:Dictionary=catalog.get("engine_bindings",{}).get(str(ship.get("audio_chassis","")),{})
	for source:String in bindings.get(str(ship.get("engine_component","")),[]):
		var bank:Array=catalog.get("engines",{}).get(source,[])
		var band:=mini(bank.size()-1,floori(clampf(float(ship.get("engine_damage",0)),0,1)*bank.size()))
		for index in bank.size():
			if index==0 or index==band:banks.append({"engine":bank[index],"running":float(ship.get("max_speed_mps",0))>0,"power":power})
	for booster:Dictionary in definition.get("booster",[]):banks.append({"engine":booster,"running":ship.get("booster_active",false),"power":1.0 if ship.get("booster_active",false) else 0.0})
	for index in banks.size():
		var key:="engine_%d"%index
		if not layers.has(key):
			var player:=AudioStreamPlayer.new();player.bus="SWG Ambience";add_child(player);layers[key]={"player":player,"sound":"","gain":0.0,"level":0.0}
		var bank:Dictionary=banks[index];var engine:Dictionary=bank.engine
		desired[key]={"sound":engine.sound,"engine":engine,"power":bank.power,"running":not ship.get("destroyed",false) and bank.running}
	for event:Dictionary in events:
		var id:=str(event.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		if float(event.get("age_seconds",0))>1.0:continue
		var p:Array=event.get("position",[]);var own:Array=ship.get("position",[])
		if p.size()==3 and own.size()==3 and Vector3(p[0],p[1],p[2]).distance_to(Vector3(own[0],own[1],own[2]))<=1024:combat_hold=5.0
		if p.size()!=3:continue
		var sounds:Array=[]
		if event.get("kind","")=="projectile":sounds=catalog.get("projectiles",{}).get(str(event.get("projectile_type",-1)),[])
		elif event.get("kind","")=="hit":sounds=catalog.get("hits",{}).get(str(event.get("hit_type",-1)),[])
		for sound:String in sounds:queue_effect(sound,world_frame*ship_pose.affine_inverse()*Vector3(p[0],p[1],-p[2]),true)
	while seen.size()>256:seen.erase(seen.keys()[0])
func _process(delta:float)->void:
	cache.poll()
	for effect:Dictionary in pending_effects.duplicate():
		if Time.get_ticks_msec()>effect.expires:pending_effects.erase(effect);continue
		var audio:=stream(effect.sound)
		if audio==null:continue
		var mixer:=get_node_or_null("/root/SWGSpatialAudio")
		if mixer!=null and mixer.enabled:
			var point:Vector3=effect.position if effect.spatial else mixer.camera.global_position
			if mixer.play_stream(catalog.sounds[effect.sound],effect.sound,audio,point,2)!=null:effects_played+=1
		pending_effects.erase(effect)
	combat_hold=maxf(0,combat_hold-delta)
	var active:=combat_hold>0
	if active!=combat_active:
		combat_active=active
		var tracks:Array=catalog.get("combat",{}).get("enter" if active else "exit",[])
		if not tracks.is_empty():request_music(str(tracks[0]))
	if not pending_music.is_empty():
		var sound:=stream(pending_music)
		if sound!=null:
			music.stream=sound;music.volume_db=linear_to_db(maxf(.001,float(catalog.sounds[pending_music].get("volume",1))));music.play();pending_music=""
	for key:String in layers:
		var layer:Dictionary=layers[key];var target:Dictionary=desired.get(key,{})
		var name:=str(target.get("sound",""))
		if name!=str(layer.sound):layer.player.stop();layer.sound=name;layer.player.stream=null
		if not name.is_empty() and layer.player.stream==null:
			var audio:=stream(name)
			if audio!=null:layer.player.stream=audio;layer.player.play()
		if target.has("engine"):
			var engine:Dictionary=target.engine
			layer.level=move_toward(float(layer.level),float(target.power),delta*maxf(0.01,float(engine.rate_up if float(target.power)>float(layer.level) else engine.rate_down)))
			layer.gain=clampf(lerpf(float(engine.volume_min),float(engine.volume_max),float(layer.level)),0,1) if target.running else 0.0
			layer.player.pitch_scale=pow(2.0,lerpf(float(engine.pitch_min),float(engine.pitch_max),float(layer.level))/12.0)
		else:layer.gain=move_toward(float(layer.gain),float(target.get("gain",0)),delta*2)
		layer.player.volume_db=linear_to_db(maxf(.00001,float(layer.gain)*float(catalog.get("sounds",{}).get(name,{}).get("volume",1))))
func _exit_tree()->void:cache.shutdown()

func queue_effect(sound:String,position:Vector3,spatial:bool)->void:
	if not sound.is_empty() and pending_effects.size()<16:
		pending_effects.append({"sound":sound,"position":position,"spatial":spatial,"expires":Time.get_ticks_msec()+750})
