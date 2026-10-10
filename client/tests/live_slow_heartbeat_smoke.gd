extends SceneTree
## Actual HTTP transport and production frame ordering; isolated mocked Core3.
const Harness=preload("res://tests/spice_profile_transport_smoke.gd").Harness
class Endpoint extends Node:
	var server:=TCPServer.new()
	var peers:Array=[]
	var paths:Array=[]
	var sequence:=0
	var optional_in_flight:=0
	var max_optional_in_flight:=0
	var envelope:Dictionary={}
	func _process(_delta:float)->void:
		while server.is_connection_available():peers.append({"peer":server.take_connection(),"text":"","path":"","due":0})
		for row:Dictionary in peers.duplicate():
			row.peer.poll()
			if row.peer.get_available_bytes()>0:row.text+=row.peer.get_utf8_string(row.peer.get_available_bytes())
			if row.path.is_empty() and "\r\n\r\n" in row.text:
				row.path=str(row.text).get_slice(" ",1);paths.append(row.path)
				var delay:float=.35 if row.path.ends_with("/update") else .4 if row.path=="/performance" else .2
				row.due=Time.get_ticks_usec()+int(delay*1000000)
				if row.path=="/services/status":optional_in_flight+=1;max_optional_in_flight=maxi(max_optional_in_flight,optional_in_flight)
			if not row.path.is_empty() and Time.get_ticks_usec()>=int(row.due):
				var value:Dictionary={"backend":"core3","fixture":"loopback mock"}
				if row.path.begins_with("/combat/session/"):
					sequence+=1;value=envelope.duplicate(true);value.sequence=sequence
				var payload:=JSON.stringify(value)
				row.peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"%payload.to_utf8_buffer().size()+payload).to_utf8_buffer());peers.erase(row)
				if row.path=="/services/status":optional_in_flight-=1
				get_tree().create_timer(.1).timeout.connect(row.peer.disconnect_from_host)
class Poller extends Node:
	var app:Node
	var family:="services"
	var pending:=false
	var grants:=0
	var performance:=false
	func _process(_delta:float)->void:
		if pending:return
		if not performance and not app.try_background_poll(family):return
		pending=true;grants+=1
		await app.api(HTTPClient.METHOD_POST,"/performance" if performance else "/services/status",{})
		pending=false
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(15).timeout.connect(func():quit(2))
	var endpoint:=Endpoint.new();root.add_child(endpoint);check(endpoint.server.listen(0,"127.0.0.1")==OK,"Slow mock CoreCU endpoint starts")
	endpoint.envelope={"ok":true,"backend":"core3","source_kind":"core3_live_combat","character_id":"123","session_id":"native-session","sequence":0,"session_live":true,"snapshot":{"ready":true,"full":true,"actors":[],"player":{"ham":[1000,900,800],"max_ham":[1000,900,800],"dead":false,"incapacitated":false,"posture":0,"wounds":[0,0,0],"shock_wounds":0},"weapon":{"item_id":"987","certified":true,"fire_interval_seconds":3.0,"max_range_m":50.0,"projectile_speed":100.0}}}
	var app:=Harness.new();root.add_child(app);app.backend_url="http://127.0.0.1:%d"%endpoint.server.get_local_port();app.datapad_account="fixture";app.datapad_character_id="123";app.world_ready=true;app.live_combat_reserved=true
	app.menu=PanelContainer.new();app.add_child(app.menu);app.menu.hide();app.stage=Node3D.new();app.add_child(app.stage);app.player=CharacterBody3D.new();app.add_child(app.player)
	var head:=Camera3D.new();app.add_child(head)
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json")).weapons.pistol_fwg5.duplicate(true);profile.item_id="987";profile.source_kind="core3_weapon_instance";profile.certified=true
	var rig:=preload("res://combat/ranged_rig.gd").new();app.add_child(rig);rig.configure(head,app.player,[profile]);rig.set_process(false);rig.set_physics_process(false)
	var live:=preload("res://combat/live_world.gd").new();app.add_child(live);live.configure(app,rig,app.stage,app.player);app.live_combat=live
	check(await live.start(Vector3.ZERO,0),"Production live session starts through actual loopback HTTP")
	var services:=Poller.new();services.app=app;services.process_priority=119;app.add_child(services)
	var entertainer:=Poller.new();entertainer.app=app;entertainer.family="entertainer";entertainer.process_priority=120;app.add_child(entertainer)
	var performance:=Poller.new();performance.app=app;performance.performance=true;performance.process_priority=121;app.add_child(performance)
	await create_timer(5.2).timeout
	check(live.live and live.is_ready() and live.sequence>=8,"Slow heartbeat remains live while later-priority optional services execute")
	check(services.grants>=2 and entertainer.grants>=2,"Both optional families receive fair grants despite continuously occupied heartbeat")
	check(services.grants+entertainer.grants<=6 and endpoint.max_optional_in_flight==1,"One-second shared interval and maximum one optional native request remain enforced")
	check(performance.grants>=8 and app.api_realtime_requests_in_flight>0,"Active performance presentation uses realtime accounting without starving native polls")
	services.set_process(false);entertainer.set_process(false);performance.set_process(false);live.set_process(false)
	while app.api_requests_in_flight>0:await process_frame
	check(app.native_requests_in_flight()==0,"Completed production HTTP requests release native admission counters")
	var report:Dictionary={"checks":checks,"errors":errors,"heartbeat_seconds":.35,"services_grants":services.grants,"entertainer_grants":entertainer.grants,"performance_requests":performance.grants,"live_sequence":live.sequence,"transport":"actual loopback HTTP, mocked CoreCU","headset_validated":false}
	app.free();endpoint.server.stop();endpoint.free();await process_frame
	FileAccess.open("res://../runtime/evidence/live-slow-heartbeat-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
