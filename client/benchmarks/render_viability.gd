extends SceneTree
## Actual local SWG assets, synthetic population. Desktop GPU benchmark, never a headset test.
const Avatar = preload("res://scripts/avatar.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")
const Terrain = preload("res://scripts/terrain_stream.gd")
const WorldStream = preload("res://scripts/world_stream.gd")
const SourceEffect = preload("res://combat/source_effect.gd")
const OptimizedParticles = preload("res://combat/optimized_particles.gd")
const OriginalAssets = preload("res://combat/original_assets.gd")
const Presentation = preload("res://scripts/environment_presentation.gd")
var options := {}
var world: Node3D
var stage: Node3D
var terrain: Node3D
var buildings: Node3D
var camera: Camera3D
var eye_cameras: Array[Camera3D] = []
var measured_viewports: Array[Viewport] = []
var view_count := 1
var actors: Array = []
var positions: Array[Vector3] = []
var bolts: MultiMeshInstance3D
var effect_mode := "optimized"
var optimized: Node3D
var tracer_handles: Array[int] = []
var source_assets: RefCounted
var source_bolts: Array = []
var source_bolt_phases: Array[float] = []
var transient_effects: Array = []
var transient_cap := 64
var effect_carry := 0.0
var effect_events := 0
var effects_dropped := 0
var results: Array = []
var errors: Array[String] = []
var center := Vector3(-98, 0, 14)
var output := ""
var warmup := 5.0
var duration := 15.0
var render_distance := 384.0
var resolution := Vector2i(1600, 900)
var npc_count := 16
var seed_value := 42
var contention := []
var last_tick := 0
var samples := {}
var active_players := 0
var time_cursor := 0.0
var measured := false
var running := false
var streaming_load_ms := 0.0
var stage_report := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	call_deferred("run")

func fail(message: String) -> void:
	errors.append(message)
	push_error(message)

func local_path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://../" + relative)

func stats(values: Array, timing := false) -> Dictionary:
	if values.is_empty():
		return {"available":false,"samples":0}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	var over := 0
	for value: float in sorted:
		sum += value
		if value > 1000.0 / 90.0:
			over += 1
	return {"available":true,"samples":sorted.size(),"mean":sum / sorted.size(),
		"p50":sorted[ceili(sorted.size() * 0.50) - 1],"p95":sorted[ceili(sorted.size() * 0.95) - 1],
		"p99":sorted[ceili(sorted.size() * 0.99) - 1],"max":sorted[-1],
		"over_90hz_fraction":float(over) / sorted.size() if timing else null}

func sample(key: String, value: float) -> void:
	if is_finite(value) and value >= 0:
		if not samples.has(key):
			samples[key] = []
		samples[key].append(value)

