extends SceneTree
## Main session ordering/API guards and actual HAM state; mocked transport, no server claim.
var Host=load("res://tests/live_main_host.gd")
const Ability=preload("res://combat/ability_state.gd")
class Feedback extends RefCounted:
	var local_prediction:=true
	var observations: Array=[]
	func observe(context:Dictionary)->void: observations.append(context.duplicate(true))
class Body extends CharacterBody3D:
	var feedback:=Feedback.new()
class Rig extends Node3D:
	var abilities:=Ability.new()
	var weapons: Array=[{}]
	var allowed:=true
	func set_allowed(value:bool)->void: allowed=value
class Controller extends Node3D:
	func reset()->void: pass
class Session extends Node3D:
	var live:=true
	var session_id:="native-main-fixture"
	signal stopped
	var app:Node
	var stopped_count:=0
	var failures: Array=[]
	var was_reserved_during_stop:=false
	func fail(reason:String)->void: failures.append(reason)
	func stop()->void:
		stopped_count+=1;app.events.append("stop_begin")
		was_reserved_during_stop=app.live_combat_reserved
		await get_tree().process_frame
		app.events.append("stop_end");stopped.emit()
class HTTPMock extends Node:
	var server:=TCPServer.new()
	var peer:StreamPeerTCP
	var port:=0
	var bytes:=""
	var requests: Array=[]
	var hold_response:=false
	func begin()->bool:
		for candidate in range(19410,19430):
			if server.listen(candidate,"127.0.0.1")==OK:port=candidate;return true
		return false
	func _process(_delta:float)->void:
		if peer==null and server.is_connection_available():peer=server.take_connection()
		if peer==null:return
		peer.poll()
		if peer.get_available_bytes()>0:bytes+=peer.get_utf8_string(peer.get_available_bytes())
		if not bytes.contains("\r\n\r\n"):return
		if hold_response:return
		requests.append(bytes.split("\r\n")[0]);var body:="{\"backend\":\"fixture\",\"source_kind\":\"transport_test_only\"}"
		peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"%[body.to_utf8_buffer().size(),body]).to_utf8_buffer())
		peer.disconnect_from_host();peer=null;bytes=""
	func _exit_tree()->void: server.stop()
var checks:=0
var errors: Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func context()->Dictionary:
	return {"character_id":"A","complete":true,"ham":[900,301,302,800,304,305,700,307,308],"max_ham":[1000,401,402,900,404,405,800,407,408],"wounds":[0,1,2,0,4,5,0,7,8]}
