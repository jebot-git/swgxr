extends SceneTree
## Synthetic tracking evidence; does not claim headset hardware validation.
const Avatar = preload("res://scripts/avatar.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.11,0.14,0.17)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,20,0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 88
	camera.near = 0.02
	world.add_child(camera)
	var avatar := Avatar.new()
	world.add_child(avatar)
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/tracked-avatar")
	DirAccess.make_dir_recursive_absolute(directory)
	for race in ["human_male","ithorian_male","wookiee_male"]:
		assert(avatar.configure(race,{"profession":"crafting_artisan"}).error == "")
		avatar.set_tracking_mode(true)
		var solver := SwgTrackedIK.new()
		assert(solver.configure(avatar.skeleton))
		var targets := {}
		for side in ["left","right"]:
			var prefix := "l" if side == "left" else "r"
			var wrist := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(prefix + "wrist"))
			var shoulder := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(prefix + "arm")).origin
			targets[side + "_hand"] = Transform3D(wrist.basis, shoulder + Vector3(-0.09 if side == "left" else 0.09,-0.25,-0.35))
		var eye_names := ["leye","reye"] if avatar.skeleton.find_bone("leye") >= 0 else ["stalk_l","stalk_r"]
		var eye := Vector3.ZERO
		for bone in eye_names:
			eye += avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone(bone)).origin * 0.5
		camera.position = avatar.skeleton.global_transform * eye
		camera.look_at(avatar.skeleton.global_transform * Vector3(0,0.6,0.03))
		var head := avatar.skeleton.get_bone_global_rest(avatar.skeleton.find_bone("head"))
		targets.head = Transform3D(camera.basis, head.origin)
		var solve: Dictionary = solver.solve(targets,1.0/90)
		assert(solve.left.valid and solve.right.valid)
		camera.cull_mask = 1
		for i in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(race + "_first_person.png"))
		camera.cull_mask = 3
		camera.position = Vector3(0,1.2,-2.7)
		camera.look_at(Vector3(0,1,0))
		for i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(race + "_external.png"))
	print("AVATAR_TRACKING_RENDER_PASS original body/arms first-person, complete external avatar; synthetic targets only")
	quit()
