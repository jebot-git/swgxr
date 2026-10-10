extends Node
## Original CuiSoundManager table, shared by desktop and XR panel controls.
var catalog:Dictionary={}
var cache:=preload("res://audio/stream_cache.gd").new()
var directory:="res://../runtime/assets/game_audio"
var pending:Array=[]
var players:Array[AudioStreamPlayer]=[]
var played:=0
var last_request:=0
func _ready()->void:
	var path:=directory.path_join("catalog.json")
	if FileAccess.file_exists(path):catalog=JSON.parse_string(FileAccess.get_file_as_string(path))
	get_tree().node_added.connect(bind_control)
func bind_control(node:Node)->void:
	if node is BaseButton:
		node.pressed.connect(func():
			if node.is_visible_in_tree() and not node.disabled:play("select"))
	elif node is ItemList:
		node.item_selected.connect(func(_index):
			if node.is_visible_in_tree():play("select_info"))
func play(event:String)->void:
	var now:=Time.get_ticks_msec()
	if now-last_request<60:return
	var sound:=str(catalog.get("ui",{}).get(event,""))
	if sound.is_empty():return
	last_request=now
	if pending.size()<4:pending.append({"sound":sound,"expires":now+500})
func _process(_delta:float)->void:
	cache.poll()
	for request:Dictionary in pending.duplicate():
		if Time.get_ticks_msec()>request.expires:pending.erase(request);continue
		var definition:Dictionary=catalog.get("sounds",{}).get(request.sound,{})
		var samples:Array=definition.get("samples",[])
		if samples.is_empty():pending.erase(request);continue
		var stream:AudioStream=cache.request(ProjectSettings.globalize_path(directory.path_join(samples[0])),false)
		if stream==null:continue
		while players.size()>=4:players.pop_front().queue_free()
		var player:=AudioStreamPlayer.new();add_child(player);players.append(player)
		player.stream=stream;player.volume_db=linear_to_db(maxf(.001,float(definition.get("volume",1))))
		player.set_meta("source_sound",request.sound)
		player.finished.connect(func():players.erase(player);player.queue_free())
		player.play();played+=1;pending.erase(request)
func _exit_tree()->void:cache.shutdown()
