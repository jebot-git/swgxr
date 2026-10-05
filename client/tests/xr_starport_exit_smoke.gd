extends SceneTree
## Actual source exterior apertures, both locomotion paths, no XR hardware.
var errors: Array[String] = []
var trackers: Array[XRControllerTracker] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: errors.append(message);push_error(message)
func tracker(id: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var item := XRControllerTracker.new()
	item.name=id;item.hand=hand;item.type=XRServer.TRACKER_CONTROLLER
	item.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	item.set_input("primary",Vector2.ZERO);XRServer.add_tracker(item);trackers.append(item)
	return item
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func point(values: Array, index: int) -> Vector3: return Vector3(values[index],values[index+1],values[index+2])
func run() -> void:
	var asset_root := "res://../runtime/assets_review" if OS.get_cmdline_user_args().has("--review-assets") else "res://../runtime/assets"
	var loader=load("res://scripts/stage_loader.gd").new()
	var stage=loader.load_stage(ProjectSettings.globalize_path(asset_root.path_join("mos_eisley/scene.json")))
	check(stage!=null,"Source stage missing")
	if stage==null: quit(1);return
	root.add_child(stage)
	var cells: Dictionary = stage.get_meta("manifest").cells
	var left=tracker(&"left_hand",XRPositionalTracker.TRACKER_HAND_LEFT)
	tracker(&"right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT)
	var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate()
	root.add_child(rig)
	var body=rig.get_node("PlayerBody")
	body.ground_provider=stage;body.active=true
	stage.set_observer(body)
	rig.get_node("LeftHand/MovementDirect").max_speed=1.2
	var head: XRCamera3D=body.get_camera()
	var original_pose := head.transform
	var hz := Engine.physics_ticks_per_second
	var profiles: Array=[]
	for portal: Dictionary in cells["1106368:0"].portals:
		var cell_id: String = portal.leads_to
		var vertices: Array = portal.vertices
		var door := Vector3.ZERO
		var bottom := INF
		for i in range(0,vertices.size(),3):
			var p := point(vertices,i);door+=p;bottom=minf(bottom,p.y)
		door/=vertices.size()/3;door.y=bottom
		var outward := (point(vertices,3)-point(vertices,0)).cross(point(vertices,6)-point(vertices,0)).normalized()
		outward.y=0;outward=outward.normalized()
		var center := Vector3.ZERO
		var floor_vertices: Array = cells[cell_id].floor_vertices
		for i in range(0,floor_vertices.size(),3):center+=point(floor_vertices,i)
		center/=floor_vertices.size()/3
		if outward.dot(center-door)>0:outward=-outward
		for direction in ["exit","enter"]:
			var forward := outward if direction=="exit" else -outward
			var spawn := door-forward*1.5+Vector3.UP*0.05
			var found: Dictionary = stage.ground_support.sample_support(spawn,[cell_id] if direction=="exit" else ["1106368:0"],1,1)
			if found.get("valid",false):spawn.y=found.height+0.03
			for mode in ["controller","roomscale"]:
				rig.queue_free()
				await process_frame
				rig=load("res://xr/player_rig.tscn").instantiate()
				root.add_child(rig)
				body=rig.get_node("PlayerBody")
				body.ground_provider=stage;body.active=true
				stage.set_observer(body)
				rig.get_node("LeftHand/MovementDirect").max_speed=1.2
				head=body.get_camera();original_pose=head.transform
				left.set_input("primary",Vector2.ZERO);head.transform=original_pose
				body.spawn_point=spawn;body.spawn_yaw=atan2(-forward.x,-forward.z)
				body.prepare_tracked_body();body.reset_spawn()
				stage.seed_membership_at(body.global_position,cell_id if direction=="exit" else "")
				await frames(30)
				var minimum: float = body.global_position.y
				if mode=="controller":left.set_input("primary",Vector2(0,1))
				for frame in range(hz*3):
					if mode=="roomscale":head.position.z=original_pose.origin.z-3.6*float(frame+1)/float(hz*3)
					await physics_frame
					minimum=minf(minimum,body.global_position.y)
				left.set_input("primary",Vector2.ZERO)
				await frames(8)
				var travel: float = (body.global_position-door).dot(forward)
				var label: String = cell_id+" "+direction+" "+mode
				check(travel>1.1,label+" blocked before clearing source portal")
				check(stage.current_cell.is_empty() if direction=="exit" else str(stage.current_cell.get("cell_id",""))==cell_id,label+" wrong persistent membership")
				check(minimum> -0.2,label+" fell through source floor")
				check(head.transform.is_equal_approx(original_pose) if mode=="controller" else head.basis.is_equal_approx(original_pose.basis) and is_equal_approx(head.position.y,original_pose.origin.y),label+" changed tracked head orientation/height")
				var contact := KinematicCollision3D.new()
				var blocker := ""
				if body.test_move(body.global_transform,forward*0.1,contact):blocker=str(contact.get_collider().get_meta("collision_source",contact.get_collider().get_path()))
				profiles.append({"cell":cell_id,"direction":direction,"mode":mode,"travel":travel,"end":str(body.global_position),"minimum_y":minimum,"blocker":blocker})
				print(JSON.stringify(profiles.back()))
	var report := {"test":"xr_all_starport_exterior_portals","passed":errors.is_empty(),"errors":errors,"hardware_tested":false,"asset_root":asset_root,"profiles":profiles}
	FileAccess.open("res://../runtime/evidence/xr-starport-exits.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"cases":profiles.size()}))
	rig.queue_free();stage.queue_free();await process_frame
	for item in trackers:XRServer.remove_tracker(item)
	quit(0 if errors.is_empty() else 1)