func verify_ham()->void:
	var ability:=Ability.new();ability.refresh_context(context());ability.cooldowns={"native_action":2.0};ability.primed=true
	var original:Dictionary={"ham":ability.ham.duplicate(),"max_ham":ability.max_ham.duplicate(),"wounds":ability.wounds.duplicate()}
	var packet:={"ham":[450,300,200],"max_ham":[1000,900,800],"wounds":[100,50,20]}
	check(ability.apply_authoritative(packet),"Valid exact authoritative HAM rejected")
	check(ability.ham[0]==450 and ability.ham[3]==300 and ability.ham[6]==200,"Primary pools did not replace local prediction exactly")
	for i in [1,2,4,5,7,8]:
		check(ability.ham[i]==original.ham[i] and ability.max_ham[i]==original.max_ham[i] and ability.wounds[i]==original.wounds[i],"Authenticated secondary attribute changed at index%d"%i)
	check(not ability.primed and ability.cooldowns.native_action==2.0,"Snapshot left a primed local ability or changed unrelated cooldown")
	packet.ham=[650,500,400];check(ability.apply_authoritative(packet) and ability.ham[0]==650,"Native regeneration was suppressed by disconnected min-only refresh policy")
	var bars:=ability.readout()
	check(bars[0].current==650 and bars[0].wounds==100 and is_equal_approx(bars[0].fill,0.65) and is_equal_approx(bars[0].blocker,0.1),"Wound blocker/current HUD fractions incorrect")
	packet.ham[0]=950;check(ability.apply_authoritative(packet) and ability.ham[0]==950 and ability.readout()[0].current==900,"Transient native current above unwounded max is not preserved with bounded readout")
	packet.ham=[0,0,0];check(ability.apply_authoritative(packet) and ability.readout()[0].current==0,"Native zero pool not preserved")
	var malformed: Array=[{}, {"ham":null},{"ham":{}},{"ham":"invalid"},{"ham":[1,2]},{"ham":[true,2,3]},{"ham":["1",2,3]},{"ham":[NAN,2,3]},{"ham":[INF,2,3]},{"ham":[-1,2,3]},{"ham":[1001,2,3]},{"max_ham":false},{"max_ham":[0,900,800]},{"wounds":null},{"wounds":[1001,0,0]}]
	for invalid:Dictionary in malformed:
		var bad:Dictionary=packet.duplicate(true)
		if invalid.is_empty():bad={}
		else:bad.merge(invalid,true)
		var before:=ability.ham.duplicate();var maximum:=ability.max_ham.duplicate();var wounds:=ability.wounds.duplicate()
		check(not ability.apply_authoritative(bad) and not ability.pools_valid and not ability.vitals_valid,"Malformed native pools did not fail closed: "+str(invalid))
		check(ability.ham==before and ability.max_ham==maximum and ability.wounds==wounds,"Malformed snapshot partially mutated primary arrays")
	check(ability.apply_authoritative(packet) and ability.pools_valid and ability.vitals_valid,"Valid recovery snapshot could not restore display validity")
