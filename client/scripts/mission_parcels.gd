extends Node3D
## Temporary hand presentation of a real native mission item. Datapad entries
## reference the same Core3 inventory object; no local container or reward exists.
const HandInput=preload("res://scripts/tracked_hand_input.gd")
var app:Node
var parcels:Dictionary={}
var held:Dictionary={}
var mount:Node3D
var label:Label3D
var visual:MeshInstance3D
var busy:=false
var trigger_armed:=false
var epoch:=-1
var generation:=0
var native_sequence:=-1
var native_session:=""
var receipt:Dictionary={}
var status:=""
func setup(host:Node)->void:
	app=host;process_priority=124
	mount=Node3D.new();add_child(mount);mount.top_level=true
	label=Label3D.new();mount.add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=22;label.pixel_size=.001;label.position.y=.09;label.modulate=Color("baffff");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	mount.hide()
	if is_instance_valid(app.datapad) and app.datapad.has_signal("parcel_draw_requested"):app.datapad.parcel_draw_requested.connect(draw_parcel)
	if is_instance_valid(app.datapad):app.datapad.ui.cancel_mission_requested.connect(cancel_mission)
	reset()
func reset()->void:
	generation+=1;epoch=int(app.datapad_epoch) if is_instance_valid(app) else -1;busy=false;native_sequence=-1;native_session="";parcels.clear();receipt.clear();return_parcel()
	if is_instance_valid(app) and is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")):app.datapad.ui.set_mission_parcels([]);app.datapad.ui.set_owned_missions([])
func observe(response:Dictionary)->void:
	if not response.get("ok",false) or response.get("source_kind")!="core3_services" or str(response.get("character_id",""))!=app.datapad_character_id:return
	var state:Variant=response.get("state")
	if not state is Dictionary or not state.get("parcels") is Array:return
	var live:Variant=response.get("live_response",{})
	if live is Dictionary and not live.is_empty():
		var session:=str(live.get("session_id",""));var sequence:=int(live.get("sequence",-1))
		if session!=preload("res://scripts/native_session_identity.gd").id(app) or sequence<0 or (session==native_session and sequence<native_sequence):return
		native_session=session;native_sequence=sequence
	var next:Dictionary={}
	for item in state.parcels:
		if not item is Dictionary or not str(item.get("id","")).is_valid_int() or str(item.get("mission_id","")).is_empty() or str(item.get("template","" )).is_empty() or next.has(str(item.id)):return
		var entry:Dictionary=item.duplicate(true)
		entry.category="data";entry.type="mission_parcel";entry.deletable=false
		entry.description=str(entry.get("description","Mission parcel. Present it to the designated recipient to complete the assignment."))
		next[str(entry.id)]=entry
	parcels=next
	if not held.is_empty() and not parcels.has(str(held.id)):
		return_parcel();receipt.clear();status="Mission item removed or delivered by Core3."
	if is_instance_valid(app.datapad):
		app.datapad.ui.set_mission_parcels(parcels.values())
		app.datapad.ui.set_owned_missions(state.get("missions",[]))
	if is_instance_valid(app.services) and is_instance_valid(app.services.ui) and app.services.ui.terminal.get("kind","")=="delivery":
		var mission:=str(app.services.ui.terminal.get("mission_id",""))
		if not state.get("delivery_contacts",[]).any(func(contact):return str(contact.get("mission_id",""))==mission):app.services.ui.close_interface()
func cancel_mission(entry:Dictionary)->void:
	if busy or not app.world_ready or app.session_leaving:return
	var mission:String=app.datapad.ui.cancellable_mission_id(entry)
	if mission.is_empty():return
	busy=true
	var version:=generation
	app.datapad.ui.set_busy(true,"Cancelling mission…")
	app.datapad.set_open(false)
	# Closing the wrist UI releases terminal input on the next orchestration frame.
	var deadline:=Time.get_ticks_msec()+2000
	while is_instance_valid(app.services) and (app.services.busy or not app.services.allowed) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
		if version!=generation:return
	var response:Dictionary={}
	if is_instance_valid(app.services) and app.services.allowed and not app.services.busy:
		response=await app.services.request("mission_abort",{"mission_id":mission,"request_id":"cancel-mission-%d-%d"%[int(Time.get_unix_time_from_system()*1000000),Time.get_ticks_usec()]})
	if version!=generation:return
	busy=false
	var confirmed:bool=response.get("ok",false) and response.get("mutation",{}).get("success",false)
	app.datapad.ui.set_busy(false,"Mission cancelled; its mission items were removed." if confirmed else str(response.get("error","Cancellation not confirmed. Refresh and try again.")))
	if confirmed and app.has_method("refresh_datapad"):app.refresh_datapad()

