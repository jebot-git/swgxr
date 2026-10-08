extends "res://scripts/service_peer.gd"
## Original source avatar presentation only. No collision, native health mutation,
## local tracking access, or movement authority is owned by this node.
var goal := Transform3D.IDENTITY
var initialized := false
var pose_age := 100.0
var tracking_goal: Dictionary = {}
var tracking_current: Dictionary = {}
var animation_accumulator := 0.0
var animation_interval := 0.0
var life_pose_time := 0.0
var previous_life_state := ""
var pose_report: Dictionary = {}
var appearance_cache: RefCounted

func configure(path := "") -> void:
	if path.is_empty(): path = ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json")
	catalog_path = path
	if not Avatar.catalog_cache.has(path): Avatar.catalog_cache[path] = Avatar.read_json(path)
	catalog = Avatar.catalog_cache[path]
	if label == null:
		label = Label3D.new()
		label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size = 28
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.1
		add_child(label)

func apply_peer(value: Dictionary) -> void:
	var point: Variant = value.get("position")
	var heading := float(value.get("heading_radians", 0.0))
	if not point is Vector3 or not point.is_finite() or not is_finite(heading):
		visible = false
		return
	var old_transform := global_transform
	var old_key := appearance_key
	var requested_key := JSON.stringify(value.get("appearance", {}))
	var cached: Node3D
	if requested_key != appearance_key and appearance_cache != null:
		cached = appearance_cache.instantiate(value.get("appearance", {}))
		if cached != null:
			if is_instance_valid(avatar): remove_child(avatar); avatar.queue_free()
			avatar = cached; add_child(avatar)
			appearance_key = requested_key
			report = avatar.report.duplicate(true)
			ik_ready = solver.configure(avatar.skeleton)
	# Base resolves only the exact original species, customization, hair and
	# authoritative equipment. Missing imported art stays explicitly diagnosed.
	super.apply_peer(value)
	if old_key != appearance_key and cached == null and appearance_cache != null and is_instance_valid(avatar):
		appearance_cache.remember(value.get("appearance", {}), avatar)
	goal = Transform3D(Basis(Vector3.UP, heading), point)
	var teleport := not initialized or old_transform.origin.distance_to(point) > 8.0
	global_transform = goal if teleport else old_transform
	initialized = true
	if teleport or old_key != appearance_key:
		tracking_current.clear()
		solver.reset_smoothing()
	tracking_goal.clear()
	pose_age = maxf(0.0, float(value.get("pose_age_ms", 0.0)) / 1000.0)
	var incoming: Variant = value.get("tracking", {})
	if incoming is Dictionary and pose_age <= 0.75:
		for key in ["head", "left_hand", "right_hand"]:
			var pose: Variant = incoming.get(key)
			if pose is Transform3D and pose.origin.is_finite() and pose.basis.is_finite() and absf(pose.basis.determinant()) > 0.01 and pose.origin.distance_to(point) <= 3.0:
				tracking_goal[key] = Transform3D(pose.basis.orthonormalized(), pose.origin)
	for key in tracking_current.keys():
		if not tracking_goal.has(key): tracking_current.erase(key)
	if is_instance_valid(avatar):
		# Face clips must obey the same bounded animation update budget as body.
		if avatar.face_player != null:
			avatar.face_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	refresh_life_label()

func life_state() -> String:
	if bool(row.get("dead", false)) or str(row.get("life_state", "")).to_lower() == "dead" or int(row.get("posture", 0)) == 14:
		return "dead"
	if bool(row.get("feigning_death",false)) or bool(row.get("incapacitated", false)) or str(row.get("life_state", "")).to_lower() == "incapacitated" or int(row.get("posture", 0)) == 13:
		return "incapacitated"
	return ""

func refresh_life_label() -> void:
	if label == null: return
	label.text = str(row.get("name", "Player"))
	if avatar == null: label.text += "\nOriginal appearance unavailable"
	elif not bool(avatar.report.get("equipment_complete", true)):
		label.text += "\nSome original equipment unavailable"
	var state := life_state()
	if not state.is_empty(): label.text += "\n" + state.capitalize()

func advance(delta: float) -> void:
	# apply_peer's base invokes this with zero before assigning the new target.
	if delta <= 0.0: return
	elapsed += delta
	sample_age += delta
	pose_age += delta
	if initialized:
		global_transform = global_transform.interpolate_with(goal, 1.0 - exp(-delta * 18.0))
	if not is_instance_valid(avatar): return
	animation_accumulator += delta
	if animation_accumulator < animation_interval: return
	var step := animation_accumulator
	animation_accumulator = 0.0
	var state := life_state()
	if state != previous_life_state:
		previous_life_state = state
		life_pose_time = 0.0
		solver.reset_smoothing()
	if not state.is_empty():
		life_pose_time += step
		pose_report = avatar.sample_life_pose(state, life_pose_time)
		if not bool(pose_report.get("valid", false)):
			label.text = str(row.get("name", "Player")) + "\n" + state.capitalize() + " · original pose unavailable"
		if not bool(row.get("feigning_death",false)) or state=="dead":return
	else:
		var motion := velocity if sample_age < 0.5 else Vector3.ZERO
		var posture := clampi(int(row.get("posture", 0)), 0, 3)
		if posture == 0 and not tracking_goal.is_empty() and pose_age <= 0.75:
			posture = clampi(int(row.get("physical_posture", 0)), 0, 2)
		avatar.update_motion(step, motion.length(), {"velocity": global_basis.inverse() * motion, "grounded": bool(row.get("grounded", true)), "posture": posture})
		if avatar.animation_player != null: avatar.animation_player.advance(step)
		if avatar.face_player != null: avatar.face_player.advance(step)
		pose_report = {"tracked": false, "motion_state": avatar.motion_state}
	if not ik_ready or pose_age > 0.75 or tracking_goal.is_empty(): return
	var targets: Dictionary = {}
	var inverse: Transform3D = avatar.skeleton.global_transform.affine_inverse()
	for key: String in tracking_goal:
		var target: Transform3D = tracking_goal[key]
		var previous: Transform3D = tracking_current.get(key, target)
		tracking_current[key] = previous.interpolate_with(target, 1.0 - exp(-step * 24.0))
		var local: Transform3D = inverse * tracking_current[key]
		local.basis = local.basis.orthonormalized()
		targets[key] = local
	pose_report = solver.solve(targets, maxf(step, 1.0 / 120.0))
	pose_report["tracked"] = true
