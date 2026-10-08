extends Node3D
## Spatial slicing UI. Core3 owns challenges, item locks, failure and rewards.
const Hands=preload("res://scripts/tracked_hand_input.gd")
const Board=preload("res://slicing/board.gd")
const View=preload("res://slicing/grid_view.gd")
var app:Node
var bag:Node3D
var body:CharacterBody3D
var grid:Node3D
var board=Board.new()
var state:Dictionary={}
var busy:=false
var allowed:=false
var generation:=0
var epoch:=-1
var poll:=0.0
var received_at:=0
var trigger_armed:=false
var submitted:=false
var completion_request_id:=""
var rejected_revision:=-1
var statistics_attempt:=""
var uncertain:=false
var pending_cancel:=false
var tool_revision:=-1
var tool_tip_local:=Vector3.ZERO
var error:=""
var locked_target:=""
var target_visual:Node3D
var notice:Label3D
var equipped_tool:Dictionary={}
var equipped_model:Node3D
var hip_drawn:=false
var draw_armed:=false
var equipped_key:=""
func setup(host:Node,inventory:Node3D)->void:
	app=host;bag=inventory;body=bag.body;process_priority=150
	grid=View.new();add_child(grid);grid.hide()
	notice=Label3D.new();notice.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");notice.font_size=20;notice.pixel_size=.0005;notice.modulate=Color("baffff");notice.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(notice);notice.hide()
	bag.item_held_changed.connect(held_changed)
	epoch=app.datapad_epoch
func active()->bool:return bool(state.get("active",false))
func set_allowed(value:bool)->void:
	allowed=value
	if not value:trigger_armed=false;board.sample(Vector3.ZERO,false);grid.hide();notice.hide()
	if not value and is_instance_valid(equipped_model):equipped_model.hide()
func reset()->void:
	generation+=1;busy=false;state={};poll=0;trigger_armed=false;submitted=false;completion_request_id="";rejected_revision=-1;uncertain=false;pending_cancel=false;tool_revision=-1;error="";statistics_attempt="";epoch=app.datapad_epoch
	release_target();grid.hide();notice.hide()
	if is_instance_valid(equipped_model):equipped_model.queue_free()
	equipped_model=null;equipped_tool={};equipped_key="";hip_drawn=false;draw_armed=false
func held_changed(item:Dictionary)->void:
	trigger_armed=false;tool_revision=-1
	if item.get("tool_kind","")!="slicing" and not active() and not uncertain:error="";notice.hide()
func source(point:Vector3)->Array:
	var p:Vector3=app.source_position_at(point);return [p.x,p.y,p.z]
func world(point:Array)->Vector3:return app.services.world(point)
func owns_tool()->bool:
	var tool:=current_tool()
	return not tool.is_empty() and (not active() or str(tool.get("id",""))==str(state.get("tool_id","")))
func current_tool()->Dictionary:
	return bag.held_item if bag.held_item.get("tool_kind","")=="slicing" else equipped_tool
func tool_hand()->XRController3D:
	return bag.held_controller() if bag.held_item.get("tool_kind","")=="slicing" else bag.controller_for(bag.main_side())
func tool_visual()->Node3D:
	return bag.held_model if bag.held_item.get("tool_kind","")=="slicing" else equipped_model
