extends SceneTree
var checks := 0
var errors: Array[String] = []
var recoveries: Array = []
var head: XRPositionalTracker
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func wait_frames(count: int) -> void:
	for i in range(count): await physics_frame
func head_height(height: float) -> void:
	head.set_pose("default", Transform3D(Basis.IDENTITY, Vector3(0,height,0)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func controller(side: String) -> XRControllerTracker:
	var item := XRControllerTracker.new()
	item.type = XRServer.TRACKER_CONTROLLER
	item.name = side + "_hand"
	item.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	item.set_input("primary_click", false)
	item.set_input("primary", Vector2.ZERO)
	var pose := Transform3D(Basis.IDENTITY, Vector3(-0.2 if side == "left" else 0.2,1.3,-0.4))
	item.set_pose("grip", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(item)
	return item
func click(item: XRControllerTracker) -> void:
	item.set_input("primary_click", true)
	await wait_frames(2)
	item.set_input("primary_click", false)
	await wait_frames(2)

func run() -> void:
	create_timer(55).timeout.connect(func(): quit(2))
	head = XRPositionalTracker.new()
	head.type = XRServer.TRACKER_HEAD
	head.name = "head"
	head_height(1.7)
	XRServer.add_tracker(head)
	var left := controller("left")
	var right := controller("right")
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20,0.2,20)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.1
	root.add_child(floor)
	var origin: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	root.add_child(origin)
	var body = origin.get_node("PlayerBody")
	var camera: XRCamera3D = origin.get_node("XRCamera3D")
	body.active = true
	body.feedback.recovery_requested.connect(func(posture, automatic): recoveries.append([posture,automatic]))
	await wait_frames(20)
	check(body.on_ground, "Tracked body is grounded")
	var body_y: float = body.global_position.y
	var eye_y: float = camera.global_position.y
	var raw_head := camera.transform
	var raw_hand: Transform3D = origin.get_node("RightHand").transform
	await click(right)
	check(body.feedback.motion.get_jump_time() < 0, "Weapon-hand stick does not jump")
	await click(left)
	check(body.feedback.last_action.action == "jump", "Offhand stick starts cosmetic jump")
	var eye_peak := 0.0
	var body_peak := 0.0
	for i in range(230):
		await physics_frame
		eye_peak = maxf(eye_peak, camera.global_position.y-eye_y)
		body_peak = maxf(body_peak, absf(body.global_position.y-body_y))
	check(eye_peak > 0.48 and eye_peak < 0.53, "VR viewpoint follows original half-metre jump")
	check(body_peak < 0.01 and not body.jump_in_progress, "Cosmetic VR jump never lifts collision body or enables obstacle jumping")
	check(camera.transform.is_equal_approx(raw_head) and origin.get_node("RightHand").transform.is_equal_approx(raw_hand), "HMD and controller local tracking poses remain unchanged")
	check(absf(camera.global_position.y-eye_y) < 0.01, "View returns without accumulated origin offset")
	check(body.receive_combat_knockdown(), "Standing tracked player accepts knockdown")
	await wait_frames(50)
	check(body.feedback.motion.is_knocked_down() and camera.global_position.y < body_y+0.4, "Knockdown lowers and holds viewpoint")
	check(body.feedback.physical().posture == 0 and absf(float(body.combat_tracking_context().eye_height)-(eye_y-body_y)) < 0.01, "Presentation lowering never creates false physical prone recovery: %s" % body.combat_tracking_context())
	check(not body.combat_actions_allowed() and not origin.get_node("LeftHand/MovementDirect").enabled, "Downed player cannot attack or use stick locomotion")
	await click(left)
	check(not body.feedback.motion.is_knocked_down() and recoveries.back() == [0,false], "Jump requests standing recovery")
	await wait_frames(30)
	body.receive_combat_knockdown()
	head_height(1.0)
	await wait_frames(30)
	await click(left)
	check(recoveries.back() == [1,false] and not body.feedback.motion.is_knocked_down(), "Crouching player requests kneeling recovery")
	head_height(1.7)
	await wait_frames(30)
	body.receive_combat_knockdown()
	await wait_frames(20)
	head_height(0.5)
	await wait_frames(30)
	check(not body.feedback.motion.is_knocked_down() and recoveries.back() == [2,true], "Physical prone automatically recovers without a button")
	check(not body.receive_combat_knockdown(), "Already prone tracked player cannot be knocked down")
	head_height(1.7)
	await wait_frames(20)
	body.dominant_hand = "left"
	await click(left)
	check(body.feedback.motion.get_jump_time() < 0, "Left dominant stick remains reserved for abilities")
	await click(right)
	check(body.feedback.motion.get_jump_time() >= 0, "Right offhand stick jumps for left-handed player")
	body.feedback.reset()
	body.configure_player_combat({"character_id":"xr-feedback", "complete":true, "posture":13,
		"ham":[0,300,300,600,300,300,800,300,300], "max_ham":[1000,300,300,1000,300,300,1000,300,300], "wounds":[150,0,0,0,0,0,100,0,0]})
	await click(right)
	check(body.feedback.last_action.action == "none" and not body.combat_actions_allowed(), "Jump cannot recover incapacitation as knockdown")
	await process_frame
	check(body.wrist_ham.visible and body.wrist_ham.bars[0].wounds.text == "−150", "Dominant wrist HAM uses observed maximum and wounds")
	body.configure_player_combat({"character_id":"xr-feedback", "posture":0})
	body.receive_combat_knockdown()
	await wait_frames(15)
	body.reset_spawn()
	await wait_frames(3)
	check(not body.feedback.motion.is_knocked_down() and absf(body.feedback.applied_offset)<0.01, "Spawn reset clears knockdown and presentation offset")
	# Camera presentation is clipped by a low ceiling; the capsule stays grounded.
	var ceiling := StaticBody3D.new()
	var roof_shape := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(4,0.1,4)
	roof_shape.shape = roof_box
	ceiling.add_child(roof_shape)
	ceiling.position.y = 2.0
	root.add_child(ceiling)
	await wait_frames(10)
	await click(right)
	var ceiling_peak := 0.0
	for i in range(210):
		await physics_frame
		ceiling_peak = maxf(ceiling_peak, camera.global_position.y)
	check(ceiling_peak < 1.92 and ceiling_peak > 1.8, "Cosmetic jump view is blocked below solid ceiling: peak=%f action=%s physical=%s body=%s" % [ceiling_peak,body.feedback.last_action,body.feedback.physical(),body.global_position])
	origin.free()
	floor.free()
	ceiling.free()
	for item in [head,left,right]: XRServer.remove_tracker(item)
	var report := {"test":"player_feedback_xr", "checks":checks, "passed":errors.is_empty(), "errors":errors, "mocked_tracking":true, "hardware_tested":false, "live_core3":false, "gpu_validation":false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../runtime/evidence/player-feedback"))
	FileAccess.open("res://../runtime/evidence/player-feedback/xr.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
