extends XRToolsPlayerBody
## Application facade over the unmodified XR Tools tracked physics body.
## OpenXR owns the camera/controllers; this script never animates their poses.

signal menu_requested

var active := false:
	set(value):
		active = value
		_update_locomotion()
var testing := false
var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var void_floor_y := -4096.0
var step_solver := SwgXRStepSolver.new()
var steps_up := 0
var steps_down := 0
var jump_in_progress := false
# Persistent cell authority owns membership; native floor evaluation owns geometry.
var ground_provider: Node3D
var support_state: Dictionary = {"valid": false}
var support_snap_distance := 0.35
var support_contact_distance := 0.1
var roomscale_steps := 0
var interface_move_captured := false
var interface_turn_captured := false
var dominant_hand := "right"
var combat_pools = preload("res://combat/ability_state.gd").new()
var feedback = preload("res://combat/player_feedback.gd").new()
var wrist_ham: Node3D
var medic: Node3D
var vehicles: Node3D
var medical_stick_side := ""
var combat_rig: Node3D

func configure_player_combat(context: Dictionary) -> void:
	combat_pools.refresh_context(context)
	feedback.observe(context)

func combat_actions_allowed() -> bool:
	return not feedback.combat_blocked() and not (is_instance_valid(feedback.performer) and feedback.performer.is_performing())

func receive_combat_knockdown() -> bool:
	return feedback.receive_knockdown()

func request_jump(_skip_jump_velocity := false):
	if is_instance_valid(vehicles) and vehicles.seated():
		vehicles.request("dismount");return
	feedback.request_jump()
var combat_stick_side := ""
var combat_prime_active := false

func set_combat_capture(side: String, prime_active: bool) -> void:
	combat_stick_side = side
	combat_prime_active = prime_active
	_update_locomotion()

func set_interface_capture(move: bool, turn: bool) -> void:
	interface_move_captured = move
	interface_turn_captured = turn
	_update_locomotion()

func _ready() -> void:
	super()
	feedback.configure(self, camera_node, origin_node)
	wrist_ham = preload("res://combat/wrist_ham.gd").new()
	add_child(wrist_ham)
	wrist_ham.pools = combat_pools
	process_priority = 150 # Read final rendered grip after avatar IK.
	left_hand_node.button_pressed.connect(_on_controller_button.bind("left"))
	right_hand_node.button_pressed.connect(_on_controller_button.bind("right"))
	player_jumped.connect(func(): jump_in_progress = true)
	_update_locomotion()

func _update_locomotion() -> void:
	if not is_inside_tree():
		return
	for path in ["../LeftHand/MovementDirect", "../RightHand/MovementTurn"]:
		var provider := get_node_or_null(path)
		if provider != null:
			var moving: bool = path.contains("MovementDirect")
			provider.enabled = active and not (is_instance_valid(vehicles) and vehicles.seated()) and not (moving and feedback.combat_blocked()) and not (interface_move_captured if moving else interface_turn_captured) and combat_stick_side != ("left" if moving else "right") and medical_stick_side != ("left" if moving else "right")

func _on_controller_button(button: String, side := "left") -> void:
	if button == "menu_button":
		menu_requested.emit()
		return
	if is_instance_valid(vehicles) and vehicles.button(button,side):return
	if is_instance_valid(medic) and medic.button(button,side):return
	if feedback.life_locked:
		if button == "ax_button" and side == "right":
			feedback.request_life_action("medical_transport", preload("res://scripts/tracked_hand_input.gd").controller_tracked(right_hand_node) and bool(combat_tracking_context().tracked))
			return
		if button == "primary_click":
			feedback.last_action = {"action":"none"}
			return # Deliberate hold is sampled below.
	if button == "primary_click" and side != dominant_hand:
		if not interface_move_captured and not interface_turn_captured: request_jump()
		return

func _physics_process(delta: float) -> void:
	# Disabling virtual locomotion does not disable room-scale head tracking,
	# collision or gravity while the player interacts with a world-space menu.
	feedback.remove_offset()
	_update_locomotion()
	if is_instance_valid(vehicles) and vehicles.seated():
		velocity=Vector3.ZERO;ground_control_velocity=Vector2.ZERO
		feedback.vital.advance(delta);return
	super(delta)
	var offhand: XRController3D = right_hand_node if dominant_hand == "left" else left_hand_node
	var life_input_tracked: bool = preload("res://scripts/tracked_hand_input.gd").controller_tracked(offhand) and bool(combat_tracking_context().tracked)
	feedback.update_life_input(offhand.is_button_pressed("primary_click"), life_input_tracked and not interface_move_captured and not interface_turn_captured, delta)
	feedback.advance(delta)
	_update_locomotion()
	if global_position.y < void_floor_y:
		reset_spawn()