func update_equipped_tool()->void:
	var candidate:Dictionary={}
	var inventory:Variant=app.get("inventory_snapshot")
	if not inventory is Dictionary:return
	for entry:Dictionary in inventory.get("equipment",[]):
		if entry.get("tool_kind","")=="slicing" and "hold_r" in entry.get("equipped_slots",[]):candidate=entry;break
	var hand:XRController3D=bag.controller_for(bag.main_side())
	if hand.get_float("grip")<.35:draw_armed=true
	elif hand.get_float("grip")>=.65 and draw_armed:
		draw_armed=false
		if not bag.is_open and bag.hip_tool.get("tool_kind","")=="slicing" and hand.global_position.distance_to(bag.hip_transform().origin)<.20:hip_drawn=not hip_drawn
	if candidate.is_empty() and hip_drawn and bag.hip_tool.get("tool_kind","")=="slicing":candidate=bag.hip_tool
	if bag.held_item.get("tool_kind","")=="slicing" or (not bag.held_item.is_empty() and bag.held_hand_side()==bag.main_side()):candidate={}
	var key:=str(candidate.get("id",""))
	if key!=equipped_key:
		if is_instance_valid(equipped_model):equipped_model.queue_free()
		equipped_model=null;equipped_key=key;equipped_tool=candidate.duplicate(true);tool_revision=-1
		if not candidate.is_empty():
			var visual:Node3D=bag.assets.instance(str(candidate.template),.28,candidate.get("customization",{}))
			if visual!=null:equipped_model=Node3D.new();add_child(equipped_model);equipped_model.add_child(visual)
	if is_instance_valid(equipped_model):
		equipped_model.global_transform=bag.item_hand_pose(hand,hand.global_transform)
		equipped_model.visible=allowed and not bag.is_open and Hands.controller_tracked(hand)
	if is_instance_valid(bag.hip_model) and not equipped_tool.is_empty() and str(bag.hip_tool.get("id",""))==str(equipped_tool.id):bag.hip_model.hide()
func tip()->Vector3:
	var visual:=tool_visual()
	if not is_instance_valid(visual) or visual.get_child_count()==0:return Vector3.INF
	var model:MeshInstance3D=visual.get_child(0) as MeshInstance3D
	if model==null or model.mesh==null:return Vector3.INF
	if tool_revision!=bag.held_revision:
		tool_revision=bag.held_revision
		# Source laser knife uses a rifle-barrel component along +Z. Rotate its
		# authored end toward runtime-neutral hand aim; retain original geometry.
		var bounds:=model.mesh.get_aabb();model.rotation=Vector3(0,PI,0)
		model.position=-(Basis.from_euler(model.rotation)*bounds.get_center())*model.scale
		tool_tip_local=Vector3(bounds.get_center().x,bounds.get_center().y,bounds.end.z)
	return model.to_global(tool_tip_local)
