extends Node3D
## Original client UI on XR Tools pointable surfaces, with a holographic keyboard.
const Surface = preload("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn")
const KeyboardContent = preload("res://ui/virtual_keyboard.gd")
var keyboard_content:Control
var screen: XRToolsViewport2DIn3D
var keyboard: XRToolsViewport2DIn3D
var ui: Control
var camera: XRCamera3D
var input_active := true
var reference_frame:Node3D
var reference_pose:=Transform3D.IDENTITY
func set_reference_frame(frame:Node3D)->void:
	if reference_frame==frame:return
	reference_frame=frame
	if visible:place_in_front()
func follow_reference_frame()->void:
	if is_instance_valid(reference_frame):global_transform=reference_frame.global_transform*reference_pose
var hovered_pointers: Dictionary = {}
var pointer_position := Vector2.ZERO
var slider_surface:Dictionary={}
var slider_drags:Dictionary={}
var slider_capture_hand:=""
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
	keyboard.screen_size = Vector2(1.8, 0.6)
	keyboard.viewport_size = Vector2(1200, 400)
	keyboard.unshaded = true
	keyboard.name = "TextKeyboard"
	keyboard.collision_layer = (1 << 20) | (1 << 22)
	keyboard.position = Vector3(0, -1.15, 0.3)
	keyboard.rotation_degrees.x = -20.0
	# Virtual keys go directly to this menu viewport; the gameplay viewport
	# never receives typing events. XR Tools still forwards physical keyboard input.
	add_child(keyboard)
	keyboard.viewport_size = Vector2(1200, 400)
	keyboard_content=KeyboardContent.new();keyboard.get_node("Viewport").add_child(keyboard_content)
	keyboard_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyboard_content.target_viewport=screen.get_node("Viewport")
	keyboard_content.dismissed.connect(func():screen.get_node("Viewport").gui_release_focus())
	keyboard.hide()
	keyboard.enabled = false
	place_in_front()

func place_in_front() -> void:
	if camera == null:
		return
	var forward := -camera.global_basis.z
	if not is_instance_valid(reference_frame):forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_position = camera.global_position + forward * 2.1
	look_at(global_position + forward, camera.global_basis.y if is_instance_valid(reference_frame) else Vector3.UP)
	if is_instance_valid(reference_frame):reference_pose=reference_frame.global_transform.affine_inverse()*global_transform

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
		keyboard_content.reset_modifiers()

func set_input_active(value: bool) -> void:
	if input_active==value:return
	input_active=value
	if not value:cancel_interaction()
	if screen!=null:
		screen.enabled=visible and value
		screen.input_keyboard=visible and value

func cancel_interaction() -> void:
	for drag in slider_drags.values():drag.cancel()
	slider_capture_hand=""
	if screen==null:return
	screen.enabled=visible and input_active
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

func slider_surfaces()->Array:
	if slider_surface.is_empty():slider_surface={"mesh":screen.get_node("Screen"),"meters":screen.screen_size,"viewport":screen.get_node("Viewport"),"control":ui}
	return [slider_surface]

func physical_slider_frame(side:String,pose:Transform3D,grip:float,tracked:bool)->bool:
	if not slider_drags.has(side):slider_drags[side]=preload("res://scripts/xr_slider_drag.gd").new()
	var drag=slider_drags[side]
	var consumed:bool=drag.frame(slider_surfaces(),{},pose,grip,0,tracked and visible and input_active and (slider_capture_hand.is_empty() or slider_capture_hand==side))
	if not drag.capture.is_empty():slider_capture_hand=side
	elif slider_capture_hand==side:slider_capture_hand=""
	# Retain the pinned XRTools normal trigger path whenever no physical hand
	# owns a slider. While gripped its pointable collision cannot steal the drag.
	screen.enabled=visible and input_active and slider_capture_hand.is_empty()
	preload("res://scripts/xr_slider_drag.gd").sync_handles(slider_surfaces())
	return consumed

func _process(delta: float) -> void:
	if visible:follow_reference_frame()
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
	var slider_consumed:=false
	for side in ["LeftHand","RightHand"]:
		var hand:XRController3D=camera.get_parent().get_node_or_null(side)
		if hand!=null:slider_consumed=physical_slider_frame(side,hand.global_transform,hand.get_float("grip"),preload("res://scripts/tracked_hand_input.gd").controller_tracked(hand)) or slider_consumed
	if slider_consumed:return
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
