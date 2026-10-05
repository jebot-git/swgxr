extends SceneTree
## Actor-owned cell states and immutable BVH geometry, tested against original assets.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func vec(values: Array, index: int) -> Vector3:
	return Vector3(values[index],values[index+1],values[index+2])
func run() -> void:
	var loader = load("res://scripts/stage_loader.gd").new()
	var stage = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	if stage == null: push_error(loader.report.error);quit(1);return
	root.add_child(stage)
	var cells: Dictionary = stage.get_meta("manifest").cells
	var queries: Array = []
	var checks: Array = []
	for portal: Dictionary in cells["1106368:0"].portals:
		var id: String = portal.leads_to
		var points: Array = portal.vertices
		var door := Vector3.ZERO
		var bottom := INF
		for i in range(0,points.size(),3):
			var point := vec(points,i)
			door += point
			bottom = minf(bottom,point.y)
		door /= points.size()/3
		door.y = bottom + 1.25
		var outward := (vec(points,3)-vec(points,0)).cross(vec(points,6)-vec(points,0)).normalized()
		var center := Vector3.ZERO
		var floor_points: Array = cells[id].floor_vertices
		for i in range(0,floor_points.size(),3): center += vec(floor_points,i)
		center /= floor_points.size()/3
		if outward.dot(center-door)>0:outward=-outward
		queries.append({"from":door-outward*1.5,"to":door+outward*1.5,"cell_id":id})
		checks.append({"kind":"portal_exit","cell":id,"end":""})
		queries.append({"from":door+outward*1.5,"to":door-outward*1.5,"cell_id":""})
		checks.append({"kind":"portal_enter","cell":id,"end":id})
	# Independent actors in different source rooms: each sees its own authored
	# floor even when the single-player observer has deactivated that room.
	for id: String in ["1106368:1","1106368:4","1106368:8","1106368:16"]:
		var cell: Dictionary = cells[id]
		var points: Array = cell.floor_vertices
		var indices: Array = cell.floor_indices
		var floor_point := (vec(points,int(indices[0])*3)+vec(points,int(indices[1])*3)+vec(points,int(indices[2])*3))/3.0
		queries.append({"from":floor_point+Vector3.UP*0.35,"to":floor_point-Vector3.UP*0.35,"cell_id":id})
		checks.append({"kind":"floor","cell":id,"height":floor_point.y})
	queries.append({"from":Vector3(-60,1.8,10),"to":Vector3(-75,1.8,10),"cell_id":"1106368:4"})
	checks.append({"kind":"wall","cell":"1106368:4"})
	var results: Array = stage.combat_collision.trace_segments(queries)
	for i in results.size():
		var hit: Dictionary = results[i]
		var expected: Dictionary = checks[i]
		check(hit.complete,"Missing source query coverage: "+str(expected))
		if expected.kind.begins_with("portal"):
			check(not hit.hit and hit.end_cell_id==expected.end and hit.portal_crossings>0,"Portal shot failed: "+str(expected)+str(hit))
		else:
			check(hit.hit,"Solid floor/wall did not occlude: "+str(expected))
			if expected.kind=="floor":check(absf(hit.position.y-float(expected.height))<0.01,"Incorrect room floor selected")
	var observer := CharacterBody3D.new()
	root.add_child(observer)
	stage.set_observer(observer)
	for fixture: Dictionary in [{"position":Vector3(-85,0.7,1.6),"cell":""},{"position":Vector3(-60,0.7,10),"cell":"1106368:4"},{"position":Vector3(-60.42,1.2,18.3),"cell":"1106368:8"}]:
		observer.position=fixture.position
		stage.seed_membership_at(observer.position,fixture.cell)
		var repeated: Array = stage.combat_collision.trace_segments(queries)
		for i in results.size():
			check(results[i]==repeated[i],"Observer changed independent query "+str(i))
	var absent: Dictionary = stage.combat_collision.trace_segment(Vector3(10000,5,10000),Vector3(10020,5,10000),"")
	check(not absent.complete,"Unloaded world was treated as a clear valid shot")
	var unknown: Dictionary = stage.combat_collision.trace_segment(Vector3.ZERO,Vector3.ONE,"unloaded:1")
	check(not unknown.complete,"Unknown actor cell was treated as exterior")
	stage.combat_collision.set_require_terrain(true)
	var missing_terrain: Dictionary = stage.combat_collision.trace_segment(queries[1].from,queries[1].to,"")
	check(not missing_terrain.complete,"Unloaded terrain was treated as loaded exterior")
	var still_indoor: Dictionary = stage.combat_collision.trace_segment(queries[6].from,queries[6].to,queries[6].cell_id)
	check(still_indoor.complete and still_indoor.hit,"Interior floor incorrectly depends on exterior terrain residency")
	var timing_profiles: Array = []
	if "--benchmark" in OS.get_cmdline_user_args():
		stage.combat_collision.set_require_terrain(false)
		for count: int in [60,120,240,375,480]:
			var batch: Array = []
			for i in count:batch.append(queries[i % queries.size()])
			for i in 5:stage.combat_collision.trace_segments(batch)
			var durations: Array[float] = []
			var complete_count := 0
			var hits := 0
			for i in 120:
				var start := Time.get_ticks_usec()
				var traced: Array = stage.combat_collision.trace_segments(batch)
				durations.append(float(Time.get_ticks_usec()-start)/1000.0)
				if i == 0:
					for hit: Dictionary in traced:
						if hit.complete:complete_count += 1
						if hit.hit:hits += 1
			durations.sort()
			timing_profiles.append({"sweeps_per_tick":count,"equivalent_450rpm_half_second_flight_shooters":float(count)/3.75,"samples":durations.size(),"p50_ms":durations[60],"p95_ms":durations[114],"p99_ms":durations[118],"max_ms":durations.back(),"complete":complete_count,"hits":hits,"budget_ms":4.0,"within_geometry_budget":durations[118] <= 4.0})
	var report := {"timing_profiles":timing_profiles,"timing_scope":"Native actual-stage geometry batch only; not networking, actors, full server tick or rendering", "test":"observer_independent_actual_stage_combat_collision","passed":failures.is_empty(),"failures":failures,"cases":checks,"queries":results,"statistics":stage.combat_collision.statistics(),"observer_configurations":3,"hardware_tested":false}
	var output := "res://../runtime/evidence/combat-collision-smoke.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	observer.queue_free();stage.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
