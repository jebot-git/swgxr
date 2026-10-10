extends Node3D
## Presentation only: never writes to the XR origin, camera, controllers or body.
## Retarget source anatomy to standard OpenXR grip poses (no runtime offsets).
## https://registry.khronos.org/OpenXR/specs/1.0-khr/html/xrspec.html#semantic-paths-standard-pose-identifiers
var combat_rig: Node3D
var avatar: Node3D
var rig: XROrigin3D
var body: CharacterBody3D
var camera: XRCamera3D
var skeleton: Skeleton3D
const BodyMotion = preload("res://scripts/tracked_body_motion.gd")
var body_motion := BodyMotion.new()
var motion_ready := false
@export_range(0.0, 1.0) var torso_animation_weight := 0.35
var standing_eye_height := 1.7
var previous_body_position := Vector3.ZERO
var have_body_position := false
var measured_velocity := Vector3.ZERO
var planted_feet: Dictionary = {}
const HandInput = preload("res://scripts/tracked_hand_input.gd")
var fingers := SwgFingerRetargeter.new()
var solver := SwgTrackedIK.new()
var stance_solver := SwgTrackedIK.new()
var stance_ready := false
var calibrated := false
var fit_scale := 1.0
var eye_rest := Vector3.ZERO
var eye_in_head := Vector3.ZERO
var head_rest := Transform3D.IDENTITY
var grip_offsets: Dictionary = {}
var weapon_hand_offsets: Dictionary = {}
var ankle_rest: Dictionary = {}
var leg_lengths: Dictionary = {}
var last_report: Dictionary = {}
var heading := 0.0
var original_cull_mask := -1
var life_pose_locked := false
var life_pose_state := ""
var life_pose_time := 0.0
var life_pose_heading := 0.0
var life_pose_anchor := Vector3.ZERO

func configure(source_avatar: Node3D, origin: XROrigin3D) -> bool:
	avatar = source_avatar
	rig = origin
	body = rig.get_node("PlayerBody")
	camera = rig.get_node("XRCamera3D")
	skeleton = avatar.skeleton
	avatar.set_tracking_mode(true)
	if not solver.configure(skeleton):
		return false
	if not fingers.configure(skeleton):
		return false
	head_rest = skeleton.get_bone_global_rest(skeleton.find_bone("head"))
	eye_rest = head_rest.origin + Vector3(0, 0.075, -0.09)
	for pair in [["leye", "reye"], ["stalk_l", "stalk_r"]]:
		var left := skeleton.find_bone(pair[0])
		var right := skeleton.find_bone(pair[1])
		if left >= 0 and right >= 0:
			eye_rest = (skeleton.get_bone_global_rest(left).origin + skeleton.get_bone_global_rest(right).origin) * 0.5
			break
	eye_in_head = head_rest.affine_inverse() * eye_rest
	for side in ["left", "right"]:
		grip_offsets[side] = grip_to_wrist("l" if side == "left" else "r")
		var hold := skeleton.find_bone("hold_l" if side=="left" else "hold_r")
		var wrist := skeleton.find_bone("lwrist" if side=="left" else "rwrist")
		weapon_hand_offsets[side] = skeleton.get_bone_global_rest(hold).affine_inverse() * skeleton.get_bone_global_rest(wrist) if hold>=0 else grip_offsets[side]
		ankle_rest[side] = skeleton.get_bone_global_rest(skeleton.find_bone("lankle" if side == "left" else "rankle"))
		var prefix := "l" if side == "left" else "r"
		var hip := skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"thigh")).origin
		var knee := skeleton.get_bone_global_rest(skeleton.find_bone(prefix+"shin")).origin
		leg_lengths[side] = hip.distance_to(knee) + knee.distance_to(ankle_rest[side].origin)
	# Ground IK refines the original gait and physical crouch presentation.
	# Legs remain inferred, with OpenXR retaining ownership of head and hands.
	stance_ready = stance_solver.configure(skeleton, {"left_upper":"lthigh", "left_lower":"lshin", "left_hand":"lankle", "right_upper":"rthigh", "right_lower":"rshin", "right_hand":"rankle"})
	motion_ready = body_motion.configure(avatar)
	if not motion_ready:
		return false
	original_cull_mask = camera.cull_mask
	camera.set_cull_mask_value(2, false)
	process_priority = 100
	process_physics_priority = 100 # Sample after XR Tools moves the physical body.
	visible = false
	return true

