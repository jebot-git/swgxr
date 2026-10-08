extends Node3D
## Immutable C++ source-rule sampling on one worker; scene/physics installation on main.
const CHUNK_SIZE := 128.0
const NEAR_RADIUS := 2
const DRAW_RADIUS := 8
const EXTENT := 8192.0
var evaluator := SwgTerrainEvaluator.new()
var builder := SwgMeshBuilder.new()
var origin := Vector3.ZERO
var material: ShaderMaterial
var cell_source: Node3D
var interior_regions: Array = []
var interior_view_groups: Array = []
var mask_builder := SwgInteriorMask.new()
var masks_dirty := false
var mask_updates := 0
var mask_pending: Array[Vector2i] = []
var mask_max_usec := 0
var chunks: Dictionary = {}
var desired: Dictionary = {}
var completed: Array = []
var jobs: Array = []
var mutex := Mutex.new()
var semaphore := Semaphore.new()
var worker := Thread.new()
var stopping := false
const SKIRT_DEPTH := 64.0
var center := Vector2i(99999, 99999)
var observer_centers: Array[Vector2i] = []
var configured := false
var source_manifest:Dictionary={}
var modification_catalog:Dictionary={}
var modification_groups:Dictionary={}
var modification_revision:=0
var dirty_chunks:Dictionary={}
var movement_solver:RefCounted
var report: Dictionary = {"installed": 0, "discarded": 0, "peak_resident": 0}

func configure(path: String, world_origin: Vector3) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Planet terrain missing: " + path)
		return false
	var source = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary or not evaluator.configure(source):
		push_error("Invalid planet terrain manifest")
		return false
	source_manifest=source
	var modifications_path:="res://../runtime/assets/terrain_modifications/catalog.json"
	if FileAccess.file_exists(modifications_path):modification_catalog=JSON.parse_string(FileAccess.get_file_as_string(modifications_path))
	origin = world_origin
	material = _make_material(source, path.get_base_dir())
	_make_water(source, path.get_base_dir())
	configured = true
	worker.start(_worker_loop)
	return true

func bind_movement_solver(solver:RefCounted)->void:
	movement_solver=solver

func set_modification_group(group:String,rows:Array)->void:
	if not configured:return
	var next:Array=preload("res://scripts/terrain_modifications.gd").resolve(rows,modification_catalog)
	var previous:Array=modification_groups.get(group,[])
	if next==previous:return
	var next_groups:=modification_groups.duplicate(false)
	next_groups[group]=next
	var manifest:=source_manifest.duplicate(false)
	var all:Array=[]
	var groups:=next_groups.keys();groups.sort()
	for key:String in groups:all.append_array(next_groups[key])
	manifest.modifications=all
	var replacement:=SwgTerrainEvaluator.new()
	if not replacement.configure(manifest):return
	modification_groups=next_groups
	for entry:Dictionary in previous+next:
		var bounds:Rect2=entry.bounds
		for z in range(floori(bounds.position.y/CHUNK_SIZE),floori(bounds.end.y/CHUNK_SIZE)+1):
			for x in range(floori(bounds.position.x/CHUNK_SIZE),floori(bounds.end.x/CHUNK_SIZE)+1):
				dirty_chunks[Vector2i(x,z)]=true
	mutex.lock()
	evaluator=replacement
	modification_revision+=1
	mutex.unlock()
	if movement_solver!=null:movement_solver.update_terrain_evaluator(evaluator)
	_queue_missing_chunks()

func _queue_missing_chunks()->void:
	var pending:Array=[]
	for key:Vector2i in desired:
		if not chunks.has(key) or chunks[key].resolution!=desired[key] or dirty_chunks.has(key):
			pending.append({"key":key,"resolution":desired[key],"revision":modification_revision,"priority":key.distance_squared_to(center)})
	pending.sort_custom(func(a,b):return a.priority<b.priority)
	mutex.lock();jobs=pending;mutex.unlock();semaphore.post()

func source_position(local: Vector3) -> Vector2:
	return Vector2(local.x + origin.x, origin.z - local.z)

func constrain_position(local: Vector3) -> Vector3:
	var swg := source_position(local)
	return Vector3(clampf(swg.x, -EXTENT+1.0, EXTENT-1.0)-origin.x, local.y, origin.z-clampf(swg.y, -EXTENT+1.0, EXTENT-1.0))

func terrain_position(swg: Vector2, clearance := 2.0) -> Vector3:
	return Vector3(swg.x - origin.x, evaluator.sample_height(swg.x, swg.y) - origin.y + clearance, origin.z - swg.y)

func update_observer(local: Vector3) -> void:
	update_observers([local])

