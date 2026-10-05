extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("25303d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	world.add_child(light)
	var avatar := Avatar.new()
	world.add_child(avatar)
	var race: String = str(args.get("race", "human_male"))
	var result: Dictionary = avatar.configure(race)
	avatar.rotation.y = PI + 0.35
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.1, 3.8)
	camera.look_at(Vector3(0, 0.85, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var label := Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 24)
	root.add_child(label)
	var directory := ProjectSettings.globalize_path("res://../runtime/evidence/animation-poses")
	DirAccess.make_dir_recursive_absolute(directory)
	var states: Array = str(args.state).split(",") if args.has("state") else ["idle", "walk", "run", "strafe_left", "backpedal", "jump", "crouch", "prone", "sit", "emote_bow"]
	var passed: bool = str(result.get("error", "")).is_empty()
	for state in states:
		if not avatar.ensure_animation(state):
			passed = false
			continue
		avatar.animation_player.play(state, 0)
		avatar.animation_player.seek(float(args.get("time", 0.4)), true)
		avatar.animation_player.advance(0)
		avatar.animation_player.pause()
		label.text = race.replace("_", " ").capitalize() + " · " + str(state).replace("_", " ").capitalize() + "\nOriginal SWG animation"
		for i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(race + "-" + str(state) + ".png"))
	print(JSON.stringify({"test": "original_animation_pose_capture", "race": race, "states": states, "passed": passed}))
	quit(0 if passed else 1)
