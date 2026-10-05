extends Node3D
## Streams original Tatooine structures, POB interiors and source cell floors.
const StageLoader = preload("res://scripts/stage_loader.gd")
const DecodeWorker = preload("res://scripts/world_decode_worker.gd")

@export var render_distance := 768.0
@export var collision_distance := 192.0
@export var instances_per_frame := 24
@export var install_budget_ms := 3.0
@export var warm_mesh_limit := 64
@export var warm_cache_bytes := 128 * 1024 * 1024
const WORKER_COUNT := 2
const MAX_QUEUED_JOBS := 64
const MAX_PREPARED_RESULTS := 2
var report: Dictionary = {"error": "", "loaded_chunks": 0, "instances": 0, "collision_bodies": 0, "pending_instances": 0}
var manifest: Dictionary = {}
var directory := ""
var observer := Vector3.ZERO
var last_observer := Vector3.INF
var simulation_observers: Array = []
var retained_objects: Dictionary = {}
var retained_buildings: Dictionary = {}
var retained_cells: Dictionary = {}
var cell_owner: Node3D
var chunks: Dictionary = {}
var mesh_cache: Dictionary = {}
var pending: Array = []
var wanted: Dictionary = {}
var material_loader := StageLoader.new()
var native_builder := SwgMeshBuilder.new()
var tick := 0
var workers: Array = []
var chunk_queue: Array = []
var publish_queue: Array = []
var mesh_queue: Array = []
var mesh_jobs := {}
var mesh_demand := {}
var prepared_meshes := {}
var pending_head := 0
var serial := 0
var decode_jobs := 0
var stale_results := 0
var decode_peak_ms := 0.0
var install_peak_ms := 0.0
var publish_peak_ms := 0.0
var texture_failures: Array = []
var current_install_ms := 0.0
var maintenance_needed := true
var combat_coverage := preload("res://scripts/world_combat_coverage.gd").new()

func configure(manifest_path: String, existing_stage = null) -> bool:
	if not FileAccess.file_exists(manifest_path):
		report.error = "World snapshot manifest missing: " + manifest_path
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or not data.has("chunks") or not data.has("meshes"):
		report.error = "Invalid world snapshot manifest: " + manifest_path
		return false
	manifest = data
	directory = manifest_path.get_base_dir()
	var stage_data: Dictionary = {}
	if existing_stage is Node:
		stage_data = existing_stage.get_meta("manifest", {})
		if existing_stage.has_method("register_cell_region"):
			cell_owner = existing_stage
	elif existing_stage is Dictionary:
		stage_data = existing_stage
	if not stage_data.is_empty():
		retained_cells = stage_data.get("cells", {})
		if material_loader.vec(stage_data.get("origin", [])) != material_loader.vec(manifest.get("origin", [])):
			report.error = "World and retained stage use different coordinate origins."
			return false
		for entry in stage_data.get("instances", []):
			retained_objects[str(int(entry.get("object_id", -1)))] = true
			var building := int(entry.get("building_object_id", 0))
			if building > 0:
				retained_buildings[str(building)] = true
	if cell_owner == null:
		cell_owner = StageLoader.CellStage.new()
		cell_owner.name = "StreamedCellMembership"
		add_child(cell_owner)
	cell_owner.set_external_world_coverage(true)
	combat_coverage.configure(manifest,"world_tiles:"+str(get_instance_id())+":")
	report.merge({"source_statistics": manifest.get("statistics", {}), "retained_stage_objects": retained_objects.size(), "mode": "original static exteriors and POB interiors with shared cell membership", "path": manifest_path}, true)
	name = "OriginalTatooineWorld"
	for index in range(WORKER_COUNT):
		var worker := DecodeWorker.new()
		worker.start()
		workers.append(worker)
	set_process(true)
	return true

func planar_distance(position: Vector3, low: Vector3, high: Vector3) -> float:
	return Vector2(maxf(maxf(low.x - position.x, position.x - high.x), 0.0), maxf(maxf(low.z - position.z, position.z - high.z), 0.0)).length()

func update_observer(position: Vector3) -> void:
	if simulation_observers.size() == 1 and position.distance_to(last_observer) < 24.0:
		return
	update_observers([position])

