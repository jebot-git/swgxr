extends SceneTree

var left: XRControllerTracker
var right: XRControllerTracker

func _initialize() -> void:
	call_deferred("run")

func tracker(name: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var result := XRControllerTracker.new()
	result.name = name
	result.hand = hand
	result.type = XRServer.TRACKER_CONTROLLER
	result.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(0.2, 1.2, -0.3)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	result.set_input("primary", Vector2.ZERO)
	XRServer.add_tracker(result)
	return result

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func run() -> void:
	var asset_root := "res://../runtime/assets_review" if OS.get_cmdline_user_args().has("--review-assets") else "res://../runtime/assets"
	var loader = load("res://scripts/stage_loader.gd").new()
	var stage = loader.load_stage(ProjectSettings.globalize_path(asset_root.path_join("mos_eisley/scene.json")))
	if stage == null:
		push_error(loader.report.error)
		quit(1)
		return
	root.add_child(stage)
	left = tracker(&"left_hand", XRPositionalTracker.TRACKER_HAND_LEFT)
	right = tracker(&"right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT)
	var rig: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	root.add_child(rig)
	var body = rig.get_node("PlayerBody")
	body.spawn_point = Vector3(-60.42, 1.2, 18.3)
	body.spawn_yaw = 0
	body.reset_spawn()
	body.prepare_tracked_body()
	body.active = true
	body.ground_provider = stage
	stage.set_observer(body)
	stage.seed_membership_at(body.global_position, "1106368:8")
	await frames(90)
	assert(stage.current_cell.get("cell_id", "") == "1106368:8" and body.collision_mask == 5, "Original staircase spawn was not attached to its source cell")
	var start: Vector3 = body.global_position
	var head: XRCamera3D = body.get_camera()
	var head_pose := head.transform
	var steps_before: int = body.steps_up
	left.set_input("primary", Vector2(0, -1))
	await frames(40)
	left.set_input("primary", Vector2.ZERO)
	await frames(15)
	var top: Vector3 = body.global_position
	var steps: int = body.steps_up - steps_before
	var ascends: bool = top.z > 22.8 and top.y - start.y > 0.85 and body.on_ground
	var down_before: int = body.steps_down
	left.set_input("primary", Vector2(0, 1))
	await frames(40)
	left.set_input("primary", Vector2.ZERO)
	await frames(30)
	var bottom: Vector3 = body.global_position
	var descends: bool = bottom.z < 18.6 and absf(bottom.y - start.y) < 0.1 and body.on_ground
	var tracking_preserved := head.transform.is_equal_approx(head_pose)
	var passed: bool = ascends and descends and tracking_preserved
	var report := {"test": "xr_authored_ticket1_stairs", "source": "appearance/mesh/mun_tato_starport_s01_u01_r8_ticket1_mesh_r8.msh", "speed": rig.get_node("LeftHand/MovementDirect").max_speed, "start": str(start), "top": str(top), "bottom": str(bottom), "steps_up": steps, "steps_down": body.steps_down - down_before, "ascends_without_jump": ascends, "descends": descends, "tracked_head_pose_preserved": tracking_preserved, "hardware_tested": false,"asset_root":asset_root, "passed": passed}
	FileAccess.open("res://../runtime/evidence/xr-authored-starport-stairs.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	rig.queue_free()
	stage.queue_free()
	await process_frame
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	quit(0 if passed else 1)
