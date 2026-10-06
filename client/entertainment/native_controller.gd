extends Node
## Native Core3 permissions/actions; the older bus is presentation only.
const Identity=preload("res://scripts/native_session_identity.gd")
const Planet=preload("res://scripts/planet_catalog.gd")
const Hands=preload("res://scripts/tracked_hand_input.gd")
var performer:Node
var host:Node
var state:Dictionary={}
var sequence:=-1
var generation:=0
var busy:=false
var pending_actions:Array[Dictionary]=[]
var clock:=0.0
var age:=100.0
var owner_session:=""
var gesture=preload("res://entertainment/register_location_gesture.gd").new()
var progress_label:Label3D
var design_ui:Node3D
var last_effect_revision:=-1
var remote_effects:Dictionary={}
var effects:Node3D
func setup(value:Node)->void:
	performer=value;host=value.host;reset()
	if not is_instance_valid(progress_label):
		progress_label=Label3D.new();add_child(progress_label);progress_label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");progress_label.font_size=26;progress_label.pixel_size=.0008;progress_label.modulate=Color("b8ffff");progress_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;progress_label.hide()
	if not is_instance_valid(design_ui):
		design_ui=preload("res://entertainment/image_design_surface.gd").new();add_child(design_ui)
		design_ui.configure(performer.origin,performer.body,"left" if performer.dominant()=="right" else "right");design_ui.action_requested.connect(request)
		design_ui.opened.connect(func():
			performer.ui.close()
			if is_instance_valid(host.get("inventory")):host.inventory.set_open(false)
			if is_instance_valid(host.get("datapad")):host.datapad.set_open(false))
	if not is_instance_valid(effects):
		effects=preload("res://entertainment/effects.gd").new();add_child(effects);effects.configure(performer.assets,performer.head)
func reset()->void:
	generation+=1;pending_actions.clear();state={};sequence=-1;busy=false;clock=0;age=100;owner_session="";last_effect_revision=-1;remote_effects.clear();gesture.reset()
	if is_instance_valid(progress_label):progress_label.hide()
	if is_instance_valid(design_ui):design_ui.set_allowed(false)
	clear_registration_points()
func clear_registration_points()->void:
	if is_instance_valid(host) and is_instance_valid(host.get("datapad")) and is_instance_valid(host.datapad.get("ui")) and host.datapad.ui.has_method("set_registered_locations"):host.datapad.ui.set_registered_locations([])
func bound()->bool:
	return is_instance_valid(host) and not Identity.id(host).is_empty() and not str(host.get("datapad_character_id")).is_empty()
func identity()->Dictionary:
	var source:Vector3=host.source_position_at(performer.body.global_position)
	var payload:Dictionary={"account":str(host.datapad_account),"character_id":str(host.datapad_character_id),"live_session_id":Identity.id(host),"zone":Planet.current(host),"position":[source.x,source.y,source.z],"building_id":"0","cell_index":0}
	if is_instance_valid(host.stage):
		var cell:Dictionary=host.stage.current_cell
		payload.building_id=str(cell.get("building_object_id","0"));payload.cell_index=int(str(cell.get("cell_id","0:0")).get_slice(":",1))
	return payload
func allowed()->bool:
	if not bound() or not bool(host.get("world_ready")) or bool(host.get("loading_stage")) or not performer.body.active:return false
	if bool(host.get("xr_requested")) and not bool(host.get("xr_focused")):return false
	if performer.body.feedback.combat_blocked():return false
	for key in ["menu","creator"]:
		var node:Variant=host.get(key)
		if is_instance_valid(node) and node.visible:return false
	return true
func registration_allowed()->bool:
	if not allowed() or busy or age>16 or not state.get("registration",{}).get("eligible",false) or state.get("registration",{}).get("registered",false):return false
	if gesture.progress==0 and age>5:return false
	var services:Variant=host.get("services")
	if is_instance_valid(services) and services.has_method("blocks_combat") and services.blocks_combat():return false
	for key in ["vendor_commerce","vendor_placement","mission_parcels"]:
		var interaction:Variant=host.get(key)
		if is_instance_valid(interaction) and interaction.has_method("blocks_interactions") and interaction.blocks_interactions():return false
	if performer.ui.menu_open or (is_instance_valid(design_ui) and not design_ui.terminal.is_empty()):return false
	for key in ["inventory","datapad"]:
		var node:Variant=host.get(key)
		if is_instance_valid(node) and bool(node.get("is_open")):return false
	return true
func image_active(value:Dictionary)->bool:
	return bool(value.get("active",false)) and not str(value.get("session_id","")).is_empty()
