extends SceneTree

const TerrainStream = preload("res://scripts/terrain_stream.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")
var stream: Node3D
var report: Dictionary = {"test":"original_tatooine_streaming_and_physics", "success":false, "regions":[], "errors":[]}
var started := 0
var stage_origin := Vector3.ZERO

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if not condition:
		report.errors.append(message)
		push_error(message)
	return condition

func wait_near(swg: Vector2, timeout_ms := 45000) -> bool:
	var position: Vector3 = stream.terrain_position(swg)
	stream.update_observer(position)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not stream.ready_near(position,1):
		if Time.get_ticks_msec() >= deadline:
			return check(false,"Terrain loading timed out at "+str(swg))
		await process_frame
	for i in range(3):
		await physics_frame
	return true

func wait_full() -> bool:
	var deadline := Time.get_ticks_msec()+45000
	while stream.chunks.size()!=stream.desired.size():
		if Time.get_ticks_msec()>=deadline:return check(false,"Full draw region loading timed out")
		await process_frame
	for i in range(3):await physics_frame
	var lod_counts := {"64":0,"32":0,"8":0}
	var collision_chunks := 0
	for item in stream.chunks.values():
		lod_counts[str(item.resolution)]+=1
		var node: MeshInstance3D = item.node
		if not check(node.mesh!=null and node.mesh.get_surface_count()>0,"Terrain renderer received empty mesh"):continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_CUSTOM0] is PackedFloat32Array,"Terrain shader family attributes have wrong buffer type")
		check(arrays[Mesh.ARRAY_CUSTOM1] is PackedFloat32Array,"Terrain tint attributes have wrong buffer type")
		var has_collision := false
		for child in node.get_children():
			if child is StaticBody3D:has_collision=true
		check(has_collision==(item.resolution==64),"Terrain LOD collision residency is incorrect")
		if has_collision:collision_chunks+=1
	check(stream.chunks.size()==289,"Complete interior planet draw region must contain289chunks")
	check(lod_counts=={"64":25,"32":56,"8":208},"Unexpected streamed terrain LOD rings")
	report.full_region={"resident":stream.chunks.size(),"lod_counts":lod_counts,"collision_chunks":collision_chunks}
	return report.errors.is_empty()

func ray(swg: Vector2, mask := 2) -> Dictionary:
	var expected: float = stream.evaluator.sample_height(swg.x,swg.y)-stage_origin.y
	var x: float = swg.x-stage_origin.x
	var z: float = stage_origin.z-swg.y
	var query := PhysicsRayQueryParameters3D.create(Vector3(x,expected+100,z),Vector3(x,expected-100,z),mask)
	return stream.get_world_3d().direct_space_state.intersect_ray(query)

func check_region(swg: Vector2) -> bool:
	var begin := Time.get_ticks_msec()
	if not await wait_near(swg):return false
	var base := Vector2(floorf(swg.x/128)*128,floorf(swg.y/128)*128)
	# The source evaluator is continuous; collision is the original 2m sample grid.
	# At grid vertices and shared chunk edges heights should agree directly.
	var points := [base+Vector2(64,64),base+Vector2(0,64),base+Vector2(128,64),base+Vector2(64,0),base+Vector2(64,128),base+Vector2(128,128)]
	var errors: Array = []
	for point in points:
		var hit := ray(point)
		if not check(not hit.is_empty(),"Missing terrain collision ray at "+str(point)):continue
		var expected: float = stream.evaluator.sample_height(point.x,point.y)-stage_origin.y
		var error: float = absf(hit.position.y-expected)
		errors.append(error)
		check(error<0.035,"Collision/source height mismatch at %s: %.6f" % [point,error])
		check(hit.normal.y>0,"Terrain collision has inverted surface normal")
		check(hit.collider.collision_layer==2,"Terrain collision is not on independent layer 2")
	check(stream.chunks.size()<=289,"Resident chunk count exceeded fixed 17x17 draw region")
	stream.mutex.lock()
	var queued: int = stream.jobs.size()
	var completed: int = stream.completed.size()
	stream.mutex.unlock()
	check(queued<=289 and completed<=1,"Terrain queue exceeded bounded producer/backpressure contract")
	report.regions.append({"swg":str(swg),"load_ms":Time.get_ticks_msec()-begin,"collision_height_errors":errors,"resident":stream.chunks.size(),"queued":queued,"completed":completed})
	return report.errors.is_empty()

