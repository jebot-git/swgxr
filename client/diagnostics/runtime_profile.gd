extends Node
## Opt-in local diagnostic. Wall-clock samples remain distinct from engine EMA monitors.
const MAX_FRAMES := 36000
const MAX_SAMPLES := 240
const DEFAULT_DURATIONS := {"warmup":10.0,"scripts":20.0,"baseline_warmup":5.0,"baseline":70.0}
const MONITORS := {
	"fps":Performance.TIME_FPS,"process_seconds":Performance.TIME_PROCESS,
	"physics_seconds":Performance.TIME_PHYSICS_PROCESS,"draw_objects":Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
	"draw_calls":Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,"primitives":Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"static_memory_bytes":Performance.MEMORY_STATIC,"video_memory_bytes":Performance.RENDER_VIDEO_MEM_USED,
	"texture_memory_bytes":Performance.RENDER_TEXTURE_MEM_USED,"buffer_memory_bytes":Performance.RENDER_BUFFER_MEM_USED,
	"objects":Performance.OBJECT_COUNT,"nodes":Performance.OBJECT_NODE_COUNT,
	"physics_active_objects":Performance.PHYSICS_3D_ACTIVE_OBJECTS,"physics_collision_pairs":Performance.PHYSICS_3D_COLLISION_PAIRS}
var target: Node
var output_dir := ""
var durations := DEFAULT_DURATIONS.duplicate()
var phase := "disabled"
var phase_start_ticks_usec := 0
var previous_ticks_usec := 0
var next_sample_ticks_usec := 0
var owns_profiler := false
var profiler_start_pending := false
var profiler_stop_pending := false
var profiler_available := false
var profiler_error := ""
var frames := {"scripts":[],"baseline":[]}
var dropped_frames := {"scripts":0,"baseline":0}
var samples: Array = []
var transitions: Array = []
var report := {}
var io_error := ""

func configure(source: Node, directory: String, timing: Dictionary = {}) -> bool:
	set_process(false)
	if not directory.is_absolute_path():
		push_warning("Runtime profile output must be an absolute directory")
		return false
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_warning("Cannot create runtime profile output directory: "+directory)
		return false
	target = source
	output_dir = directory
	for key in durations:
		durations[key] = clampf(float(timing.get(key,durations[key])),0.05,120.0)
	profiler_available = EngineDebugger.is_active() and EngineDebugger.has_profiler("scripts")
	if not profiler_available:
		profiler_error = "Local scripts profiler unavailable; launch Godot with --debug --ignore-error-breaks. Baseline collection remains available."
	elif EngineDebugger.is_profiling("scripts"):
		profiler_available = false
		profiler_error = "Scripts profiler was already enabled; refusing to alter external profiling. Baseline is contaminated."
	change_phase("waiting_world",Time.get_ticks_usec())
	set_process(true)
	return io_error.is_empty()

func _process(_delta: float) -> void:
	advance(Time.get_ticks_usec())

func advance(now: int) -> void:
	if phase == "done" or phase == "disabled": return
	if profiler_start_pending and EngineDebugger.is_profiling("scripts"):
		profiler_start_pending = false
		owns_profiler = true
	if profiler_stop_pending and not EngineDebugger.is_profiling("scripts"):
		profiler_stop_pending = false
		owns_profiler = false
	if not is_instance_valid(target):
		finish(now,"Observed main node was removed")
		return
	if phase == "waiting_world":
		if bool(target.get("world_ready")): change_phase("warmup",now)
		elif now >= next_sample_ticks_usec:
			write_status(now)
			next_sample_ticks_usec = now+1000000
		return
	if frames.has(phase) and previous_ticks_usec>0:
		if frames[phase].size()<MAX_FRAMES: frames[phase].append(now-previous_ticks_usec)
		else: dropped_frames[phase] += 1
	previous_ticks_usec = now
	if now >= next_sample_ticks_usec:
		collect_sample(now)
		write_status(now)
		next_sample_ticks_usec = now+1000000
	if now-phase_start_ticks_usec < int(float(durations[phase])*1000000): return
	match phase:
		"warmup": change_phase("scripts",now)
		"scripts": change_phase("baseline_warmup",now)
		"baseline_warmup": change_phase("baseline",now)
		"baseline": finish(now)

func change_phase(next: String, now: int) -> void:
	if owns_profiler or profiler_start_pending: stop_profiler()
	phase = next
	phase_start_ticks_usec = now
	previous_ticks_usec = 0
	next_sample_ticks_usec = now
	if phase == "scripts" and profiler_available:
		# Toggle on the native singleton after the GDScript stack unwinds. Starting
		# synchronously charges this function's unprofiled entry as spurious time.
		profiler_start_pending = true
		EngineDebugger.call_deferred("profiler_enable","scripts",true)
	transitions.append({"phase":phase,"ticks_usec":now})
	print("SWG_RUNTIME_PROFILE "+phase+" ticks_usec="+str(now))
	write_status(now)

