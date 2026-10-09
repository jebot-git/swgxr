extends SceneTree
const Controller=preload("res://space/controller.gd")
const Scene=preload("res://space/scene.gd")
const Presenter=preload("res://space/crew_presentation.gd")
class Host extends "res://scripts/main.gd":
	var response:Dictionary={}
	var calls:Array=[]
	var landings:Array=[]
	func api(_method:HTTPClient.Method,path:String,body:Dictionary={})->Dictionary:
		calls.append({"path":path,"body":body.duplicate(true)});await get_tree().process_frame;return response.duplicate(true)
	func perform_service_transport(value:Dictionary)->bool:landings.append(value.duplicate(true));return true
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
class Services extends "res://scripts/services_controller.gd":
	func terminal_records(_fresh:=true)->Array:return [{"id":"555","kind":"starship","position":Vector3.ZERO}]
class Native extends Node:
	var live:=true
	var session_id:="crew-owned-session"
	func accept_native_response(_value:Dictionary)->bool:return true
class Pad extends Node3D:
	var ui=preload("res://scripts/datapad_ui.gd").new()
	var is_open:=false
	func _ready()->void:add_child(ui);add_child(ui.take_detail_panel())
	func set_open(value:bool)->void:is_open=value
var checks:=0
var failures:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func receipt(value:Dictionary,sequence:int,ok:=true)->Dictionary:
	return {"ok":ok,"backend":"core3","source_kind":"core3_jtl","character_id":"123","state":value,"live_response":{"sequence":sequence},"mutation":{"success":ok}}