func update_observers(positions: Array) -> void:
	if manifest.is_empty() or positions == simulation_observers:
		return
	simulation_observers = positions.duplicate()
	if not positions.is_empty():
		observer = positions[0]
		last_observer = observer
	wanted.clear()
	var nearby: Array = []
	for key in manifest.chunks:
		var source: Dictionary = manifest.chunks[key]
		var distance := INF
		for focus: Vector3 in positions:
			distance = minf(distance,planar_distance(focus, material_loader.vec(source.bounds_min), material_loader.vec(source.bounds_max)))
		if distance <= render_distance:
			wanted[key] = true
			nearby.append({"key": key, "distance": distance})
	for key in chunks.keys():
		if not wanted.has(key):
			remove_chunk(key)
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	for item in nearby:
		if not chunks.has(item.key):
			queue_chunk(item.key)
	refresh_collisions()
	refresh_combat_coverage()
	update_report()

func queue_chunk(key: String) -> void:
	serial += 1
	var node := Node3D.new()
	node.name = "Chunk_" + key.replace(":", "_")
	add_child(node)
	var source_bounds: Dictionary = manifest.chunks[key]
	var minimum := material_loader.vec(source_bounds.bounds_min)
	node.set_meta("combat_coverage", AABB(minimum,material_loader.vec(source_bounds.bounds_max)-minimum))
	chunks[key] = {"node":node,"instances":[],"mesh_ids":[],"required_meshes":[],"complete":false,"exteriors":[],"classifier":null,"cell_count":0,"region_key":str(get_instance_id())+":"+key,"definitions":{},"published":false,"publishing":false,"generation":serial,"remaining":0,"decoding":true,"interior_count":0,"colliders":[],"combat_surfaces":[]}
	chunks[key]["request"] = {"kind":"chunk","key":key,"generation":serial,"path":directory.path_join(str(source_bounds.path)),"observer":observer,"retained_cells":retained_cells,"retained_objects":retained_objects}
	chunks[key]["job_state"] = "waiting"

func accept_chunk(key: String, result: Dictionary) -> void:
	var chunk: Dictionary = chunks[key]
	chunk.definitions = result.definitions
	chunk.classifier = result.classifier
	chunk.cell_count = result.definitions.size()
	chunk.decoding = false
	# Filtering, distance sorting, cell classifier and immutable install records
	# were built privately by the worker. Scene operations remain main-thread.
	pending.append_array(result.installs)
	chunk.remaining = result.installs.size()
	for id: String in result.meshes:
		mesh_demand[id] = int(mesh_demand.get(id,0)) + 1
		chunk.required_meshes.append(id)
	if chunk.remaining == 0: publish_chunk(key)

func pump_workers() -> void:
	for worker in workers:
		var result: Dictionary = worker.take_result()
		if result.is_empty():
			continue
		decode_jobs += 1
		decode_peak_ms = maxf(decode_peak_ms,float(result.decode_ms))
		var job: Dictionary = result.job
		if job.kind == "publish":
			if not chunks.has(job.key) or chunks[job.key].generation != job.generation:
				stale_results += 1
				continue
			if not str(result.error).is_empty():
				report.error = result.error
				continue
			var chunk: Dictionary = chunks[job.key]
			var publish_start := Time.get_ticks_usec()
			cell_owner.register_cell_region(chunk.region_key,chunk.node,chunk.classifier,chunk.exteriors,chunk.definitions,result.geometry,result.support,chunk.colliders)
			publish_peak_ms = maxf(publish_peak_ms,(Time.get_ticks_usec()-publish_start)/1000.0)
			chunk.combat_surfaces.clear()
			chunk.published = true
			refresh_combat_coverage()
		elif job.kind == "chunk":
			if not chunks.has(job.key) or chunks[job.key].generation != job.generation:
				stale_results += 1
				continue
			if not str(result.error).is_empty():
				report.error = result.error
				chunks[job.key].decoding = false
				continue
			accept_chunk(job.key,result)
		else:
			mesh_jobs.erase(job.key)
			if int(mesh_demand.get(job.key,0)) <= 0:
				stale_results += 1
				continue
			if not str(result.error).is_empty():
				report.error = result.error
				# A failed mesh remains an explicit blocker, not false readiness.
				mesh_jobs[job.key] = "failed"
				continue
			prepared_meshes[job.key] = result
			for path in result.get("texture_errors",[]):
				if path not in texture_failures: texture_failures.append(path)
	# Queue only lightweight bounded descriptors, never a task per instance.
	for key: String in chunks:
		if publish_queue.size() >= MAX_QUEUED_JOBS: break
		if chunks[key].has("publication_request") and not chunks[key].publication_request.is_empty():
			publish_queue.append(chunks[key].publication_request)
			chunks[key].publication_request = {}
	for key: String in chunks:
		if chunk_queue.size() >= MAX_QUEUED_JOBS: break
		if chunks[key].job_state == "waiting":
			chunk_queue.append(chunks[key].request)
			chunks[key].job_state = "queued"
	for id: String in mesh_demand:
		if mesh_queue.size() >= MAX_QUEUED_JOBS: break
		if int(mesh_demand[id]) > 0 and not mesh_cache.has(id) and not prepared_meshes.has(id) and not mesh_jobs.has(id):
			if not manifest.meshes.has(id):
				report.error = "Missing world mesh descriptor: " + id
				mesh_jobs[id] = "failed"
				continue
			mesh_queue.append(id)
			mesh_jobs[id] = "queued"
	var busy_meshes := 0
	for state in mesh_jobs.values():
		if state == "running": busy_meshes += 1
	for worker in workers:
		if worker.is_busy(): continue
		if not publish_queue.is_empty():
			var request: Dictionary = publish_queue.pop_front()
			if chunks.has(request.key) and chunks[request.key].generation == request.generation:
				worker.submit(request)
		elif not mesh_queue.is_empty() and prepared_meshes.size()+busy_meshes < MAX_PREPARED_RESULTS:
			var id: String = mesh_queue.pop_front()
			if int(mesh_demand.get(id,0)) <= 0:
				mesh_jobs.erase(id)
				continue
			mesh_jobs[id] = "running"
			busy_meshes += 1
			worker.submit({"kind":"mesh","key":id,"path":directory.path_join(str(manifest.meshes[id].path)),"directory":directory})
		elif not chunk_queue.is_empty():
			var request: Dictionary = chunk_queue.pop_front()
			if chunks.has(request.key) and chunks[request.key].generation == request.generation:
				chunks[request.key].job_state = "running"
				worker.submit(request)

