extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value:failures.append(label);push_error(label)
func run() -> void:
	var loader = load("res://scripts/stage_loader.gd").new()
	var stage = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	if stage==null:quit(1);return
	root.add_child(stage)
	var terrain = load("res://scripts/terrain_stream.gd").new()
	root.add_child(terrain)
	if not terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),loader.vec(loader.report.origin)):
		quit(1);return
	terrain.set_cell_source(stage)
	var a: Vector3 = terrain.terrain_position(Vector2(3900,-4700),0)
	var b: Vector3 = terrain.terrain_position(Vector2(4600,-4700),0)
	terrain.update_observers([a,b])
	var deadline := Time.get_ticks_msec()+45000
	while (not terrain.ready_near(a,0) or not terrain.ready_near(b,0)) and Time.get_ticks_msec()<deadline:
		await process_frame
	check(terrain.ready_near(a,0) and terrain.ready_near(b,0),"Both independent actor terrain chunks must reside simultaneously")
	var hits: Array = []
	for p: Vector3 in [a,b]:
		var hit: Dictionary = stage.combat_collision.trace_segment(p+Vector3.UP*2,p-Vector3.UP*2,"",2)
		hits.append(hit)
		check(hit.complete and hit.hit and hit.source_layer==2,"Terrain query missing independent actor region")
	var before: Dictionary = stage.combat_collision.statistics()
	terrain.update_observers([b])
	var old: Dictionary = stage.combat_collision.trace_segment(a+Vector3.UP*2,a-Vector3.UP*2,"",2)
	# a may remain in b's far render region temporarily, but cannot be claimed as
	# authoritative terrain once the LOD64 geometry is replaced with render LOD.
	deadline=Time.get_ticks_msec()+45000
	while old.complete and Time.get_ticks_msec()<deadline:
		await process_frame
		old=stage.combat_collision.trace_segment(a+Vector3.UP*2,a-Vector3.UP*2,"",2)
	check(not old.complete,"Downgraded or unloaded terrain retained stale authoritative collision")
	var report := {"test":"multiple_actor_collision_residency","passed":failures.is_empty(),"failures":failures,"actor_distance_m":a.distance_to(b),"source_queries":hits,"before":before,"after":stage.combat_collision.statistics(),"unloaded_query":old,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/combat-residency-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	terrain.queue_free();await process_frame
	stage.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
