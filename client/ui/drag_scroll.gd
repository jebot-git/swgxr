extends Node
## Defer a potential click until release, so dragging never activates its contents.
var viewport:Viewport
var target:Control
var origin:=Vector2.ZERO
var initial:=Vector2.ZERO
var dragged:=false
var replaying:=false
var press:InputEventMouseButton
const DEADZONE:=8.0

func _ready()->void:
	viewport=get_viewport();set_process_input(true)
static func scrollbars(control:Control)->Array:
	if control is ScrollContainer:return [control.get_h_scroll_bar(),control.get_v_scroll_bar()]
	if control is ItemList:return [null,control.get_v_scroll_bar()]
	if control is RichTextLabel:return [null,control.get_v_scroll_bar()] if control.scroll_active else []
	if control is TextEdit:return [control.get_h_scroll_bar(),control.get_v_scroll_bar()]
	return []
static func can_scroll(control:Control)->bool:
	for bar in scrollbars(control):
		if is_instance_valid(bar) and bar.max_value-bar.min_value>bar.page:return true
	return false
static func at(root:Node,point:Vector2)->Control:
	# Descendants first: the innermost scroll area owns this gesture.
	var children:=root.get_children();children.reverse()
	for child in children:
		if child is SubViewport:continue
		if child is CanvasItem and not child.is_visible_in_tree():continue
		if child is Control and child.clip_contents and not child.get_global_rect().has_point(point):continue
		var found:=at(child,point)
		if found!=null:return found
	if root is Control and root.is_visible_in_tree() and root.get_global_rect().has_point(point) and can_scroll(root):return root
	return null
func cancel()->void:
	target=null;press=null;dragged=false
func begin(root:Node,point:Vector2)->bool:
	cancel()
	if root is Viewport:
		# Follow the actual GUI hit route: respect modal overlays and avoid a
		# traversal of the entire streamed 3D world for every pointer press.
		var hovered:Control=root.gui_get_hovered_control()
		while is_instance_valid(hovered):
			if hovered is Range or hovered is LineEdit:return false
			if can_scroll(hovered):target=hovered;break
			hovered=hovered.get_parent_control()
	else:target=at(root,point)
	if target==null:return false
	var hovered:=target.get_viewport().gui_get_hovered_control()
	if hovered is Range or hovered is LineEdit:cancel();return false
	origin=point
	var bars:=scrollbars(target)
	initial=Vector2(bars[0].value if is_instance_valid(bars[0]) else 0,bars[1].value if is_instance_valid(bars[1]) else 0)
	return true
func move(point:Vector2)->bool:
	if not is_instance_valid(target):cancel();return false
	var delta:Vector2=(point-origin)/target.get_global_transform_with_canvas().get_scale().abs().max(Vector2(.1,.1))
	if delta.length()>DEADZONE:dragged=true
	if dragged:
		var bars:=scrollbars(target)
		if is_instance_valid(bars[0]):bars[0].value=initial.x-delta.x
		if is_instance_valid(bars[1]):
			# TextEdit's vertical scrollbar counts lines, other controls use pixels.
			bars[1].value=initial.y-delta.y/(maxf(1,target.get_line_height()) if target is TextEdit else 1.0)
	return dragged
func finish(point:Vector2)->bool:
	move(point);var consumed:=dragged;cancel();return consumed
func _input(event:InputEvent)->void:
	if replaying:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if begin(viewport,event.position):press=event.duplicate();viewport.set_input_as_handled()
		elif press!=null:
			var down:=press;var valid:=is_instance_valid(target) and target.is_visible_in_tree();var consumed:=finish(event.position)
			viewport.set_input_as_handled()
			if valid and not consumed:
				replaying=true;viewport.push_input(down,true);viewport.push_input(event.duplicate(),true);replaying=false
	elif event is InputEventMouseMotion and press!=null:
		move(event.position);viewport.set_input_as_handled()
func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:cancel()