func publish_chunk(key: String) -> void:
	if not chunks.has(key) or chunks[key].published or chunks[key].publishing:
		return
	var chunk: Dictionary = chunks[key]
	chunk.complete = true
	chunk.publishing = true
	# Geometry and authored collider nodes exist before membership or terrain
	# cutouts can reference the region. Deferred physics sync completes first.
	publish_after_physics(key,chunk.node)

func publish_after_physics(key: String, expected_node: Node3D) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(expected_node) or not chunks.has(key) or chunks[key].node != expected_node: return
	var chunk: Dictionary = chunks[key]
	# Private immutable records were accumulated during budgeted installation.
	# Native BVH/floor preparation runs off-thread; scene membership and terrain
	# cutouts are published only when both the colliders and snapshot are ready.
	chunk["publication_request"] = {"kind":"publish","key":key,"generation":chunk.generation,"surfaces":chunk.combat_surfaces.duplicate(),"coverage":chunk.node.get_meta("combat_coverage"),"transform":chunk.node.global_transform,"definitions":chunk.definitions}

func get_mesh(id: String) -> Dictionary:
	if mesh_cache.has(id):
		mesh_cache[id].last_used = tick
		return mesh_cache[id]
	if not prepared_meshes.has(id):
		return {}
	var prepared: Dictionary = prepared_meshes[id]
	var geometry: Dictionary = prepared.prepared
	var mesh: ArrayMesh = native_builder.create_prepared_mesh(geometry.arrays)
	if mesh == null:
		report.error = "Prepared world mesh rejected: " + id
		return {}
	for path: String in prepared.images:
		if not material_loader.textures.has(path):
			material_loader.textures[path] = ImageTexture.create_from_image(prepared.images[path])
	for i in range(mesh.get_surface_count()):
		mesh.surface_set_material(i, material_loader.make_material(prepared.surfaces[i],directory,false))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(geometry.faces)
	var descriptor: Dictionary = manifest.meshes[id]
	var radius := maxf(material_loader.vec(descriptor.bounds_min).length(),material_loader.vec(descriptor.bounds_max).length())
	mesh_cache[id] = {"mesh":mesh,"shape":shape,"radius":radius,"refs":0,"last_used":tick,"bytes":int(prepared.bytes)}
	prepared_meshes.erase(id)
	return mesh_cache[id]

