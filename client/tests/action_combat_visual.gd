extends SceneTree
## Explicit local desktop inspection of the production client and native fixture.
## Launch with Forward+ Vulkan and --xr-mode off. Never launches an XR session.
var app:Node
var output:=""
var capturing:=false
var next_capture:=0
var encounter:Dictionary={}
var started:=false
var recording:=false
var recording_started:=0.0
var recording_seconds:=35.0
var video_frames:Array=[]
var audio_record:AudioEffectRecord
var caption:Label
var remote_test:=false
var ai_enabled:=false
var ai_home:=Vector3.ZERO
var ai_destination:=Vector3.ZERO
var ai_attack:=""
var ai_react_at:=0.0
var ai_slow_until:=0.0
var ai_next_shot:=0.0
var ai_slow_elapsed:=0.0
var ai_phase:="stationary baseline"
var ai_shots:=0
func _initialize()->void:call_deferred("run")
func run()->void:
	var options:Dictionary={}
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.trim_prefix("--").split("=",true,1)
		options[pair[0]]=pair[1] if pair.size()>1 else true
	output=str(options.get("combat-view-output",""))
	recording_seconds=float(options.get("record-seconds",35))
	ai_enabled=options.has("combat-ai")
	var fixture:Dictionary={"account":"rangetest1a142","name":"Varek Solun","id":"281474993659303"}
	var backend:="http://127.0.0.1:18081"
	if options.has("combat-fixture"):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(str(options["combat-fixture"])))
		if not data is Dictionary or not data.get("created_for_remote_combat",false) or not data.get("prepared",false) or not str(data.get("account","")).begins_with("actiontest"):
			push_error("Dedicated prepared remote combat fixture required");quit(2);return
		fixture=data;backend="http://127.0.0.1:18083";remote_test=true
	if not options.has("desktop") or options.get("backend")!=backend or options.get("account")!=fixture.account or options.get("enter-character")!=fixture.name or not output.is_absolute_path() or DisplayServer.get_name()=="headless":
		push_error("Local fixture, desktop Vulkan and absolute combat-view-output required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60
	app=load("res://scripts/main.gd").new();root.add_child(app);current_scene=app
	while not app.world_ready:await process_frame
	while not is_instance_valid(app.multiplayer_sync) or app.multiplayer_sync.owner_session.is_empty():await process_frame
	if app.datapad_character_id!=str(fixture.id):push_error("Unexpected fixture identity");quit(2);return
	app.player.testing=ai_enabled or not remote_test
	app.player.test_input=Vector2.ZERO
	app.player.camera_pitch=-0.22
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var overlay:=CanvasLayer.new();root.add_child(overlay);caption=Label.new();overlay.add_child(caption);caption.position=Vector2(20,52);caption.add_theme_color_override("font_color",Color.WHITE);caption.add_theme_color_override("font_shadow_color",Color.BLACK);caption.add_theme_constant_override("shadow_offset_x",2);caption.add_theme_constant_override("shadow_offset_y",2)
	await create_timer(3).timeout
	var body:Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"session_id":app.multiplayer_sync.owner_session,"zone":"tatooine","action_combat":{"action":"start"}}
	encounter=await app.api(HTTPClient.METHOD_POST,"/combat/session/action_combat",body)
	started=bool(encounter.get("mutation",{}).get("success",false))
	if started:
		ai_home=app.source_position_at(app.player.global_position);ai_destination=ai_home
		if ai_enabled:
			Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			app.player.third_person=true
			if is_instance_valid(app.combat_rig) and not app.combat_rig.weapons.is_empty():app.combat_rig.draw(0)
		DirAccess.make_dir_recursive_absolute(output+"/frames")
		audio_record=AudioEffectRecord.new();AudioServer.add_bus_effect(0,audio_record);audio_record.set_recording_active(true)
		recording_started=Time.get_ticks_usec()/1000000.0;recording=true
	print("COMBAT_VISUAL_READY "+JSON.stringify(encounter))
func _process(_delta:float)->bool:
	if recording and ai_enabled:drive_ai(_delta)
	if not is_instance_valid(app) or output.is_empty() or capturing or Time.get_ticks_msec()<next_capture:return false
	capture()
	return false
