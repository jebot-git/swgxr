extends Node
## Orchestrates real Core3 gathering. World nodes are views of persistent state.
signal request_finished
const POLL_SECONDS:=5.0
const REQUEST_WAIT_TIMEOUT_MS:=12000
var app: Node
var bag: Node3D
var world_tools: Node3D
var state: Dictionary={}
var busy:=false
var next_poll:=0.0
var revision:=0
var current_epoch:=-1
var request_serial:=0
var last_error:=""
var requests_sent:=0
var pending_receipts: Dictionary={}
var ambiguous_receipts: Dictionary={}

func configure(host: Node, inventory: Node3D) -> void:
	app=host; bag=inventory; current_epoch=app.datapad_epoch
	world_tools=load("res://scripts/deployed_resource_tools.gd").new(); app.add_child(world_tools); world_tools.configure(bag.assets)
	bag.tool_context_requested.connect(refresh_tool)
	bag.survey_requested.connect(survey)
	bag.deploy_requested.connect(deploy)
	bag.tool_holster_requested.connect(holster)
	bag.tool_pickup_requested.connect(pickup)
	bag.return_tool_requested.connect(return_tool)

func reset() -> void:
	revision+=1; state={}; pending_receipts.clear(); ambiguous_receipts.clear(); next_poll=0; current_epoch=app.datapad_epoch
	if is_instance_valid(world_tools): world_tools.set_states([])
	if is_instance_valid(bag): bag.set_hip_tool({})

func hip_item() -> Dictionary:
	var item: Dictionary=state.get("hip_tool",{}).duplicate(true) if state.get("hip_tool") is Dictionary else {}
	if not item.is_empty(): item["gathering_hip"]=true
	return item

func owned_hip_item(id: String) -> Dictionary:
	var item:=hip_item()
	return item if str(item.get("id",""))==id else {}

func source_position(point: Vector3) -> Array:
	var source: Vector3=app.source_position_at(point)
	return [source.x,source.y,source.z]

func held_tool_id() -> String:
	return str(bag.held_item.get("id","")) if is_instance_valid(bag) and bag.is_survey_held() else ""

func live_session_id() -> String:
	return preload("res://scripts/native_session_identity.gd").id(app)

func request_path(tool_id: String="") -> String:
	var path: String="/gathering?account="+app.datapad_account.uri_encode()+"&character_id="+app.datapad_character_id.uri_encode()
	if not tool_id.is_empty(): path+="&tool_id="+tool_id.uri_encode()
	return path

func accept_state(value: Dictionary) -> bool:
	var zone:=preload("res://scripts/planet_catalog.gd").current(app)
	if str(value.get("zone",value.get("planet",zone)))!=zone:return false
	if value.get("source_kind","")!="core3_gathering" or str(value.get("character_id",""))!=app.datapad_character_id: return false
	world_tools.set_context(app.stage,app.player,app.terrain)
	if not world_tools.set_states(value.get("deployments",[])): return false
	state=value.duplicate(true)
	world_tools.set_server_time(float(value.get("server_time",0)))
	bag.set_hip_tool(hip_item())
	var tool_id:=str(state.get("tool_id",""))
	if not tool_id.is_empty() and tool_id==str(bag.held_item.get("id","")):
		var context:=state.duplicate(true)
		context["center"]=source_position(app.player.global_position)
		bag.set_tool_context(tool_id,context)
	return true

func refresh(tool_id: String="") -> bool:
	if busy or app.datapad_character_id.is_empty(): return false
	busy=true; var epoch: int=app.datapad_epoch; var generation:=revision
	requests_sent+=1
	var result: Dictionary
	var native_session := live_session_id()
	if not native_session.is_empty():
		var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"live_session_id":native_session}
		if not tool_id.is_empty(): payload.tool_id=tool_id
		result=await app.api(HTTPClient.METHOD_POST,"/gathering/status",payload)
	else:
		result=await app.api(HTTPClient.METHOD_GET,request_path(tool_id))
	var accepted:=false
	if epoch==app.datapad_epoch and generation==revision:
		if result.get("ok",false): accepted=accept_state(result.get("state",result))
		if not accepted: last_error=str(result.get("error","Core3 gathering state is unavailable."))
	busy=false; request_finished.emit(); next_poll=POLL_SECONDS
	return accepted

func refresh_tool(tool: Dictionary) -> void:
	if tool.get("tool_kind","") in ["crafting","camp","trap","medical","fishing","slicing"]: return
	var id:=str(tool.get("id","")); var epoch: int=app.datapad_epoch
	var held_revision: int=bag.held_revision
	bag.set_busy(true,"Reading current planetary resources…")
	if not await wait_available(epoch,held_revision): return
	if held_revision!=bag.held_revision or str(bag.held_item.get("id",""))!=id: return
	var accepted:=await refresh(id)
	if epoch!=app.datapad_epoch or held_revision!=bag.held_revision or str(bag.held_item.get("id",""))!=id: return
	if not accepted: bag.set_busy(false,last_error)

func new_request_id() -> String:
	request_serial+=1
	return "%s-%d-%d-%d"%[str(app.datapad_character_id),Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec(),request_serial]

