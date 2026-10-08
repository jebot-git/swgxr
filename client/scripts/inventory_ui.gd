extends Control
## Fixed 8x4 visible grid. Models render in one shared viewport behind this UI.
signal selection_changed(item: Dictionary)
signal page_changed
signal split_requested(item: Dictionary, amount: int)
signal unequip_requested(item: Dictionary)
const FONT = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
const COLUMNS := 8
const ROWS := 4
const SLOTS := 32
const PIXELS := Vector2i(1024,640)
const GRID_ORIGIN := Vector2(16,100)
const CELL := Vector2(124,126)
var crafting_timers: Dictionary = {}
var snapshot: Dictionary = {}
var items: Array = []
var container_id := ""
var pending := false
var split_slider: HSlider
var split_button: Button
var split_label: Label
var container_button: Button
var back_button: Button
var container_switch: OptionButton
var unequip_button: Button
var first_row := 0
var selected_id := ""
var hovered := -1
var navigation_anchor:=Vector2.INF
var unavailable: Dictionary = {}
var status := "Waiting for Core3 inventory…"
var detail: Control
var detail_item: Dictionary = {}
var detail_title: Label
var detail_text: RichTextLabel

func _init() -> void:
	theme=preload("res://scripts/datapad_theme.gd").build()
	custom_minimum_size=Vector2(PIXELS)
	size=Vector2(PIXELS)
	mouse_filter=Control.MOUSE_FILTER_STOP
	gui_input.connect(on_input)
	container_switch=OptionButton.new(); add_child(container_switch)
	container_switch.position=Vector2(786,14); container_switch.size=Vector2(220,48)
	container_switch.add_theme_font_size_override("font_size",18)
	container_switch.item_selected.connect(func(index):
		container_id=str(container_switch.get_item_metadata(index)); first_row=0; selected_id=""; detail_item={}; set_snapshot(snapshot))

func configure_details() -> Control:
	detail=Control.new(); detail.theme=theme; detail.custom_minimum_size=Vector2(420,640); detail.size=Vector2(420,640)
	var panel:=Panel.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); detail.add_child(panel)
	panel.add_theme_stylebox_override("panel",preload("res://scripts/datapad_theme.gd").frame(10,"tall"))
	detail_title=Label.new(); detail.add_child(detail_title); detail_title.position=Vector2(20,18); detail_title.size=Vector2(380,80)
	detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; detail_title.add_theme_font_override("font",FONT); detail_title.add_theme_font_size_override("font_size",24)
	detail_title.text="ITEM INFORMATION"
	detail_text=RichTextLabel.new(); detail.add_child(detail_text); detail_text.position=Vector2(20,350); detail_text.size=Vector2(380,130)
	detail_text.add_theme_font_override("normal_font",FONT); detail_text.add_theme_font_size_override("normal_font_size",19)
	detail_text.text="Point and trigger to select.\nGrip to inspect in your hand.\nRelease to return to the backpack."
	split_label=Label.new(); detail.add_child(split_label); split_label.position=Vector2(20,487); split_label.size=Vector2(380,30); split_label.add_theme_font_override("font",FONT)
	split_slider=HSlider.new(); detail.add_child(split_slider); split_slider.position=Vector2(20,520); split_slider.size=Vector2(230,28); split_slider.min_value=1; split_slider.step=1
	split_slider.value_changed.connect(func(value): split_label.text="Split %d / %d"%[int(value),int(detail_item.get("quantity",1))])
	split_button=Button.new(); detail.add_child(split_button); split_button.position=Vector2(265,508); split_button.size=Vector2(135,42); split_button.text="Split stack"
	split_button.pressed.connect(func():
		if pending or not bool(detail_item.get("split_available",false)) or str(detail_item.get("local_state","")) in ["held","dropped"]: return
		set_pending(true); split_requested.emit(detail_item.duplicate(true),int(split_slider.value)))
	unequip_button=Button.new();detail.add_child(unequip_button);unequip_button.position=Vector2(20,502);unequip_button.size=Vector2(380,46);unequip_button.text="Return to inventory"
	unequip_button.pressed.connect(func():
		if pending or not detail_item.get("unequip_available",false):return
		set_pending(true);unequip_requested.emit(detail_item.duplicate(true)))
	container_button=Button.new(); detail.add_child(container_button); container_button.position=Vector2(20,566); container_button.size=Vector2(180,46); container_button.text="Open container"
	container_button.pressed.connect(func(): open_container(str(detail_item.get("id",""))))
	back_button=Button.new(); detail.add_child(back_button); back_button.position=Vector2(218,566); back_button.size=Vector2(182,46); back_button.text="Parent container"; back_button.pressed.connect(parent_container)
	for button in [split_button,container_button,back_button]: button.add_theme_font_size_override("font_size",18)
	refresh_controls()
	return detail

