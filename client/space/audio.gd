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
func observe(ship:Dictionary,events:Array=[])->void:
	var next:=str(ship.get("zone",""));var environment:Dictionary=catalog.get("sectors",{}).get(next,{})
	if next!=zone:
		zone=next;combat_hold=0;combat_active=false;sector_music=str(environment.get("music",""));request_music(sector_music)
	var definition:Dictionary=catalog.get("ships",{}).get(str(ship.get("template","")),{})
	var power:=clampf(float(ship.get("speed_mps",0))/maxf(1,float(ship.get("max_speed_mps",1))),0,1)
	desired={"interior":{"sound":definition.get("interior",""),"gain":1.0},"ambient":{"sound":environment.get("ambient",""),"gain":1.0},"idle":{"sound":definition.get("idle",""),"gain":1-power},"run":{"sound":definition.get("run",""),"gain":power}}
	for event:Dictionary in events:
		var id:=str(event.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		var p:Array=event.get("position",[]);var own:Array=ship.get("position",[])
		if p.size()==3 and own.size()==3 and Vector3(p[0],p[1],p[2]).distance_to(Vector3(own[0],own[1],own[2]))<=1024:combat_hold=5.0
	while seen.size()>256:seen.erase(seen.keys()[0])
func _process(delta:float)->void:
	cache.poll()
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
		layer.gain=move_toward(float(layer.gain),float(target.get("gain",0)),delta*2)
		layer.player.volume_db=linear_to_db(maxf(.00001,float(layer.gain)*float(catalog.get("sounds",{}).get(name,{}).get("volume",1))))
func _exit_tree()->void:cache.shutdown()