func mutation_payload(action: String, parameters: Dictionary) -> Dictionary:
	# Explicit retries after ambiguous transport failure repeat the SAME semantic
	# command and receipt. Position changes must not create a duplicate deployment.
	var key := action+":"+str(parameters.get("tool_id",""))+":"+str(parameters.get("deployment_id",""))+":"+str(parameters.get("resource_id",""))
	if not pending_receipts.has(key):
		if pending_receipts.size()>=64: return {}
		var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"request_id":new_request_id()}
		payload.merge(parameters)
		pending_receipts[key]=payload
	var result: Dictionary=pending_receipts[key].duplicate(true)
	result["_receipt_key"]=key
	return result

func wait_available(epoch: int, held_revision: int) -> bool:
	var deadline := Time.get_ticks_msec()+REQUEST_WAIT_TIMEOUT_MS
	while busy:
		if epoch!=app.datapad_epoch or held_revision!=bag.held_revision: return false
		if Time.get_ticks_msec()>=deadline:
			bag.finish_item_action(false)
			bag.set_busy(false,"Core3 is still handling the previous request. Try again shortly.")
			return false
		await get_tree().process_frame
	return epoch==app.datapad_epoch and held_revision==bag.held_revision

func perform(action: String, parameters: Dictionary) -> Dictionary:
	var epoch: int=app.datapad_epoch
	var held_revision: int=bag.held_revision
	if not await wait_available(epoch,held_revision): return {}
	if app.inventory_request_pending:
		bag.finish_item_action(false)
		bag.set_busy(false,"Wait for the current inventory request, then grip the tool again."); return {}
	if app.datapad_character_id.is_empty(): bag.set_busy(false,"Core3 character is unavailable."); return {}
	var payload := mutation_payload(action,parameters)
	if payload.is_empty():
		bag.finish_item_action(false);bag.set_busy(false,"Too many unconfirmed Core3 actions. Reconnect before retrying.");return {}
	var receipt_key := str(payload["_receipt_key"]);payload.erase("_receipt_key")
	busy=true; app.inventory_request_pending=true
	var generation:=revision
	var native_session := live_session_id()
	if not native_session.is_empty(): payload.live_session_id=native_session
	requests_sent+=1
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/gathering/"+action,payload)
	var confirmed: bool=result.get("ok",false) and result.get("source_kind","")=="core3_gathering_"+action and result.get("mutation",{}).get("success",false)
	if epoch!=app.datapad_epoch or generation!=revision:
		busy=false
		if epoch==app.datapad_epoch: app.inventory_request_pending=false
		request_finished.emit(); return {}
	if confirmed:
		var inventory: Dictionary=result.get("inventory",{})
		confirmed=inventory.get("source_kind","")=="core3_inventory" and str(inventory.get("character_id",""))==app.datapad_character_id
		if confirmed: confirmed=accept_state(result.get("state",{}))
		if confirmed:
			app.inventory_snapshot=inventory.duplicate(true);pending_receipts.erase(receipt_key);ambiguous_receipts.erase(receipt_key)
	busy=false; app.inventory_request_pending=false; request_finished.emit(); next_poll=3.0
	if not confirmed:
		if result.get("mutation_started",true)==false:
			if not ambiguous_receipts.has(receipt_key): pending_receipts.erase(receipt_key)
		else: ambiguous_receipts[receipt_key]=true
		var reason:=str(result.get("error","Core3 did not confirm this action."))
		# Reconcile possessions after a potentially committed response was lost.
		# Only reads are retried: never silently issue a second mutation.
		last_error=reason
		bag.finish_item_action(false); bag.set_busy(false,reason)
		await app.refresh_inventory()
		if epoch!=app.datapad_epoch or generation!=revision: return {}
		# A slow reconciliation must not hold the hand hostage or overwrite a new action.
		if held_revision==bag.held_revision and not bag.action_pending: bag.set_busy(false,reason)
		return {}
	result["confirmed_request_id"] = str(payload.request_id)
	return result

func survey(tool: Dictionary, resource_id: String) -> void:
	if not valid_held(tool): bag.set_busy(false,"Hold an owned survey tool first."); return
	bag.begin_mutation("Surveying current resource concentrations…")
	var center:=source_position(app.player.global_position)
	var visual_center: Vector3 = app.player.global_position
	var result:=await perform("survey",{"tool_id":str(tool.id),"resource_id":resource_id,"planet":preload("res://scripts/planet_catalog.gd").current(app),"position":center})
	if result.is_empty(): return
	if result.get("mutation", {}).get("success", false) and not bool(result.get("mutation", {}).get("replayed", false)):
		var receipt := str(result.get("confirmed_request_id", ""))
		if not receipt.is_empty():
			var eye: Camera3D = app.player.get_camera() if app.player.has_method("get_camera") else null
			preload("res://multiplayer/survey_pulse.gd").shared(app, eye).play_confirmed(visual_center, "local:" + receipt)
	app.update_inventory_presentation()
	var scan: Dictionary=result.get("survey",{}).duplicate(true)
	scan["center"]=center
	bag.set_survey_result(str(tool.id),scan)
	if is_instance_valid(app.datapad): app.refresh_datapad()

