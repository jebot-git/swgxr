extends SceneTree
const Preferences=preload("res://space/preferences.gd")
const Controls=preload("res://space/flight_input.gd")
const Scene=preload("res://space/scene.gd")
const Controller=preload("res://space/controller.gd")
class Host extends Node:
	var datapad_character_id:="123"
	var datapad:Node
class FullHost extends "res://scripts/main.gd":
	var response:Dictionary={}
	var ship_calls:Array=[]
	var landings:Array=[]
	func perform_service_transport(value:Dictionary)->bool:
		landings.append(value.duplicate(true));return true
	func api(_method:HTTPClient.Method,path:String,body:Dictionary={})->Dictionary:
		ship_calls.append({"path":path,"body":body.duplicate(true)})
		await get_tree().process_frame
		return response.duplicate(true)
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
class NativeSession extends Node:
	var live:=true
	var session_id:="owned-native-session"
	var sequence:=-1
	func accept_native_response(value:Dictionary)->bool:
		sequence=int(value.get("sequence",-1));return true
class Pad extends Node3D:
	var ui=preload("res://scripts/datapad_ui.gd").new()
	var is_open:=false
	func _ready()->void:add_child(ui);add_child(ui.take_detail_panel())
	func set_open(value:bool)->void:is_open=value
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	check(load("res://scripts/main.gd")!=null,"Integrated main script compiles")
	var invisible:ShaderMaterial=preload("res://scripts/stage_loader.gd").new().make_material({"source_invisible":true},"")
	check(invisible.shader.resource_path=="res://shaders/source_invisible.gdshader","Original invisible collidable effect is rendered with explicit discard")
	var settings:=Preferences.new();settings.mode="virtual_hotas"
	var controls:=Controls.new()
	var seat:=Transform3D.IDENTITY
	var left:=Transform3D(Basis.IDENTITY,Vector3(-.28,.6,-.32))
	var right:=Transform3D(Basis.IDENTITY,Vector3(.28,.6,-.32))
	var original_left:=left;var original_right:=right
	controls.sample(settings,true,left,right,0,0,Vector2.ZERO,Vector2.ZERO,seat,.016)
	var captured:Dictionary=controls.sample(settings,true,left,right,1,1,Vector2.ZERO,Vector2.ZERO,seat,.016)
	check(controls.stick_held and controls.throttle_held and captured.pitch==0,"Grip captures near authored seat controls")
	right.basis=Basis(Vector3.RIGHT,deg_to_rad(-25));left.origin.z-=.28
	var moved:Dictionary=controls.sample(settings,true,left,right,1,1,Vector2.ZERO,Vector2.ZERO,seat,.016)
	check(moved.pitch>.99 and moved.throttle>.99,"Virtual stick rotation and throttle travel produce bounded input")
	check(original_left.origin==Vector3(-.28,.6,-.32) and original_right.basis==Basis.IDENTITY,"Control input does not overwrite tracked poses")
	var lost:Dictionary=controls.sample(settings,false,left,right,1,1,Vector2.ZERO,Vector2.ZERO,seat,.016)
	check(lost.throttle==0 and lost.pitch==0 and not controls.stick_held,"Tracking loss cuts thrust and drops captures")
	controls.sample(settings,true,left,right,1,1,Vector2.ZERO,Vector2.ZERO,seat,.016)
	check(not controls.stick_held,"Tracking recovery needs deliberate grip release")
	settings.mode="motion_sticks"
	var sticks:Dictionary=controls.sample(settings,true,left,right,0,0,Vector2(1,-1),Vector2(1,-1),seat,.1)
	check(sticks.pitch==1 and sticks.roll==-1 and sticks.yaw==1 and sticks.throttle>0,"Motion controller axes map flight without moving avatar")
	settings.mode="physical_hotas";settings.inverted.pitch=true
	var hotas:Dictionary=controls.sample(settings,false,left,right,0,0,Vector2.ZERO,Vector2.ZERO,seat,.1,{"available":true,"pitch":.8,"yaw":.03,"roll":-1,"throttle":1})
	check(hotas.pitch>0 and hotas.yaw==0 and hotas.roll==1 and hotas.throttle==1,"Physical HOTAS inversion, deadzone and absolute throttle work independently of grips")
	check(controls.sample(settings,true,left,right,0,0,Vector2.ZERO,Vector2.ZERO,seat,.1,{}).throttle==0,"Disconnected HOTAS produces neutral controls")
	settings.path="/tmp/swgxr-flight-smoke.cfg";settings.axes.pitch=4;settings.axis_devices.throttle=2;settings.save_preferences()
	var restored:=Preferences.new();restored.path=settings.path;restored.load_preferences()
	check(restored.axes.pitch==4 and restored.axis_devices.throttle==2 and restored.mode==settings.mode and restored.inverted.pitch,"Flight hardware configuration survives reload")
	DirAccess.remove_absolute(settings.path)
	var scene:=Scene.new();root.add_child(scene);scene.position=Vector3(0,10000,0)
	check(scene.ready_assets(),"Original yacht asset catalog is available")
	if scene.ready_assets():
		check(scene.build("123456789"),"Original yacht loads through production native mesh/floor builders")
		if is_instance_valid(scene.stage):
			check(is_instance_valid(scene.exterior) and scene.exterior.find_children("*","StaticBody3D",true,false).is_empty(),"Original Tatooine station is visible navigation geometry without fictional docking collision")
			check(scene.stage.definitions.size()>=11,"Original yacht interior cells retained")
			check(scene.stage.definitions.has("123456789:1"),"Persistent native ship ID replaces exporter fixture ID")
			var world:Vector3=scene.world([-.76,.43,21.14])
			var source:Array=scene.source(world)
			check(Vector3(source[0],source[1],source[2]).distance_to(Vector3(-.76,.43,21.14))<.001,"Ship source/world conversion round-trips cockpit position")
			var support:Dictionary=scene.stage.ground_support.sample_support(world,["123456789:1"],2.0,2.0,{})
			check(support.get("valid",false),"Actual bridge floor supports the pilot spawn")
	var host:=Host.new();root.add_child(host)
	var controller:=Controller.new();host.add_child(controller);controller.set_process(false);controller.app=host
	var authoritative:Dictionary={"enabled":true,"scope":"noncombat_yacht","source_kind":"core3_jtl","character_id":"123","ships":[],"ship":{"station":"ground"}}
	check(controller.observe(authoritative,10),"Owned authoritative ground ship snapshot accepted")
	var empty:=authoritative.duplicate(true);empty.ship=null
	check(controller.observe(empty,10) and controller.ship.is_empty(),"Accounts without an entitled yacht accept native null ship safely")
	var foreign:=authoritative.duplicate(true);foreign.character_id="456"
	check(not controller.observe(foreign,11),"Another character's ship snapshot rejected")
	check(not controller.observe(authoritative,9) and controller.revision==10,"Older ship receipt cannot rewind the newer state")
	var ui:=preload("res://scripts/datapad_ui.gd").new();root.add_child(ui);root.add_child(ui.take_detail_panel())
	ui.set_ships([{"id":"99","category":"ships","type":"ship","name":"Luxury Yacht","launched":false}]);ui.select_category("ships")
	check(ui.filtered_entries.size()==1,"Native yacht is discoverable in Ships datapad tab")
	ui.select_entry(0)
	check(ui.vehicle_button.visible and ui.vehicle_button.text=="Prepare launch","Ship action is distinct from vehicle call")
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	panel.configure({"id":"555","kind":"starship","ships":[{"id":"99","name":"Luxury Yacht","eligible":true}]},{})
	var launch_calls:Array=[];panel.action_requested.connect(func(action,payload):launch_calls.append([action,payload]))
	panel.selected=0;panel.confirm()
	check(launch_calls.size()==1 and launch_calls[0][0]=="jtl_launch" and launch_calls[0][1].terminal_id=="555","Original starship terminal launch retains native terminal identity")
	var full:=FullHost.new();root.add_child(full);full.datapad_character_id="123";full.datapad_epoch=1
	full.xr_origin=load("res://xr/player_rig.tscn").instantiate();full.add_child(full.xr_origin);full.player=full.xr_origin.get_node("PlayerBody");full.player.set_physics_process(false);full.player.set_process(false)
	full.stage=preload("res://scripts/cell_stage.gd").new();full.add_child(full.stage);full.player.ground_provider=full.stage
	full.datapad=Pad.new();full.add_child(full.datapad)
	var old_stage:Node3D=full.stage;var old_origin:Transform3D=full.xr_origin.global_transform
	var tracked_camera:Transform3D=full.player.get_camera().transform
	var flight:=Controller.new();full.add_child(flight);flight.setup(full,settings);flight.set_process(false);full.space=flight
	var launched:=authoritative.duplicate(true);launched.ship={"id":"123456789","station":"pilot","position":[100,200,300],"quaternion":[0,0,0,1],"player_position":[-.76,.93,21.14],"cell_index":1,"decorations":[],"stations":[],"commands":[]}
	check(flight.observe(launched,12) and flight.seated(),"Owned native launch enters production original interior and pilot station")
	check(not full.datapad.ui.professions.forgetting_available,"Forget is unavailable aboard while native learned skills remain intact")
	check(full.stage!=old_stage and full.player.ground_provider==full.stage and not old_stage.visible,"Interior replaces ground support while preserving ground scene")
	check(full.player.get_camera().transform.is_equal_approx(tracked_camera),"Pilot boarding preserves tracked camera's local transform")
	var interior:=launched.duplicate(true);interior.ship.station="interior";interior.ship.player_position=[0,.4,20]
	check(flight.observe(interior,13) and not flight.seated() and flight.aboard(),"Native leave permits original-floor POB locomotion")
	check(absf(full.player.global_position.y-10000.4)<.002,"Native bridge position is placed in isolated space frame")
	full.gameplay_session=NativeSession.new();full.add_child(full.gameplay_session)
	var pilot_station:Dictionary={"id":"pilot","cell_index":1,"position":[-.76,.43,21.14],"occupied_by":"0"}
	interior.ship.owner_id="123";interior.ship.stations=[pilot_station]
	flight.observe(interior,13)
	check(flight.command_rows().is_empty() and not flight.button("primary_click",full.player.dominant_hand) and not flight.wheel.opened,"Walking in the interior cannot open flight commands or consume the equipment shortcut")
	flight.show_station_targets(true)
	check(flight.station_labels.pilot.visible and "Take pilot seat" in flight.station_labels.pilot.text,"Reachable original pilot chair exposes its own visible seat target")
	var aim_origin:=full.player.global_position+Vector3(0,1.5,1)
	var seat_point:Vector3=flight.scene.world(pilot_station.position)+Vector3(0,.95,0)
	var seat_target:=flight.station_target({"ray_origin":aim_origin,"direction":(seat_point-aim_origin).normalized()},aim_origin)
	check(not seat_target.is_empty() and aim_origin.distance_to(seat_point)>.65,"Shared controller aim selects pilot seat without reaching into chair")
	check(flight.station_target({"ray_origin":aim_origin,"direction":Vector3.UP},aim_origin).is_empty(),"Pointing away from seat cannot select it")
	var occupied:=pilot_station.duplicate(true);occupied.occupied_by="987"
	check(not flight.station_option(occupied).available,"Another occupant cannot be displaced through pilot command")
	flight.ship.owner_id="987";check(not flight.station_option(pilot_station).available,"Guest cannot take owner's pilot station");flight.ship.owner_id="123"
	var wrong_room:=pilot_station.duplicate(true);wrong_room.cell_index=2
	check(not flight.station_option(wrong_room).available,"Station in another native room remains unavailable")
	var distant:=pilot_station.duplicate(true);distant.position=[0,.4,10]
	check(not flight.station_option(distant).available,"Command cannot board a distant chair")
	flight.busy=true
	full.response={"ok":true,"source_kind":"core3_jtl","character_id":"123","state":launched,"mutation":{"success":true},"live_response":{"sequence":14}}
	var seat_calls:=full.ship_calls.size()
	flight.command("station:pilot")
	check(flight.interaction_waiting and full.ship_calls.size()==seat_calls,"Deliberate reseat queues behind a walking update instead of being dropped")
	await process_frame;flight.busy=false
	await process_frame;await process_frame;await process_frame
	check(full.ship_calls.size()==seat_calls+1 and full.ship_calls.back().path=="/jtl/station" and full.ship_calls.back().body.station_id=="pilot","Queued pilot-seat request is dispatched exactly once after heartbeat completes")
	check(flight.seated() and flight.station=="pilot" and full.player.get_camera().transform.is_equal_approx(tracked_camera),"Native reseat acknowledgement restores controls without changing tracked HMD local pose")
	check(not flight.command_rows().any(func(row):return str(row.id).begins_with("station:")),"Already seated player is offered Leave rather than another seat request")
	check(flight.button("primary_click",full.player.dominant_hand) and flight.wheel.opened,"Pilot can deliberately open flight commands")
	var copilot:=interior.duplicate(true);copilot.ship.station="passenger"
	check(flight.observe(copilot,14) and not flight.wheel.opened,"Changing stations closes the prior seat's wheel")
	check(flight.button("primary_click",full.player.dominant_hand) and flight.wheel.opened,"Seated copilot can open command wheel")
	check(not flight.command_rows().filter(func(row):return row.id=="land")[0].available,"Copilot wheel preserves native pilot-only landing permission")
	flight.observe(interior,14);flight.scene.place_player(full.player,[0,.4,10],1)
	seat_calls=full.ship_calls.size();flight.command("station:pilot")
	check(full.ship_calls.size()==seat_calls and flight.error=="Move closer to the seat.","Stale open menu rechecks reach at selection and reports why seat is unavailable")
	check(not flight.wheel.opened,"Native seat exit dismisses an already open flight wheel")
	flight.scene.place_player(full.player,[0,.4,20],1)
	full.inventory=preload("res://scripts/xr_inventory.gd").new();full.add_child(full.inventory);full.inventory.configure(full.xr_origin,full.player);full.inventory.set_process(false);full.inventory.set_allowed(true)
	full.housing=preload("res://housing/controller.gd").new();full.add_child(full.housing);full.housing.set_process(false);full.housing.app=full;full.housing.bag=full.inventory
	var item:Dictionary={"id":"knife","template":"object/weapon/melee/knife/knife_stone.iff","name":"Stone knife","equippable":true}
	full.inventory.take_item(item);full.inventory.begin_mutation("Dropping item…")
	full.response={"ok":true,"source_kind":"core3_jtl","character_id":"123","state":interior,"mutation":{"success":true},"live_response":{"sequence":14}}
	flight.busy=true;var drop_calls:=full.ship_calls.size()
	check(flight.try_drop(item,Transform3D(Basis.IDENTITY,full.player.global_position)) and flight.interaction_waiting and full.inventory.action_pending,"Ship placement queues behind walking update and keeps mutation pending")
	await process_frame;flight.busy=false;await process_frame;await process_frame;await process_frame
	check(full.ship_calls.size()==drop_calls+1 and full.ship_calls.back().path=="/jtl/decorate","Queued item drop sends exactly one native decoration request")
	check(full.inventory.held_item.is_empty() and not full.inventory.action_pending and full.inventory.ui.status.is_empty(),"Confirmed placement clears item, pending state and obsolete Dropping item message")
	full.inventory.take_item(item);full.inventory.begin_mutation("Dropping item…")
	full.response={"ok":false,"error":"Placement reply timed out; check inventory before retrying."}
	flight.try_drop(item,Transform3D(Basis.IDENTITY,full.player.global_position));await process_frame;await process_frame
	check(not full.inventory.held_item.is_empty() and not full.inventory.action_pending and not full.inventory.mutation_pending and "timed out" in full.inventory.ui.status,"Unconfirmed placement retains item and replaces pending message with the actual failure")
	drop_calls=full.ship_calls.size();await process_frame
	check(full.ship_calls.size()==drop_calls,"Uncertain placement does not replay automatically")
	check(flight.observe(authoritative,14) and not flight.aboard() and full.stage==old_stage and old_stage.visible,"Native land restores exact prior ground stage and presentation")
	check(full.datapad.ui.professions.forgetting_available,"Landing restores native skill eligibility presentation")
	check(full.xr_origin.global_transform.is_equal_approx(old_origin) and full.player.get_camera().transform.is_equal_approx(tracked_camera),"Landing restores ground origin without changing tracked HMD pose")
	full.response={"ok":true,"source_kind":"core3_jtl","character_id":"123","state":authoritative,"mutation":{"success":true},"live_response":{"sequence":15}}
	await flight.request("status")
	check(full.ship_calls.back().path=="/jtl/status" and full.ship_calls.back().body.session_id=="owned-native-session" and full.gameplay_session.sequence==15,"REST ship action binds owned native session and consumes returned authority heartbeat")
	full.response.live_response={"sequence":16,"snapshot":{"player":{"zone":"tatooine","position":[3500,5,-4800],"building_id":"0","cell_index":0}}}
	await flight.request("land")
	check(full.landings.size()==1 and full.landings[0].destination.position==[3500,5,-4800],"Landing loads the actual native ground destination rather than cached prelaunch pose")
	full.response={"ok":false,"error":"Connection lost"}
	await flight.request("command",{"command_id":"shield_balance"})
	var unconfirmed_id:String=full.ship_calls.back().body.request_id
	await flight.request("command",{"command_id":"shield_balance"})
	check(full.ship_calls.back().body.request_id==unconfirmed_id,"Unknown mutation outcome retains stable replay identity")
	var before:int=full.ship_calls.size()
	await flight.request("launch")
	check(full.ship_calls.size()==before and "terminal" in flight.error,"Datapad cannot bypass reachable native starship terminal")
	full.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"geometry":"original yacht","controls":"synthetic tracked poses","live_core3":false,"live_xr":false}
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