func limit_weapon_pose(side: String, pose: Transform3D, support_pose: Variant = null) -> Transform3D:
	if not is_instance_valid(skeleton) or not calibrated: return pose
	var local := skeleton.global_transform.affine_inverse()*pose
	local.basis=local.basis.orthonormalized()
	var wrist: Transform3D=local*weapon_hand_offsets[side]
	var bounded: Transform3D
	if support_pose is Transform3D:
		var offhand := "left" if side=="right" else "right"
		var support: Transform3D=skeleton.global_transform.affine_inverse()*support_pose
		support.basis=support.basis.orthonormalized()
		bounded=solver.limit_hand_pair(side,wrist,support*weapon_hand_offsets[offhand])
	else:
		bounded=solver.limit_hand_target(side,wrist)
	var result:=pose
	result.origin+=skeleton.global_basis*(bounded.origin-wrist.origin)
	return result

func grip_to_wrist(prefix: String) -> Transform3D:
	var wrist := skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "wrist"))
	var index := skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "index01")).origin
	var ring := skeleton.get_bone_global_rest(skeleton.find_bone(prefix + "ring01")).origin
	var fingers := (index + ring) * 0.5
	# OpenXR grip -Z points from little finger toward index; +Y faces the wrist.
	# Construct the frame from each source rig, including asymmetric alien wrists.
	var z := (ring - index).normalized()
	var y := (wrist.origin - fingers).slide(z).normalized()
	var x := y.cross(z).normalized()
	y = z.cross(x).normalized()
	var grip := Transform3D(Basis(x, y, z), wrist.origin.lerp(fingers, 0.55))
	return grip.affine_inverse() * wrist

func set_standing_eye_height(value: float) -> Dictionary:
	if not is_finite(value) or value < 0.8 or value > 2.5 or not is_instance_valid(avatar):
		return {"valid":false,"reason":"Standing eye height must be between 0.8 and 2.5 metres."}
	var source_eye: Vector3 = avatar.visual_root.transform * eye_rest
	standing_eye_height = value
	fit_scale = standing_eye_height / maxf(source_eye.y, 0.5)
	calibrated = true
	planted_feet.clear()
	solver.reset_smoothing()
	stance_solver.reset_smoothing()
	return {"valid":true,"standing_eye_height":standing_eye_height,"fit_scale":fit_scale}

func calibrate_standing_height() -> Dictionary:
	if not is_instance_valid(camera) or not is_instance_valid(body):
		return {"valid":false,"reason":"Tracked avatar is not ready."}
	var tracker = XRServer.get_tracker("head")
	var pose: XRPose = tracker.get_pose("default") if tracker != null else null
	if pose == null or not pose.has_tracking_data:
		return {"valid":false,"reason":"Head tracking is unavailable."}
	var ground := foot_ground(body.global_position, body.global_position.y)
	if ground.is_empty() or absf(body.global_position.y-Vector3(ground.position).y)>0.15:
		return {"valid":false,"reason":"Stand on a supported floor before calibrating."}
	return set_standing_eye_height(camera.global_position.y - Vector3(ground.position).y)

func _physics_process(delta: float) -> void:
	if is_instance_valid(body):
		sample_body_velocity(delta)

func sample_body_velocity(delta: float) -> void:
	# Actual displacement includes room-scale recentering, unlike body.velocity.
	# Differentiate on the fixed physics clock: render frames may contain zero,
	# one or several physics moves and must not turn that into gait-rate jitter.
	var velocity := Vector3.ZERO
	if have_body_position and delta > 0.00001:
		var displacement := body.global_position - previous_body_position
		if displacement.length() < maxf(0.8, delta * 20.0):
			velocity = displacement / delta
		else:
			planted_feet.clear()
			measured_velocity = Vector3.ZERO
	previous_body_position = body.global_position
	have_body_position = true
	measured_velocity = measured_velocity.lerp(velocity, 1.0 - exp(-16.0 * delta))