func add_instance(key: String, source: Dictionary) -> void:
	var id: String = source.get("mesh", "")
	var cached := get_mesh(id)
	if cached.is_empty() or not chunks.has(key):
		return
	var instance := MeshInstance3D.new()
	instance.mesh = cached.mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_instance_shader_parameter("swg_indoor", 1.0 if source.has("cell_id") and not source.get("is_exterior", false) else 0.0)
	instance.position = material_loader.vec(source.position)
	var q: Array = source.get("quaternion", [0,0,0,1])
	instance.quaternion = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	if source.has("scale"):
		instance.scale = material_loader.vec(source.scale, Vector3.ONE)
	instance.set_meta("object_id", source.get("object_id", 0))
	instance.set_meta("source_template", source.get("source_template", ""))
	instance.set_meta("cell_id", source.get("cell_id", ""))
	instance.set_meta("building_object_id", source.get("building_object_id", 0))
	instance.set_meta("is_exterior", source.get("is_exterior", false))
	instance.set_meta("source_layout",source.get("source_layout",""))
	instance.set_meta("source_layout_index",source.get("source_layout_index",-1))
	var body := material_loader.make_collision_body(source, manifest.get("collisions", {}), cached.shape, chunks[key].definitions)
	if body != null:
		instance.add_child(body)

	chunks[key].node.add_child(instance)
	if body != null:
		chunks[key].colliders.append(body)
		cell_owner._collect_combat_surfaces(body,chunks[key].combat_surfaces)
	var record := {"instance": instance, "body": body, "radius": cached.radius, "source_collision": source.get("collision", true), "interior": source.has("cell_id") and not source.get("is_exterior", false)}
	chunks[key].instances.append(record)
	if record.interior: chunks[key].interior_count += 1
	chunks[key].mesh_ids.append(id)
	cached.refs += 1
	set_collision(record)
	if source.get("is_exterior", false):
		chunks[key].exteriors.append(instance)
		cell_owner.refresh_exterior(instance)

func set_collision(record: Dictionary) -> void:
	var active: bool = record.source_collision and record.instance.position.distance_to(observer) <= collision_distance + float(record.radius)
	record.instance.set_meta("stream_collision_active", active)
	if is_instance_valid(record.body):
		record.body.set_meta("stream_collision_active", active)
		cell_owner.refresh_collision(record.body)
		record.body.collision_mask = 0

func refresh_combat_coverage() -> void:
	if not is_instance_valid(cell_owner): return
	combat_coverage.refresh(cell_owner.combat_collision,chunks,simulation_observers,global_transform)
	report["combat_coverage_tiles"] = combat_coverage.active.size()

func refresh_collisions() -> void:
	for chunk in chunks.values():
		for record in chunk.instances:
			set_collision(record)

func remove_chunk(key: String) -> void:
	maintenance_needed = true
	var chunk: Dictionary = chunks[key]
	if is_instance_valid(cell_owner):
		if chunk.published:
			cell_owner.unregister_cell_region(chunk.region_key)
	for id in chunk.required_meshes:
		mesh_demand[id] = maxi(0,int(mesh_demand.get(id,0))-1)
		if mesh_demand[id] == 0:
			prepared_meshes.erase(id)
	for id in chunk.mesh_ids:
		if mesh_cache.has(id):
			mesh_cache[id].refs -= 1
	remove_child(chunk.node)
	chunk.node.queue_free()
	chunks.erase(key)
	refresh_combat_coverage()
	pending = pending.slice(pending_head).filter(func(item): return item.chunk != key)
	pending_head = 0
	chunk_queue = chunk_queue.filter(func(item): return item.key != key)
	publish_queue = publish_queue.filter(func(item): return item.key != key)

func update_report() -> void:
	var count := 0
	var collisions := 0
	var interiors := 0
	var cells := 0
	for chunk in chunks.values():
		count += chunk.instances.size()
		cells += int(chunk.cell_count)
		for record in chunk.instances:
			if record.interior:
				interiors += 1
			if is_instance_valid(record.body) and record.body.collision_layer != 0:
				collisions += 1
	report.merge({"loaded_chunks": chunks.size(), "instances": count, "collision_bodies": collisions, "interior_instances": interiors, "loaded_cells": cells, "cached_meshes": mesh_cache.size(), "pending_instances": pending.size()-pending_head, "ready": pending_head >= pending.size() and chunks.values().all(func(chunk): return chunk.published)}, true)