func draw_parcel(entry:Dictionary,hand_pose:Transform3D)->bool:
	if busy or not held.is_empty() or not app.world_ready or app.session_leaving or not hand_pose.is_finite():return false
	var id:=str(entry.get("id",""))
	if not parcels.has(id) or str(parcels[id].mission_id)!=str(entry.get("mission_id","")):return false
	if is_instance_valid(app.inventory) and not app.inventory.held_item.is_empty():
		app.datapad.ui.set_status("Return the held inventory item before drawing the parcel.");return false
	var model:ArrayMesh=app.inventory.assets.model(str(parcels[id].template),parcels[id].get("customization",{}))
	if model==null:app.datapad.ui.set_status("The original mission parcel model is unavailable.");return false
	if is_instance_valid(app.combat_rig):app.combat_rig.stow()
	held=parcels[id].duplicate(true);trigger_armed=false
	visual=MeshInstance3D.new();visual.mesh=model;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mount.add_child(visual)
	visual.position=-model.get_aabb().get_center()
	label.text=str(held.get("name","Mission parcel"));mount.global_transform=hand_pose;mount.show()
	app.datapad.set_open(false)
	return true
func return_parcel()->void:
	held.clear();trigger_armed=false
	if is_instance_valid(visual):visual.free()
	visual=null
	if is_instance_valid(mount):mount.hide()
func blocks_interactions()->bool:return busy or not held.is_empty()
func receiver_at(hand_position:Vector3)->Dictionary:
	if held.is_empty() or not is_instance_valid(app.services) or app.services.state_age>8:return {}
	var identity:Dictionary=app.services.identity_payload()
	for contact:Dictionary in app.services.state.get("delivery_contacts",[]):
		if str(contact.get("mission_id",""))!=str(held.mission_id) or str(contact.get("id",""))!=str(held.get("receiver_id","")) or contact.get("role","")!="receiver":continue
		if str(contact.get("building_id","0"))!=str(identity.building_id) or int(contact.get("cell_index",0))!=int(identity.cell_index):continue
		if not contact.get("position") is Array or contact.position.size()!=3:continue
		var position:Vector3=app.services.world(contact.position)
		if app.player.global_position.distance_to(position)<=2.5 and hand_position.distance_to(position+Vector3.UP*1.1)<=.75:return contact
	return {}
func delivery_frame(tracked:bool,hand_pose:Transform3D,grip:float,trigger:float)->void:
	if held.is_empty():return
	if not tracked or not hand_pose.is_finite():return_parcel();return
	mount.global_transform=hand_pose
	if grip<.35 and not busy:return_parcel();return
	if trigger<.3:trigger_armed=true
	if busy or not trigger_armed or trigger<.55:return
	trigger_armed=false
	var receiver:=receiver_at(hand_pose.origin)
	if receiver.is_empty():label.text="Present the parcel to its recipient";return
	deliver(receiver)
func deliver(receiver:Dictionary)->void:
	if busy or held.is_empty() or not parcels.has(str(held.id)):return
	busy=true
	var version:=generation
	var item:=held.duplicate(true)
	if receipt.is_empty() or str(receipt.get("parcel_id",""))!=str(item.id):
		receipt={"npc_id":str(receiver.id),"mission_id":str(item.mission_id),"parcel_id":str(item.id),"request_id":"parcel-%d-%d"%[int(Time.get_unix_time_from_system()*1000000),Time.get_ticks_usec()]}
	label.text="Delivering…"
	while is_instance_valid(app.services) and app.services.busy:
		await get_tree().process_frame
		if version!=generation:return
	if not is_instance_valid(app.services) or not app.services.allowed:busy=false;label.text="Interaction unavailable. Try again.";return
	var response:Dictionary=await app.services.request("delivery_complete",receipt.duplicate(true))
	if version!=generation:return
	busy=false
	var confirmed:bool=response.get("ok",false) and response.get("mutation",{}).get("success",false)
	if confirmed:
		receipt.clear()
		if is_instance_valid(app.services.ui):app.services.ui.close_interface()
		status="Parcel handed over. Core3 is completing the mission."
	else:
		status=str(response.get("error",response.get("mutation",{}).get("error_code","Delivery was not confirmed. Keep the parcel and try again.")))
		if not held.is_empty():label.text=status
func _process(_delta:float)->void:
	if not is_instance_valid(app):return
	if epoch!=app.datapad_epoch:reset()
	if held.is_empty():return
	if not app.world_ready or app.loading_stage or app.session_leaving or app.menu.visible or not app.xr_requested:
		if not busy:return_parcel()
		return
	var hand:XRController3D=app.xr_origin.get_node("RightHand" if app.vr_settings.offhand=="left" else "LeftHand")
	var head=XRServer.get_tracker("head")
	var head_pose:XRPose=head.get_pose("default") if head!=null else null
	var tracked:bool=app.xr_focused and head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(hand)
	delivery_frame(tracked,hand.global_transform,hand.get_float("grip"),hand.get_float("trigger"))
