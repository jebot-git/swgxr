extends SceneTree
## Real native backend, isolated diagnostic body; no headset or GPU validation.
const Controller=preload("res://combat/action_combat.gd")
class Host extends Node3D:
	var datapad_account:=""
	var world_ready:=true
	var loading_stage:=false
	var session_leaving:=false
	var xr_requested:=false
	var xr_focused:=true
	var player:CharacterBody3D
	var base_url:=""
	var timings:Array=[]
	var latency:=0.0
	var serial:=0
	func source_position_at(p:Vector3)->Vector3:return p
	func api(method:int,path:String,body:Dictionary)->Dictionary:
		var started:=Time.get_ticks_usec()
		if latency>0:await get_tree().create_timer(latency*.5).timeout
		var http:=HTTPRequest.new();add_child(http);http.timeout=10
		if http.request(base_url+path,["Content-Type: application/json"],method,JSON.stringify(body))!=OK:http.queue_free();return {}
		var response:Array=await http.request_completed;http.queue_free()
		if latency>0:await get_tree().create_timer(latency*.5).timeout
		var value:Variant=JSON.parse_string(response[3].get_string_from_utf8())
		var elapsed:float=(Time.get_ticks_usec()-started)/1000000.0
		var timing:Dictionary={"route":path,"ms":elapsed*1000,"status":response[1]}
		if value is Dictionary:
			for key in ["adapter_queue_ms","adapter_rate_wait_ms","native_bridge_roundtrip_ms","native_action_ms"]:
				if value.has(key):timing[key]=value[key]
		timings.append(timing)
		return value if value is Dictionary else {}
class Sync extends Node:
	var owner_session:=""
	var owner_character:=""
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],p[2])
var config:Dictionary
var host:Host
var sync:Sync
var controller:Node3D
var elapsed:=0.0
var sequence:=int(Time.get_unix_time_from_system()*1000000)
var poll_busy:=false
var update_busy:=false
var poll_at:=0.0
var update_at:=0.0
var events:=0
var seen:Dictionary={}
var movement_errors:Array=[]
var home:Vector3
var destination:Vector3
var ending:=false
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();config=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	host=Host.new();root.add_child(host);host.base_url=config.url;host.datapad_account=config.account;host.latency=float(config.get("latency_ms",0))/1000
	host.player=CharacterBody3D.new();host.add_child(host.player);home=Vector3(config.position[0],config.position[1],config.position[2]);host.player.position=home;destination=home
	sync=Sync.new();root.add_child(sync);sync.owner_session=config.session_id;sync.owner_character=config.character_id
	controller=Controller.new();root.add_child(controller);controller.setup(host,sync)
func identity()->Dictionary:
	return {"account":config.account,"character_id":config.character_id,"session_id":config.session_id,"zone":"tatooine"}
func _process(delta:float)->bool:
	if not is_instance_valid(host) or ending:return false
	elapsed+=delta
	# First six seconds hold position; then sidestep committed ranged footprints.
	if elapsed>6:
		for row:Dictionary in controller.timeline.attacks.values():
			var event:Dictionary=row.event
			if event.role!="ranged" or event.phase!="windup" or seen.has(controller.timeline.key(event)):continue
			seen[controller.timeline.key(event)]=true
			var aim:=Vector3(event.direction[0],0,event.direction[2]);var side:=Vector3(aim.z,0,-aim.x)
			destination=host.player.position+side*2.2
			if destination.distance_to(home)>8:destination=host.player.position-side*2.2
	host.player.position=host.player.position.move_toward(destination,3.5*delta)
	if elapsed>=poll_at and not poll_busy:poll()
	if elapsed>=update_at and not update_busy:update_native()
	if elapsed>=float(config.get("seconds",24)):finish()
	return false
func poll()->void:
	poll_busy=true;sequence+=1;var body:=identity();var p:=host.player.position
	body.merge({"sequence":sequence,"world_revision":0,"event_sequence":0,"position":[p.x,p.y,p.z],"heading_radians":0,"building_id":"0","cell_index":0,"tracking":{}})
	var start:=Time.get_ticks_usec();var reply:Dictionary=await host.api(HTTPClient.METHOD_POST,"/session/sync",body)
	var rtt:float=(Time.get_ticks_usec()-start)/1000000.0
	var rows:Array=reply.get("motion",{}).get("action_events",[]);events+=rows.size();controller.accept(rows,rtt)
	poll_at=elapsed+.06;poll_busy=false
func update_native()->void:
	update_busy=true;var body:=identity();var p:=host.player.position
	body.merge({"position":[p.x,p.y,p.z],"heading_radians":0,"ready":true})
	var reply:Dictionary=await host.api(HTTPClient.METHOD_POST,"/combat/session/update",body)
	if reply.has("error_code"):movement_errors.append(reply.error_code)
	update_at=elapsed+.1;update_busy=false
func finish()->void:
	ending=true
	while update_busy or poll_busy or controller.sending:await process_frame
	controller.set_process(false)
	var p:=host.player.position
	var report:Dictionary={"position":[p.x,p.y,p.z],"events":events,"receipts":controller.timeline.receipts,"accepted":controller.confirmed,"rejected":controller.rejected,"late_warnings":controller.timeline.rejected_late,"aim_updates":controller.timeline.aim_updates,"aim_locks":controller.timeline.aim_locks,"late_locks":controller.timeline.late_locks,"sidesteps":seen.size(),"movement_errors":movement_errors,"requests":host.timings,"renderer":"dummy","server_mocked":false,"injected_rtt_ms":host.latency*1000}
	var file:=FileAccess.open(config.output,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print(JSON.stringify(report));quit(0 if controller.confirmed>0 and seen.size()>0 and movement_errors.is_empty() else 1)
