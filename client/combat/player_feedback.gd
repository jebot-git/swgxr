extends RefCounted
## Shared presentation orchestration. No server posture is changed here.
signal recovery_requested(posture: int, automatic: bool)
signal life_action_requested(action: String)
const LIFE_HOLD_SECONDS := 1.0
const FORCE_HOLD_SECONDS := 3.0
const ForceOfWill = preload("res://combat/force_of_will.gd")
var force_of_will: Dictionary = {}
var force_available := false
var force_hold_seconds := 0.0
var force_hold_armed := false
const LIFE_VIEW_SECONDS := 0.32
var motion := SwgViewPosture.new()
var stance = preload("res://combat/firing_posture.gd").new()
var body: CharacterBody3D
var camera: Camera3D
var origin: XROrigin3D
var applied_offset := 0.0
var character_id := ""
var observed_posture := -1
var life_locked := false
var feigning_death := false
var feign_available := false
var feign_pose = preload("res://smuggler/feign_pose.gd").new()
var local_prediction := true
var last_action: Dictionary = {}
var source: Dictionary = {}
var locomotion:Dictionary={}
var armour:Dictionary={}
var performer: Node3D
var life_action_pending := false
var life_action := ""
var life_status := ""
var recovery_remaining_seconds := -1.0
var recovery_requested_authoritatively := false
var cloning := false
var life_hold_seconds := 0.0
var life_jump_armed := false
var life_view_offset := 0.0
var life_view_from := 0.0
var life_view_time := LIFE_VIEW_SECONDS
var life_fade_alpha := 0.0
var spice=preload("res://spice/state.gd").new()
var spice_screen:CompositorEffect
var vital = preload("res://combat/vital_feedback.gd").new()
var life_label: Label3D

func configure(player: CharacterBody3D, view: Camera3D, xr: XROrigin3D = null) -> void:
	body = player
	camera = view
	origin = xr
	vital.configure(camera)
	spice_screen=preload("res://spice/screen_effect.gd").new();spice_screen.attach(camera)
	life_label = Label3D.new()
	life_label.name = "AuthoritativeLifeFeedback"
	life_label.font = load("res://resources/fonts/Jupiteroid-Regular.ttf")
	life_label.font_size = 26
	life_label.pixel_size = 0.00065
	life_label.outline_size = 6
	life_label.modulate = Color(0.55, 0.92, 1.0)
	life_label.no_depth_test = true
	life_label.position = Vector3(0, -0.08, -0.8)
	life_label.visible = false
	camera.add_child(life_label)
	var fade := camera.get_node_or_null("Fade")
	if fade != null: fade.layers = 1 # Local head layer is excluded by the XR camera.
	var path := "res://../runtime/assets/combat/player_postures/catalog.json"
	if FileAccess.file_exists(path):
		source = JSON.parse_string(FileAccess.get_file_as_string(path))
		var curve := PackedVector2Array()
		for point in source.get("jump", {}).get("height_curve", []): curve.append(Vector2(point[0], point[1]))
		motion.configure_jump(curve)

func physical() -> Dictionary:
	if is_instance_valid(origin):
		var context: Dictionary = body.combat_tracking_context()
		var pose: String = stance.update_tracked(context)
		context["posture"] = 2 if pose == "prone" else 1 if pose == "crouched" else 0
		return context
	return {"posture":body.get_posture(), "eye_height":camera.position.y - applied_offset,
		"grounded":body.get_grounded() if body.has_method("get_grounded") else body.is_on_floor(), "tracked":true}

