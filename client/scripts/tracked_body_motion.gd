extends RefCounted
## Original SWG lower-body/spine clips, sampled separately from tracked limbs.
var avatar: Node3D
var skeleton: Skeleton3D
var sampler := SwgBodyMotion.new()
var state := "idle"
var time := 0.0
var previous_state := ""
var previous_time := 0.0
var transition := 1.0
var crouched := false
var posture = preload("res://combat/firing_posture.gd").new()
var prone_blend := 0.0
var profiles: Dictionary = {}
var airborne_time := 0.0
var was_grounded := true
var report: Dictionary = {}

func configure(source: Node3D) -> bool:
	posture.set_standing_eye_height(1.0) # Input is already normalized to calibration.
	avatar = source
	skeleton = avatar.skeleton
	return sampler != null and sampler.configure(skeleton)

func clip(key: String) -> Animation:
	# The original stationary crouch is a one-knee kneel. Physical HMD
	# crouching uses standing source posture plus tracked torso/leg IK.
	if key == "crouch":
		key = "idle"
	if not avatar.ensure_animation(key):
		return null
	return avatar.animation_player.get_animation(key)

func profile(key: String) -> Dictionary:
	if profiles.has(key):
		return profiles[key]
	var animation := clip(key)
	var minimum := {"left":INF, "right":INF}
	if animation != null:
		# Source contact heights differ from the bind pose. Measure one cycle
		# once, so floor IK preserves authored foot lift rather than flattening it.
		for frame in range(33):
			sampler.sample(animation, animation.length * frame / 33.0)
			for side in ["left", "right"]:
				var ankle := skeleton.find_bone("lankle" if side == "left" else "rankle")
				minimum[side] = minf(minimum[side], skeleton.get_bone_global_pose(ankle).origin.y)
	profiles[key] = minimum
	return minimum

func advance(delta: float, local_velocity: Vector3, grounded: bool, eye_ratio: float, visual_scale: float, presentation: Dictionary = {}) -> Dictionary:
	var dt := clampf(delta, 0, 0.1)
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	var physical: String = posture.update_tracked({"tracked":is_finite(eye_ratio),"grounded":grounded,"eye_height":eye_ratio})
	crouched = physical == "crouched"
	var prone := physical == "prone"
	var knocked: bool = presentation.get("knocked_down", false)
	var jump_time := float(presentation.get("jump_time", -1))
	prone_blend = move_toward(prone_blend,1.0 if prone or knocked else 0.0,dt/0.18)
	var desired := "idle"
	if presentation.get("life_locked",false):
		desired = str(presentation.get("life_animation","incapacitated"))
	elif knocked:
		desired = "knockdown"
	elif jump_time >= 0 or not grounded:
		desired = "jump"
	elif not str(presentation.get("performance_clip","")).is_empty():
		desired = str(presentation.performance_clip)
	elif prone:
		desired = "crawl" if speed > 0.18 else "prone"
	elif crouched:
		desired = "crouch_walk" if speed > 0.18 else "crouch"
	elif speed > 0.18:
		if absf(local_velocity.x) > absf(local_velocity.z) * 0.9:
			desired = "strafe_right" if local_velocity.x > 0 else "strafe_left"
		elif local_velocity.z > 0.1:
			desired = "backpedal"
		else:
			desired = "run" if speed > 3.2 else "walk"
	if clip(desired) == null:
		desired = "idle"
	var changed := desired != state
	if changed:
		previous_state = state
		previous_time = time
		state = desired
		time = 0.0
		transition = 0.0
	var animation := clip(state)
	if animation == null:
		return {"state":state, "valid":false}
	var minimum := profile(state)
	var from_clip: Animation = null
	var from_minimum := minimum
	if not previous_state.is_empty() and transition < 1.0:
		from_clip = clip(previous_state)
		from_minimum = profile(previous_state)
	var source_speeds: Dictionary = avatar.get("clip_speeds") if avatar.get("clip_speeds") is Dictionary else {}
	var reference_speed := float(source_speeds.get(state, {"walk":1.55,"run":5.13,"strafe_left":2.07,"strafe_right":2.16,"backpedal":1.35,"crouch_walk":1.63,"crawl":0.5}.get(state, 0.0)))
	var rate := float(avatar.clip_rates.get(state, 1.0))
	if reference_speed > 0.0:
		rate *= clampf(speed / maxf(0.1, reference_speed * visual_scale), 0.25, 2.8)
	time += dt * rate
	if state == "dead":
		time = 0.0
	elif state.begins_with("perform_"):
		time = fmod(float(presentation.get("performance_time",0)),animation.length) if animation.loop_mode != Animation.LOOP_NONE else minf(float(presentation.get("performance_time",0)),animation.length)
	elif state == "jump" and jump_time >= 0:
		time = minf(jump_time, animation.length)
	elif state == "jump":
		airborne_time = airborne_time + dt if not was_grounded else 0.0
		var phases: Dictionary = avatar.jump_phases
		var apex := float(phases.get("apex", animation.length * 0.5))
		time = minf(apex, float(phases.get("takeoff", 0)) + airborne_time)
		if local_velocity.y <= 0:
			time = minf(float(phases.get("land", apex)), apex + maxf(0, airborne_time - apex))
	elif animation.loop_mode != Animation.LOOP_NONE:
		time = fposmod(time, animation.length)
	else:
		time = minf(time, animation.length)
	was_grounded = grounded
	transition = minf(1.0, transition + dt / 0.18)
	var blend := smoothstep(0.0, 1.0, transition)
	var result: Dictionary = sampler.sample(animation, time, from_clip, previous_time, blend)
	var lifts := {}
	for side in ["left", "right"]:
		var ankle := skeleton.find_bone("lankle" if side == "left" else "rankle")
		var baseline := lerpf(float(from_minimum[side]), float(minimum[side]), blend)
		lifts[side] = maxf(0.0, skeleton.get_bone_global_pose(ankle).origin.y - baseline) if state not in ["idle","crouch","prone"] else 0.0
	report = {"valid":result.get("valid", false), "state":state, "time":time, "rate":rate, "speed":speed, "crouched":crouched,"prone":prone,"prone_blend":prone_blend, "grounded":grounded, "changed":changed, "blend":blend, "foot_lift":lifts}
	return report
