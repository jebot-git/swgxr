extends SceneTree
## Desktop Vulkan evidence only, not live headset validation.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var body := CharacterBody3D.new()
	root.add_child(body)
	var camera := Camera3D.new()
	body.add_child(camera)
	camera.fov = 65
	camera.near = 0.03
	camera.make_current()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.025, 0.045, 0.065)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	world.environment.glow_enabled = true
	root.add_child(world)
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-35, -25, 0)
	var rig := preload("res://combat/ranged_rig.gd").new()
	root.add_child(rig)
	if not rig.configure(camera, body, [fixture.weapons.pistol_cdef]): quit(1); return
	rig.set_physics_process(false)
	rig.set_process(false)
	rig.configure_player_combat(fixture.player_combat)
	rig.set_allowed(true)
	rig.draw(0)
	rig.weapons[0].visual.global_transform = Transform3D(Basis(Vector3.UP, 0.15), Vector3(0.14, -0.23, -0.6))
	rig.update_visuals()
	rig.sample_ability_input(true, Vector2.ZERO, false, true)
	await capture("ability-radial.png")
	rig.sample_ability_input(false, Vector2.UP, false, true)
	rig.sample_ability_input(false, Vector2.ZERO, true, true)
	rig.update_visuals()
	await capture("ability-primed.png")
	rig.free()
	body.free()
	world.free()
	light.free()
	print(JSON.stringify({"test":"profession_ui_capture", "renderer":RenderingServer.get_current_rendering_method(), "driver":RenderingServer.get_current_rendering_driver_name(), "hardware_tested":false}))
	quit(0)

func capture(name: String) -> void:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/professions/" + name))
