extends SceneTree
## Asynchronous orchestration tests; real models, mocked HTTP, no Core3/XR claim.
var Harness = load("res://tests/gathering_test_host.gd")
class LiveSession extends Node3D:
	var live := true
	var session_id := "native-gathering-session"
class Player extends CharacterBody3D:
	func set_interface_capture(_move: bool,_turn: bool) -> void: pass
var checks:=0
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app: Node=Harness.new(); root.add_child(app)
	var origin:=XROrigin3D.new(); app.add_child(origin)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; origin.add_child(head)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; origin.add_child(hand)
	app.player=Player.new(); origin.add_child(app.player)
	app.inventory=load("res://scripts/xr_inventory.gd").new(); app.add_child(app.inventory); app.inventory.configure(origin,app.player); app.inventory.set_process(false); app.inventory.set_allowed(true)
	app.datapad_character_id="281474999999999"; app.datapad_account="fixture"; app.world_ready=true
	app.gathering=load("res://scripts/resource_gathering.gd").new(); app.add_child(app.gathering); app.gathering.configure(app,app.inventory); app.gathering.set_process(false)
	var service:Node=app.gathering
	var tool:Dictionary={"id":"12345","tool_kind":"survey","template":"object/tangible/survey_tool/survey_tool_mineral.iff","name":"Mineral survey tool","equipped":false}
	var inventory:Dictionary={"source_kind":"core3_inventory","character_id":app.datapad_character_id,"items":[tool],"equipment":[],"inventory":{"id":"bag","capacity":80,"occupied":1}}
	var state:Dictionary={"source_kind":"core3_gathering","character_id":app.datapad_character_id,"deployments":[],"hip_tool":null}
	app.inventory_snapshot=inventory.duplicate(true); app.update_inventory_presentation()
	var sample_view=load("res://scripts/deployed_resource_tools.gd").new()
	var sampling:Dictionary={"buffer":[],"resource_name":"Fixture ore","sample_status":"trace_amount","sample_message":"Trace amounts located.","next_sample_at_unix":110,"minimum_productive_density":0.3572,"recommended_density":0.4}
	var sample_text:String=sample_view.count_text(sampling,100)
	check(sample_text.contains("Trace amounts") and sample_text.contains("10s") and sample_text.contains("40%") and sample_text.contains("0 units"),"Original trace outcome, productive density and server-clock countdown are visible without inventing yield")
	sampling.buffer=[{"quantity":3}];sampling.sample_status="sample_located";sampling.sample_message="Sample located."
	check(sample_view.count_text(sampling,111).contains("3 units") and sample_view.count_text(sampling,111).contains("Waiting for CoreCU"),"Collected count is authoritative and overdue timer waits for native result")
	sample_view.free()
	check(service.accept_state(state),"Owner-verified initial context accepted")
	var alien:=state.duplicate(true); alien.character_id="different"
	check(not service.accept_state(alien) and service.state==state,"Foreign context rejected without altering canonical state")
	var bad:=state.duplicate(true); bad.deployments=[{"id":"bad"}]
	check(not service.accept_state(bad) and service.state==state,"Malformed deployment rejected transactionally")
	var before:Dictionary=service.state.duplicate(true)
	var hip:=state.duplicate(true); hip.hip_tool=tool; hip.hip_tool_id=tool.id
	var after:=inventory.duplicate(true); after.items=[]; after.inventory.occupied=0
	app.reply={"ok":true,"source_kind":"core3_gathering_holster","mutation":{"success":true},"state":hip,"inventory":after}
	var result:Dictionary=await service.perform("holster",{"tool_id":tool.id})
	check(not result.is_empty() and service.hip_item().id==tool.id and app.inventory_snapshot.items.is_empty(),"Confirmed hip escrow adopts native inventory and tool together")
	check(app.owned_inventory_item(tool.id).get("gathering_hip",false),"Escrowed hip remains owned for visual draw")
	var key:=str(app.calls[-1].payload.request_id)
	check(key.length()>=8 and key.length()<=64 and key!=service.new_request_id(),"Mutation keys bounded and unique")
	check(app.calls[-1].payload.tool_id==tool.id and app.calls[-1].payload.account=="fixture","Mutation preserves source identity and account")
	var forged:=after.duplicate(true); forged.character_id="another"
	app.reply={"ok":true,"source_kind":"core3_gathering_return_tool","mutation":{"success":true},"state":state,"inventory":forged}
	result=await service.perform("return_tool",{"tool_id":tool.id})
	check(result.is_empty() and service.hip_item().id==tool.id and app.inventory_snapshot==after,"Mismatched inventory never partially adopts gathering state")
	check(app.reconciliations==1 and not app.inventory.action_pending and not app.reconciliation_started_pending,"Ambiguous result uses one possession refresh and unlocks UI")
	app.reply={"ok":false,"error":"No free inventory slot for tool and resources"}
	result=await service.perform("collect",{"deployment_id":"12345:8"})
	check(result.is_empty() and service.hip_item().id==tool.id,"Rejected pickup preserves canonical ownership")
	check(app.inventory.ui.status==app.reply.error,"Native capacity failure remains visible after reconcile")
	check(app.calls.filter(func(call):return call.method==HTTPClient.METHOD_POST).size()==3,"Rejected or ambiguous mutations never automatically repeat")
	app.inventory_request_pending=true
	var count:int=app.calls.size()
	await service.perform("holster",{"tool_id":tool.id})
	check(app.calls.size()==count and not app.inventory.action_pending,"Busy inventory rejects retrieval without retaining a stuck hand action")
	app.inventory_request_pending=false; app.inventory.set_busy(false)
	app.reply={"ok":true,"source_kind":"core3_gathering_return_tool","mutation":{"success":true},"state":state,"inventory":inventory}
	app.change_epoch=true
	result=await service.perform("return_tool",{"tool_id":tool.id})
	check(result.is_empty() and service.hip_item().id==tool.id and not service.busy,"Late previous-session response cannot mutate current possessions")
	app.change_epoch=false; app.inventory_request_pending=false; app.inventory.set_busy(false); service.reset()
	check(service.state.is_empty() and service.hip_item().is_empty(),"Session reset clears canonical presentation")
	var deployed:Dictionary=state.duplicate(true);deployed.deployments=[{"id":"deployment-fixture","tool_id":tool.id,"resource_name":"Fixture ore"}]
	service.accept_state(deployed)
	app.reply={"ok":false,"error":"CoreCU request timed out; outcome unconfirmed.","code":"request_timeout"}
	app.inventory.begin_mutation("Recovering deployed tool")
	await service.perform("collect",{"deployment_id":"deployment-fixture","position":[1,0,2]})
	var original_request:Dictionary=app.calls[-1].payload.duplicate(true)
	check(service.state.deployments.size()==1 and not app.inventory.action_pending and not app.reconciliation_started_pending,"Timed-out recovery preserves deployed source state and releases hand before slow reconciliation")
	app.reply={"ok":false,"error":"CoreCU is busy.","code":"backend_busy","mutation_started":false}
	await service.perform("collect",{"deployment_id":"deployment-fixture","position":[2,0,3]})
	check(app.calls[-1].payload.request_id==original_request.request_id and app.calls[-1].payload.position==original_request.position,"Explicit ambiguous retry keeps original receipt and semantic position")
	check(service.state.deployments.size()==1 and not app.inventory.action_pending,"Backend-busy recovery preserves deployment and permits another intentional grip")
	app.live_combat=LiveSession.new();app.add_child(app.live_combat)
	app.reply={"ok":true,"state":state}
	await service.refresh(tool.id)
	check(app.calls[-1].method==HTTPClient.METHOD_POST and app.calls[-1].path=="/gathering/status" and app.calls[-1].payload.live_session_id=="native-gathering-session" and app.calls[-1].payload.tool_id==tool.id,"Live gathering read reuses active native actor identity")
	app.reply={"ok":true,"source_kind":"core3_gathering_holster","mutation":{"success":true},"state":hip,"inventory":after}
	await service.perform("holster",{"tool_id":tool.id})
	check(app.calls[-1].payload.live_session_id=="native-gathering-session","Sampling mutation retains native live identity")
	app.live_combat.free();app.live_combat=null
	# A completed read for the previous hand cannot unlock the current hand action.
	app.inventory.held_item=tool.duplicate(true)
	app.reply={"ok":false,"error":"Old tool context failed"}
	service.refresh_tool(tool)
	app.inventory.clear_held();app.inventory.held_item=tool.duplicate(true);app.inventory.held_item.id="67890"
	app.inventory.begin_mutation("New held tool operation")
	await process_frame;await process_frame
	check(app.inventory.action_pending and app.inventory.ui.status=="New held tool operation","Late failed tool read cannot unlock a different held tool")
	app.inventory.set_busy(false)
	app.inventory.held_item=tool.duplicate(true)
	service.refresh_tool(tool)
	app.inventory.clear_held();app.inventory.held_item=tool.duplicate(true)
	app.inventory.begin_mutation("Same tool newly re-grabbed")
	await process_frame;await process_frame
	check(app.inventory.action_pending and app.inventory.ui.status=="Same tool newly re-grabbed","Late failed read cannot unlock a new hold of the same tool ID")
	app.inventory.clear_held();app.inventory.set_busy(false)
	# Main's source conversion is independently exercised against a rotated stage.
	app.loader=load("res://scripts/stage_loader.gd").new()
	app.loader.report={"origin":[100,7,-300]}
	app.stage=Node3D.new(); app.add_child(app.stage); app.stage.position=Vector3(2,4,9); app.stage.rotation.y=0.3
	var source:Vector3=app.source_position_at(app.stage.to_global(Vector3(3,5,11)))
	check(source.distance_to(Vector3(103,12,-311))<0.001,"World-to-source position applies full stage transform and SWG Z reflection")
	var combat:Node3D=load("res://combat/ranged_rig.gd").new(); app.add_child(combat); combat.set_process(false); combat.set_physics_process(false)
	combat.interaction_blocker=func(): return true
	check(not combat.inventory_allows_combat(),"Physics input checks interaction ownership immediately")
	combat.interaction_blocker=Callable()
	check(combat.inventory_allows_combat(),"Combat resumes after interaction releases input")
	service.busy=true;app.inventory.begin_mutation("Waiting for previous sampling request")
	count=app.calls.size()
	var wait_started:=Time.get_ticks_msec()
	await service.perform("collect",{"deployment_id":"hung-fixture"})
	check(Time.get_ticks_msec()-wait_started>=service.REQUEST_WAIT_TIMEOUT_MS and app.calls.size()==count and not app.inventory.action_pending,"Unanswered earlier request has bounded wait and releases recovery action without issuing duplicate mutation")
	service.busy=false
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/gathering-actions-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); app.loader=null; app.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
