extends SceneTree
var errors: Array[String] = []
var rows: Array = []
var trackers: Array[XRControllerTracker] = []
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value:errors.append(label);push_error(label)
func tracker(id: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var item := XRControllerTracker.new()
	item.name=id;item.hand=hand;item.type=XRServer.TRACKER_CONTROLLER
	item.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	item.set_input("primary",Vector2.ZERO);XRServer.add_tracker(item);trackers.append(item)
	return item
func frames(count: int) -> void:
	for i in count:await physics_frame
func floor_mesh(parent: Node3D, samples: Array, denied := false) -> StaticBody3D:
	var vertices := PackedVector3Array()
	for i in range(samples.size()-1):
		var a := Vector3(samples[i].x,samples[i].y,-5)
		var b := Vector3(samples[i].x,samples[i].y,5)
		var c := Vector3(samples[i+1].x,samples[i+1].y,5)
		var d := Vector3(samples[i+1].x,samples[i+1].y,-5)
		vertices.append_array([a,b,c,a,c,d])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	shape.backface_collision = true
	var collision := CollisionShape3D.new();collision.shape=shape
	var body := StaticBody3D.new();body.collision_layer=2;body.collision_mask=0
	body.set_meta("terrain_walkable",not denied)
	body.add_child(collision);parent.add_child(body)
	return body
func run() -> void:
	var left := tracker(&"left_hand",XRPositionalTracker.TRACKER_HAND_LEFT)
	tracker(&"right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT)
	var original_hz := Engine.physics_ticks_per_second
	for profile: Dictionary in [{"angle":55.0,"negotiation":0.0},{"angle":70.0,"negotiation":0.0},{"angle":82.0,"negotiation":0.0},{"angle":70.0,"negotiation":1.0}]:
		var angle: float = profile.angle
		for hz: int in [60,120]:
			Engine.physics_ticks_per_second=hz
			var world := Node3D.new();root.add_child(world)
			var height := tan(deg_to_rad(angle))*0.5
			floor_mesh(world,[Vector2(-3,0),Vector2(0,0),Vector2(0.5,height),Vector2(1,height),Vector2(1.5,0),Vector2(5,0)])
			var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate();world.add_child(rig)
			var body=rig.get_node("PlayerBody");body.collision_mask=7;body.active=true
			body.spawn_point=Vector3(-1,0.05,0);body.reset_spawn();body.prepare_tracked_body()
			rig.get_node("ScoutMovement").observe({"slope_fraction":profile.negotiation})
			await frames(hz/2)
			var head: XRCamera3D=body.get_camera();var pose:=head.transform
			left.set_input("primary",Vector2(1,0))
			var gaps: Array[float] = []
			var started := Time.get_ticks_msec()
			var ticks := 0
			for tick in hz*6:
				ticks += 1
				await physics_frame
				var support: Dictionary=body.step_solver.terrain_support(body,body.global_position,0.5,3)
				if support.get("valid",false):gaps.append(body.global_position.y-float(support.height))
				if body.global_position.x>2:break
			left.set_input("primary",Vector2.ZERO)
			var finish: Vector3=body.global_position
			await frames(15)
			var label := "%sdeg_%shz_neg%s" % [angle,hz,profile.negotiation]
			check(finish.x>2,label+" steep ascent/descent stalled")
			check(not gaps.is_empty() and gaps.min()>-0.025 and gaps.max()<0.1,label+" feet lost terrain support")
			check(head.transform.is_equal_approx(pose),label+" changed tracking")
			check(absf(body.global_position.y)<0.025,label+" slow fall persisted at rest")
			rows.append({"label":label,"angle":angle,"hz":hz,"negotiation":profile.negotiation,"ticks":ticks,"finish":str(finish),"min_gap":gaps.min() if not gaps.is_empty() else INF,"max_gap":gaps.max() if not gaps.is_empty() else INF,"elapsed_ms":Time.get_ticks_msec()-started})
			world.queue_free();await process_frame
	for hz: int in [60,120]:
		var novice: Dictionary = rows.filter(func(row):return row.angle == 70.0 and row.hz == hz and row.negotiation == 0.0)[0]
		var master: Dictionary = rows.filter(func(row):return row.angle == 70.0 and row.hz == hz and row.negotiation == 1.0)[0]
		check(master.ticks < novice.ticks,"Core3 slope_fraction did not improve steep walking speed")
	# Physical tracking uses the same support path without modifying head pose.
	var physical_world := Node3D.new();root.add_child(physical_world)
	floor_mesh(physical_world,[Vector2(-3,0),Vector2(0,0),Vector2(0.5,1.2),Vector2(3,1.2)])
	var physical_rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate();physical_world.add_child(physical_rig)
	var physical_body=physical_rig.get_node("PlayerBody");physical_body.collision_mask=7;physical_body.active=true
	physical_body.spawn_point=Vector3(-0.2,0.02,0);physical_body.reset_spawn();physical_body.prepare_tracked_body()
	await frames(30)
	var physical_head: XRCamera3D=physical_body.get_camera()
	var initial_pose:=physical_head.transform
	for i in 180:
		physical_head.position.x=initial_pose.origin.x+1.2*float(i+1)/180.0
		await physics_frame
	await frames(30)
	check(physical_body.global_position.x>0.7 and absf(physical_body.global_position.y-1.2)<0.025,"Physical roomscale steep ascent lost terrain")
	check(is_equal_approx(physical_head.position.y,initial_pose.origin.y) and physical_head.basis.is_equal_approx(initial_pose.basis),"Terrain altered physical head height/orientation")
	physical_world.queue_free();await process_frame
	# Direct helper checks: a real wall cannot become walkable terrain; gaps
	# and explicitly denied terrain are never bridged by a sampled height.
	var world := Node3D.new();root.add_child(world)
	floor_mesh(world,[Vector2(-3,0),Vector2(0,0)])
	floor_mesh(world,[Vector2(1,0),Vector2(3,0)],true)
	var body := CharacterBody3D.new();body.collision_mask=7
	var capsule := CapsuleShape3D.new();capsule.radius=0.25;capsule.height=1.7
	var shape := CollisionShape3D.new();shape.shape=capsule;shape.position.y=0.85;body.add_child(shape);world.add_child(body)
	body.position=Vector3(-0.1,0.001,0)
	var solver:=SwgXRStepSolver.new();await frames(2)
	check(not solver.move_on_terrain(body,Vector3(0.4,0,0)).handled,"Missing ground bridged")
	check(not solver.terrain_support(body,Vector3(2,0.1,0)).valid,"Denied terrain became walkable")
	var wall:=StaticBody3D.new();wall.collision_layer=1
	var wall_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(0.2,5,3);wall_shape.shape=box;wall.add_child(wall_shape);wall.position=Vector3(-1,2,0);world.add_child(wall)
	body.position=Vector3(-2,0.001,0);await frames(2)
	var blocked:Dictionary=solver.move_on_terrain(body,Vector3(1.5,0,0))
	check(blocked.handled and blocked.blocked and body.position.x < -1.3,"Solid building wall bypassed")
	var desktop=load("res://scripts/player.gd").new()
	world.add_child(desktop);desktop.collision_mask=7;desktop.testing=true;desktop.active=true
	desktop.spawn_point=Vector3(-2,0.03,4);desktop.reset_spawn()
	await frames(10)
	check(desktop.get_grounded() and desktop.feedback.physical().grounded,"Desktop terrain support did not reach gameplay grounded state")
	desktop.test_input=Vector2(1,0)
	for i in 180:
		await physics_frame
		if desktop.global_position.x>0.65:break
	desktop.test_input=Vector2.ZERO
	check(not desktop.get_grounded() and not desktop.feedback.physical().grounded,"Desktop grounded state remained true after walking into terrain hole")
	check(desktop.global_position.y < -0.02,"Desktop terrain follower prevented real falling into hole")
	world.queue_free();await process_frame
	Engine.physics_ticks_per_second=original_hz
	for item in trackers:XRServer.remove_tracker(item)
	var report:Dictionary={"test":"terrain_locomotion","passed":errors.is_empty(),"errors":errors,"rows":rows,"hardware_tested":false,"walkability_source":"resident terrain triangles; not a server passability claim"}
	FileAccess.open("res://../runtime/evidence/terrain-locomotion-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
