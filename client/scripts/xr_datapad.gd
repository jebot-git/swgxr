extends Node3D
## Floating datapad and wrist minimap; native math owns follow and finger hits.
signal factory_blueprint_draw_requested(entry:Dictionary, hand_pose:Transform3D)
signal harvester_draw_requested(entry:Dictionary, hand_pose:Transform3D)
signal vendor_draw_requested(entry:Dictionary, hand_pose:Transform3D)
signal parcel_draw_requested(entry:Dictionary, hand_pose:Transform3D)
signal opened
signal new_waypoint_requested(position: Vector3, label: String)
signal delete_entry_requested(entry: Dictionary)
const UI = preload("res://scripts/datapad_ui.gd")
const HandInput = preload("res://scripts/tracked_hand_input.gd")
const WristRadar = preload("res://scripts/wrist_radar.gd")
const MINIMAP_TOUCH_MARGIN:=0.05
const MINIMAP_TOUCH_DEPTH:=0.06
var radar: Node3D
var radar_contacts_provider: Callable
var radar_eligible := false
var radar_requested := false
var pointer_visual:Node3D
var summary_ui:Control
var ui: Control
var rig: XROrigin3D
var body: CharacterBody3D
var avatar: Node3D
var offhand := "left"
var allowed := false
var is_open := false
var hold_time := 0.0
var gesture_reserved := false
var gesture_release_required := false
var released_trigger := false
var pressed := false
var capture: Dictionary = {}
var aim_latch: Dictionary = {}
var last_hover: Dictionary = {}
var surfaces: Array[Dictionary] = []
var follower := SwgWristDatapad.new()
var pointer_saved: Dictionary = {}
var stick_captured := false
var hover_surface := -1
var dot: MeshInstance3D
var last_pixel := Vector2.ZERO
var parcel_drag:Dictionary={}
var parcel_grip_armed:=false
var navigation_repeat:=0.0
var slider_dragger=preload("res://scripts/xr_slider_drag.gd").new()

func configure(origin: XROrigin3D, player: CharacterBody3D, side := "left") -> void:
	rig = origin
	body = player
	offhand = "right" if side == "right" else "left"
	process_priority = 120 # Read the final tracked avatar pose after its animation/IK.
	ui = UI.new()
	add_surface(ui,Vector2i(900,900),Vector2(0.36,0.36))
	add_surface(ui.take_detail_panel(),Vector2i(550,625),Vector2(0.22,0.25))
	summary_ui=preload("res://scripts/player_summary_ui.gd").new()
	add_surface(summary_ui,Vector2i(550,625),Vector2(.22,.25))
	ui.configure(load_catalog(),ProjectSettings.globalize_path("res://../runtime/assets/datapad"))
	ui.new_waypoint_requested.connect(func(point: Vector3,label: String): new_waypoint_requested.emit(point,label))
	ui.delete_entry_requested.connect(func(entry: Dictionary): delete_entry_requested.emit(entry))
	ui.map_expansion_requested.connect(resize_map)
	ui.close_requested.connect(func():set_open(false))
	resize_map(false)
	dot = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.0025
	sphere.height = 0.005
	dot.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("baffff")
	dot.material_override = material
	add_child(dot)
	dot.visible = false
	radar = WristRadar.new()
	add_child(radar)
	radar.configure()
	pointer_visual=preload("res://scripts/finger_pointer_visual.gd").new();add_child(pointer_visual)
	sync_presentation()