func run()->void:
	var proof:=preload("res://space/crew_handshake.gd").new()
	var peer:Dictionary={"id":"987","crew_launch_id":"launch-1","crew_handshake_id":"0123456789abcdef01234567","crew_handshake_ready":true}
	var joined:Dictionary=proof.take_ready("123",[peer])
	check(joined.get("pilot_id","")=="987" and joined.launch_id=="launch-1" and joined.request_id=="crew_"+peer.crew_handshake_id,"Crew gesture uses an exact launch-bound receipt independent of character ID order or party membership")
	check(proof.take_ready("123",[peer]).is_empty(),"One contact receipt cannot enroll twice")
	proof.reset();var expired:=peer.duplicate();expired.crew_handshake_ready=false
	check(proof.take_ready("123",[expired]).is_empty(),"Unready contact is not enrollment")
	var payment:=peer.duplicate();payment.erase("crew_handshake_ready");payment.handshake_authorized=true
	check(proof.take_ready("123",[payment]).is_empty(),"A wallet proof cannot authorize crew enrollment")
	var wrong:=peer.duplicate();wrong.crew_handshake_id="bad"
	check(proof.take_ready("123",[wrong]).is_empty() and proof.take_ready("987",[peer]).is_empty(),"Malformed proof and pilot self-join are rejected")
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var actions:Array=[];var close_calls:Array=[]
	panel.action_requested.connect(func(action,payload):actions.append([action,payload]));panel.close_requested.connect(func():close_calls.append(true))
	panel.configure({"id":"555","kind":"ship_crew","launch_id":"launch-1","pilot_id":"123","is_pilot":true,"capacity":8,"members":[{"id":"123","name":"Pilot"},{"id":"987","name":"Guest"}]},{})
	check(actions.is_empty() and panel.rows.size()==2,"Displaying authoritative roster never launches or changes crew")
	panel.click_at(Vector2(150,145));check(actions.is_empty(),"Pilot cannot remove himself by tapping the roster")
	panel.click_at(Vector2(150,181));check(actions.size()==1 and actions[0][0]=="jtl_crew_remove" and actions[0][1].member_id=="987","Tapping a guest requests native removal")
	check(panel.rows.size()==2,"Roster waits for native removal receipt")
	panel.set_pending(false);panel.confirm()
	check(actions.back()[0]=="jtl_launch_confirm" and actions.back()[1].launch_id=="launch-1" and actions.back()[1].terminal_id=="555","Separate Launch confirmation binds prepared stage and original terminal")
	panel.set_pending(false);panel.click_at(panel.REFRESH_RECT.get_center());check(close_calls.size()==1,"Cancel launch is a distinct action")
	panel.terminal.is_pilot=false;var before:=actions.size();panel.confirm();check(actions.size()==before,"A crew member cannot trigger pilot launch")
	var stage:=preload("res://scripts/cell_stage.gd").new();root.add_child(stage);stage.position=Vector3(0,10000,0)
	var native_peer:Dictionary={"id":"987","ship_id":"77","name":"Guest","position":[2,0,3],"heading_radians":0.0,"cell_index":1,"posture":0,"appearance":{}}
	var ship:Dictionary={"id":"77","crew":[native_peer]}
	var pose:Dictionary={"id":"987","ship_id":"77","position":[2,0,3],"heading_radians":0.0,"cell_index":1,"age_ms":100,"tracking":{"head":{"tracked":true,"position":[2,1.65,3],"rotation":[0,0,0,1]}}}
	var normalizer:=Presenter.new();var rows:Array=normalizer.normalize(ship,[pose],"123",stage)
	check(rows.size()==1 and rows[0].position==Vector3(2,10000,-3) and rows[0].tracking.head.origin==Vector3(2,10001.65,-3),"Native crew body and authenticated tracked head use shared source-local cabin coordinates")
	var stale:=pose.duplicate(true);stale.age_ms=751
	check(normalizer.normalize(ship,[stale],"123",stage)[0].tracking.is_empty(),"Stale tracking disappears while native crew presence remains")
	var foreign:=pose.duplicate(true);foreign.ship_id="88"
	check(normalizer.normalize(ship,[foreign],"123",stage)[0].tracking.is_empty(),"Another ship cannot inject crew tracking")
	var other_cell:=pose.duplicate(true);other_cell.cell_index=2
	check(normalizer.normalize(ship,[other_cell],"123",stage)[0].tracking.is_empty(),"Tracking from a different native room is rejected")
	check(normalizer.normalize({"id":"77","crew":[]},[pose],"123",stage).is_empty(),"Presentation cannot add a passenger absent from native roster")
	var distant:=pose.duplicate(true);distant.tracking.head.position=[20,1,3]
	check(normalizer.normalize(ship,[distant],"123",stage)[0].tracking.is_empty(),"Out-of-reach tracked limbs cannot escape their native body")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/catalog.json"))
	var fighter_count:=0
	for template:String in catalog.templates:
		if catalog.templates[template].get("kind","pob")=="pob":continue
		var scene:=Scene.new();root.add_child(scene);scene.position=Vector3(0,10000,0)
		var loaded:bool=scene.build("77",template)
		check(loaded and is_instance_valid(scene.cockpit),"Original cockpit loads: "+template.get_file())
		if loaded:
			scene.align_cockpit(1.65)
			check(scene.cell_index()==0 and scene.cockpit.find_children("*","StaticBody3D",true,false).is_empty(),"Small craft uses original seated cockpit without fabricated walkable floor: "+template.get_file())
		fighter_count+=1;scene.free()
	check(fighter_count>=11,"All curated small craft original cockpit variants are tested")
	var host:=Host.new();root.add_child(host);host.datapad_character_id="123";host.datapad_epoch=1;host.world_ready=true
	host.xr_origin=load("res://xr/player_rig.tscn").instantiate();host.add_child(host.xr_origin);host.player=host.xr_origin.get_node("PlayerBody");host.player.set_physics_process(false);host.player.set_process(false)
	host.stage=preload("res://scripts/cell_stage.gd").new();host.add_child(host.stage);host.player.ground_provider=host.stage
	host.datapad=Pad.new();host.add_child(host.datapad);host.gameplay_session=Native.new();host.add_child(host.gameplay_session)
	host.services=Services.new();host.add_child(host.services);host.services.set_process(false);host.services.app=host;host.services.allowed=true
	host.services.ui=preload("res://scripts/xr_services.gd").new();host.services.add_child(host.services.ui);host.services.ui.configure(host.xr_origin,host.player);host.services.ui.set_process(false);host.services.ui.allowed=true
	var flight:=Controller.new();host.add_child(flight);flight.setup(host,preload("res://space/preferences.gd").new());flight.set_process(false);host.space=flight
	host.services.ui.closed.connect(flight.lobby_closed)
	var ground:Dictionary={"enabled":true,"scope":"noncombat_navigation","ships":[],"ship":null,"boarding":{"incoming":[],"pending":{},"return_ship":{}},"launch_stage":{}}
	var prepared:=ground.duplicate(true);prepared.launch_stage={"id":"launch-1","pilot_id":"123","ship_id":"77","terminal_id":"555","capacity":8,"members":[{"id":"123","name":"Pilot"},{"id":"987","name":"Guest"}]}
	host.response=receipt(prepared,1)
	await host.services.request("jtl_launch",{"terminal_id":"555","ship_id":"77"})
	check(host.calls.back().path=="/jtl/crew_prepare" and flight.lobby_open and host.services.ui.terminal.kind=="ship_crew","Terminal selects native preparation and opens a second confirmation screen")
	check(not flight.aboard(),"Preparing a departure keeps all players on the ground")
	check(not host.services.party_hand_free("right") and host.services.party_hand_free("right",true),"Only crew handshake bypasses the open crew panel hand blocker")
	host.services.ui.wallet_held=true;check(not host.services.party_hand_free("right",true),"Held wallet cannot qualify as an empty crew handshake hand");host.services.ui.wallet_held=false
	host.services.ui.update_proximity(Vector3(4,0,0));check(flight.cancel_lobby and not flight.lobby_open,"Walking away closes the lobby and queues native cancellation")
	host.response=receipt(ground,2);flight.epoch=1;flight._process(.1);await process_frame;await process_frame
	check(host.calls.back().path=="/jtl/crew_cancel" and flight.launch_stage().is_empty(),"Walking-away cancellation is completed by native receipt")
	var launch:=ground.duplicate(true);launch.ship={"id":"77","template":"object/ship/player/player_z95.iff","kind":"fighter","station":"pilot","position":[0,0,0],"quaternion":[0,0,0,1],"player_position":[0,0,0],"cell_index":0,"stations":[{"id":"pilot","position":[0,0,0]}],"crew":[],"commands":[]}
	var hmd:Transform3D=host.player.get_camera().transform
	check(flight.observe(launch,3) and flight.seated() and is_instance_valid(flight.scene.cockpit),"Native small craft enters its actual original cockpit")
	check(host.player.get_camera().transform.is_equal_approx(hmd),"Small craft boarding preserves physical HMD local tracking")
	check(not flight.command_rows().any(func(row):return row.id=="leave"),"Fighter has no fictitious interior dismount")
	flight.state.nearby_ships=[{"id":"88","name":"Host Yacht","boarding_available":false,"boarding_reason":"POB visitors cannot board another POB.","distance_m":45}]
	flight.command("boarding_targets")
	check(flight.wheel.rows[0].available==false and flight.wheel.rows[0].reason.contains("POB"),"Boarding menu preserves native prohibition and reason")
	flight.state.nearby_ships[0].boarding_available=true;flight.command("boarding_targets")
	check(flight.wheel.rows[0].available and flight.wheel.rows[0].id=="board:88","An eligible nearby ship offers an explicit boarding request")
	host.response=receipt(launch,4);flight.command("board:88");await process_frame;await process_frame
	check(host.calls.back().path=="/jtl/boarding_request" and host.calls.back().body.target_ship_id=="88","Nearby selection asks the other pilot rather than locally transferring")
	flight.state.boarding.incoming=[{"requester_id":"987","name":"Visitor","ship_id":"99"}];flight.command("boarding_incoming")
	check(flight.wheel.rows.size()==3 and flight.wheel.rows[0].id=="board_accept:987" and flight.wheel.rows[1].id=="board_decline:987","Pilot consent offers separate allow and decline choices")
	host.response=receipt(launch,5);flight.command("board_decline:987");await process_frame;await process_frame
	check(host.calls.back().path=="/jtl/boarding_decline" and host.calls.back().body.requester_id=="987","Consent response binds the native requester's identity")
	var visit:=launch.duplicate(true);visit.ship={"id":"88","template":"object/ship/player/player_sorosuub_space_yacht.iff","kind":"pob","station":"interior","position":[20,0,0],"quaternion":[0,0,0,1],"player_position":[0,.4,20],"cell_index":1,"stations":[],"crew":[],"commands":[]}
	visit.boarding.return_ship={"ship_id":"99","device_id":"98","host_ship_id":"88"}
	check(flight.observe(visit,6) and flight.scene.ship_id=="88" and flight.scene.stage.definitions.has("88:1"),"Approved guest transfer replaces cockpit with actual destination ship's original cells")
	check(host.player.get_camera().transform.is_equal_approx(hmd),"Guest boarding preserves tracked HMD local pose")
	host.response=receipt(launch,7);await flight.request("return_ship")
	check(flight.scene.ship_id=="77" and is_instance_valid(flight.scene.cockpit),"Acknowledged return restores original own-ship cockpit without ground teleport")
	host.menu=PanelContainer.new();host.add_child(host.menu);host.menu.show()
	host.response={"ok":false,"error":"jtl_pilot_required"};await flight.request("control",{"throttle":0,"pitch":0,"yaw":0,"roll":0,"sequence":1})
	check(flight.needs_reconcile,"Unstructured control rejection requests authoritative status resynchronization")
	host.response=receipt(visit,8);flight.poll=0;flight._process(.1);await process_frame;await process_frame
	check(host.calls.back().path=="/jtl/status" and flight.scene.ship_id=="88" and flight.station=="interior" and not flight.needs_reconcile,"Rejected old-pilot heartbeat polls status and enters the newly approved host ship")
	var eject:=receipt(ground,9,false);eject.error="Pilot disconnected";eject.live_response.snapshot={"player":{"zone":"tatooine","position":[3512,5,-4810],"building_id":"0","cell_index":0}}
	var delayed:=eject.duplicate(true);delayed.live_response.sequence=1
	host.response=delayed;await flight.request("status")
	check(flight.aboard() and host.landings.is_empty(),"Stale ground receipt cannot eject a more recent native ship state")
	host.response=eject;await flight.request("control",{"throttle":0,"pitch":0,"yaw":0,"roll":0,"sequence":1})
	check(not flight.aboard() and host.landings.size()==1 and host.landings[0].destination.position==[3512,5,-4810],"Rejected control after forced ejection still loads native ground starport destination")
	host.world_ready=true;var guest:=ground.duplicate(true);guest.boarding.return_ship={"ship_id":"99","device_id":"98","host_ship_id":"77"};flight.observe(guest,10)
	check(host.datapad.ui.ships.any(func(row):return row.get("temporary_return",false) and not row.get("deletable",true)),"Native visit creates a temporary own-ship return entry")
	flight.observe(ground,11);check(not host.datapad.ui.ships.any(func(row):return row.get("temporary_return",false)),"Return entry disappears with native visit state")
	host.free();stage.free();panel.free()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"geometry":"original yacht and eleven original small craft cockpits","renderer":"dummy","live_core3":false,"live_xr":false}));quit(0 if failures.is_empty() else 1)