func sample_body_context(_delta: float) -> Dictionary:
	var ground := foot_ground(body.global_position, body.global_position.y)
	var floor_y := body.global_position.y
	var grounded: bool = body.get_grounded() if body.has_method("get_grounded") else body.is_on_floor()
	if body.has_method("prepare_tracked_body"):
		grounded = bool(body.get("on_ground"))
	if not ground.is_empty():
		floor_y = Vector3(ground.position).y
		# XRTools ground classification precedes its move. Verify current floor
		# proximity too, so source support attachment does not present as falling.
		var separation := body.global_position.y - floor_y
		grounded = grounded or (separation >= -0.025 and separation <= 0.12 and measured_velocity.y <= 0.6)
	var result := {"velocity":measured_velocity,"grounded":grounded,"floor_y":floor_y,"support_found":not ground.is_empty()}
	if body.has_method("combat_actions_allowed"):
		result["presentation"] = body.feedback.animation_context()
		result["physical_eye_height"] = camera.global_position.y - floor_y - body.feedback.applied_offset
	return result

func _process(delta: float) -> void:
	if not is_instance_valid(avatar) or not is_instance_valid(camera):
		return
	var head_tracker = XRServer.get_tracker("head")
	var head_pose: XRPose = head_tracker.get_pose("default") if head_tracker != null else null
	if head_pose == null or not head_pose.has_tracking_data:
		visible = false
		set_gloves_visible(true)
		return
	var left: XRController3D = rig.get_node("LeftHand")
	var right: XRController3D = rig.get_node("RightHand")
	var context := sample_body_context(delta)
	update_tracking(delta, camera.global_transform,
		hand_target(left, "left"), hand_target(right, "right"), float(context.floor_y), context)
	update_fingers()

