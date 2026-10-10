extends Node3D
## Runtime-neutral, local presentation and gestures for authoritative Core3 services.
## No balance, inventory, mission, or travel state is mutated here.
signal action_requested(action: String, payload: Dictionary)
signal opened
signal closed
signal wallet_changed(held: bool)
const ServicePanel=preload("res://gcw/panel.gd")
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const InventoryAssets=preload("res://scripts/inventory_assets.gd")
const PANEL_METERS=Vector2(0.64,0.4614)
const CLOSE_DISTANCE=3.0
const WALLET_TEMPLATE="object/tangible/item/loot_credit_chip.iff"
var rig: XROrigin3D
var body: CharacterBody3D
var avatar: Node3D
var offhand := "left"
var allowed := false
var terminal_provider: Callable
var remote_hands_provider: Callable
var wallet_model_factory: Callable
var terminal: Dictionary={}
var wallet: Dictionary={"cash":0,"bank":0}
var tickets: Array=[]
var wallet_held := false
var pending := false
var panel: Control
var viewport: SubViewport
var surface: MeshInstance3D
var wallet_mount: Node3D
var wallet_readout: Label3D
var terminal_origin:=Vector3.ZERO
var grip_armed:=false
var trigger_armed:=false
var pointer_pressed:=false
var pointer_grip_armed:=false
var pointer_button:=""
var pointer_visual: Node3D
var stick_scroll:=0.0
var stick_captured:=false
var drag_hand_anchor:=Vector3.ZERO
var drag_pixel_anchor:=Vector2.ZERO
var pointer_last:=Vector2.ZERO
var interaction_epoch:=0
var assets:=InventoryAssets.new()
var point_math:=SwgWristDatapad.new()
var slider_surface:Dictionary={}
var handshake_id:=""
var handshake_seconds:=0.0
var handshake_latched:=false
var handshake_anchor:=Vector3.ZERO
var handshake_travel:=0.0
var boarding_latch:=""
var pointer_saved: Dictionary={}
var inventory_focus:=false
var inventory_focus_provider:Callable

func configure(origin: XROrigin3D, player: CharacterBody3D, side: String="left") -> void:
	rig=origin;body=player;offhand="right" if side=="right" else "left"
	process_priority=123
	pointer_visual=preload("res://scripts/finger_pointer_visual.gd").new();add_child(pointer_visual)
	panel=ServicePanel.new()
	viewport=SubViewport.new();viewport.size=Vector2i(860,620)
	viewport.transparent_bg=true;viewport.disable_3d=true;viewport.gui_disable_input=false
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport);viewport.add_child(panel)
	panel.action_requested.connect(request_action)
	panel.close_requested.connect(close_interface)
	surface=MeshInstance3D.new();add_child(surface);surface.top_level=true
	var quad:=QuadMesh.new();quad.size=PANEL_METERS;surface.mesh=quad
	surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture=viewport.get_texture();material.cull_mode=BaseMaterial3D.CULL_BACK
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.material_override=material;surface.visible=false
	wallet_mount=Node3D.new();add_child(wallet_mount);wallet_mount.top_level=true;wallet_mount.visible=false
	wallet_readout=Label3D.new();wallet_mount.add_child(wallet_readout)
	wallet_readout.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	wallet_readout.font_size=32;wallet_readout.pixel_size=0.0010
	wallet_readout.modulate=Color("baffff");wallet_readout.outline_size=3
	wallet_readout.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	wallet_readout.position=Vector3(0,0.17,0)
	assets.configure()
	set_wallet(wallet)

func set_allowed(value: bool) -> void:
	if allowed==value: return
	allowed=value
	if not value:
		close_interface();set_wallet_held(false)
		grip_armed=false;trigger_armed=false
		handshake_id="";handshake_seconds=0;handshake_latched=false

