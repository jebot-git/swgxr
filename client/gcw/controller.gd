extends Node3D
## Native GCW state presentation and one deliberate tracked salute request.
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Fingers=preload("res://scout/ranger_input.gd")
var services:Node3D
var app:Node
var recognizer:=SwgSaluteGesture.new()
var label:Label3D
var message:=""
var message_until:=0
var scan_shown:=""
var claims:=false
func setup(owner:Node3D)->void:
	services=owner;app=services.app;process_physics_priority=-108
	label=Label3D.new();add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=26;label.pixel_size=.001;label.modulate=Color("b8ffff");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.hide()
func reset()->void:
	recognizer.reset();message="";message_until=0;scan_shown="";claims=false
	if is_instance_valid(label):label.hide()
func outcome(value:String)->void:message=value;message_until=Time.get_ticks_msec()+8000
func state()->Dictionary:return services.state.get("gcw",{})
func observe(response:Dictionary)->void:
	var mutation:Dictionary=response.get("mutation",{})
	var operation:=str(mutation.get("operation",mutation.get("action","")))
	if mutation.has("success") and not bool(mutation.success):outcome(str(mutation.get("error",mutation.get("message","CoreCU rejected the request."))))
	elif operation=="recruiter_status_toggle":
		if state().get("changing",false):outcome("Duty change queued by CoreCU · "+pending_text())
		else:outcome("Duty: "+str(state().get("status_name","unknown")).replace("_"," "))
	if operation=="contraband_answer" and mutation.get("success",false):outcome("Inspection answer recorded · awaiting CoreCU patrol outcome.")
	var scan:Dictionary=state().get("scan",{})
	if not is_instance_valid(services.ui):return
	if not scan.get("active",false) or not scan.get("answer_pending",false):
		if services.ui.terminal.get("kind","")=="contraband":services.ui.close_interface()
		if not scan.get("active",false):scan_shown=""
		return
	var id:=str(scan.get("id",""))
	if id.is_empty():return
	var head:Camera3D=app.xr_origin.get_node("XRCamera3D")
	var forward:=(-head.global_basis.z).slide(Vector3.UP).normalized()
	if forward.length_squared()<.5:forward=Vector3.FORWARD
	var center:=head.global_position+forward-Vector3.UP*.18
	var terminal:Dictionary={"id":"scan:"+id,"kind":"contraband","name":"CONTRABAND INSPECTION","scan":scan.duplicate(true),"position":Vector3(head.global_position.x,app.player.global_position.y,head.global_position.z),"ui_position":center}
	if services.ui.terminal.get("kind","")=="contraband" and str(services.ui.terminal.get("scan",{}).get("id",""))==id:
		terminal=services.ui.terminal.duplicate(true);terminal.scan=scan.duplicate(true)
		services.ui.apply_response({"terminal":terminal,"mutation":mutation});return
	if scan_shown!=id and services.allowed:
		scan_shown=id;services.ui.open_terminal(terminal)
func pending_text()->String:
	var target:="combatant" if int(state().get("pending_status",-1))==1 else "on leave"
	var left:=maxi(0,int(state().get("cooldown_remaining_ms",0))-int(services.state_age*1000))
	return "%s in about %ds"%[target,ceili(left/1000.0)] if left>0 else "Awaiting native "+target+" confirmation"
func actor(id:String)->Node3D:
	var live:Variant=app.get("live_combat")
	if is_instance_valid(live) and live.live:return live.actors.get(id)
	var sync:Variant=app.get("multiplayer_sync")
	return sync.entities.actors.get(id) if is_instance_valid(sync) and is_instance_valid(sync.entities) else null
func recruiter_menu_open()->bool:
	return is_instance_valid(services.ui) and services.ui.terminal.get("kind","")=="recruiter" and not services.ui.wallet_held and not services.ui.pending and not services.ui.pointer_pressed and not services.ui.panel.pointer_down and not services.ui.panel.drag_scrolling
func target(head:Transform3D)->Dictionary:
	var selected:Dictionary={};var score:=INF
	for row:Dictionary in state().get("recruiters",[]):
		if is_instance_valid(services.ui) and not services.ui.terminal.is_empty() and str(services.ui.terminal.get("id",""))!=str(row.id):continue
		if not row.get("can_salute",false) or str(row.get("faction",""))!=str(state().get("faction","")):continue
		var npc:=actor(str(row.id))
		if not is_instance_valid(npc) or not npc.is_visible_in_tree() or not npc.is_targetable() or app.player.global_position.distance_to(npc.global_position)>3:continue
		var anchor:Variant=preload("res://pets/creature_targeting.gd").head_anchor(npc)
		if not anchor is Vector3:continue
		var delta:Vector3=anchor-head.origin;var alignment:float=(-head.basis.z).dot(delta.normalized())
		if alignment<cos(deg_to_rad(20)) or delta.length()>3.5:continue
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(head.origin,anchor,7)).is_empty():continue
		var rank:float=(1-alignment)*10+delta.length()*.1
		if rank<score:score=rank;selected=row
	return selected
