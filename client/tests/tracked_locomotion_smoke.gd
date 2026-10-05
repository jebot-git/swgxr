extends SceneTree
## Actual original avatars + native body sampler + tracked-avatar/limb IK.
## Synthetic tracking only: run --headless --xr-mode off.
const Avatar = preload("res://scripts/avatar.gd")
const Driver = preload("res://scripts/tracked_avatar.gd")
var errors: Array[String] = []
var reports: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func run() -> void:
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "Test requires --xr-mode off")
	var world := Node3D.new()
	root.add_child(world)
	var rig := XROrigin3D.new()
	world.add_child(rig)
	var body := CharacterBody3D.new()
	body.name = "PlayerBody"
	rig.add_child(body)
	var camera := XRCamera3D.new()
	camera.name = "XRCamera3D"
	rig.add_child(camera)
	for hand in ["LeftHand", "RightHand"]:
		var controller := XRController3D.new()
		controller.name = hand
		rig.add_child(controller)
		var glove := Node3D.new()
		glove.name = "Hand"
		controller.add_child(glove)
	var catalog := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json"))
	var cases := [
		["idle", Vector3.ZERO, 1.7, true],
		["walk", Vector3(0, 0, -2), 1.7, true],
		["run", Vector3(0, 0, -9.36), 1.7, true],
		["strafe_left", Vector3(-2, 0, 0), 1.7, true],
		["strafe_right", Vector3(2, 0, 0), 1.7, true],
		["backpedal", Vector3(0, 0, 1.5), 1.7, true],
		["crouch_walk", Vector3(0, 0, -1.3), 1.18, true],
		["crouch", Vector3.ZERO, 1.18, true],
		["crouch", Vector3.ZERO, 0.85, true],
		["idle", Vector3.ZERO, 1.7, true],
		["jump", Vector3(0, 2, -2), 2.1, false],
		["idle", Vector3.ZERO, 1.7, true],
	]
	var began := Time.get_ticks_msec()
	for race: String in catalog.races:
		var before_errors := errors.size()
		var driver := Driver.new()
		world.add_child(driver)
		driver.set_process(false)
		var avatar := Avatar.new()
		driver.add_child(avatar)
		var configured: Dictionary = avatar.configure(race, {"height":1.0, "profession":"crafting_artisan", "customization":{}}, [])
		if configured.error != "" or not driver.configure(avatar, rig):
			check(false, race + " original avatar/locomotion configure failed")
			driver.free()
			continue
		var skeleton: Skeleton3D = avatar.skeleton
		var rig_before := rig.global_transform
		var camera_before := camera.global_transform
		var body_before := body.global_transform
		var states: Array = []
		var max_eye_error := 0.0
		var max_wrist_error := 0.0
		var max_solver_error := 0.0
		var clamped_hand_frames := 0
		var max_contact_error := 0.0
		var max_reachable_contact_error := 0.0
		var max_foot_height := -INF
		var min_foot_height := INF
		var metadata := {}
		for scenario in cases:
			var state: String = scenario[0]
			var speed: Vector3 = scenario[1]
			var eye_y: float = scenario[2]
			var grounded: bool = scenario[3]
			var base := Transform3D(Basis(Vector3.UP, 0.45), Vector3(24, 4, -19))
			var head := base * Transform3D(Basis(Vector3.RIGHT, -0.25 if state == "crouch" else -0.1), Vector3(0, eye_y, 0))
			var left := base * Transform3D(Basis.IDENTITY, Vector3(-0.22, eye_y - 0.42, -0.24))
			var right := base * Transform3D(Basis.IDENTITY, Vector3(0.22, eye_y - 0.42, -0.24))
			var first_legs: Array[Quaternion] = []
			var first_spine := Quaternion.IDENTITY
			var leg_change := 0.0
			var spine_change := 0.0
			var scenario_clamped := 0
			var scenario_hand_error := 0.0
			var scenario_contact_error := 0.0
			for frame in range(90):
				# The virtual body translates through the world while tracked head
				# and hand offsets remain physical; exercise contact-foot planting.
				var displacement: Vector3 = base.basis * Vector3(speed.x, 0, speed.z) / 90.0
				head.origin += displacement
				left.origin += displacement
				right.origin += displacement
				driver.update_tracking(1.0/90, head, left, right, 4.0, {"velocity":base.basis * speed, "grounded":grounded})
				var eye_pose := skeleton.get_bone_global_pose(skeleton.find_bone("head"))
				var actual_eye: Vector3 = skeleton.global_transform * (eye_pose * driver.eye_in_head)
				max_eye_error = maxf(max_eye_error, actual_eye.distance_to(head.origin))
				for side in ["left", "right"]:
					var arm: Dictionary = driver.last_report[side]
					max_solver_error = maxf(max_solver_error, float(arm.solver_error))
					if arm.clamped:
						clamped_hand_frames += 1
						scenario_clamped += 1
					else:
						max_wrist_error = maxf(max_wrist_error, float(arm.error))
					scenario_hand_error = maxf(scenario_hand_error, float(arm.error) * driver.fit_scale * avatar.visual_root.scale.y)
					var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("lankle" if side == "left" else "rankle"))
					var actual: Vector3 = skeleton.global_transform * ankle.origin
					if grounded:
						max_foot_height = maxf(max_foot_height, actual.y-4.0)
						min_foot_height = minf(min_foot_height, actual.y-4.0)
						var lift: float = driver.last_report.motion.foot_lift[side] * driver.fit_scale * avatar.visual_root.scale.y
						if lift < 0.025 and frame > 20:
							var rest: Transform3D = driver.ankle_rest[side]
							var expected: float = (avatar.visual_root.transform * rest.origin).y * driver.fit_scale
							max_contact_error = maxf(max_contact_error, absf(actual.y-4.0-expected-lift))
							scenario_contact_error = maxf(scenario_contact_error, absf(actual.y-4.0-expected-lift))
							var hip := skeleton.get_bone_global_pose(skeleton.find_bone("lthigh" if side == "left" else "rthigh"))
							var hip_y: float = (skeleton.global_transform * hip.origin).y
							var leg: Dictionary = driver.last_report.stance[side]
							var reach: float = (leg.upper_length + leg.lower_length) * driver.fit_scale * avatar.visual_root.scale.y
							if absf(hip_y - (4.0 + expected + lift)) < reach - 0.002:
								max_reachable_contact_error = maxf(max_reachable_contact_error, absf(actual.y-4.0-expected-lift))
				if frame == 25:
					for bone in ["lthigh", "lshin", "rthigh", "rshin"]:
						first_legs.append(skeleton.get_bone_pose_rotation(skeleton.find_bone(bone)))
					first_spine = skeleton.get_bone_pose_rotation(skeleton.find_bone("spine1"))
				elif frame > 25:
					var i := 0
					for bone in ["lthigh", "lshin", "rthigh", "rshin"]:
						leg_change = maxf(leg_change, first_legs[i].angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone(bone))))
						i += 1
					spine_change = maxf(spine_change, first_spine.angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone("spine1"))))
			var motion: Dictionary = driver.last_report.motion
			check(motion.valid and motion.state == state, race + " wrong locomotion state: " + str(motion))
			if state in ["walk", "run", "strafe_left", "strafe_right", "backpedal", "crouch_walk"]:
				check(leg_change > 0.03, race + " " + state + " legs did not animate")
				check(spine_change > 0.0005, race + " " + state + " spine did not animate")
				var source_speed: float = avatar.clip_speeds.get(state, 0.0)
				check(source_speed > 0, race + " " + state + " missing source_speed_mps metadata")
				metadata[state] = source_speed
			if state == "crouch":
				check(driver.body_motion.clip("crouch") == avatar.animation_player.get_animation("idle"), race + " physical crouch selected authored kneel")
				for bone in ["lshin", "rshin"]:
					var index := skeleton.find_bone(bone)
					check(skeleton.get_bone_pose_rotation(index).angle_to(skeleton.get_bone_rest(index).basis.get_rotation_quaternion()) > 0.15, race + " physical crouch did not bend both knees")
			if not grounded:
				check(not driver.last_report.has("stance") and driver.planted_feet.is_empty(), race + " airborne frame still applied floor IK")
			states.append({"state":state, "leg_motion_rad":leg_change, "spine_motion_rad":spine_change,
				"clamped_hand_frames":scenario_clamped, "max_hand_target_error_m":scenario_hand_error, "max_contact_error_m":scenario_contact_error})
		check(max_eye_error < 0.001, race + " locomotion displaced tracked eyes")
		check(max_wrist_error < 0.003, race + " locomotion displaced reachable tracked wrist")
		check(max_solver_error < 0.003, race + " arm solver failed to reach its bounded endpoint")
		check(min_foot_height > -0.15 and max_foot_height < 0.8, race + " inferred contact feet escaped ground bounds")
		check(max_contact_error < 0.003, race + " contact foot floated more than 3mm")
		check(max_reachable_contact_error < 0.003, race + " reachable contact foot floated more than 3mm")
		check(rig.global_transform.is_equal_approx(rig_before) and camera.global_transform.is_equal_approx(camera_before) and body.global_transform.is_equal_approx(body_before), race + " body animation modified physical XR nodes")
		reports.append({"race":race, "passed":errors.size()==before_errors, "states":states, "max_eye_error_m":max_eye_error,
			"max_reachable_wrist_error_m":max_wrist_error, "max_arm_solver_error_m":max_solver_error, "clamped_hand_frames":clamped_hand_frames,
			"min_foot_height_m":min_foot_height,"max_foot_height_m":max_foot_height,"max_contact_height_error_m":max_contact_error,
			"max_reachable_contact_height_error_m":max_reachable_contact_error,"source_speed_mps":metadata})
		driver.free()
	var report := {"test":"original_avatar_tracked_locomotion_integration", "hardware_tested":false, "passed":errors.is_empty(), "elapsed_ms":Time.get_ticks_msec()-began, "races":reports,"errors":errors}
	FileAccess.open("res://../runtime/evidence/tracked-locomotion-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.free()
	quit(0 if errors.is_empty() else 1)