func set_inventory_focus(value: bool) -> void:
	if inventory_focus==value:return
	inventory_focus=value
	if value:
		pointer_pressed=false;pointer_button="";trigger_armed=false;pointer_grip_armed=false
		panel.cancel_pointer();set_stick_capture(false);pointer_visual.hide()

func confirm_button(side: String) -> bool:
	if inventory_focus_provider.is_valid():set_inventory_focus(bool(inventory_focus_provider.call()))
	if not allowed or inventory_focus or terminal.is_empty() or side==offhand:return false
	if not pending and not pointer_pressed:panel.confirm_navigation()
	return true

func blocks_combat() -> bool:
	return wallet_held or not terminal.is_empty()

func set_wallet(value: Dictionary) -> void:
	var updated: Dictionary={"cash":maxi(int(value.get("cash",0)),0),"bank":maxi(int(value.get("bank",0)),0)}
	updated.faction_delegation=bool(value.get("faction_delegation",false))
	updated.faction_points={};updated.faction_limits={}
	updated.delegation_ratio=maxf(1.0,float(value.get("delegation_ratio",1.0)))
	for faction in ["imperial","rebel"]:
		updated.faction_points[faction]=maxi(0,int(value.get("faction_points",{}).get(faction,0)))
		updated.faction_limits[faction]=maxi(0,int(value.get("faction_limits",{}).get(faction,0)))
	var changed:=wallet!=updated
	wallet=updated
	if is_instance_valid(wallet_readout): wallet_readout.text="WALLET\n%d cr carried\n%d cr bank"%[wallet.cash,wallet.bank]
	if is_instance_valid(panel) and changed: panel.wallet=wallet.duplicate(true);panel.update_limit();panel.queue_redraw()

func set_pending(value: bool) -> void:
	pending=value
	if is_instance_valid(panel): panel.set_pending(value)

func apply_response(response: Dictionary, resolve_pending: bool=true) -> void:
	if response.get("wallet") is Dictionary: set_wallet(response.wallet)
	if response.get("tickets") is Array: tickets=response.tickets.duplicate(true)
	if resolve_pending: set_pending(false)
	var mutation: Dictionary=response.get("mutation",{})
	var updated: Dictionary=response.get("terminal",{}).duplicate(true)
	if updated.get("kind","")=="recruiter":updated.gcw=response.get("gcw",{}).duplicate(true)
	# A late response must not reopen a closed/different terminal.
	if terminal.get("kind","")!="ship_crew" and not terminal.is_empty() and str(updated.get("id",""))==str(terminal.get("id","")) and not updated.is_empty() and (terminal.get("kind","")!="delivery" or str(updated.get("mission_id",""))==str(terminal.get("mission_id",""))):
		var anchor: Variant=terminal.get("position",terminal_origin)
		var changed:=false
		for key in ["front_money","reputation","reward_faction","reward_credits","duration_seconds","tier_minimum","tier_maximum","blocked_reason","tier","eligible","kind","listings","missions","destinations","tools","categories","category_id","page","has_more","skills","ships","trainer_text","profession","dialogue","confirm_action","stage","parcel_id","options","maintenance","maintenance_rate","item_count","item_limit","owner","recruiter_text","faction","status","can_join","can_toggle","reason","rewards","gcw","scan","rank","rank_name","next_rank","next_rank_name","promotion_cost_faction_points","can_promote","promotion_reason"]:
			if updated.has(key) and updated[key]!=terminal.get(key): changed=true
		terminal.merge(updated,true);terminal.position=anchor
		if changed:
			panel.configure(terminal,wallet,tickets)
			panel.set_pending(pending)
		else:
			var upkeep:bool=panel.terminal.get("kind","")=="house_deposit" and terminal.get("kind","")=="house"
			panel.terminal=terminal.duplicate(true)
			if upkeep:panel.terminal.kind="house_deposit"
	panel.message=str(mutation.get("message",mutation.get("error",mutation.get("error_code",""))))
	if mutation.has("success") and bool(mutation.success) and panel.message.is_empty(): panel.message="Confirmed by Core3"
	panel.queue_redraw()