func drive_ai(delta:float)->void:
	var stamp:=Time.get_ticks_usec()/1000000.0
	var combat:Variant=app.multiplayer_sync.action_combat
	if not is_instance_valid(combat):return
	var feet:Vector3=app.source_position_at(app.player.global_position)
	# Six-second stationary baseline, then real collision/locomotion with a
	# 250 ms reaction delay, dodging before slowing for ordinary client shots.
	if stamp-recording_started<6:return
	var threat:Dictionary={};var earliest:=INF
	for row:Dictionary in combat.timeline.attacks.values():
		var event:Dictionary=row.event
		if event.role=="support" or event.phase in ["cancelled","recovery"] or combat.timeline.server_time(row,stamp)>float(event.end_at):continue
		if float(event.active_at)<earliest:threat=event;earliest=float(event.active_at)
	if not threat.is_empty():
		var id:String=combat.timeline.key(threat)
		if ai_attack!=id:
			ai_attack=id;ai_react_at=stamp+.25;ai_slow_until=0;ai_slow_elapsed=0
			var aim:=Vector3(threat.direction[0],0,threat.direction[2]);var side:=Vector3(aim.z,0,-aim.x)
			var origin:=Vector3(threat.origin[0],feet.y,threat.origin[2])
			if (feet-origin).dot(side)<0:side=-side
			var move:=side if threat.role=="ranged" else (side+(feet-origin).normalized()).normalized()
			ai_destination=feet+move*2.5
			if ai_destination.distance_to(ai_home)>9:ai_destination=feet-move*2.5
		if threat.get("aim_locked",false) and not combat.timeline.contact(threat,feet) and ai_slow_until==0 and stamp>=ai_react_at:
			ai_slow_until=stamp+.55;ai_slow_elapsed=0
	var slow:=stamp<ai_slow_until
	ai_phase="slow and shoot" if slow else "dodge" if stamp>=ai_react_at else "reaction delay"
	var direction:Vector3=ai_destination-feet;direction.y=0
	var speed:=.6 if slow else 3.5
	if stamp<ai_react_at or direction.length()<.15:speed=0
	var world_direction:Vector3=app.stage.global_basis*Vector3(direction.x,0,-direction.z).normalized()
	# Aim the real desktop camera/weapon at an original mob, with no forged
	# impact reports. Ordinary projectile collision and RPG resolution apply.
	for mob:Dictionary in encounter.get("mutation",{}).get("mobs",[]):
		if mob.role!="melee" or not app.multiplayer_sync.entities.actors.has(str(mob.id)):continue
		var actor:Node3D=app.multiplayer_sync.entities.actors[str(mob.id)]
		var target:Vector3=actor.global_position+Vector3.UP*.4
		var aim:Vector3=target-app.player.get_camera().global_position
		app.player.global_rotation.y=atan2(-aim.x,-aim.z)
		app.player.camera_pitch=atan2(aim.y,Vector2(aim.x,aim.z).length())
		break
	var local_direction:Vector3=app.player.global_basis.inverse()*world_direction
	var profile:Dictionary=app.player.locomotion_profile
	var maximum:=float(profile.get("run_speed",5.2))*float(profile.get("speed_multiplier_base",1))*float(profile.get("speed_multiplier_mod",1))
	app.player.test_input=Vector2(local_direction.x,local_direction.z)*clampf(speed/maxf(maximum,.1),0,1)
	if slow and Vector2(app.player.velocity.x,app.player.velocity.z).length()<1:ai_slow_elapsed+=delta
	else:ai_slow_elapsed=0
	var press:=slow and ai_slow_elapsed>=.15 and stamp>=ai_next_shot
	if press:
		ai_next_shot=stamp+float(app.gameplay_combat.weapon.get("fire_interval_seconds",3.5));ai_shots+=1
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=press
	Input.parse_input_event(mouse)
