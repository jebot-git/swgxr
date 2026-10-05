extends SceneTree
## Main's real XR branch with simulated controller inputs and camera poses.
## Run ONLY with --headless --xr-mode off; this does not initialize OpenXR.

class Harness extends "res://scripts/main.gd":
	var loading_samples := 0
	var loading_physics_enabled := false
	var loading_y := INF
	var loading_drop := 0.0
	var covered_spawn_adjustment := 0.0
	func _process(delta: float) -> void:
		super(delta)
		if loading_stage and terrain != null:
			loading_samples += 1
			loading_physics_enabled = loading_physics_enabled or player.is_physics_processing()
			if is_inf(loading_y):
				loading_y = player.global_position.y
			var drop := maxf(0.0,loading_y-player.global_position.y)
			if is_instance_valid(loading_screen) and loading_screen.active:
				covered_spawn_adjustment = maxf(covered_spawn_adjustment,drop)
			else:
				loading_drop = maxf(loading_drop,drop)
	func _ready() -> void:
		pass

class AnimationProbe extends Node3D:
	var updates := 0
	func update_motion(_delta, _speed, _state) -> void:
		updates += 1

var app: Harness
var trackers: Array[XRPositionalTracker] = []
var report := {"test": "main_xr_actual_stage_mocked_tracking", "hardware_tested": false, "passed": false, "errors": []}
var finished := false
var started := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		report.errors.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func controller(name: StringName, hand: XRPositionalTracker.TrackerHand, position: Vector3) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = name
	tracker.hand = hand
	for pose in [&"grip", &"aim"]:
		tracker.set_pose(pose, Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("primary", Vector2.ZERO)
	tracker.set_input("trigger", 0.0)
	tracker.set_input("grip", 0.0)
	tracker.set_input("ax_button", false)
	tracker.set_input("trigger_click", false)
	XRServer.add_tracker(tracker)
	trackers.append(tracker)
	return tracker

func finish() -> void:
	if finished:
		return
	finished = true
	report.passed = report.errors.is_empty()
	report.elapsed_ms = Time.get_ticks_msec() - started
	var path := ProjectSettings.globalize_path("res://../runtime/evidence/xr-main-smoke.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	print("XR_MAIN_SMOKE_PASS" if report.passed else "XR_MAIN_SMOKE_FAIL")
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	quit(0 if report.passed else 1)

func run() -> void:
	started = Time.get_ticks_msec()
	var interface := XRServer.find_interface("OpenXR")
	check(DisplayServer.get_name() == "headless", "Integration test requires headless mode")
	check(interface == null or not interface.is_initialized(), "Integration test requires --xr-mode off")
	if not report.errors.is_empty():
		await finish()
		return
	create_timer(90).timeout.connect(func():
		if not finished:
			check(false, "Main XR integration exceeded 90 seconds")
			finish()
	)
	var left := controller(&"left_hand", XRPositionalTracker.TRACKER_HAND_LEFT, Vector3(-0.25, 1.2, -0.35))
	controller(&"right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT, Vector3(0.25, 1.2, -0.35))
	app = Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.xr_requested = true
	app.xr_initialized = true # Test the selected application branch, not runtime startup.
	app.xr_focused = true
	app.stage_path = ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")
	if "--review-assets" in OS.get_cmdline_user_args():
		app.stage_path = ProjectSettings.globalize_path("res://../runtime/assets_review/mos_eisley/scene.json")
		app.args["world-manifest"] = ProjectSettings.globalize_path("res://../runtime/assets_review/tatooine_world/world.json")
	app.configure_inputs()
	app.make_environment()
	app.xr_origin = load("res://xr/player_rig.tscn").instantiate()
	app.add_child(app.xr_origin)
	app.player = app.xr_origin.get_node("PlayerBody")
	app.player.set_physics_process(false)
	app.player.menu_requested.connect(app.toggle_xr_menu)
	app.prepare_xr_viewport()
	app.vr_settings.apply(app.xr_origin)
	app.make_ui()
	app.xr_menu = app.XRMenu.new()
	app.add_child(app.xr_menu)
	var camera: XRCamera3D = app.player.get_camera()
	app.xr_menu.configure(app.ui_root, camera)
	app.xr_spectator = load("res://xr/spectator.tscn").instantiate()
	app.add_child(app.xr_spectator)
	check(app.xr_spectator.configure(app.xr_origin, app.player), "Main spectator failed to configure")
	check(app.xr_origin.get_viewport() == app.xr_viewport and app.xr_viewport.world_3d == app.get_world_3d(), "Headset viewport does not share the stage world")
	check(app.xr_spectator.get_viewport() == root and camera.get_viewport() != root, "Desktop and headset rendering were not separated")
	app.set_process(true)
	await app.enter_stage(true)
	app.set_process(false)
	check(app.loading_samples > 0 and not app.loading_physics_enabled and app.loading_drop < 0.0001, "Loading allowed VR physics or visible gravity drop")
	report.loading = {"samples":app.loading_samples,"physics_enabled":app.loading_physics_enabled,"uncovered_vertical_drop":app.loading_drop,"covered_spawn_adjustment":app.covered_spawn_adjustment}
	report.spawn_support = app.player.get_meta("spawn_support", {})
	check(app.stage != null and app.terrain != null and app.world_stream != null, "Main failed to load actual stage, terrain or world")
	if app.stage == null or app.terrain == null or app.world_stream == null:
		await finish()
		return
	check(app.terrain.ready_near(app.player.global_position), "Main enabled entry before nearby terrain was ready")
	check(app.world_stream.report.get("ready", false), "Main entered before world scenery was ready")
	check(app.player.global_position.distance_to(app.player.spawn_point) < 0.001, "XR body did not enter the original manifest spawn")
	check(not app.menu.visible and not app.xr_menu.visible and app.player.active, "Stage entry did not close XR menu and enable locomotion")
	check(camera.get_parent() == app.xr_origin and camera.current, "Main lost the tracked origin/camera hierarchy")
	check(app.avatar == null and not app.action_row.visible, "XR mode created a desktop animated avatar or action row")
	var spawn_body: Vector3 = app.player.global_position
	var head_offset: Vector3 = camera.global_position - spawn_body
	check(absf(head_offset.y - 1.65) < 0.01, "Stage spawn incorrectly scaled or translated tracked head height")
	await frames(120)
	check(absf(app.player.global_position.y-spawn_body.y) < 0.01, "VR entry still settled visibly after loading")
	report.entry_settle_distance = absf(app.player.global_position.y-spawn_body.y)
	app.stage.update_cell()
	check(not app.stage.current_cell.is_empty() and app.player.collision_mask == 5, "XR body did not acquire original interior floor/extent collision mask")
	check(app.player.on_ground, "XR Tools body did not settle onto original starport collision")
	report.stage = {"instances": app.loader.report.instances, "terrain_near_ready": true, "world_ready": true,
		"spawn": str(spawn_body), "head_offset": str(head_offset), "interior_cell": app.stage.current_cell,
		"grounded": app.player.on_ground, "collision_mask": app.player.collision_mask}
	app.portal_visibility.update_views()
	report.portal_visibility = app.portal_visibility.report
	check(not app.portal_visibility.report.views[0].overflow, "Source starport exceeded portal visibility budget")
	check(app.portal_visibility.report.views[0].building == 1106368, "Headset portal view lost its source starport cell")
	# Core3 appearance now creates a tracked original avatar without driving XR poses.
	var metadata := {"id": "integration-fixture", "appearance": {"race": "wookiee_male", "height": 1.2}}
	var head_before: Transform3D = camera.transform
	app.configure_player_avatar({"character": metadata})
	check(app.player.get_meta("core3_character") == metadata and app.avatar != null and app.avatar.tracking_mode and app.tracked_avatar != null, "XR character appearance failed to create a tracked original avatar")
	check(camera.transform.is_equal_approx(head_before), "Species appearance changed the tracked head transform")
	var head_tracker := XRPositionalTracker.new()
	head_tracker.name = "head"
	head_tracker.type = XRServer.TRACKER_HEAD
	head_tracker.set_pose("default", camera.transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(head_tracker)
	trackers.append(head_tracker)
	app.tracked_avatar._process(1.0 / 72.0)
	check(app.tracked_avatar.visible and app.tracked_avatar.calibrated, "Tracked head failed to activate the original body")
	check(app.tracked_avatar.last_report.left_tracked and app.tracked_avatar.last_report.right_tracked, "Valid controller poses did not drive both original arms")
	check(not app.xr_origin.get_node("LeftHand/Hand").visible and not camera.get_cull_mask_value(2), "First-person original body did not replace gloves or mask own head")
	check(app.tracked_avatar.last_report.fingers.left.mode == "controller_pose", "Controller finger pose collection was not connected")
	head_tracker.invalidate_pose("default")
	app.tracked_avatar._process(1.0 / 72.0)
	check(not app.tracked_avatar.visible and app.xr_origin.get_node("LeftHand/Hand").visible, "Lost head tracking did not hide the body and restore glove fallback")
	head_tracker.set_pose("default", camera.transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	app.tracked_avatar._process(1.0 / 72.0)
	check(camera.transform.is_equal_approx(head_before), "Tracked IK wrote to HMD tracking")
	report.tracked_original_body = {"head_loss_and_recovery":true, "controller_arms_and_fingers":true, "camera_unchanged":true}
	var probe := AnimationProbe.new()
	app.add_child(probe)
	app.avatar = probe
	app._process(1.0 / 72.0)
	check(probe.updates == 0 and not app.play_avatar_action("emote_wave1"), "XR mode ran desktop animation")
	app.avatar = app.tracked_avatar.avatar
	probe.queue_free()
	var before_input: Vector3 = app.player.global_position
	for key in [KEY_V, KEY_C, KEY_P, KEY_X, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_R]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		app._unhandled_input(event)
	check(app.player.global_position.is_equal_approx(before_input), "Desktop posture/view/reset keys affected XR body")
	report.desktop_animation_and_posture_suppressed = true
	# Open the actual world-space menu; controller stick input must stop while
	# tracked room-scale displacement continues to drive the real physics body.
	app.toggle_xr_menu()
	check(app.menu.visible and app.xr_menu.visible and not app.player.active, "XR menu failed to disable virtual locomotion")
	check(app.player.is_physics_processing(), "XR menu disabled tracked-body physics")
	var menu_start: Vector3 = app.player.global_position
	left.set_input("primary", Vector2(0, 1))
	await frames(30)
	var menu_drift: float = app.player.global_position.distance_to(menu_start)
	check(menu_drift < 0.05, "Virtual locomotion continued behind the XR menu")
	left.set_input("primary", Vector2.ZERO)
	var room_start: Vector3 = app.player.global_position
	camera.position.x += 0.20
	await frames(20)
	var room_distance: float = app.player.global_position.distance_to(room_start)
	check(room_distance > 0.12 and room_distance < 0.3, "Room-scale tracking stopped while XR menu was open")
	app.toggle_xr_menu()
	check(not app.menu.visible and not app.xr_menu.visible and app.player.active, "Closing XR menu did not restore locomotion")
	var walk_start: Vector3 = app.player.global_position
	left.set_input("primary", Vector2(0, 1))
	await frames(20)
	left.set_input("primary", Vector2.ZERO)
	var walk_distance: float = app.player.global_position.distance_to(walk_start)
	check(walk_distance > 0.2, "Main XR locomotion did not resume after menu close")
	check(app.tracked_avatar.last_report.motion.state in ["walk", "run", "strafe_left", "strafe_right", "backpedal"], "Measured XR movement did not animate the original legs/torso")
	report.tracked_locomotion_state = app.tracked_avatar.last_report.motion.state
	report.menu = {"virtual_motion_during_menu": menu_drift, "room_scale_during_menu": room_distance, "resumed_motion": walk_distance}
	# Stage-space recenter preserves the tracked head position and physical height.
	app.player.rotate_player(0.5)
	var recenter_before: Vector3 = camera.global_position
	app.recenter_xr()
	check(camera.global_position.distance_to(recenter_before) < 0.002, "Recenter translated the tracked head")
	check(absf(angle_difference(camera.global_rotation.y, app.player.spawn_yaw)) < 0.001, "Recenter did not reset view yaw")
	app.xr_focused = false
	app.sync_xr_activity()
	check(not app.player.active, "Losing XR focus did not gate virtual locomotion")
	app.xr_focused = true
	app.sync_xr_activity()
	check(app.player.active, "Restoring XR focus did not restore virtual locomotion")
	report.recenter_and_focus = true
	# Exercise main's actual world-bound correction, not only the rig facade.
	app.player.set_physics_process(false)
	var outside: Vector3 = app.terrain.terrain_position(Vector2(8300, -8300))
	app.player.apply_world_correction(outside - app.player.global_position)
	var relative_before: Vector3 = camera.global_position - app.player.global_position
	var basis_before: Basis = camera.global_basis
	app._process(1.0 / 72.0)
	var source: Vector2 = app.terrain.source_position(app.player.global_position)
	var relative_error: float = (camera.global_position - app.player.global_position).distance_to(relative_before)
	check(absf(source.x) <= 8191.001 and absf(source.y) <= 8191.001, "Main XR planet bounds did not constrain tracked body")
	check(relative_error < 0.002 and camera.global_basis.is_equal_approx(basis_before), "World bounds correction changed tracked head-relative pose")
	report.world_bounds = {"source_position": str(source), "head_offset_error": relative_error, "head_orientation_preserved": camera.global_basis.is_equal_approx(basis_before)}
	# Failed grounding cannot expose a falling player or be undone by _process.
	app.args["position"] = "-60,1000,10"
	app.menu.visible = true
	app.xr_menu.set_open(true)
	await app.enter_stage(true)
	var failed_y: float = app.player.global_position.y
	app._process(1.0/72.0)
	await frames(5)
	check(not app.world_ready and not app.player.is_physics_processing() and not app.player.active, "Missing spawn floor enabled physics")
	check(absf(app.player.global_position.y-failed_y) < 0.001 and app.asset_status.text.begins_with("No safe ground"), "Missing spawn floor did not remain paused with an error")
	report.missing_floor_stays_paused = true
	await finish()