func request_action(action: String, payload: Dictionary) -> void:
	if not allowed: panel.set_pending(false);return
	pending=true
	action_requested.emit(action,payload)

func face_pose(center: Vector3, head: Vector3) -> Transform3D:
	var normal:=(head-center).slide(Vector3.UP).normalized()
	if normal.length_squared()<0.5: normal=Vector3.BACK
	return Transform3D(Basis(Vector3.UP.cross(normal),Vector3.UP,normal),center)

func open_terminal(record: Dictionary) -> void:
	if not allowed or pending or str(record.get("id","")).is_empty(): return
	close_interface()
	terminal=record.duplicate(true)
	terminal_origin=record.get("position",Vector3.ZERO)
	var head: Vector3=rig.get_node("XRCamera3D").global_position
	var facing:=(head-terminal_origin).slide(Vector3.UP).normalized()
	if facing.length_squared()<0.5: facing=Vector3.BACK
	var center:=terminal_origin+facing*0.38
	center.y=clampf(head.y-0.18,terminal_origin.y+0.85,terminal_origin.y+1.65)
	if record.get("ui_position") is Vector3: center=record.ui_position
	surface.global_transform=terminal_pose(record,center,head)
	panel.selected=-1;panel.offset=0;panel.message="Connecting to Core3…"
	panel.configure(terminal,wallet,tickets)
	surface.visible=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	trigger_armed=false
	sync_pointers();opened.emit()
	set_pending(true)
	if record.get("kind","") in ["contraband","bounty_informant","bounty_droid"]:set_pending(false);return
	if record.get("kind","")=="delivery":action_requested.emit("delivery_open",{"npc_id":str(record.id),"mission_id":str(record.get("mission_id",""))})
	else:action_requested.emit("open",{"terminal_id":str(record.id)})

func close_interface() -> void:
	var was_open:=not terminal.is_empty()
	terminal={};interaction_epoch+=1
	pointer_pressed=false;pointer_button="";stick_scroll=0
	set_stick_capture(false)
	if is_instance_valid(pointer_visual):pointer_visual.hide()
	if is_instance_valid(panel):
		panel.cancel_pointer()
		if panel.has_method("interface_closed"):panel.interface_closed()
	if is_instance_valid(surface): surface.visible=false
	if is_instance_valid(viewport): viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	# Request latches remain server-owned; closing cannot enable duplicate mutations.
	sync_pointers()
	if was_open: closed.emit()

func set_wallet_held(value: bool) -> void:
	if wallet_held==value: return
	wallet_held=value
	wallet_mount.visible=value
	if value:
		for child in wallet_mount.get_children():
			if child!=wallet_readout: child.queue_free()
		var model: Node3D=wallet_model_factory.call() if wallet_model_factory.is_valid() else assets.instance(WALLET_TEMPLATE,0.13)
		if model!=null: wallet_mount.add_child(model)
	else:
		if terminal.get("kind","")=="payment": close_interface()
		handshake_id="";handshake_seconds=0;handshake_latched=false
	wallet_changed.emit(value);sync_pointers()

func back_contains(head: Transform3D, hand: Vector3) -> bool:
	var heading: Transform3D=rig.global_transform if is_instance_valid(rig) else Transform3D.IDENTITY
	var center: Vector3=preload("res://scripts/body_grab_anchor.gd").from_pose(head,heading,Vector3(0,-.50,.25)).origin
	return hand.distance_to(center)<.28

func update_wallet_gesture(tracked: bool, head: Transform3D, hand: Transform3D, grip: float) -> void:
	if not allowed or not tracked:
		set_wallet_held(false);grip_armed=false;return
	if grip<0.35:
		grip_armed=true
		if wallet_held: set_wallet_held(false)
	elif grip>=0.65 and grip_armed:
		grip_armed=false
		if not wallet_held and back_contains(head,hand.origin):
			set_wallet_held(true)
			action_requested.emit("status",{})
	if wallet_held: wallet_mount.global_transform=hand