func _process(delta: float) -> bool:
	if not running:
		return false
	var now := Time.get_ticks_usec()
	if measured and last_tick > 0:
		sample("wall_frame_ms", (now - last_tick) / 1000.0)
		sample("process_monitor_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		sample("physics_monitor_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var cpu := 0.0
		var gpu := 0.0
		for viewport: Viewport in measured_viewports:
			var rid := viewport.get_viewport_rid()
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		# Zero is not a reliable timing measurement (headless/driver unsupported).
		if cpu > 0:
			sample("render_cpu_ms", cpu)
		if gpu > 0:
			sample("render_gpu_ms", gpu)
		sample("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		sample("primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		sample("video_memory_bytes", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		sample("static_memory_bytes", Performance.get_monitor(Performance.MEMORY_STATIC))
	last_tick = now
	time_cursor += delta
	# Same path and initial pose for every population. Camera stays outside the starport.
	camera.position = center + Vector3(sin(time_cursor * 0.18) * 3, 14, -14)
	camera.look_at(center + Vector3(1, 1.0, 0))
	for index in range(eye_cameras.size()):
		var eye := eye_cameras[index]
		eye.global_transform = camera.global_transform
		eye.global_position += camera.global_basis.x * ((-0.032 if index == 0 else 0.032) if view_count == 2 else 0.0)
	for i in range(actors.size()):
		var actor: Node3D = actors[i]
		var phase := float(i + seed_value) * 0.61803398875
		actor.position = positions[i] + Vector3(sin(time_cursor * 0.6 + phase) * 0.45, 0, 0)
		actor.update_motion(delta, 3.0 if i < active_players else 0.0, {"grounded":true})
	if optimized != null:
		optimized.set_view(camera.global_transform,camera.fov,float(resolution.x)/resolution.y)
	var tracer_admissions := 0
	for i in range(bolts.multimesh.instance_count):
		var shooter := i % maxi(active_players, 1)
		var phase := fposmod(time_cursor * 2.0 + float(i + seed_value) * 0.61803398875, 1.0)
		var point: Vector3 = positions[shooter] + Vector3(0, 1.3, -phase * 30.0)
		if effect_mode == "surrogate": bolts.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, point))
		if i < tracer_handles.size():
			# Warm the persistent pool over several frames, as actual firing does.
			# One artificial all-at-once spawn would hit admission limits permanently.
			if tracer_handles[i] < 0 and tracer_admissions < 16:
				tracer_handles[i] = optimized.tracer("appearance/pt_bolt_red.prt",Transform3D(Basis.IDENTITY,point))
				tracer_admissions += 1
			optimized.move_tracer(tracer_handles[i],Transform3D(Basis.IDENTITY,point))
		if i < source_bolts.size():
			if phase < source_bolt_phases[i]:
				source_bolts[i].reset_playback()
			source_bolt_phases[i] = phase
			source_bolts[i].global_position = point
	if effect_mode in ["source","optimized"]:
		transient_effects = transient_effects.filter(func(effect): return is_instance_valid(effect))
		effect_carry += delta * active_players * 7.5
		var emissions := int(effect_carry)
		effect_carry -= emissions
		for emission in range(emissions):
			var shooter := effect_events % active_players
			effect_events += 1
			for kind in range(2):
				if effect_mode == "optimized":
					var path := "appearance/pt_bls_1_red_muz_flash_01.prt" if kind == 0 else "appearance/pt_bls_1_red_hit_other_01.prt"
					var point: Vector3 = positions[shooter] + Vector3(0,1.3,0 if kind == 0 else -30)
					if not optimized.burst(path,Transform3D(Basis.IDENTITY,point),1.0): effects_dropped += 1
					continue
				if transient_effects.size() >= transient_cap:
					effects_dropped += 1
					continue
				var path := "appearance/pt_bls_1_red_muz_flash_01.prt" if kind == 0 else "appearance/pt_bls_1_red_hit_other_01.prt"
				var effect := make_source_effect(path, false, 1.0, effect_events * 2 + kind)
				effect.global_position = positions[shooter] + Vector3(0, 1.3, 0 if kind == 0 else -30)
				transient_effects.append(effect)
	if optimized != null: optimized.batch.advance(delta)
	return false

func add_actor(index: int) -> bool:
	var actor := Avatar.new()
	world.add_child(actor)
	var race: String = ["human_male", "human_female", "rodian_male", "twilek_female"][index % 4]
	var result: Dictionary = actor.configure(race, {"profession":"combat_marksman"})
	if not str(result.get("error", "")).is_empty():
		fail(str(result.error))
		actor.queue_free()
		return false
	if not actor.ensure_animation("walk") or not actor.ensure_animation("idle"):
		fail("Original walk/idle animation missing for " + race)
		actor.queue_free()
		return false
	actor.animation_player.play("walk" if index < active_players else "idle")
	var clip: Animation = actor.animation_player.get_animation(actor.animation_player.current_animation)
	actor.animation_player.seek(fposmod((index + seed_value) * 0.61803398875, 1.0) * clip.length, true)
	for mesh: MeshInstance3D in actor.meshes:
		mesh.layers = 1
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var columns := 16
	var point := center + Vector3(float(index % columns) * 1.1 - 8.25, 0, (float(index / columns) - float(ceili(float(active_players + npc_count) / columns) - 1) * 0.5) * 1.1)
	var swg: Vector2 = terrain.source_position(point)
	point.y = terrain.evaluator.sample_height(swg.x, swg.y) - terrain.origin.y
	actor.position = point
	actor.rotation.y = PI
	actors.append(actor)
	positions.append(point)
	return true

func make_source_effect(path: String, persistent: bool, lifetime: float, index: int) -> Node3D:
	var effect := SourceEffect.new()
	world.add_child(effect)
	effect.configure(source_assets.catalog.particles[path], source_assets, camera, persistent, lifetime)
	# Seed before reset so random emitter timings and all emitted particles repeat.
	effect.rng.seed = seed_value + index
	effect.reset_playback()
	return effect

func create_bolts(count: int) -> void:
	if optimized != null:
		for handle in tracer_handles: optimized.release_tracer(handle)
		optimized.clear()
		optimized.set_view(camera.global_transform,camera.fov,float(resolution.x)/resolution.y)
	tracer_handles.clear()
	for effect in source_bolts + transient_effects:
		if is_instance_valid(effect):
			effect.free()
	source_bolts.clear()
	source_bolt_phases.clear()
	transient_effects.clear()
	effect_carry = 0
	effect_events = 0
	effects_dropped = 0
	if bolts != null:
		bolts.free()
	bolts = MultiMeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.028, 0.028, 0.65)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.12, 0.025, 0.8)
	mesh.material = material
	bolts.multimesh = MultiMesh.new()
	bolts.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	bolts.multimesh.mesh = mesh
	bolts.multimesh.instance_count = count
	world.add_child(bolts)
	bolts.visible = effect_mode == "surrogate"
	if effect_mode == "optimized":
		tracer_handles.resize(count)
		tracer_handles.fill(-1)
	if effect_mode == "source":
		for index in range(count):
			source_bolts.append(make_source_effect("appearance/pt_bolt_red.prt", true, 0.5, index))
			source_bolt_phases.append(0.0)

