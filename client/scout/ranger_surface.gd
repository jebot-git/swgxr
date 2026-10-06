extends "res://scripts/xr_services.gd"
func configure(origin:XROrigin3D,player:CharacterBody3D,side:String="left")->void:
	super(origin,player,side);panel.free();panel=preload("res://scout/ranger_panel.gd").new();viewport.add_child(panel);panel.action_requested.connect(request_action);panel.close_requested.connect(close_interface)
func update_wallet_gesture(_tracked:bool,_head:Transform3D,_hand:Transform3D,_grip:float)->void:pass
func request_action(action:String,payload:Dictionary)->void:
	# The Ranger owns validation and the native request latch. A rejected click
	# (e.g. a background scout poll in flight) must not lock this surface.
	if allowed and not pending:action_requested.emit(action,payload)
func show_state(value:Dictionary)->void:
	if not allowed:return
	var opening:=terminal.is_empty();terminal={"id":"ranger-tracking","kind":"ranger"};panel.apply(value)
	# Status replies complete the six-second native search asynchronously.
	# Clear both the drawn panel and the XR pointer's pending gate together.
	set_pending(value.get("tracking",{}).get("state","")=="pending")
	if not opening:return
	var head:Node3D=rig.get_node("XRCamera3D");var ahead:Vector3=-head.global_basis.z.slide(Vector3.UP).normalized()
	terminal_origin=body.global_position;surface.global_transform=face_pose(head.global_position+ahead*.85+Vector3.DOWN*.12,head.global_position);viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;surface.show();trigger_armed=false;sync_pointers();opened.emit()
