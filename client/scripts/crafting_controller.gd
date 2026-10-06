extends "res://scripts/xr_datapad.gd"
## Native Core3 crafting session with refundable ingredient escrow.
const CraftPanel = preload("res://scripts/crafting_panel.gd")
var app: Node
var bag: Node3D
var materials: Control
var state: Dictionary = {}
var allocations: Array = []
var points: Array = []
var colors: Array = []
var busy := false
var pending_selection: Dictionary={}
var selecting := false
var generation := 0
var pending_cancel := false
var held_id := ""
var selected_resource := -1
var slots: Array[Node3D] = []
var knobs: Array[Node3D] = []
var sliders: Array[Node3D] = []
var preview: Node3D
var preview_root: Node3D
var preview_missing: Label3D
var dragging := -1
var gripping := false
var grabbed_knob := -1
var grabbed_slider := -1
var knob_angle := 0.0
var knob_accum := 0.0
var next_poll := 0.0
var clock_offset := 0.0
var locked_pose := Transform3D.IDENTITY
var last_error := ""
var icon_catalog: Dictionary = {}
var drag_visual: Node3D
var scroll_delay := 0.0
var main_stick_captured := false
var navigation_surface:=-1
var hip_timer: Label3D
var ingredient_viewport: SubViewport
var ingredient_images: TextureRect
var blueprint_output: CheckButton
const KNOB_GRAB_RADIUS := 0.024

func setup(host: Node, inventory: Node3D) -> void:
	app=host;bag=inventory;rig=bag.rig;body=bag.body;offhand=bag.offhand;process_priority=123
	ui=CraftPanel.new(); materials=CraftPanel.new()
	add_surface(ui,Vector2i(660,660),Vector2(0.34,0.34))
	add_surface(materials,Vector2i(660,660),Vector2(0.34,0.34))
	var inner: float=-1 if offhand=="left" else 1
	surfaces[1].mesh.position=Vector3(inner*0.43,0,0.035)
	surfaces[1].mesh.rotation.y=deg_to_rad(-inner*25)
	preview_root=Node3D.new(); add_child(preview_root); preview_root.position=Vector3(-inner*0.43,0,0.035); preview_root.rotation.y=deg_to_rad(inner*25)
	var frame:=MeshInstance3D.new(); var plane:=QuadMesh.new(); plane.size=Vector2(0.32,0.34); frame.mesh=plane; frame.material_override=holo(Color(0.02,0.16,0.21,0.5)); preview_root.add_child(frame)
	var label:=label3d("ITEM PREVIEW",Vector3(0,0.14,0.015));preview_root.add_child(label)
	preview_missing=label3d("Original preview unavailable",Vector3(0,0,0.015));preview_missing.font_size=18;preview_missing.visible=false;preview_root.add_child(preview_missing)
	dot=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.003;sphere.height=0.006;dot.mesh=sphere;dot.material_override=holo(Color("baffff"));add_child(dot)
	ingredient_viewport=bag.create_model_viewport(Vector2i(660,660))
	ingredient_images=TextureRect.new();ingredient_images.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ingredient_images.texture=ingredient_viewport.get_texture();ingredient_images.size=Vector2(660,660);materials.add_child(ingredient_images)
	materials.page_changed.connect(refresh_material_page)
	ui.chosen.connect(select_schematic);materials.chosen.connect(select_resource)
	bag.crafting_requested.connect(activate)
	bag.item_held_changed.connect(held_changed)
	var icon_path: String="res://../runtime/assets/crafting/catalog.json"
	if FileAccess.file_exists(icon_path): icon_catalog=JSON.parse_string(FileAccess.get_file_as_string(icon_path))
	var holster:=Button.new();ui.add_child(holster);holster.position=Vector2(540,8);holster.size=Vector2(105,38);holster.text="Tool slot"
	blueprint_output=CheckButton.new();ui.add_child(blueprint_output);blueprint_output.position=Vector2(20,540);blueprint_output.size=Vector2(610,42);blueprint_output.text="Create factory blueprint · 1000 runs";blueprint_output.hide()
	holster.pressed.connect(func():
		cancel_draft()
		bag.show_equipment_hologram(rig.get_node("XRCamera3D").global_transform))
	hip_timer=label3d("",Vector3.ZERO);bag.add_child(hip_timer);hip_timer.top_level=true;hip_timer.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	set_visible_ui(false)

