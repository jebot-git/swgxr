extends RefCounted
## Shared UI aim. Finger animation and optical finger joints never steer the cursor.
## Keep the same OpenXR aim (or XR Tools grip fallback) on every UI surface.
static func pose(_avatar: Node3D, _side: String, rig: XROrigin3D=null, controller: XRController3D=null) -> Dictionary:
	if not is_instance_valid(controller):return {}
	var target:=controller.global_transform*XRTools.get_aim_offset(XRTools.HandOffsetMode.HAND_OFFSET_AUTO,controller)
	var source:="controller_grip"
	var tracker:=XRServer.get_tracker(controller.tracker) as XRPositionalTracker
	var aim: XRPose=tracker.get_pose("aim") if tracker!=null else null
	if aim!=null and aim.has_tracking_data and is_instance_valid(rig):
		target=rig.global_transform*aim.get_adjusted_transform()
		source="controller_aim"
	return {"tip":target.origin,"ray_origin":target.origin,"direction":-target.basis.z.normalized(),"source":source}
