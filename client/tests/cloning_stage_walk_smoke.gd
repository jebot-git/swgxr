extends SceneTree
## Actual streamed Mos Eisley collision with production XR locomotion and mocked input.
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var loader = preload("res://scripts/stage_loader.gd").new()
	var stage = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	root.add_child(stage)
	var stream = preload("res://scripts/world_stream.gd").new()
	stream.render_distance = 96
	stream.collision_distance = 128
	root.add_child(stream)
	assert(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),stage))
	var chunk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/chunks/-2_-1.json"))
	var portal: Dictionary = chunk.cells["1105879:0"].portals[0]
	var a: Array = portal.vertices
	var center := Vector3.ZERO
	var bottom := INF
	for i in range(0,a.size(),3):
		center += Vector3(a[i],a[i+1],a[i+2])
		bottom = minf(bottom,float(a[i+1]))
	center /= a.size()/3
	center.y = bottom
	var normal := (Vector3(a[3],a[4],a[5])-Vector3(a[0],a[1],a[2])).cross(Vector3(a[6],a[7],a[8])-Vector3(a[0],a[1],a[2])).normalized()
	normal.y = 0
	normal = normal.normalized()
	var trackers: Array[XRControllerTracker] = []
	for id: StringName in [&"left_hand",&"right_hand"]:
		var tracker := XRControllerTracker.new()
		tracker.name = id
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if id == &"left_hand" else XRPositionalTracker.TRACKER_HAND_RIGHT
		tracker.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input("primary",Vector2.ZERO)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	var rig: XROrigin3D = load("res://xr/player_rig.tscn").instantiate()
	root.add_child(rig)
	var body = rig.get_node("PlayerBody")
	body.spawn_point = center-normal*2.5+Vector3.UP*.2
	body.reset_spawn()
	body.prepare_tracked_body()
	body.ground_provider = stage
	stage.set_observer(body)
	stream.update_observer(body.global_position)
	var timeout := Time.get_ticks_msec()+90000
	while not stream.report.get("ready",false):
		assert(Time.get_ticks_msec()<timeout,"Stream readiness timed out")
		await process_frame
	stage.seed_membership_at(body.global_position)
	body.active = true
	await frames(45)
	var start: Vector3 = body.global_position
	var head_pose: Transform3D = body.get_camera().transform
	trackers[0].set_input("primary",Vector2(normal.x,-normal.z))
	for i in 120:
		await physics_frame
		if (body.global_position-center).dot(normal)>1.8: break
	trackers[0].set_input("primary",Vector2.ZERO)
	await frames(12)
	var inside: Vector3 = body.global_position
	var entered: bool = stage.current_cell.get("cell_id","") == "1105879:1"
	trackers[0].set_input("primary",Vector2(-normal.x,normal.z))
	for i in 120:
		await physics_frame
		if (body.global_position-center).dot(normal)<-2.3: break
	trackers[0].set_input("primary",Vector2.ZERO)
	await frames(12)
	var outside: Vector3 = body.global_position
	var exited: bool = stage.current_cell.is_empty()
	var tracking_preserved: bool = body.get_camera().transform.is_equal_approx(head_pose)
	var passed: bool = entered and exited and (inside-center).dot(normal)>1.5 and (outside-center).dot(normal)<-2.0 and tracking_preserved and body.on_ground
	var report := {"passed":passed,"start":str(start),"inside":str(inside),"outside":str(outside),"entered_foyer":entered,"exited":exited,"tracking_preserved":tracking_preserved,"grounded":body.on_ground,"renderer":"dummy","hardware_tested":false,"actual_streamed_scene":true}
	FileAccess.open("res://../runtime/evidence/cloning-stage-walk-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	rig.queue_free()
	stream.queue_free()
	stage.queue_free()
	await process_frame
	for tracker in trackers: XRServer.remove_tracker(tracker)
	quit(0 if passed else 1)