func reset() -> void:
	vital.reset();spice.reset();locomotion={};armour={}
	if is_instance_valid(body) and body.has_method("set_locomotion_profile"):body.set_locomotion_profile({})
	if spice_screen!=null:spice_screen.set_policy(spice.policy())
	remove_offset()
	motion.reset()
	life_locked = false
	feigning_death = false
	feign_available = false
	feign_pose.reset()
	observed_posture = -1
	last_action = {}
	life_action_pending = false
	life_action = ""
	life_status = ""
	recovery_remaining_seconds = -1.0
	recovery_requested_authoritatively = false
	cloning = false
	force_of_will = {}
	force_available = false
	force_hold_seconds = 0.0
	force_hold_armed = false
	life_hold_seconds = 0.0
	life_jump_armed = false
	life_view_offset = 0.0
	life_view_from = 0.0
	life_view_time = LIFE_VIEW_SECONDS
	set_life_fade(0.0)
	if is_instance_valid(life_label): life_label.visible = false

func observe(context: Dictionary) -> void:
	var id := str(context.get("character_id", ""))
	if id != character_id:
		reset()
		character_id = id
	if context.get("locomotion") is Dictionary:
		locomotion=context.locomotion.duplicate(true)
		if is_instance_valid(body) and body.has_method("set_locomotion_profile"):body.set_locomotion_profile(locomotion)
		var solver:Variant=body.get("step_solver") if is_instance_valid(body) else null
		var swim_height:=float(locomotion.get("swim_height",NAN))
		if solver!=null and solver.has_method("set_swim_height") and is_finite(swim_height) and swim_height>=0:solver.set_swim_height(swim_height)
	feign_available=bool(context.get("feign_death_available",false))
	if context.get("armour") is Dictionary:
		var candidate: Dictionary = context.armour
		var valid := int(candidate.get("version", 0)) == 1
		for key in ["movement_scale", "output_scale", "recovery_scale"]:
			var value := float(candidate.get(key, NAN))
			valid = valid and is_finite(value) and value >= 0.75 and value <= 1
		if valid: armour = candidate.duplicate(true)
	if context.get("spice") is Dictionary:spice.observe(context.spice)
	vital.prefer_latest_heal=spice.is_phase("crash_n_burn","withdrawal")
	vital.observe(context.get("vital_feedback",{}))
	if not context.has("posture"): return
	var posture := int(context.posture)
	var countdown = context.get("recovery_remaining_seconds", -1.0)
	recovery_remaining_seconds = float(countdown) if (countdown is float or countdown is int) and is_finite(float(countdown)) else -1.0
	recovery_requested_authoritatively = bool(context.get("recovery_requested",false))
	cloning = bool(context.get("cloning",false))
	force_of_will = context.force_of_will.duplicate(true) if context.get("force_of_will") is Dictionary else {}
	force_available = ForceOfWill.available(context)
	if not force_available:
		force_hold_seconds = 0.0
		force_hold_armed = false
	var feigning:bool=bool(context.get("feigning_death",false)) and posture!=14
	if posture == observed_posture and feigning==feigning_death: return
	feigning_death=feigning
	var was_locked := life_locked
	observed_posture = posture
	life_locked = posture in [13, 14] and not feigning_death
	if was_locked or life_locked:
		life_view_from = life_view_offset
		life_view_time = 0.0
		life_hold_seconds = 0.0
		life_jump_armed = false
		force_hold_seconds = 0.0
		force_hold_armed = false
		life_action_pending = false
		life_action = ""
		life_status = ""
		motion.reset()
	if posture == 12: receive_knockdown()
	else: motion.clear_knockdown()
	update_life_label()

func update_life_input(pressed: bool, tracked: bool, delta: float) -> void:
	if not life_locked or observed_posture != 13 or not tracked or not body.active or cloning or not is_finite(delta) or delta < 0 or delta > 0.25:
		life_hold_seconds = 0.0
		life_jump_armed = false
		force_hold_seconds = 0.0
		force_hold_armed = false
		return
	if not pressed:
		life_jump_armed = true
		life_hold_seconds = 0.0
		force_hold_armed = force_available
		force_hold_seconds = 0.0
	else:
		# Continue the longer hold across the ordinary recovery acknowledgement.
		if force_hold_armed and force_available:
			force_hold_seconds = minf(FORCE_HOLD_SECONDS, force_hold_seconds + minf(delta, 0.1))
		if life_jump_armed and not life_action_pending and not recovery_requested_authoritatively:
			life_hold_seconds += minf(delta, 0.1)
			if life_hold_seconds >= LIFE_HOLD_SECONDS:
				life_jump_armed = false
				request_life_action("recover", tracked)
		if force_hold_armed and force_available and force_hold_seconds >= FORCE_HOLD_SECONDS and not life_action_pending:
			force_hold_armed = false
			request_life_action("force_of_will", tracked)
	update_life_label()

