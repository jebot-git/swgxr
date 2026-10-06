extends SceneTree
## Main's native activation bridge; mocked HTTP and poses, original deed model.
class Host extends "res://scripts/main.gd":
	var reply: Dictionary={}
	var calls: Array=[]
	var datapad_refreshes:=0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
		calls.append({"method":method,"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
	func refresh_datapad() -> void: datapad_refreshes+=1
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
class LiveSession extends Node3D:
	var live:=true
	var session_id:="fixture-native-session"
class Vehicles extends Node3D:
	var snapshots: Array=[]
	func observe(state: Dictionary) -> void: snapshots.append(state)
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host:=Host.new();root.add_child(host)
	host.xr_origin=XROrigin3D.new();host.add_child(host.xr_origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";host.xr_origin.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;host.xr_origin.add_child(hand)
	host.player=Player.new();host.xr_origin.add_child(host.player)
	host.inventory=preload("res://scripts/xr_inventory.gd").new();host.add_child(host.inventory);host.inventory.configure(host.xr_origin,host.player);host.inventory.set_process(false);host.inventory.set_allowed(true)
	host.world_ready=true;host.datapad_account="fixture";host.datapad_character_id="123"
	var deed:Dictionary={"id":"456","template":"object/tangible/deed/pet_deed/bantha_deed.iff","name":"Bantha creature deed"}
	check(host.inventory.is_pet_deed(deed),"Creature deed recognized separately from vehicles")
	check(not host.inventory.is_pet_deed({"template":"object/tangible/deed/house_deed/tatooine_house_small_deed.iff"}),"Structure deed never enters pet registration")
	check(not host.inventory.is_pet_deed({"template":"object/tangible/component/dna/dna_template_generic.iff"}),"DNA templates remain crafting ingredients")
	host.inventory_snapshot={"source_kind":"core3_inventory","character_id":"123","items":[deed],"equipment":[],"inventory":{"id":"bag","capacity":80,"occupied":1}}
	host.update_inventory_presentation();host.inventory.take_item(deed)
	check(not host.inventory.held_item.is_empty(),"Original creature deed model can be held")
	var requests:Array=[]
	host.inventory.vehicle_deed_requested.connect(func(item):requests.append(item))
	host.inventory.update_held_trigger(0,Transform3D.IDENTITY)
	host.inventory.update_held_trigger(1,Transform3D.IDENTITY)
	host.inventory.update_held_trigger(1,Transform3D.IDENTITY)
	check(requests.size()==1 and requests[0].id==deed.id,"Triggering held creature deed requests exactly one registration")
	host.inventory.finish_consumable_action({},false)

	host.reply={"ok":false,"error":"Core3 request timed out; outcome unconfirmed.","code":"request_timeout"}
	await host.activate_inventory_vehicle_deed(deed)
	check(host.calls[-1].path=="/vehicles/activate" and not host.calls[-1].payload.has("live_session_id"),"Normal world activation uses native vehicle endpoint without invented live session")
	check(host.inventory.held_item.id==deed.id and not host.inventory.action_pending and not host.inventory_request_pending,"Unknown activation outcome preserves deed and unlocks input")
	var receipt:String=host.calls[-1].payload.request_id
	var original_position:Array=host.calls[-1].payload.position.duplicate()
	host.player.global_position=Vector3(9,0,0)
	host.reply={"ok":false,"error":"Core3 is busy.","error_code":"backend_busy","mutation_started":false}
	await host.activate_inventory_vehicle_deed(deed)
	check(host.calls[-1].payload.request_id==receipt and host.calls.size()==2,"Explicit retry keeps same receipt after ambiguous response")
	check(host.calls[-1].payload.position==original_position,"Moving after timeout cannot change semantic position under retained receipt")
	check(host.inventory.held_item.id==deed.id and not host.inventory.action_pending,"Backend busy does not destroy or trap held deed")
	var after:Dictionary={"source_kind":"core3_inventory","character_id":"123","items":[],"equipment":[],"inventory":{"id":"bag","capacity":80,"occupied":0}}
	host.reply={"ok":true,"source_kind":"core3_vehicles","mutation":{"success":true,"item_id":"456"},"inventory":after,"state":{"character_id":"123","devices":[{"id":"789"}]}}
	await host.activate_inventory_vehicle_deed(deed)
	check(host.inventory.held_item.is_empty() and host.inventory_snapshot.items.is_empty() and host.datapad_refreshes==1,"Confirmed activation consumes deed presentation and refreshes normal datapad")
	check(host.vehicle_activation_requests.is_empty(),"Completed receipt is removed")
	host.inventory_snapshot.items=[deed];host.update_inventory_presentation();host.inventory.take_item(deed)
	host.live_combat=LiveSession.new();host.add_child(host.live_combat)
	host.vehicles=Vehicles.new();host.add_child(host.vehicles)
	await host.activate_inventory_vehicle_deed(deed)
	check(host.calls[-1].payload.live_session_id=="fixture-native-session" and not host.calls[-1].payload.has("session_id"),"Live activation carries separate native identity")
	check(host.vehicles.snapshots.size()==1 and host.inventory.held_item.is_empty(),"Live confirmed state updates real vehicle presentation")
	host.inventory_snapshot.items=[deed];host.update_inventory_presentation();host.inventory.take_item(deed)
	host.reply.inventory.character_id="different"
	await host.activate_inventory_vehicle_deed(deed)
	check(not host.inventory.held_item.is_empty() and not host.inventory.action_pending,"Foreign inventory response preserves deed and unlocks input")
	host.reply.inventory.character_id="123";host.reply.inventory.source_kind="unverified_inventory"
	await host.activate_inventory_vehicle_deed(deed)
	check(not host.inventory.held_item.is_empty() and not host.inventory.action_pending,"Unverified inventory source cannot consume held vehicle deed")
	host.reply={"ok":false,"error":"Vehicle deeds must be used outside.","confirmed_rejection":true,"mutation_started":false}
	await host.activate_inventory_vehicle_deed(deed)
	check(host.vehicle_activation_requests.is_empty() and not host.inventory.held_item.is_empty(),"Confirmed native preflight rejection releases receipt so player can change location")
	host.free()
	var report:Dictionary={"checks":checks,"passed":failures.is_empty(),"errors":failures,"server_mocked":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/bioengineer-deed-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(1 if not failures.is_empty() else 0)
