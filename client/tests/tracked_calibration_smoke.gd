extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")
const Driver = preload("res://scripts/tracked_avatar.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100,0.2,100)
	collision.shape = shape
	floor_body.position.y = -0.1
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var rig = load("res://xr/player_rig.tscn").instantiate()
	world.add_child(rig)
	var body = rig.get_node("PlayerBody")
	body.set_physics_process(false)
	body.collision_mask = 5
	var camera: XRCamera3D = rig.get_node("XRCamera3D")
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_HEAD
	tracker.name = "head"
	tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.85,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	await physics_frame
	await physics_frame
	var catalog := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json"))
	var reports: Array = []
	for race in catalog.races:
		var driver := Driver.new()
		world.add_child(driver)
		driver.set_process(false)
		var avatar := Avatar.new()
		driver.add_child(avatar)
		assert(avatar.configure(race,{"height":1.0},[]).error == "")
		assert(driver.configure(avatar,rig))
		driver.set_physics_process(false) # This fixture advances its own fixed clock.
		body.position = Vector3.ZERO
		camera.position = Vector3(0,1.85,0)
		assert(driver.calibrate_standing_height().valid)
		assert(absf(driver.standing_eye_height-1.85)<0.001)
		var scale_before: float = driver.fit_scale
		body.on_ground = false # XRTools phase lag must not freeze source gait.
		var first_knee := Quaternion.IDENTITY
		var knee_change := 0.0
		for frame in range(90):
			body.position.z -= 2.0/90
			driver.sample_body_velocity(1.0/90)
			camera.position = body.position+Vector3(0,1.85,0)
			var context: Dictionary = driver.sample_body_context(1.0/90)
			assert(context.grounded and context.support_found)
			driver.update_tracking(1.0/90,camera.global_transform,null,null,context.floor_y,context)
			var knee := avatar.skeleton.get_bone_pose_rotation(avatar.skeleton.find_bone("lshin"))
			if frame == 30: first_knee = knee
			elif frame > 30: knee_change = maxf(knee_change,first_knee.angle_to(knee))
		assert(driver.last_report.motion.state == "walk" and knee_change > 0.05)
		var rig_before: Transform3D = rig.global_transform
		camera.position.y = 0.85
		var camera_before := camera.global_transform
		for frame in range(60): driver.update_tracking(1.0/90,camera.global_transform,null,null,0,{"velocity":Vector3.ZERO,"grounded":true})
		assert(is_equal_approx(driver.fit_scale,scale_before))
		assert(driver.last_report.motion.state == "crouch")
		assert(camera.global_transform.is_equal_approx(camera_before) and rig.global_transform.is_equal_approx(rig_before))
		var maximum_error := 0.0
		for side in ["left","right"]:
			maximum_error = maxf(maximum_error,driver.last_report.stance[side].error*driver.fit_scale)
		assert(maximum_error<0.003)
		body.position.y = 2
		assert(not driver.calibrate_standing_height().valid)
		var knee_heights := []
		for bone in ["lshin","rshin"]: knee_heights.append((avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone(bone)).origin).y)
		assert(float(knee_heights.min())>0.03)
		reports.append({"knees":knee_heights,"race":race,"standing_height":driver.standing_eye_height,"deep_crouch_contact_error":maximum_error,"walk_knee_change":knee_change})
		driver.free()
	XRServer.remove_tracker(tracker)
	var report := {"test":"standing_calibration_and_live_body_context","passed":true,"hardware_tested":false,"races":reports,"original_xr_nodes_preserved":true,"missing_ground_rejected":true,"ground_phase_lag_handled":true}
	FileAccess.open("res://../runtime/evidence/tracked-calibration-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"test":report.test,"passed":true,"races":reports.size()}))
	world.queue_free()
	await process_frame
	quit()