func holo(color: Color) -> StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;value.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;value.albedo_color=color;return value
func label3d(text: String, point: Vector3) -> Label3D:
	var label:=Label3D.new();label.text=text;label.position=point;label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=24;label.pixel_size=0.00035;label.modulate=Color("baffff");label.outline_size=3;return label
func set_visible_ui(value: bool) -> void:
	is_open=value;visible=value
	for surface: Dictionary in surfaces:
		surface.mesh.visible=value;surface.viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if value else SubViewport.UPDATE_DISABLED
	if not value:
		cancel_press();clear_hover();cancel_grab();stick_captured=false;main_stick_captured=false;navigation_surface=-1
		if is_instance_valid(body): body.set_interface_capture(false,false)
func reset() -> void:
	if not str(state.get("session_id","")).is_empty(): cancel_draft()
	generation+=1;state={};pending_selection.clear();held_id="";set_visible_ui(false)
func held_changed(item: Dictionary) -> void:
	var next_id:=str(item.get("id","")) if item.get("tool_kind","")=="crafting" else ""
	if next_id!=held_id:
		pending_selection.clear()
		set_visible_ui(false)
		if busy: pending_cancel=true
		elif not str(state.get("session_id","")).is_empty(): cancel_draft()
		held_id=next_id
func source_position() -> Array:
	var p: Vector3=app.source_position_at(app.player.global_position)
	return [p.x,p.y,p.z]
func request_id() -> String: return "craft-%d-%d"%[Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()]
func request(action: String, extra: Dictionary={}) -> Dictionary:
	if busy or app.datapad_character_id.is_empty(): return {}
	busy=true;var epoch: int=app.datapad_epoch;var version:=generation
	var payload: Dictionary={"account":app.datapad_account,"character_id":app.datapad_character_id,"tool_id":held_id,"session_id":state.get("session_id",""),"request_id":request_id(),"position":source_position()}
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if not native_id.is_empty(): payload.live_session_id=native_id
	if is_instance_valid(app.stage) and app.stage.get("current_cell") is Dictionary:
		var key: String=str(app.stage.current_cell.get("cell_id",""))
		payload.building_id=str(app.stage.current_cell.get("building_object_id","0")) if key.contains(":") else "0"
		payload.cell_index=int(key.get_slice(":",1)) if key.contains(":") else 0
	payload.merge(extra,true)
	var path: String="/crafting/"+action
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,path,payload)
	busy=false
	if epoch!=app.datapad_epoch or version!=generation: return {}
	if result.get("ok",false) and result.get("state",{}).get("character_id","")==app.datapad_character_id:
		state=result.state.duplicate(true);clock_offset=float(state.server_time)-Time.get_unix_time_from_system()
		if result.get("inventory",{}).get("source_kind","")=="core3_inventory":
			app.inventory_snapshot=result.inventory.duplicate(true);app.reconcile_inventory_presentations();app.update_inventory_presentation()
		last_error=""
		if action=="finish" and is_instance_valid(app.get("services")):app.services.poll_clock=0
	else: last_error=str(result.get("error","Core3 did not confirm crafting. Refresh before retrying."))
	if pending_cancel:
		pending_cancel=false
		if not str(state.get("session_id","")).is_empty(): cancel_draft()
		return {}
	if not last_error.is_empty(): ui.footer=last_error;ui.queue_redraw();return {}
	drain_selection.call_deferred()
	return result
func activate(tool: Dictionary) -> void:
	if busy or selecting or not pending_selection.is_empty(): return
	held_id=str(tool.id)
	if not is_open:
		bag.set_open(false)
		var result:=await request("open")
		if result.is_empty(): bag.set_busy(false,last_error);return
		allocations=[];points=[];colors=[];selected_resource=-1;follower.reset();set_visible_ui(true);rebuild()
	else:
		if int(state.get("stage",0))==2:
			if not ready_to_assemble(): ui.footer="Fill every required ingredient cube first.";ui.queue_redraw();return
			var result:=await request("assemble",{"allocations":allocations})
			if result.is_empty(): bag.set_busy(false,last_error);return
		elif int(state.get("stage",0)) in [3,4]:
			var result:=await request("finish",{"points":points,"colors":colors,"output":"blueprint" if blueprint_output.button_pressed and state.get("can_create_blueprint",false) else "prototype"})
			if result.is_empty(): bag.set_busy(false,last_error);return
		rebuild()
	bag.set_busy(false,last_error)
