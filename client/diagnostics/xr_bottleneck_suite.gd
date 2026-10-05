extends Node
## Explicit controlled diagnostic, never enabled during ordinary play.
const CONDITIONS := ["baseline","no_spectator","frozen_npc_animation","headset_half_resolution","scene_hidden","restore_baseline"]
const MAX_FRAMES := 12000
const MAX_SAMPLES := 900
const MONITORS := preload("res://diagnostics/runtime_profile.gd").MONITORS
var active := false
var npc_frozen := false
var phase := "disabled"
var condition := ""
var measuring := false
var target: Node
var output_dir := ""
var timing := {"warmup":10.0,"notice":2.0,"settle":3.0,"measure":20.0}
var saved := {}
var npc_snapshot: Array = []
var results := {}
var transitions: Array = []
var samples: Array = []
var report := {}
var error := ""
var io_error := ""
var index := -1
var phase_start_ticks_usec := 0
var previous_ticks_usec := 0
var next_status_ticks_usec := 0
var origin_head := Transform3D.IDENTITY
var origin_player := Vector3.ZERO
var desktop: CanvasLayer
var desktop_text: Label
var head_text: Label3D
var head: Camera3D
var xr_viewport: Viewport
var spectator: Node
var npcs: Node
var viewports := {}
var measurement_enabled := false
var captured := false
var restored := false

func configure(source: Node, directory: String, overrides: Dictionary = {}) -> bool:
	set_process(false)
	if not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory)!=OK:
		push_warning("XR bottleneck suite needs a writable absolute output directory")
		return false
	target=source; output_dir=directory
	for key in timing: timing[key]=clampf(float(overrides.get(key,timing[key])),0.02,60.0)
	process_priority=10000
	set_phase("waiting_world",Time.get_ticks_usec())
	set_process(true)
	return io_error.is_empty()

func _process(_delta: float) -> void:
	advance(Time.get_ticks_usec())

func advance(now: int) -> void:
	if phase in ["done","failed","disabled"]: return
	if not io_error.is_empty():
		finish(io_error,now)
		return
	if not is_instance_valid(target):
		finish("Main node removed",now)
		return
	if phase=="waiting_world":
		if bool(target.get("world_ready")):
			if not capture_state():
				finish("XR viewport, player camera or spectator unavailable",now)
				return
			active=true
			gate_controls()
			show_notice("Controlled XR test\nKeep still and face the same view.\nScene will briefly go dark, then restore.")
			set_phase("warmup",now)
		elif now>=next_status_ticks_usec: publish_status(now)
		return
	if not bool(target.get("world_ready")) or not is_instance_valid(head) or not is_instance_valid(xr_viewport):
		finish("World or XR view became unavailable",now)
		return
	gate_controls()
	if measuring:
		var entry: Dictionary=results[condition]
		if previous_ticks_usec>0:
			if entry.frame_intervals_usec.size()<MAX_FRAMES: entry.frame_intervals_usec.append(now-previous_ticks_usec)
			else: entry.dropped_frames+=1
		previous_ticks_usec=now
		entry.observed_frames+=1
		if not bool(target.get("xr_focused")): entry.unfocused_frames+=1
		entry.max_head_translation_m=maxf(entry.max_head_translation_m,head.global_position.distance_to(origin_head.origin))
		entry.max_head_rotation_degrees=maxf(entry.max_head_rotation_degrees,rad_to_deg(head.global_basis.get_rotation_quaternion().angle_to(origin_head.basis.get_rotation_quaternion())))
		entry.max_player_translation_m=maxf(entry.max_player_translation_m,target.player.global_position.distance_to(origin_player))
	if now>=next_status_ticks_usec:
		collect_sample(now)
		publish_status(now)
	var duration:=float(timing.measure if measuring else timing.get(phase,0.0))
	if now-phase_start_ticks_usec<int(duration*1000000): return
	if phase=="warmup": begin_next(now)
	elif phase=="notice":
		apply_condition()
		head_text.visible=false
		set_phase("settle",now)
	elif phase=="settle":
		results[condition]={"frame_intervals_usec":[],"dropped_frames":0,"observed_frames":0,"unfocused_frames":0,
			"max_head_translation_m":0.0,"max_head_rotation_degrees":0.0,"max_player_translation_m":0.0,"start_ticks_usec":now}
		measuring=true
		set_phase(condition,now)
	elif measuring:
		results[condition].end_ticks_usec=now
		results[condition].summary=summarize(results[condition].frame_intervals_usec)
		measuring=false
		begin_next(now)

