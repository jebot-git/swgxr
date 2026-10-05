extends SceneTree
## Validate project bindings and installed hand-joint API without starting XR.

var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "Run this test with --xr-mode off")
	var action_map: OpenXRActionMap = load("res://openxr_action_map.tres")
	var actions := {}
	for action_set in action_map.action_sets:
		for action in action_set.actions:
			actions[action.resource_name] = action
	for name in ["trigger_touch", "primary_touch", "secondary_touch", "ax_touch", "by_touch", "thumbrest_touch"]:
		check(actions.has(name), "Missing hand touch action: " + name)
		if actions.has(name):
			check(actions[name].action_type == OpenXRAction.OPENXR_ACTION_BOOL, "Touch action must be boolean: " + name)
	var profiles := {}
	for profile in action_map.interaction_profiles:
		var bindings := {}
		for binding in profile.bindings:
			bindings[binding.binding_path] = binding.action.resource_name
		profiles[profile.interaction_profile_path] = bindings
	for profile_name in ["/interaction_profiles/oculus/touch_controller", "/interaction_profiles/valve/index_controller"]:
		check(profiles.has(profile_name), "Missing supported interaction profile: " + profile_name)
		if not profiles.has(profile_name):
			continue
		var bindings: Dictionary = profiles[profile_name]
		var oculus: bool = profile_name.contains("oculus")
		for hand in ["left", "right"]:
			var expected := {"trigger/touch": "trigger_touch", "thumbstick/touch": "primary_touch"}
			expected[("x" if hand == "left" and oculus else "a") + "/touch"] = "ax_touch"
			expected[("y" if hand == "left" and oculus else "b") + "/touch"] = "by_touch"
			expected["thumbrest/touch" if oculus else "trackpad/touch"] = "thumbrest_touch" if oculus else "secondary_touch"
			for path in expected:
				var full_path: String = "/user/hand/" + hand + "/input/" + path
				check(bindings.get(full_path, "") == expected[path], "Wrong or absent touch binding: " + full_path + " in " + profile_name)
	for setting in ["hand_tracking", "hand_tracking_controller_data_source", "hand_tracking_unobstructed_data_source"]:
		check(ProjectSettings.get_setting("xr/openxr/extensions/" + setting, false), "Hand tracking source disabled: " + setting)
	# Exercise this exact engine's runtime-neutral hand API with synthetic data.
	var tracker := XRHandTracker.new()
	tracker.name = &"/user/hand_tracker/left"
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	var joint := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
	var pose := Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(-0.2, 1.2, -0.3))
	tracker.set_hand_joint_flags(joint, XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID)
	tracker.set_hand_joint_transform(joint, pose)
	XRServer.add_tracker(tracker)
	check(XRServer.get_tracker(tracker.name) == tracker, "XRServer hand tracker lookup failed")
	check(tracker.get_hand_joint_transform(joint).is_equal_approx(pose), "Hand joint transform API round trip failed")
	check(int(tracker.get_hand_joint_flags(joint)) == 5, "Joint valid flags API mismatch")
	check(tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER, "Controller skeleton source unavailable")
	XRServer.remove_tracker(tracker)
	var report := {"test": "project_hand_bindings_and_godot_joint_api", "passed": errors.is_empty(), "hardware_tested": false,
		"action_count": actions.size(), "profile_count": profiles.size(), "joint_count": XRHandTracker.HAND_JOINT_MAX,
		"oculus_and_index_touch_bindings": errors.is_empty(), "errors": errors}
	var path := ProjectSettings.globalize_path("res://../runtime/evidence/xr-hand-input-smoke.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
