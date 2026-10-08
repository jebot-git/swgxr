extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func area(data:Dictionary)->float:
	var total:=0.0
	var v:PackedVector3Array=data.vertices
	var indices:PackedInt32Array=data.indices
	for i in range(0,indices.size(),3):
		var a:=v[indices[i]];var b:=v[indices[i+1]];var c:=v[indices[i+2]]
		total+=absf(Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)))*.5
	return total
func run() -> void:
	var source:Dictionary={"fractals":[],"layers":[{"enabled":true,"boundaries":[{"type":"BREC","enabled":true,"rect":[5.3,4.7,9.2,11.1]}],"affectors":[{"type":"AEXC","enabled":true}]}]}
	var evaluator:=SwgTerrainEvaluator.new()
	assert(evaluator.configure(source))
	var builder:=SwgMeshBuilder.new()
	var cases:Array=[]
	var expected:=256.0-(9.2-5.3)*(11.1-4.7)
	for resolution:int in [1,2,4,8,16]:
		var data:=evaluator.build_chunk(0,0,16,resolution)
		var measured:=area(data)
		assert(absf(measured-expected)<.03,"Exclusion area differs from exactsource rectangle "+str(measured))
		var shape:=builder.create_terrain_collision(data)
		var mesh:=builder.create_terrain_mesh(data,0)
		assert(shape.get_faces().size()==data.indices.size())
		assert(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==data.indices.size())
		cases.append({"resolution":resolution,"surface_area":measured,"boundary_vertices":data.exclusion_boundary_vertices,"same_render_collision_triangles":true})
	var body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	collider.shape=builder.create_terrain_collision(evaluator.build_chunk(0,0,16,8))
	body.add_child(collider);root.add_child(body)
	for i in range(3):await physics_frame
	for point:Vector2 in [Vector2(5.28,8),Vector2(5.32,8),Vector2(9.18,8),Vector2(9.22,8)]:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,1,-point.y),Vector3(point.x,-1,-point.y))
		var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
		assert(hit.is_empty()==bool(evaluator.sample(point.x,point.y).excluded),"Collider erodes outside sourceedge")
	var actual:=SwgTerrainEvaluator.new()
	assert(actual.configure(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json")))))
	var started:=Time.get_ticks_usec()
	var actual_data:=actual.build_chunk(-2592,-5528,16,8)
	var usec:=Time.get_ticks_usec()-started
	assert(actual_data.exclusion_boundary_vertices>0)
	var crack_cases: Array = []
	for corner: Vector2 in [Vector2(-4008,6224),Vector2(5152,592),Vector2(6544,-1312)]:
		var refined := actual.build_chunk(corner.x,corner.y,32,16)
		var points: PackedVector3Array = refined.vertices
		var maximum_error := 0.0
		var low := INF
		var high := -INF
		for i in range(17*17):
			low=minf(low,points[i].y);high=maxf(high,points[i].y)
		for i in range(17*17,points.size()):
			var point := points[i]
			var col:=clampi(floori(point.x/2),0,15)
			var row:=clampi(floori(-point.z/2),0,15)
			var u:=clampf(point.x/2-col,0,1)
			var v:=clampf(-point.z/2-row,0,1)
			var a:=row*17+col;var b:=a+1;var c:=a+17;var d:=c+1
			var plane:=points[a].y+u*(points[b].y-points[a].y)+v*(points[c].y-points[a].y) if u+v<=1 else points[d].y+(1-v)*(points[b].y-points[d].y)+(1-u)*(points[c].y-points[d].y)
			if (roundi(corner.x/2)+col+roundi(corner.y/2)+row)%2==0:
				plane=points[a].y+u*(points[b].y-points[a].y)+v*(points[d].y-points[b].y) if u>=v else points[a].y+v*(points[c].y-points[a].y)+u*(points[d].y-points[c].y)
			maximum_error=maxf(maximum_error,absf(point.y-plane))
		assert(maximum_error<.001,"Adaptive exclusion vertices split original terrain surface")
		crack_cases.append({"source_corner":str(corner),"height_span_m":high-low,"inserted_vertices":points.size()-17*17,"maximum_coarse_surface_error_m":maximum_error})
	assert(crack_cases.any(func(value):return value.height_span_m>1 and value.inserted_vertices>0),"Crack test did not exercise nonflat source terrain")
	var report:Dictionary={"test":"source_AEXC_boundary_shared_geometry","passed":true,"source_rectangle_expected_area":expected,"nonflat_refinement_continuity":crack_cases,"cases":cases,"actual_source_boundary_vertices":actual_data.exclusion_boundary_vertices,"actual_build_usec":usec,"boundary_sampling_m":.125,"outside_edge_collision_retained_2cm":true,"inside_edge_hole_present_2cm":true,"render_collision_shared_indices":true}
	print(JSON.stringify(report))
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/terrain-exclusion-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	body.queue_free();await process_frame;quit()
