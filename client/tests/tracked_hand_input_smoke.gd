extends SceneTree
const HandInput = preload("res://scripts/tracked_hand_input.gd")
var failures: Array = []
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var controller_tracker := XRControllerTracker.new()
	controller_tracker.name = "left_hand"
	controller_tracker.type = XRServer.TRACKER_CONTROLLER
	controller_tracker.set_pose("grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(controller_tracker)
	var controller := XRController3D.new()
	controller.tracker = "left_hand"
	controller.pose = "grip"
	var origin := XROrigin3D.new()
	root.add_child(origin)
	origin.add_child(controller)
	await process_frame
	for name in ["primary_touch", "secondary_touch", "ax_touch", "by_touch", "thumbrest_touch", "trigger_touch"]:
		controller_tracker.set_input(name, false)
	controller_tracker.set_input("grip", 1.0)
	controller_tracker.set_input("trigger", 0.0)
	await process_frame
	var point := HandInput.controller_state(controller)
	check(point.grip == 1.0 and point.trigger == 0 and not point.thumb_touch, "Point/thumbs-up controller inputs lost")
	controller_tracker.set_input("thumbrest_touch", true)
	controller_tracker.set_input("trigger_touch", true)
	await process_frame
	var touching := HandInput.controller_state(controller)
	check(touching.thumb_touch and touching.trigger_touch, "Touch controller thumbrest/index inputs lost")
	var tracker := XRHandTracker.new()
	tracker.name = "/user/hand_tracker/left"
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	XRServer.add_tracker(tracker)
	var wrist := Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 2, 3))
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, wrist)
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	for key in HandInput.JOINTS:
		var index: int = HandInput.JOINTS[key]
		tracker.set_hand_joint_transform(index, wrist * Transform3D(Basis.IDENTITY, Vector3(index * 0.01, 0.02, 0.03)))
		tracker.set_hand_joint_flags(index, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	var data := HandInput.tracked_joints("left")
	check(not data.is_empty() and data.source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, "Controller-derived skeletal source rejected")
	check(data.joints.index_proximal.distance_to(Vector3(0.07, 0.02, 0.03)) < 0.00001, "Skeletal joint coordinates not wrist-relative")
	tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, 0)
	check(HandInput.tracked_joints("left").is_empty(), "Invalid joints did not select controller fallback")
	tracker.has_tracking_data = false
	check(HandInput.tracked_joints("left").is_empty(), "Tracking loss kept stale finger skeleton")
	controller_tracker.invalidate_pose("grip")
	await process_frame
	check(HandInput.controller_state(controller).grip == 0, "Controller tracking loss kept stale grip")
	origin.free()
	XRServer.remove_tracker(tracker)
	XRServer.remove_tracker(controller_tracker)
	var report := {"test":"openxr_hand_input", "hardware_tested":false, "passed":failures.is_empty(), "errors":failures}
	FileAccess.open("res://../runtime/evidence/tracked-hand-input-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