func update_tracking(delta: float, head: Transform3D, left: Variant, right: Variant, floor_y: float, context: Dictionary = {}) -> void:
	var performer: Node3D = body.feedback.performer if body != null and body.has_method("combat_actions_allowed") else null
	if not head.origin.is_finite() or not head.basis.is_finite():
		return
	if not calibrated:
		# First tracking may arrive while seated, crouched or with the HMD on a
		# desk. It is a posture sample, not evidence of standing body size.
		# Main applies saved explicit calibration before this update; otherwise
		# retain the 1.70 m standing baseline until the user calibrates upright.
		# Only the rendered avatar is fitted; XR/world/weapon size is unchanged.
		set_standing_eye_height(standing_eye_height)
	var presentation:Dictionary=context.get("presentation",{})
	if bool(presentation.get("life_locked",false)):
		update_life_pose(delta,head,floor_y,presentation,left,right)
		return
	if life_pose_locked:
		reset_life_pose_anchor()
	var seat_provider:Node=body.get("space") if is_instance_valid(body.get("space")) and body.space.seated() else body.get("vehicles")
	var riding: bool=is_instance_valid(seat_provider) and seat_provider.seated()
	if riding:
		context=context.duplicate();context["grounded"]=false
	var previous_heading := heading
	var forward := -head.basis.z
	if Vector2(forward.x, forward.z).length() > 0.15:
		heading = atan2(-forward.x, -forward.z)
	if riding:heading=seat_provider.seat_pose().basis.get_euler().y
	var yaw := Basis(Vector3.UP, heading)
	if absf(angle_difference(previous_heading, heading)) > 0.25:
		planted_feet.clear()
	var motion := {}
	if motion_ready:
		var velocity: Vector3 = context.get("velocity", Vector3.ZERO)
		motion = body_motion.advance(delta, yaw.inverse() * velocity, bool(context.get("grounded", true)), float(context.get("physical_eye_height", head.origin.y-floor_y))/standing_eye_height, fit_scale * avatar.visual_root.scale.y, context.get("presentation", {}))
		if motion.get("changed", false):
			planted_feet.clear()
			stance_solver.reset_smoothing()
	if riding:
		var mounted: Dictionary=seat_provider.rider_pose(avatar.race_id)
		if not mounted.is_empty():
			skeleton.reset_bone_poses()
			for track: Dictionary in mounted.tracks:
				var bone:=skeleton.find_bone(str(track.name))
				if bone<0:continue
				var p: Array=track.position;var q: Array=track.rotation
				skeleton.set_bone_pose_position(bone,Vector3(p[0],p[1],p[2]))
				skeleton.set_bone_pose_rotation(bone,Quaternion(q[0],q[1],q[2],q[3]))
			motion={"state":"riding","source":mounted.source,"prone_blend":0.0}
	var prone_weight := float(motion.get("prone_blend",0.0))
	# Original run clips lean the spine as much as 15 cm behind the eyes.
	# Keep their rhythm at reduced amplitude so authored motion does not consume
	# the reach budget of tracked arms. Legs retain the full original gait.
	for bone_name in ["spine1", "spine2", "spine3"]:
		var index := skeleton.find_bone(bone_name)
		var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var source_weight := 1.0 if str(motion.get("state","")).begins_with("perform_") else lerpf(torso_animation_weight,1.0,prone_weight)
		skeleton.set_bone_pose_rotation(index, rest_rotation.slerp(skeleton.get_bone_pose_rotation(index), source_weight))
	# Directional clips turn the pelvis up to 74 degrees. Counter that rotation
	# at the waist so hips/legs keep the source stride while the tracked torso
	# stays aligned with the user's heading and does not drag shoulders away.
	var root_index := skeleton.find_bone("root")
	var spine_index := skeleton.find_bone("spine1")
	var root_rest_rotation := skeleton.get_bone_rest(root_index).basis.get_rotation_quaternion()
	var pelvis_rotation := skeleton.get_bone_pose_rotation(root_index)
	var torso_counter := (pelvis_rotation.inverse() * root_rest_rotation).slerp(Quaternion.IDENTITY,prone_weight)
	skeleton.set_bone_pose_rotation(spine_index, torso_counter * skeleton.get_bone_pose_rotation(spine_index))
	if motion.get("crouched", false) and motion.get("state", "") == "crouch":
		var spine := skeleton.find_bone("spine1")
		var tracked_pitch := (yaw.inverse() * head.basis.orthonormalized()).get_euler().x
		var lean := clampf(tracked_pitch, -0.7, 0.5) * clampf((1.0-(head.origin.y-floor_y)/standing_eye_height)*2.0, 0.0, 0.5)
		skeleton.set_bone_pose_rotation(spine, Quaternion(Vector3.RIGHT, lean) * skeleton.get_bone_pose_rotation(spine))
	var posed_head := skeleton.get_bone_global_pose(skeleton.find_bone("head"))
	var animated_ankles := {}
	var animated_knees := {}
	for side in ["left", "right"]:
		animated_ankles[side] = skeleton.get_bone_global_pose(skeleton.find_bone("lankle" if side == "left" else "rankle"))
		animated_knees[side] = skeleton.get_bone_global_pose(skeleton.find_bone("lshin" if side == "left" else "rshin"))
	var head_rotation := yaw.inverse() * head.basis.orthonormalized() * head_rest.basis
	var eye_at_pose := posed_head.origin + head_rotation * eye_in_head
	var source_eye: Vector3 = avatar.visual_root.transform * eye_at_pose
	global_transform = Transform3D(yaw.scaled(Vector3.ONE * fit_scale), head.origin - yaw * source_eye * fit_scale)
	if riding:
		# The source rider root is the pelvis at the vehicle player hardpoint.
		# Keep it seated while head/arms continue through bounded tracked IK.
		var pelvis_local: Vector3=avatar.visual_root.transform*skeleton.get_bone_global_pose(root_index).origin
		global_transform=Transform3D(yaw.scaled(Vector3.ONE*fit_scale),seat_provider.seat_pose().origin-yaw*pelvis_local*fit_scale)
	# Keep inferred hips within leg reach without moving tracked eyes/shoulders.
	# Source locomotion shifts pelvis independently; compensate at the waist,
	# instead of accepting clamped IK endpoints that hover above contact ground.
	var pelvis_correction := 0.0
	if stance_ready and bool(context.get("grounded",true)):
		var lower_bound := -INF
		var upper_bound := INF
		for side in ["left","right"]:
			var ankle: Transform3D = animated_ankles[side]
			var ankle_world: Vector3 = skeleton.global_transform * ankle.origin
			var ground := foot_ground(ankle_world,floor_y)
			if ground.is_empty(): continue
			var hip_index := skeleton.find_bone("lthigh" if side == "left" else "rthigh")
			var hip_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hip_index).origin
			var rest: Transform3D = ankle_rest[side]
			var ankle_height: float = (avatar.visual_root.transform*rest.origin).y*fit_scale
			var reach: float = leg_lengths[side]*skeleton.global_basis.get_scale().y
			var lift: float = float(motion.get("foot_lift",{}).get(side,0))*fit_scale*avatar.visual_root.scale.y
			lower_bound = maxf(lower_bound,Vector3(ground.position).y+minf(lerpf(0.22,0.10,prone_weight),reach*0.25)-hip_world.y)
			upper_bound = minf(upper_bound,Vector3(ground.position).y+ankle_height+lift+reach*0.985-hip_world.y)
		if lower_bound <= upper_bound:
			pelvis_correction = clampf(0.0,lower_bound,upper_bound)
		# A physical squat moves inferred hips behind planted feet. Keeping hips
		# directly under the HMD while lowering it forces a knee below the floor.
		var eye_ratio := (head.origin.y-floor_y)/standing_eye_height
		var hip_back := clampf((0.78-eye_ratio)/0.35,0,1)*0.28*standing_eye_height/1.7*(1.0-prone_weight)
		var pelvis_delta := Vector3.UP*pelvis_correction + yaw*Vector3(0,0,hip_back)
		if is_finite(pelvis_correction) and pelvis_delta.length_squared()>0.00000001:
			var root_parent := skeleton.get_bone_parent(root_index)
			var parent_basis := skeleton.get_bone_global_pose(root_parent).basis if root_parent>=0 else Basis.IDENTITY
			var skeleton_delta := skeleton.global_basis.inverse()*pelvis_delta
			skeleton.set_bone_pose_position(root_index,skeleton.get_bone_pose_position(root_index)+parent_basis.inverse()*skeleton_delta)
			var root_basis := skeleton.get_bone_global_pose(root_index).basis
			skeleton.set_bone_pose_position(spine_index,skeleton.get_bone_pose_position(spine_index)-root_basis.inverse()*skeleton_delta)
	if is_instance_valid(combat_rig): combat_rig.constrain_held_weapon()
	if is_instance_valid(performer): performer.constrain_prop()
	var inverse := skeleton.global_transform.affine_inverse()
	var local_head := inverse * head
	local_head.basis = local_head.basis.orthonormalized() * head_rest.basis
	var targets := {"head":local_head}
	for wrist_name in ["lwrist","rwrist"]:
		var wrist := skeleton.find_bone(wrist_name)
		skeleton.set_bone_pose_position(wrist,skeleton.get_bone_rest(wrist).origin)
	for side in ["left", "right"]:
		var tracked: Variant = left if side == "left" else right
		var vehicle_target:Variant=vehicle_hand_target(side)
		var prop_attached := is_instance_valid(performer) and performer.hand_target(side) is Transform3D
		if is_instance_valid(combat_rig) and combat_rig.hand_target(side) is Transform3D:
			tracked=combat_rig.hand_target(side)
		if prop_attached: tracked=performer.hand_target(side)
		if vehicle_target is Transform3D:tracked=vehicle_target
		if tracked is Transform3D:
			var local: Transform3D = inverse * tracked
			local.basis = local.basis.orthonormalized()
			var attached := vehicle_target is Transform3D or prop_attached or (is_instance_valid(combat_rig) and combat_rig.hand_target(side) is Transform3D)
			targets[side + "_hand"] = local * (weapon_hand_offsets[side] if attached else grip_offsets[side])
			targets[side + "_hand_attached"] = vehicle_target is Transform3D
		else:
			# Safe shoulder-relative resting target, rather than stale world poses
			# or a stretch to the untracked controller's origin.
			var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone("larm" if side == "left" else "rarm")).origin
			var rest := skeleton.get_bone_global_rest(skeleton.find_bone("lwrist" if side == "left" else "rwrist"))
			rest.origin = shoulder + Vector3(-0.12 if side == "left" else 0.12, -0.46, -0.08)
			targets[side + "_hand"] = rest
	last_report = solver.solve(targets, delta)
	# Keep source hand sockets rigid. Mounted controls allow visual arm extension;
	# ordinary controllers and held weapons retain anatomical reach constraints.
	for side in ["left","right"]:
		var hold := skeleton.find_bone("hold_l" if side=="left" else "hold_r")
		if hold >= 0:
			skeleton.set_bone_pose_position(hold,skeleton.get_bone_rest(hold).origin)
			skeleton.set_bone_pose_rotation(hold,skeleton.get_bone_rest(hold).basis.get_rotation_quaternion())
	last_report["left_tracked"] = left is Transform3D
	last_report["right_tracked"] = right is Transform3D
	last_report["motion"] = motion
	last_report["pelvis_correction_m"] = pelvis_correction
	if stance_ready and bool(context.get("grounded", true)):
		var stance := {"head_tracked":false}
		var planting := float(motion.get("blend",1.0))>=1.0
		if not planting:
			planted_feet.clear()
			stance_solver.reset_smoothing()
		for side in ["left", "right"]:
			var ankle: Transform3D = animated_ankles[side]
			var world: Transform3D = skeleton.global_transform * ankle
			var rest: Transform3D = ankle_rest[side]
			var rest_offset: Vector3 = avatar.visual_root.transform * rest.origin
			var lift: float = float(motion.get("foot_lift", {}).get(side, 0.0)) * fit_scale * avatar.visual_root.scale.y
			# Hold contact feet in world space, sampling ground at the planted
			# position (important when the next stair has a different height).
			var candidate := world.origin
			if planting and lift < 0.025 and planted_feet.has(side) and Vector2(world.origin.x-planted_feet[side].x, world.origin.z-planted_feet[side].z).length() < 0.45:
				world.origin.x = planted_feet[side].x
				world.origin.z = planted_feet[side].z
			else:
				planted_feet.erase(side)
			var ground := foot_ground(world.origin, floor_y)
			if not ground.is_empty():
				var ground_position: Vector3 = ground.position
				world.origin.y = ground_position.y + rest_offset.y * fit_scale + lift
				if planting and lift < 0.025:
					planted_feet[side] = world.origin
				var foot_up := (world.basis * (rest.basis.inverse() * Vector3.UP)).normalized()
				var normal: Vector3 = ground.normal
				var align := Quaternion(foot_up, normal)
				world.basis = Basis(Quaternion.IDENTITY.slerp(align, clampf(1.0-lift/0.12, 0, 1)*(1.0-prone_weight))) * world.basis
			else:
				world.origin = candidate
				planted_feet.erase(side)
			if not ground.is_empty():
				# A full authored stride can exceed the calibrated leg reach. Keep
				# the contact height and shorten horizontal reach, rather than let
				# the generic IK clamp pull a planted foot above the floor.
				var hip_index := skeleton.find_bone("lthigh" if side == "left" else "rthigh")
				var hip := skeleton.global_transform * skeleton.get_bone_global_pose(hip_index).origin
				var reach: float = leg_lengths[side] * skeleton.global_basis.get_scale().y - 0.0002
				for attempt in range(2):
					var vertical := world.origin.y - hip.y
					if absf(vertical) >= reach:
						break
					var horizontal := Vector2(world.origin.x-hip.x, world.origin.z-hip.z)
					var radius := sqrt(maxf(0, reach*reach-vertical*vertical))
					if horizontal.length() <= radius:
						break
					horizontal = horizontal.normalized() * radius
					world.origin.x = hip.x + horizontal.x
					world.origin.z = hip.z + horizontal.y
					var adjusted_ground := foot_ground(world.origin, floor_y)
					if not adjusted_ground.is_empty():
						world.origin.y = adjusted_ground.position.y + rest_offset.y * fit_scale + lift
				if planting and lift < 0.025:
					planted_feet[side] = world.origin
			stance[side + "_hand"] = inverse * world
			var pole_hip_index := skeleton.find_bone("lthigh" if side == "left" else "rthigh")
			var pole_hip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(pole_hip_index).origin
			var pole_reach: float = leg_lengths[side] * skeleton.global_basis.get_scale().y
			# Standing/crouched knees bend FORWARD, not upward. An upward pole
			# projects behind a sloped hip-to-ankle segment and reverses the knee.
			# Preserve the original prone/crawl knee planes (including the authored
			# sideways bent leg); a generic downward pole buries that knee.
			var standing_pole := pole_hip + yaw*Vector3.FORWARD*pole_reach
			var source_pole: Vector3 = skeleton.global_transform * animated_knees[side].origin
			var knee_pole := standing_pole.lerp(source_pole,prone_weight)
			stance[side + "_pole"] = inverse * knee_pole
		last_report["stance"] = stance_solver.solve(stance, delta)
	else:
		planted_feet.clear()
	visible = true
	set_gloves_visible(false)
	# Bone-driven mounts consume the final presented posture in this same frame.
	if is_instance_valid(combat_rig):
		combat_rig.finalize_held_weapon()
		combat_rig.update_visuals()