func request_life_action(action: String, tracked: bool = true) -> bool:
	if not life_locked or life_action_pending or cloning or not tracked or not body.active: return false
	if action != "medical_transport" and not (action in ["recover", "force_of_will"] and observed_posture == 13): return false
	if action == "force_of_will" and not force_available: return false
	if action != "recover": force_hold_armed = false
	if action == "recover" and recovery_requested_authoritatively: return false
	life_action_pending = true
	life_action = action
	life_hold_seconds = 0.0
	life_status = "Requesting Force of Will…" if action == "force_of_will" else "Requesting recovery…" if action == "recover" else "Requesting medical transport…"
	update_life_label()
	life_action_requested.emit(action)
	return true

func resolve_life_action(success: bool, message: String = "") -> void:
	# A reply acknowledges an intent. Only observe() changes the confirmed pose.
	var previous := life_action
	if not success:
		force_hold_armed = false
		force_hold_seconds = 0.0
		life_jump_armed = false
	life_action_pending = false
	life_action = ""
	life_status = message if not message.is_empty() else ("Waiting for CoreCU recovery…" if previous in ["recover", "force_of_will"] else "Waiting for CoreCU medical transport…") if success else "CoreCU rejected the request. Release the control before retrying."
	update_life_label()

func life_readout() -> Dictionary:
	return {"locked":life_locked, "posture":observed_posture, "pending":life_action_pending,
		"action":life_action, "status":life_status, "hold_progress":clampf(life_hold_seconds/LIFE_HOLD_SECONDS,0,1),
		"recovery_remaining_seconds":recovery_remaining_seconds,
		"recovery_requested":recovery_requested_authoritatively,"cloning":cloning,
		"force_of_will_available":force_available,"force_of_will_progress":clampf(force_hold_seconds/FORCE_HOLD_SECONDS,0,1),
		"title":"Incapacitated" if observed_posture == 13 else "Dead"}

func update_life_label() -> void:
	if not is_instance_valid(life_label): return
	life_label.visible = life_locked or feigning_death
	if feigning_death:
		life_label.text="FEIGN DEATH\nStand upright to resume movement"
		return
	if not life_locked: return
	var lines: Array[String] = ["INCAPACITATED" if observed_posture == 13 else "DEAD"]
	if not life_status.is_empty(): lines.append(life_status)
	if recovery_requested_authoritatively and recovery_remaining_seconds >= 0: lines.append("Recovery: %.1f s" % recovery_remaining_seconds)
	if cloning: lines.append("CoreCU medical transport in progress…")
	if not life_action_pending and not cloning:
		if observed_posture == 13:
			if not recovery_requested_authoritatively: lines.append("Hold offhand stick: recover  %d%%" % roundi(100.0*life_hold_seconds/LIFE_HOLD_SECONDS))
			if force_available: lines.append("Keep holding offhand stick for 3 s: Force of Will  %d%%" % roundi(100.0*force_hold_seconds/FORCE_HOLD_SECONDS))
			elif bool(force_of_will.get("learned",false)) and float(force_of_will.get("cooldown_remaining_seconds",0)) > 0: lines.append("Force of Will: %.0f s cooldown" % float(force_of_will.cooldown_remaining_seconds))
			lines.append("A: give up and respawn at a medical facility")
		else: lines.append("A: respawn at a medical facility")
	life_label.text = "\n".join(lines)

