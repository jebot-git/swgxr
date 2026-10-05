extends Node3D
## Palm-facing underside wrist controls. No grip binding or tracking mutation.
signal channel_requested(channel: String)
signal mode_requested(mode: String)
signal ptt_changed(held: bool)
const VoicePanel=preload("res://scripts/voice_panel.gd")
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const METERS:=Vector2(0.23,0.115)
const PIXELS:=Vector2i(640,320)
var rig: XROrigin3D
var avatar: Node3D
var offhand:="left"
var panel: PanelContainer
var viewport: SubViewport
var surface: MeshInstance3D
var allowed:=false
var interactive:=true
var tracking_valid:=false
var hovered:=false
var trigger_armed:=false
var captured:=""
var ptt_down:=false
var state: Dictionary={}
var point_math:=SwgWristDatapad.new()
var mount_frame:=preload("res://scripts/forearm_mount.gd").new()
var pointer_visual: Node3D
var extended_hover: Dictionary={}
var cursor: MeshInstance3D
func configure(origin: XROrigin3D, side: String="left") -> void:
	rig=origin;set_offhand(side);process_priority=40 # Before ranged interactions (50).
	RenderingServer.frame_pre_draw.connect(sync_mount)
	viewport=SubViewport.new();viewport.size=PIXELS;viewport.transparent_bg=true;viewport.disable_3d=true
	viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(viewport)
	panel=VoicePanel.new();viewport.add_child(panel)
	panel.channel_requested.connect(func(channel):channel_requested.emit(channel))
	panel.mode_requested.connect(func(mode):mode_requested.emit(mode))
	surface=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=METERS;surface.mesh=quad
	surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_texture=viewport.get_texture()
	material.cull_mode=BaseMaterial3D.CULL_BACK;material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.material_override=material;add_child(surface);visible=false
	cursor=MeshInstance3D.new();var dot:=SphereMesh.new();dot.radius=.0025;dot.height=.005;dot.radial_segments=12;dot.rings=6;cursor.mesh=dot
	var cursor_material:=StandardMaterial3D.new();cursor_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_material.albedo_color=Color("dcffff");cursor_material.no_depth_test=true;cursor_material.render_priority=120
	cursor.material_override=cursor_material;cursor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.add_child(cursor);cursor.hide()
func set_offhand(side: String) -> void:
	offhand="right" if side=="right" else "left"
	cancel_pointer()
func apply_state(value: Dictionary) -> void:
	state=value.duplicate(true)
	if is_instance_valid(panel):panel.apply_state(state)
	if state.get("mic_mode","muted")!="ptt":set_ptt(false)
func set_allowed(value: bool, can_interact: bool=true, reason: String="") -> void:
	allowed=value;interactive=can_interact
	if not value or not can_interact:cancel_pointer()
	if is_instance_valid(panel):panel.set_active(value and can_interact,reason)
	if not value:tracking_valid=false
	sync_visible()
func sync_visible() -> void:
	visible=allowed and tracking_valid
	if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if visible else SubViewport.UPDATE_DISABLED
func underside_mount(grip: Transform3D) -> Transform3D:
	var skeleton: Skeleton3D=avatar.get("skeleton") if is_instance_valid(avatar) else null
	return mount_frame.resolve(skeleton,offhand,grip)
func finger_pose(controller: XRController3D) -> Dictionary:
	return preload("res://scripts/rendered_finger_pointer.gd").pose(avatar,"right" if offhand=="left" else "left",rig,controller)

func update_tracking(head: bool, mount: bool, pointing: bool) -> void:
	tracking_valid=head and mount and pointing
	if not tracking_valid:cancel_pointer()
	sync_visible()
func hit_test(tip: Vector3, direction: Vector3) -> Dictionary:
	if not allowed or not interactive or not tracking_valid or tip.distance_to(surface.global_position)>0.32:return {}
	if (tip-surface.global_position).dot(surface.global_basis.z)<-0.005:return {}
	var hit: Dictionary=point_math.point(surface.global_transform,METERS,Vector2(PIXELS),tip,direction)
	return hit if hit.get("valid",false) else {}