func cancel_draft() -> void:
	set_visible_ui(false)
	await request("cancel")
func select_schematic(index: int) -> void:
	if int(state.get("stage",0))>2 or not is_open: return
	var choices: Array=state.get("schematics",[])
	if index<0 or index>=choices.size(): return
	pending_selection={"id":str(choices[index].get("id","")),"template":str(choices[index].get("template","")),"epoch":app.datapad_epoch,"generation":generation,"tool":held_id}
	ui.footer="Loading selected recipe from Core3…";ui.queue_redraw()
	drain_selection()

func drain_selection() -> void:
	if busy or selecting or pending_selection.is_empty(): return
	var selection:=pending_selection;pending_selection={}
	if not is_open or selection.epoch!=app.datapad_epoch or selection.generation!=generation or selection.tool!=held_id or int(state.get("stage",0))>2: return
	var choices: Array=state.get("schematics",[])
	var resolved_index:=-1
	for i in range(choices.size()):
		if str(choices[i].get("id",""))==selection.id and str(choices[i].get("template",""))==selection.template:
			resolved_index=i;break
	if resolved_index<0:
		ui.footer="The selected recipe is no longer available. Select another recipe.";ui.queue_redraw();return
	selecting=true
	var result:=await request("select",{"index":int(choices[resolved_index].index)})
	selecting=false
	if not result.is_empty():
		allocations=[]
		for slot in state.get("schematic",{}).get("slots",[]): allocations.append([])
		ui.selected=resolved_index
		selected_resource=-1;rebuild()
	if not pending_selection.is_empty():drain_selection.call_deferred()
func select_resource(index: int) -> void:
	if busy or int(state.get("stage",0))!=2: return
	selected_resource=index;materials.selected=index;materials.queue_redraw();update_slots()
func ready_to_assemble() -> bool:
	var definitions: Array=state.get("schematic",{}).get("slots",[])
	if definitions.size()!=allocations.size() or definitions.is_empty(): return false
	for i in range(definitions.size()):
		if (not definitions[i].get("optional",false) or not allocations[i].is_empty()) and slot_amount(i)<int(definitions[i].quantity): return false
	return true
func slot_amount(index: int) -> int:
	var total:=0
	if index>=allocations.size(): return 0
	for id in allocations[index]:
		for item: Dictionary in state.get("inventory",[]):
			if str(item.id)==str(id): total+=int(item.quantity)
	return total
func compatible(item: Dictionary, index: int) -> bool:
	return item.get("slots",[]).any(func(value): return int(value)==index)

func place_resource(resource: int, slot: int) -> bool:
	if busy or int(state.get("stage",0))!=2: return false
	var items: Array=state.get("inventory",[]);var definitions: Array=state.get("schematic",{}).get("slots",[])
	if resource<0 or resource>=items.size() or slot<0 or slot>=definitions.size(): return false
	var item: Dictionary=items[resource];var definition: Dictionary=definitions[slot]
	if not compatible(item,slot): return false
	var used:=0
	for i in range(allocations.size()):
		if i!=slot and str(item.id) in allocations[i]: used+=int(definitions[i].quantity)
	if int(definition.get("kind",0))==0:
		if int(item.quantity)-used<int(definition.quantity): return false
		allocations[slot]=[str(item.id)]
	else:
		if str(item.id) in allocations[slot] or int(item.quantity)-used<=0: return false
		if slot_amount(slot)>=int(definition.quantity): allocations[slot]=[]
		allocations[slot].append(str(item.id))
	update_slots();return true
func set_points(index: int, value: int) -> bool:
	if busy or index<0 or index>=points.size(): return false
	var available:=int(state.get("points",0))
	for i in range(points.size()): if i!=index: available-=int(points[i])
	points[index]=clampi(value,0,mini(available,int(state.rows[index].point_limit)));refresh_experiment();return true
func cancel_grab() -> void:
	if is_instance_valid(drag_visual): drag_visual.queue_free()
	drag_visual=null
	dragging=-1;grabbed_knob=-1;grabbed_slider=-1;gripping=false
