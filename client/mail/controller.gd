extends Node3D
## Persistent native mail. Polls only a bounded summary outside the inbox.
var services:Node
var app:Node
var panel:Control
var surface:Node3D
var canvas:CanvasLayer
var active:=false
var pending:=false
var pending_action:=""
var queued:Dictionary={}
var epoch:=-1
var poll:=0.0
var receipts:Dictionary={}
var unread:=0
var bank_record:Dictionary={}
var pointer_saved:Dictionary={}

func setup(owner_services:Node)->void:
	services=owner_services;app=services.app;epoch=app.datapad_epoch
	panel=preload("res://mail/panel.gd").new()
	canvas=CanvasLayer.new();canvas.layer=30;add_child(canvas);canvas.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if app.xr_requested:
		surface=preload("res://scripts/xr_menu.gd").new();add_child(surface);surface.configure(panel,app.player.get_camera());surface.set_open(false)
	panel.action_requested.connect(request);panel.close_requested.connect(close)
	panel.hide()
	if is_instance_valid(app.get("datapad")):
		app.datapad.ui.mail_requested.connect(open_mail)
	if is_instance_valid(app.get("inventory")) and app.inventory.has_signal("survey_probe_requested"):app.inventory.survey_probe_requested.connect(open_probe)

func reset()->void:
	close();epoch=app.datapad_epoch;pending=false;pending_action="";queued={};receipts.clear();unread=0;poll=0
	panel.messages=[];panel.current={};panel.selected_id="";panel.reader.text="";panel.body.text="";panel.recipient.text="";panel.subject.text="";panel.list.clear();notify_unread(0)
func open_panel()->bool:
	if app.datapad_character_id.is_empty() or not app.world_ready or app.loading_stage:return false
	active=true;panel.show();services.interface_opened()
	if is_instance_valid(services.ui):services.ui.close_interface()
	if is_instance_valid(surface):
		surface.set_open(true)
		for side in ["LeftHand","RightHand"]:
			var pointer=app.xr_origin.get_node_or_null(side+"/FunctionPointer")
			if pointer!=null:pointer_saved[pointer]=pointer.enabled;pointer.enabled=true
	else:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	return true
func close()->void:
	active=false;queued={}
	if is_instance_valid(panel):panel.hide();panel.get_viewport().gui_release_focus()
	if is_instance_valid(surface):surface.set_open(false)
	for pointer in pointer_saved:
		if is_instance_valid(pointer):pointer.enabled=pointer_saved[pointer]
	pointer_saved.clear()
	if is_instance_valid(app) and not app.xr_requested and app.world_ready and not app.menu.visible:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func open_mail()->void:
	if open_panel():panel.show_mode("inbox");request("mail_list",{"page":panel.page})
func open_probe(item:Dictionary={})->void:
	if open_panel():panel.probe_id=str(item.get("id",""));panel.show_mode("probe");request("probe_status",{})
func open_bank(detail:Dictionary)->void:
	bank_record=detail.duplicate(true)
	if open_panel():panel.show_bank(str(detail.terminal_id),int(services.state.get("wallet",{}).get("bank",0)),int(detail.get("amount",0)))
func notify_unread(value:int)->void:
	unread=maxi(0,value)
	if is_instance_valid(app.get("datapad")):
		app.datapad.ui.set_unread_mail(unread)
		if is_instance_valid(app.datapad.radar):app.datapad.radar.set_unread_mail(unread)
func observe(response:Dictionary)->void:
	var state:Dictionary=response.get("state",{})
	if state.has("mail"):
		var changed:=unread!=int(state.mail.get("unread",0))
		notify_unread(int(state.mail.get("unread",0)));panel.set_mail(state.mail)
		if changed and active and panel.mode=="inbox" and not state.mail.has("messages"):queued={"action":"mail_list","detail":{"page":panel.page}}
	if state.has("survey_probes"):panel.set_probes(state.survey_probes)
func request(action:String,detail:Dictionary={})->void:
	if pending or services.busy:
		if pending and pending_action=="mail_status" and action!="mail_status":queued={"action":action,"detail":detail.duplicate(true)};return
		if active:panel.status.text="Wait for the current request to finish, then retry."
		return
	var generation:=epoch
	var key:=action+JSON.stringify(detail)
	var payload:=detail.duplicate(true)
	if action not in ["mail_status","mail_list","probe_status","bank_quote"]:
		if not receipts.has(key):receipts[key]="mail-%d-%d"%[int(Time.get_unix_time_from_system()*1000000),Time.get_ticks_usec()]
		payload.request_id=receipts[key]
	pending=true;pending_action=action
	if active and action!="mail_status":panel.set_pending(true)
	var response:Dictionary=await services.request(action,payload)
	if generation!=epoch:return
	pending=false;pending_action=""
	if response.is_empty():response={"ok":false,"error":"Request not confirmed; retry to check the same operation."}
	if response.get("ok",false):receipts.erase(key)
	if active and action!="mail_status":panel.outcome(action,response)
	if action=="mail_waypoint" and response.get("ok",false):app.refresh_datapad()
	if not queued.is_empty():
		var next:=queued;queued={};call_deferred("request",str(next.action),next.detail)
func _process(delta:float)->void:
	if not is_instance_valid(app):return
	if epoch!=app.datapad_epoch:reset()
	if active and (not app.world_ready or app.loading_stage or app.menu.visible or app.session_leaving or app.player.feedback.life_locked):close()
	if is_instance_valid(surface):surface.set_input_active(app.xr_focused)
	if not app.world_ready or app.loading_stage or app.datapad_character_id.is_empty():return
	poll-=delta
	if poll<=0 and not pending and not services.busy:
		poll=10.0
		request("mail_status",{})