func pointer_frame(hit: Dictionary, trigger: float) -> void:
	if not allowed or not interactive or not tracking_valid:cancel_pointer();return
	hovered=not hit.is_empty()
	if is_instance_valid(cursor):
		cursor.visible=hovered
		if hovered:cursor.position=Vector3((float(hit.pixel.x)/PIXELS.x-.5)*METERS.x,(.5-float(hit.pixel.y)/PIXELS.y)*METERS.y,.004)
	var action: String=panel.action_at(hit.pixel) if hovered else ""
	panel.set_hover(action)
	if trigger<0.3:
		trigger_armed=true;captured="";set_ptt(false)
	elif trigger>=0.55 and trigger_armed and not action.is_empty():
		trigger_armed=false;captured=action
		if action=="talk" and state.get("mic_mode")=="ptt":set_ptt(true)
		else:panel.activate(action)
	if captured=="talk" and (action!="talk" or trigger<0.3):set_ptt(false)
func set_ptt(value: bool) -> void:
	if ptt_down==value:return
	ptt_down=value;ptt_changed.emit(value)
func cancel_pointer() -> void:
	if is_instance_valid(pointer_visual):pointer_visual.hide()
	hovered=false;trigger_armed=false;captured="";extended_hover.clear();set_ptt(false)
	if is_instance_valid(cursor):cursor.hide()
	if is_instance_valid(panel):panel.set_hover("")
func blocks_combat() -> bool:
	return allowed and interactive and tracking_valid and (hovered or not captured.is_empty())
func _process(_delta: float) -> void:
	if not allowed or not is_instance_valid(rig):return
	var mount:=rig.get_node_or_null("LeftHand" if offhand=="left" else "RightHand") as XRController3D
	var hand:=rig.get_node_or_null("RightHand" if offhand=="left" else "LeftHand") as XRController3D
	var head=XRServer.get_tracker("head");var head_pose: XRPose=head.get_pose("default") if head!=null else null
	update_tracking(head_pose!=null and head_pose.has_tracking_data,mount!=null and HandInput.controller_tracked(mount),hand!=null and HandInput.controller_tracked(hand))
	if not tracking_valid:return
	global_transform=underside_mount(mount.global_transform)
	var finger:=finger_pose(hand)
	var hit:=hit_test(finger.get("ray_origin",finger.tip),finger.direction)
	if hand.get_float("trigger")<.3:extended_hover=hit.duplicate()
	elif captured.is_empty() and not extended_hover.is_empty():
		# Preserve extended-index target while the analog trigger starts to curl.
		hit=extended_hover.duplicate()
	if not is_instance_valid(pointer_visual):
		pointer_visual=preload("res://scripts/finger_pointer_visual.gd").new();add_child(pointer_visual)
	pointer_visual.update_pointer(finger.tip,hit)
	pointer_frame(hit,hand.get_float("trigger"))

func sync_mount() -> void:
	# Skeleton IK runs after input capture; sample its final forearm before rendering.
	if not allowed or not tracking_valid or not is_instance_valid(rig):return
	var controller:=rig.get_node_or_null("LeftHand" if offhand=="left" else "RightHand") as XRController3D
	if controller!=null:global_transform=underside_mount(controller.global_transform)
	if hovered and is_instance_valid(pointer_visual) and is_instance_valid(cursor):
		var pointing:=rig.get_node_or_null("RightHand" if offhand=="left" else "LeftHand") as XRController3D
		var finger:=finger_pose(pointing)
		if not finger.is_empty():pointer_visual.update_pointer(finger.tip,{"world":cursor.global_position})
func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(sync_mount):RenderingServer.frame_pre_draw.disconnect(sync_mount)
