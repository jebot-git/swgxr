extends SceneTree
## Controlled style comparison only: source quad playback versus bounded native batches.
## Run with --xr-mode off --audio-driver Dummy --rendering-method forward_plus
## --rendering-driver vulkan --script res://tests/particle_visual_capture.gd.
const Assets = preload("res://combat/original_assets.gd")
const Legacy = preload("res://combat/source_effect.gd")
const Optimized = preload("res://combat/optimized_particles.gd")
const EFFECTS := [
	["RED BLASTER BOLT", "appearance/pt_bolt_red.prt"],
	["RED MUZZLE FLASH", "appearance/pt_bls_1_red_muz_flash_01.prt"],
	["RED IMPACT / SMOKE", "appearance/pt_bls_1_red_hit_other_01.prt"],
]
var fixtures: Array[Dictionary] = []
var assets := Assets.new()
var output := ProjectSettings.globalize_path("res://../runtime/evidence/particles")

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name() != "vulkan":
		fail("Visual capture requires desktop Forward+ Vulkan; headless does not validate appearance.")
		return
	if not assets.load_catalog():
		fail("Local user-provided combat asset catalog is missing.")
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1200, 1200)
	root.content_scale_size = Vector2i(1200, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.disable_3d = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for row in range(EFFECTS.size()):
		for column in range(2):
			make_fixture(row, column)
	for frame in range(6): await process_frame
	var captures: Array[String] = []
	var previous_age := 0.0
	for age in [0.04, 0.12, 0.30]:
		var remaining: float = age - previous_age
		while remaining > 0.000001:
			var step := minf(remaining, 1.0 / 120.0)
			for fixture in fixtures:
				if fixture.optimized: fixture.player.advance(step)
				else: fixture.player._process(step)
			remaining -= step
		previous_age = age
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var file := output.path_join("source-vs-batched-%03dms.png" % int(round(age * 1000.0)))
		if root.get_texture().get_image().save_png(file) != OK:
			fail("Unable to save particle comparison capture: " + file)
			return
		captures.append(file)
	var stats: Array = []
	for fixture in fixtures:
		if fixture.optimized: stats.append({"effect": fixture.path, "native": fixture.player.statistics()})
	var report := {
		"passed": true, "purpose": "Source-derived style comparison, not a performance or headset test",
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"source_catalog_sha256": FileAccess.get_sha256(assets.directory.path_join("assets.json")),
		"projection": "Each tile: 600x400, orthographic height 1.6 m, eye 4 m from emitter; reference tracer camera shifted 0.5 m left to fit its authored offsets",
		"timing": "Both implementations manually advance at <=1/120 s; frozen during readback",
		"randomness": "Legacy seed is fixed; native implementation has its own deterministic random stream",
		"captures": captures, "optimized": stats,
		"live_headset_validated": false,
	}
	var file := FileAccess.open(output.path_join("visual-comparison.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("PARTICLE_VISUAL_CAPTURE_PASS " + output)
	fixtures.clear()
	for child in root.get_children():
		if child is SubViewport or child is Control: child.queue_free()
	for frame in range(3): await process_frame
	assets = null
	quit(0)

func make_fixture(row: int, column: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.045, 0.06)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-0.5 if row == 0 and column == 0 else 0.0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.6
	camera.current = true
	var texture := TextureRect.new()
	root.add_child(texture)
	texture.position = Vector2(column * 600, row * 400)
	texture.size = Vector2(600, 400)
	texture.texture = viewport.get_texture()
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	root.add_child(label)
	label.position = texture.position + Vector2(18, 12)
	label.add_theme_font_size_override("font_size", 20)
	label.text = ("SOURCE REFERENCE" if column == 0 else "OPTIMIZED BATCHES") + "\n" + EFFECTS[row][0]
	var note := Label.new()
	root.add_child(note)
	note.position = texture.position + Vector2(18, 368)
	note.add_theme_font_size_override("font_size", 14)
	note.text = "User-provided source textures · desktop style test"
	var path: String = EFFECTS[row][1]
	var pose := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	var player: Node
	if column == 0:
		player = Legacy.new()
		world.add_child(player)
		player.global_transform = pose
		player.configure(assets.catalog.particles[path], assets, camera, row == 0, 1.0)
		player.rng.seed = 1729
		player.set_process(false)
	else:
		player = Optimized.shared(world, assets, camera)
		player.set_process(false)
		player.set_view(camera.global_transform, 110.0, 1.5)
		if row == 0: player.tracer(path, pose)
		else: player.burst(path, pose, 1.0)
	fixtures.append({"optimized": column == 1, "player": player, "path": path})
