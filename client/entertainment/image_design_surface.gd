extends "res://scripts/xr_services.gd"
## Reuses the existing rendered-finger click/drag surface without wallet gestures.
func configure(origin:XROrigin3D,player:CharacterBody3D,side:String="left")->void:
	super(origin,player,side)
	panel.free();panel=preload("res://entertainment/image_design_panel.gd").new();viewport.add_child(panel)
	panel.action_requested.connect(request_action);panel.close_requested.connect(cancel_design)
func update_wallet_gesture(_tracked:bool,_head:Transform3D,_hand:Transform3D,_grip:float)->void:pass
func cancel_design()->void:
	if not panel.design.is_empty():action_requested.emit("image_cancel",panel.mutation_payload())
	else:close_interface()
func place_panel()->void:
	if not is_instance_valid(rig):return
	var head:Node3D=rig.get_node("XRCamera3D")
	var ahead:Vector3=-head.global_basis.z.slide(Vector3.UP).normalized()
	if ahead.length_squared()<.5:ahead=Vector3.FORWARD
	terminal_origin=body.global_position
	surface.global_transform=face_pose(head.global_position+ahead*.85+Vector3.DOWN*.12,head.global_position)
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;surface.show();trigger_armed=false;sync_pointers();opened.emit()
func show_candidates(rows:Array,action:String="image_open")->void:
	if not allowed:return
	terminal={"id":"image-design-targets","kind":"image_design"};panel.show_candidates(rows,action);pending=false
	place_panel()
func show_design(value:Dictionary)->void:
	if not allowed:return
	var changed:bool=str(terminal.get("id",""))!=str(value.get("session_id",""))
	terminal={"id":str(value.get("session_id","")),"kind":"image_design"}
	panel.apply_design(value);pending=false
	if changed or not surface.visible:place_panel()