func load_catalog() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://../runtime/assets/datapad/catalog.json")
	if not FileAccess.file_exists(path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func add_surface(control: Control, pixels: Vector2i, meters: Vector2) -> void:
	var viewport := SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = false
	viewport.gui_embed_subwindows = true # Profession selector stays on the wrist screen.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(control)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = meters
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.material_override = material
	add_child(mesh)
	surfaces.append({"viewport":viewport,"mesh":mesh,"control":control,"meters":meters})

func resize_map(expanded: bool) -> void:
	cancel_press()
	var meters := Vector2(0.70,0.70) if expanded else Vector2(0.36,0.36)
	var pixels := Vector2i(1260,1260) if expanded else Vector2i(900,900)
	surfaces[0].meters = meters
	surfaces[0].viewport.size = pixels
	surfaces[0].mesh.mesh.size = meters
	surfaces[0].mesh.rotation=Vector3.ZERO
	# Center the whole interface ahead of the viewer, including the side panes.
	surfaces[0].mesh.position.y = 0
	surfaces[1].mesh.position = Vector3(meters.x*0.5+0.12, 0, 0.025)
	surfaces[1].mesh.rotation.y = deg_to_rad(-25)
	if surfaces.size()>2:
		surfaces[2].mesh.position=Vector3(-meters.x*.5-.12,0,.025)
		surfaces[2].mesh.rotation.y=deg_to_rad(25)

func set_gesture_reserved(value: bool) -> void:
	gesture_reserved = value
	if value:
		gesture_release_required = true
		hold_time = 0.0
		radar_requested=false
		set_open(false)
		sync_presentation()

func set_allowed(value: bool) -> void:
	if allowed == value: return
	allowed = value
	if not allowed:
		hold_time = 0.0
		radar_requested=false
		set_open(false)
	sync_presentation()

func set_open(value: bool) -> void:
	if is_open == value: return
	is_open = value
	sync_presentation()
	if value:
		released_trigger = false
		follower.reset()
		# Inventory/crafting/installation panels reuse input plumbing but retain
		# their own placement and layouts.
		if ui is UI:update_view_follow(rig.get_node("XRCamera3D").global_transform,0)
		for side in ["LeftHand","RightHand"]:
			var pointer = rig.get_node_or_null(side+"/FunctionPointer")
			if pointer != null:
				pointer_saved[pointer] = pointer.enabled
				pointer.enabled = false
		opened.emit()
	else:
		cancel_press()
		clear_hover()
		for pointer in pointer_saved:
			if is_instance_valid(pointer): pointer.enabled = pointer_saved[pointer]
		pointer_saved.clear()
		if is_instance_valid(dot): dot.visible = false

func sync_presentation() -> void:
	var mode := SubViewport.UPDATE_WHEN_VISIBLE if is_open else SubViewport.UPDATE_DISABLED
	for surface: Dictionary in surfaces:
		if surface.mesh.visible != is_open: surface.mesh.visible = is_open
		if surface.viewport.render_target_update_mode != mode: surface.viewport.render_target_update_mode = mode
	if is_instance_valid(radar): radar.set_active(allowed and radar_eligible and radar_requested and not is_open)
	if is_instance_valid(pointer_visual) and not is_open:pointer_visual.hide()
	var presentation_visible: bool = is_open or (is_instance_valid(radar) and radar.active)
	if visible != presentation_visible: visible = presentation_visible

func update_tracking_state(head_tracked: bool, mount_tracked: bool, pointing_tracked: bool, grip: float, trigger: float, delta: float) -> void:
	if not head_tracked:set_open(false)
	radar_eligible = head_tracked and mount_tracked
	update_activation(allowed and radar_eligible,grip,trigger,delta)
	sync_presentation()

func _process(delta: float) -> void:
	if not is_instance_valid(rig):
		radar_eligible = false
		sync_presentation()
		return
	var mount_controller: XRController3D = rig.get_node("LeftHand" if offhand == "left" else "RightHand")
	var hand: XRController3D = rig.get_node("RightHand" if offhand == "left" else "LeftHand")
	var head_tracker = XRServer.get_tracker("head")
	var head_pose: XRPose = head_tracker.get_pose("default") if head_tracker != null else null
	var head_tracked := head_pose != null and head_pose.has_tracking_data
	var mount_tracked := HandInput.controller_tracked(mount_controller)
	var pointing_tracked := HandInput.controller_tracked(hand)
	var tracked := head_tracked and pointing_tracked
	var grip := mount_controller.get_float("grip") if head_tracked and mount_tracked else 0.0
	var trigger := mount_controller.get_float("trigger") if head_tracked and mount_tracked else 0.0
	update_tracking_state(head_tracked,mount_tracked,pointing_tracked,grip,trigger,delta)
	var stick := hand.get_vector2("primary") if tracked else Vector2.ZERO
	var camera: Camera3D = rig.get_node("XRCamera3D")
	if is_open and head_tracked:
		update_view_follow(camera.global_transform,delta)
	elif radar.active:
		var mount := wrist_mount(mount_controller)
		var followed: Dictionary = follower.follow(mount,camera.global_position,delta)
		if followed.get("valid",false): global_transform = followed.transform
	if radar.active:
		var center: Vector3 = body.global_position if is_instance_valid(body) else camera.global_position
		radar.tick(delta,center,-camera.global_basis.z,radar_contacts_provider)
		if pointing_tracked:touch_minimap(pointing_pose(hand))
	if not is_open:
		update_stick_capture(stick,{},delta)
		return
	if not tracked:
		cancel_press();clear_hover();pointer_visual.hide();dot.hide()
		update_stick_capture(Vector2.ZERO,{},delta)
		return
	var finger := pointing_pose(hand)
	var hit := find_hit(finger)
	pointer_visual.update_pointer(finger.get("tip",hand.global_position),hit)
	if slider_frame(hit,hand.global_transform,hand.get_float("grip"),hand.get_float("trigger"),tracked):return
	update_parcel_drag(hit,hand.global_transform,hand.get_float("grip"),tracked)
	if not is_open:return
	update_pointer(hit,hand.get_float("trigger"))
	update_stick_capture(stick,hit,delta)

func update_parcel_drag(hit:Dictionary,hand_pose:Transform3D,grip:float,tracked:bool)->void:
	if not tracked or not is_open:
		parcel_drag={};parcel_grip_armed=false;return
	if grip<.35:
		parcel_grip_armed=true;parcel_drag={};return
	if not parcel_drag.is_empty():
		if hand_pose.origin.distance_to(parcel_drag.anchor)>=.06:
			var entry:Dictionary=parcel_drag.entry;parcel_drag={}
			if entry.get("type","") in ["harvesting_deed","factory_deed"]:harvester_draw_requested.emit(entry,hand_pose)
			elif entry.get("type","")=="manufacturing_blueprint":factory_blueprint_draw_requested.emit(entry,hand_pose)
			elif entry.get("type","")=="vendor":vendor_draw_requested.emit(entry,hand_pose)
			else:parcel_draw_requested.emit(entry,hand_pose)
		return
	if not parcel_grip_armed or grip<.65:return
	parcel_grip_armed=false
	var candidate:=hit if not hit.is_empty() else last_hover
	if candidate.is_empty() or int(candidate.get("surface",-1))!=0:return
	var entry:Dictionary=ui.draggable_entry_at(candidate.pixel)
	if not entry.is_empty():parcel_drag={"entry":entry,"anchor":hand_pose.origin}

func update_stick_capture(stick: Vector2, hit: Dictionary, delta: float) -> void:
	if not slider_dragger.capture.is_empty():
		stick_captured=stick.length()>.15;apply_capture();return
	navigation_repeat=maxf(0,navigation_repeat-delta)
	if stick.length() < 0.15: stick_captured = false;navigation_repeat=0
	if is_open and not hit.is_empty() and stick.length() > 0.2:
		stick_captured = true
		if preload("res://scripts/frontend_choice.gd").scroll_active(surfaces[int(hit.surface)].viewport,-stick.y,delta):
			apply_capture();return
		if int(hit.surface) == 0:
			var steps:=(-1 if stick.y>0 else 1) if absf(stick.y)>.5 and navigation_repeat<=0 else 0
			if ui.navigate_at(hit.pixel,steps):
				if steps!=0:navigation_repeat=.18
			else:ui.scroll_at(hit.pixel,Vector2(stick.x,-stick.y)*delta*650.0)
		elif int(hit.surface)==2:
			summary_ui.scroll.scroll_vertical-=int(stick.y*delta*650.0)
		else:
			ui.detail_description.get_v_scroll_bar().value -= stick.y*delta*650.0
	apply_capture()

func update_activation(tracked_allowed: bool, grip: float, trigger: float, delta: float) -> void:
	if grip < 0.45 or trigger < 0.45:
		gesture_release_required = false
	if gesture_reserved or gesture_release_required:
		hold_time = 0.0
		radar_requested=false
		set_open(false)
		sync_presentation()
		return
	if not tracked_allowed or grip < 0.45 or trigger < 0.45:
		hold_time = 0.0
		radar_requested=false
	elif grip >= 0.65 and trigger >= 0.65:
		hold_time += delta
		if hold_time >= 0.25:radar_requested=true
	sync_presentation()

func update_view_follow(head:Transform3D,delta:float)->void:
	var main_size:Vector2=surfaces[0].meters
	var distance:=.95 if ui.expanded else .75
	var frozen:bool=pressed or not parcel_drag.is_empty() or not slider_dragger.capture.is_empty()
	var result:Dictionary=follower.follow_view(head,Vector2(main_size.x+.46,main_size.y),delta,distance,frozen)
	if result.get("valid",false):
		global_transform=result.transform
		orient_expanded_panels(result.anchor)

func touch_minimap(finger:Dictionary)->bool:
	if not allowed or not radar.active or finger.is_empty():return false
	var hit:Dictionary=follower.point(radar.display.global_transform,Vector2.ONE*(radar.DIAMETER_METERS+MINIMAP_TOUCH_MARGIN*2),Vector2.ONE*radar.PIXELS,finger.tip,finger.direction,0.0,MINIMAP_TOUCH_DEPTH)
	if not hit.get("valid",false) or not hit.get("touching",false):return false
	var local:Vector3=radar.display.to_local(finger.tip)
	set_open(true)
	if radar.unread_mail>0 and local.x>radar.DIAMETER_METERS*.20 and local.y< -radar.DIAMETER_METERS*.20:ui.mail_requested.emit()
	return true

func orient_expanded_panels(viewer:Vector3)->void:
	if not is_open or not ui.expanded:return
	for surface:Dictionary in surfaces:
		if surface.mesh.global_position.distance_squared_to(viewer)>.001:surface.mesh.look_at(viewer,Vector3.UP,true)

func apply_capture() -> void:
	if is_instance_valid(body):
		# Retain capture of the pointing hand stick until it returns to neutral.
		body.set_interface_capture(stick_captured and offhand == "right",stick_captured and offhand == "left")

func wrist_mount(controller: XRController3D) -> Transform3D:
	var grip := controller.global_transform.orthonormalized()
	# OpenXR grip +X points out of the left palm, into the right palm.
	var dorsal := grip.basis.x * (-1.0 if offhand == "left" else 1.0)
	# The display rises vertically from the wrist like a projected terminal.
	# Its base orientation follows the rig's horizontal heading, not palm roll.
	var up := Vector3.UP
	var facing := rig.global_basis.z.slide(up).normalized()
	if facing.length_squared() < 0.5: facing = Vector3.BACK
	var origin := grip.origin+grip.basis.y*0.09
	if is_instance_valid(avatar) and is_instance_valid(avatar.skeleton):
		var skeleton: Skeleton3D = avatar.skeleton
		var bone := skeleton.find_bone("lwrist" if offhand == "left" else "rwrist")
		if bone >= 0: origin = (skeleton.global_transform*skeleton.get_bone_global_pose(bone)).origin
	return Transform3D(Basis(up.cross(facing),up,facing),origin+dorsal*0.035)

func pointing_pose(controller: XRController3D) -> Dictionary:
	return preload("res://scripts/rendered_finger_pointer.gd").pose(avatar,"right" if offhand=="left" else "left",rig,controller)

func find_hit(finger: Dictionary) -> Dictionary:
	if finger.is_empty(): return {}
	var best: Dictionary = {}
	for index in range(surfaces.size()):
		var surface: Dictionary = surfaces[index]
		var hit: Dictionary = follower.point(surface.mesh.global_transform,surface.meters,Vector2(surface.viewport.size),finger.get("ray_origin",finger.tip),finger.direction,1.4)
		if hit.get("valid",false) and (best.is_empty() or float(hit.distance)<float(best.distance)):
			hit.surface = index
			best = hit
	return best

func slider_frame(hit:Dictionary,pose:Transform3D,grip:float,trigger:float,tracked:bool)->bool:
	var consumed:bool=slider_dragger.frame(surfaces,hit,pose,grip,trigger,tracked and allowed and is_open and not pressed)
	slider_dragger.sync_handles(surfaces)
	if consumed:
		released_trigger=false;aim_latch={};last_hover={};parcel_drag={};parcel_grip_armed=false
		if is_instance_valid(dot):dot.hide()
	return consumed

func update_pointer(hit: Dictionary, trigger: float) -> void:
	if trigger < 0.1:
		aim_latch = {}
		last_hover = hit.duplicate()
	else:last_hover=hit.duplicate()
	if trigger < 0.35: released_trigger = true
	if pressed:
		# Keep sending captured motion to the owning viewport so map, list and
		# description drag scrolling share the same input as desktop pointers.
		var same_surface:bool=not hit.is_empty() and hit.surface==capture.surface
		var dropdown:bool=preload("res://scripts/frontend_choice.gd").active(surfaces[int(capture.surface)].viewport)
		var pixel:Vector2=hit.pixel if same_surface else Vector2(-100,-100) if dropdown else capture.pixel
		var drag:=InputEventMouseMotion.new();drag.position=pixel;drag.global_position=pixel;drag.relative=pixel-capture.pixel;drag.button_mask=MOUSE_BUTTON_MASK_LEFT
		surfaces[int(capture.surface)].viewport.push_input(drag,true)
		capture.pixel=pixel
		if trigger < 0.35:
			send_button(capture,false)
			pressed = false
			capture = {}
		return
	if hit.is_empty():
		clear_hover()
		dot.visible = false
		return
	var index := int(hit.surface)
	if hover_surface != index:
		clear_hover()
		hover_surface = index
		surfaces[index].viewport.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = hit.pixel
	motion.global_position = hit.pixel
	motion.relative = hit.pixel-last_pixel
	surfaces[index].viewport.push_input(motion,true)
	last_pixel = hit.pixel
	dot.visible = true
	dot.global_position = hit.world+surfaces[index].mesh.global_basis.z*0.001
	if released_trigger and trigger >= 0.55:
		capture = hit.duplicate()
		if int(capture.surface)==0 and not preload("res://scripts/frontend_choice.gd").active(surfaces[0].viewport) and ui.has_method("navigation_target"):capture.pixel=ui.navigation_target(capture.pixel)
		pressed = true
		released_trigger = false
		send_button(capture,true)

func send_button(hit: Dictionary, down: bool) -> void:
	if hit.is_empty(): return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = hit.pixel
	event.global_position = hit.pixel
	surfaces[int(hit.surface)].viewport.push_input(event,true)

func clear_hover() -> void:
	if hover_surface >= 0:
		surfaces[hover_surface].viewport.notify_mouse_exited()
		hover_surface = -1

func cancel_press() -> void:
	for surface:Dictionary in surfaces:preload("res://scripts/frontend_choice.gd").close_all(surface.viewport)
	slider_dragger.cancel()
	if pressed:
		# A close/tracking loss cancels the click rather than activating on release.
		var hit := capture.duplicate()
		hit.pixel = Vector2(-100,-100)
		var viewport: SubViewport = surfaces[int(hit.surface)].viewport
		var scroll:=viewport.get_node_or_null("UniversalDragScroll")
		if scroll!=null:scroll.cancel()
		var motion := InputEventMouseMotion.new()
		motion.position = hit.pixel
		motion.global_position = hit.pixel
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion,true)
		viewport.notify_mouse_exited()
		hover_surface = -1
		send_button(hit,false)
	pressed = false
	capture = {}
	parcel_drag={};parcel_grip_armed=false
	aim_latch = {}
	last_hover = {}

func _exit_tree() -> void:
	set_open(false)
	if is_instance_valid(body): body.set_interface_capture(false,false)