func image_eligible()->bool:
	return age<=15 and ("imagedesign" in state.get("commands",[]) or "social_imagedesigner_novice" in state.get("skills",[]))
func group_available()->bool:
	return age<=15 and not str(state.get("group_inviter_id","")).is_empty() and str(state.get("group_inviter_id","0"))!="0"
func group_selector()->void:
	if not allowed() or age>15:return
	design_ui.set_allowed(true);design_ui.show_candidates(state.get("group_candidates",[]).filter(func(row):return not row.get("self",false) and not row.get("in_same_group",false)),"group_invite")
func image_open_selector()->void:
	if not allowed() or not image_eligible():return
	design_ui.set_allowed(true);design_ui.show_candidates(state.get("nearby_players",[]))
func _process(delta:float)->void:
	if not is_instance_valid(performer) or not is_instance_valid(host):return
	age+=delta;clock-=delta
	if age>30:clear_registration_points()
	var id:=Identity.id(host)
	if not bound():
		if not owner_session.is_empty():reset()
		return
	if id!=owner_session:
		reset();owner_session=id
	if is_instance_valid(design_ui):
		design_ui.avatar=host.get("tracked_avatar");design_ui.set_allowed(allowed())
		var design:Dictionary=state.get("image_design",{})
		if allowed() and image_active(design) and str(design_ui.terminal.get("id",""))!=str(design.session_id):design_ui.show_design(design)
	if not busy and not pending_actions.is_empty():
		flush_pending_actions()
		return
	if busy or clock>0 or not allowed() or (gesture.progress>0 and not gesture.latched):return
	var active:bool=image_active(state.get("image_design",{}))
	if not active and host.has_method("try_background_poll") and not host.try_background_poll("entertainer"):return
	request("status")
func _physics_process(delta:float)->void:
	if not is_instance_valid(performer) or not is_instance_valid(performer.origin):gesture.interrupt();return
	var origin:XROrigin3D=performer.origin
	var left:XRController3D=origin.get_node("LeftHand");var right:XRController3D=origin.get_node("RightHand")
	var tracker=XRServer.get_tracker("head");var head_pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:bool=head_pose!=null and head_pose.has_tracking_data and Hands.controller_tracked(left) and Hands.controller_tracked(right)
	var physical:Dictionary=performer.body.feedback.physical()
	var standing:bool=int(physical.get("posture",-1))==0 and bool(physical.get("grounded",false))
	sample_registration(delta,performer.head.global_transform,left.global_transform,right.global_transform,tracked,standing)
func sample_registration(delta:float,head:Transform3D,left:Transform3D,right:Transform3D,tracked:bool,standing:bool)->void:
	var eligible:=registration_allowed()
	if gesture.sample(delta,head,left,right,tracked,standing,eligible):request("register_location")
	if is_instance_valid(progress_label):
		progress_label.visible=eligible and gesture.progress>0 and not gesture.latched
		progress_label.global_position=head.origin-head.basis.z*.65+Vector3.DOWN*.18
		progress_label.text="Register performance location\nHold raised arms · %d%%"%roundi(gesture.progress*100)
func flush_pending_actions()->void:
	if busy or pending_actions.is_empty():return
	var entry:Dictionary=pending_actions.pop_front()
	if not allowed() or Time.get_ticks_msec()>int(entry.expires) or (entry.action=="perform" and str(performer.item.get("id",""))!=str(entry.item_id)):
		performer.message="Performance input expired or changed; perform the gesture again."
		return
	request(str(entry.action),entry.detail)

func request(action:String,detail:Dictionary={})->Dictionary:
	if not bound():return {}
	if busy:
		if action!="status" and allowed() and pending_actions.size()<4:
			var duplicate:bool=pending_actions.any(func(entry):return entry.action==action and entry.detail==detail)
			if not duplicate:pending_actions.append({"action":action,"detail":detail.duplicate(true),"item_id":str(performer.item.get("id","")),"expires":Time.get_ticks_msec()+2500})
			return {"queued":true}
		return {}
	if action!="status" and not allowed():return {}
	busy=true;clock=1.0 if image_active(state.get("image_design",{})) else 5.0
	var epoch:=generation;var owner:=Identity.id(host)
	var payload:=identity();payload.merge(detail,true)
	if action!="status":payload.request_id="ent-"+Crypto.new().generate_random_bytes(16).hex_encode()
	if action=="perform":payload.item_id=str(performer.item.get("id",""))
	if action.begins_with("image_") and is_instance_valid(design_ui):design_ui.set_pending(true)
	var reply:Dictionary=await host.api(HTTPClient.METHOD_POST,"/entertainer/"+action,payload)
	if epoch!=generation or owner!=Identity.id(host):return {}
	busy=false
	if not accept(reply) or not reply.get("ok",false):
		performer.message=str(reply.get("error",reply.get("mutation",{}).get("error_code","Core3 did not confirm this action.")))
		if is_instance_valid(design_ui):design_ui.set_pending(false);design_ui.panel.message=performer.message;design_ui.panel.queue_redraw()
	elif action=="group_invite" and is_instance_valid(design_ui):design_ui.close_interface()
	return reply