func _process(_delta: float) -> void:
	tick += 1
	if report.get("ready",false) and not maintenance_needed and int(report.get("active_workers",0)) == 0:
		report.install_last_ms = 0.0
		return
	var start_us := Time.get_ticks_usec()
	pump_workers()
	var processed := 0
	var new_meshes := 0
	# Upload completed results even when a different mesh is at the instance
	# queue head. This prevents a bounded result pool from deadlocking after a
	# teleport changes mesh priority while two old-priority jobs finish.
	if not prepared_meshes.is_empty() and (Time.get_ticks_usec()-start_us)/1000.0 < install_budget_ms:
		get_mesh(str(prepared_meshes.keys()[0]))
		new_meshes += 1
	while pending_head < pending.size() and processed < instances_per_frame:
		if (Time.get_ticks_usec()-start_us)/1000.0 >= install_budget_ms: break
		var item: Dictionary = pending[pending_head]
		if not chunks.has(item.chunk):
			pending_head += 1
			continue
		var chunk: Dictionary = chunks[item.chunk]
		if item.has("floor"):
			var floor_bodies: Array = []
			material_loader.install_floors(chunk.node,{item.floor:chunk.definitions[item.floor]},floor_bodies)
			chunk.colliders.append_array(floor_bodies)
			for body: StaticBody3D in floor_bodies: cell_owner._collect_combat_surfaces(body,chunk.combat_surfaces)
		else:
			var id: String = item.entry.get("mesh","")
			if not mesh_cache.has(id):
				if new_meshes >= 1 or not prepared_meshes.has(id): break
				new_meshes += 1
			add_instance(item.chunk,item.entry)
		pending_head += 1
		processed += 1
		chunk.remaining -= 1
		if chunk.remaining == 0: publish_chunk(item.chunk)
	if pending_head >= pending.size():
		pending.clear()
		pending_head = 0
	elif pending_head > 1024 and pending_head > pending.size()/2:
		pending = pending.slice(pending_head)
		pending_head = 0
	# Bounded warm resources. Active meshes are never evicted under actors.
	var unused: Array = []
	var unused_bytes := 0
	for id: String in mesh_cache:
		if mesh_cache[id].refs <= 0 and int(mesh_demand.get(id,0)) <= 0:
			unused.append(id)
			unused_bytes += int(mesh_cache[id].get("bytes",0))
	unused.sort_custom(func(a,b): return mesh_cache[a].last_used < mesh_cache[b].last_used)
	var remaining := unused.size()
	var evicted := false
	for id: String in unused:
		if remaining <= warm_mesh_limit and unused_bytes <= warm_cache_bytes: break
		unused_bytes -= int(mesh_cache[id].get("bytes",0))
		mesh_cache.erase(id)
		remaining -= 1
		evicted = true
	if evicted: material_loader.textures.clear()
	current_install_ms = (Time.get_ticks_usec()-start_us)/1000.0
	install_peak_ms = maxf(install_peak_ms,current_install_ms)
	# Full scene statistics are not recomputed for every installed instance.
	if tick % 15 == 0 or (pending_head >= pending.size() and not report.get("ready",false)): update_report()
	report.ready = pending_head >= pending.size() and chunks.values().all(func(chunk): return chunk.published)
	maintenance_needed = false
	report.pending_instances = pending.size()-pending_head
	report.merge({"worker_count":workers.size(),"worker_jobs":decode_jobs,"worker_decode_peak_ms":decode_peak_ms,"install_last_ms":current_install_ms,"install_peak_ms":install_peak_ms,"install_budget_ms":install_budget_ms,"queued_mesh_jobs":mesh_queue.size(),"queued_chunk_jobs":chunk_queue.size(),"prepared_meshes":prepared_meshes.size(),"stale_results_discarded":stale_results,"warm_meshes":remaining,"warm_bytes":unused_bytes,"warm_mesh_limit":warm_mesh_limit,"warm_byte_limit":warm_cache_bytes,"texture_failures":texture_failures},true)
	report["publish_peak_ms"] = publish_peak_ms
	report["max_queued_jobs_per_kind"] = MAX_QUEUED_JOBS
	report["max_prepared_results"] = MAX_PREPARED_RESULTS
	report["publication_profile"] = cell_owner.publication_profile.duplicate()
	report["queued_publications"] = publish_queue.size()
	report["active_workers"] = workers.filter(func(worker): return worker.is_busy()).size()

func set_observer(node: Node3D) -> void:
	if is_instance_valid(cell_owner):
		cell_owner.set_observer(node)
	update_observer(node.global_position)

func _exit_tree() -> void:
	for worker in workers: worker.shutdown()
	workers.clear()
	if is_instance_valid(cell_owner):
		combat_coverage.clear(cell_owner.combat_collision)
		cell_owner.set_external_world_coverage(false)
		for chunk: Dictionary in chunks.values():
			cell_owner.unregister_cell_region(chunk.region_key)
