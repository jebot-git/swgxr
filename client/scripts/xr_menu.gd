extends Node3D
## Original client UI on XR Tools pointable surfaces, with its virtual keyboard.
const Surface = preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")
const KeyboardContent = preload("res://addons/godot-xr-tools/objects/keyboard/virtual_keyboard_2d.tscn")
var screen: XRToolsViewport2DIn3D
var keyboard: XRToolsViewport2DIn3D
var ui: Control
var camera: XRCamera3D
var input_active := true
var hovered_pointers: Dictionary = {}
var pointer_position := Vector2.ZERO
const Choice=preload("res://scripts/frontend_choice.gd")
const PageScroll=preload("res://scripts/frontend_scroll.gd")

func configure(content: Control, head: XRCamera3D) -> void:
	camera = head
	ui = content
	screen = Surface.instantiate()
	screen.name = "CharacterMenu"
	screen.screen_size = Vector2(2.88, 1.8)
	screen.viewport_size = Vector2(1440, 900)
	screen.unshaded = true
	screen.collision_layer = (1 << 20) | (1 << 22)
	add_child(screen)
	screen.viewport_size = Vector2(1440, 900)
	screen.pointer_event.connect(_pointer_event)
	content.reparent(screen.get_node("Viewport"))
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyboard = Surface.instantiate()
	keyboard.scene = KeyboardContent
	keyboard.screen_size = Vector2(1.5, 0.75)
	keyboard.viewport_size = Vector2(600, 300)
	keyboard.unshaded = true
	keyboard.name = "TextKeyboard"
	keyboard.collision_layer = (1 << 20) | (1 << 22)
	keyboard.position = Vector3(0, -1.15, 0.3)
	keyboard.rotation_degrees.x = -20.0
	# The original keyboard injects key events into the root viewport; the menu
	# surface forwards them to its focused field, exactly as physical key input.
	add_child(keyboard)
	keyboard.viewport_size = Vector2(600, 300)
	keyboard.hide()
	keyboard.enabled = false
	place_in_front()

func place_in_front() -> void:
	if camera == null:
		return
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_position = camera.global_position + forward * 2.1
	look_at(global_position + forward, Vector3.UP)

func set_open(open: bool) -> void:
	visible = open
	if screen != null:
		screen.enabled = open and input_active
		screen.input_keyboard = open and input_active
	if open:
		place_in_front()
	else:
		cancel_interaction()
		keyboard.enabled = false
		keyboard.hide()

func set_input_active(value: bool) -> void:
	if input_active==value:return
	input_active=value
	if not value:cancel_interaction()
	if screen!=null:
		screen.enabled=visible and value
		screen.input_keyboard=visible and value

func cancel_interaction() -> void:
	if screen==null:return
	var viewport: Viewport=screen.get_node("Viewport")
	Choice.close_all(viewport)
	for page in get_tree().get_nodes_in_group(PageScroll.GROUP):
		if page.get_viewport()==viewport:page.cancel()
	# Release any pressed control before disabling the physical pointing surface.
	var enabled_buttons: Array[BaseButton]=[]
	for control in ui.find_children("*","BaseButton",true,false):
		if not control.disabled:enabled_buttons.append(control);control.disabled=true
	var surface: Node3D=screen.get_node("StaticBody3D")
	for pointer in hovered_pointers.keys():
		if not is_instance_valid(pointer):continue
		var pixel: Vector2=hovered_pointers[pointer]
		var local:=Vector3((pixel.x/screen.viewport_size.x-.5)*screen.screen_size.x,(.5-pixel.y/screen.viewport_size.y)*screen.screen_size.y,0)
		var point: Vector3=surface.get_node("CollisionShape3D").global_transform*local
		XRToolsPointerEvent.released(pointer,surface,point)
		XRToolsPointerEvent.exited(pointer,surface,point)
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT
	release.position=pointer_position;release.global_position=pointer_position
	viewport.push_input(release,true);viewport.gui_release_focus()
	for control in enabled_buttons:control.disabled=false
	hovered_pointers.clear()
	if keyboard!=null:keyboard.enabled=false;keyboard.hide()

func _pointer_event(event: XRToolsPointerEvent) -> void:
	if not visible or not input_active:return
	if event.event_type==XRToolsPointerEvent.Type.EXITED:
		hovered_pointers.erase(event.pointer);return
	pointer_position=screen.get_node("StaticBody3D").global_to_viewport(event.position)
	hovered_pointers[event.pointer]=pointer_position

func scroll_pointer(point: Vector2,axis: float,delta: float) -> bool:
	if not visible or not input_active:return false
	return PageScroll.scroll_at(screen.get_node("Viewport"),point,axis,delta)

func _process(delta: float) -> void:
	if screen == null or not visible or not input_active:
		return
	var focus: Control = screen.get_node("Viewport").gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	keyboard.visible = typing
	keyboard.enabled = typing

	if XRServer.primary_interface!=null and XRServer.primary_interface.is_initialized():
		var head=XRServer.get_tracker("head")
		var pose: XRPose=head.get_pose("default") if head!=null else null
		if pose==null or not pose.has_tracking_data:cancel_interaction();return
	var strongest:=0.0
	var point:=pointer_position
	for pointer in hovered_pointers.keys():
		if not is_instance_valid(pointer):hovered_pointers.erase(pointer);continue
		var controller: Node=pointer
		while controller!=null and not controller is XRController3D:controller=controller.get_parent()
		if controller==null:continue # Nontracked pointer fixtures do not poll devices.
		if not preload("res://scripts/tracked_hand_input.gd").controller_tracked(controller):
			cancel_interaction();return
		var axis:float=-controller.get_vector2("primary").y
		if absf(axis)>absf(strongest):strongest=axis;point=hovered_pointers[pointer]
	if not hovered_pointers.is_empty():scroll_pointer(point,strongest,delta)