func reset_life_pose_anchor()->void:
	# Authoritative relocation/reconnect calls this under the loading cover.
	# Room-scale body motion itself must never relocate an immobilized avatar.
	life_pose_locked=false;life_pose_state="";life_pose_time=0.0
	life_pose_anchor=Vector3.ZERO;life_pose_heading=0.0
	if is_instance_valid(skeleton):skeleton.reset_bone_poses()
	solver.reset_smoothing();stance_solver.reset_smoothing();planted_feet.clear()
	have_body_position=false;measured_velocity=Vector3.ZERO

func update_life_pose(delta:float,head:Transform3D,floor_y:float,presentation:Dictionary,left:Variant=null,right:Variant=null)->void:
	var state:=str(presentation.get("life_state","incapacitated"))
	if not life_pose_locked:
		var forward:Vector3=-head.basis.z
		life_pose_heading=atan2(-forward.x,-forward.z) if Vector2(forward.x,forward.z).length()>0.15 else heading
		life_pose_anchor=Vector3(body.global_position.x,floor_y,body.global_position.z)
		planted_feet.clear()
	if not life_pose_locked or state!=life_pose_state:life_pose_time=0.0
	life_pose_locked=true;life_pose_state=state
	if bool(presentation.get("feigning_death",false)):life_pose_anchor=Vector3(body.global_position.x,floor_y,body.global_position.z)
	if bool(presentation.get("life_pose_frozen",state=="dead")):
		life_pose_time=float(presentation.get("life_pose_time",0.0))
	else:life_pose_time+=clampf(delta,0.0,0.1)
	global_transform=Transform3D(Basis(Vector3.UP,life_pose_heading).scaled(Vector3.ONE*fit_scale),life_pose_anchor)
	var sampled:Dictionary=avatar.sample_life_pose(str(presentation.get("life_animation",state)),life_pose_time)
	last_report={"life_locked":true,"life_state":state,"life_pose":sampled,"life_pose_time":life_pose_time,"anchor":life_pose_anchor,"tracking_ik_applied":false}
	if bool(presentation.get("feigning_death",false)):
		# Only untracked bones retain the incap clip. Tracking remains authoritative.
		var inverse:=skeleton.global_transform.affine_inverse()
		var local_head:=inverse*head
		local_head.basis=local_head.basis.orthonormalized()*head_rest.basis
		var targets:Dictionary={"head":local_head}
		for side in ["left","right"]:
			var tracked:Variant=left if side=="left" else right
			if tracked is Transform3D:
				var local:Transform3D=inverse*tracked;local.basis=local.basis.orthonormalized()
				targets[side+"_hand"]=local*grip_offsets[side]
		last_report["tracking_ik"]=solver.solve(targets,delta)
		last_report.tracking_ik_applied=true
	visible=true;set_gloves_visible(false)
	if is_instance_valid(combat_rig):combat_rig.update_visuals()