func rebuild() -> void:
	for node in slots+knobs+sliders: node.queue_free()
	slots.clear();knobs.clear();sliders.clear()
	if is_instance_valid(preview): preview.queue_free()
	preview=null;preview_missing.visible=false
	var stage:=int(state.get("stage",0))
	blueprint_output.visible=stage in [3,4] and state.get("can_create_blueprint",false)
	if stage<=2 or not blueprint_output.visible:blueprint_output.button_pressed=false
	if stage==0: set_visible_ui(false);return
	ui.enabled=stage<=2;materials.enabled=stage==2
	if stage<=2:
		ui.configure("USABLE SCHEMATICS",state.get("schematics",[]),"Stick: highlight · stick click: select · trigger assembles")
		materials.layout(true)
		materials.configure("INGREDIENTS",state.get("inventory",[]),"Finger selects quality · grip drags to cube")
		for i in range(state.get("schematic",{}).get("slots",[]).size()):
			var cube:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.075,0.075,0.075);cube.mesh=box;cube.material_override=holo(Color(0.1,0.7,0.85,0.2));add_child(cube);cube.position=Vector3((i%6-(mini(6,state.schematic.slots.size())-1)*0.5)*0.16,0.25+int(i/6)*0.16,0)
			var slot_label:=label3d("",Vector3(0,0.075,0.045));slot_label.width=350;slot_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;slot_label.font_size=20;cube.add_child(slot_label);slots.append(cube)
			var kind: String=str(state.schematic.slots[i].type)
			var icon: Dictionary=icon_catalog.get("icons",{}).get(kind,icon_catalog.get("icons",{}).get("default",{}))
			if not icon.is_empty():
				var image:=Image.load_from_file(ProjectSettings.globalize_path("res://../runtime/assets/crafting").path_join(str(icon.texture)))
				if image!=null:
					var sprite:=Sprite3D.new();sprite.texture=ImageTexture.create_from_image(image);sprite.pixel_size=0.06/image.get_width();sprite.position.z=0.04;cube.add_child(sprite)
		update_slots()
	else:
		points=[];colors=[]
		for i in range(state.get("rows",[]).size()):
			points.append(0);var knob:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=0.014;cylinder.bottom_radius=0.014;cylinder.height=0.015;knob.mesh=cylinder;knob.rotation.x=PI/2;knob.material_override=holo(Color("63dbe5"));add_child(knob);knob.add_child(label3d("•",Vector3(0,0.014,0)));knobs.append(knob)
		for i in range(state.get("colors",[]).size()):
			var color: Dictionary=state.colors[i];colors.append(clampi(int(color.value),int(color.minimum),int(color.maximum)))
			var slider:=Node3D.new();add_child(slider);slider.position=Vector3(0,-0.215-i*0.05,0)
			for n in range(int(color.maximum)+1):
				var tile:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.4/(int(color.maximum)+1),0.015,0.008);tile.mesh=box;var rgba: Array=color.colors[n];tile.material_override=holo(Color(rgba[0],rgba[1],rgba[2],1));tile.position.x=-0.2+(n+0.5)*box.size.x;slider.add_child(tile)
			var handle:=MeshInstance3D.new();handle.name="Handle";var shape:=BoxMesh.new();shape.size=Vector3(0.012,0.032,0.017);handle.mesh=shape;handle.material_override=holo(Color("e6fdff"));handle.position.z=0.01;slider.add_child(handle)
			sliders.append(slider)
			update_slider_handles()
		refresh_experiment()
	refresh_material_page()
	var template := preview_template()
	show_preview(template)

func preview_template() -> String:
	var template := str(state.get("prototype_template",""))
	if template.is_empty(): template=str(state.get("schematic",{}).get("template",""))
	if template.is_empty():
		var choices: Array=state.get("schematics",[])
		if not choices.is_empty(): template=str(choices[clampi(ui.selected,0,choices.size()-1)].get("template",""))
	return template

func show_preview(template: String, customization: Dictionary={}) -> void:
	if is_instance_valid(preview): preview.queue_free()
	preview=null
	preview_missing.visible=true
	if template.is_empty():
		preview_missing.text="No usable recipes returned by Core3."
		return
	var model: MeshInstance3D=bag.assets.instance(template,0.25,customization)
	if model==null:
		preview_missing.text="Original preview unavailable"
		return
	# Rotate a centered fitted model as a group: replacing its source-derived offset
	# or rotating the mesh around its authored origin shifts long/asymmetric items.
	preview=Node3D.new(); preview_root.add_child(preview); preview.add_child(model)
	preview.position=Vector3(0,-0.01,0.15);preview.rotation=Vector3(-0.1,0.5,0)
	preview_missing.visible=false
