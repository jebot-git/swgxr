extends SceneTree
## Real Jolt capsules + native solver + production XR locomotion. No headset claim.
var checks:=0
var errors:Array=[]
var rows:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func surface(parent:Node3D,points:Array,layer:int)->void:
	var vertices:=PackedVector3Array()
	for i in range(points.size()-1):
		var a:=Vector3(points[i].x,points[i].y,-2);var b:=Vector3(points[i].x,points[i].y,2)
		var c:=Vector3(points[i+1].x,points[i+1].y,2);var d:=Vector3(points[i+1].x,points[i+1].y,-2)
		vertices.append_array([a,b,c,a,c,d])
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(vertices);shape.backface_collision=true
	var collision:=CollisionShape3D.new();collision.shape=shape
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=layer;floor_body.collision_mask=0;floor_body.add_child(collision);parent.add_child(floor_body)
	if layer==2:floor_body.set_meta("terrain_walkable",true)
func box(parent:Node3D,center:Vector3,size:Vector3)->void:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;parent.add_child(body);body.position=center
	var collision:=CollisionShape3D.new();collision.shape=BoxShape3D.new();collision.shape.size=size;body.add_child(collision)
func frames(count:int)->void:
	for _i in count:await physics_frame
func run()->void:
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var left:=XRControllerTracker.new();left.name="left_hand";left.type=XRServer.TRACKER_CONTROLLER;left.hand=XRPositionalTracker.TRACKER_HAND_LEFT;left.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(-.3,1.3,-.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);left.set_input("primary",Vector2.ZERO);XRServer.add_tracker(left)
	var world:=Node3D.new();root.add_child(world);surface(world,[Vector2(-3,0),Vector2(4,0)],2);surface(world,[Vector2(0,0),Vector2(1,.45),Vector2(3,.45)],1)
	var body:=CharacterBody3D.new();body.collision_mask=7;world.add_child(body)
	var capsule:=CapsuleShape3D.new();capsule.radius=.25;capsule.height=1.7
	var collision:=CollisionShape3D.new();collision.shape=capsule;collision.position.y=.85;body.add_child(collision);body.position=Vector3(-.3,.001,0)
	await frames(2)
	var solver:=SwgXRStepSolver.new();var start:=body.global_transform
	var result:=solver.move_on_terrain(body,Vector3(.3,0,0))
	check(not result.handled and body.global_transform.is_equal_approx(start),"Ramp toe returns unconsumed full movement with original capsule position restored")
	check(body.collision_mask==7,"Authored handoff restores complete terrain/building collision mask")
	check(solver.step_up(body,Vector3(.3,0,0),.35) and body.position.y>start.origin.y and body.position.x>-.05,"Bounded native step accepts walkable ramp after terrain yields ownership")
	world.free();await process_frame
	for mode in ["controller","roomscale"]:
		for scenario in ["ramp","wall","tall_ledge","low_ceiling"]:
			world=Node3D.new();root.add_child(world);surface(world,[Vector2(-3,0),Vector2(4,0)],2)
			if scenario in ["ramp","low_ceiling"]:surface(world,[Vector2(0,0),Vector2(1,.45),Vector2(3,.45)],1)
			if scenario=="wall":box(world,Vector3(.1,1.5,0),Vector3(.2,3,4))
			if scenario=="tall_ledge":box(world,Vector3(1,.5,0),Vector3(2,1,4))
			if scenario=="low_ceiling":box(world,Vector3(1,2.0,0),Vector3(4,.2,4))
			var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();world.add_child(rig)
			var player=rig.get_node("PlayerBody");player.collision_mask=7;player.active=true;player.spawn_point=Vector3(-1,.03,0);player.reset_spawn();player.prepare_tracked_body()
			await frames(20)
			var raw_head:Transform3D=player.get_camera().transform;var expected_head:=raw_head;var max_y:float=player.global_position.y
			left.set_input("primary",Vector2(1,0) if mode=="controller" else Vector2.ZERO)
			for _i in 180:
				if mode=="roomscale":
					expected_head.origin.x=raw_head.origin.x+float(_i+1)*.02
					player.get_camera().transform=expected_head
				await physics_frame;max_y=maxf(max_y,player.global_position.y)
				if scenario=="ramp" and player.global_position.x>1.4:break
			left.set_input("primary",Vector2.ZERO);await frames(10)
			var finish:Vector3=player.global_position
			rows.append({"mode":mode,"case":scenario,"finish":[finish.x,finish.y,finish.z],"max_y":max_y,"steps":player.steps_up})
			check(player.get_camera().transform.is_equal_approx(expected_head),"Physical HMD pose remains untouched: "+scenario+" / "+mode)
			check(player.collision_mask==7,"Production locomotion retains collision mask: "+scenario+" / "+mode)
			match scenario:
				"ramp":check(finish.x>1.4 and finish.y>.43 and finish.y<.49 and player.steps_up>0,"Production XR player ascends from terrain onto authored ramp without toe stall: "+mode)
				"wall":check(finish.x<-.18 and max_y<.05,"Solid authored wall remains blocking from terrain: "+mode)
				"tall_ledge":check(finish.x<-.18 and max_y<.05,"Ledge above bounded step height cannot be climbed or crossed: "+mode)
				"low_ceiling":check(finish.x<.65 and max_y<.25,"Ceiling capsule sweep prevents stepping through insufficient headroom: "+mode)
			world.free();await process_frame
	XRServer.remove_tracker(left);XRServer.remove_tracker(head_tracker)
	var report:Dictionary={"checks":checks,"errors":errors,"rows":rows,"renderer":"dummy","physics":"Jolt and native SwgXRStepSolver","tracking":"mocked","headset_validated":false}
	FileAccess.open("res://../runtime/evidence/terrain-authored-handoff-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
