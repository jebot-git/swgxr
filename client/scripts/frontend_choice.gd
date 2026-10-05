extends Button
## A bounded selection list rendered in the same canvas as its owning menu.
## Synthetic XR mouse/touch pairs never create or dismiss a native popup window.
signal item_selected(index: int)
const GROUP := "frontend_choices"
var items: Array[Dictionary] = []
var selected := -1
var item_count: int:
	get: return items.size()
var fit_to_longest_item := false
var popup: PanelContainer
var scroll: ScrollContainer
var rows: VBoxContainer
var overlay: Control
var popup_height := 320.0
var drag_origin := Vector2.ZERO
var drag_initial := 0
var drag_pressed := false
var dragged := false
var scroll_fraction := 0.0

func _ready() -> void:
	add_to_group(GROUP)
	text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	alignment=HORIZONTAL_ALIGNMENT_LEFT
	var layer:=CanvasLayer.new();layer.layer=50;add_child(layer)
	overlay=Control.new();layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.theme=preload("res://scripts/frontend_theme.gd").build()
	popup=PanelContainer.new();overlay.add_child(popup)
	popup.add_theme_stylebox_override("panel",preload("res://scripts/datapad_theme.gd").box("071c29","67dcea",2,8))
	scroll=ScrollContainer.new();popup.add_child(scroll)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone=100000;scroll.follow_focus=true
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	pressed.connect(toggle_popup)
	visibility_changed.connect(func():
		if not is_visible_in_tree():close_popup())
	overlay.hide()
	_update_label()

func add_item(label: String, id: int=-1) -> void:
	items.append({"text":label,"id":items.size() if id<0 else id,"metadata":null,"disabled":false})
	if selected<0:selected=0
	_update_label()
func clear() -> void:
	close_popup();items.clear();selected=-1;_update_label()
func select(index: int) -> void:
	selected=index if index>=0 and index<items.size() else -1
	_update_label()
func get_item_text(index: int) -> String:return str(items[index].text) if index>=0 and index<items.size() else ""
func get_item_metadata(index: int) -> Variant:return items[index].metadata if index>=0 and index<items.size() else null
func set_item_metadata(index: int,value: Variant) -> void:items[index].metadata=value
func get_selected_metadata() -> Variant:return get_item_metadata(selected)
func get_selected_id() -> int:return int(items[selected].id) if selected>=0 else -1
func set_item_disabled(index: int,value: bool) -> void:items[index].disabled=value
func is_item_disabled(index: int) -> bool:return bool(items[index].disabled)
func _update_label() -> void:text=(get_item_text(selected) if selected>=0 else "Select…")+"  ▾"

func toggle_popup() -> void:
	if is_open():close_popup()
	else:open_popup()
func is_open() -> bool:return is_instance_valid(overlay) and overlay.visible
func open_popup() -> void:
	if disabled or items.is_empty() or not is_visible_in_tree():return
	close_all(get_viewport())
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	for index in range(items.size()):
		var row:=Button.new();row.text=get_item_text(index);row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		row.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		row.custom_minimum_size.y=44;row.disabled=is_item_disabled(index)
		rows.add_child(row)
		row.pressed.connect(_choose.bind(index))
	var bounds:=get_viewport_rect().size
	var transform:=get_global_transform_with_canvas()
	var factor:=transform.get_scale().abs()
	factor.x=maxf(.1,factor.x);factor.y=maxf(.1,factor.y)
	popup.scale=factor
	var width:=minf(maxf(size.x,180),maxf(80,(bounds.x-24)/factor.x))
	var height:=minf(minf(popup_height,items.size()*48+16),maxf(44,(bounds.y-24)/factor.y))
	popup.size=Vector2(width,height)
	var below:=transform*Vector2(0,size.y)
	var y:=below.y if below.y+height*factor.y<=bounds.y-12 else transform.origin.y-height*factor.y
	popup.position=Vector2(clampf(below.x,12,maxf(12,bounds.x-width*factor.x-12)),clampf(y,12,maxf(12,bounds.y-height*factor.y-12)))
	scroll.scroll_vertical=maxi(0,selected*48-48)
	drag_pressed=false;dragged=false;scroll_fraction=0
	overlay.show()
	focus_selected.call_deferred()
func focus_selected() -> void:
	if is_open() and selected>=0 and selected<rows.get_child_count():
		var row: Button=rows.get_child(selected)
		if not row.disabled:row.grab_focus();scroll.ensure_control_visible(row)
func close_popup() -> void:
	if is_instance_valid(overlay):overlay.hide()
	drag_pressed=false;dragged=false;scroll_fraction=0
func _choose(index: int) -> void:
	if not is_open() or dragged or disabled or is_item_disabled(index):return
	select(index);close_popup();grab_focus();item_selected.emit(index)
static func close_all(viewport: Viewport) -> void:
	for choice in viewport.get_tree().get_nodes_in_group(GROUP):
		if choice.get_viewport()==viewport:choice.close_popup()
static func scroll_active(viewport: Viewport,axis: float,delta: float) -> bool:
	for choice in viewport.get_tree().get_nodes_in_group(GROUP):
		if choice.get_viewport()==viewport and choice.is_open():
			choice.scroll_axis(axis,delta);return true
	return false
func scroll_axis(axis: float,delta: float) -> void:
	if absf(axis)<=.25:scroll_fraction=0;return
	scroll_fraction+=signf(axis)*(absf(axis)-.25)/.75*600*delta
	var pixels:=int(scroll_fraction);scroll_fraction-=pixels
	scroll.scroll_vertical+=pixels
func _input(event: InputEvent) -> void:
	if not is_open():return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		close_popup();get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not popup.get_global_rect().has_point(event.position):
				close_popup();get_viewport().set_input_as_handled();return
			drag_origin=event.position;drag_initial=scroll.scroll_vertical;drag_pressed=true;dragged=false
		elif drag_pressed:
			drag_pressed=false
			if dragged:
				for row in rows.get_children():row.set_pressed_no_signal(false)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_pressed:
		var distance: float=(event.position.y-drag_origin.y)/popup.scale.y
		if absf(distance)>8:dragged=true
		if dragged:
			scroll.scroll_vertical=drag_initial-roundi(distance);get_viewport().set_input_as_handled()
func _process(_delta: float) -> void:
	if is_open() and (disabled or not is_visible_in_tree()):close_popup()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:close_popup()