func update_observers(positions: Array) -> void:
	# A simulation worker may retain the union of all authoritative actors. The
	# headset is only one consumer; residency must not follow a spectator camera.
	if not configured:
		return
	var next_centers: Array[Vector2i] = []
	for local: Vector3 in positions:
		var swg := source_position(local)
		var next := Vector2i(floori(swg.x / CHUNK_SIZE), floori(swg.y / CHUNK_SIZE))
		if next not in next_centers:
			next_centers.append(next)
	next_centers.sort()
	if next_centers == observer_centers:
		return
	observer_centers = next_centers
	if not observer_centers.is_empty():
		center = observer_centers[0]
	desired.clear()
	var priorities := {}
	for focus: Vector2i in observer_centers:
		for z in range(focus.y - DRAW_RADIUS, focus.y + DRAW_RADIUS + 1):
			for x in range(focus.x - DRAW_RADIUS, focus.x + DRAW_RADIUS + 1):
				if x < -64 or x >= 64 or z < -64 or z >= 64:
					continue
				var key := Vector2i(x, z)
				var distance := maxi(absi(x-focus.x), absi(z-focus.y))
				var resolution := 64 if distance <= NEAR_RADIUS else (32 if distance <= 4 else 8)
				desired[key] = maxi(desired.get(key, 0), resolution)
				priorities[key] = mini(priorities.get(key, 2147483647), key.distance_squared_to(focus))
	var pending: Array = []
	for key: Vector2i in desired:
		if not chunks.has(key) or chunks[key].resolution != desired[key] or dirty_chunks.has(key):
			pending.append({"key": key, "resolution": desired[key], "priority": priorities[key], "revision":modification_revision})
	pending.sort_custom(func(a, b): return a.priority < b.priority)
	mutex.lock()
	jobs = pending
	mutex.unlock()
	semaphore.post()
	for key in chunks.keys():
		if not desired.has(key):
			if is_instance_valid(cell_source):
				cell_source.combat_collision.remove_geometry("terrain:" + str(key))
			chunks[key].node.queue_free()
			chunks.erase(key)

func ready_near(local: Vector3, radius := 1) -> bool:
	var swg := source_position(local)
	if absf(swg.x) >= EXTENT or absf(swg.y) >= EXTENT:
		return false
	var key := Vector2i(floori(swg.x / CHUNK_SIZE), floori(swg.y / CHUNK_SIZE))
	for z in range(key.y-radius, key.y+radius+1):
		for x in range(key.x-radius, key.x+radius+1):
			if x < -64 or x >= 64 or z < -64 or z >= 64:
				continue
			var neighbor := Vector2i(x,z)
			if not chunks.has(neighbor) or chunks[neighbor].resolution != 64 or dirty_chunks.has(neighbor):
				return false
	return configured

func _worker_loop() -> void:
	while true:
		mutex.lock()
		var stop := stopping
		var job: Dictionary = jobs.pop_front() if not jobs.is_empty() and completed.is_empty() else {}
		var sampler:=evaluator
		mutex.unlock()
		if stop:
			break
		if job.is_empty():
			semaphore.wait()
			continue
		var key: Vector2i = job.key
		var data := sampler.build_chunk(key.x * CHUNK_SIZE, key.y * CHUNK_SIZE, CHUNK_SIZE, job.resolution)
		# Backpressure keeps completed mesh data bounded while the main thread installs it.
		mutex.lock()
		completed.append({"job": job, "data": data})
		mutex.unlock()

func _process(_delta: float) -> void:
	if masks_dirty:
		_refresh_interior_masks()
	_update_pending_masks()
	mutex.lock()
	var result: Dictionary = completed.pop_front() if not completed.is_empty() else {}
	mutex.unlock()
	if result.is_empty():
		return
	var job: Dictionary = result.job
	var key: Vector2i = job.key
	if desired.get(key, 0) != job.resolution or int(job.get("revision",0))!=modification_revision:
		report.discarded += 1
		semaphore.post()
		return
	var node := MeshInstance3D.new()
	node.name = "Terrain_%d_%d_LOD%d" % [key.x, key.y, job.resolution]
	node.mesh = builder.create_terrain_mesh(result.data, SKIRT_DEPTH)
	node.material_override = material.duplicate(false) if is_instance_valid(cell_source) else material
	if is_instance_valid(cell_source):
		_apply_interior_mask(node, key)
	node.position = Vector3(key.x * CHUNK_SIZE - origin.x, -origin.y, origin.z - key.y * CHUNK_SIZE)
	if job.resolution == 64:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.set_meta("source_layer", 2)
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = builder.create_terrain_collision(result.data)
		body.add_child(shape)
		node.add_child(body)
	add_child(node)
	if chunks.has(key):
		chunks[key].node.queue_free()
	chunks[key] = {"node": node, "resolution": job.resolution}
	dirty_chunks.erase(key)
	_register_combat_chunk(key)
	report.installed += 1
	report.peak_resident = maxi(report.peak_resident, chunks.size())
	semaphore.post()