func update_handshake(hand: Transform3D, grip: float, peers: Array, delta: float) -> void:
	if not wallet_held or not allowed or grip<0.65:
		handshake_id="";handshake_seconds=0;handshake_travel=0;handshake_latched=false;return
	var candidate: Dictionary={}
	for peer: Dictionary in peers:
		if not str(peer.get("crew_launch_id","")).is_empty():continue
		if not bool(peer.get("fresh",false)) or not bool(peer.get("authenticated",false)) or float(peer.get("grip",0))<0.65: continue
		if not peer.get("hand_position") is Vector3 or str(peer.get("id","")).is_empty(): continue
		if hand.origin.distance_to(peer.hand_position)>0.13: continue
		candidate=peer;break
	if candidate.is_empty():
		handshake_id="";handshake_seconds=0;handshake_travel=0;handshake_latched=false;return
	var identifier:=str(candidate.id)
	if handshake_id!=identifier:
		handshake_id=identifier;handshake_seconds=0;handshake_travel=0;handshake_anchor=hand.origin;handshake_latched=false
	handshake_seconds+=minf(delta,0.1)
	handshake_travel+=minf(hand.origin.distance_to(handshake_anchor),0.04)
	handshake_anchor=hand.origin
	if not pending and not handshake_latched and handshake_seconds>=0.35 and handshake_travel>=0.035 and bool(candidate.get("handshake_authorized",false)):
		handshake_latched=true
		show_payment(candidate)

func show_payment(peer: Dictionary) -> void:
	if pending or not wallet_held or not bool(peer.get("handshake_authorized",false)): return
	close_interface()
	terminal={"id":"payment:"+str(peer.id),"kind":"payment","name":"DIRECT PAYMENT","recipient_name":str(peer.get("name",peer.id))}
	panel.target_id=str(peer.id);panel.message="Confirm only after checking the recipient and amount."
	panel.configure(terminal,wallet,tickets)
	surface.visible=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	trigger_armed=false;sync_pointers();opened.emit()

func validate_payment_peer(peers: Array, player_position: Vector3) -> void:
	if terminal.get("kind","")!="payment": return
	for peer: Dictionary in peers:
		if str(peer.get("id",""))!=panel.target_id: continue
		if not bool(peer.get("fresh",false)) or not bool(peer.get("authenticated",false)) or not bool(peer.get("handshake_authorized",false)): break
		if peer.get("hand_position") is Vector3 and player_position.distance_to(peer.hand_position)<=CLOSE_DISTANCE: return
		break
	close_interface()

func offer_boarding(shuttle: Dictionary, available_tickets: Array) -> void:
	if not allowed or pending or not bool(shuttle.get("landed",false)) or not bool(shuttle.get("doors_open",false)): return
	var choices: Array=[]
	for ticket: Dictionary in available_tickets:
		if bool(ticket.get("usable",false)): choices.append(ticket)
	if choices.is_empty(): return
	var shuttle_id:=str(shuttle.get("id",""))
	if shuttle_id.is_empty() or boarding_latch==shuttle_id: return
	boarding_latch=shuttle_id
	if choices.size()==1:
		set_pending(true)
		action_requested.emit("travel_board",{"terminal_id":shuttle_id,"ticket_id":str(choices[0].get("id",""))})
		return
	close_interface()
	terminal={"id":shuttle_id,"kind":"boarding","name":"SELECT SHUTTLE TICKET"}
	tickets=choices
	terminal_origin=body.global_position
	var head: Transform3D=rig.get_node("XRCamera3D").global_transform
	surface.global_transform=face_pose(head.origin-head.basis.z*0.6-Vector3.UP*0.12,head.origin)
	panel.selected=-1;panel.offset=0;panel.message="Choose the ticket for this journey."
	panel.configure(terminal,wallet,tickets)
	surface.visible=true;viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	trigger_armed=false;sync_pointers();opened.emit()