func deploy(tool: Dictionary, pose: Transform3D) -> void:
	if not valid_held(tool): bag.finish_item_action(false); bag.set_busy(false,"Hold an owned survey tool first."); return
	world_tools.set_context(app.stage,app.player,app.terrain)
	var support: Dictionary=world_tools.ground_placement(pose)
	if not support.get("valid",false):
		bag.finish_item_action(false); bag.set_busy(false,str(support.get("error","Lower the tool onto supported outdoor ground."))); return
	var resource_id:=str(bag.survey_ui.selected_resource_id)
	if resource_id.is_empty(): bag.finish_item_action(false); bag.set_busy(false,"Select a resource before placing the tool."); return
	bag.begin_mutation("Placing survey tool…")
	var result:=await perform("deploy",{"tool_id":str(tool.id),"resource_id":resource_id,"planet":preload("res://scripts/planet_catalog.gd").current(app),"position":source_position(support.position)})
	if result.is_empty(): return
	bag.finish_item_action(true); app.reconcile_inventory_presentations(); app.update_inventory_presentation()

func holster(tool: Dictionary) -> void:
	if tool.get("tool_kind","")=="medical" and is_instance_valid(app.get("medic")):
		app.medic.belt_action("holster",tool);return
	if tool.get("tool_kind","")=="trap" and is_instance_valid(app.get("scout")):
		app.scout.belt_action("holster",tool);return
	if not valid_held(tool): bag.finish_item_action(false); return
	bag.begin_mutation("Securing offhand hip tool…")
	var result:=await perform("holster",{"tool_id":str(tool.id)})
	if result.is_empty(): return
	bag.finish_item_action(true); app.reconcile_inventory_presentations(); app.update_inventory_presentation()

func return_tool(tool: Dictionary) -> void:
	if tool.get("tool_kind","")=="medical" and is_instance_valid(app.get("medic")):
		app.medic.belt_action("return_tool",tool);return
	if tool.get("tool_kind","")=="trap" and is_instance_valid(app.get("scout")):
		app.scout.belt_action("return_tool",tool);return
	if not valid_held(tool): bag.finish_item_action(false); return
	bag.begin_mutation("Returning tool to inventory…")
	var result:=await perform("return_tool",{"tool_id":str(tool.id)})
	if result.is_empty(): return
	bag.finish_item_action(true); app.reconcile_inventory_presentations(); app.update_inventory_presentation()

func valid_held(tool: Dictionary) -> bool:
	var id:=str(tool.get("id",""))
	return app.world_ready and not id.is_empty() and str(bag.held_item.get("id",""))==id and not app.owned_inventory_item(id).is_empty()

func pickup(candidate: Dictionary) -> void:
	if not app.world_ready or not bag.held_item.is_empty(): bag.set_busy(false); return
	if candidate.get("gathering_hip",false):
		var item:=hip_item()
		if item.is_empty() or str(candidate.get("item",{}).get("id",""))!=str(item.id): bag.set_busy(false,"Holstered tool changed. Refresh the inventory."); return
		bag.set_busy(false); bag.take_item(item,str(candidate.get("hand",""))); return
	var record: Dictionary=candidate.get("gathering_deployment",candidate)
	var tool: Dictionary=record.get("tool",record)
	var template:=str(tool.get("template",record.get("template","")))
	# Confirm original geometry before transferring server possessions.
	if bag.assets.model(template)==null: bag.set_busy(false,"Original deployed tool appearance is unavailable."); return
	bag.begin_mutation("Checking room for the tool and collected resources…")
	var result:=await perform("collect",{"deployment_id":str(record.get("id","")),"planet":preload("res://scripts/planet_catalog.gd").current(app),"position":source_position(app.player.global_position)})
	if result.is_empty(): return
	var id:=str(record.get("tool_id",tool.get("id","")))
	var item: Dictionary=app.owned_inventory_item(id).duplicate(true)
	app.reconcile_inventory_presentations(); app.update_inventory_presentation()
	bag.set_busy(false)
	if not item.is_empty(): bag.take_item(item)

func pickup_candidate(pose: Transform3D) -> Dictionary:
	if not is_instance_valid(world_tools) or not app.world_ready: return {}
	var found: Dictionary=world_tools.nearest(pose.origin)
	return {"gathering_deployment":found} if not found.is_empty() else {}

func _process(delta: float) -> void:
	if not is_instance_valid(app) or not is_instance_valid(bag): return
	if current_epoch!=app.datapad_epoch: reset()
	if not app.world_ready or app.loading_stage: return
	if bag.is_survey_held(): bag.survey_ui.set_center(app.source_position_at(app.player.global_position))
	if state.get("deployments",[]).is_empty(): return
	next_poll-=delta
	if next_poll<=0 and not busy and not app.inventory_request_pending and not bag.action_pending and (not app.has_method("try_background_poll") or app.try_background_poll("gathering")):
		refresh(held_tool_id())