func run()->void:
	create_timer(20).timeout.connect(func():push_error("Live main smoke timed out");quit(2))
	verify_ham()
	var app:Node=Host.new();root.add_child(app)
	app.player=Body.new();app.add_child(app.player)
	app.combat_rig=Rig.new();app.add_child(app.combat_rig);app.combat_rig.abilities.refresh_context(context())
	app.asset_status=Label.new();app.add_child(app.asset_status)
	app.status=Label.new();app.add_child(app.status)
	app.gathering=Controller.new();app.add_child(app.gathering)
	app.corpse_gathering=Controller.new();app.add_child(app.corpse_gathering)
	app.entertainer=Controller.new();app.add_child(app.entertainer)
	app.datapad_character_id="selected_owner"
	var packet:={"ham":[100,200,300],"max_ham":[1000,900,800],"wounds":[0,1,2],"posture":0}
	var before: Array=app.combat_rig.abilities.ham.duplicate()
	app.apply_live_player(packet)
	check(app.combat_rig.abilities.ham==before and app.player.feedback.observations.is_empty(),"Late snapshot outside reserved session mutated pools/posture")
	var session:=Session.new();session.app=app;app.add_child(session);app.live_combat=session;app.live_combat_reserved=true
	app.apply_live_player(packet)
	check(app.combat_rig.abilities.ham[3]==200 and app.player.feedback.observations[-1].character_id=="selected_owner","Main did not adopt exact native pools and current owner posture")
	var count:int=app.player.feedback.observations.size()
	var bad:=packet.duplicate(true);bad.ham=null;app.apply_live_player(bad)
	check(session.failures.size()==1 and app.player.feedback.observations.size()==count,"Malformed snapshot applied posture instead of failing live transport")
	app.live_combat_state_changed(false,"Disconnected fixture")
	check(not app.combat_rig.allowed and not app.combat_rig.abilities.pools_valid,"Lost session failed to disarm combat")
	var transport:=HTTPMock.new();root.add_child(transport);check(transport.begin(),"Local HTTP transport fixture could not bind")
	app.backend_url="http://127.0.0.1:%d"%transport.port
	for path in ["/inventory","/enter","/gathering","/datapad","/characters","/combat/items"]:
		var denied:Dictionary=await app.guarded_api(HTTPClient.METHOD_GET,path)
		check(not denied.get("ok",false) and transport.requests.is_empty(),"Reserved session leaked a reconnecting RPC: "+path)
	var allowed:Dictionary=await app.guarded_api(HTTPClient.METHOD_POST,"/combat/session/update",{"session_id":"fixture"})
	check(allowed.get("ok",false) and transport.requests.size()==1,"Main guard blocked persistent session transport")
	check(app.api_requests_in_flight==0,"Completed session HTTP request leaked the drain counter")
	app.live_combat_reserved=false;transport.hold_response=true
	app.guarded_api(HTTPClient.METHOD_GET,"/inventory")
	await process_frame;await process_frame
	check(app.api_requests_in_flight==1,"Already-issued legacy request is absent from the session drain counter")
	app.live_combat_reserved=true
	var blocked:Dictionary=await app.guarded_api(HTTPClient.METHOD_GET,"/characters")
	check(not blocked.get("ok",false) and app.api_requests_in_flight==1,"Reserved denied RPC corrupted pending legacy drain count")
	transport.hold_response=false
	for _frame in range(8):await process_frame
	check(app.api_requests_in_flight==0 and transport.requests.size()==2,"Pending legacy completion did not drain before live ownership")
	for controller in [app.gathering,app.corpse_gathering,app.entertainer]:controller.process_mode=Node.PROCESS_MODE_DISABLED
	app.player.feedback.local_prediction=false
	app.core3_ready=true;app.account_input=LineEdit.new();app.account_input.text="owner";app.add_child(app.account_input)
	app.character_list=ItemList.new();app.add_child(app.character_list);app.character_list.add_item("next");app.character_list.select(0)
	app.characters=[{"id":"next_character"}];app.reply={"ok":true,"backend":"core3","character_id":"next_character"}
	await app.enter_character()
	check(app.events==["stop_begin","stop_end","api:/enter","enter_stage"],"Character reconnect started before persistent session stop completed")
	check(not app.calls[-1].reserved and app.live_combat==null and not app.live_combat_reserved,"Session reservation remained during next character entry")
	check(app.player.feedback.local_prediction,"Stop did not restore local feedback mode")
	for controller in [app.gathering,app.corpse_gathering,app.entertainer]:check(controller.process_mode==Node.PROCESS_MODE_INHERIT,"Stop failed to resume suspended controller")
	var calls_before:int=app.calls.size();await app.stop_live_combat();check(app.calls.size()==calls_before,"Idempotent second stop issued another mutation")
	app.apply_live_player(packet);check(app.player.feedback.observations.size()==count,"Late stopped-session snapshot reached feedback")
	app.api_requests_in_flight=1;app.begin_start_test()
	await process_frame
	check(app.live_combat_reserved and app.start_result==null and app.live_combat==null,"Live startup did not wait for old one-shot RPCs before creating a session")
	await app.stop_live_combat();app.api_requests_in_flight=0
	await process_frame;await process_frame
	check(app.start_result==false and app.live_combat==null and not app.live_combat_reserved and app.calls.size()==calls_before,"Cancelled drain resumed an obsolete live startup")
	var concurrent:=Session.new();concurrent.app=app;app.add_child(concurrent);app.live_combat=concurrent;app.live_combat_reserved=true
	var events_before:int=app.events.size()
	app.stop_live_combat();await app.stop_live_combat()
	await process_frame;await process_frame
	check(app.events.slice(events_before)==["stop_begin","stop_end"] and app.live_combat==null and not app.live_combat_reserved,"Concurrent stop dereferenced/freed the wrong session or stopped it twice")
	transport.queue_free()
	# Exercise the actual WM_CLOSE handler last: it intentionally quits SceneTree.
	var closing:=Session.new();closing.app=app;app.add_child(closing);app.live_combat=closing;app.live_combat_reserved=true;app.args={"live-combat":true}
	closing.stopped.connect(func():
		check(closing.stopped_count==1 and closing.was_reserved_during_stop,"WM_CLOSE did not hold reservation through one graceful session stop")
		var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"gpu_tested":false,"wm_close_session_stop_tested":true}
		FileAccess.open("res://../runtime/evidence/live-main-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		print(JSON.stringify(report))
	)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
