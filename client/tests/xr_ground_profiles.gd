extends SceneTree
class SourceGround extends Node3D:
	var ground_support := SwgGroundSupport.new()
	func collision_context(_position: Vector3) -> Dictionary:
		return {"allowed_cell_ids":["test:1"],"cell_id":"test:1"}
var errors: Array[String] = []
var rows: Array = []
var left: XRControllerTracker
var right: XRControllerTracker
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)
func tracker(id: StringName, hand: XRPositionalTracker.TrackerHand) -> XRControllerTracker:
	var result := XRControllerTracker.new()
	result.name=id;result.hand=hand;result.type=XRServer.TRACKER_CONTROLLER
	result.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(0.2,1.2,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	result.set_input("primary",Vector2.ZERO)
	XRServer.add_tracker(result)
	return result
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
func box(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size;collision.shape=shape;body.add_child(collision);body.position=position;parent.add_child(body)
func run() -> void:
	left=tracker(&"left_hand",XRPositionalTracker.TRACKER_HAND_LEFT)
	right=tracker(&"right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT)
	var original_hz := Engine.physics_ticks_per_second
	for hz in [60,90,120]:
		Engine.physics_ticks_per_second=hz
		var world := SourceGround.new()
		root.add_child(world)
		var vertices: Array = []
		var triangles: Array = []
		for span in [[2.0,0.0,0.0,0.0],[0.0,0.0,-1.0,0.25],[-1.0,0.25,-5.0,0.25]]:
			var offset := vertices.size()/3
			vertices.append_array([-2,span[1],span[0],2,span[1],span[0],2,span[3],span[2],-2,span[3],span[2]])
			var normal := Vector3(0,1,(float(span[3])-float(span[1]))/(float(span[0])-float(span[2]))).normalized()
			for ids in [[offset,offset+1,offset+2],[offset,offset+2,offset+3]]:
				triangles.append({"id":triangles.size(),"indices":ids,"normal":[normal.x,normal.y,normal.z],"fallthrough":false,"edge_flags":[1,0,1] if ids[1]==offset+1 else [1,1,0],"portal_ids":[-1,-1,-1]})
		var cell := {"floor_vertices":vertices,"floor_triangles":triangles}
		world.ground_support.configure([{"transform":Transform3D.IDENTITY,"cells":{"test:1":cell}}])
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer=4
		var floor_shape := CollisionShape3D.new()
		floor_shape.shape=SwgCollisionBuilder.new().build_floor(cell)
		floor_body.add_child(floor_shape);world.add_child(floor_body)
		box(world,Vector3(10,-0.5,0),Vector3(4,1,10))
		box(world,Vector3(10,0.125,-1.25),Vector3(4,0.25,2))
		var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate()
		world.add_child(rig)
		var body=rig.get_node("PlayerBody")
		body.collision_mask=5;body.ground_provider=world;body.active=true
		var head: XRCamera3D=body.get_camera()
		var tracked_pose := head.transform
		body.spawn_point=Vector3(0,0.7,-0.2);body.reset_spawn()
		await frames(hz)
		var start: Vector3=body.global_position
		var origin_start: Vector3=rig.global_position
		rig.get_node("LeftHand/MovementDirect").max_speed=0.4
		left.set_input("primary",Vector2(0,0.5))
		var profile: Array=[]
		for frame in range(hz*3):
			await physics_frame
			profile.append([body.global_position.y,rig.global_position.y])
		left.set_input("primary",Vector2.ZERO)
		var finish: Vector3=body.global_position
		var rise := finish.y-start.y
		var max_reverse := 0.0
		for frame in range(1,profile.size()):
			max_reverse=maxf(max_reverse,float(profile[frame-1][0])-float(profile[frame][0]))
		check(finish.z<start.z-0.45 and rise>0.1,"Slow authored-ramp climb failed at "+str(hz))
		check(max_reverse<0.003,"Body oscillated down during steady ascent at "+str(hz))
		check(absf((rig.global_position.y-origin_start.y)-rise)<0.002,"Controller body/origin vertical correction diverged at "+str(hz))
		check(head.transform.is_equal_approx(tracked_pose),"Controller motion modified tracked HMD pose")
		# True room-scale movement: only the mock tracking-local Z is updated.
		body.spawn_point=Vector3(0,0.5,0.4);body.reset_spawn()
		await frames(hz)
		var room_body_start: Vector3=body.global_position
		var room_origin_start: Vector3=rig.global_position
		for frame in range(hz*2):
			head.position.z=tracked_pose.origin.z-float(frame+1)/float(hz*2)*1.8
			await physics_frame
		var room_finish: Vector3=body.global_position
		var room_rise := room_finish.y-room_body_start.y
		check(room_rise>0.2 and room_finish.z< -1.0,"Physical room-scale ramp ascent failed at "+str(hz))
		check(absf((rig.global_position.y-room_origin_start.y)-room_rise)<0.005,"Room-scale body/origin vertical profile diverged at "+str(hz))
		check(Vector2(rig.global_position.x-room_origin_start.x,rig.global_position.z-room_origin_start.z).length()<0.005,"Room-scale correction moved virtual horizontal origin")
		check(is_equal_approx(head.position.y,tracked_pose.origin.y) and head.basis.is_equal_approx(tracked_pose.basis),"Room-scale support changed tracked head height/orientation")
		for frame in range(hz):
			head.position.x=3.0*float(frame+1)/float(hz)
			await physics_frame
		check(body.global_position.x<=1.751,"Physical room-scale crossed original uncrossable boundary at "+str(hz))
		check(is_equal_approx(head.position.x,3.0),"Boundary constraint modified raw tracking pose")
		head.position.x=0
		await frames(2)
		# Keep genuine airborne integration; support loss must not attach 2m down.
		body.apply_world_correction(Vector3.UP*2)
		var airborne_y: float=body.global_position.y
		await frames(2)
		check(body.global_position.y>airborne_y-0.05 and not body.on_ground,"Airborne body snapped to floor at "+str(hz))
		body.apply_world_correction(Vector3(0,0.5-body.global_position.y,0))
		var short_air_y: float=body.global_position.y
		await frames(2)
		check(body.global_position.y>short_air_y-0.05 and not body.on_ground,"Small airborne gap incorrectly triggered step snap at "+str(hz))
		# Slow physical riser fallback also operates below 5mm/frame.
		head.transform=tracked_pose
		body.prepare_tracked_body()
		body.ground_provider=null;body.spawn_point=Vector3(10,0.1,0.05);body.reset_spawn()
		await frames(hz)
		left.set_input("primary",Vector2(0,0.5))
		await frames(hz*3)
		left.set_input("primary",Vector2.ZERO)
		check(body.global_position.y>0.23 and body.global_position.z< -0.3,"Sub-5mm/frame physical stair blocked at "+str(hz))
		rows.append({"hz":hz,"source_ramp_start":str(start),"source_ramp_end":str(finish),"maximum_reverse_y":max_reverse,"roomscale_rise":room_rise,"roomscale_end":str(room_finish),"slow_riser_end":str(body.global_position),"profile":profile})
		world.queue_free()
		await process_frame
	Engine.physics_ticks_per_second=original_hz
	XRServer.remove_tracker(left);XRServer.remove_tracker(right)
	var report := {"test":"xr_authored_ground_profiles","passed":errors.is_empty(),"errors":errors,"rates":rows,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/xr-ground-profiles.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"rates_tested":rows.size()}))
	quit(0 if errors.is_empty() else 1)