func permitted(side:String)->bool:
	if not services.allowed or services.busy or services.state_age>8 or not app.world_ready or app.loading_stage or not app.xr_requested or not app.xr_focused:return false
	if not app.player.active or app.player.feedback.combat_blocked() or (services.blocks_combat() and not recruiter_menu_open()):return false
	if is_instance_valid(services.ui) and not services.ui.allowed:return false
	for key in ["entertainer","vendor_commerce","vendor_placement","mission_parcels"]:
		var interaction:Variant=app.get(key)
		if is_instance_valid(interaction) and interaction.blocks_interactions():return false
	for key in ["voice_controls","corpse_gathering"]:
		var interaction:Variant=app.get(key)
		if is_instance_valid(interaction) and interaction.blocks_combat():return false
	var voice:Variant=app.get("desktop_voice_panel")
	if is_instance_valid(voice) and voice.visible:return false
	for key in ["datapad","crafting"]:
		var panel:Variant=app.get(key)
		if is_instance_valid(panel) and panel.is_open:return false
	for key in ["menu","creator"]:
		var menu:Variant=app.get(key)
		if is_instance_valid(menu) and menu.visible:return false
	var bag:Variant=app.get("inventory")
	if is_instance_valid(bag) and (bag.is_open or (not bag.held_item.is_empty() and bag.held_hand_side()==side)):return false
	var combat:Variant=app.get("combat_rig")
	if is_instance_valid(combat) and (combat.selected>=0 or combat.support_latched):return false
	var vehicle:Variant=app.get("vehicles")
	if is_instance_valid(vehicle) and vehicle.seated():return false
	var scout:Variant=app.get("scout")
	if is_instance_valid(scout) and (scout.blocks_interactions() or (is_instance_valid(scout.ranger) and scout.ranger.claims)):return false
	var pets:Variant=app.get("pets")
	if is_instance_valid(pets) and is_instance_valid(pets.commands) and (pets.commands.wheel.menu_open or not pets.commands.state.selection.is_empty()):return false
	return not state().get("changing",false)
func _physics_process(delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(app.get("xr_origin")):return
	var rig:XROrigin3D=app.xr_origin;var head:Camera3D=rig.get_node("XRCamera3D");var side:="right" if str(app.vr_settings.offhand)=="left" else "left"
	var controller:XRController3D=rig.get_node(side.capitalize()+"Hand");var optical:=Hands.tracked_joints(side)
	var pose:Transform3D=rig.global_transform*optical.grip if not optical.is_empty() else controller.global_transform
	var tracker=XRServer.get_tracker("head");var head_pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:bool=(not optical.is_empty() or Hands.controller_tracked(controller)) and head_pose!=null and head_pose.has_tracking_data
	var open:bool=(Fingers.curl(optical.get("joints",{}),"index")<.25 and Fingers.curl(optical.get("joints",{}),"ring")<.25) if not optical.is_empty() else (controller.get_float("grip")<.25 and controller.get_float("trigger")<.25)
	var allowed:=permitted(side);var selected:=target(head.global_transform) if allowed and tracked else {}
	var sample:Dictionary=recognizer.sample(delta,str(selected.get("id","")),head.global_transform,pose.origin,side=="right",open,tracked,allowed)
	claims=allowed and tracked and (float(sample.progress)>0 or bool(sample.latched))
	label.visible=services.allowed and (not services.blocks_combat() or recruiter_menu_open()) and app.world_ready and not app.loading_stage and app.xr_focused and (float(sample.progress)>0 or Time.get_ticks_msec()<message_until)
	label.global_position=head.global_position-head.global_basis.z*.75+Vector3.DOWN*.2
	label.text="Salute · %d%%"%roundi(float(sample.progress)*100) if float(sample.progress)>0 else message
	if str(sample.action)=="salute":
		outcome("Requesting duty change from CoreCU…")
		services.request("recruiter_status_toggle",{"terminal_id":str(selected.id),"expected_status":int(state().get("status",-1))})