func set_gloves_visible(value: bool) -> void:
	if is_instance_valid(rig):
		for path in ["LeftHand/Hand", "RightHand/Hand"]:
			var glove := rig.get_node_or_null(path)
			if glove != null:
				glove.visible = value

func _exit_tree() -> void:
	set_gloves_visible(true)
	if is_instance_valid(camera) and original_cull_mask >= 0:
		camera.cull_mask = original_cull_mask

func update_fingers() -> void:
	if fingers == null or life_pose_locked:
		return
	var left: XRController3D = rig.get_node("LeftHand")
	var right: XRController3D = rig.get_node("RightHand")
	fingers.apply_controller(finger_state(left,"left"), finger_state(right,"right"))
	var sources := {}
	for side in ["left", "right"]:
		if vehicle_hand_target(side) is Transform3D:
			apply_vehicle_fingers(side)
			sources[side]={"mode":"vehicle_grip"}
			continue
		if is_instance_valid(combat_rig) and (combat_rig.hand_target(side) is Transform3D or combat_rig.unarmed_engaged(side)):
			sources[side] = {"mode":"unarmed_fist" if combat_rig.unarmed_engaged(side) else "weapon_grip"}
			continue
		var data := HandInput.tracked_joints(side)
		sources[side] = {"mode":"controller_pose"}
		if not data.is_empty():
			var result: Dictionary = fingers.apply_hand_joints(side, data.joints)
			if result.get("valid", false):
				sources[side] = {"mode":"skeletal", "source":data.source, "result":result}
	last_report["fingers"] = sources

