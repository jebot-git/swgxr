extends SceneTree
const Loader = preload("res://scripts/stage_loader.gd")
const WorldStream = preload("res://scripts/world_stream.gd")

func _initialize() -> void:
	call_deferred("run")

func wait_ready(stream: Node3D) -> void:
	for i in range(3000):
		await process_frame
		if stream.report.get("ready", false):
			assert(stream.chunks.values().all(func(chunk): return chunk.complete and chunk.published), "Ready before geometry/collision region publication")
			for chunk: Dictionary in stream.chunks.values():
				assert(stream.cell_owner.cell_regions.has(chunk.region_key), "Published chunk absent from floor registry")
			return
	assert(false, "Source world load did not finish")

func walk_entrance(stage: Node3D, source: Dictionary) -> Dictionary:
	var exterior: Dictionary = source.cells["1082874:0"]
	var portal: Dictionary = exterior.portals[0]
	var vertices: Array = portal.vertices
	var points: Array[Vector3] = []
	var center := Vector3.ZERO
	var floor_y := INF
	for i in range(0, vertices.size(), 3):
		var point := Vector3(vertices[i], vertices[i + 1], vertices[i + 2])
		points.append(point)
		center += point
		floor_y = minf(floor_y, point.y)
	center /= points.size()
	center.y = floor_y + 0.05
	var direction := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	direction.y = 0
	direction = direction.normalized()
	if stage.classify_world(center + direction * 0.7).is_empty():
		direction = -direction
	var ground = load("res://scripts/terrain_stream.gd").new()
	root.add_child(ground)
	var origin: Array = stage.get_meta("manifest").origin
	assert(ground.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"), Vector3(origin[0], origin[1], origin[2])))
	ground.update_observer(center)
	var deadline := Time.get_ticks_msec() + 45000
	while not ground.ready_near(center, 0):
		assert(Time.get_ticks_msec() < deadline, "Entrance terrain load timed out")
		await process_frame
	for i in range(3):
		await physics_frame
	var walker = load("res://scripts/player.gd").new()
	root.add_child(walker)
	walker.ground_provider = stage
	walker.spawn_point = center - direction * 1.1 + Vector3.UP * 0.2
	walker.spawn_yaw = atan2(-direction.x, -direction.z)
	walker.testing = true
	walker.active = true
	walker.reset_spawn()
	stage.set_observer(walker)
	stage.seed_membership_at(walker.global_position, "1082874:0")
	for i in range(60):
		await physics_frame
	var start: Vector3 = walker.global_position
	walker.test_input = Vector2(0, -1)
	for i in range(38):
		await physics_frame
	walker.test_input = Vector2.ZERO
	var finish: Vector3 = walker.global_position
	var inside: bool = int(stage.current_cell.get("building_object_id", 0)) == 1082874
	var crossed: bool = (finish - center).dot(direction) > 0.4 and inside
	var report := {"crossed":crossed, "start":str(start), "finish":str(finish), "portal_center":str(center), "cell":stage.current_cell.duplicate()}
	walker.queue_free()
	ground.queue_free()
	await process_frame
	return report

func run() -> void:
	var loader := Loader.new()
	var stage := loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	assert(stage != null, str(loader.report))
	root.add_child(stage)
	var stream := WorldStream.new()
	stream.render_distance = 320
	root.add_child(stream)
	assert(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"), stage))
	stream.update_observer(Vector3(-181, 1, 20))
	await wait_ready(stream)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(stream.directory.path_join(str(stream.manifest.chunks["-1:0"].path))))
	var cell: Dictionary = source.cells["1082874:3"]
	var triangles: Array = []
	var vertices: Array = cell.floor_vertices
	for i in range(0, cell.floor_indices.size(), 3):
		var points: Array[Vector3] = []
		for j in range(3):
			var index := int(cell.floor_indices[i + j]) * 3
			points.append(Vector3(vertices[index], vertices[index + 1], vertices[index + 2]))
		triangles.append({"point":(points[0] + points[1] + points[2]) / 3, "area":(points[1] - points[0]).cross(points[2] - points[0]).length()})
	triangles.sort_custom(func(a, b): return a.area > b.area)
	var player := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = 0.22
	collider.shape = capsule
	collider.position.y = 0.85
	player.add_child(collider)
	root.add_child(player)
	player.global_position = triangles[0].point + Vector3.UP * 0.5
	stage.set_observer(player)
	stage.seed_membership_at(player.global_position,"1082874:3")
	assert(stage.current_cell.get("building_object_id", 0) == 1082874, str(stage.current_cell))
	assert(player.collision_mask == 5, "Terrain collision was not excluded inside streamed cantina")
	# A terrain layer deliberately above the true floor must be ignored indoors.
	var terrain := StaticBody3D.new()
	terrain.collision_layer = 2
	var terrain_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.1, 8)
	terrain_shape.shape = box
	terrain.add_child(terrain_shape)
	terrain.position = triangles[0].point + Vector3.UP * 0.25
	root.add_child(terrain)
	for i in range(90):
		await physics_frame
		player.velocity = Vector3(0, -2, 0)
		player.move_and_slide()
	var floor: Vector3 = triangles[0].point
	var actual := player.global_position
	assert(player.is_on_floor() and absf(actual.y - floor.y) < 0.12, "Original cantina floor support failed: " + str(actual) + " source " + str(floor))
	var exteriors := 0
	var furnishings := 0
	for chunk: Dictionary in stream.chunks.values():
		for record: Dictionary in chunk.instances:
			if int(record.instance.get_meta("building_object_id", 0)) != 1082874:
				continue
			if record.instance.get_meta("is_exterior", false):
				exteriors += 1
				assert(record.instance.visible, "Exterior render geometry was globally hidden")
				if is_instance_valid(record.body):
					var id := str(record.body.get_meta("source_cell",""))
					var relevant: bool = stage.physical_cells.has(id)
					assert(record.body.collision_layer == (1 if relevant else 0), "Exterior collider ignores source cell scope")
			elif not record.instance.get_meta("source_template", "").contains("building"):
				furnishings += 1
	assert(exteriors > 0 and furnishings > 0, "Streamed shell or authored furnishings missing")
	var wall_hit := false
	for i in range(16):
		var direction := Vector3(sin(i * TAU / 16), 0, cos(i * TAU / 16))
		var hit := KinematicCollision3D.new()
		if player.test_move(player.global_transform, direction * 30, hit) and absf(hit.get_normal().y) < 0.4:
			wall_hit = true
			break
	assert(wall_hit, "No actual cantina wall/furnishing blocked the capsule")
	var entrance := await walk_entrance(stage, source)
	assert(entrance.crossed, "Actual entrance walk blocked: " + str(entrance))
	stage.set_observer(player)
	# Retained starport and streamed cantina must share one terrain-mask owner.
	player.global_position = Vector3(-60, 0.65, 10)
	stage.update_cell()
	assert(stage.current_cell.get("building_object_id", 0) == 1106368 and player.collision_mask == 5)
	for chunk: Dictionary in stream.chunks.values():
		for record: Dictionary in chunk.instances:
			if int(record.instance.get_meta("building_object_id", 0)) == 1082874 and record.instance.get_meta("is_exterior", false):
				assert(record.instance.visible, "Previous streamed exterior was globally hidden")
				if is_instance_valid(record.body):
					assert(record.body.collision_layer == 1, "Unoccupied building exterior collision not restored")
	player.global_position = Vector3(-400, 80, 400)
	stage.update_cell()
	assert(stage.current_cell.is_empty() and player.collision_mask == 7)
	var regions_before: int = stage.cell_regions.size()
	stream.update_observer(Vector3(-6000, 0, -6000))
	await wait_ready(stream)
	assert(stage.classify_world(actual).is_empty(), "Unloaded building left stale classification behind")
	# Reload the same source region, then prove physical support is restored.
	stream.update_observer(actual)
	await wait_ready(stream)
	player.global_position = floor + Vector3.UP * 0.5
	stage.seed_membership_at(player.global_position,"1082874:3")
	for i in range(90):
		await physics_frame
		player.velocity = Vector3(0,-2,0)
		player.move_and_slide()
	assert(player.is_on_floor() and absf(player.global_position.y-floor.y)<0.12, "Reloaded authored floor failed to reground capsule")
	assert(player.collision_mask==5 and stage.current_cell.get("cell_id","")=="1082874:3")
	var output := {"test":"actual_streamed_cantina_interior", "passed":true, "source_cell":"1082874:3", "source_pob":cell.source_pob, "capsule_floor":str(actual), "source_floor":str(floor), "capsule_wall_collision":wall_hit, "walked_original_entrance":entrance, "streamed_furnishings":furnishings, "exterior_render_instances_preserved":exteriors,"source_cell_collision_scope":true,"readiness_after_region_publication":true,"reload_regrounded":true, "terrain_excluded_indoors":true, "retained_streamed_membership_shared":true, "regions_before_unload":regions_before, "stale_regions_removed":true}
	print(JSON.stringify(output))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/world-interior-smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n")
	stream.queue_free()
	await process_frame
	stage.queue_free()
	player.queue_free()
	terrain.queue_free()
	await process_frame
	quit()