func _process(_delta: float) -> void:
	if not is_instance_valid(wrist_ham): return
	var hand: XRController3D = left_hand_node if dominant_hand == "left" else right_hand_node
	var tracked: bool = preload("res://scripts/tracked_hand_input.gd").controller_tracked(hand)
	var pose := hand.global_transform
	if is_instance_valid(combat_rig) and combat_rig.hand_target(dominant_hand) is Transform3D:
		pose = combat_rig.hand_target(dominant_hand)
	wrist_ham.side=dominant_hand
	wrist_ham.avatar=combat_rig.tracked_avatar if is_instance_valid(combat_rig) else null
	wrist_ham.update_readout(pose, camera_node.global_position, active and tracked)

func get_camera() -> XRCamera3D:
	return camera_node

func prepare_tracked_body() -> void:
	# Populate the full tracked capsule before the application's initial ground
	# sweep. Tracking poses remain untouched; only the collision body follows.
	feedback.remove_offset()
	_update_body_under_camera(1.0)
	feedback.advance(0)

func _source_support(point: Vector3, max_up: float, max_down: float) -> Dictionary:
	if not is_instance_valid(ground_provider):
		return {"valid": false}
	var context: Dictionary = ground_provider.collision_context(point)
	var allowed: Array = context.get("allowed_cell_ids", [])
	# Empty membership must not turn into unrestricted cross-storey lookup.
	if allowed.is_empty():
		return {"valid": false}
	var found: Dictionary = ground_provider.ground_support.sample_support(point, allowed, max_up, max_down, support_state)
	if bool(found.get("valid", false)):
		var capsule: Dictionary = ground_provider.ground_support.capsule_support(point, player_radius * XRServer.world_scale, allowed, max_up, max_down)
		found["body_height"] = float(capsule.get("body_height", found.height))
	return found

func _update_ground_information(delta: float) -> void:
	super(delta)
	var found := _source_support(global_position, support_contact_distance, support_contact_distance + player_radius)
	if bool(found.get("valid", false)) and not jump_in_progress:
		var distance := global_position.y - float(found.body_height)
		if absf(distance) <= support_contact_distance:
			support_state = found
			on_ground = true
			near_ground = true
			ground_vector = found.normal
			ground_angle = rad_to_deg(ground_vector.angle_to(up_gravity))
			if ground_physics == null:
				ground_physics = XRToolsGroundPhysics.get_physics(null, default_physics)
			return
	support_state = {"valid": false}

func _attach_source_floor() -> bool:
	var found := _source_support(global_position, support_snap_distance, support_snap_distance + player_radius)
	if not bool(found.get("valid", false)):
		return false
	var difference := float(found.body_height) - global_position.y
	if absf(difference) > support_snap_distance:
		return false
	if absf(difference) > 0.000001:
		var contact := KinematicCollision3D.new()
		var motion := Vector3.UP * difference
		if test_move(global_transform, motion, contact, safe_margin):
			motion = contact.get_travel()
		global_position += motion
	support_state = found
	return absf(global_position.y - float(found.body_height)) < support_contact_distance

func _constrain_source_motion(start: Vector3, motion: Vector3) -> Vector3:
	if not is_instance_valid(ground_provider):
		return motion
	var context: Dictionary = ground_provider.collision_context(start + motion)
	var allowed: Array = context.get("allowed_cell_ids", [])
	if allowed.is_empty():
		return motion
	var constrained: Dictionary = ground_provider.ground_support.constrain_motion(start, motion, allowed, player_radius * XRServer.world_scale, support_snap_distance)
	return constrained.get("motion", motion)

func _update_body_under_camera(delta: float) -> void:
	var before := global_position
	var previous := _source_support(before, support_contact_distance, support_contact_distance + player_radius)
	var supported: bool = (bool(previous.get("valid", false)) and absf(float(previous.body_height) - before.y) <= support_contact_distance) or step_solver.has_support(self, support_contact_distance)
	super(delta)
	if not supported or jump_in_progress or not _in_physics_movement:
		return
	var after_tracking := global_position
	if bool(previous.get("valid", false)):
		var physical_motion := global_position - before
		var permitted := _constrain_source_motion(before, physical_motion)
		global_position.x = before.x + permitted.x
		global_position.z = before.z + permitted.z
	var target := camera_node.global_position
	var forward := _estimate_body_forward_dir()
	if forward.length() > 0.01:
		target -= forward.normalized() * eye_forward_offset * player_radius * XRServer.world_scale
	var remaining := target - global_position
	remaining.y = 0
	if bool(previous.get("valid", false)):
		remaining = _constrain_source_motion(global_position, remaining)
	# Physical translation uses the same bounded stair sweep as controller
	# motion. Only vertical environmental correction is carried to XROrigin;
	# horizontal head movement already came from tracking.
	if remaining.length_squared() > 1e-12 and step_solver.step_up(self, remaining, support_snap_distance):
		roomscale_steps += 1
		steps_up += 1
	if not _attach_source_floor():
		if step_solver.step_down(self, support_snap_distance):
			steps_down += 1
	origin_node.global_position.y += global_position.y - after_tracking.y

