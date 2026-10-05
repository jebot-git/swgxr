extends SceneTree
const WorldStream = preload("res://scripts/world_stream.gd")
var errors: Array[String] = []
var stream: Node3D
var report := {"test":"threaded_world_cancellation_and_native_adoption","gpu_tested":false}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func run() -> void:
	var path := ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var descriptor: Dictionary = manifest.meshes[manifest.meshes.keys()[0]]
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_base_dir().path_join(descriptor.path)))
	var builder := SwgMeshBuilder.new()
	var prepared := builder.prepare_mesh(source.surfaces)
	var reference := builder.create_mesh(source.surfaces)
	var converted := builder.create_prepared_mesh(prepared.arrays)
	check(reference.get_faces() == converted.get_faces(),"Worker packing changes authored geometry")
	for index in range(reference.get_surface_count()):
		check(reference.surface_get_arrays(index)[Mesh.ARRAY_COLOR] == converted.surface_get_arrays(index)[Mesh.ARRAY_COLOR],"Worker packing changes baked vertex colors")
	check(builder.prepare_mesh([]).is_empty(),"Empty geometry was accepted")
	var retained: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")))
	var ground := SwgGroundSupport.new()
	var private_ground := SwgGroundSupport.new()
	private_ground.configure([{"cells":retained.cells,"transform":Transform3D.IDENTITY}])
	var point := Vector3(-60,0.7,10)
	var expected := private_ground.sample_support(point,[],0.5,2)
	check(expected.get("valid",false),"Actual stage ground fixture is invalid")
	check(ground.adopt_region("fixture",private_ground),"Native ground adoption rejected")
	check(ground.sample_support(point,[],0.5,2) == expected,"Native floor adoption changes support")
	ground.remove_region("fixture")
	check(not ground.sample_support(point,[],0.5,2).get("valid",false),"Removed floor region still supplies ground")
	stream = WorldStream.new()
	stream.render_distance = 128.0
	stream.warm_mesh_limit = 2
	root.add_child(stream)
	check(stream.configure(path,retained),"World setup failed")
	stream.update_observer(Vector3(-60,2,10))
	stream.pump_workers() # Start private jobs, then invalidate their exact keys.
	stream.update_observer(Vector3(-2200,2,-8050))
	stream.update_observer(Vector3(-60,2,10))
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline and not stream.report.get("ready",false):
		await process_frame
		check(stream.mesh_queue.size() <= stream.MAX_QUEUED_JOBS,"Mesh descriptor queue exceeded cap")
		check(stream.chunk_queue.size() <= stream.MAX_QUEUED_JOBS,"Chunk descriptor queue exceeded cap")
		check(stream.publish_queue.size() <= stream.MAX_QUEUED_JOBS,"Publication queue exceeded cap")
		check(stream.prepared_meshes.size() <= stream.MAX_PREPARED_RESULTS,"Prepared result pool exceeded cap")
		if not str(stream.report.error).is_empty(): break
	check(stream.report.get("ready",false),"Cancelled/requeued world did not settle")
	check(stream.stale_results > 0,"Obsolete same-key decode results were not rejected")
	check(stream.report.error == "",str(stream.report.error))
	check(stream.workers.size()==2,"Unexpected worker count")
	var checked_floor := false
	for chunk: Dictionary in stream.chunks.values():
		check(chunk.published and stream.wanted.has(chunk.request.key),"Stale or incomplete chunk published")
		for id: String in chunk.definitions:
			var cell: Dictionary = chunk.definitions[id]
			var indices: Array = cell.get("floor_indices",[])
			var vertices: Array = cell.get("floor_vertices",[])
			if cell.get("is_exterior",false) or indices.size()<3: continue
			var center := Vector3.ZERO
			for corner in range(3):
				var start := int(indices[corner])*3
				center += Vector3(vertices[start],vertices[start+1],vertices[start+2])/3.0
			var result: Dictionary = stream.cell_owner.combat_collision.trace_segment(center+Vector3.UP*.15,center-Vector3.UP*.15,id,4)
			if result.get("hit",false):
				check(result.get("complete",false),"Adopted actual floor snapshot is incomplete")
				checked_floor = true
				break
		if checked_floor: break
	check(checked_floor,"No actual streamed authored floor hit after native adoption")
	report["stream"] = stream.report.duplicate(true)
	stream.update_observers([])
	await process_frame
	check(stream.chunks.is_empty(),"Unwanted chunks remain loaded")
	check(stream.cell_owner.cell_regions.is_empty(),"Unloaded cell memberships remain active")
	check(stream.report.get("warm_meshes",0)<=2,"Warm cache limit was not enforced")
	# Shutdown with an active private decode must join safely and publish nothing.
	stream.update_observer(Vector3(-60,2,10))
	stream.pump_workers()
	stream.queue_free()
	await process_frame
	report["passed"] = errors.is_empty()
	report["errors"] = errors
	FileAccess.open("res://../runtime/evidence/world-threading-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("WORLD_THREADING_SMOKE "+JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
