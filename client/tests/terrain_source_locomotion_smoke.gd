extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var source_path := "res://../runtime/assets/terrain/tatooine.json"
	var evaluator := SwgTerrainEvaluator.new()
	assert(evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string(source_path))))
	var builder := SwgMeshBuilder.new()
	var chosen := {}
	for corner: Vector2 in [Vector2(3456,-4864),Vector2(3712,-4864),Vector2(3968,-4864),Vector2(3200,-4864),Vector2(4096,-4608),Vector2(-4096,6144),Vector2(5120,512),Vector2(6400,-1408)]:
		var data: Dictionary=evaluator.build_chunk(corner.x,corner.y,128,64)
		var vertices:PackedVector3Array=data.vertices
		var indices:PackedInt32Array=data.indices
		for i in range(0,indices.size(),3):
			var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
			var normal:Vector3=(b-a).cross(c-a).normalized()
			if normal.y<0:normal=-normal
			var angle:=rad_to_deg(normal.angle_to(Vector3.UP))
			var center:Vector3=(a+b+c)/3.0
			if angle>50 and angle<78 and center.x>8 and center.x<120 and center.z< -8 and center.z> -120:
				chosen={"data":data,"normal":normal,"center":center,"angle":angle,"corner":corner}
				break
		if not chosen.is_empty():break
	assert(not chosen.is_empty(),"No authentic steep Tatooine triangle found in source fixture areas")
	if chosen.is_empty():quit(1);return
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=2
	var floor_shape:=CollisionShape3D.new();floor_shape.shape=builder.create_terrain_collision(chosen.data)
	floor_body.add_child(floor_shape);root.add_child(floor_body)
	var body:=CharacterBody3D.new();body.collision_mask=7
	var capsule:=CapsuleShape3D.new();capsule.radius=0.25;capsule.height=1.7
	var collision:=CollisionShape3D.new();collision.shape=capsule;collision.position.y=0.85;body.add_child(collision);root.add_child(body)
	var solver:=SwgXRStepSolver.new()
	body.position=chosen.center+Vector3.UP*0.001
	for i in 3:await physics_frame
	var normal:Vector3=chosen.normal
	var direction:Vector3=-Vector3(normal.x,0,normal.z).normalized()
	var start:=body.position
	var maximum_gap:=0.0
	var complete:=true
	for i in 60:
		var result:Dictionary=solver.move_on_terrain(body,direction*0.03)
		complete=complete and result.handled
		var support:Dictionary=solver.terrain_support(body,body.position,0.1,0.1)
		complete=complete and support.valid
		if support.valid:maximum_gap=maxf(maximum_gap,absf(body.position.y-float(support.height)))
		await physics_frame
	var uphill:=body.position-start
	for i in 60:
		var result:Dictionary=solver.move_on_terrain(body,-direction*0.03)
		complete=complete and result.handled
		await physics_frame
	var passed:=complete and uphill.y>0.4 and maximum_gap<0.01 and body.position.distance_to(start)<0.15
	var report:Dictionary={"test":"actual_tatooine_steep_terrain_follow","passed":passed,"source":source_path,"source_chunk":str(chosen.corner),"triangle_slope_degrees":chosen.angle,"uphill_motion":str(uphill),"return_error":body.position.distance_to(start),"maximum_foot_gap":maximum_gap,"all_steps_supported":complete,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/terrain-source-locomotion-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));body.queue_free();floor_body.queue_free();await process_frame;quit(0 if passed else 1)
