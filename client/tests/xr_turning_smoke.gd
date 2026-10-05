extends SceneTree
## Exercise the pinned XR Tools turn provider with simulated controller input.
var errors: Array[String] = []
var measurements: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func run() -> void:
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "Use --xr-mode off for this test")
	var right := XRControllerTracker.new()
	right.type = XRServer.TRACKER_CONTROLLER
	right.name = &"right_hand"
	right.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	right.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(0.3, 1.2, -0.4)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right.set_input("primary", Vector2.ZERO)
	XRServer.add_tracker(right)
	var world := Node3D.new()
	root.add_child(world)
	var rig: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	world.add_child(rig)
	var body = rig.get_node("PlayerBody")
	body.set_physics_process(false)
	var camera: XRCamera3D = rig.get_node("XRCamera3D")
	camera.position = Vector3(0.4, 1.65, -0.2)
	var turning = rig.get_node("RightHand/MovementTurn")
	var preferences = load("res://scripts/vr_settings.gd").new()
	preferences.path = "user://swgxr-turning-test-%d.cfg" % OS.get_process_id()
	preferences.set_turn_mode("smooth")
	preferences.set_turn_speed(90)
	check(preferences.save_preferences() == OK, "Test preferences could not be saved")
	var restored = load("res://scripts/vr_settings.gd").new()
	restored.path = preferences.path
	restored.load_preferences()
	check(restored.turn_mode == "smooth" and is_equal_approx(restored.turn_speed_degrees, 90), "Turning preferences did not persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences.path))
	body.active = true
	await process_frame
	for hz in [60, 90, 120]:
		for axis in [1.0, -1.0, 0.55, 0.05]:
			preferences.apply(rig)
			var head_before := camera.global_position
			var yaw_before := rig.global_rotation.y
			right.set_input("primary", Vector2(axis, 0))
			for tick in range(hz):
				turning.physics_movement(1.0 / hz, body, false)
			var observed := rad_to_deg(angle_difference(yaw_before, rig.global_rotation.y))
			var expected: float = 90.0 * signf(axis) * maxf(0.0, absf(axis) - 0.1) / 0.9
			# XR Tools rotates the origin opposite the right-stick input.
			check(absf(observed + expected) < 0.02, "Smooth turn rate differs at %d Hz / %.2f input: %.3f" % [hz, axis, observed])
			check(camera.global_position.distance_to(head_before) < 0.0001, "Turning translated the tracked head pivot")
			measurements.append({"hz": hz, "input": axis, "degrees": observed})
	preferences.set_turn_mode("snap")
	preferences.apply(rig)
	var snap_before := rig.global_rotation.y
	right.set_input("primary", Vector2(1, 0))
	for tick in range(120):
		turning.physics_movement(1.0 / 120.0, body, false)
	check(absf(absf(angle_difference(snap_before, rig.global_rotation.y)) - PI / 6) < 0.001, "Held snap input repeated or used wrong angle")
	right.set_input("primary", Vector2.ZERO)
	turning.physics_movement(1.0 / 120.0, body, false)
	right.set_input("primary", Vector2(1, 0))
	turning.physics_movement(1.0 / 120.0, body, false)
	check(absf(absf(angle_difference(snap_before, rig.global_rotation.y)) - PI / 3) < 0.001, "Snap turn did not re-arm after release")
	body.active = false
	check(not turning.enabled, "Menu/focus inactivity did not disable turning")
	preferences.set_turn_mode("smooth")
	preferences.apply(rig)
	check(not turning.enabled, "Changing preference bypassed locomotion gating")
	var report := {"test": "smooth_and_snap_turning", "hardware_tested": false, "passed": errors.is_empty(), "errors": errors, "measurements": measurements, "preferences_roundtrip": true}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-turning-smoke.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	XRServer.remove_tracker(right)
	quit(0 if errors.is_empty() else 1)
