extends "res://housing/harvester_panel.gd"
## Native factory inventories; blueprint and resource acceptance remain Core3 decisions.
var blueprint_slot:MeshInstance3D
var blueprint_label:Label3D
var inputs:Node3D
var latched_input:=-1
var latched_blueprint:=false
func setup(controller:Node3D)->void:
	super.setup(controller)
	ui.chosen.disconnect(select_resource);ui.chosen.connect(withdraw_input);ui.layout(true)
	ui.page_changed.connect(refresh_input)
	inputs=Node3D.new();surfaces[0].mesh.add_child(inputs)
	blueprint_slot=target_plate(Vector2(.23,.08));surfaces[0].mesh.add_child(blueprint_slot);blueprint_slot.position=Vector3(0,.25,.04)
	blueprint_label=Label3D.new();blueprint_slot.add_child(blueprint_label);blueprint_label.font_size=20;blueprint_label.pixel_size=.0006;blueprint_label.position=Vector3(0,.005,.005);blueprint_label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");blueprint_label.modulate=Holo.INK
	blueprint_label.text="SOURCE BLUEPRINT\nDrag from datapad"
func close()->void:
	latched_input=-1;latched_blueprint=false;super.close()
func observe(result:Dictionary)->void:
	var value:Dictionary=result.get("mutation",{}).get("factory",{})
	if value.is_empty() or str(value.get("id",""))!=structure_id:return
	current=value.duplicate(true);poll=3
	var blueprint:Dictionary=current.get("blueprint",{})
	blueprint_label.text="SOURCE BLUEPRINT\n"+("Drag from datapad" if blueprint.is_empty() else str(blueprint.get("name","Blueprint"))+"\nGrip/pull to remove")
	var requirements:PackedStringArray=[]
	for row:Dictionary in current.get("requirements",[]):
		requirements.append("%s ×%d"%[row.get("name",row.get("type","Ingredient")),row.get("quantity",row.get("amount",0))])
	ui.configure("FACTORY INPUT INVENTORY",current.get("input",[]),"Drop required resources here · grip/pull to retrieve\n"+("Insert a source blueprint above" if blueprint.is_empty() else "Needs: "+" · ".join(requirements)))
	output.configure("OUTPUT INVENTORY",current.get("output",[]),"Click or grip/pull to collect finished items")
	heading.text="POWER %d · %d/hour\nMAINTENANCE %d · %.0f/hour\n%s"%[current.get("power",0),current.get("power_rate",0),current.get("maintenance",0),current.get("maintenance_rate",0),"MANUFACTURING" if current.get("active",false) else "STOPPED"]
	slider.max_value=maxi(0,mini(int(current.get("cash",0)),100000000-int(current.get("maintenance",0))));slider.value=minf(slider.value,slider.max_value);deposit.text="Deposit %d credits"%int(slider.value);toggle.text="Stop" if current.get("active",false) else "Start"
	refresh_input();refresh_output();slider_dragger.sync_handles(surfaces)
func refresh_input()->void:
	for child in inputs.get_children():child.queue_free()
	for i in range(ui.offset,mini(ui.rows.size(),ui.offset+ui.page_size)):
		var row:Dictionary=ui.rows[i];var model:Node3D=owner_controller.bag.assets.instance(str(row.get("template","")),.046)
		if model==null:continue
		inputs.add_child(model);var cell:Rect2=ui.cell_rect(i);var p:Vector2=cell.position+Vector2(cell.size.x*.5,66)
		model.position=Vector3((p.x/660-.5)*.38,(.5-p.y/660)*.38,.028);model.rotation=Vector3(-.1,.6,0)
func operate(action:String,extra:Dictionary={})->void:
	if structure_id.is_empty() or owner_controller.busy:return
	var version:int=owner_controller.generation
	extra=extra.duplicate(true);extra.structure_id=structure_id
	var result:Dictionary=await owner_controller.request("factory_"+action,extra)
	if version!=owner_controller.generation:return
	if result.get("ok",false):observe(result)
	else:show_error(result)
func show_error(result:Dictionary)->void:
	if is_open:ui.footer=str(result.get("error","Core3 did not confirm this operation."));ui.queue_redraw()