func capture_state() -> bool:
	var player: Node=target.get("player")
	if not is_instance_valid(player) or not player.has_method("get_camera"): return false
	head=player.get_camera()
	xr_viewport=target.get("xr_viewport")
	spectator=target.get("xr_spectator")
	npcs=target.get("ambient_npcs")
	if not is_instance_valid(head) or not is_instance_valid(xr_viewport) or not is_instance_valid(spectator): return false
	saved={"head_mask":head.cull_mask,"head_environment":head.environment,"scale":xr_viewport.scaling_3d_scale,
		"scaling_mode":xr_viewport.scaling_3d_mode,"player_active":player.get("active"),
		"spectator_enabled":spectator.get("enabled"),"spectator_visible":spectator.get("visible"),
		"spectator_process":spectator.is_processing(),"spectator_physics":spectator.is_physics_processing(),
		"spectator_update":spectator.viewport.render_target_update_mode,
		"npc_process":npcs.is_processing() if is_instance_valid(npcs) else false}
	for key in ["combat_rig","datapad"]:
		var item: Node=target.get(key)
		if is_instance_valid(item): saved[key+"_allowed"]=item.get("allowed")
	origin_head=head.global_transform
	origin_player=player.global_position
	viewports={"headset":xr_viewport,"spectator":spectator.viewport,"root":get_tree().root}
	# Godot exposes no getter for this instrumentation flag. This opt-in suite
	# exclusively owns it and turns it off again on every completion/abort path.
	for viewport: Viewport in viewports.values(): RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	measurement_enabled=true
	captured=true
	create_notice()
	return true

func create_notice() -> void:
	desktop=CanvasLayer.new(); desktop.layer=101; add_child(desktop)
	desktop_text=Label.new(); desktop.add_child(desktop_text)
	desktop_text.position=Vector2(20,20); desktop_text.add_theme_font_size_override("font_size",24)
	desktop_text.add_theme_color_override("font_shadow_color",Color.BLACK)
	desktop_text.add_theme_constant_override("shadow_outline_size",8)
	head_text=Label3D.new(); head_text.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf"); head_text.name="DiagnosticNotice"; head.add_child(head_text)
	head_text.position=Vector3(0,-0.12,-1.3); head_text.font_size=40; head_text.pixel_size=0.0007
	head_text.no_depth_test=true; head_text.modulate=Color(0.65,0.95,1.0)
	head_text.outline_size=8; head_text.layers=int(saved.head_mask)

func gate_controls() -> void:
	if not active: return
	if is_instance_valid(target.get("player")): target.player.set("active",false)
	for key in ["combat_rig","datapad"]:
		var item: Node=target.get(key)
		if is_instance_valid(item) and item.has_method("set_allowed"): item.set_allowed(false)

func show_notice(message: String) -> void:
	if is_instance_valid(head_text): head_text.text=message; head_text.visible=true
	if is_instance_valid(desktop_text): desktop_text.text=message

func begin_next(now: int) -> void:
	restore_condition()
	index+=1
	if index>=CONDITIONS.size():
		finish("",now)
		return
	condition=CONDITIONS[index]
	var message: String="Next: "+condition.replace("_"," ")+"\nKeep still; measuring for %.0f seconds."%timing.measure
	if condition=="scene_hidden": message="Next: scene hidden for %.0f seconds\nThe view will go dark. Keep still.\nIt restores automatically; tracking stays active."%timing.measure
	show_notice(message)
	set_phase("notice",now)

func apply_condition() -> void:
	if condition in ["no_spectator","scene_hidden"]:
		spectator.set("enabled",false); spectator.set_process(false); spectator.set_physics_process(false)
		spectator.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if condition=="frozen_npc_animation" and is_instance_valid(npcs):
		npc_frozen=true
		npcs.set_process(false)
		npc_snapshot=[]
		for record: Dictionary in npcs.records.values():
			var actor: Node=record.avatar
			for player: AnimationPlayer in [actor.animation_player,actor.face_player]:
				if player==null: continue
				npc_snapshot.append({"player":player,"active":player.active})
				player.active=false
	if condition=="headset_half_resolution":
		xr_viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_BILINEAR
		xr_viewport.scaling_3d_scale=maxf(0.1,float(saved.scale)*0.5)
	if condition=="scene_hidden":
		head.cull_mask=0
		var dark:=Environment.new(); dark.background_mode=Environment.BG_COLOR; dark.background_color=Color.BLACK
		head.environment=dark

