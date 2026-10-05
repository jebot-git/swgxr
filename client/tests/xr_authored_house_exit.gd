extends SceneTree
var errors: Array[String] = []
var left: XRControllerTracker
var right: XRControllerTracker
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)
func tracker(id: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var item := XRControllerTracker.new()
	item.name=id;item.hand=hand;item.type=XRServer.TRACKER_CONTROLLER
	item.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	item.set_input("primary",Vector2.ZERO);XRServer.add_tracker(item)
	return item
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func run() -> void:
	var asset_root := "res://../runtime/assets_review" if OS.get_cmdline_user_args().has("--review-assets") else "res://../runtime/assets"
	var loader=load("res://scripts/stage_loader.gd").new()
	var stage=loader.load_stage(ProjectSettings.globalize_path(asset_root.path_join("mos_eisley/scene.json")))
	check(stage!=null,"Review stage missing")
	if stage==null: quit(1);return
	root.add_child(stage)
	var world=load("res://scripts/world_stream.gd").new()
	root.add_child(world)
	check(world.configure(ProjectSettings.globalize_path(asset_root.path_join("tatooine_world/world.json")),stage),"Review world configure failed")
	var terrain=load("res://scripts/terrain_stream.gd").new()
	root.add_child(terrain)
	check(terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(3618.98388671875,5,-4801.0859375)),"Source terrain configure failed")
	var door := Vector3(-244.99495,1.13636,38.86325)
	var outward := Vector3(-0.789,0,-0.614).normalized()
	var spawn := door-outward
	world.update_observer(spawn);terrain.update_observer(spawn)
	var deadline := Time.get_ticks_msec()+60000
	while not world.report.get("ready",false) or not terrain.ready_near(spawn):
		if Time.get_ticks_msec()>deadline:
			check(false,"House source environment timed out")
			quit(1);return
		await process_frame
	left=tracker(&"left_hand",XRPositionalTracker.TRACKER_HAND_LEFT)
	right=tracker(&"right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT)
	var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate()
	root.add_child(rig)
	var body=rig.get_node("PlayerBody")
	body.ground_provider=stage;body.active=true
	body.spawn_point=spawn;body.spawn_yaw=atan2(-outward.x,-outward.z)
	body.reset_spawn();body.prepare_tracked_body()
	stage.set_observer(body);stage.seed_membership_at(body.global_position,"1281533:1")
	rig.get_node("LeftHand/MovementDirect").max_speed=1.2
	await frames(60)
	check(str(stage.current_cell.get("cell_id",""))=="1281533:1","House interior spawn did not attach to foyer1")
	var head: XRCamera3D=body.get_camera()
	var original_pose := head.transform
	var hz := Engine.physics_ticks_per_second
	var profiles: Array=[]
	for mode in ["controller","roomscale"]:
		left.set_input("primary",Vector2.ZERO)
		head.transform=original_pose
		body.prepare_tracked_body();body.reset_spawn()
		stage.seed_membership_at(body.global_position,"1281533:1")
		await frames(30)
		var profile: Array=[]
		if mode=="controller":left.set_input("primary",Vector2(0,1))
		for frame in range(hz*4):
			if mode=="roomscale":head.position.z=original_pose.origin.z-4.2*float(frame+1)/float(hz*4)
			await physics_frame
			profile.append({"position":str(body.global_position),"y":body.global_position.y,"cell":str(stage.current_cell.get("cell_id","")),"mask":body.collision_mask,"origin_y":rig.global_position.y})
		left.set_input("primary",Vector2.ZERO)
		await frames(10)
		var travel: float = (body.global_position-door).dot(outward)
		check(travel>2.6,mode+" could not traverse the actual house doorway and exterior stairs")
		check(stage.current_cell.is_empty() and body.collision_mask==7,mode+" lost exterior membership/terrain collision above buried bedroom")
		var minimum := INF
		var buried := false
		for row: Dictionary in profile:
			minimum=minf(minimum,row.y)
			buried=buried or row.cell=="1281533:7"
		check(minimum> -0.2 and not buried,mode+" fell or attached to the buried bedroom")
		if mode=="controller":check(head.transform.is_equal_approx(original_pose),"Controller house traversal changed tracked head pose")
		else:check(head.basis.is_equal_approx(original_pose.basis) and is_equal_approx(head.position.y,original_pose.origin.y),"Room-scale house traversal changed tracked orientation/height")
		profiles.append({"mode":mode,"outside_distance":travel,"end":str(body.global_position),"minimum_y":minimum,"profile":profile})
	var report := {"test":"xr_original_house_exit_traversal","passed":errors.is_empty(),"errors":errors,"source_building":"1281533","hardware_tested":false,"asset_root":asset_root,"profiles":profiles}
	FileAccess.open("res://../runtime/evidence/xr-authored-house-exit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"profiles":profiles.map(func(row):return {"mode":row.mode,"end":row.end,"outside_distance":row.outside_distance,"minimum_y":row.minimum_y})}))
	rig.queue_free();world.queue_free();terrain.queue_free();stage.queue_free()
	await process_frame
	XRServer.remove_tracker(left);XRServer.remove_tracker(right)
	quit(0 if errors.is_empty() else 1)
