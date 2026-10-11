extends SceneTree
## Source appearance assets with mocked asynchronous adapter replies; no backend/XR claim.
var Host=load("res://tests/gathering_test_host.gd")
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var errors: Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func run() -> void:
	var app: Node=Host.new(); root.add_child(app)
	app.xr_origin=XROrigin3D.new(); app.add_child(app.xr_origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; app.xr_origin.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; app.xr_origin.add_child(hand)
	app.player=Player.new(); app.add_child(app.player)
	app.loader=load("res://scripts/stage_loader.gd").new(); app.loader.report={"origin":[100,7,-300]}
	app.stage=Node3D.new(); app.stage.set_meta("manifest",{"origin":[100,7,-300]}); app.add_child(app.stage)
	app.stage.position=Vector3(3,0,4); app.stage.rotation.y=0.3
	app.player.global_position=app.stage.to_global(Vector3(2,1,3))
	app.inventory=load("res://scripts/xr_inventory.gd").new(); app.add_child(app.inventory)
	app.inventory.configure(app.xr_origin,app.player); app.inventory.set_process(false)
	app.datapad_character_id="corpse_character"; app.datapad_account="fixture"; app.world_ready=true
	app.gathering=load("res://scripts/resource_gathering.gd").new(); app.add_child(app.gathering); app.gathering.configure(app,app.inventory); app.gathering.set_process(false)
	var service: Node=load("res://scripts/corpse_gathering_controller.gd").new(); app.add_child(service); service.configure(app,app.inventory); service.set_process(false); service.ui.set_process(false); service.visuals.set_physics_process(false)
	var corpse:={"id":"native_corpse_id","dead":true,"loot_available":true,"loot":{"credits":10,"item_count":1},"template":"object/mobile/worrt_hue.iff","position":[102,8,-303],"scale":1,"heading_radians":0.25,"resources":[{"kind":"meat","quantity":10,"available":true,"container_template":"object/resource_container/organic_food.iff"}]}
	app.reply={"ok":true,"source_kind":"core3_corpses","character_id":app.datapad_character_id,"corpses":[corpse]}
	check(await service.refresh(),"Matching native corpse query rejected")
	service.visuals.sync_visuals()
	check(service.visuals.visuals.size()==1,"Native query did not project original corpse model")
	check(app.calls[-1].method==HTTPClient.METHOD_GET and app.calls[-1].path.begins_with("/gathering/corpses?"),"Nearby corpse request uses incorrect route")
	check(service.position()==[102.0,8.0,-303.0],"Corpse request does not preserve SWG source coordinates")
	var node: Node3D=service.visuals.visuals[corpse.id].node
	check(node.global_position.distance_to(app.player.global_position)<0.001,"Authoritative source corpse position projects incorrectly")
	check(node.global_basis.is_equal_approx(app.stage.global_basis*Basis(Vector3.UP,-0.25)),"Source corpse heading omitted rotated stage basis")
	var foreign: Dictionary=app.reply.duplicate(true); foreign.character_id="foreign"; foreign.corpses=[]; app.reply=foreign
	check(not await service.refresh() and service.visuals.states.has(corpse.id),"Foreign query removed current native corpse")
	service.ui.corpse=corpse.duplicate(true)
	app.reply={"ok":true,"source_kind":"core3_corpse_inspect","character_id":app.datapad_character_id,"corpse":corpse}
	var result: Dictionary=await service.perform("inspect",corpse)
	check(not result.is_empty() and not service.ui.pending,"Inspect did not update source resource UI")
	check(app.calls[-1].payload.corpse_id==corpse.id and app.calls[-1].payload.position==[102.0,8.0,-303.0],"Inspect changed source identity or source position")
	# A corpse refresh may start while a mutation waits for gathering. The
	# resumed waiter must recheck both gates instead of racing that refresh.
	app.gathering.busy=true
	var waiting_count: int=app.calls.size()
	service.perform("inspect",corpse)
	service.busy=true; app.gathering.busy=false; app.gathering.request_finished.emit()
	await process_frame
	check(app.calls.size()==waiting_count,"Corpse mutation raced a refresh that started during gathering wait")
	service.busy=false; service.request_finished.emit()
	await process_frame; await process_frame
	check(app.calls.size()==waiting_count+1 and not service.busy,"Serialized corpse waiter failed to resume once both services were idle")
	var before: Dictionary={"source_kind":"core3_inventory","character_id":app.datapad_character_id,"items":[],"equipment":[],"inventory":{"capacity":80,"occupied":0}}
	app.inventory_snapshot=before.duplicate(true)
	var after:=before.duplicate(true); after.inventory.occupied=1; after.items=[{"id":"native_resource_stack","template":"object/resource_container/organic_food.iff","quantity":10}]
	app.reply={"ok":true,"source_kind":"core3_corpse_harvest","character_id":app.datapad_character_id,"corpse":corpse,"mutation":{"success":true},"inventory":after}
	result=await service.perform("harvest",corpse,"meat")
	check(not result.is_empty() and app.inventory_snapshot==after,"Confirmed native yield not adopted")
	check(app.calls[-1].payload.kind=="meat" and str(app.calls[-1].payload.request_id).length()>8,"Native resource kind/request identity missing")
	var invalid:=after.duplicate(true); invalid.character_id="foreign"
	app.reply={"ok":true,"source_kind":"core3_corpse_loot","character_id":app.datapad_character_id,"corpse":corpse,"mutation":{"success":true},"inventory":invalid}
	result=await service.perform("loot",corpse)
	check(result.is_empty() and app.inventory_snapshot==after,"Foreign mutation inventory replaced local possessions")
	check(app.reconciliations==1 and not service.busy and not app.inventory_request_pending,"Failed action did not reconcile and unlock")
	app.reply={"ok":false,"error":"Native corpse ownership denied"}
	var count:int=app.calls.size(); result=await service.perform("harvest",corpse,"hide")
	check(result.is_empty() and app.calls.size()==count+1 and service.visuals.states.has(corpse.id),"Rejected harvest repeated a mutation or deleted source corpse")
	check(service.ui.message.text=="Native corpse ownership denied","Native rights failure hidden from player")
	var emptied:Dictionary=corpse.duplicate(true);emptied.loot={"credits":0,"item_count":0};emptied.loot_available=false
	check(service.visuals.coins[corpse.id].visible,"Eligible confirmed corpse retains coin before successful loot")
	app.reply={"ok":true,"source_kind":"core3_corpse_loot","character_id":app.datapad_character_id,"corpse":emptied,"mutation":{"success":true},"inventory":after}
	result=await service.perform("loot",corpse)
	check(not result.is_empty() and not service.visuals.coins[corpse.id].visible,"Successful Loot All hides coin immediately without waiting for polling")
	app.change_epoch=true; app.reply={"ok":true,"source_kind":"core3_corpse_loot","character_id":app.datapad_character_id,"corpse":corpse,"mutation":{"success":true},"inventory":before}
	result=await service.perform("loot",corpse)
	check(result.is_empty() and app.inventory_snapshot==after,"Late old-character mutation was adopted")
	app.change_epoch=false; service.reset()
	check(service.visuals.states.is_empty() and not service.ui.visible,"Character reset retained corpse projection/UI")
	var report:={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/corpse-controller-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); app.loader=null; app.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
