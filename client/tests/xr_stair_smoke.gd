extends SceneTree

var body: CharacterBody3D
var rig: XROrigin3D
var left: XRControllerTracker
var right: XRControllerTracker

func _initialize() -> void:
	call_deferred("run")

func controller(name: StringName, hand: XRPositionalTracker.TrackerHand, position: Vector3) -> XRControllerTracker:
	var tracker := XRControllerTracker.new()
	tracker.name = name
	tracker.hand = hand
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.set_pose("grip", Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input("primary", Vector2.ZERO)
	XRServer.add_tracker(tracker)
	return tracker

func box(parent: Node3D, location: Vector3, size: Vector3) -> void:
	var node := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	node.add_child(collider)
	node.position = location
	parent.add_child(node)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func settle(point: Vector3) -> void:
	left.set_input("primary", Vector2.ZERO)
	body.spawn_point = point
	body.spawn_yaw = 0
	body.reset_spawn()
	await frames(60)

func walk(input: Vector2, count: int) -> Vector3:
	left.set_input("primary", input)
	await frames(count)
	left.set_input("primary", Vector2.ZERO)
	return body.global_position

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(10, -0.5, -3), Vector3(45, 1, 30))
	for i in range(4):
		var height := (i + 1) * 0.25
		box(world, Vector3(0, height / 2, -1.9 - i * 0.8), Vector3(4, height, 0.8))
	box(world, Vector3(0, 0.5, -6.3), Vector3(4, 1, 3.2))
	box(world, Vector3(10, 0.45, -3), Vector3(4, 0.9, 3))
	box(world, Vector3(20, 0.15, -3), Vector3(4, 0.3, 3))
	box(world, Vector3(20, 2.1, -3), Vector3(4, 0.2, 6))
	left = controller(&"left_hand", XRPositionalTracker.TRACKER_HAND_LEFT, Vector3(-0.25, 1.2, -0.35))
	right = controller(&"right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT, Vector3(0.25, 1.2, -0.35))
	rig = load("res://xr/player_rig.tscn").instantiate()
	world.add_child(rig)
	body = rig.get_node("PlayerBody")
	body.active = true
	await settle(Vector3(0, 1, 0))
	var head: XRCamera3D = rig.get_node("XRCamera3D")
	var tracked_pose := head.transform
	var up_start: int = body.steps_up
	var top := await walk(Vector2(0, 1), 42)
	var climbed: bool = top.y > 0.95 and top.z < -5 and body.steps_up > up_start
	var down_start: int = body.steps_down
	var bottom := await walk(Vector2(0, -1), 48)
	await frames(25)
	var descended: bool = bottom.y < 0.1 and body.steps_down > down_start and body.on_ground
	var head_preserved: bool = head.transform.is_equal_approx(tracked_pose)
	await settle(Vector3(10, 1, 0))
	up_start = body.steps_up
	var wall := await walk(Vector2(0, 1), 60)
	var high_wall: bool = wall.z > -1.6 and wall.y < 0.1 and body.steps_up == up_start
	await settle(Vector3(20, 0.1, 0.5))
	up_start = body.steps_up
	var ceiling := await walk(Vector2(0, 1), 60)
	var headroom: bool = ceiling.z > -1.6 and ceiling.y < 0.25 and body.steps_up == up_start
	await settle(Vector3(-8, 1, 8))
	await walk(Vector2(0, 1), 45)
	var forward_speed := Vector2(body.velocity.x, body.velocity.z).length()
	await settle(Vector3(-8, 1, 8))
	await walk(Vector2(1, 1), 45)
	var diagonal_speed := Vector2(body.velocity.x, body.velocity.z).length()
	await settle(Vector3(-8, 1, 8))
	await walk(Vector2(0, 0.5), 45)
	var analog_speed := Vector2(body.velocity.x, body.velocity.z).length()
	var speed_ok := absf(forward_speed - 9.36) < 0.05 and absf(diagonal_speed - 9.36) < 0.05 and analog_speed > 1 and analog_speed < forward_speed - 1
	# A downward snap must never attach an airborne capsule to ground from a
	# large drop. Let ordinary gravity handle this independent fall.
	await settle(Vector3(-8, 1, 0))
	body.apply_world_correction(Vector3(0, 2, 0))
	var airborne_start := body.global_position.y
	await frames(1)
	var no_air_snap: bool = body.global_position.y > airborne_start - 0.1
	var passed := climbed and descended and high_wall and headroom and head_preserved and no_air_snap and speed_ok
	var report := {"test": "xr_native_stairs_full_run_speed", "speed": rig.get_node("LeftHand/MovementDirect").max_speed, "measured_forward_speed": forward_speed, "measured_diagonal_speed": diagonal_speed, "measured_half_stick_speed": analog_speed, "speed_and_analog_cap": speed_ok, "climbed_without_jump": climbed, "top": str(top), "descended_with_support": descended, "bottom": str(bottom), "high_wall_blocks": high_wall, "wall": str(wall), "low_ceiling_blocks": headroom, "ceiling": str(ceiling), "tracked_hmd_pose_unchanged": head_preserved, "no_airborne_snap": no_air_snap, "passed": passed}
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	quit(0 if passed else 1)