func set_life_fade(alpha: float) -> void:
	life_fade_alpha = alpha
	if not is_instance_valid(camera): return
	var fade := camera.get_node_or_null("Fade")
	if fade != null: fade.set_fade_level("authoritative_life_feedback", Color(0, 0, 0, alpha))

func receive_knockdown() -> bool:
	if life_locked or feigning_death: return false
	return motion.knock_down(int(physical().posture))

func request_jump() -> Dictionary:
	var context := physical()
	last_action = motion.press_jump(int(context.posture), bool(context.grounded), body.active and not life_locked and not feigning_death and bool(context.tracked))
	if last_action.action == "recover":
		recovery_requested.emit(int(last_action.posture), false)
		# Explicit local prediction until a continuous authoritative combat
		# transport supplies resolve_recovery(success). No server write occurs.
		if local_prediction: motion.resolve_recovery(true)
	return last_action

func remove_offset() -> void:
	if is_instance_valid(origin): origin.global_position.y -= applied_offset
	elif is_instance_valid(body): body.presentation_height = 0.0
	applied_offset = 0.0

func advance(delta: float) -> void:
	vital.advance(delta);spice.advance(delta)
	vital.prefer_latest_heal=spice.is_phase("crash_n_burn","withdrawal")
	if spice_screen!=null:spice_screen.set_policy(spice.policy())
	var context := physical()
	if is_instance_valid(origin):feign_pose.sample(context,camera.global_basis,stance.standing_eye_height,delta)
	var state: Dictionary = motion.advance(delta, 0 if life_locked else int(context.posture), float(context.eye_height), bool(context.tracked))
	if state.get("auto_prone_recovery", false): recovery_requested.emit(2, true)
	var desired := 0.0 if feigning_death else float(state.offset)
	if life_locked or life_view_time < LIFE_VIEW_SECONDS:
		life_view_time = minf(LIFE_VIEW_SECONDS, life_view_time + clampf(delta, 0.0, 0.1))
		var progress := life_view_time / LIFE_VIEW_SECONDS
		var target := (minf(0.0, 0.28 - float(context.eye_height)) if bool(context.tracked) else life_view_offset) if life_locked else 0.0
		life_view_offset = lerpf(life_view_from, target, smoothstep(0.0, 1.0, progress))
		desired = life_view_offset
		set_life_fade(sin(progress * PI) if progress < 1.0 else 0.0)
	else:
		life_view_offset = 0.0
		set_life_fade(0.0)
	var from := camera.global_position - Vector3.UP * applied_offset
	# Do not let a cosmetic rise move the view through solid ceilings.
	if absf(desired) > 0.0001:
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * (desired + signf(desired) * 0.06), 7, [body.get_rid()])
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): desired = signf(desired) * maxf(0, from.distance_to(hit.position) - 0.06)
		desired = maxf(desired, body.global_position.y + 0.15 - from.y)
	if is_instance_valid(origin): origin.global_position.y += desired - applied_offset
	else: body.presentation_height = desired
	applied_offset = desired
	update_life_label()

func combat_blocked() -> bool:
	return life_locked or feigning_death or motion.is_knocked_down()

func animation_context() -> Dictionary:
	var result := {"knocked_down":motion.is_knocked_down() or life_locked, "jump_time":motion.get_jump_time(),
		"life_locked":life_locked, "life_posture":observed_posture,
		"life_pose":"dead" if observed_posture == 14 else "incapacitated" if observed_posture == 13 else "",
		"life_state":"dead" if observed_posture == 14 else "incapacitated" if observed_posture == 13 else "",
		"life_animation":"dead" if observed_posture == 14 else "incapacitated" if observed_posture == 13 else "",
		"life_pose_frozen":observed_posture == 14, "life_pose_time":0.0}
	if feigning_death:
		result.merge({"feigning_death":true,"life_locked":true,"life_pose":"incapacitated","life_state":"incapacitated","life_animation":"incapacitated","life_pose_frozen":false},true)
	if is_instance_valid(performer) and not combat_blocked(): result.merge(performer.animation_context())
	return result
