extends Node
## Native dead-creature projection and request orchestration. No client kill rewards.
signal request_finished
const POLL_SECONDS:=15.0
var app: Node
var bag: Node3D
var ui: Node3D
var visuals: Node3D
var busy:=false
var revision:=0
var current_epoch:=-1
var next_poll:=2.0
var last_error:=""
var requests_sent:=0

func configure(host: Node,inventory: Node3D) -> void:
	app=host; bag=inventory; current_epoch=app.datapad_epoch
	visuals=load("res://scripts/corpse_visuals.gd").new(); app.add_child(visuals); visuals.configure()
	ui=load("res://scripts/corpse_gathering.gd").new(); app.add_child(ui)
	ui.configure(app.xr_origin,app.player,bag.assets,"right" if app.vr_settings.offhand=="left" else "left")
	ui.corpse_provider=func(point: Vector3): return visuals.nearest(point)
	ui.empty_hand_provider=empty_hand
	ui.corpse_inspect_requested.connect(inspect)
	ui.corpse_harvest_requested.connect(harvest)
	ui.corpse_loot_requested.connect(loot)

func empty_hand() -> bool:
	return bag.held_item.is_empty() and not bag.is_open and not (is_instance_valid(app.combat_rig) and app.combat_rig.selected>=0)

func set_allowed(value: bool) -> void:
	if is_instance_valid(ui): ui.set_allowed(value and empty_hand())

func blocks_combat() -> bool:
	return is_instance_valid(ui) and ui.blocks_combat()

func reset() -> void:
	revision+=1; current_epoch=app.datapad_epoch; next_poll=2.0
	if is_instance_valid(ui): ui.close()
	if is_instance_valid(visuals): visuals.set_states([])

func position() -> Array:
	return app.gathering.source_position(app.player.global_position)

func refresh() -> bool:
	if busy or app.inventory_request_pending or app.gathering.busy or app.datapad_character_id.is_empty(): return false
	busy=true
	var epoch: int=app.datapad_epoch; var generation:=revision; var point:=position()
	var path: String="/gathering/corpses?account="+app.datapad_account.uri_encode()+"&character_id="+app.datapad_character_id.uri_encode()+"&position="+("%s,%s,%s"%point).uri_encode()
	requests_sent+=1
	var response: Dictionary=await app.api(HTTPClient.METHOD_GET,path)
	var accepted:=false
	if epoch==app.datapad_epoch and generation==revision:
		if response.get("ok",false) and response.get("source_kind","")=="core3_corpses" and str(response.get("character_id",""))==app.datapad_character_id:
			visuals.set_context(app.stage,app.player)
			accepted=visuals.set_states(response.get("corpses",[]))
			if accepted and not ui.corpse.is_empty() and not visuals.states.has(str(ui.corpse.id)): ui.close()
		if not accepted: last_error=str(response.get("error","CoreCU corpse state unavailable."))
	busy=false; next_poll=POLL_SECONDS; request_finished.emit()
	return accepted

func inspect(record: Dictionary) -> void: await perform("inspect",record)
func harvest(record: Dictionary,kind: String) -> void: await perform("harvest",record,kind)
func loot(record: Dictionary) -> void: await perform("loot",record)

func perform(action: String,record: Dictionary,kind: String="") -> Dictionary:
	var epoch: int=app.datapad_epoch; var generation:=revision
	while busy or app.gathering.busy:
		if busy: await request_finished
		else: await app.gathering.request_finished
		if epoch!=app.datapad_epoch or generation!=revision: return {}
	var id:=str(record.get("id",""))
	if not app.world_ready or app.datapad_character_id.is_empty() or not visuals.states.has(id) or not empty_hand():
		ui.set_busy(false,"This corpse is no longer available for interaction."); return {}
	if app.inventory_request_pending:
		ui.set_busy(false,"Wait for the current inventory request."); return {}
	busy=true; app.inventory_request_pending=true
	var payload:Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"corpse_id":id,"position":position(),"request_id":app.gathering.new_request_id()}
	if action=="harvest": payload["kind"]=kind
	requests_sent+=1
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/gathering/corpse/"+action,payload)
	if epoch!=app.datapad_epoch or generation!=revision:
		busy=false; app.inventory_request_pending=false; request_finished.emit(); return {}
	var confirmed:bool=response.get("ok",false) and response.get("source_kind","")=="core3_corpse_"+action and str(response.get("character_id",""))==app.datapad_character_id and str(response.get("corpse",{}).get("id",""))==id
	if confirmed and action!="inspect":
		var snapshot:Dictionary=response.get("inventory",{})
		confirmed=response.get("mutation",{}).get("success",false) and snapshot.get("source_kind","")=="core3_inventory" and str(snapshot.get("character_id",""))==app.datapad_character_id
		if confirmed: app.inventory_snapshot=snapshot.duplicate(true)
	busy=false; app.inventory_request_pending=false; request_finished.emit(); next_poll=0.0
	if not confirmed:
		var reason:=str(response.get("error","CoreCU did not confirm this corpse action."))
		if action!="inspect": await app.refresh_inventory()
		if epoch!=app.datapad_epoch or generation!=revision: return {}
		last_error=reason; ui.set_busy(false,reason)
		return {}
	if action!="inspect": app.reconcile_inventory_presentations(); app.update_inventory_presentation()
	ui.set_corpse_context(record,response.corpse)
	return response

func _process(delta: float) -> void:
	if not is_instance_valid(app): return
	if current_epoch!=app.datapad_epoch: reset()
	if not app.world_ready or app.loading_stage: return
	if is_instance_valid(app.get("space")) and app.space.aboard():return
	next_poll-=delta
	if next_poll<=0 and not busy and not app.inventory_request_pending and not app.gathering.busy and not bag.action_pending and (not app.has_method("try_background_poll") or app.try_background_poll("corpses")):
		refresh()
