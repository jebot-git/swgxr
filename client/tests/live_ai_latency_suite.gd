extends SceneTree
## Explicit opt-in, real Core3 + full production scene. Only the dedicated local
## ranged fixture is accepted. No mocked transport, tracking or native AI.
class Host extends "res://scripts/main.gd":
	var timings:Array=[]
	var samples:Array=[]
	var owned_session:=""
	var motion_samples:Array=[]
	func api(method:HTTPClient.Method,path:String,body:Dictionary={})->Dictionary:
		var start:=Time.get_ticks_usec()
		var reply:Dictionary=await super.api(method,path,body)
		var finish:=Time.get_ticks_usec()
		if path.ends_with("/start") and reply.get("session_live",false):owned_session=str(reply.get("session_id",""))
		timings.append({"at":finish/1000000.0,"unix_at":Time.get_unix_time_from_system(),"path":path.get_slice("?",0),"elapsed_ms":(finish-start)/1000.0,"ok":reply.get("ok",false),"error":str(reply.get("error_code",reply.get("error",""))).left(160),"world_age_ms":reply.get("world_age_ms",0)})
		var movement:Dictionary=reply.get("motion",{})
		if not movement.is_empty():motion_samples.append({"at":finish/1000000.0,"request_ms":(finish-start)/1000.0,"epoch":movement.get("epoch"),"actors":movement.get("actors",[])})
		var snapshot:Dictionary=reply.get("snapshot",{})
		var source_actors:Variant=snapshot.get("actors",snapshot.get("world",{}).get("actors"))
		if source_actors is Array:
			var actors:Array=[]
			for row:Dictionary in source_actors:
				actors.append({"id":str(row.id),"position":row.position,"heading":row.get("heading_radians",0),"dead":row.get("dead",false),"kind":row.get("kind",""),"movement_counter":row.get("movement_counter",-1),"lair_id":str(row.get("lair_id",""))})
			samples.append({"at":finish/1000000.0,"sequence":reply.get("sequence",-1),"actors":actors,"player":snapshot.get("player",{}).get("position",[])})
		return reply
var app:Host
var output:=""
var frames:Array=[]
var errors:Array=[]
var finished:=false
func _initialize()->void:call_deferred("run")
func run()->void:
	var options:Dictionary={}
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.trim_prefix("--").split("=",true,1)
		options[pair[0]]=pair[1] if pair.size()>1 else true
	output=str(options.get("latency-output",""))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(options.get("latency-fixture","res://../runtime/server/ranged-test-fixture.json"))))
	var local_fixture:bool=options.has("local") and fixture.account=="rangetest1a142"
	var remote_fixture:bool=options.has("connection-profile") and str(fixture.account).begins_with("latency_")
	if not (local_fixture or remote_fixture) or options.get("account","")!=fixture.account or options.get("enter-character","")!=fixture.name or not output.is_absolute_path():
		push_error("Explicit dedicated diagnostic fixture and absolute latency-output required");quit(2);return
	create_timer(240).timeout.connect(func():finish("Suite watchdog expired"))
	Engine.max_fps=90
	app=Host.new();root.add_child(app);current_scene=app
	while not app.world_ready and not finished:
		await process_frame
		if is_instance_valid(app.asset_status) and str(app.asset_status.text).begins_with("Live CoreCU combat could not start"):
			await finish(str(app.asset_status.text));return
	if finished:return
	if app.datapad_character_id!=str(fixture.id):await finish("Unexpected character identity");return
	await create_timer(3).timeout
	var start:=Time.get_ticks_usec()
	var previous:=start
	app.player.testing=true
	# Autonomous bounded patrol: stationary, walk out, stop, reverse, stationary.
	# Native locomotion and stage collision govern every input; no pose teleport.
	while Time.get_ticks_usec()-start<60000000 and not finished:
		await process_frame
		var now:=Time.get_ticks_usec()
		var elapsed:=(now-start)/1000000.0
		var phase:="idle"
		var input:=Vector2.ZERO
		if elapsed>=20 and elapsed<23:phase="forward";input=Vector2(0,-.4)
		elif elapsed>=30 and elapsed<33:phase="reverse";input=Vector2(0,.4)
		app.player.test_input=input
		var poses:Array=[]
		var actors:Dictionary={}
		if is_instance_valid(app.live_combat):actors=app.live_combat.actors
		elif is_instance_valid(app.multiplayer_sync):actors=app.multiplayer_sync.entities.actors
		for actor:Node3D in actors.values():
			poses.append({"id":str(actor.record.id),"position":[actor.position.x,actor.position.y,actor.position.z],"goal":[actor.goal.origin.x,actor.goal.origin.y,actor.goal.origin.z],"motion_sequence":actor.motion_sequence,"motion_counter":actor.motion_counter})
		frames.append({"at":now/1000000.0,"elapsed":elapsed,"delta_ms":(now-previous)/1000.0,"phase":phase,"player":[app.player.position.x,app.player.position.y,app.player.position.z],"actors":poses})
		previous=now
	if frames.is_empty():errors.append("No live frames collected")
	await finish("")
func finish(problem:String)->void:
	if finished:return
	finished=true
	if not problem.is_empty():errors.append(problem)
	if is_instance_valid(app):
		if is_instance_valid(app.player):app.player.test_input=Vector2.ZERO
		# Persist diagnostics before cleanup as well, preserving evidence on error.
		save(false)
		if app.world_ready:await app.leave_character()
		elif not app.owned_session.is_empty():
			var stopped:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/stop",{"account":app.datapad_account,"character_id":app.datapad_character_id,"session_id":app.owned_session})
			if not stopped.get("ok",false):errors.append("Native cleanup failed")
		save(true)
	print(JSON.stringify({"suite":"live_ai_latency","errors":errors,"frames":frames.size(),"snapshots":app.samples.size(),"output":output}))
	quit(0 if errors.is_empty() else 1)
func save(cleaned:bool)->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"native_execution":true,"transport_mocked":false,"scene":"full production main/stage","renderer":DisplayServer.get_name(),"headset_tested":false,"input":"autonomous bounded patrol through native locomotion","errors":errors,"cleanup_completed":cleaned,"frames":frames,"snapshots":app.samples,"motion":app.motion_samples,"requests":app.timings,"native_queue":app.native_api_observations}))
