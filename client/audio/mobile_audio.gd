extends Node
## Bounded original moving-entity audio on the shared HMD spatial mixer.
const MAX_EMITTERS:=8
const MAX_CHANNELS:=16
const Cache=preload("res://audio/stream_cache.gd")
var mixer:Node3D
var directory:=ProjectSettings.globalize_path("res://../runtime/assets/mobile_audio")
var catalog:Dictionary={}
var cache:=Cache.new()
var channels:Dictionary={}
var clock:=0.0
var poll:=0.0
var variants:Dictionary={}
func configure(owner_mixer:Node3D)->void:
	mixer=owner_mixer
	var path:=directory.path_join("catalog.json")
	if FileAccess.file_exists(path):
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary:catalog=value
func binding(template:String)->Dictionary:
	return catalog.get("bindings",{}).get(catalog.get("templates",{}).get(template,""),{})
func vehicle_slots(definition:Dictionary,damage:float)->Dictionary:
	var slots:Dictionary={}
	for band:Dictionary in definition.get("bands",[]):
		if float(band.damage)>damage:break
		if not band.sounds.is_empty():slots=band.sounds[0]
	return slots
func wanted(emitter:Node3D)->Dictionary:
	var definition:=binding(emitter.source_template)
	if definition.is_empty():return {}
	var result:Dictionary={}
	if definition.kind=="vehicle":
		var slots:=vehicle_slots(definition,emitter.damage)
		var phase:="run" if emitter.moving else "idle"
		for key in [phase,"damage_"+phase]:
			var sound:=str(slots.get(key,""))
			if not sound.is_empty():result["engine" if key==phase else "damage"]={"sound":sound,"repeat":true}
	else:
		for i in range(definition.get("ambient",[]).size()):
			var source:String=definition.ambient[i]
			result["ambient"+str(i)]={"sound":source,"repeat":bool(catalog.get("sounds",{}).get(source,{}).get("repeat",false))}
		if emitter.moving and definition.get("events",{}).has("footstep"):
			result["movement"]={"sound":definition.events.footstep,"repeat":true}
	return result
func stop_channel(key:String)->void:
	var state:Dictionary=channels[key]
	if is_instance_valid(state.get("player")):mixer.retire(state.player)
	channels.erase(key)
func clear()->void:
	for key:String in channels.keys():stop_channel(key)
func tick(delta:float)->void:
	clock+=delta;cache.poll();poll+=delta
	# Position follows the rendered model each frame, not a stale network sample.
	for key:String in channels.keys():
		var channel:Dictionary=channels[key]
		if not is_instance_valid(channel.emitter) or not channel.emitter.audible():stop_channel(key);continue
		if is_instance_valid(channel.get("player")):channel.player.global_position=channel.emitter.global_position
	if poll<.1:return
	poll=0
	var nearby:Array=[]
	for emitter:Node3D in get_tree().get_nodes_in_group("swg_mobile_audio"):
		if not emitter.audible() or binding(emitter.source_template).is_empty():emitter.events.clear();continue
		var distance:float=mixer.camera.global_position.distance_to(emitter.global_position)
		if distance>96:emitter.events.clear();continue
		nearby.append({"emitter":emitter,"distance":distance})
	nearby.sort_custom(func(a,b):return a.distance<b.distance)
	var desired:Dictionary={}
	for i in range(mini(MAX_EMITTERS,nearby.size())):
		var emitter:Node3D=nearby[i].emitter
		var prefix:=str(emitter.get_instance_id())+":"
		var requests:=wanted(emitter)
		for slot:String in requests:
			var request:Dictionary=requests[slot]
			desired[prefix+slot]={"emitter":emitter,"sound":request.sound,"repeat":request.repeat}
		var definition:=binding(emitter.source_template)
		var slots:Dictionary=vehicle_slots(definition,emitter.damage) if definition.kind=="vehicle" else definition.get("events",{})
		for event:String in emitter.events:
			var sound:=str(slots.get(event,""))
			if not sound.is_empty():desired[prefix+"event"]={"emitter":emitter,"sound":sound,"repeat":false}
		emitter.events.clear()
	# Keep an accepted one-shot until it completes; continuous channels follow state.
	for key:String in channels.keys():
		if not desired.has(key) and key.ends_with(":event") and is_instance_valid(channels[key].emitter) and channels[key].emitter.audible():
			desired[key]=channels[key]
		elif not desired.has(key) or desired[key].sound!=channels[key].sound:stop_channel(key)
	for key:String in desired:
		var request:Dictionary=desired[key]
		var sound:Dictionary=catalog.get("sounds",{}).get(request.sound,{})
		if sound.is_empty() or sound.get("samples",[]).is_empty():continue
		if mixer.camera.global_position.distance_to(request.emitter.global_position)>float(sound.max_distance):
			if channels.has(key):stop_channel(key)
			continue
		if not channels.has(key):
			if channels.size()>=MAX_CHANNELS:continue
			channels[key]=request.duplicate();channels[key].due=clock+randf_range(sound.start_delay_seconds[0],sound.start_delay_seconds[1])
		var channel:Dictionary=channels[key]
		if is_instance_valid(channel.get("player")) or clock<float(channel.due):continue
		if channel.get("done",false):
			if key.ends_with(":event"):stop_channel(key)
			continue
		var index:int=int(variants.get(request.sound,0))%sound.samples.size()
		var looped:bool=sound.get("loop",false) and channel.repeat
		var stream:AudioStream=cache.request(directory.path_join(sound.samples[index]),looped)
		if stream==null:continue
		var player:AudioStreamPlayer3D=mixer.play_stream(sound,request.sound,stream,request.emitter.global_position,0,looped)
		if player==null:continue
		variants[request.sound]=index+1;channel.player=player
		channel.due=clock+stream.get_length()+randf_range(sound.delay_seconds[0],sound.delay_seconds[1])
		channel.done=not channel.repeat
func _exit_tree()->void:
	clear();cache.shutdown()
