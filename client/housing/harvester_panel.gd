extends "res://scripts/xr_datapad.gd"
const CraftPanel=preload("res://scripts/crafting_panel.gd")
const Holo=preload("res://scripts/datapad_theme.gd")
const Hands=preload("res://scripts/tracked_hand_input.gd")
var owner_controller:Node3D
var app:Node
var output:Control
var left_panel:Control
var heading:Label
var deposit:Button
var slider:HSlider
var power_slot:MeshInstance3D
var slider_handle:MeshInstance3D
var outputs:Node3D
var current:Dictionary={}
var structure_id:=""
var poll:=0.0
var gripping:=false
var sliding:=false
var latched_output:=-1
var grip_anchor:=Vector3.ZERO
var toggle:Button
func setup(controller:Node3D)->void:
	owner_controller=controller;app=controller.app;rig=app.xr_origin;body=app.player;offhand=controller.bag.offhand
	ui=CraftPanel.new();output=CraftPanel.new();output.layout(true)
	left_panel=Control.new();left_panel.custom_minimum_size=Vector2(660,660);left_panel.theme=Holo.build()
	var backing:=Panel.new();left_panel.add_child(backing);backing.size=Vector2(660,660);backing.mouse_filter=Control.MOUSE_FILTER_IGNORE
	backing.add_theme_stylebox_override("panel",Holo.frame(24))
	add_surface(ui,Vector2i(660,660),Vector2(.38,.38));add_surface(left_panel,Vector2i(660,660),Vector2(.34,.38));add_surface(output,Vector2i(660,660),Vector2(.38,.38))
	surfaces[1].mesh.position.x=-.41;surfaces[1].mesh.rotation.y=.2;surfaces[2].mesh.position.x=.43;surfaces[2].mesh.rotation.y=-.2
	heading=Label.new();left_panel.add_child(heading);heading.position=Vector2(30,26);heading.size=Vector2(600,160);heading.add_theme_font_size_override("font_size",27)
	slider=HSlider.new();left_panel.add_child(slider);slider.position=Vector2(25,430);slider.size=Vector2(610,40);slider.step=1
	deposit=Button.new();left_panel.add_child(deposit);deposit.position=Vector2(25,490);deposit.size=Vector2(610,55);deposit.pressed.connect(pay_maintenance)
	toggle=Button.new();left_panel.add_child(toggle);toggle.position=Vector2(25,565);toggle.size=Vector2(295,60);toggle.pressed.connect(func():operate("active",{"active":not current.get("active",false)}))
	var close_button:=Button.new();left_panel.add_child(close_button);close_button.text="Close";close_button.position=Vector2(340,565);close_button.size=Vector2(295,60);close_button.pressed.connect(close)
	slider.value_changed.connect(func(value):deposit.text="Deposit %d credits"%int(value))
	ui.chosen.connect(select_resource);output.chosen.connect(collect_output);output.page_changed.connect(refresh_output)
	power_slot=target_plate(Vector2(.145,.07));surfaces[1].mesh.add_child(power_slot);power_slot.position=Vector3(0,.01,.07)
	var label:=Label3D.new();power_slot.add_child(label);label.text="ENERGY\nDrop resource stack";label.font_size=20;label.pixel_size=.00055;label.position=Vector3(0,.005,.005);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.modulate=Holo.INK
	slider_handle=target_plate(Vector2(.014,.025));surfaces[1].mesh.add_child(slider_handle);slider_handle.position=Vector3(-.15,-.065,.03);slider_handle.hide() # The themed slider draws its actual grabbable thumb.
	outputs=Node3D.new();surfaces[2].mesh.add_child(outputs)
	dot=cube(Vector3(.003,.003,.003));add_child(dot);dot.hide();set_open(false);hide()
func target_plate(size:Vector2)->MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=size;node.mesh=mesh
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture=Holo.BUTTON_NORMAL;material.albedo_color=Color(.72,.78,1.12,1);material.cull_mode=BaseMaterial3D.CULL_DISABLED;node.material_override=material;return node
func cube(size:Vector3)->MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.albedo_color=Color(.1,.85,1,.35);node.material_override=m;return node
func close()->void:
	structure_id="";current={};sliding=false;latched_output=-1;set_open(false)
func open_structure(row:Dictionary)->void:
	if owner_controller.busy:return
	structure_id=str(row.id);current={};poll=3
	var eye:Vector3=rig.get_node("XRCamera3D").global_position
	var anchor:Vector3=app.services.world(row.position);var toward:Vector3=(eye-anchor);toward.y=0
	if toward.length_squared()<.001:toward=rig.get_node("XRCamera3D").global_basis.z; toward.y=0
	if toward.length_squared()<.001:toward=Vector3.BACK
	global_position=eye-toward.normalized()*.8-Vector3.UP*.2
	look_at(Vector3(eye.x,global_position.y,eye.z),Vector3.UP,true)
	allowed=true;set_open(true);released_trigger=false;operate("status")
