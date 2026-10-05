extends SceneTree
const Loader = preload("res://scripts/stage_loader.gd")
const World = preload("res://scripts/world_stream.gd")
const Terrain = preload("res://scripts/terrain_stream.gd")
const Player = preload("res://scripts/player.gd")
const Placement = preload("res://combat/live_transport.gd")
class PlacementHost extends Node3D:
	var stage: Node3D
	var player: CharacterBody3D
	var world_stream: Node3D
	var terrain: Node3D
	var xr_requested := false
	var environment_presentation: Node3D
	var ambient_npcs: Node3D
	var tracked_avatar: Node3D
	func source_position_at(p: Vector3) -> Vector3:
		var o: Array = stage.get_meta("manifest").origin
		return Vector3(p.x+o[0],p.y+o[1],o[2]-p.z)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host := PlacementHost.new()
	root.add_child(host)
	var loader := Loader.new()
	host.stage = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	host.add_child(host.stage)
	host.player = Player.new()
	host.player.testing = true
	host.player.active = false
	host.add_child(host.player)
	host.player.ground_provider = host.stage
	host.player.set_physics_process(false)
	host.stage.set_observer(host.player)
	host.world_stream = World.new()
	host.world_stream.render_distance = 128.0
	host.add_child(host.world_stream)
	assert(host.world_stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),host.stage))
	host.terrain = Terrain.new()
	host.add_child(host.terrain)
	var origin: Array = loader.report.origin
	assert(host.terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(origin[0],origin[1],origin[2])))
	host.terrain.set_cell_source(host.stage)
	await process_frame
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/services/catalog.json")))
	var placement := Placement.new()
	var report := {"points":[],"passed":true,"gpu_tested":false,"validation":"Original source travel centers, streamed authored geometry/collisions, real native player capsule; no live Core3 transaction or XR validation"}
	for point: Dictionary in catalog.travel_points:
		var start := Time.get_ticks_msec()
		var target := {"position":point.position,"zone":"tatooine","building_id":"0","cell_index":0}
		var result: Dictionary = await placement.place(host,target)
		var row := {"name":point.name,"source":point.position,"incoming":point.incoming,"placement":result,"load_ms":Time.get_ticks_msec()-start}
		if not bool(result.get("ok",false)): report.passed=false
		else:
			var source: Vector3 = result.position
			row["height_adjustment"] = source.y-float(point.position[1])
			var query := PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*.15,host.player.global_position-Vector3.UP*.4,7)
			query.exclude=[host.player.get_rid()]
			var hit: Dictionary = host.get_world_3d().direct_space_state.intersect_ray(query)
			row["floor_hit"] = not hit.is_empty()
			row["normal_y"] = hit.get("normal",Vector3.ZERO).y
			if hit.is_empty() or float(row.normal_y)<0.7: report.passed=false
		report.points.append(row)
		print("TRAVEL_FLOOR "+JSON.stringify(row))
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/service-travel-floors.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("TRAVEL_FLOORS_PASSED "+str(report.passed))
	host.queue_free()
	await process_frame
	quit(0 if report.passed else 1)