func refresh_experiment() -> void:
	var used:=0;var rows: Array=[]
	for i in range(points.size()):
		used+=int(points[i]);var row: Dictionary=state.rows[i];rows.append({"label":"%s  +%d / %d"%[str(row.name),int(points[i]),int(row.point_limit)],"bar":float(row.value)})
	materials.layout(false,true)
	materials.configure("EXPERIMENTATION",rows,"Grip knob · clockwise adds · reverse removes")
	refresh_material_page()
	var stats: Array=[]
	for value: Dictionary in state.get("statistics",[]): stats.append({"label":"%s: %.2f"%[str(value.name),float(value.value)]})
	ui.page_size=10 if blueprint_output.visible else 11
	ui.configure("POINTS: %d / %d"%[int(state.get("points",0))-used,int(state.get("points",0))],stats,"Trigger creates selected output · stow refunds ingredients")
func refresh_material_page() -> void:
	ingredient_images.visible=materials.grid_mode
	var models:=ingredient_viewport.get_node("Models")
	for child in models.get_children(): child.free()
	if materials.grid_mode:
		for i in range(materials.offset,mini(materials.rows.size(),materials.offset+materials.page_size)):
			var item: Dictionary=state.inventory[i]
			var model: Node3D=bag.assets.instance(str(item.template),82,item.get("customization",{}))
			if model==null: continue
			var cell: Rect2=materials.cell_rect(i)
			var pixel:=cell.position+Vector2(cell.size.x/2,66)
			var mount:=Node3D.new();models.add_child(mount);mount.position=Vector3(pixel.x-330,330-pixel.y,0)
			mount.rotation=Vector3(-0.12,0.65,0);mount.add_child(model)
		ingredient_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	else:
		ingredient_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		for i in range(knobs.size()):
			knobs[i].visible=i>=materials.offset and i<materials.offset+materials.page_size
			var y: float=CraftPanel.TOP+(i-materials.offset)*materials.row_height+materials.row_height/2
			knobs[i].transform=surfaces[1].mesh.transform*Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(0.145,(0.5-y/660)*0.34,0.02))

func update_slider_handles() -> void:
	for i in range(sliders.size()):
		var maximum:=maxi(1,int(state.colors[i].maximum)-int(state.colors[i].minimum))
		sliders[i].get_node("Handle").position.x=-0.2+0.4*float(int(colors[i])-int(state.colors[i].minimum))/maximum

func update_slots() -> void:
	var definitions: Array=state.get("schematic",{}).get("slots",[])
	for i in range(slots.size()):
		var value: Dictionary=definitions[i];var filled:=slot_amount(i)>=int(value.quantity)
		slots[i].material_override=holo(Color(0.1,0.9,0.6,0.6) if filled else Color(0.1,0.7,0.85,0.2))
		for child in slots[i].get_children():
			if child.has_meta("quality_bar"): child.queue_free()
		var quality: String=""
		var items: Array=state.get("inventory",[])
		if selected_resource>=0 and selected_resource<items.size() and compatible(items[selected_resource],i):
			var bar_index:=0
			var quality_names: Array=[]
			for q: Dictionary in items[selected_resource].get("quality",[]):
				if int(q.get("slot",i))!=i: continue
				if q.has("raw"): quality+="\n%s %.0f"%[str(q.name),float(q.raw)]
				if str(q.name) in quality_names: continue
				quality_names.append(str(q.name))
				var bar:=MeshInstance3D.new();bar.set_meta("quality_bar",true);var shape:=BoxMesh.new();var fraction:=clampf(float(q.value),0,1);shape.size=Vector3(maxf(0.001,0.068*fraction),0.006,0.002);bar.mesh=shape;bar.material_override=holo(Color("7ce3ba"));bar.position=Vector3(-0.034+shape.size.x/2,-0.048-bar_index*0.009,0.042);slots[i].add_child(bar);bar_index+=1
		slots[i].get_child(0).text="%s\n%d / %d%s"%[str(value.get("name",value.type)),mini(slot_amount(i),int(value.quantity)),int(value.quantity),quality]

