extends ColorRect
## Login/roster presentation only; neither tracking nor world audio is driven here.
const Cache=preload("res://audio/stream_cache.gd")
var host:Node
var audio:AudioStreamPlayer
var cache:=Cache.new()
var catalog:Dictionary={}
var directory:=""
var active:=false
var began:=false
var fade:Tween
var error:=""
var view:Camera3D
var saved_environment:Environment
var sky_environment:Environment
func _ready()->void:
	name="LoginStarfield";mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader:=ShaderMaterial.new();shader.shader=preload("res://shaders/login_starfield.gdshader");material=shader
	audio=AudioStreamPlayer.new();audio.name="OriginalLoginMusic";audio.bus="SWG Music";audio.volume_db=-80;add_child(audio)
	sky_environment=Environment.new();sky_environment.background_mode=Environment.BG_SKY
	sky_environment.sky=Sky.new();var sky_material:=ShaderMaterial.new();sky_material.shader=preload("res://shaders/login_sky.gdshader");sky_environment.sky.sky_material=sky_material
	visible=false
func configure(value:Node,path:="res://../runtime/assets/login/catalog.json")->void:
	host=value;directory=path.get_base_dir()
	if FileAccess.file_exists(path):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:catalog=parsed
	if catalog.get("samples",[]).is_empty():error="Original login music assets are unavailable."
func set_frontend_active(value:bool)->void:
	if active==value:return
	active=value;visible=value
	update_view_environment()
	if fade!=null and fade.is_valid():fade.kill()
	if not value:
		if audio.playing:
			fade=create_tween();fade.tween_property(audio,"volume_db",-80.0,clampf(float(catalog.get("fade_out_seconds",.6)),0,15))
			fade.tween_callback(func():audio.stop();began=false)
		else:began=false
	elif audio.playing:
		fade=create_tween();fade.tween_property(audio,"volume_db",linear_to_db(maxf(float(catalog.get("volume",1)),.00001)),.6)
func update_view_environment()->void:
	if not active:
		if is_instance_valid(view) and view.environment==sky_environment:view.environment=saved_environment
		view=null;return
	if not is_instance_valid(host) or not is_instance_valid(host.get("player")):return
	var camera:Camera3D=host.player.get_camera()
	if camera==view:return
	if is_instance_valid(view) and view.environment==sky_environment:view.environment=saved_environment
	view=camera;saved_environment=view.environment;view.environment=sky_environment
func _process(_delta:float)->void:
	if is_instance_valid(host):
		var login:Variant=host.get("account_panel");var menu:Variant=host.get("menu");var creator:Variant=host.get("creator")
		var frontend:bool=(is_instance_valid(login) and login.visible) or (is_instance_valid(menu) and menu.visible)
		set_frontend_active(frontend and not bool(host.get("world_ready")) and not bool(host.get("loading_stage")) and not bool(host.get("session_leaving")) and not (is_instance_valid(creator) and creator.visible))
	cache.poll()
	if active:update_view_environment()
	if not active or began or catalog.get("samples",[]).is_empty():return
	var path:String=directory.path_join(str(catalog.samples[0]))
	var stream:AudioStream=cache.request(path,bool(catalog.get("loop",false)))
	if stream==null:
		if cache.is_failed(path,bool(catalog.get("loop",false))):error="Original login music could not be decoded."
		return
	audio.stream=stream;audio.volume_db=-80;audio.play();began=true
	fade=create_tween();fade.tween_property(audio,"volume_db",linear_to_db(maxf(float(catalog.get("volume",1)),.00001)),clampf(float(catalog.get("fade_in_seconds",.8)),0,15))
func _exit_tree()->void:
	active=false;update_view_environment()
	if fade!=null and fade.is_valid():fade.kill()
	if is_instance_valid(audio):audio.stop();audio.stream=null
	cache.shutdown()
