extends SceneTree
## Original human mesh/skeleton, actual avatar driver and native retargeter;
## only the OpenXR inputs are synthetic. Always run --headless --xr-mode off.
const Avatar = preload("res://scripts/avatar.gd")
const Driver = preload("res://scripts/tracked_avatar.gd")
const HandInput = preload("res://scripts/tracked_hand_input.gd")
var errors: Array[String] = []
var trackers: Array[XRTracker] = []

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func controller(rig: XROrigin3D, side: String) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = side + "_hand"
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(-0.2 if side == "left" else 0.2, 1.2, -0.3)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for action in ["grip", "trigger"]:
		tracker.set_input(action, 1.0)
	tracker.set_input("thumbrest_touch", true)
	XRServer.add_tracker(tracker)
	trackers.append(tracker)
	var node := XRController3D.new()
	node.name = "LeftHand" if side == "left" else "RightHand"
	node.tracker = tracker.name
	node.pose = "grip"
	rig.add_child(node)
	var glove := Node3D.new()
	glove.name = "Hand"
	node.add_child(glove)
	return tracker

func rotations(skeleton: Skeleton3D, prefix: String) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for finger in ["thumb", "index", "ring"]:
		for number in ["01", "02"]:
			result.append(skeleton.get_bone_pose_rotation(skeleton.find_bone(prefix + finger + number)))
	return result

func difference(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var result := 0.0
	for i in range(a.size()):
		result = maxf(result, a[i].angle_to(b[i]))
	return result

func source_joints(skeleton: Skeleton3D) -> Dictionary:
	var wrist := skeleton.get_bone_global_rest(skeleton.find_bone("lwrist"))
	var inverse := wrist.affine_inverse()
	var result := {}
	for finger in ["thumb", "index", "ring"]:
		var first := inverse * skeleton.get_bone_global_rest(skeleton.find_bone("l" + finger + "01")).origin
		var second := inverse * skeleton.get_bone_global_rest(skeleton.find_bone("l" + finger + "02")).origin
		var tip := second + (second - first).normalized() * 0.025
		result[finger + "_metacarpal"] = first if finger == "thumb" else first * 0.7
		result[finger + "_proximal"] = second if finger == "thumb" else first
		if finger != "thumb":
			result[finger + "_intermediate"] = second
		result[finger + "_distal"] = second.lerp(tip, 0.5)
		result[finger + "_tip"] = tip
	return result

func run() -> void:
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "Test requires --xr-mode off")
	var world := Node3D.new()
	root.add_child(world)
	var rig := XROrigin3D.new()
	world.add_child(rig)
	rig.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(20, 3, -10))
	var body := CharacterBody3D.new()
	body.name = "PlayerBody"
	rig.add_child(body)
	var camera := XRCamera3D.new()
	camera.name = "XRCamera3D"
	rig.add_child(camera)
	var left := controller(rig, "left")
	controller(rig, "right")
	var driver := Driver.new()
	world.add_child(driver)
	driver.set_process(false)
	var avatar := Avatar.new()
	driver.add_child(avatar)
	var fixture := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/evidence/tracked-avatar-core3-character.json"))
	var character: Dictionary = fixture.character
	var configured: Dictionary = avatar.configure("human_male", character.appearance, character.equipment)
	check(configured.error == "" and driver.configure(avatar, rig), "Original human CoreCU appearance fixture failed to configure")
	var skeleton: Skeleton3D = avatar.skeleton
	var open_left := rotations(skeleton, "l")
	var joints := source_joints(skeleton)
	await process_frame
	driver.update_fingers()
	var fist_left := rotations(skeleton, "l")
	var fist_right := rotations(skeleton, "r")
	check(difference(open_left, fist_left) > 0.4 and driver.last_report.fingers.left.mode == "controller_pose", "Controller default failed to animate source fingers")
	var hand := XRHandTracker.new()
	hand.name = &"/user/hand_tracker/left"
	hand.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	hand.has_tracking_data = true
	hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	var wrist := Transform3D(Basis.from_euler(Vector3(0.4, -0.8, 0.3)), Vector3(-0.25, 1.15, -0.35))
	hand.set_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST, wrist)
	hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_WRIST, 5)
	for key in HandInput.JOINTS:
		var joint: int = HandInput.JOINTS[key]
		hand.set_hand_joint_transform(joint, wrist * Transform3D(Basis.IDENTITY, joints[key]))
		hand.set_hand_joint_flags(joint, 5)
	XRServer.add_tracker(hand)
	trackers.append(hand)
	driver.update_fingers()
	var skeletal_error := difference(open_left, rotations(skeleton, "l"))
	check(driver.last_report.fingers.left.mode == "skeletal" and skeletal_error < 0.002, "Skeletal joints failed to override controller fist with original open anatomy")
	check(driver.last_report.fingers.right.mode == "controller_pose" and difference(fist_right, rotations(skeleton, "r")) < 0.002, "Left skeleton altered right-hand fallback")
	hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, 0)
	driver.update_fingers()
	check(driver.last_report.fingers.left.mode == "controller_pose" and difference(fist_left, rotations(skeleton, "l")) < 0.002, "Invalid skeletal joint failed to restore controller fallback")
	hand.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, 5)
	hand.has_tracking_data = false
	driver.update_fingers()
	check(driver.last_report.fingers.left.mode == "controller_pose", "Tracking loss retained stale skeletal input")
	hand.has_tracking_data = true
	hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN
	driver.update_fingers()
	check(driver.last_report.fingers.left.mode == "skeletal", "Valid unknown-source runtime skeleton was rejected")
	hand.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	left.invalidate_pose("grip")
	await process_frame
	var left_node: XRController3D = rig.get_node("LeftHand")
	var target = driver.hand_target(left_node, "left")
	var ip: Vector3 = wrist * joints.index_proximal
	var rp: Vector3 = wrist * joints.ring_proximal
	var expected_position: Vector3 = rig.global_transform * wrist.origin.lerp((ip + rp) * 0.5, 0.55)
	var optical_error := INF
	if target is Transform3D:
		optical_error = target.origin.distance_to(expected_position)
	check(target is Transform3D and optical_error < 0.00001, "Optical arm target double-transformed or lost play-space anatomy")
	driver.update_fingers()
	check(driver.last_report.fingers.left.mode == "skeletal" and difference(fist_right, rotations(skeleton, "r")) < 0.002, "Optical skeletal input or independent right controller failed")
	hand.has_tracking_data = false
	check(driver.hand_target(left_node, "left") == null, "All tracking lost but stale optical arm target remained")
	var report := {"test": "original_human_controller_skeleton_finger_pipeline", "hardware_tested": false,
		"source_character_id": character.get("id", ""), "passed": errors.is_empty(), "errors": errors,
		"skeletal_open_pose_error_rad": skeletal_error, "optical_world_target_error_m": optical_error,
		"controller_default_skeletal_priority_tracking_loss_and_independent_hands": errors.is_empty()}
	FileAccess.open("res://../runtime/evidence/tracked-hand-pipeline-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	world.free()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	quit(0 if errors.is_empty() else 1)