func run() -> void:
	output = str(options.get("output", local_path("runtime/evidence/render-viability.json")))
	seed_value = int(options.get("seed", 42))
	view_count = 2 if int(options.get("views", 1)) == 2 else 1
	effect_mode = str(options.get("effects", "optimized"))
	transient_cap = clampi(int(options.get("effect-cap", 64)), 0, 1024)
	if effect_mode not in ["optimized", "source", "surrogate", "none"]:
		fail("Invalid --effects, expected optimized/source/surrogate/none")
		write_report()
		quit(2)
		return
	if effect_mode in ["source","optimized"]:
		source_assets = OriginalAssets.new()
		if not source_assets.load_catalog():
			fail("Original combat assets missing")
			write_report()
			quit(2)
			return
		for required in ["appearance/pt_bolt_red.prt", "appearance/pt_bls_1_red_muz_flash_01.prt", "appearance/pt_bls_1_red_hit_other_01.prt"]:
			if not source_assets.catalog.get("particles", {}).has(required):
				fail("Original combat particle missing: " + required)
				write_report()
				quit(2)
				return
	var process_output: Array = []
	if OS.get_name() == "Linux" and OS.execute("pgrep", ["-a", "-x", "godot"], process_output) == 0:
		for chunk in process_output:
			for line in str(chunk).split("\n",false):
				if int(line.strip_edges().get_slice(" ",0)) != OS.get_process_id(): contention.append(line.strip_edges())
	warmup = maxf(0.1, float(options.get("warmup", 5)))
	duration = maxf(0.25, float(options.get("duration", 15)))
	npc_count = clampi(int(options.get("npcs", 16)), 0, 256)
	render_distance = clampf(float(options.get("world-radius", 384)), 128, 768)
	resolution = Vector2i(clampi(int(options.get("width", 1600)), 320, 4096), clampi(int(options.get("height", 900)), 240, 4096))
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name() != "vulkan":
		fail("Rendered benchmark requires a desktop display, Forward+ and Vulkan; headless is not performance evidence.")
		write_report()
		quit(2)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	# Fixed-size preview prevents the window manager changing the measured eye
	# resolution. Every measured eye renders to its own exact-size SubViewport.
	root.size = Vector2i(1280,800)
	root.title = "SWGXR Forward+ render viability — synthetic population / desktop only"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	camera.fov = 78
	camera.far = 2200
	world.add_child(camera)
	camera.position = center + Vector3(0, 14, -14)
	camera.look_at(center + Vector3(0,1,0))
	camera.make_current()
	measured_viewports.append(root)
	if view_count >= 1:
		root.disable_3d = true
		for index in range(view_count):
			var viewport := SubViewport.new()
			viewport.size = resolution
			viewport.world_3d = world.get_world_3d()
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
			measured_viewports.append(viewport)
			var eye := Camera3D.new()
			eye.fov = camera.fov
			eye.far = camera.far
			viewport.add_child(eye)
			eye.make_current()
			eye_cameras.append(eye)
			var display := TextureRect.new()
			# Disable texture minimum size before sizing the preview; otherwise
			# the root capture crops a native-resolution eye instead of fitting it.
			display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			display.texture = viewport.get_texture()
			display.position = Vector2(index * 1280.0/view_count, 0)
			display.size = Vector2(1280.0/view_count,800)
			display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			root.add_child(display)
	var start := Time.get_ticks_msec()
	var loader := StageLoader.new()
	stage = loader.load_stage(local_path("runtime/assets/mos_eisley/scene.json"))
	stage_report = loader.report
	if stage == null:
		fail(str(loader.report.error))
		write_report()
		quit(2)
		return
	world.add_child(stage)
	terrain = Terrain.new()
	world.add_child(terrain)
	buildings = WorldStream.new()
	buildings.render_distance = render_distance
	world.add_child(buildings)
	if not buildings.configure(local_path("runtime/assets/tatooine_world/world.json"), stage) or not terrain.configure(local_path("runtime/assets/terrain/tatooine.json"), loader.vec(loader.report.origin)):
		fail("Original world/terrain assets unavailable")
		write_report()
		quit(2)
		return
	terrain.set_cell_source(stage)
	# Camera and crowd share the authored terrain elevation, not stage-relative zero.
	var source_center: Vector2 = terrain.source_position(center)
	center.y = terrain.evaluator.sample_height(source_center.x,source_center.y) - terrain.origin.y
	buildings.update_observer(center)
	terrain.update_observer(center)
	var presentation := Presentation.new()
	world.add_child(presentation)
	if not presentation.configure(local_path("runtime/assets/tatooine_environment/environment.json")):
		fail("Original environment manifest unavailable")
	presentation.bind_world(terrain, stage)
	presentation.set_phase(0.25)
	# Fixed noon, audio disabled. Baked source shaders, no dynamic lights or shadows.
	presentation.set_process(false)
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if terrain.chunks.size() == terrain.desired.size() and int(buildings.report.get("pending_instances", 1)) == 0:
			break
	if terrain.chunks.size() != terrain.desired.size() or int(buildings.report.get("pending_instances", 1)) != 0:
		fail("Streaming did not settle before timeout")
	streaming_load_ms = Time.get_ticks_msec() - start
	if effect_mode == "optimized":
		optimized = OptimizedParticles.shared(world,source_assets,camera)
		optimized.set_process(false)
	for entry: String in str(options.get("players", "16,32,64,128")).split(","):
		active_players = clampi(int(entry), 1, 256)
		for actor: Node in actors:
			actor.free()
		actors.clear()
		positions.clear()
		for index in range(active_players + npc_count):
			if not add_actor(index):
				break
			if index % 4 == 0:
				await process_frame
		if actors.size() != active_players + npc_count:
			break
		create_bolts(ceili(active_players * 450.0 / 60.0 * 0.5))
		time_cursor = 0
		running = true
		measured = false
		await create_timer(warmup).timeout
		# Reject a fixture that animates a crowd outside the measured views.
		var visible_actors_per_view: Array[int] = []
		for eye: Camera3D in eye_cameras:
			var visible_count := 0
			for actor: Node3D in actors:
				if eye.is_position_in_frustum(actor.global_position + Vector3.UP * 0.1) and eye.is_position_in_frustum(actor.global_position + Vector3.UP * 1.8):
					visible_count += 1
			visible_actors_per_view.append(visible_count)
			if visible_count != actors.size():
				fail("Crowd framing excludes actors: %d of %d in view" % [visible_count,actors.size()])
		if not errors.is_empty():
			break
		# Rewind deterministic route after warmup; do not include GPU screenshot readback.
		time_cursor = 0
		samples.clear()
		last_tick = Time.get_ticks_usec()
		measured = true
		await create_timer(duration).timeout
		measured = false
		var metrics := {}
		for key in samples:
			metrics[key] = stats(samples[key], str(key).ends_with("_ms"))
		for optional in ["render_cpu_ms", "render_gpu_ms"]:
			if not metrics.has(optional):
				metrics[optional] = {"available":false,"reason":"Driver did not expose nonzero viewport timing"}
		var particle_stats: Dictionary = optimized.statistics() if optimized != null else {}
		if optimized != null:
			for pair in [["peak_particles","max_particles"],["peak_tracers","max_tracers"],["styles","max_styles"],["render_nodes","max_render_nodes"]]:
				if int(particle_stats.get(pair[0],-1)) < 0 or int(particle_stats[pair[0]]) > int(particle_stats.get(pair[1],-1)):
					fail("Native particle budget/report violation: "+pair[0])
		var frame: Dictionary = metrics.get("wall_frame_ms", {})
		var sufficient := int(frame.get("samples", 0)) >= 300 and duration >= 10
		results.append({"players":active_players,"npcs":npc_count,"animated_original_rigs":actors.size(),"actors_in_frustum_per_view":visible_actors_per_view,
			"effect_mode":effect_mode,"optimized_particle_stats":particle_stats,"transient_effect_cap":transient_cap if effect_mode == "source" else null,"effect_events_including_warmup":effect_events,"dropped_transient_visuals_including_warmup":effects_dropped,"requested_bolt_visuals":bolts.multimesh.instance_count if effect_mode != "none" else 0,"concurrent_legacy_bolt_visuals":bolts.multimesh.instance_count if effect_mode in ["source","surrogate"] else 0,"shots_per_second":active_players * 7.5,
			"warmup_seconds":warmup,"measurement_seconds":duration,"metrics":metrics,
			"target":{"hz":90,"frame_budget_ms":1000.0 / 90.0,"p95_budget_met":float(frame.get("p95", INF)) <= 1000.0 / 90.0,
				"p99_under_2_frames":float(frame.get("p99", INF)) <= 2000.0 / 90.0,"sufficient_duration_and_samples":sufficient,
				"status":"desktop_target_missed" if duration>=10 and float(frame.get("p95",INF))>1000.0/90.0 else ("desktop_target_met" if sufficient else "insufficient_samples")}})
		print("RENDER_SCENARIO " + JSON.stringify(results[-1]))
		var capture := str(options.get("capture", ""))
		if not capture.is_empty():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
			root.get_texture().get_image().save_png(capture.get_basename() + "-%d.png" % active_players)
		running = false
	write_report()
	world.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)