func sync_boarding_choices(eligible: Array) -> void:
	if terminal.get("kind","")!="boarding": return
	var current: Array=[]
	for ticket: Dictionary in eligible:
		if bool(ticket.get("usable",false)): current.append(ticket.duplicate(true))
	if current.is_empty(): close_interface();return
	if current==panel.tickets: return
	var selected_id:=""
	if panel.selected>=0 and panel.selected<panel.rows.size(): selected_id=str(panel.rows[panel.selected].get("id",""))
	tickets=current
	panel.configure(terminal,wallet,tickets)
	panel.selected=-1
	for index in range(panel.rows.size()):
		if str(panel.rows[index].get("id",""))==selected_id: panel.selected=index;break
	panel.set_pending(pending)
	panel.queue_redraw()

func update_boarding(shuttle: Dictionary, available_tickets: Array, previous: Vector3, current: Vector3) -> void:
	var door: Vector3=shuttle.get("door_position",shuttle.get("position",Vector3.ZERO))
	var radius:=clampf(float(shuttle.get("boarding_radius",1.2)),0.4,2.0)
	if current.distance_to(door)>radius+0.5:
		if boarding_latch==str(shuttle.get("id","")): boarding_latch=""
		return
	if not bool(shuttle.get("landed",false)) or not bool(shuttle.get("doors_open",false)):
		if terminal.get("kind","")=="boarding" and str(terminal.get("id",""))==str(shuttle.get("id","")): close_interface()
		return
	# Require entering the door's boarding volume; landing on an idle player is not consent.
	if previous.distance_to(door)>radius and current.distance_to(door)<=radius and current.distance_squared_to(previous)>0.000001:
		offer_boarding(shuttle,available_tickets)

func update_proximity(player_position: Vector3) -> void:
	if not terminal.is_empty() and terminal.get("kind","")!="payment" and player_position.distance_to(terminal_origin)>CLOSE_DISTANCE:
		close_interface()

func pointer_frame(hit: Dictionary, trigger: float, grip: float) -> void:
	# Trigger click and grip drag have independent edges. Holding an unrelated
	# grip must never prevent the trigger from rearming or releasing a click.
	if trigger<0.3:trigger_armed=true
	if grip<0.35:pointer_grip_armed=true
	if pointer_pressed:
		if not hit.is_empty():pointer_last=hit.pixel;panel.pointer_move(pointer_last)
		var released:=trigger<0.3 if pointer_button=="trigger" else grip<0.35
		if released:
			if hit.is_empty():panel.cancel_pointer()
			else:panel.pointer_end(pointer_last)
			pointer_pressed=false;pointer_button=""
	elif not hit.is_empty() and not pending:
		if trigger_armed and trigger>=.55:
			trigger_armed=false;pointer_button="trigger"
		elif pointer_grip_armed and grip>=.65:
			pointer_grip_armed=false;pointer_button="grip"
		if not pointer_button.is_empty():
			pointer_pressed=true;pointer_last=hit.pixel;panel.pointer_begin(pointer_last)

	if grip>=.65:pointer_grip_armed=false

func sync_slider_handles()->void:
	if slider_surface.is_empty():slider_surface={"mesh":surface,"meters":PANEL_METERS,"viewport":viewport,"control":panel}
	slider_surface.control=panel
	preload("res://scripts/xr_slider_drag.gd").sync_handles([slider_surface])

func physical_slider_hit(position:Vector3)->Dictionary:
	if pending or not surface.visible:return {}
	var candidate:Dictionary=preload("res://scripts/xr_slider_drag.gd").near_handle({"mesh":surface,"meters":PANEL_METERS,"viewport":viewport,"control":panel},position)
	if candidate.is_empty():return {}
	var pixel:Vector2=candidate.pixel
	return {"valid":true,"pixel":pixel,"world":surface.global_transform*Vector3((pixel.x/viewport.size.x-.5)*PANEL_METERS.x,(.5-pixel.y/viewport.size.y)*PANEL_METERS.y,.002)}

