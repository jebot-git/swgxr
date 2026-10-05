extends SceneTree
## Real coordinator and UI with asynchronous native API fixtures, XR disabled.
const Coordinator=preload("res://scripts/services_controller.gd")
const ServiceUI=preload("res://scripts/xr_services.gd")
class Stage extends Node3D:
	var current_cell: Dictionary={"building_object_id":"100","cell_id":"100:2"}
class Inventory extends Node3D:
	var held_item: Dictionary={}
	var taken: Array=[]
	func set_open(_value: bool) -> void: pass
	func take_item(item: Dictionary) -> void:
		held_item=item.duplicate(true);taken.append(item.duplicate(true))
class Crafting extends Node:
	var activations: Array=[]
	func activate(item: Dictionary) -> void:
		activations.append(item.duplicate(true));await get_tree().process_frame
class Live extends Node:
	var live:=false
	var session_id:="session-1"
	var sequence:=1
	var accepted:=0
	var last_error:="invalid live envelope"
	var failure:=""
	func accept_response(response: Dictionary) -> bool:
		accepted+=1;sequence=int(response.sequence);return true
	func fail(message: String) -> void: failure=message
class Scenery extends Node3D:
	var rows: Array=[]
	func advance(_delta: float) -> void: pass
	func reset() -> void: rows=[]
	func configure(_origin: Vector3) -> void: pass
	func apply_snapshot(_state: Dictionary,_position: Vector3) -> void: pass
	func boarding_rows() -> Array:
		return rows.filter(func(row): return bool(row.get("boarding",false)))