func move_player(requested_velocity: Vector3) -> Vector3:
	var supported: bool = on_ground or bool(support_state.get("valid", false)) or step_solver.has_support(self, support_contact_distance)
	if on_ground and requested_velocity.y <= 0:
		jump_in_progress = false
	var before := global_position
	var step_velocity := Vector3(requested_velocity.x, 0, requested_velocity.z)
	if active and supported and not jump_in_progress and ground_control_velocity.length() >= 0.1:
		var camera_basis := camera_node.global_basis
		var intent := (camera_basis.z.slide(up_gravity).normalized() * -ground_control_velocity.y + camera_basis.x.slide(up_gravity).normalized() * ground_control_velocity.x) * XRServer.world_scale
		if bool(support_state.get("valid", false)) or intent.length_squared() > step_velocity.length_squared():
			step_velocity = intent
	var delta := get_physics_process_delta_time()
	if bool(support_state.get("valid", false)) and not jump_in_progress and ground_control_velocity.length() < 0.1 and ground_physics != null and ground_physics.stop_on_slope:
		# The source plane already provides vertical support. Do not turn the
		# addon gravity impulse into tangential downhill motion when resting.
		step_velocity = Vector3.ZERO
	var horizontal := step_velocity * delta
	if bool(support_state.get("valid", false)) and not jump_in_progress:
		horizontal = _constrain_source_motion(before, horizontal)
		step_velocity = horizontal / delta
		requested_velocity.x = step_velocity.x
		requested_velocity.z = step_velocity.z
	if supported and not jump_in_progress:
		var destination := _source_support(before + horizontal, support_snap_distance, support_snap_distance + player_radius)
		if bool(destination.get("valid", false)):
			var rise := float(destination.body_height) - before.y
			if absf(rise) <= support_snap_distance:
				requested_velocity = step_velocity + Vector3.UP * rise / delta
	var result: Vector3 = super(requested_velocity)
	var after_slide := global_position
	if supported and not jump_in_progress:
		var travelled := global_position - before
		travelled.y = 0
		var direction := horizontal.normalized()
		var blocked := maxf(0, horizontal.length() - travelled.dot(direction))
		# Floating-point tolerance only: no fixed millimeter movement gate.
		if blocked > 0.0000001 and step_solver.step_up(self, direction * blocked, support_snap_distance):
			steps_up += 1
			result.x = step_velocity.x
			result.z = step_velocity.z
			result.y = 0
		if _attach_source_floor():
			result.y = 0
		elif step_solver.step_down(self, support_snap_distance):
			steps_down += 1
			result.y = 0
	if not _in_physics_movement:
		origin_node.global_position += global_position - after_slide
	velocity = result
	return result

func set_avatar_height(_height: float) -> void:
	# Physical tracking determines height; species must never rescale the HMD.
	pass

func reset_spawn() -> void:
	if origin_node == null:
		return
	feedback.reset()
	velocity = Vector3.ZERO
	jump_in_progress = false
	on_ground = false
	near_ground = false
	support_state = {"valid": false}
	ground_control_velocity = Vector2.ZERO
	teleport(Transform3D(Basis(Vector3.UP, spawn_yaw), spawn_point))

func apply_world_correction(delta: Vector3) -> void:
	feedback.remove_offset()
	on_ground = false
	near_ground = false
	support_state = {"valid": false}
	if delta.is_zero_approx():
		return
	var target := global_transform
	target.origin += delta
	teleport(target)
	velocity = Vector3.ZERO

func tracked_height() -> float:
	return _collision_node.shape.height if _collision_node != null else 0.0

func combat_tracking_context() -> Dictionary:
	var tracker = XRServer.get_tracker("head")
	var pose: XRPose = tracker.get_pose("default") if tracker != null else null
	var tracked := pose != null and pose.has_tracking_data and is_instance_valid(camera_node)
	return {"tracked":tracked,"grounded":on_ground and not jump_in_progress and not (is_instance_valid(vehicles) and vehicles.seated()),
		"eye_height":(camera_node.global_position-global_position-Vector3.UP*feedback.applied_offset).dot(up_gravity.normalized()) if tracked else NAN}