func set_snapshot(value: Dictionary) -> void:
	snapshot=value.duplicate(true)
	if container_id.is_empty(): container_id=str(snapshot.get("inventory",{}).get("id",""))
	var container:=current_container()
	if container.is_empty(): container_id=str(snapshot.get("inventory",{}).get("id","")); container=current_container()
	items=[]
	for item: Dictionary in snapshot.get("items",[]):
		if str(item.get("container_id",""))==container_id: items.append(item)
	if container_id=="@equipment":items=snapshot.get("equipment",[]).duplicate(true)
	snapshot["capacity"]=container.get("capacity",0)
	snapshot["count"]=container.get("occupied",0)
	status=str(snapshot.get("error",""))
	first_row=clampi(first_row,0,max_first_row())
	if not selected_id.is_empty():
		var selected:=items.filter(func(item): return str(item.get("id",""))==selected_id)
		if selected.is_empty(): selected_id=""; detail_item={}
		else: select_item(selected[0])
	refresh_container_switch(); refresh_controls(); queue_redraw(); page_changed.emit()

func max_first_row() -> int:
	return maxi(0,int(ceil(float(maxi(items.size(),int(snapshot.get("capacity",0))))/COLUMNS))-ROWS)

func scroll_rows(direction: int) -> void:
	var next:=clampi(first_row+direction,0,max_first_row())
	if next==first_row: return
	first_row=next; hovered=-1; queue_redraw(); page_changed.emit()

func navigate(direction: int, pixel: Vector2=Vector2.INF) -> void:
	if pending or items.is_empty() or direction==0:return
	var index:=-1
	for i in range(items.size()):
		if str(items[i].get("id",""))==selected_id:index=i;break
	index=clampi(first_row*COLUMNS if index<0 else index+direction,0,items.size()-1)
	var row:=index/COLUMNS
	first_row=clampi(first_row,maxi(0,row-ROWS+1),row)
	first_row=mini(first_row,max_first_row())
	navigation_anchor=pixel
	hovered=-1;select_item(items[index]);page_changed.emit()

func navigation_target(pixel:Vector2)->Vector2:
	if pixel.distance_to(navigation_anchor)>12:return pixel
	for i in range(items.size()):
		if str(items[i].get("id",""))==selected_id:
			var visible_index:=i-first_row*COLUMNS
			return GRID_ORIGIN+Vector2(visible_index%COLUMNS+.5,visible_index/COLUMNS+.5)*CELL
	return pixel

func visible_items() -> Array:
	return items.slice(first_row*COLUMNS,mini(items.size(),first_row*COLUMNS+SLOTS))

func slot_at(pixel: Vector2) -> int:
	var local:=pixel-GRID_ORIGIN
	if local.x<0 or local.y<0: return -1
	var col:=int(local.x/CELL.x); var row:=int(local.y/CELL.y)
	if col>=COLUMNS or row>=ROWS: return -1
	return first_row*COLUMNS+row*COLUMNS+col

func item_at(pixel: Vector2) -> Dictionary:
	var slot:=slot_at(pixel)
	return items[slot] if slot>=0 and slot<items.size() else {}

func select_item(item: Dictionary) -> void:
	selected_id=str(item.get("id","")); detail_item=item
	if detail_title!=null:
		detail_title.text=str(item.get("name",item.get("template","Item")))
		var text: String="Quantity: %d"%int(item.get("quantity",1))
		var description:=str(item.get("description",""))
		if not description.is_empty() and not description.begins_with("@"): text+="\n"+description
		for attribute: Variant in item.get("attributes",[]):
			text+="\n"+(attribute_name(str(attribute.get("name","")))+": "+str(attribute.get("value","")) if attribute is Dictionary else str(attribute))
		if unavailable.has(selected_id): text+="\nOriginal model unavailable."
		detail_text.text=text
	refresh_controls(); selection_changed.emit(item); queue_redraw()

func on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered=slot_at(event.position); queue_redraw()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		var item:=item_at(event.position)
		if not item.is_empty(): select_item(item)

