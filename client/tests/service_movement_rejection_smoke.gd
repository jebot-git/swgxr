extends SceneTree
const Host=preload("res://tests/spice_profile_transport_smoke.gd").Harness
const Fixture=preload("res://tests/gameplay_combat_smoke.gd")
class Endpoint extends Node:
	var server:=TCPServer.new()
	var peers:Array=[]
	var response:Dictionary={}
	func _process(_delta:float)->void:
		if server.is_connection_available():peers.append({"peer":server.take_connection(),"text":""})
		for row in peers.duplicate():
			row.peer.poll()
			if row.peer.get_available_bytes()>0:row.text+=row.peer.get_utf8_string(row.peer.get_available_bytes())
			if "\r\n\r\n" in row.text:
				var payload:=JSON.stringify(response)
				row.peer.put_data(("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"%payload.to_utf8_buffer().size()+payload).to_utf8_buffer());peers.erase(row)
				get_tree().create_timer(.5).timeout.connect(row.peer.disconnect_from_host)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func corrected_position(session:Node)->bool:
	var point:Variant=session.player_state.get("position")
	return point is Array and point.size()==3 and Vector3(float(point[0]),float(point[1]),float(point[2])).is_equal_approx(Vector3(2,0,3))
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(15).timeout.connect(func():quit(2))
	var app:=Host.new();root.add_child(app);app.datapad_character_id="101";app.datapad_account="fixture"
	var session:=preload("res://scripts/gameplay_session.gd").new();app.gameplay_session=session;app.add_child(session);session.setup(app);session.set_process(false)
	var fixture:=Fixture.Host.new();var native:Dictionary=fixture.envelope();fixture.free()
	check(session.accept(native,true),"Production owned RPG session accepts fixture")
	native.source_kind="core3_live_combat";native.sequence=2;native.ok=false;native.error_code="native_movement_speed"
	native.mutation={"movement_accepted":false,"error_code":"native_movement_speed"};native.snapshot.player.position=[2,0,3]
	var reply:Dictionary={"ok":false,"backend":"core3","error_code":"native_movement_speed","live_response":native}
	# Even the socket-free fixture uses actual JSON numeric types. Godot parses
	# numbers as floats; Array equality against integer fixtures is type-strict.
	reply=JSON.parse_string(JSON.stringify(reply))
	var endpoint:=Endpoint.new();root.add_child(endpoint);endpoint.response=reply
	var listening:=false
	if "--http" in OS.get_cmdline_user_args():
		listening=endpoint.server.listen(0,"127.0.0.1")==OK
		check(listening,"Loopback HTTP fixture can bind")
	if listening:
		app.backend_url="http://127.0.0.1:%d"%endpoint.server.get_local_port()
		var result:Dictionary=await app.api(HTTPClient.METHOD_POST,"/services/status",{"character_id":"101"})
		check(not result.ok and result.http_status==400,"Movement rejection preserves failed service action")
		check(session.sequence==2 and session.player_state.movement_rejected.reason=="native_movement_speed" and corrected_position(session),"Global HTTP path adopts explicit authoritative correction before service sees failure")
		check(not result.live_response.ok,"State acceptance does not rewrite original rejected envelope")
	else:
		check(app.consume_movement_rejection(reply),"Global API rejection consumer accepts explicit owned correction")
		check(session.sequence==2 and session.player_state.movement_rejected.reason=="native_movement_speed" and corrected_position(session) and not reply.ok and not reply.live_response.ok,"Correction updates player state while retaining failed action and original envelope")
	var stale:=reply.duplicate(true);stale.live_response.sequence=1;stale.live_response.snapshot.player.position=[99,0,99]
	app.consume_movement_rejection(stale)
	check(session.sequence==2 and corrected_position(session),"Older correction cannot roll back newer authoritative state")
	var foreign:=reply.duplicate(true);foreign.live_response.session_id="other";foreign.live_response.sequence=3
	check(not app.consume_movement_rejection(foreign) and session.sequence==2,"Foreign-session correction is rejected")
	var ordinary:=reply.duplicate(true);ordinary.live_response.mutation.movement_accepted=true
	check(not app.consume_movement_rejection(ordinary),"Accepted movement is never reinterpreted as correction")
	ordinary=reply.duplicate(true);ordinary.live_response.mutation.error_code="inventory_full"
	check(not app.consume_movement_rejection(ordinary),"Unrelated service failure cannot bypass snapshot success validation")
	var success:=reply.duplicate(true);success.ok=true;success.live_response.erase("ok");success.live_response.erase("error_code");success.live_response.mutation={"success":true};success.live_response.sequence=3
	success.live_response.snapshot.player.locomotion={"movement_revision":91}
	check(app.consume_native_success(success),"Any successful service envelope advances owned authority, even without optional ok field")
	check(session.sequence==3 and session.player_state.locomotion.movement_revision==91 and not session.player_state.has("movement_rejected"),"Housing/service success does not leave a stale movement revision or apply a correction")
	var stamped:Dictionary=preload("res://combat/movement_reconciliation.gd").stamp_request({"position":[2,0,3]},session.player_state)
	check(stamped.movement_revision==91,"Next movement uses revision produced by successful housing/service request")
	endpoint.server.stop();endpoint.queue_free();app.queue_free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"transport":"loopback HTTP, mocked CoreCU" if listening else "direct production API response consumer, mocked CoreCU","renderer":"dummy","headset_validated":false}
	FileAccess.open("res://../runtime/evidence/service-movement-rejection-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