func capture()->void:
	capturing=true
	await RenderingServer.frame_post_draw
	var stamp:=Time.get_ticks_usec()/1000000.0
	var frame:=root.get_texture().get_image()
	if frame!=null and not frame.is_empty():
		frame.save_jpg(output+"/frame-next.jpg",0.85)
		DirAccess.rename_absolute(output+"/frame-next.jpg",output+"/frame.jpg")
		if recording:
			var name:="frames/%05d.jpg"%video_frames.size();frame.save_jpg(output+"/"+name,.92)
			var poses:Array=[]
			for actor in app.multiplayer_sync.entities.actors.values():
				if not actor.action_pose_status.is_empty():
					var forward:Vector3=-actor.global_basis.z
					poses.append({"actor":str(actor.record.id),"pose":actor.action_pose_status.duplicate(true),"weapon_visible":actor.report.get("action_weapon_visible",false),"world_forward":[forward.x,forward.y,forward.z]})
			var attacks:Array=[]
			var combat:Variant=app.multiplayer_sync.action_combat
			if is_instance_valid(combat):
				for row:Dictionary in combat.timeline.attacks.values():attacks.append({"event":row.event.duplicate(true),"estimated_server_time":combat.timeline.server_time(row,stamp),"covered":row.covered})
			var feet:Vector3=app.source_position_at(app.player.global_position)
			video_frames.append({"file":name,"seconds":stamp-recording_started,"poses":poses,"attacks":attacks,"player_source_position":[feet.x,feet.y,feet.z],"sync_request_ms":app.multiplayer_sync.request_ms,"ai_phase":ai_phase if ai_enabled else "manual","shot_trigger_attempts":ai_shots})
			caption.text=("Remote CoreCU" if remote_test else "Local CoreCU")+" · %.1f s\nSlow aim correction · Final lock 300 ms before delivery"%(stamp-recording_started)
			if ai_enabled:caption.text+="\nAI: "+ai_phase
			if stamp-recording_started>=recording_seconds:finish_recording()
	var status:Dictionary={"at":Time.get_unix_time_from_system(),"world_ready":app.world_ready,"encounter_started":started,"renderer":RenderingServer.get_current_rendering_method(),"headset_tested":false}
	status["remote_server"]=remote_test
	if is_instance_valid(app.multiplayer_sync):
		status["sync_request_ms"]=app.multiplayer_sync.request_ms
		var combat:Variant=app.multiplayer_sync.action_combat
		if is_instance_valid(combat):status["combat"]={"accepted":combat.confirmed,"rejected":combat.rejected,"aim_updates":combat.timeline.aim_updates,"aim_locks":combat.timeline.aim_locks,"late_locks":combat.timeline.late_locks}
	if is_instance_valid(app.gameplay_combat):status["player_shots"]={"launched":app.gameplay_combat.serial,"confirmed_contacts":app.gameplay_combat.confirmed_contacts,"rejected":app.gameplay_combat.rejected_shots}
	if is_instance_valid(app.player):status["position"]=str(app.source_position_at(app.player.global_position))
	var file:=FileAccess.open(output+"/status.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(status))
	next_capture=Time.get_ticks_msec()+(50 if recording else 500);capturing=false
func finish_recording()->void:
	recording=false;audio_record.set_recording_active(false)
	caption.text="Recording saved · Manual desktop controls restored"
	if ai_enabled:
		app.player.test_input=Vector2.ZERO;app.player.testing=false
		var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=false;Input.parse_input_event(mouse)
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var recording_audio:=audio_record.get_recording()
	if recording_audio!=null:recording_audio.save_to_wav(output+"/combat-audio.wav")
	for index in range(AudioServer.get_bus_effect_count(0)-1,-1,-1):
		if AudioServer.get_bus_effect(0,index)==audio_record:AudioServer.remove_bus_effect(0,index)
	var file:=FileAccess.open(output+"/video-frames.json",FileAccess.WRITE);file.store_string(JSON.stringify({"frames":video_frames,"duration":video_frames[-1].seconds,"headset_tested":false,"renderer":"forward_plus","server_mocked":false,"remote_server":remote_test}))
	print("COMBAT_VIDEO_CAPTURED "+str(video_frames.size())+" frames")
	var body:Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"session_id":app.multiplayer_sync.owner_session,"zone":"tatooine","action_combat":{"action":"status"}}
	var reply:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/action_combat",body)
	var result:=FileAccess.open(output+"/native-results.json",FileAccess.WRITE)
	result.store_string(JSON.stringify({"native":reply.get("mutation",{}),"ai_trigger_attempts":ai_shots,"remote_server":remote_test,"headset_tested":false,"player_shots":{"launched":app.gameplay_combat.serial,"confirmed_contacts":app.gameplay_combat.confirmed_contacts,"rejected":app.gameplay_combat.rejected_shots}},"  "))
	var trace:=FileAccess.open(output+"/request-timings.json",FileAccess.WRITE)
	trace.store_string(JSON.stringify({"native_api":app.native_api_observations,"contact_receipts":app.multiplayer_sync.action_combat.observations,"last_player_shot_error":app.gameplay_combat.last_error},"  "))
