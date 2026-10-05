extends SceneTree
const WorldStream = preload("res://scripts/world_stream.gd")
var stream: Node3D

func _initialize() -> void:
	call_deferred("run")

func wait_ready() -> void:
	for frame in range(2000):
		await process_frame
		if stream.report.get("ready", false):
			return
	assert(false, "World instance queue did not drain")

func run() -> void:
	stream = WorldStream.new()
	root.add_child(stream)
	var stage = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")))
	assert(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"), stage))
	stream.update_observer(Vector3(-60, 2, 10))
	await wait_ready()
	assert(stream.report.error == "", stream.report.error)
	assert(stream.report.instances > 100 and stream.report.collision_bodies > 0, str(stream.report))
	var initial: Dictionary = stream.report.duplicate(true)
	for chunk in stream.chunks.values():
		for record in chunk.instances:
			assert(not stream.retained_objects.has(str(int(record.instance.get_meta("object_id")))))
	await physics_frame
	var real_hit := {}
	for chunk in stream.chunks.values():
		for record in chunk.instances:
			if not is_instance_valid(record.body) or record.body.collision_layer == 0:
				continue
			var center: Vector3 = record.instance.global_transform * record.instance.mesh.get_aabb().get_center()
			var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 80, center - Vector3.UP * 80)
			real_hit = stream.get_world_3d().direct_space_state.intersect_ray(query)
			if not real_hit.is_empty():
				break
		if not real_hit.is_empty():
			break
	assert(not real_hit.is_empty(), "No collision on actual streamed source geometry")
	var first_chunks: Array = stream.chunks.keys()
	var best := ""
	var best_count := 0
	for key in stream.manifest.chunks:
		var descriptor: Dictionary = stream.manifest.chunks[key]
		var center: Vector3 = (stream.material_loader.vec(descriptor.bounds_min) + stream.material_loader.vec(descriptor.bounds_max)) * 0.5
		if center.length() > 4000 and int(descriptor.instance_count) > best_count:
			best = key
			best_count = int(descriptor.instance_count)
	var descriptor: Dictionary = stream.manifest.chunks[best]
	var distant: Vector3 = (stream.material_loader.vec(descriptor.bounds_min) + stream.material_loader.vec(descriptor.bounds_max)) * 0.5
	distant.y = 0.0
	stream.update_observer(distant)
	await wait_ready()
	assert(stream.report.error == "", stream.report.error)
	assert(stream.report.instances > 100 and stream.report.collision_bodies > 0, str(stream.report))
	var removed := 0
	for key in first_chunks:
		if not stream.chunks.has(key):
			removed += 1
	assert(removed > 0, "Old chunks were not unloaded")
	print("WORLD_STREAM_PASS ", JSON.stringify({"mos_eisley":initial,"distant":stream.report,"removed_chunks":removed,"collision_hit":str(real_hit.position),"distant_observer":str(distant)}))
	quit()
