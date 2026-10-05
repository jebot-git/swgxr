extends SceneTree
const Diagnostic = preload("res://diagnostics/runtime_profile.gd")
class MainProbe extends Node3D:
	var world_ready := false
	var xr_focused := true
	var world_stream: Node
	var ambient_npcs: Node
	var portal_visibility: Node
	var terrain: Node
	var player: Node3D
var errors: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var main := MainProbe.new()
	root.add_child(main)
	main.player = Node3D.new()
	main.add_child(main.player)
	main.player.position = Vector3(10,2,30)
	var initial := main.player.transform
	var diagnostic := Diagnostic.new()
	main.add_child(diagnostic)
	var output := ProjectSettings.globalize_path("res://../runtime/evidence/runtime-profile-smoke")
	check(diagnostic.configure(main,output,{"warmup":0.05,"scripts":1.1,"baseline_warmup":0.05,"baseline":0.1}),"Absolute output directory accepted")
	check(diagnostic.profiler_available,"Installed Godot --debug exposes local scripts profiler")
	await create_timer(0.05).timeout
	check(diagnostic.phase=="waiting_world" and not EngineDebugger.is_profiling("scripts"),"Profiler waits for world readiness")
	main.world_ready = true
	var observed := false
	while diagnostic.phase!="done":
		if diagnostic.phase=="scripts": observed = observed or EngineDebugger.is_profiling("scripts")
		await process_frame
	check(observed,"Real local script profiler enabled during scripts phase")
	check(not EngineDebugger.is_profiling("scripts"),"Profiler is disabled before completing baseline")
	check(main.player.transform==initial and main.is_inside_tree(),"Diagnostic preserves player transform and leaves client running")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("report.json")))
	var status: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("status.json")))
	check(status.phase=="done" and not status.scripts_profiler_active,"Atomic completion status published")
	check(report.transitions.map(func(t): return t.phase)==["waiting_world","warmup","scripts","baseline_warmup","baseline","done"],"Phase ordering separates profiling and baseline")
	check(report.summary.scripts.count>0 and report.summary.baseline.count>0,"Both measured phases record wall-clock samples")
	check(report.samples.size()>0 and report.samples[0].has("draw_calls") and report.samples[0].has("physics_seconds"),"Engine monitor snapshots collected")
	check(report.display_server=="headless" and report.has("limits"),"Report identifies Dummy/headless scope and monitor limits")
	check(not FileAccess.file_exists(output.path_join("status.json.tmp")),"Atomic temporary status file consumed")
	var second := Diagnostic.new()
	main.add_child(second)
	second.configure(main,output.path_join("shutdown"),{"warmup":0.05,"scripts":1.0})
	second.set_process(false)
	second.change_phase("scripts",Time.get_ticks_usec())
	await process_frame
	await process_frame
	second.advance(Time.get_ticks_usec())
	check(EngineDebugger.is_profiling("scripts"),"Shutdown probe owns profiler")
	second.queue_free()
	await process_frame
	await process_frame
	check(not EngineDebugger.is_profiling("scripts"),"Node shutdown relinquishes owned profiler")
	main.queue_free()
	await process_frame
	var result := {"test":"runtime_profile_lifecycle","checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_validated":false}
	FileAccess.open("res://../runtime/evidence/runtime-profile-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit(0 if errors.is_empty() else 1)