func accept(reply:Dictionary)->bool:
	if not bound():return false
	if reply.get("source_kind","")!="core3_entertainer" or str(reply.get("character_id",""))!=str(host.datapad_character_id):return false
	var incoming:Variant=reply.get("state")
	var revision:=int(reply.get("sequence",reply.get("live_response",{}).get("sequence",-1)))
	if not incoming is Dictionary or str(incoming.get("zone",Planet.current(host)))!=Planet.current(host) or revision<sequence or revision<0:return false
	if not incoming.get("skills") is Array or not incoming.get("commands") is Array or not incoming.get("flourishes") is Array:return false
	var live:Variant=reply.get("live_response")
	if live is Dictionary and (str(live.get("session_id",""))!=Identity.id(host) or str(live.get("character_id",""))!=str(host.datapad_character_id)):return false
	var session:Variant=host.get("gameplay_session")
	if live is Dictionary and is_instance_valid(session) and session.live and not session.accept_native_response(live):return false
	state=incoming.duplicate(true);sequence=revision;age=0
	var updated:Dictionary={"character_id":str(host.datapad_character_id),"complete":true,"skills":state.skills.duplicate(),"commands":state.commands.duplicate(),"flourishes":state.flourishes.duplicate(),"entertainer":"social_entertainer_novice" in state.skills}
	performer.apply_native_context(updated)
	if state.get("appearance") is Dictionary and host.has_method("apply_native_appearance"):host.apply_native_appearance(state.appearance)
	if is_instance_valid(host.get("datapad")) and is_instance_valid(host.datapad.get("ui")) and host.datapad.ui.has_method("set_registered_locations"):host.datapad.ui.set_registered_locations(state.get("registrations",[]))
	var design:Dictionary=state.get("image_design",{})
	if is_instance_valid(design_ui):
		design_ui.set_pending(false);design_ui.set_allowed(allowed())
		if image_active(design) and allowed():design_ui.show_design(design)
		elif str(design_ui.terminal.get("id",""))!="image-design-targets":design_ui.close_interface()
	var mutation:Dictionary=reply.get("mutation",{})
	if mutation.get("success",false) and revision>last_effect_revision:
		last_effect_revision=revision
		var effect:=str(mutation.get("effect_file",""));var point:Variant=mutation.get("effect_position")
		if not effect.is_empty() and point is Array and point.size()==3 and is_instance_valid(effects):
			var origin:Array=host.stage.get_meta("manifest",{}).get("origin",[0,0,0])
			effects.play(effect,Transform3D(Basis.IDENTITY,host.stage.to_global(Vector3(float(point[0])-float(origin[0]),float(point[1])-float(origin[1]),float(origin[2])-float(point[2])))))
	performer.message=str(mutation.get("message",mutation.get("error_code","")))
	return true

func observe_bus(reply:Dictionary)->void:
	if not is_instance_valid(host):return
	for band in reply.get("bands",[]):
		if not band is Dictionary:continue
		var effect:Dictionary=band.get("flourish",{})
		var actor:=str(effect.get("actor",""));var revision:=int(effect.get("sequence",-1))
		if effect.get("source_kind","")!="core3_entertainer" or actor.is_empty() or actor==str(host.datapad_character_id) or revision<=int(remote_effects.get(actor,-1)):continue
		if str(effect.get("effect_file","")).is_empty():continue
		var point:Variant=effect.get("effect_position")
		if not point is Array or point.size()!=3:continue
		remote_effects[actor]=revision
		if remote_effects.size()>64:remote_effects.erase(remote_effects.keys()[0])
		var source:=Vector3(float(point[0]),float(point[1]),float(point[2]))
		if not source.is_finite() or not is_instance_valid(host.stage) or not is_instance_valid(effects):continue
		var anchor:Array=host.stage.get_meta("manifest",{}).get("origin",[0,0,0])
		effects.play(str(effect.effect_file),Transform3D(Basis.IDENTITY,host.stage.to_global(Vector3(source.x-float(anchor[0]),source.y-float(anchor[1]),float(anchor[2])-source.z))))