func interaction_hit(hand: XRController3D, finger: Dictionary) -> Dictionary:
	if pointer_pressed:
		# Pulling a trigger curls the rendered index. Once pressed, retain the
		# contact and drag with hand translation instead of re-aiming a bent finger.
		var movement: Vector3=surface.global_basis.inverse()*(hand.global_position-drag_hand_anchor)
		var pixel:=drag_pixel_anchor+Vector2(movement.x/PANEL_METERS.x*viewport.size.x,-movement.y/PANEL_METERS.y*viewport.size.y)
		return {"valid":true,"pixel":pixel,"world":surface.global_transform*Vector3((pixel.x/viewport.size.x-.5)*PANEL_METERS.x,(.5-pixel.y/viewport.size.y)*PANEL_METERS.y,.002)}
	if pointer_grip_armed and hand.get_float("grip")>=.65:
		var physical:=physical_slider_hit(hand.global_position)
		if not physical.is_empty():return physical

	var hit: Dictionary=point_math.point(surface.global_transform,PANEL_METERS,Vector2(viewport.size),finger.get("ray_origin",finger.tip),finger.direction)
	hit=hit if bool(hit.get("valid",false)) else {}
	return hit

func set_stick_capture(value: bool) -> void:
	stick_captured=value
	if is_instance_valid(body) and body.has_method("set_interface_capture"):
		body.set_interface_capture(value and offhand=="right",value and offhand=="left")

func scroll_frame(hit: Dictionary, stick: Vector2, delta: float) -> void:
	if stick.length()<.15:set_stick_capture(false)
	elif not hit.is_empty() and panel.ROWS_RECT.has_point(hit.pixel) and not pending:set_stick_capture(true)
	if hit.is_empty() or pending or absf(stick.y)<.25 or panel.slider.dragging:
		stick_scroll=0;return
	stick_scroll+=-stick.y*12.0*delta
	if absf(stick_scroll)>=1:
		var steps:=int(stick_scroll)
		panel.navigate_at(hit.pixel,steps);stick_scroll-=steps

func finger_pose(controller: XRController3D) -> Dictionary:
	return preload("res://scripts/rendered_finger_pointer.gd").pose(avatar,"right" if offhand=="left" else "left",rig,controller)