func restore_condition() -> void:
	if not captured: return
	if is_instance_valid(head): head.cull_mask=int(saved.head_mask); head.environment=saved.head_environment
	if is_instance_valid(xr_viewport): xr_viewport.scaling_3d_mode=int(saved.scaling_mode); xr_viewport.scaling_3d_scale=float(saved.scale)
	if is_instance_valid(spectator):
		spectator.set("enabled",saved.spectator_enabled); spectator.set("visible",saved.spectator_visible)
		spectator.set_process(bool(saved.spectator_process)); spectator.set_physics_process(bool(saved.spectator_physics))
		if is_instance_valid(spectator.viewport): spectator.viewport.render_target_update_mode=int(saved.spectator_update)
	for snapshot: Dictionary in npc_snapshot:
		if is_instance_valid(snapshot.player): snapshot.player.active=snapshot.active
	npc_snapshot.clear()
	if is_instance_valid(npcs): npcs.set_process(bool(saved.npc_process))
	npc_frozen=false

func set_phase(value: String, now: int) -> void:
	phase=value; phase_start_ticks_usec=now; previous_ticks_usec=0
	transitions.append({"phase":phase,"condition":condition,"measuring":measuring,"ticks_usec":now})
	print("SWG_XR_BOTTLENECK "+phase+" condition="+condition+" ticks_usec="+str(now))
	publish_status(now)

func publish_status(now: int) -> void:
	next_status_ticks_usec=now+1000000
	var duration:=float(timing.measure if measuring else timing.get(phase,0.0))
	var remaining:=maxf(0.0,duration-float(now-phase_start_ticks_usec)/1000000.0)
	if is_instance_valid(desktop_text): desktop_text.text="XR diagnostic: %s / %s\n%.0f seconds remaining · keep still"%[condition,phase,ceil(remaining)]
	write_atomic("status.json",{"phase":phase,"condition":condition,"measuring":measuring,"active":active,"ticks_usec":now,
		"phase_start_ticks_usec":phase_start_ticks_usec,"phase_duration_seconds":duration,"remaining_seconds":remaining,
		"pid":OS.get_process_id(),"npc_frozen":npc_frozen,"error":error,"io_error":io_error})

func viewport_sample(viewport: Viewport, name_key: String) -> Dictionary:
	var rid:=viewport.get_viewport_rid()
	var cpu:=RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var gpu:=RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var enabled: bool=name_key!="spectator" or (is_instance_valid(spectator) and bool(spectator.get("enabled")))
	return {"cpu_ms":cpu if enabled else null,"gpu_ms":gpu if enabled else null,"enabled":enabled,
		"timing_available":enabled and (cpu>0 or gpu>0),"last_rendered_frame_not_synchronized":true,
		"viewport_size":[viewport.size.x,viewport.size.y],"scaling_3d_scale_requested":viewport.scaling_3d_scale,
		"scaling_3d_mode":viewport.scaling_3d_mode,"use_xr":viewport.use_xr}

