extends ScrollContainer
## Canvas page dragging and deterministic controller scrolling, preserving sliders/text.
const GROUP := "frontend_scrolls"
const Choice=preload("res://scripts/frontend_choice.gd")
var origin:=Vector2.ZERO
var initial:=0
var held:=false
var dragged:=false
var fraction:=0.0
func _ready() -> void:
	add_to_group(GROUP);scroll_deadzone=100000
	visibility_changed.connect(func():
		if not is_visible_in_tree():cancel())
func cancel() -> void:held=false;dragged=false;fraction=0
static func scroll_at(viewport: Viewport,point: Vector2,axis: float,delta: float) -> bool:
	if Choice.scroll_active(viewport,axis,delta):return true
	var target=target_at(viewport,point)
	if target==null:return false
	target.scroll_axis(axis,delta);return true
static func target_at(viewport: Viewport,point: Vector2):
	var hovered:=viewport.gui_get_hovered_control()
	var ancestor:=hovered
	while ancestor!=null:
		if ancestor is TextEdit or ancestor is LineEdit or ancestor is Range:return null
		if ancestor is ScrollContainer:break
		ancestor=ancestor.get_parent_control()
	for candidate in viewport.get_tree().get_nodes_in_group(GROUP):
		if candidate.get_viewport()!=viewport or not candidate.is_visible_in_tree():continue
		if (ancestor==null or ancestor==candidate) and candidate.get_global_rect().has_point(point) and (hovered==candidate or (hovered!=null and candidate.is_ancestor_of(hovered))):return candidate
	return null
func scroll_axis(axis: float,delta: float) -> void:
	if absf(axis)<=.25:fraction=0;return
	fraction+=signf(axis)*(absf(axis)-.25)/.75*600*delta
	var pixels:=int(fraction);fraction-=pixels;scroll_vertical+=pixels
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if target_at(get_viewport(),event.position)!=self:return
			var hover:=get_viewport().gui_get_hovered_control()
			while hover!=null and hover!=self:
				if hover is Range or hover is LineEdit or hover is TextEdit or hover is BaseButton:return
				hover=hover.get_parent_control()
			held=true;dragged=false;origin=event.position;initial=scroll_vertical
		elif held:
			var consume:=dragged;cancel()
			if consume:get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and held:
		var distance:float=(event.position.y-origin.y)/maxf(.1,get_global_transform_with_canvas().get_scale().y)
		if absf(distance)>8:dragged=true
		if dragged:scroll_vertical=initial-roundi(distance);get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:cancel()