func clear_solid_line(from:Vector3,to:Vector3)->bool:
	if from.distance_squared_to(to)<.0001:return true
	var query:=PhysicsRayQueryParameters3D.create(from,to,7,[body.get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or Vector3(hit.position).distance_to(to)<.12
func target_at(point:Vector3)->Dictionary:
	if not point.is_finite():return {}
	var selected:Dictionary={};var distance:=INF
	if bag.held_item.get("tool_kind","")!="slicing" and not bag.held_item.is_empty() and is_instance_valid(bag.held_model) and bag.held_model.get_child_count()>0:
		var model:=bag.held_model.get_child(0) as MeshInstance3D
		var item:Dictionary=app.owned_inventory_item(str(bag.held_item.get("id","")))
		if model!=null and model.mesh!=null and model.mesh.get_aabb().grow(.055).has_point(model.to_local(point)):
			selected={"id":str(item.get("id","")),"kind":"item","position":bag.held_model.global_position,"name":str(item.get("name","Item")),"eligible":bool(item.get("sliceable",false)),"reason":str(item.get("slice_block_reason","Item cannot be sliced"))};distance=point.distance_to(bag.held_model.global_position)
	if is_instance_valid(app.inventory_drops):
		for id:String in app.inventory_drops.records:
			var record:Dictionary=app.inventory_drops.records[id]
			var item:Dictionary=app.owned_inventory_item(id)
			if item.is_empty() or record.get("slicing_reserved",false) or not is_instance_valid(record.body):continue
			var local:Vector3=record.body.to_local(point)
			if not record.source_bounds.grow(.055).has_point(local):continue
			var d:float=point.distance_to(record.body.global_position)
			if d<distance:selected={"id":id,"kind":"item","position":record.body.global_position,"name":str(item.get("name","Item")),"eligible":bool(item.get("sliceable",false)),"reason":str(item.get("slice_block_reason","Core3 has not confirmed that this item can be sliced"))};distance=d
	if is_instance_valid(app.services):
		for record:Dictionary in app.services.terminal_records():
			if record.get("kind","")!="mission":continue
			var anchors:Array=record.get("ui_anchors",[])
			if anchors.is_empty():anchors=[Transform3D(Basis.IDENTITY,record.position+Vector3.UP)]
			for anchor:Transform3D in anchors:
				var d:float=point.distance_to(anchor.origin)
				if d<.14 and d<distance:selected={"id":str(record.id),"kind":"terminal","position":record.position,"name":str(record.get("name","Mission terminal")),"eligible":bool(record.get("sliceable",true)),"reason":str(record.get("slice_block_reason","This terminal cannot be sliced"))};distance=d
	if not selected.is_empty() and (body.global_position.distance_to(selected.position)>3.0 or not clear_solid_line(tool_hand().global_position,point)):return {}
	if not selected.is_empty() and selected.get("eligible",true)==false:
		error=str(selected.reason);return {}
	return selected
func begin(target:Dictionary,point:Vector3,head:Transform3D)->void:
	if busy or active() or uncertain or target.is_empty() or not owns_tool():return
	var forward:=(-head.basis.z).slide(Vector3.UP).normalized()
	if forward.length_squared()<.5:forward=Vector3.FORWARD
	var anchor:=head.origin+forward*.65-Vector3.UP*.35
	if target.kind=="terminal":
		var toward:Vector3=(head.origin-Vector3(target.position)).slide(Vector3.UP).normalized()
		if toward.length_squared()>.5:anchor=Vector3(target.position)+toward*.60;anchor.y=head.origin.y-.35
	var basis:=Basis.looking_at(forward,Vector3.UP)
	var source_basis:Basis=app.stage.global_basis.inverse()*basis if is_instance_valid(app.stage) else basis
	var payload:Dictionary={"tool_id":str(current_tool().id),"target_id":str(target.id),"target_kind":str(target.kind),"tool_position":source(point),"anchor_position":source(anchor),"heading_radians":-source_basis.get_euler().y}
	if target.kind=="item":payload.target_position=source(target.position)
	request("begin",payload)
func request(action:String,extra:Dictionary={})->Dictionary:
	if busy or not is_instance_valid(app.services) or app.datapad_character_id.is_empty():return {}
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if native_id.is_empty():error="Slicing needs a connected Core3 session";return {}
	busy=true
	var version:=generation;var character_epoch:int=app.datapad_epoch
	var payload:Dictionary=app.services.identity_payload();payload.merge(extra,true)
	payload.request_id="slice-%d-%d"%[int(Time.get_unix_time_from_system()*1000000),Time.get_ticks_usec()]
	if action=="complete":
		if completion_request_id.is_empty():completion_request_id=payload.request_id
		payload.request_id=completion_request_id
	if action!="begin" and active():payload.attempt_id=str(state.get("attempt_id",""))
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/services/slicing_"+action,payload)
	if version!=generation or character_epoch!=app.datapad_epoch:return {}
	busy=false
	if response.get("ok",false) and response.get("source_kind","")=="core3_services" and str(response.get("character_id",""))==app.datapad_character_id:
		if app.services.accept_response(response,false):
			# Normal service observer handles revision/ownership fencing.
			if not response.get("state",{}).has("slicing"):error="Core3 omitted slicing state";uncertain=true
			elif action=="status" and active() and submitted and board.complete():
				# Active status after an uncertain completion means no outcome yet.
				# Retry the same receipt so transport loss cannot cost a solved board.
				submitted=false
		else:error=app.services.last_error;uncertain=true
	else:
		error=str(response.get("error","Slicing response uncertain; checking Core3"));uncertain=true
	var mutation:Dictionary=response.get("mutation",{})
	if action=="complete" and response.get("source_kind","")=="core3_services" and str(response.get("character_id",""))==app.datapad_character_id and str(response.get("state",{}).get("slicing",{}).get("attempt_id",""))==str(state.get("attempt_id","")) and mutation.get("success",true)==false and mutation.get("status","")=="active":
		# A definitive rejected candidate is editable. A changed candidate needs
		# a fresh receipt; an uncertain delivery retains the original receipt.
		submitted=false;completion_request_id="";rejected_revision=board.revision;uncertain=false
		error=str(mutation.get("error","Adjust the pipe paths and try again"))
	poll=.75 if uncertain or active() else 5.0
	return response
func observe(response:Dictionary)->void:
	var incoming:Variant=response.get("state",{}).get("slicing")
	if not incoming is Dictionary:return
	if str(response.get("character_id",""))!=app.datapad_character_id:return
	var changed:bool=str(incoming.get("attempt_id",""))!=str(state.get("attempt_id",""))
	var was_active:=active()
	if incoming.get("active",false):
		if str(incoming.get("attempt_id","")).is_empty() or not incoming.get("challenge") is Dictionary or not incoming.get("anchor_position") is Array or incoming.anchor_position.size()!=3:return
		if changed or not was_active:
			if not board.configure(incoming.challenge,float(incoming.get("cell_size",.1))):error=board.error;uncertain=true;return
			grid.configure(board);submitted=false;completion_request_id="";rejected_revision=-1;pending_cancel=false
		var basis:=Basis(Vector3.UP,-float(incoming.get("heading_radians",0)))
		if is_instance_valid(app.stage):basis=app.stage.global_basis*basis
		grid.global_transform=Transform3D(basis,world(incoming.anchor_position))
	state=incoming.duplicate(true);received_at=Time.get_ticks_msec();uncertain=false;error=""
	if active():lock_target()
	elif was_active or not locked_target.is_empty():
		release_target();submitted=false;completion_request_id="";rejected_revision=-1;pending_cancel=false
		error={"success":"Slice complete","succeeded":"Slice complete","walked_away":"Too far away — slice failed","interrupted":"Slice interrupted — item cannot be sliced again","disconnected":"Slice interrupted by disconnection","ownership_changed":"Slice interrupted — target ownership changed","failed":"Slice failed — item cannot be sliced again","cancelled":"Slice cancelled — item cannot be sliced again","abandoned":"Too far away — slice failed","expired":"Time expired — slice failed"}.get(str(state.get("status","")),str(state.get("status","")))
	grid.visible=active() and allowed
func equipment_updated(response:Dictionary)->void:
	# Services invokes this only after adopting the confirmed inventory. Equip
	# still forces its normal refresh later for the sliced unequipped item.
	var incoming:Dictionary=response.get("state",{}).get("slicing",{})
	var attempt:=str(incoming.get("attempt_id",""))
	if incoming.get("active",false) or incoming.get("status","")!="succeeded" or incoming.get("target_kind","")!="item" or attempt.is_empty() or attempt==statistics_attempt:return
	if not app.has_method("sync_inventory_equipment"):return
	statistics_attempt=attempt
	app.sync_inventory_equipment(true)
func lock_target()->void:
	if state.get("target_kind","")!="item":return
	var id:=str(state.get("target_id",""))
	if str(bag.held_item.get("id",""))==id:bag.finish_item_action(true)
	if locked_target!=id:release_target();locked_target=id
	var position:Vector3=grid.global_position-Vector3.UP*(board.size*board.cell_size*.5+.18)
	if is_instance_valid(app.inventory_drops) and app.inventory_drops.records.has(id):
		app.inventory_drops.lock_for_slicing(id,Transform3D(grid.global_basis,position))
	elif not is_instance_valid(target_visual):
		var item:Dictionary=app.owned_inventory_item(id)
		if not item.is_empty():
			target_visual=bag.assets.instance(str(item.get("template","")),.22,item.get("customization",{}))
			if target_visual!=null:add_child(target_visual);target_visual.global_position=position
func release_target()->void:
	if not locked_target.is_empty() and is_instance_valid(app) and is_instance_valid(app.get("inventory_drops")):app.inventory_drops.remove(locked_target)
	locked_target=""
	if is_instance_valid(target_visual):target_visual.queue_free()
	target_visual=null
func sample_input(point:Vector3,trigger:float,tracked:bool,head:Transform3D)->void:
	if not tracked or not is_finite(trigger):trigger_armed=false;board.sample(Vector3.ZERO,false);grid.show_cursor(Vector3.ZERO,false);return
	if trigger<.35:trigger_armed=true
	if active():
		if busy or uncertain or submitted or pending_cancel:return
		if board.complete() and board.revision!=rejected_revision:submitted=true;request("complete",{"paths":board.paths()});return
		var local:=grid.to_local(point)
		var event:Dictionary=board.sample(local,true)
		grid.show_cursor(local,true,event.action=="blocked");grid.refresh()
		if event.get("changed",false) and event.get("complete",false):submitted=true;request("complete",{"paths":board.paths()})
		return
	if trigger>=.65 and trigger_armed and not busy and not uncertain:
		trigger_armed=false
		if bag.get("hologram")!=null and bag.hologram.active:bag.close_equipment_hologram();return
		var target:=target_at(point)
		if target.is_empty() and bag.held_item.get("tool_kind","")=="slicing" and bag.has_method("show_equipment_hologram"):bag.show_equipment_hologram(head)
		else:begin(target,point,head)
func _process(delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(bag):return
	if epoch!=app.datapad_epoch:reset()
	poll-=delta
	if not allowed or not app.world_ready or app.session_leaving:return
	update_equipped_tool()
	var hand:XRController3D=tool_hand();var head:Camera3D=bag.rig.get_node("XRCamera3D")
	var tracker=XRServer.get_tracker("head");var head_pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:bool=owns_tool() and not bag.is_open and not bag.action_pending and Hands.controller_tracked(hand) and head_pose!=null and head_pose.has_tracking_data and not body.feedback.combat_blocked()
	grid.visible=active();notice.visible=owns_tool() or active() or not error.is_empty()
	if notice.visible:notice.global_position=(grid.global_position+Vector3.DOWN*(board.size*board.cell_size*.5+.35)) if active() else head.global_position-head.global_basis.z*.6+Vector3.DOWN*.23
	if active():
		var remaining:=float(state.get("remaining_seconds",0))
		var seconds:=maxf(0,remaining-(Time.get_ticks_msec()-received_at)/1000.0)
		grid.set_status("SLICING · %d / %d PIPES%s"%[board.wires.size(),board.pairs.size()," · %ds"%ceili(seconds) if remaining>0 else ""])
		notice.text=error if not error.is_empty() else "Checking Core3…" if busy or uncertain or submitted else board.error if not board.error.is_empty() else "Touch matching ends · Touch a connected end to detach"
		# Native watchdog measures abandonment from the original player position;
		# the visual cube anchor is not that origin. Status carries its outcome.
	else:notice.text=error if not error.is_empty() else "Touch an item or mission terminal with the knife; click trigger"
	if not busy and pending_cancel:request("cancel")
	elif not busy and poll<=0 and (active() or uncertain or owns_tool()):
		if not app.has_method("try_background_poll") or app.try_background_poll("slicing"):request("status")
	if owns_tool():sample_input(tip(),hand.get_float("trigger"),tracked,head.global_transform)
	else:board.sample(Vector3.ZERO,false);grid.show_cursor(Vector3.ZERO,false)