func update_hand(grip: float, pose: Transform3D, hit: Dictionary) -> void:
	var down:=grip>=0.65
	if not gripping and down:
		locked_pose=global_transform
		if int(state.get("stage",0))==2 and not hit.is_empty() and int(hit.surface)==1:
			dragging=materials.row_at(hit.pixel)
			if dragging>=0:
				select_resource(dragging)
				drag_visual=bag.assets.instance(str(state.inventory[dragging].template),0.07)
				if drag_visual!=null: add_child(drag_visual)
		if dragging<0 and int(state.get("stage",0))==2:
			for i in range(slots.size()):
				if not allocations[i].is_empty() and pose.origin.distance_to(slots[i].global_position)<0.07:
					allocations[i]=[];update_slots();break
		for i in range(knobs.size()):
			if knobs[i].visible and pose.origin.distance_to(knobs[i].global_position)<KNOB_GRAB_RADIUS:
				grabbed_knob=i;knob_angle=twist_angle(pose);knob_accum=0;break
		for i in range(sliders.size()):
			var p: Vector3=sliders[i].to_local(pose.origin)
			if absf(p.x)<=0.24 and absf(p.y)<0.035 and absf(p.z)<0.07: grabbed_slider=i;break
	if is_instance_valid(drag_visual): drag_visual.global_position=pose.origin
	if down and grabbed_knob>=0:
		var angle:=twist_angle(pose)
		knob_accum+=wrapf(knob_angle-angle,-PI,PI);knob_angle=angle
		var steps:=int(knob_accum/deg_to_rad(25))
		if steps!=0:
			set_points(grabbed_knob,int(points[grabbed_knob])+steps);knob_accum-=steps*deg_to_rad(25)
			knobs[grabbed_knob].basis=surfaces[1].mesh.basis*Basis(Vector3.BACK,float(points[grabbed_knob])*deg_to_rad(25))*Basis(Vector3.RIGHT,PI/2)
	if down and grabbed_slider>=0:
		var p: Vector3=sliders[grabbed_slider].to_local(pose.origin)
		var choice: Dictionary=state.colors[grabbed_slider]
		colors[grabbed_slider]=roundi(lerpf(float(choice.minimum),float(choice.maximum),clampf((p.x+0.2)/0.4,0,1)))
		update_slider_handles();update_preview_color()
	if gripping and grip<0.35:
		if dragging>=0:
			for i in range(slots.size()):
				if pose.origin.distance_to(slots[i].global_position)<0.09:
					if not place_resource(dragging,i): ui.footer="Wrong ingredient or insufficient unallocated quantity.";ui.queue_redraw()
					break
		cancel_grab()
	elif down: gripping=true
func twist_angle(pose: Transform3D) -> float:
	var axis:=global_basis.inverse()*pose.basis.x
	return atan2(axis.y,axis.x)
func update_preview_color() -> void:
	var customization: Dictionary={}
	for i in range(colors.size()): customization[str(state.colors[i].name)]=int(colors[i])
	show_preview(preview_template(),customization)
func poll() -> void:
	if busy or app.datapad_character_id.is_empty(): return
	busy=true;var epoch: int=app.datapad_epoch
	var result: Dictionary
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if not native_id.is_empty():
		result=await app.api(HTTPClient.METHOD_POST,"/crafting/status",{"account":app.datapad_account,"character_id":app.datapad_character_id,"live_session_id":native_id})
	else:
		result=await app.api(HTTPClient.METHOD_GET,"/crafting?account="+app.datapad_account.uri_encode()+"&character_id="+app.datapad_character_id.uri_encode())
	busy=false
	if epoch!=app.datapad_epoch: return
	if result.get("ok",false):
		var fresh: Dictionary=result.get("state",{})
		if not fresh.get("character_id","")==app.datapad_character_id: return
		var old_jobs: Array=state.get("jobs",[])
		var old_stage:=int(state.get("stage",0))
		state=fresh;clock_offset=float(state.get("server_time",0))-Time.get_unix_time_from_system()
		if state.get("jobs",[]).size()<old_jobs.size():
			await app.refresh_inventory()
			if is_instance_valid(app.get("services")):app.services.poll_clock=0
		if is_open and old_stage!=int(state.get("stage",0)): rebuild()
		if is_open and str(state.get("session_id","")).is_empty(): set_visible_ui(false)
	if pending_cancel:
		pending_cancel=false
		if not str(state.get("session_id","")).is_empty(): cancel_draft()
	drain_selection.call_deferred()
