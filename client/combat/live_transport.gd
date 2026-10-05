extends RefCounted
## Place only a server-selected destination after its original world/cell is ready.
## Session acknowledgement and loading presentation remain with main/live_world.
var generation := 0

func cancel() -> void:
	generation += 1

func destination_valid(destination: Dictionary) -> bool:
	if str(destination.get("zone", "")) != "tatooine": return false
	var point: Variant = destination.get("position")
	if not point is Array or point.size() != 3: return false
	for value in point:
		if not (value is int or value is float) or not is_finite(float(value)): return false
	if absf(float(point[0])) > 8192 or absf(float(point[2])) > 8192: return false
	var building := str(destination.get("building_id", "0"))
	var index: Variant = destination.get("cell_index", 0)
	return building.is_valid_int() and int(building) >= 0 and (index is int or index is float) and float(index) == int(index) and int(index) >= 0 and ((int(building) == 0) == (int(index) == 0))

func source_cell(destination: Dictionary) -> String:
	return "" if str(destination.get("building_id", "0")) == "0" else "%s:%d" % [str(destination.building_id), int(destination.cell_index)]

func place(app: Node, destination: Dictionary) -> Dictionary:
	if not destination_valid(destination): return {"ok":false,"error":"Core3 returned an unsupported destination."}
	generation += 1
	var epoch := generation
	var stage: Node3D = app.stage
	var player: CharacterBody3D = app.player
	var origin: Array = stage.get_meta("manifest", {}).get("origin", [0,0,0])
	var p: Array = destination.position
	var target := stage.to_global(Vector3(float(p[0])-float(origin[0]),float(p[1])-float(origin[1]),-(float(p[2])-float(origin[2]))))
	player.set_physics_process(false)
	player.active = false
	player.feedback.remove_offset()
	if bool(app.xr_requested): player.apply_world_correction(target-player.global_position)
	else: player.global_position = target
	player.velocity = Vector3.ZERO
	if app.world_stream != null: app.world_stream.update_observer(target)
	if app.terrain != null: app.terrain.update_observer(target)
	var deadline := Time.get_ticks_msec()+90000
	while true:
		if epoch != generation or not is_instance_valid(app) or not is_instance_valid(player): return {"ok":false,"cancelled":true}
		var terrain_ready: bool = app.terrain == null or app.terrain.ready_near(target)
		var world_ready: bool = app.world_stream == null or bool(app.world_stream.report.get("ready",false))
		if terrain_ready and world_ready: break
		if app.world_stream != null and not str(app.world_stream.report.get("error", "")).is_empty(): return {"ok":false,"error":"Destination scenery could not be loaded."}
		if Time.get_ticks_msec() > deadline: return {"ok":false,"error":"Destination loading timed out."}
		await app.get_tree().process_frame
	var cell := source_cell(destination)
	if not cell.is_empty() and not stage.definitions.has(cell): return {"ok":false,"error":"Original destination cell is unavailable: "+cell}
	stage.seed_membership_at(target, cell if not cell.is_empty() else "exterior")
	await app.get_tree().physics_frame
	await app.get_tree().physics_frame
	if epoch != generation: return {"ok":false,"cancelled":true}
	# Exact server cell membership prevents exterior terrain selecting a floor
	# above the medical room. Sweep the real player capsule onto that floor.
	if bool(app.xr_requested):
		player.prepare_tracked_body()
		if not app.ground_xr_spawn(): return {"ok":false,"error":"No safe original floor at the Core3 destination."}
	else:
		var hit := KinematicCollision3D.new()
		if not player.test_move(player.global_transform,Vector3.DOWN*8.0,hit,0.002) or hit.get_collision_count()==0 or hit.get_normal().dot(Vector3.UP)<cos(player.floor_max_angle): return {"ok":false,"error":"No safe original floor at the Core3 destination."}
		player.global_position += hit.get_travel()
	stage.seed_membership_at(player.global_position,cell if not cell.is_empty() else "exterior")
	player.spawn_point = player.global_position
	player.velocity = Vector3.ZERO
	if app.environment_presentation != null: app.environment_presentation.update_observer(player.global_position)
	if app.ambient_npcs != null: app.ambient_npcs.update_observer(player.global_position)
	if app.tracked_avatar != null:
		if app.tracked_avatar.has_method("reset_life_pose_anchor"): app.tracked_avatar.reset_life_pose_anchor()
		app.tracked_avatar.planted_feet.clear()
		app.tracked_avatar.have_body_position = false
	return {"ok":true,"position":app.source_position_at(player.global_position),"cell_key":cell}