func finish(code: int) -> void:
	report.elapsed_ms=Time.get_ticks_msec()-started
	report.success=code==0
	report.stream_report=stream.report.duplicate()
	var directory := ProjectSettings.globalize_path("res://../runtime/terrain")
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("streaming-physics.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	print("TERRAIN_STREAM_SMOKE_PASS" if code==0 else "TERRAIN_STREAM_SMOKE_FAIL")
	# Exercise worker shutdown while there are still queued far chunks.
	stream.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	started=Time.get_ticks_msec()
	var path := ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	stage_origin=Vector3(scene.origin[0],scene.origin[1],scene.origin[2])
	stream=TerrainStream.new()
	root.add_child(stream)
	if not check(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),stage_origin),"Terrain configure failed"):
		await finish(1);return
	# Wake notifications must not serve as build permits: a stalled main thread
	# plus rapid teleports still allows only one completed CPU mesh at a time.
	stream.set_process(false)
	for update in range(40):
		stream.update_observer(stream.terrain_position(Vector2(3000+update*128,-4000)))
	OS.delay_msec(900)
	stream.mutex.lock()
	var stalled_completed: int = stream.completed.size()
	stream.mutex.unlock()
	check(stalled_completed<=1,"Rapid teleports bypassed worker backpressure")
	report.adversarial_completed=stalled_completed
	stream.set_process(true)
	var outside: Vector3 = stream.terrain_position(Vector2(8300,-8300))
	check(not stream.ready_near(outside,0),"Outside-planet coordinates incorrectly report collision ready")
	var constrained: Vector2 = stream.source_position(stream.constrain_position(outside))
	check(absf(constrained.x)<=8191.001 and absf(constrained.y)<=8191.001,"Planet movement clamp failed")
	report.planet_bounds=true
	if not await check_region(Vector2(3618,-4800)):
		await finish(1);return
	if not await wait_full():
		await finish(1);return
	var initial_nodes: Array = []
	for item in stream.chunks.values():initial_nodes.append(weakref(item.node))
	var initial_center: Vector2i = stream.center
	# Cross the planet, including high fractal terrain and the negative world edge.
	for point in [Vector2(-7552,7552),Vector2(7424,-7424),Vector2(128,128)]:
		if not await check_region(point):
			await finish(1);return
		check(not stream.chunks.has(initial_center),"Starport chunk was retained after distant teleport")
	for reference in initial_nodes:check(reference.get_ref()==null,"Retired terrain node leaked after teleport")
	# Original cave exclusion removes the physics surface as well as geometry.
	if not await wait_near(Vector2(6556,-1305)):
		await finish(1);return
	check(stream.evaluator.sample(6556,-1305).excluded,"Original cave AEXC rule absent")
	check(ray(Vector2(6556,-1305)).is_empty(),"Source cave exclusion still has terrain collision")
	check(not ray(Vector2(6574,-1304)).is_empty(),"Terrain outside source cave hole is missing")
	report.cave_physics_hole=true
	if not await check_region(Vector2(3618,-4800)):
		await finish(1);return
	# Validate the actual starport FLR mask and original cell membership, not an AABB proxy.
	var loader := StageLoader.new()
	var stage = loader.load_stage(path)
	if not check(stage!=null,"Original starport stage failed to load"):
		await finish(1);return
	root.add_child(stage)
	var observer := CharacterBody3D.new()
	root.add_child(observer)
	observer.position=Vector3(-60,1.2,10)
	stage.set_observer(observer)
	stage.update_cell()
	check(not stage.current_cell.is_empty(),"Original starport foyer not classified as interior")
	check(observer.collision_mask==5,"Interior observer must exclude terrain collision layer 2")
	var context: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/terrain/context.json")))
	var mask: Dictionary = context.interior_masks[0]
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://../runtime/assets/terrain/"+str(mask.path)))
	var world: Vector2 = stream.source_position(observer.position)
	var u: float = (world.x-mask.world_rect[0])/mask.world_rect[2]
	var v: float = (world.y-mask.world_rect[1])/mask.world_rect[3]
	var pixel := image.get_pixel(clampi(floori(u*image.get_width()),0,image.get_width()-1),clampi(floori(v*image.get_height()),0,image.get_height()-1))
	check(pixel.r>.5,"Source FLR interior point missing from terrain render mask")
	check(bool(stream.material.get_shader_parameter("mask_enabled")),"Terrain shader interior mask is disabled")
	observer.position=Vector3(-85,.6,1.6)
	stage.update_cell()
	check(stage.current_cell.is_empty(),"Exterior observer still classified inside starport")
	check(observer.collision_mask==7,"Exterior observer must collide with terrain and object layers")
	report.original_floor_mask_and_membership=true
	stage.queue_free();observer.queue_free()
	await finish(0 if report.errors.is_empty() else 1)