func _draw() -> void:
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(12,"wide"),Rect2(Vector2.ZERO,Vector2(PIXELS)))
	draw_string(FONT,Vector2(24,37),"INVENTORY",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("d2f6ff"))
	var count_text: String="%s / %s  ·  Rows %d–%d"%[str(int(snapshot.count)) if snapshot.has("count") else "?",str(int(snapshot.capacity)) if snapshot.has("capacity") else "?",first_row+1,first_row+ROWS]
	draw_string(FONT,Vector2(310,36),count_text,HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("9ac7da"))
	draw_string(FONT,Vector2(24,75),status if not status.is_empty() else "Point + trigger: select   ·   Grip: hold item   ·   Stick: select",HORIZONTAL_ALIGNMENT_LEFT,980,18,Color("9ac7da"))
	for i in range(SLOTS):
		var index:=first_row*COLUMNS+i
		var rect:=Rect2(GRID_ORIGIN+Vector2(i%COLUMNS,i/COLUMNS)*CELL,CELL-Vector2(6,6))
		var item: Dictionary=items[index] if index<items.size() else {}
		var selected:=not item.is_empty() and str(item.get("id",""))==selected_id
		var slot_style:=preload("res://scripts/datapad_theme.gd").cell(selected or index==hovered)
		slot_style.draw_center=false # Keep the original model viewport visible.
		draw_style_box(slot_style,rect)
		if item.is_empty():
			draw_string(FONT,rect.position+Vector2(28,65),"EMPTY",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("326270"))
		else:
			var id:=str(item.get("id",""))
			if str(item.get("local_state","")) in ["held","dropped"]: draw_string(FONT,rect.position+Vector2(5,53),str(item.local_state).to_upper(),HORIZONTAL_ALIGNMENT_CENTER,108,13,Color("dbb27d"))
			elif unavailable.has(id): draw_string(FONT,rect.position+Vector2(5,53),"NO MODEL",HORIZONTAL_ALIGNMENT_CENTER,108,13,Color("dbb27d"))
			var label:=str(item.get("name","Item"))
			if id in crafting_timers: draw_string(FONT,rect.position+Vector2(5,88),"%ds"%int(crafting_timers[id]),HORIZONTAL_ALIGNMENT_CENTER,108,18,Color("d2f6ff"))
			if label.length()>13: label=label.substr(0,12)+"…"
			draw_string(FONT,rect.position+Vector2(5,111),label,HORIZONTAL_ALIGNMENT_CENTER,108,13,Color("d2f6ff"))

func current_container() -> Dictionary:
	if container_id=="@equipment":return {"capacity":snapshot.get("equipment",[]).size(),"occupied":snapshot.get("equipment",[]).size()}
	if container_id==str(snapshot.get("inventory",{}).get("id","")): return snapshot.get("inventory",{})
	for container: Dictionary in snapshot.get("containers",[]):
		if str(container.get("id",""))==container_id: return container
	return {}

func open_container(id: String) -> void:
	for container: Dictionary in snapshot.get("containers",[]):
		if str(container.get("id",""))==id:
			container_id=id; first_row=0; selected_id=""; detail_item={}; set_snapshot(snapshot); return

func parent_container() -> void:
	var container:=current_container()
	container_id=str(container.get("parent_id",snapshot.get("inventory",{}).get("id","")))
	first_row=0; selected_id=""; detail_item={}; set_snapshot(snapshot)

func set_pending(value: bool) -> void:
	pending=value; container_switch.disabled=false; refresh_controls(); queue_redraw()

func refresh_controls() -> void:
	if split_button==null: return
	var supported:=bool(detail_item.get("split_supported",false))
	var available:=bool(detail_item.get("split_available",false)) and str(detail_item.get("local_state","")) not in ["held","dropped"]
	split_slider.visible=supported; split_button.visible=supported; split_label.visible=supported
	split_slider.max_value=maxi(1,int(detail_item.get("split_max_quantity",1)))
	split_slider.editable=available and not pending; split_button.disabled=not available or pending
	split_label.text=("Split %d / %d"%[int(split_slider.value),int(detail_item.get("quantity",1))]) if available else str(detail_item.get("split_block_reason","No room to split"))
	unequip_button.visible=bool(detail_item.get("equipped",false))
	unequip_button.disabled=pending or not bool(detail_item.get("unequip_available",false))
	unequip_button.tooltip_text=str(detail_item.get("unequip_block_reason",""))
	if unequip_button.visible:split_slider.hide();split_button.hide();split_label.hide()
	container_button.disabled=not bool(detail_item.get("is_container",false))
	back_button.disabled=container_id==str(snapshot.get("inventory",{}).get("id",""))

func refresh_container_switch() -> void:
	container_switch.clear()
	container_switch.add_item("Inventory")
	container_switch.set_item_metadata(0,str(snapshot.get("inventory",{}).get("id","")))
	var backpack: Variant=snapshot.get("equipped_backpack")
	if backpack is Dictionary and not str(backpack.get("id","")).is_empty():
		container_switch.add_item("Equipped backpack")
		container_switch.set_item_metadata(1,str(backpack.id))
		if container_id==str(backpack.id): container_switch.select(1)
	container_switch.add_item("Equipped items");container_switch.set_item_metadata(container_switch.item_count-1,"@equipment")
	if container_id=="@equipment":container_switch.select(container_switch.item_count-1)
	container_switch.disabled=false

func attribute_name(value: String) -> String:
	var label:=value.get_slice(":",value.get_slice_count(":")-1)
	if label.begins_with("cat_"): label=label.substr(4)
	return label.replace("_"," ").capitalize()
