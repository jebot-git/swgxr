extends SceneTree
var errors:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var motion:=SwgSnapshotMotion.new()
	check(motion.push_goal(Transform3D.IDENTITY,0,2.5,7,0,true),"First native baseline initializes presentation")
	check(motion.get_delay()==0,"SWG goal pursuit adds no snapshot buffer delay")
	var previous:=Vector3.ZERO
	var maximum_step:=0.0
	var packet:=.2
	var index:=0
	var latest:=0.0
	var jitter:=[.18,.24,.19,.21,.18]
	for frame in range(1,901):
		var now:=frame/90.0
		if now>=packet:
			# Core3 broadcasts next-step goals ahead of its simulated body.
			latest=(now+.4)*3
			motion.push_goal(Transform3D(Basis(Vector3.UP,now*.1),Vector3(latest,0,0)),now,2.5,7,3)
			packet+=jitter[index%jitter.size()];index+=1
		var pose:=motion.advance(now,1.0/90)
		var distance:=pose.origin.distance_to(previous);maximum_step=maxf(maximum_step,distance)
		check(pose.origin.x<=latest+.001,"Presentation never extrapolates beyond native endpoint")
		previous=pose.origin
	check(maximum_step<.09,"Irregular native goals render without packet-sized jumps")
	var held:Transform3D
	for frame in 900:held=motion.advance(10+frame/90.0,1.0/90)
	check(motion.get_velocity().length()<.001 and absf(held.origin.x-latest)<.001,"Missing packets settle exactly to the last endpoint")
	var before:=held.origin
	motion.push_goal(Transform3D(Basis.IDENTITY,before+Vector3(12,0,0)),21,2.5,7,7)
	var next:=motion.advance(21.01,1.0/90)
	check(next.origin.distance_to(before)<.1,"Delayed twelve-metre goal accelerates without teleporting")
	check(not motion.push(Transform3D.IDENTITY,20),"Older receipt cannot rewind motion")
	var warp:=Transform3D(Basis.IDENTITY,Vector3(200,0,0))
	motion.push(warp,22,true)
	check(motion.advance(22,.01)==warp,"Explicit relocation resets immediately")
	# Exercise real render/collision facade and sequence fences.
	var actor:=preload("res://combat/live_actor.gd").new();root.add_child(actor);actor.set_process(false)
	var row:Dictionary={"id":"1","kind":"creature","template":"fixture","health":100,"max_health":100,"dead":false,"cell_id":"0","movement_counter":10,"run_speed":7,"walk_speed":2.5}
	actor.visual=Node3D.new();actor.add_child(actor.visual)
	actor.collider=CollisionShape3D.new();actor.collider.shape=BoxShape3D.new();actor.add_child(actor.collider)
	actor.apply_record(row,Transform3D.IDENTITY,.2,true)
	var authority_age:=actor.snapshot_usec
	var streamed:Dictionary={"movement_counter":11,"sequence":1,"cell_id":"0","movement_speed":3}
	var endpoint:=Transform3D(Basis.IDENTITY,Vector3(4,0,0))
	check(actor.apply_motion(streamed,endpoint,1),"New native movement goal accepted")
	check(actor.snapshot_usec==authority_age,"Motion never refreshes health/ability authority age")
	check(not actor.apply_motion(streamed,warp,1),"Duplicate packet cannot change endpoint")
	row.health=90
	actor.apply_record(row,Transform3D.IDENTITY,.2)
	check(actor.goal==endpoint and actor.record.health==90,"Delayed health snapshot updates health without rewinding newer goal")
	row.movement_counter=11
	actor.apply_record(row,Transform3D.IDENTITY,.2)
	check(actor.goal==endpoint,"Equal-counter body snapshot does not replace next-step endpoint")
	for frame in 30:actor._process(1.0/90)
	var displayed:=actor.global_position
	check(displayed.x>0 and displayed.x<endpoint.origin.x,"Actor pursues latest goal on every frame")
	await physics_frame
	await physics_frame
	var query:=PhysicsRayQueryParameters3D.create(displayed+Vector3(0,0,2),displayed-Vector3(0,0,2),8)
	var hit:=root.world_3d.direct_space_state.intersect_ray(query)
	check(hit.get("collider")==actor,"Projectile physics contacts the same body transform as the displayed actor")
	query.from=endpoint.origin+Vector3(0,0,2);query.to=endpoint.origin-Vector3(0,0,2)
	check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(),"No invisible target collider at future native endpoint")
	row.cell_id="different-cell";row.movement_counter=1
	actor.apply_record(row,warp,.2)
	check(actor.global_transform==warp,"Cell transfer resets instead of traversing intervening geometry")
	check(not actor.apply_motion(streamed,endpoint,1),"Prior-cell motion cannot resurrect old collision")
	row.dead=true
	actor.apply_record(row,warp,.2)
	streamed.cell_id=row.cell_id
	check(not actor.apply_motion(streamed,endpoint,1) and actor.collision_layer==0,"Death disables target collision and rejects movement goals")
	actor.free()
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"maximum_step_m":maximum_step,"renderer":"dummy","network":"simulated jitter/loss"}))
	quit(0 if errors.is_empty() else 1)