func apply_vehicle_fingers(side:String)->void:
	# Original rider clips already fit fingers around their source yoke. Keep
	# those authored curls for a latched hand instead of an unrelated gun fist.
	var mounted:Dictionary=body.vehicles.rider_pose(avatar.race_id)
	var prefix:String="l" if side=="left" else "r"
	for track:Dictionary in mounted.get("tracks",[]):
		var name:String=str(track.name)
		if not name.begins_with(prefix):continue
		var finger:bool=false
		for stem in ["thumb","index","middle","ring","pinky"]:
			if name.begins_with(prefix+stem):finger=true;break
		if not finger:continue
		var bone:=skeleton.find_bone(name)
		if bone<0:continue
		var p:Array=track.position;var q:Array=track.rotation
		skeleton.set_bone_pose_position(bone,Vector3(p[0],p[1],p[2]))
		skeleton.set_bone_pose_rotation(bone,Quaternion(q[0],q[1],q[2],q[3]))

func finger_state(controller: XRController3D, side: String) -> Dictionary:
	var state := HandInput.controller_state(controller)
	if vehicle_hand_target(side) is Transform3D:
		state.grip=1.0;state.trigger=1.0;state.trigger_touch=true;state.thumb_touch=true
		return state
	if is_instance_valid(combat_rig) and (combat_rig.hand_target(side) is Transform3D or combat_rig.unarmed_engaged(side)):
		state.grip = 1.0
		state.thumb_touch = true
		if side != combat_rig.dominant or combat_rig.unarmed_engaged(side):
			state.trigger = 1.0
			state.trigger_touch = true
	return state