func _exit_tree() -> void:
	if is_instance_valid(cell_source):
		for key: Vector2i in chunks:
			cell_source.combat_collision.remove_geometry("terrain:" + str(key))
	if worker.is_started():
		mutex.lock()
		stopping = true
		mutex.unlock()
		semaphore.post()
		worker.wait_to_finish()

func _make_material(source: Dictionary, directory: String) -> ShaderMaterial:
	var albedos: Array[Image] = []
	var normals: Array[Image] = []
	var info := PackedVector2Array()
	info.resize(64)
	for family in source.shader_families:
		var textures: Array = family.shaders[0].get("textures", []) if not family.shaders.is_empty() else []
		var diffuse := _channel(textures, "MAIN", directory, Color.WHITE)
		var normal := _channel(textures, "NRML", directory, Color(0.5,0.5,1.0))
		info[int(family.id)] = Vector2(albedos.size(), float(family.shader_size))
		albedos.append(diffuse)
		normals.append(normal)
	var color_array := Texture2DArray.new()
	color_array.create_from_images(albedos)
	var normal_array := Texture2DArray.new()
	normal_array.create_from_images(normals)
	var result := ShaderMaterial.new()
	result.shader = load("res://shaders/terrain.gdshader")
	result.set_shader_parameter("terrain_albedo", color_array)
	result.set_shader_parameter("terrain_normal", normal_array)
	result.set_shader_parameter("family_info", info)
	var context_path := directory.path_join("context.json")
	if FileAccess.file_exists(context_path):
		var context: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(context_path))
		for mask in context.get("interior_masks", []):
			var image := Image.load_from_file(directory.path_join(mask.path))
			if image != null:
				var rect: Array = mask.world_rect
				result.set_shader_parameter("interior_mask", ImageTexture.create_from_image(image))
				result.set_shader_parameter("interior_rect", Vector4(rect[0],rect[1],rect[2],rect[3]))
				result.set_shader_parameter("mask_enabled", true)
				break
	return result

func _channel(textures: Array, tag: String, directory: String, fallback: Color) -> Image:
	var result: Image
	for item in textures:
		if item.tag == tag and FileAccess.file_exists(directory.path_join(item.path)):
			result = Image.load_from_file(directory.path_join(item.path))
			break
	if result == null:
		result = Image.create(512,512,false,Image.FORMAT_RGBA8)
		result.fill(fallback)
	result.convert(Image.FORMAT_RGBA8)
	result.resize(512,512,Image.INTERPOLATE_LANCZOS)
	result.generate_mipmaps()
	return result

func _make_water(source: Dictionary, directory: String) -> void:
	var regions:Array=source.get("water_regions",[]).duplicate(true)
	if source.get("global_water_enabled",false):
		regions.append({"points":[[-EXTENT,-EXTENT],[EXTENT,-EXTENT],[EXTENT,EXTENT],[-EXTENT,EXTENT]],"water_height":source.get("global_water_height",0.0),"water_shader_size":source.get("global_water_shader_size",2.0),"water_shader":source.get("global_water_shader","")})
	for region in regions:
		if not bool(region.get("enabled",true)) or not bool(region.get("water_enabled",true)):continue
		var points:Array=region.get("points",[])
		if region.get("type","")=="BREC" and region.get("rect") is Array and region.rect.size()==4:
			var rect:Array=region.rect
			points=[[rect[0],rect[1]],[rect[2],rect[1]],[rect[2],rect[3]],[rect[0],rect[3]]]
		if points.size()<3:continue
		var polygon := PackedVector2Array()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for point in points:
			polygon.append(Vector2(point[0], point[1]))
			vertices.append(Vector3(point[0]-origin.x, float(region.water_height)-origin.y, origin.z-point[1]))
			normals.append(Vector3.UP)
			uvs.append(Vector2(point[0],point[1]) / maxf(float(region.water_shader_size),0.1))
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var water := StandardMaterial3D.new()
		water.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		water.cull_mode = BaseMaterial3D.CULL_DISABLED
		water.roughness = 0.2
		water.albedo_color = Color(0.55,0.72,0.78,0.78)
		water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var shader_data: Dictionary = source.get("water_shaders",{}).get(region.water_shader,{})
		if shader_data.has("textures"):
			water.albedo_texture = ImageTexture.create_from_image(_channel(shader_data.textures,"MAIN",directory,Color.WHITE))
		var instance := MeshInstance3D.new()
		instance.name = "OriginalWaterBoundary"
		instance.mesh = mesh
		instance.material_override = water
		add_child(instance)

