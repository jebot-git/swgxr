extends Node
## Applies only to the headset viewport. UI and observer targets stay full rate.
const Policy=preload("res://graphics/foveation.gd")
var masks=preload("res://graphics/gaze_vrs.gd").new()
var viewport:Viewport
var origin:XROrigin3D
var gaze:XRController3D
var preferences:RefCounted
var xr:XRInterface
var state:Dictionary={}
var capability_key:=""
var poll:=0.0

func configure(target:Viewport,rig:XROrigin3D,settings:RefCounted)->void:
	viewport=target;origin=rig;preferences=settings
	xr=XRServer.find_interface("OpenXR")
	gaze=XRController3D.new();gaze.name="FoveationGaze"
	gaze.tracker="/user/eyes_ext";gaze.pose="eye_gaze_pose";origin.add_child(gaze)
	if xr!=null and xr.has_signal("session_begun"):xr.connect("session_begun",apply_preferences)
	apply_preferences()

func capabilities()->String:
	return Policy.mode(xr)+str(xr.is_foveation_supported() if xr!=null and xr.is_initialized() else false)

func apply_preferences()->void:
	if not is_instance_valid(viewport) or preferences==null:return
	capability_key=capabilities()
	masks.attached=false
	RenderingServer.viewport_set_vrs_texture(viewport.get_viewport_rid(),RID())
	state=Policy.apply(viewport,xr,preferences.foveation_level,preferences.fovea_size)
	# The generic gaze path must never briefly use the engine's different gaze map.
	if state.mode=="gaze" and not state.runtime_profile:
		viewport.vrs_mode=Viewport.VRS_DISABLED
		update_gaze()
	state.vrs_mode=viewport.vrs_mode
	state.generic_gaze_supported=masks.supported(xr)
	print("XR_FOVEATION ",JSON.stringify(state))

func update_gaze()->void:
	if xr==null:return
	var focused:bool=xr.is_initialized() and xr.get_session_state()==OpenXRInterface.SESSION_STATE_FOCUSED
	masks.update(viewport,xr,origin,gaze,focused,preferences.fovea_size)

func _process(delta:float)->void:
	if not is_instance_valid(viewport):return
	poll+=delta
	if poll>=0.5:
		poll=0.0
		if capabilities()!=capability_key:apply_preferences()
	if state.get("mode","")=="gaze" and not state.get("runtime_profile",false):update_gaze()

func _exit_tree()->void:
	if is_instance_valid(gaze):gaze.queue_free()