func vehicle_hand_target(side:String)->Variant:
	if is_instance_valid(body) and is_instance_valid(body.get("vehicles")):
		return body.vehicles.hand_target(side)
	return null

func hand_target(controller: XRController3D, side: String) -> Variant:
	var vehicle_target:Variant=vehicle_hand_target(side)
	if vehicle_target is Transform3D:return vehicle_target
	if is_instance_valid(combat_rig):
		var attached: Variant = combat_rig.hand_target(side)
		if attached is Transform3D: return attached
	if HandInput.controller_tracked(controller):
		return visual_hand_pose(controller.global_transform,side)
	var data := HandInput.tracked_joints(side)
	return visual_hand_pose(rig.global_transform * data.grip,side) if not data.is_empty() else null

func visual_hand_pose(pose:Transform3D,side:String)->Transform3D:
	if is_instance_valid(body) and body.get("feedback")!=null:return body.feedback.spice.hand_pose(pose,camera.global_transform,side)
	return pose

func foot_ground(point: Vector3, fallback_y: float) -> Dictionary:
	# Imported interior cells deliberately exclude terrain; use the same mask.
	# No collision is installed in isolated pose tests, where the supplied
	# floor is the explicit test surface. Live misses never invent a floor.
	if not body.has_method("prepare_tracked_body"):
		return {"position":Vector3(point.x, fallback_y, point.z), "normal":Vector3.UP}
	var provider: Node3D = body.get("ground_provider")
	if is_instance_valid(provider):
		var context: Dictionary = provider.collision_context(point)
		var allowed: Array = context.get("allowed_cell_ids", [])
		if not allowed.is_empty():
			var support: Dictionary = provider.ground_support.sample_support(Vector3(point.x,fallback_y,point.z),allowed,0.35,0.8)
			if support.get("valid",false): return {"position":Vector3(point.x,support.height,point.z),"normal":support.normal}
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, fallback_y + 0.6, point.z), Vector3(point.x, fallback_y - 0.8, point.z), body.collision_mask, [body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.65:
		return {}
	return hit