class Host extends Node3D:
	signal release_api
	var datapad_account:="fixture"
	var datapad_character_id:="1000"
	var datapad_epoch:=1
	var xr_requested:=true
	var xr_origin: XROrigin3D
	var vr_settings: Dictionary={"offhand":"left"}
	var player: CharacterBody3D
	var stage: Node3D
	var tracked_avatar: Node3D
	var datapad: Node3D
	var inventory: Node3D
	var combat_rig: Node3D
	var crafting: Node
	var live_combat: Node
	var loader: Dictionary={"report":{"origin":[3500,5,-4800]}}
	var inventory_snapshot: Dictionary={}
	var calls: Array=[]
	var transports: Array=[]
	var owned: Dictionary={"id":"900","tool_kind":"crafting","name":"Source crafting tool"}
	var next_response: Dictionary={}
	var hold_next:=false
	var reconciled:=0
	var background_allowed:=true
	var background_families: Array=[]
	func try_background_poll(family: String) -> bool:
		background_families.append(family);return background_allowed
	func source_position_at(point: Vector3) -> Vector3:
		return Vector3(point.x+3500,point.y+5,-4800-point.z)
	func reconcile_inventory_presentations() -> void: reconciled+=1
	func update_inventory_presentation() -> void: pass
	func owned_inventory_item(id: String) -> Dictionary: return owned if id==owned.id else {}
	func response() -> Dictionary:
		return {"ok":true,"source_kind":"core3_services","character_id":datapad_character_id,
			"state":{"character_id":datapad_character_id,"wallet":{"cash":800,"bank":1200},"terminal":{"id":"10","kind":"bank","name":"Bank"},"terminals":[]},"mutation":{"success":true}}
	func api(_method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		var result:=next_response.duplicate(true) if not next_response.is_empty() else response()
		next_response={}
		var wait:=hold_next;hold_next=false
		if wait: await release_api
		await get_tree().process_frame
		return result
	func perform_service_transport(transport: Dictionary) -> void:
		transports.append(transport.duplicate(true));await get_tree().process_frame
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func frames(count: int=4) -> void:
	for _frame in range(count): await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Host.new();root.add_child(host)
	host.xr_origin=XROrigin3D.new();host.add_child(host.xr_origin)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";host.xr_origin.add_child(camera);camera.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;host.xr_origin.add_child(hand)
	host.player=CharacterBody3D.new();host.add_child(host.player)
	host.stage=Stage.new();host.add_child(host.stage);host.stage.set_meta("manifest",{"origin":[3500,5,-4800]})
	host.inventory=Inventory.new();host.add_child(host.inventory)
	host.crafting=Crafting.new();host.add_child(host.crafting)
	host.live_combat=Live.new();host.add_child(host.live_combat)
	var coordinator:=Coordinator.new();host.add_child(coordinator);coordinator.set_process(false)
	coordinator.app=host;coordinator.epoch=host.datapad_epoch
	var ui:=ServiceUI.new();host.add_child(ui);ui.configure(host.xr_origin,host.player);ui.set_process(false)
	coordinator.ui=ui;coordinator.set_allowed(true)
	ui.action_requested.connect(coordinator.request)
	ui.opened.connect(coordinator.interface_opened)
	ui.open_terminal({"id":"10","kind":"bank","position":Vector3(0,0,-1)})
	await frames()
	check(host.calls.size()==1 and host.calls[0].path=="/services/open","Terminal open reaches expected native route once")
	check(not coordinator.busy and ui.wallet.cash==800,"Native response unlocks and applies confirmed wallet")
	var identity: Dictionary=host.calls[0].payload
	check(identity.account=="fixture" and identity.character_id=="1000" and identity.building_id=="100" and identity.cell_index==2,"Native request carries account, character, and original cell membership")
	check(not str(identity.request_id).is_empty(),"Mutation envelope has request identity")
	ui.panel.pointer_begin(Vector2(172,332));ui.panel.pointer_move(Vector2(428,332))
	host.hold_next=true
	coordinator.request("status",{"terminal_id":"10"})
	check(ui.panel.pointer_down and ui.panel.slider.dragging and not ui.pending,"Idle status does not cancel active physical drag")
	host.release_api.emit();await frames()
	check(ui.panel.pointer_down and ui.panel.slider.amount==400,"Unchanged native poll preserves amount proposal")
	ui.panel.pointer_end(Vector2(428,332))
	host.hold_next=true
	coordinator.request("status",{"terminal_id":"10"})
	var before:=host.calls.size()
	coordinator.request("bank_transfer",{"terminal_id":"10","direction":"deposit","amount":400})
	coordinator.request("bank_transfer",{"terminal_id":"10","direction":"deposit","amount":400})
	check(host.calls.size()==before and not coordinator.queued_action.is_empty(),"Mutation waits behind one in-flight native read")
	host.release_api.emit();await frames(8)
	check(host.calls.size()==before+1 and host.calls.back().path=="/services/bank_transfer","Queued user mutation submits exactly once")
	check(host.calls.back().payload.amount==400 and not coordinator.busy and coordinator.queued_action.is_empty(),"Queued action retains proposal and clears flight state")
	var invalid:=host.response();invalid.source_kind="local_fixture"
	check(not coordinator.accept_response(invalid),"Non-Core3 service source rejected")
	invalid=host.response();invalid.character_id="other"
	check(not coordinator.accept_response(invalid),"Wrong envelope character rejected")
	invalid=host.response();invalid.state.character_id="other"
	check(not coordinator.accept_response(invalid),"Wrong nested state character rejected")
	var cash_before: int=ui.wallet.cash
	host.hold_next=true;coordinator.request("status")
	host.datapad_epoch+=1;host.datapad_character_id="2000";coordinator.reset();coordinator.set_allowed(true)
	host.release_api.emit();await frames()
	check(coordinator.state.is_empty() and ui.wallet.cash==cash_before,"Late old-character response cannot update current state")
	check(not coordinator.busy,"Session reset clears busy while old reply is discarded")
	host.next_response={"ok":false,"error":"Core3 unavailable"};host.hold_next=true;coordinator.request("status")
	before=host.calls.size()
	coordinator.request("pay",{"target_id":"3000","amount":50})
	host.release_api.emit();await frames(6)
	check(host.calls.size()==before and coordinator.queued_action.is_empty(),"Failed prerequisite read cancels queued economic mutation")
	check(ui.panel.message=="Core3 unavailable" and not ui.pending,"Native failure is visible and does not hang UI")
	var reply:=host.response();reply.transport={"id":"travel-1","destination":{"zone":"tatooine","position":[3600,5,-4700],"building_id":"0","cell_index":0}}
	host.next_response=reply
	await coordinator.request("travel_board",{"terminal_id":"600","ticket_id":"700"})
	check(host.transports.size()==1 and host.transports[0].id=="travel-1","Confirmed native travel uses source destination placement")
	check(host.calls.back().payload.ticket_id=="700","Travel retains actual native ticket identity")
	check(ui.terminal.is_empty(),"Accepted boarding closes local chooser")
	host.live_combat.live=true
	reply=host.response();reply.transport={"id":"travel-2","destination":{"zone":"tatooine","position":[3700,5,-4650]}}
	reply.live_response={"session_id":"session-1","sequence":2}
	host.next_response=reply
	await coordinator.request("travel_board",{"terminal_id":"600","ticket_id":"701"})
	check(host.transports.size()==1 and host.live_combat.accepted==1,"Live travel delegates newer authoritative envelope to existing transport flow without duplicate placement")
	reply=host.response();reply.live_response={"session_id":"stale","sequence":100}
	coordinator.accept_response(reply)
	check(host.live_combat.accepted==1,"Different live-session response cannot alter active session")
	host.live_combat.live=false
	reply=host.response();reply.inventory={"source_kind":"core3_inventory","character_id":"2000","items":[]}
	coordinator.accept_response(reply)
	check(host.reconciled==1,"Native same-character inventory refresh reconciles item presentation")
	host.live_combat.live=true
	var authoritative_state:=coordinator.state.duplicate(true)
	var stale_inventory:=reply.duplicate(true)
	stale_inventory.live_response={"session_id":"session-1","sequence":1}
	stale_inventory.inventory.items=[{"id":"cancelled-parcel"}]
	stale_inventory.state.parcels=[{"id":"cancelled-parcel"}]
	coordinator.accept_response(stale_inventory)
	check(host.reconciled==1 and host.inventory_snapshot.items.is_empty() and coordinator.state==authoritative_state,"Older native receipt cannot resurrect cancelled parcel inventory or service projection")
	host.live_combat.live=false
	reply.inventory.character_id="wrong";coordinator.accept_response(reply)
	check(host.reconciled==1,"Wrong-character inventory ignored")
	await coordinator.request("crafting_station",{"terminal_id":"11","tool_id":"900"})
	check(host.inventory.taken.size()==1 and host.crafting.activations.size()==1,"Confirmed station selection draws owned tool and activates existing crafting flow")
	check(host.crafting.activations[0].id=="900","Crafting uses selected source inventory item")
	await coordinator.use_crafting_tool("missing")
	check(host.crafting.activations.size()==1,"Missing/unowned station tool cannot activate crafting")
	coordinator.peers=[{"id":"3000","fresh":true,"authenticated":true}];coordinator.presence_age=0.1
	check(coordinator.remote_hands().size()==1,"Fresh authenticated presence available for handshake UI")
	coordinator.presence_age=0.9
	check(coordinator.remote_hands().is_empty(),"Stale remote tracking hidden after freshness deadline")
	var transformed:=coordinator.world([3510,7,-4803])
	check(transformed.is_equal_approx(Vector3(10,2,3)),"Source terminal positions retain manifest origin and SWG Z reflection")
	coordinator.state={"terminals":[{"id":"12","kind":"mission","position":[3510,7,-4803],"building_id":"100","cell_index":2},{"id":"bad","position":[1,2]}]}
	check(coordinator.terminal_records().size()==1 and coordinator.terminal_records()[0].position==transformed,"Only valid source terminal locations become interaction records")
	coordinator.state_age=0
	coordinator.state.terminals.append({"id":"outside","kind":"bank","position":[3510,7,-4803],"building_id":"0","cell_index":0})
	coordinator.state.terminals.append({"id":"other-room","kind":"bank","position":[3510,7,-4803],"building_id":"100","cell_index":3})
	check(coordinator.terminal_records().size()==1,"Co-located terminals in other cells or outdoors cannot be opened through walls")
	coordinator.state_age=8.01
	check(coordinator.terminal_records().is_empty(),"Expired native terminal discovery cannot authorize opening")
	coordinator.state_age=0
	coordinator.poll_clock=100;coordinator.presence_clock=100
	ui.terminal={"id":"12","kind":"mission"};ui.surface.visible=true
	coordinator._process(0.01)
	check(not ui.terminal.is_empty(),"Fresh same-cell active terminal remains open")
	host.stage.current_cell={"building_object_id":"100","cell_id":"100:3"}
	coordinator._process(0.01)
	check(ui.terminal.is_empty(),"Leaving original cell closes terminal even at identical world position")
	host.stage.current_cell={"building_object_id":"100","cell_id":"100:2"}
	ui.terminal={"id":"12","kind":"mission"};ui.surface.visible=true
	coordinator.state_age=7.99;coordinator._process(0.02)
	check(not ui.terminal.is_empty(),"Background refresh delay preserves already-open static terminal; mutations remain native")
	host.stage.current_cell={"building_object_id":"100","cell_id":"100:3"};coordinator._process(.01)
	check(ui.terminal.is_empty(),"Delayed refresh does not bypass cell departure closure")
	host.stage.current_cell={"building_object_id":"100","cell_id":"100:2"}
	var scenery:=Scenery.new();host.add_child(scenery);coordinator.scenery=scenery
	var shuttle: Dictionary={"id":"600","position":[3500,5,-4800],"door_position":[3500,5,-4800],"departure":"Mos Eisley","landed":true,"doors_open":true,"boarding":true,"boarding_radius":1.2}
	scenery.rows=[shuttle];coordinator.state_age=0
	coordinator.state={"tickets":[{"id":"700","usable":true,"departure":"Mos Eisley","arrival":"Mos Espa"},{"id":"701","usable":true,"departure":"Mos Eisley","arrival":"Bestine"},{"id":"702","usable":true,"departure":"Bestine","arrival":"Mos Eisley"},{"id":"703","usable":false,"departure":"Mos Eisley"}]}
	coordinator.have_previous=true;coordinator.previous_position=Vector3(2,0,0);host.player.position=Vector3(1,0,0)
	before=host.calls.size();coordinator._process(0.01)
	check(ui.terminal.get("kind","")=="boarding" and ui.panel.rows.size()==2,"Door crossing filters chooser to usable tickets for native departure point")
	check(host.calls.size()==before,"Multiple-ticket chooser never auto-submits boarding")
	ui.panel.selected=1
	coordinator.state.tickets=[coordinator.state.tickets[1]];coordinator._process(0.01)
	check(ui.panel.rows.size()==1 and ui.panel.selected==0 and ui.panel.rows[0].id=="701","Fresh snapshot removes consumed ticket while retaining selected native identity")
	check(host.calls.size()==before,"Snapshot shrink to one ticket does not initiate travel")
	scenery.rows=[];coordinator._process(0.01)
	check(ui.terminal.is_empty(),"Missing native shuttle closes open ticket chooser")
	scenery.rows=[shuttle];ui.boarding_latch=""
	ui.offer_boarding(shuttle,[{"id":"700","usable":true},{"id":"701","usable":true}])
	scenery.rows[0].boarding=false;coordinator._process(0.01)
	check(ui.terminal.is_empty(),"Native departure closes chooser when original boarding state ends")
	scenery.rows[0].boarding=true;ui.boarding_latch=""
	ui.offer_boarding(shuttle,[{"id":"700","usable":true},{"id":"701","usable":true}])
	coordinator.state_age=2.49;coordinator._process(0.02)
	check(ui.terminal.is_empty(),"Stale shuttle state closes ticket chooser before another input")
	coordinator.state_age=0;scenery.rows=[]
	var categories: Array=preload("res://tests/bazaar_tree_smoke.gd").source_categories()
	var bazaar_record: Dictionary={"id":"20","kind":"bazaar","name":"Bazaar","categories":categories,"listings":[{"id":"850","name":"Native weapon fixture","price":100,"buy_eligible":true}],"category_id":0,"page":0,"has_more":false}
	ui.terminal=bazaar_record.duplicate(true);ui.terminal.position=Vector3.ZERO;ui.panel.configure(bazaar_record,{"cash":800,"bank":1200})
	ui.panel.category_offset=12
	var weapon_index:=-1
	for index in range(ui.panel.category_rows.size()):
		if int(ui.panel.category_rows[index].id)==131072: weapon_index=index
	reply=host.response();reply.state.terminal=bazaar_record.duplicate(true);reply.state.terminal.category_id=131072
	reply.state.terminals=[{"id":"20","kind":"bazaar","position":[3500,5,-4800],"building_id":"100","cell_index":2}]
	host.next_response=reply;ui.panel.select_category(weapon_index);await frames()
	check(ui.panel.category_id==131072 and ui.panel.category_path.size()==1,"Actual coordinator preserves selected source browse path after filter response")
	ui.panel.selected=0;host.next_response=reply;ui.panel.confirm();await frames()
	check(host.calls.back().path=="/services/bazaar_buy" and host.calls.back().payload.category_id==131072,"Bazaar mutation carries selected source tree context through coordinator")
	check(ui.panel.category_path.size()==1 and ui.panel.category_name=="Weapon","Mutation refresh retains source tree path and Back history")
	host.next_response=reply;coordinator.poll_clock=0;coordinator.presence_clock=100;coordinator._process(0.01);await frames()
	check(host.calls.back().path=="/services/status" and host.calls.back().payload.category_id==131072,"Automatic status poll retains selected bazaar category")
	check(ui.panel.category_path.size()==1,"Read-only refresh does not clear browse Back history")
	reply.state.terminal.category_id=0;host.next_response=reply;ui.panel.category_back();await frames()
	check(ui.panel.category_id==0 and ui.panel.category_path.is_empty() and ui.panel.category_offset==12 and ui.panel.category_selected==weapon_index,"Back after mutation and status restores original parent selection and scroll")
	host.stage.transform=Transform3D(Basis(Vector3.UP,0.5),Vector3(10,2,-20))
	check(coordinator.world([3510,7,-4803]).is_equal_approx(host.stage.to_global(Vector3(10,2,3))),"World conversion preserves non-identity stage transform after source-origin reflection")
	ui.terminal={}
	check(coordinator.services_poll_interval({"shuttles":[{"position":[6000,5,-4800]}]})==5.0,"Distant planetary shuttles keep services at idle poll cadence")
	check(coordinator.services_poll_interval({"shuttles":[{"position":[3500,5,-4800]}]})==1.0,"Nearby boarding site uses fast native phase polling")
	ui.terminal={"kind":"bank"}
	check(coordinator.services_poll_interval({})==5.0,"Static terminal menus do not force repeated one-second native logins")
	ui.terminal={"kind":"travel"}
	check(coordinator.services_poll_interval({})==1.0,"Travel interface requests timely native shuttle phase observations")
	ui.terminal={};coordinator.poll_clock=0;coordinator.presence_clock=100
	host.background_allowed=false
	var before_calls:=host.calls.size()
	coordinator._process(.01);await frames()
	check(host.calls.size()==before_calls and coordinator.poll_clock<=0 and host.background_families.back()=="services","Denied automatic services poll retains expired clock without HTTP request")
	host.background_allowed=true;coordinator._process(.01);await frames()
	check(host.calls.size()==before_calls+1 and host.calls.back().path=="/services/status","Granted background slot sends one services status request")
	host.background_allowed=false;before_calls=host.calls.size()
	await coordinator.request("open",{"terminal_id":"10"})
	check(host.calls.size()==before_calls+1 and host.calls.back().path=="/services/open","Explicit terminal interaction bypasses background admission")
	host.queue_free();await process_frame
	var result: Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"backend":"async mocked Core3 envelopes","renderer":"headless dummy","tracking":"mocked; not live XR"}
	var file:=FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/services-controller-smoke.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
