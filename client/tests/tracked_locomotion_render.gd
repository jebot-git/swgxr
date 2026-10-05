extends SceneTree
## Mocked head/controller transforms. This does not validate a live headset.
const Avatar = preload("res://scripts/avatar.gd")
const Tracked = preload("res://scripts/tracked_avatar.gd")
var results: Array = []
var capture := false
func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 45
	camera.near = 0.02
	camera.cull_mask = 3
	world.add_child(camera)
	camera.make_current()
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.11,0.14,0.17)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,25,0)
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000,1000)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.21,0.24,0.26)
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var rig := XROrigin3D.new()
	world.add_child(rig)
	var body := CharacterBody3D.new()
	body.name = "PlayerBody"
	rig.add_child(body)
	var xr_camera := XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_camera.current = false
	rig.add_child(xr_camera)
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/tracked-locomotion")
	DirAccess.make_dir_recursive_absolute(directory)
	var passed := true
	var fixture := Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/evidence/tracked-avatar-core3-character.json"))
	for race in ["human_male","rodian_male","ithorian_male","wookiee_male"]:
		var tracked := Tracked.new()
		world.add_child(tracked)
		var avatar := Avatar.new()
		tracked.add_child(avatar)
		var appearance := {"height":1.0,"profession":"crafting_artisan","customization":{}}
		var equipment: Array = []
		if race == "human_male" and fixture.has("character"):
			appearance = fixture.character.appearance.duplicate(true)
			appearance.profession = fixture.character.profession
			equipment = fixture.character.equipment
		assert(avatar.configure(race,appearance,equipment).error == "")
		assert(tracked.configure(avatar,rig))
		tracked.set_process(false)
		var center := Vector3.ZERO
		var states := {"walk":Vector3(0,0,-1.55),"run":Vector3(0,0,-5.13),"strafe_left":Vector3(-2.07,0,0),"strafe_right":Vector3(2.16,0,0),"backpedal":Vector3(0,0,1.35),"crouch":Vector3.ZERO,"crouch_walk":Vector3(0,0,-1.1),"idle":Vector3.ZERO}
		tracked.update_tracking(1.0/90,Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),null,null,0.0)
		for state in states:
			var velocity: Vector3 = states[state]
			var eye_height := 0.85 if state == "crouch" else (1.18 if state == "crouch_walk" else 1.7)
			var maximum_eye_error := 0.0
			var maximum_wrist_error := 0.0
			var maximum_unclamped_wrist_error := 0.0
			var maximum_solver_error := 0.0
			var clamped_hand_samples := 0
			var ankle_minimum := INF
			var ankle_maximum := -INF
			var knee_poses: Array = []
			for frame in range(100):
				center += velocity / 90.0
				var head := Transform3D(Basis.IDENTITY,center + Vector3(0,eye_height,0))
				var left := Transform3D(Basis.IDENTITY,center + Vector3(-0.27,eye_height-0.5,-0.34))
				var right := Transform3D(Basis.IDENTITY,center + Vector3(0.27,eye_height-0.5,-0.34))
				tracked.update_tracking(1.0/90,head,left,right,0.0,{"velocity":velocity,"grounded":true})
				var head_pose: Transform3D = avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("head"))
				maximum_eye_error = maxf(maximum_eye_error,(avatar.skeleton.global_transform * (head_pose*tracked.eye_in_head)).distance_to(head.origin))
				for side in ["left","right"]:
					var wrist: Transform3D = avatar.skeleton.global_transform * avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("lwrist" if side == "left" else "rwrist"))
					var input_hand: Transform3D = left if side == "left" else right
					var target := avatar.skeleton.global_transform.affine_inverse() * input_hand
					target.basis = target.basis.orthonormalized()
					target = avatar.skeleton.global_transform * (target * tracked.grip_offsets[side])
					var wrist_error := wrist.origin.distance_to(target.origin)
					maximum_wrist_error = maxf(maximum_wrist_error,wrist_error)
					var solve: Dictionary = tracked.last_report[side]
					maximum_solver_error = maxf(maximum_solver_error,float(solve.solver_error))
					if solve.clamped:
						clamped_hand_samples += 1
					else:
						maximum_unclamped_wrist_error = maxf(maximum_unclamped_wrist_error,wrist_error)
					var ankle: Vector3 = avatar.skeleton.global_transform * avatar.skeleton.get_bone_global_pose(avatar.skeleton.find_bone("lankle" if side == "left" else "rankle")).origin
					ankle_minimum = minf(ankle_minimum,ankle.y)
					ankle_maximum = maxf(ankle_maximum,ankle.y)
				if frame in [40,80]:
					knee_poses.append(avatar.skeleton.get_bone_pose_rotation(avatar.skeleton.find_bone("lshin")))
					if capture:
						camera.global_position = center + Vector3(-1.3,1.2,-2.65)
						camera.look_at(center + Vector3(0,0.9,0))
						for unused in range(3): await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(directory.path_join(race+"_"+state+"_"+str(frame)+".png"))
			var state_passed: bool = tracked.last_report.motion.state == state and maximum_eye_error < 0.0001 and maximum_unclamped_wrist_error < 0.01 and maximum_solver_error < 0.0001 and ankle_minimum > -0.01
			passed = passed and state_passed
			results.append({"race":race,"state":state,"passed":state_passed,"eye_error":maximum_eye_error,"wrist_error":maximum_wrist_error,"unclamped_wrist_error":maximum_unclamped_wrist_error,"solver_error":maximum_solver_error,"clamped_hand_samples":clamped_hand_samples,"ankle_range":[ankle_minimum,ankle_maximum],"knee_changes":not knee_poses[0].is_equal_approx(knee_poses[1]),"rate":tracked.last_report.motion.rate})
		tracked.free()
	var output := {"test":"tracked_locomotion","hardware_tested":false,"reach_policy":"Out-of-reach controller targets are clamped to original limb lengths; residual is reported, not hidden.","passed":passed,"states":results}
	var file := FileAccess.open(directory.path_join("render_report.json" if capture else "report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  ")+"\n")
	print("TRACKED_LOCOMOTION ",JSON.stringify(output))
	quit(0 if passed else 1)