func observe(result:Dictionary)->void:
	var value:Dictionary=result.get("mutation",{}).get("harvester",{})
	if value.is_empty() or str(value.id)!=structure_id:return
	current=value.duplicate(true);poll=3
	var rows:Array=[]
	for r:Dictionary in current.get("resources",[]):rows.append({"id":r.id,"name":"%s · %.0f%%"%[r.name,float(r.density)*100],"description":"Selected" if str(r.id)==str(current.get("selected_resource","")) else str(r.type)})
	ui.configure("HARVEST RESOURCES",rows,"Select resource to start · %.1f units/min"%float(current.get("rate",0)))
	output.configure("OUTPUT INVENTORY",current.get("output",[]),"Click or grip and pull to collect · %d / %d"%[current.get("hopper_size",0),current.get("hopper_capacity",0)])
	heading.text="POWER %d · %d/hour\nMAINTENANCE %d · %.0f/hour\n%s"%[current.get("power",0),current.get("power_rate",0),current.get("maintenance",0),current.get("maintenance_rate",0),"HARVESTING" if current.get("active",false) else "STOPPED"]
	slider.max_value=mini(int(current.get("cash",0)),100000000-int(current.get("maintenance",0)));slider.value=minf(slider.value,slider.max_value);deposit.text="Deposit %d credits"%int(slider.value);toggle.text="Stop" if current.get("active",false) else "Start"
	refresh_output();slider_dragger.sync_handles(surfaces)
func refresh_output()->void:
	for child in outputs.get_children():child.queue_free()
	for i in range(output.offset,mini(output.rows.size(),output.offset+output.page_size)):
		var row:Dictionary=output.rows[i];var model:Node3D=owner_controller.bag.assets.instance(str(row.get("template","")),.046)
		if model==null:continue
		outputs.add_child(model);var cell:Rect2=output.cell_rect(i);var p:Vector2=cell.position+Vector2(cell.size.x*.5,66)
		model.position=Vector3((p.x/660-.5)*.38,(.5-p.y/660)*.38,.028);model.rotation=Vector3(-.1,.6,0)
func operate(action:String,extra:Dictionary={})->void:
	if structure_id.is_empty() or owner_controller.busy:return
	extra=extra.duplicate(true);extra.structure_id=structure_id
	var result:Dictionary=await owner_controller.request("harvester_"+action,extra)
	if result.get("ok",false):observe(result)
	elif is_open:ui.footer=str(result.get("error","Core3 did not confirm this operation."));ui.queue_redraw()
func select_resource(index:int)->void:
	if index>=0 and index<ui.rows.size():operate("select",{"resource_id":str(ui.rows[index].id)})
func collect_output(index:int)->void:
	if index>=0 and index<output.rows.size():
		var row:Dictionary=output.rows[index];operate("collect",{"resource_id":str(row.resource_id),"quantity":mini(100000,int(row.quantity))})
func pay_maintenance()->void:
	if slider.value>0:operate("deposit",{"amount":int(slider.value)})
func try_drop(item:Dictionary,pose:Transform3D)->bool:
	if not is_open or power_slot.global_position.distance_to(pose.origin)>.12:return false
	deposit_power(item);return true
func deposit_power(item:Dictionary)->void:
	if owner_controller.busy:owner_controller.bag.finish_item_action(false);return
	var version:int=owner_controller.generation
	var result:Dictionary=await owner_controller.request("harvester_power",{"structure_id":structure_id,"item_id":str(item.id)})
	if version!=owner_controller.generation:return
	owner_controller.bag.finish_item_action(result.get("ok",false) and result.get("mutation",{}).get("success",false))
	if result.get("ok",false):observe(result)
	elif is_open:ui.footer=str(result.get("error","Core3 did not confirm this operation."));ui.queue_redraw()
func _process(dt:float)->void:
	if not is_open:return
	if not owner_controller.allowed:close();return
	if owner_controller.bag.is_open:cancel_press();return
	if global_position.distance_to(body.global_position)>5:close();return
	poll-=dt
	var hand:XRController3D=rig.get_node("RightHand" if offhand=="left" else "LeftHand")
	if not Hands.controller_tracked(hand):cancel_press();gripping=false;sliding=false;latched_output=-1;return
	var hit:=find_hit(pointing_pose(hand))
	if slider_frame(hit,hand.global_transform,hand.get_float("grip"),hand.get_float("trigger"),not owner_controller.busy and owner_controller.bag.held_item.is_empty()):gripping=hand.get_float("grip")>.65;return
	update_pointer(hit,hand.get_float("trigger"))
	var down:=hand.get_float("grip")>.65
	if down and not gripping:
		if not hit.is_empty() and int(hit.surface)==2:latched_output=output.row_at(hit.pixel);grip_anchor=hand.global_position
	if down and latched_output>=0 and hand.global_position.distance_to(grip_anchor)>.06:
		var selected:=latched_output;latched_output=-1;collect_output(selected)
	if not down:sliding=false;latched_output=-1
	gripping=down
	var stick:Vector2=hand.get_vector2("primary")
	if stick.length()>.4 and not hit.is_empty():
		var pane:Control=ui if int(hit.surface)==0 else output if int(hit.surface)==2 else null
		if pane!=null and scroll_delay<=0:pane.scroll(-stick.y);scroll_delay=.2
	scroll_delay=maxf(0,scroll_delay-dt)
	if poll<=0 and not owner_controller.busy:operate("status");poll=3
var scroll_delay:=0.0