func collect_sample(now: int) -> void:
	if not captured or samples.size()>=MAX_SAMPLES: return
	var sample: Dictionary={"phase":phase,"condition":condition,"measuring":measuring,"ticks_usec":now,"xr_focused":bool(target.get("xr_focused")),
		"head_position":vector_array(head.global_position),"head_quaternion":quaternion_array(head.global_basis.get_rotation_quaternion()),
		"player_position":vector_array(target.player.global_position),"head_cull_mask":head.cull_mask,
		"render_frame_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"viewports":{}}
	for key in MONITORS: sample[key]=Performance.get_monitor(MONITORS[key])
	for key in viewports:
		var viewport: Viewport=viewports[key]
		if is_instance_valid(viewport): sample.viewports[key]=viewport_sample(viewport,key)
	if is_instance_valid(npcs):
		sample["npcs"]={"instances":npcs.records.size(),"manager_processing":npcs.is_processing(),"active_body_players":0,"active_face_players":0}
		for record: Dictionary in npcs.records.values():
			if record.avatar.animation_player!=null and record.avatar.animation_player.active: sample.npcs.active_body_players+=1
			if record.avatar.face_player!=null and record.avatar.face_player.active: sample.npcs.active_face_players+=1
	var world: Node=target.get("world_stream")
	if is_instance_valid(world):
		sample["world"]={}
		for key in ["instances","loaded_cells","loaded_chunks","pending_instances","active_workers"]: sample.world[key]=world.report.get(key,0)
	var visibility: Node=target.get("portal_visibility")
	if is_instance_valid(visibility):
		var culling: Dictionary=visibility.report.get("culling",{})
		sample["portal_culling"]={}
		for key in ["enabled","managed_instances","hidden_instances","revision","bounds_complete","bounds_queries","bounds_rejected","view_count","cpu_usec"]:
			sample.portal_culling[key]=culling.get(key)
		var tracking: Dictionary=culling.get("view_tracking",{})
		sample.portal_culling["view_tracking"]={}
		for key in ["source","fail_open_reason","head_pose_confidence","head_pose_has_tracking_data"]:
			sample.portal_culling.view_tracking[key]=tracking.get(key)
	samples.append(sample)

func vector_array(value: Vector3) -> Array: return [value.x,value.y,value.z]
func quaternion_array(value: Quaternion) -> Array: return [value.x,value.y,value.z,value.w]

func summarize(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var ordered:=values.duplicate(); ordered.sort(); var total:=0.0
	for value in values: total+=float(value)
	return {"count":values.size(),"mean_ms":total/values.size()/1000.0,"p50_ms":float(ordered[int((ordered.size()-1)*0.5)])/1000.0,
		"p95_ms":float(ordered[int((ordered.size()-1)*0.95)])/1000.0,"p99_ms":float(ordered[int((ordered.size()-1)*0.99)])/1000.0,"max_ms":float(ordered[-1])/1000.0}

func restore_all() -> void:
	if restored: return
	restore_condition()
	active=false
	if captured and is_instance_valid(target):
		if is_instance_valid(target.get("player")): target.player.set("active",saved.player_active)
		for key in ["combat_rig","datapad"]:
			var item: Node=target.get(key)
			if is_instance_valid(item) and saved.has(key+"_allowed") and item.has_method("set_allowed"): item.set_allowed(bool(saved[key+"_allowed"]))
	if measurement_enabled:
		for viewport: Viewport in viewports.values():
			if is_instance_valid(viewport): RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),false)
		measurement_enabled=false
	if is_instance_valid(head_text): head_text.queue_free()
	if is_instance_valid(desktop): desktop.queue_free()
	restored=true

func finish(reason: String, now: int) -> void:
	error=reason
	restore_all()
	if is_instance_valid(target) and target.has_method("sync_xr_activity"): target.sync_xr_activity()
	measuring=false
	report={"schema":1,"test":"controlled_xr_bottlenecks","pid":OS.get_process_id(),"engine":Engine.get_version_info(),
		"error":error,"io_error":io_error,"restored":restored,"timing_seconds":timing,"phases":results,"samples":samples,"transitions":transitions,
		"renderer":RenderingServer.get_current_rendering_method(),"display_server":DisplayServer.get_name(),
		"initial_head_transform":{"position":vector_array(origin_head.origin),"quaternion":quaternion_array(origin_head.basis.get_rotation_quaternion())},
		"limitations":["Opt-in same-process controlled changes, not normal-play performance qualification.",
			"Head/controller tracking stays live; head/body drift and focus are measured, not driven or corrected.",
			"Viewport CPU/GPU timings are asynchronous last-rendered-frame values in milliseconds; disabled views are null, not zero. Do not blindly sum stale viewport timings.",
			"Half resolution changes requested viewport internal scale per axis, not OpenXR swapchain size. Actual internal buffer dimensions are not publicly queried.",
			"Scene-hidden removes scene drawing and mirror output, but retains engine simulation, animation, physics, audio and XR submission; it is not a pure compositor benchmark.",
			"Frozen NPC animation also disables its ambient manager processing; the difference combines animation/skin/attachment and NPC orchestration costs.",
			"Measured phases follow notice and settling windows; phase drift or lost focus can invalidate comparisons.",
			"Render-time instrumentation has no public prior-state getter; suite exclusively enables it for all phases and disables it when done.",
			"Bounded to12000frame intervals per phase and900monitor snapshots; no GPU validation from Dummy tests."]}
	write_atomic("report.json",report)
	set_phase("done" if error.is_empty() else "failed",now)
	set_process(false)

func write_atomic(filename: String, value: Dictionary) -> void:
	var path:=output_dir.path_join(filename)
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: io_error="Cannot write "+path; return
	file.store_string(JSON.stringify(value)); file.close()
	if DirAccess.rename_absolute(path+".tmp",path)!=OK: io_error="Cannot publish "+path

func _exit_tree() -> void:
	restore_all()
	if is_instance_valid(target) and target.has_method("sync_xr_activity"): target.sync_xr_activity()

func cancel(reason: String = "Cancelled by user") -> void:
	if phase not in ["done","failed","disabled"]: finish(reason,Time.get_ticks_usec())
