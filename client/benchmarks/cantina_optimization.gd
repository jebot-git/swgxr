extends SceneTree
## Fixed actual-world desktop screening, never a headset performance claim.
var args := {}
var errors: Array[String] = []
var app: Node3D
var output := ""
var captures := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var split := arg.substr(2).split("=",true,1)
			args[split[0]] = split[1] if split.size()>1 else true
	output = str(args.get("output","res://../runtime/evidence/cantina-optimization.json"))
	captures = args.has("capture") and DisplayServer.get_name()!="headless"
	call_deferred("run")

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in sorted: sum += float(value)
	return {"count":sorted.size(),"mean":sum/sorted.size(),"p50":sorted[int((sorted.size()-1)*0.5)],"p95":sorted[int((sorted.size()-1)*0.95)],"p99":sorted[int((sorted.size()-1)*0.99)],"max":sorted[-1]}

func run() -> void:
	root.size = Vector2i(1280,800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var deadline := Time.get_ticks_msec()+180000
	while not app.world_ready and Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(app.loading_screen) and app.loading_screen.failed: break
	if not app.world_ready:
		errors.append("Actual application did not finish entry")
		finish({})
		return
	# Stop input, locomotion, observer streaming and changing time of day. Existing
	# resident scenery, NPC scheduler, portal queries and animation remain active.
	app.set_process(false)
	app.player.active = false
	app.player.set_physics_process(false)
	app.player.set_process_input(false)
	app.player.set_process_unhandled_input(false)
	app.player.global_position = Vector3(-190.798396,-0.894992,22.327722)
	app.stage.seed_membership_at(app.player.global_position,"1082874:3")
	app.environment_presentation.set_process(false)
	app.ui_root.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera: Camera3D = app.player.get_camera()
	camera.global_position = app.player.global_position+Vector3.UP*1.7
	var views := [{"name":"band","target":Vector3(-195,0.8,31)},
		{"name":"bar","target":Vector3(-174,0.8,29)}]
	var results: Array = []
	for view in views:
		camera.look_at(view.target)
		await create_timer(clampf(float(args.get("warmup",5)),0.1,30)).timeout
		var intervals: Array = []
		var draw_calls: Array = []
		var primitives: Array = []
		var snapshots: Array = []
		var next_snapshot := 0
		var last := Time.get_ticks_usec()
		var end := last+int(clampf(float(args.get("duration",15)),0.2,120)*1000000)
		while Time.get_ticks_usec()<end:
			await process_frame
			var now := Time.get_ticks_usec()
			if intervals.size()<36000: intervals.append((now-last)/1000.0)
			else: errors.append("Frame sample capacity exceeded"); break
			last = now
			if now>=next_snapshot:
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				snapshots.append({"portal":app.portal_visibility.report.duplicate(true),"npc":app.ambient_npcs.report.duplicate(true)})
				next_snapshot = now+1000000
		if captures:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.get_basename()+"-"+str(view.name)+".png")
		results.append({"view":view.name,"frame_interval_ms":stats(intervals),"draw_calls":stats(draw_calls),"primitives":stats(primitives),"snapshots":snapshots})
	finish({"views":results,"world":app.world_stream.report.duplicate(true),"terrain":app.terrain.report.duplicate(true)})

func finish(report: Dictionary) -> void:
	report.merge({"test":"fixed_cantina_optimization","passed":errors.is_empty(),"errors":errors,
		"flags":args,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
		"display":DisplayServer.get_name(),"viewport":[1280,800],"live_headset_tested":false,
		"limitations":["Fixed desktop mono scene, no XR compositor or spectator; not comparable to live VR FPS",
			"Dummy audio; fixed observer and time of day; no gameplay input or network load",
			"Frame callback intervals include engine rendering and pacing; draw monitors are sampled once per second"]})
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CANTINA_OPTIMIZATION "+JSON.stringify({"passed":errors.is_empty(),"errors":errors,"output":output}))
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		await process_frame
	quit(0 if errors.is_empty() else 1)