func update_timers() -> void:
	var values: Dictionary={}
	for job: Dictionary in state.get("jobs",[]): values[str(job.tool_id)]=maxi(0,ceili(float(job.due)-Time.get_unix_time_from_system()-clock_offset))
	bag.crafting_timers=values
	if held_id in values:
		bag.held_status.text="CRAFTING  %02d:%02d"%[int(values[held_id])/60,int(values[held_id])%60];bag.held_status.visible=true
	elif bag.held_status.text.begins_with("CRAFTING  "): bag.held_status.text="";bag.held_status.visible=false
	bag.ui.crafting_timers=values;bag.ui.queue_redraw()
	if is_instance_valid(hip_timer):
		var hip_id:=str(bag.hip_tool.get("id",""));hip_timer.visible=hip_id in values and is_instance_valid(bag.hip_model) and bag.hip_model.visible
		if hip_timer.visible: hip_timer.global_position=bag.hip_model.global_position+Vector3.UP*0.09;hip_timer.text="%ds"%int(values[hip_id])
func _process(delta: float) -> void:
	if not is_instance_valid(app) or not is_instance_valid(rig) or not app.world_ready: return
	update_timers()
	next_poll-=delta
	if next_poll<=0 and not busy and not app.inventory_request_pending and not bag.action_pending and (not app.has_method("try_background_poll") or app.try_background_poll("crafting")):
		next_poll=4.0;poll()
	if not is_open: return
	if bag.is_open or not bag.allowed:
		set_visible_ui(false)
		if busy: pending_cancel=true
		else: cancel_draft()
		return
	var main: XRController3D=bag.held_controller()
	var off: XRController3D=bag.tool_pointer_controller()
	var head: XRCamera3D=rig.get_node("XRCamera3D")
	if not HandInput.controller_tracked(main) or not HandInput.controller_tracked(off): cancel_grab();cancel_press();clear_hover();return
	if not gripping:
		var facing: Vector3=(head.global_position-main.global_position).slide(Vector3.UP).normalized()
		if facing.length_squared()>0.5:
			var mount:=Transform3D(Basis(Vector3.UP.cross(facing),Vector3.UP,facing),main.global_position+Vector3.UP*0.24)
			var followed: Dictionary=follower.follow(mount,head.global_position,delta)
			if followed.get("valid",false): global_transform=followed.transform
	else: global_transform=locked_pose
	var hit:=find_hit(bag.tool_pointer_pose(off))
	if not gripping:
		var press: float=off.get_float("trigger")
		var hand_tracker=XRServer.get_tracker("/user/hand_tracker/"+("left" if bag.held_hand_side()=="right" else "right")) as XRHandTracker
		if hand_tracker!=null and hand_tracker.has_tracking_data: press=1.0 if not hit.is_empty() and float(hit.get("distance",1))<0.015 else 0.0
		update_pointer(hit,press)
	update_hand(off.get_float("grip"),off.global_transform,hit)
	update_scroll_inputs(main.get_vector2("primary"),off.get_vector2("primary"),hit,delta)

func confirm_button(side: String) -> bool:
	if not is_open:return false
	# The free hand confirms the last highlighted pane even after aim moves away.
	if side==bag.held_hand_side():return false
	if not gripping and navigation_surface>=0:
		var panel:Control=ui if navigation_surface==0 else materials
		panel.confirm_navigation()
	return true

func update_scroll_inputs(main_stick: Vector2, off_stick: Vector2, hit: Dictionary, delta: float) -> void:
	scroll_delay-=delta
	if not gripping and scroll_delay<=0:
		if int(state.get("stage",0))<=2 and absf(main_stick.y)>0.5:
			ui.scroll(-main_stick.y); navigation_surface=0; main_stick_captured=true; scroll_delay=0.18
		elif absf(off_stick.y)>0.5 and (not hit.is_empty() or int(state.get("stage",0))<=2):
			navigation_surface=int(hit.get("surface",0))
			if navigation_surface==0: ui.scroll(-off_stick.y)
			else: materials.scroll(-off_stick.y)
			stick_captured=true; scroll_delay=0.18
	if main_stick.length()<0.15: main_stick_captured=false
	if off_stick.length()<0.15: stick_captured=false
	var free_left:bool=bag.held_hand_side()=="right"
	var left_capture := stick_captured if free_left else main_stick_captured
	var right_capture := main_stick_captured if free_left else stick_captured
	body.set_interface_capture(left_capture,right_capture)

func _exit_tree() -> void:
	if is_instance_valid(hip_timer): hip_timer.queue_free()
	if is_instance_valid(ingredient_viewport): ingredient_viewport.queue_free()