func write_atomic(filename: String, value: Dictionary) -> void:
	var path := output_dir.path_join(filename)
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		io_error = "Cannot write "+path
		return
	file.store_string(JSON.stringify(value))
	file.close()
	if DirAccess.rename_absolute(path+".tmp",path)!=OK: io_error = "Cannot publish "+path

func write_status(now: int) -> void:
	var visibility: Variant = target.get("portal_visibility") if is_instance_valid(target) else null
	var culling: Dictionary = {}
	if is_instance_valid(visibility): culling = visibility.get("report").get("culling", {})
	write_atomic("status.json",{"phase":phase,"ticks_usec":now,"phase_start_ticks_usec":phase_start_ticks_usec,
		"phase_duration_seconds":durations.get(phase,0),"scripts_profiler_active":EngineDebugger.is_profiling("scripts"),
		"profiler_start_pending":profiler_start_pending,"profiler_stop_pending":profiler_stop_pending,
		"profiler_available":profiler_available,"profiler_error":profiler_error,"io_error":io_error,"pid":OS.get_process_id(),
		"portal_culling":bounded_snapshot(culling),"world_ready":bool(target.get("world_ready")),
		"xr_initialized":bool(target.get("xr_initialized")),"xr_focused":bool(target.get("xr_focused"))})

func collect_sample(now: int) -> void:
	if samples.size()>=MAX_SAMPLES: return
	var sample := {"phase":phase,"ticks_usec":now,"world_ready":bool(target.get("world_ready"))}
	for key in MONITORS: sample[key] = Performance.get_monitor(MONITORS[key])
	for key in ["world_stream","ambient_npcs","portal_visibility","terrain"]:
		var subsystem: Variant = target.get(key)
		if is_instance_valid(subsystem): sample[key] = bounded_snapshot(subsystem.get("report"))
	var player: Variant = target.get("player")
	if is_instance_valid(player):
		var p: Vector3 = player.global_position
		sample["player_position"] = [p.x,p.y,p.z]
	var combat: Variant = target.get("live_combat")
	if is_instance_valid(combat): sample["live_combat"] = bounded_snapshot(combat.statistics())
	sample["xr_focused"] = bool(target.get("xr_focused"))
	samples.append(sample)

func bounded_snapshot(value: Variant, depth: int = 0) -> Variant:
	if depth>3: return "nested report omitted"
	if value is Dictionary:
		var result := {}
		for key in value.keys().slice(0,48): result[str(key)] = bounded_snapshot(value[key],depth+1)
		return result
	if value is Array:
		return {"count":value.size(),"items":value.slice(0,4).map(func(item): return bounded_snapshot(item,depth+1))}
	if value is String: return value.left(256)
	return value if value == null or value is int or value is float or value is bool else str(value).left(128)

func summarize(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"count":values.size(),"mean_ms":total/values.size()/1000.0,"p50_ms":float(ordered[int((ordered.size()-1)*0.5)])/1000.0,
		"p95_ms":float(ordered[int((ordered.size()-1)*0.95)])/1000.0,"p99_ms":float(ordered[int((ordered.size()-1)*0.99)])/1000.0,"max_ms":float(ordered[-1])/1000.0}

func finish(now: int, error: String = "") -> void:
	change_phase("done",now)
	var profiled := summarize(frames.scripts)
	var baseline := summarize(frames.baseline)
	report = {"schema":1,"pid":OS.get_process_id(),"engine":Engine.get_version_info(),"durations_seconds":durations,
		"profiler_available":profiler_available,"profiler_error":profiler_error,"error":error,"io_error":io_error,
		"transitions":transitions,"samples":samples,"frame_intervals_usec":frames,"dropped_frame_samples":dropped_frames,
		"summary":{"scripts":profiled,"baseline":baseline},"renderer":RenderingServer.get_current_rendering_method(),
		"display_server":DisplayServer.get_name(),"limits":[
			"Script profiling instruments GDScript and prints to stdout; profiled timing is not a normal-play baseline.",
			"Profile-versus-baseline difference is observed overhead plus changing scene/user workload; it is not isolated causal overhead.",
			"Performance process/physics values are engine-smoothed monitors, not per-frame samples; some monitors refresh at most once per second.",
			"Wall-clock process callback intervals include pacing and stalls; they do not isolate CPU, GPU, compositor or WiVRn latency.",
			"Draw counters aggregate engine viewports; headless Dummy results do not validate rendering.",
			"Collection is bounded to 36000 intervals per measured phase and 240 monitor samples; dropped counts are explicit."]}
	if profiled.get("count",0)>0 and baseline.get("count",0)>0:
		report["observed_profile_mean_ratio"] = profiled.mean_ms/maxf(0.000001,baseline.mean_ms)
	write_atomic("report.json",report)
	write_status(now)
	set_process(false)

func stop_profiler() -> void:
	if profiler_stop_pending: return
	profiler_start_pending = false
	profiler_stop_pending = true
	EngineDebugger.call_deferred("profiler_enable","scripts",false)

func _exit_tree() -> void:
	if owns_profiler or profiler_start_pending: stop_profiler()