func write_report() -> void:
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var report := {"schema":1,"suite":"render_viability","errors":errors,"passed":errors.is_empty() and not results.is_empty(),"completed":errors.is_empty() and not results.is_empty(),
		"hardware_tested":DisplayServer.get_name() != "headless","headset_tested":false,"seed":seed_value,"concurrent_godot_processes_at_start":contention,"measurement_scope":"desktop Vulkan render; synthetic crowd and bolt presentation; no network, gameplay authority or HMD compositor",
		"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"asset_manifest_sha256":{"stage":FileAccess.get_sha256(local_path("runtime/assets/mos_eisley/scene.json")),"terrain":FileAccess.get_sha256(local_path("runtime/assets/terrain/tatooine.json")),"world":FileAccess.get_sha256(local_path("runtime/assets/tatooine_world/world.json")),"characters":FileAccess.get_sha256(local_path("runtime/assets/characters/catalog.json")),"combat":FileAccess.get_sha256(local_path("runtime/assets/combat/assets.json"))},
		"gpu":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info().string,
		"resolution_per_view":[resolution.x,resolution.y],"actual_eye_viewports":measured_viewports.slice(1).map(func(v):return [v.size.x,v.size.y]),"actual_root_viewport":[root.size.x,root.size.y],"views":view_count,"projection":"two independent symmetric views, 64 mm baseline; no OpenXR multiview, distortion or runtime" if view_count == 2 else "desktop mono","vsync_requested":"disabled","world_radius_m":render_distance,
		"streaming_load_ms":streaming_load_ms,"stage":stage_report,"terrain_chunks":terrain.chunks.size() if terrain != null else 0,
		"world":buildings.report if buildings != null else {},"scenarios":results,
		"timing_sources":{"wall_frame_ms":"monotonic time between SceneTree process callbacks","process_monitor_ms":"Godot TIME_PROCESS monitor; refresh can lag frames, not per-frame CPU trace","physics_monitor_ms":"Godot TIME_PHYSICS_PROCESS monitor; refresh can lag frames","render_cpu_ms":"sum of nonzero viewport measured CPU times, including root composite","render_gpu_ms":"sum of nonzero viewport measured GPU times, including root composite; may lag"},
		"limitations":["Desktop wall-frame budget is only a screening target; no MMO or live VR capacity claim",
			"No local-user tracked IK, network decode, audio, spectator view or remote finger reconstruction",
			"Two-view mode is a separate-view draw workload surrogate, not true OpenXR stereo/multiview",
			"Fixed source noon lighting, exterior route, warmed resident world; cold streaming recorded separately",
			"Four original races and starter outfits; no animation LOD; original clips animate every actor",
			"Optimized mode uses the production native batch with hard budgets, distance/frustum LOD; source mode preserves legacy playback for comparison",
			"Counts report deliberately omitted visuals; source reference has a separate transient cap",
			"Source audio, transient lights and camera shake excluded; surrogate mode uses synthetic pooled alpha bolts only",
			"Particle presentation only; authoritative collision measured by simulation suite",
			"Concurrent live applications can contend for GPU/CPU; record external load with run"]}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("RENDER_VIABILITY_REPORT " + output)
