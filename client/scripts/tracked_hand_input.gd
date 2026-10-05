extends RefCounted
## Runtime-neutral controller poses and XR_EXT_hand_tracking joint input.
const JOINTS := {
	"thumb_metacarpal": XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
	"thumb_proximal": XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL,
	"thumb_distal": XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL,
	"thumb_tip": XRHandTracker.HAND_JOINT_THUMB_TIP,
	"index_metacarpal": XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL,
	"index_proximal": XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL,
	"index_intermediate": XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE,
	"index_distal": XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL,
	"index_tip": XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
	"ring_metacarpal": XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL,
	"ring_proximal": XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL,
	"ring_intermediate": XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE,
	"ring_distal": XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL,
	"ring_tip": XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
}

static func controller_tracked(controller: XRController3D) -> bool:
	var tracker = XRServer.get_tracker(controller.tracker)
	var pose: XRPose = tracker.get_pose(controller.pose) if tracker != null else null
	return pose != null and pose.has_tracking_data

static func controller_state(controller: XRController3D) -> Dictionary:
	if not controller_tracked(controller):
		return {"grip":0.0, "trigger":0.0, "thumb_touch":false, "trigger_touch":false}
	var thumb_touch := false
	for action in ["primary_touch", "secondary_touch", "ax_touch", "by_touch", "thumbrest_touch"]:
		thumb_touch = thumb_touch or controller.is_button_pressed(action)
	return {"grip":clampf(controller.get_float("grip"), 0, 1),
		"trigger":clampf(controller.get_float("trigger"), 0, 1),
		"thumb_touch":thumb_touch, "trigger_touch":controller.is_button_pressed("trigger_touch")}

static func tracked_joints(side: String) -> Dictionary:
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + side) as XRHandTracker
	if tracker == null or not tracker.has_tracking_data or tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED:
		return {}
	if not (tracker.get_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
		return {}
	var wrist := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST)
	if not wrist.origin.is_finite() or not wrist.basis.is_finite() or absf(wrist.basis.determinant()) < 0.0001:
		return {}
	var inverse := wrist.affine_inverse()
	var joints := {}
	for key in JOINTS:
		var index: int = JOINTS[key]
		if not (tracker.get_hand_joint_flags(index) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID):
			return {}
		var position := inverse * tracker.get_hand_joint_transform(index).origin
		if not position.is_finite():
			return {}
		joints[key] = position
	# Godot stores all hand joints in play space. Derive a standard grip frame
	# so optical tracking can also drive the arm when there is no controller.
	var index := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL).origin
	var ring := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL).origin
	var z := (ring - index).normalized()
	var y := (wrist.origin - (index + ring) * 0.5).slide(z).normalized()
	if z.length_squared() < 0.5 or y.length_squared() < 0.5:
		return {}
	var x := y.cross(z).normalized()
	var pose := XRPose.new()
	pose.transform = Transform3D(Basis(x, z.cross(x), z), wrist.origin.lerp((index + ring) * 0.5, 0.55))
	var wrist_pose := XRPose.new()
	wrist_pose.transform = wrist
	return {"joints":joints, "source":tracker.hand_tracking_source, "grip":pose.get_adjusted_transform(), "wrist":wrist_pose.get_adjusted_transform()}