func set_cell_source(source: Node3D) -> void:
	if is_instance_valid(cell_source) and cell_source != source:
		for key: Vector2i in chunks:
			cell_source.combat_collision.remove_geometry("terrain:" + str(key))
	if is_instance_valid(cell_source) and cell_source.interior_cells_changed.is_connected(_mark_interior_masks_dirty):
		cell_source.interior_cells_changed.disconnect(_mark_interior_masks_dirty)
	cell_source = source
	if is_instance_valid(cell_source):
		cell_source.interior_cells_changed.connect(_mark_interior_masks_dirty)
		cell_source.combat_collision.set_require_terrain(true)
		for key: Vector2i in chunks:
			_register_combat_chunk(key)
	_mark_interior_masks_dirty()

func _mark_interior_masks_dirty() -> void:
	masks_dirty = true
	# Restore outside terrain immediately, before the incremental mask queue.
	# Otherwise an exited basement can leave a visible ground hole for frames.
	if is_instance_valid(cell_source) and cell_source.interior_view_regions().is_empty():
		for chunk: Dictionary in chunks.values():
			var target: ShaderMaterial = chunk.node.material_override
			target.set_shader_parameter("volume_mask_enabled", false)
			target.set_shader_parameter("volume_mask_enabled2", false)
			target.set_shader_parameter("mask_enabled", false)

func _refresh_interior_masks() -> void:
	masks_dirty = false
	interior_view_groups = cell_source.interior_view_regions() if is_instance_valid(cell_source) else []
	interior_regions = interior_view_groups[0].regions if not interior_view_groups.is_empty() else []
	mask_pending.assign(chunks.keys())
	mask_pending.sort_custom(func(a, b): return a.distance_squared_to(center) < b.distance_squared_to(center))

func _update_pending_masks() -> void:
	var started := Time.get_ticks_usec()
	var count := 0
	while not mask_pending.is_empty() and count < 2 and Time.get_ticks_usec() - started < 4000:
		if count > 0 and Time.get_ticks_usec() - started + mask_max_usec > 4000:
			break
		var key: Vector2i = mask_pending.pop_front()
		if not chunks.has(key):
			continue
		var node: MeshInstance3D = chunks[key].node
		if node.material_override == material:
			node.material_override = material.duplicate(false)
		_apply_interior_mask(node, key)
		count += 1
	report["interior_masks_pending"] = mask_pending.size()

func _apply_interior_mask(node: MeshInstance3D, key: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	var target: ShaderMaterial = node.material_override
	target.set_shader_parameter("mask_enabled", false)
	target.set_shader_parameter("interior_volume_rect", Vector4(key.x * CHUNK_SIZE, key.y * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE))
	var metadata := {"cells":0,"triangles":0,"covered_texels":0,"buildings":[]}
	for slot in range(2):
		var suffix := "" if slot == 0 else "2"
		var group: Dictionary = interior_view_groups[slot] if slot < interior_view_groups.size() else {}
		var result: Dictionary = mask_builder.rasterize(group.get("regions",[]), Vector2(key.x * CHUNK_SIZE, key.y * CHUNK_SIZE), origin, CHUNK_SIZE, 512)
		target.set_shader_parameter("volume_mask_enabled"+suffix, result.has("image"))
		target.set_shader_parameter("volume_mask_building"+suffix, group.get("building_id",0))
		target.set_shader_parameter("interior_volume_mask"+suffix, ImageTexture.create_from_image(result.image) if result.has("image") else null)
		metadata.cells += int(result.get("cells",0))
		metadata.triangles += int(result.get("triangles",0))
		metadata.covered_texels += int(result.get("covered_texels",0))
		if group.has("building_id"):
			metadata.buildings.append(group.building_id)
	node.set_meta("interior_mask", metadata)
	mask_updates += 1
	mask_max_usec = maxi(mask_max_usec, Time.get_ticks_usec() - started)
	report["interior_mask_updates"] = mask_updates
	report["interior_mask_max_usec"] = mask_max_usec

func _register_combat_chunk(key: Vector2i) -> void:
	if not is_instance_valid(cell_source):
		return
	var entry: Dictionary = chunks[key]
	var geometry_key := "terrain:" + str(key)
	if entry.resolution != 64:
		cell_source.combat_collision.remove_geometry(geometry_key)
		return
	# Bounds are explicit even where AEXC removes every triangle. Coverage means
	# this source chunk was loaded, not that every point must have solid ground.
	var low: Vector3 = entry.node.global_position + Vector3(0, -100000, -CHUNK_SIZE)
	cell_source.register_combat_geometry(geometry_key, entry.node, AABB(low,Vector3(CHUNK_SIZE,200000,CHUNK_SIZE)),2)