func _process(delta: float) -> void:
	if not allowed or not is_instance_valid(rig): return
	if inventory_focus_provider.is_valid():set_inventory_focus(bool(inventory_focus_provider.call()))
	var hand: XRController3D=rig.get_node("RightHand" if offhand=="left" else "LeftHand")
	var mount: XRController3D=rig.get_node("LeftHand" if offhand=="left" else "RightHand")
	var head: Camera3D=rig.get_node("XRCamera3D")
	var head_tracker=XRServer.get_tracker("head")
	var head_pose: XRPose=head_tracker.get_pose("default") if head_tracker!=null else null
	var tracked:=head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(mount) and HandInput.controller_tracked(hand)
	if not inventory_focus:update_wallet_gesture(tracked,head.global_transform,mount.global_transform,mount.get_float("grip") if tracked else 0)
	if not tracked:
		close_interface();pointer_pressed=false;trigger_armed=false;return
	if inventory_focus:
		update_proximity(body.global_position);pointer_visual.hide();return
	var finger:=finger_pose(hand)
	if wallet_held:
		var peers: Array=remote_hands_provider.call() if remote_hands_provider.is_valid() else []
		validate_payment_peer(peers,body.global_position)
		update_handshake(hand.global_transform,hand.get_float("grip"),peers,delta)
	if not terminal.is_empty():
		if terminal.get("kind","")=="payment":
			var center:=wallet_mount.global_position+Vector3.UP*0.24
			surface.global_transform=face_pose(center,head.global_position)
		else:
			update_proximity(body.global_position)
			if terminal.is_empty(): return
		var hit:=interaction_hit(hand,finger)
		var was_pressed:=pointer_pressed
		pointer_visual.update_pointer(finger.tip,hit)
		pointer_frame(hit,hand.get_float("trigger"),hand.get_float("grip"))
		sync_slider_handles()
		if pointer_pressed and not was_pressed:
			drag_hand_anchor=hand.global_position;drag_pixel_anchor=pointer_last
		scroll_frame(hit,hand.get_vector2("primary"),delta)
		return
	if hand.get_float("trigger")<0.3: trigger_armed=true
	if pending or not terminal_provider.is_valid():pointer_visual.hide();return
	var candidate:=pointed_terminal(terminal_provider.call(),body.global_position,finger.get("ray_origin",finger.tip),finger.direction,head.global_position)
	if candidate.is_empty():pointer_visual.hide();return
	# Nearby terminal targeting is invisible until its interface is opened.
	# Keep original screen hit-testing and trigger activation; the active UI
	# retains its click dot without a projected beam.
	pointer_visual.hide()
	if trigger_armed and hand.get_float("trigger")>=0.55:
		trigger_armed=false;open_terminal(candidate)

func pointed_terminal(records: Array, player_position: Vector3, origin: Vector3, direction: Vector3, viewer: Vector3=Vector3.INF) -> Dictionary:
	# Match the real screen planes used to place the hologram. Short narrow
	# terminals and nearby paired terminals must not use an invented origin+1m.
	var best: Dictionary={}
	var best_score:=INF
	for record: Dictionary in records:
		if not record.get("position") is Vector3 or player_position.distance_to(record.position)>CLOSE_DISTANCE: continue
		var anchors: Array=record.get("ui_anchors",[])
		if anchors.is_empty(): anchors=[Transform3D(Basis.IDENTITY,record.position+Vector3.UP)]
		for anchor: Transform3D in anchors:
			var delta:=anchor.origin-origin
			var distance:=delta.length()
			var alignment:=direction.normalized().dot(delta.normalized())
			if distance>0.4 and (distance>3.0 or alignment<0.94): continue
			if record.has("ui_anchors") and not record.ui_anchors.is_empty():
				# ui_anchors are 55mm in front of physical glass. Testing the finger
				# against that plane rejected real touch (55mm > old50mm tolerance).
				# Facing belongs to the viewer; a tracked finger may touch or slightly
				# penetrate the glass without making the entire terminal a back face.
				var physical:=anchor.origin-anchor.basis.z*.055
				var eye:=viewer if viewer.is_finite() else origin
				if anchor.basis.z.dot(eye-physical)<-0.05:continue
				if anchor.basis.z.dot(origin-physical)<-.15:continue
			var score:=(1.0-alignment)*10.0+distance*0.1
			if score<best_score: best_score=score;best=record
	return best

func sync_pointers() -> void:
	preload("res://scripts/pointer_capture.gd").suspend(self,rig,blocks_combat())

func _exit_tree() -> void:
	preload("res://scripts/pointer_capture.gd").suspend(self,rig,false)

func terminal_pose(record: Dictionary, fallback_center: Vector3, head: Vector3) -> Transform3D:
	var best: Transform3D=face_pose(fallback_center,head)
	var score:=-INF
	for pose: Transform3D in record.get("ui_anchors",[]):
		var toward:=head-pose.origin
		var candidate:=pose.basis.z.normalized().dot(toward.normalized())*10.0-toward.length()
		if candidate>score:best=pose;score=candidate
	if record.get("kind","") in ["starship","ship_crew"]:
		best.origin.y=maxf(best.origin.y+.40,float(record.get("position",fallback_center).y)+1.65)
	return best
