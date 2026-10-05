extends SceneTree
## Simulated XR poses/inputs exercise the real XR Tools rig without claiming
## headset rendering, runtime connectivity or human comfort validation.

var trackers: Array[XRControllerTracker] = []
var menu_count := 0
var pointer_events: Array[int] = []

class PointTarget extends StaticBody3D:
	signal pointer_event(event)

func _initialize() -> void:
	call_deferred("run")

func controller(name: StringName, hand: XRPositionalTracker.TrackerHand, position: Vector3) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = name
	tracker.hand = hand
	tracker.set_pose("grip", Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_pose("aim", Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("primary", Vector2.ZERO)
	tracker.set_input("trigger", 0.0)
	tracker.set_input("grip", 0.0)
	tracker.set_input("ax_button", false)
	tracker.set_input("menu_button", false)
	tracker.set_input("trigger_click", false)
	XRServer.add_tracker(tracker)
	trackers.append(tracker)
	return tracker

func box(parent: Node3D, position: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = position
	parent.add_child(body)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.5, 0), Vector3(30, 1, 30), 2)
	box(world, Vector3(0, 2, -4), Vector3(6, 4, 0.3), 1)
	var left := controller(&"left_hand", XRPositionalTracker.TRACKER_HAND_LEFT, Vector3(-0.25, 1.2, -0.35))
	var right := controller(&"right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT, Vector3(0.25, 1.2, -0.35))
	var rig: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	world.add_child(rig)
	var body = rig.get_node("PlayerBody")
	var camera: XRCamera3D = rig.get_node("XRCamera3D")
	body.menu_requested.connect(func(): menu_count += 1)
	body.active = true
	await frames(60)
	var floor_ok: bool = body.on_ground and absf(body.global_position.y) < 0.1
	var initial_height: float = body.tracked_height()
	var target := PointTarget.new()
	var aim_ray: RayCast3D = rig.get_node("LeftHand/FunctionPointer/RayCast")
	# XR Tools applies its authored grip-to-aim offset for an unknown mock
	# controller profile. Put the test target on that actual pointer ray.
	target.transform = Transform3D(aim_ray.global_basis, aim_ray.to_global(Vector3(0, 0, -1.25)))
	target.collision_layer = 1 << 22
	var target_shape := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(0.5, 0.5, 0.1)
	target_shape.shape = target_box
	target.add_child(target_shape)
	target.pointer_event.connect(func(event): pointer_events.append(int(event.event_type)))
	world.add_child(target)
	await frames(5)
	left.set_input("trigger_click", true)
	await frames(2)
	left.set_input("trigger_click", false)
	await frames(2)
	var pointer_click_ok: bool = pointer_events.has(2) and pointer_events.has(3)
	if not pointer_click_ok:
		var ray: RayCast3D = rig.get_node("LeftHand/FunctionPointer/RayCast")
		print(JSON.stringify({"pointer_events": pointer_events, "ray_origin": str(ray.global_position), "ray_target": str(ray.to_global(ray.target_position)), "target": str(target.global_position), "ray_collision": ray.is_colliding()}))
	target.queue_free()
	camera.position.y = 1.0
	await frames(15)
	var crouch_ok: bool = body.tracked_height() < initial_height - 0.4
	body.set_avatar_height(3.0)
	var no_species_camera_scale: bool = is_equal_approx(camera.position.y, 1.0) and is_equal_approx(XRServer.world_scale, 1.0)
	camera.position.y = 1.65
	await frames(15)
	var begin: Vector3 = body.global_position
	left.set_input("primary", Vector2(0, 1))
	await frames(45)
	var movement_distance: float = begin.distance_to(body.global_position)
	await frames(100)
	left.set_input("primary", Vector2.ZERO)
	await frames(10)
	var wall_ok: bool = body.global_position.z > -3.65 and body.global_position.z < -3.2
	var camera_before: Vector3 = camera.global_position
	var yaw_before: float = rig.global_rotation.y
	right.set_input("primary", Vector2(1, 0))
	await frames(10)
	right.set_input("primary", Vector2.ZERO)
	await frames(2)
	var yaw_change := absf(angle_difference(yaw_before, rig.global_rotation.y))
	var snap_ok: bool = absf(yaw_change - PI / 6) < 0.01 and camera_before.distance_to(camera.global_position) < 0.1
	body.active = false
	begin = body.global_position
	left.set_input("primary", Vector2(0, 1))
	await frames(20)
	var menu_stops_virtual_motion: bool = body.global_position.distance_to(begin) < 0.05
	left.set_input("primary", Vector2.ZERO)
	right.set_input("ax_button", true)
	await frames(2)
	right.set_input("ax_button", false)
	var action_buttons_do_not_open_menu := menu_count == 0
	left.set_input("menu_button", true)
	await frames(2)
	left.set_input("menu_button", false)
	var menu_signal_ok := action_buttons_do_not_open_menu and menu_count == 1
	var relative_before: Vector3 = camera.global_position - body.global_position
	body.apply_world_correction(Vector3(3, 0, 2))
	var correction_ok: bool = (camera.global_position - body.global_position).distance_to(relative_before) < 0.0001
	body.spawn_point = Vector3(4, 0, 4)
	body.spawn_yaw = 0.4
	body.reset_spawn()
	var reset_ok: bool = body.global_position.distance_to(body.spawn_point) < 0.0001 and body.velocity.length() < 0.001
	var pointers_ok: bool = rig.get_node("LeftHand/FunctionPointer").is_xr_class("XRToolsFunctionPointer") and rig.get_node("RightHand/FunctionPointer").is_xr_class("XRToolsFunctionPointer")
	var passed: bool = floor_ok and crouch_ok and no_species_camera_scale and movement_distance > 1 and wall_ok and snap_ok and menu_stops_virtual_motion and menu_signal_ok and correction_ok and reset_ok and pointers_ok and pointer_click_ok
	var report := {"test": "xr_tools_mocked_pose_and_input", "real_xr_tools_body": body.is_xr_class("XRToolsPlayerBody"), "tracked_floor_contact": floor_ok, "head_height_changes_capsule": crouch_ok, "species_does_not_scale_headset": no_species_camera_scale, "direct_movement_distance": movement_distance, "structures_block_motion": wall_ok, "snap_30_degrees_about_head": snap_ok, "menu_gates_locomotion": menu_stops_virtual_motion, "controller_menu_signal": menu_signal_ok, "world_correction_preserves_head_offset": correction_ok, "reset_preserves_tracking": reset_ok, "official_pointers": pointers_ok, "pointer_trigger_press_release": pointer_click_ok, "passed": passed, "hardware_tested": false}
	print(JSON.stringify(report))
	var evidence := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/xr-rig-smoke.json"), FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(report, "  "))
		evidence.close()
	world.queue_free()
	await process_frame
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	quit(0 if passed else 1)