func withdraw_input(index:int)->void:
	if index>=0 and index<ui.rows.size():operate("withdraw",{"item_id":str(ui.rows[index].id)})
func collect_output(index:int)->void:
	if index>=0 and index<output.rows.size():operate("collect",{"item_id":str(output.rows[index].id)})
func try_drop(item:Dictionary,pose:Transform3D)->bool:
	if not is_open:return false
	if blueprint_slot.global_position.distance_to(pose.origin)<.12:
		if item.get("type","")!="manufacturing_blueprint":
			owner_controller.bag.finish_item_action(false);show_error({"error":"Only a source manufacturing blueprint belongs in this slot."});return true
		transfer("blueprint",item);return true
	if power_slot.global_position.distance_to(pose.origin)<.12:transfer("power",item);return true
	var point:Vector3=surfaces[0].mesh.to_local(pose.origin)
	if absf(point.x)<.2 and absf(point.y)<.2 and absf(point.z)<.12:
		transfer("input",item);return true
	return false
func transfer(action:String,item:Dictionary)->void:
	if owner_controller.busy:owner_controller.bag.finish_item_action(false);return
	var version:int=owner_controller.generation
	var result:Dictionary=await owner_controller.request("factory_"+action,{"structure_id":structure_id,"item_id":str(item.id)})
	if version!=owner_controller.generation:return
	owner_controller.bag.finish_item_action(result.get("ok",false) and result.get("mutation",{}).get("success",false))
	if result.get("ok",false):observe(result)
	else:show_error(result)
func _process(dt:float)->void:
	if not is_open:return
	if not owner_controller.allowed:close();return
	if is_instance_valid(app.get("datapad")) and app.datapad.is_open:
		cancel_press();gripping=false;sliding=false;latched_input=-1;latched_output=-1;latched_blueprint=false;return
	if owner_controller.bag.is_open:cancel_press();gripping=false;sliding=false;latched_input=-1;latched_output=-1;latched_blueprint=false;return
	if global_position.distance_to(body.global_position)>5:close();return
	poll-=dt
	var hand:XRController3D=rig.get_node("RightHand" if offhand=="left" else "LeftHand")
	if not Hands.controller_tracked(hand):cancel_press();gripping=false;sliding=false;latched_input=-1;latched_output=-1;latched_blueprint=false;return
	var hit:=find_hit(pointing_pose(hand))
	if slider_frame(hit,hand.global_transform,hand.get_float("grip"),hand.get_float("trigger"),not owner_controller.busy and owner_controller.bag.held_item.is_empty()):gripping=hand.get_float("grip")>.65;return
	update_pointer(hit,hand.get_float("trigger"))
	var down:=hand.get_float("grip")>.65
	if down and not gripping and owner_controller.bag.held_item.is_empty():
		latched_blueprint=not current.get("blueprint",{}).is_empty() and hand.global_position.distance_to(blueprint_slot.global_position)<.12
		grip_anchor=hand.global_position
		if not latched_blueprint and not hit.is_empty():
			if int(hit.surface)==0:latched_input=ui.row_at(hit.pixel)
			elif int(hit.surface)==2:latched_output=output.row_at(hit.pixel)
	if down and hand.global_position.distance_to(grip_anchor)>.06:
		if latched_blueprint:latched_blueprint=false;operate("remove_blueprint")
		elif latched_input>=0:
			var selected:=latched_input;latched_input=-1;withdraw_input(selected)
		elif latched_output>=0:
			var selected:=latched_output;latched_output=-1;collect_output(selected)
	if not down:sliding=false;latched_input=-1;latched_output=-1;latched_blueprint=false
	gripping=down
	var stick:Vector2=hand.get_vector2("primary")
	if stick.length()>.4 and not hit.is_empty():
		var pane:Control=ui if int(hit.surface)==0 else output if int(hit.surface)==2 else null
		if pane!=null and scroll_delay<=0:pane.scroll(-stick.y);scroll_delay=.2
	scroll_delay=maxf(0,scroll_delay-dt)
	if poll<=0 and not owner_controller.busy:operate("status");poll=3
