extends SceneTree
# SWG ClientChunk leaf tile: centre plus eight perimeter samples, eight faces.
# Compare physical ray heights with independent barycentric source-fan planes.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var evaluator:=SwgTerrainEvaluator.new()
	assert(evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain/tatooine.json"))))
	var builder:=SwgMeshBuilder.new()
	var checks:=0
	var maximum_error:=0.0
	for corner:Vector2 in [Vector2(3456,-4864),Vector2(-4008,6224),Vector2(5152,592),Vector2(-1300,-3600)]:
		var data:Dictionary=evaluator.build_chunk(corner.x,corner.y,4,2)
		assert(data.vertices.size()==9 and data.indices.size()==24)
		var vertices:PackedVector3Array=data.vertices
		# Independently enumerate the original tile's perimeter around its centre.
		var ring: Array[int]=[0,1,2,5,8,7,6,3]
		var actual:Dictionary={}
		for i in range(0,24,3):
			var triangle:Array[int]=[data.indices[i],data.indices[i+1],data.indices[i+2]]
			assert(4 in triangle,"Every original tile face must meet its centre")
			triangle.sort();actual[str(triangle)]=true
		var body:=StaticBody3D.new()
		var shape:=CollisionShape3D.new();shape.shape=builder.create_terrain_collision(data)
		body.add_child(shape);root.add_child(body)
		for i in 3: await physics_frame
		for i in 8:
			var a:=ring[i];var b:=ring[(i+1)%8]
			var triangle:Array[int]=[4,a,b];triangle.sort()
			assert(actual.has(str(triangle)),"Source fan face missing")
			var point:=vertices[4]*0.2+vertices[a]*0.3+vertices[b]*0.5
			var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*100,point-Vector3.UP*100)
			var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
			assert(not hit.is_empty())
			maximum_error=maxf(maximum_error,absf(hit.position.y-point.y))
			assert(absf(hit.position.y-point.y)<0.001,"Physical height differs from original fan plane")
			checks+=1
		body.queue_free();await physics_frame
	var report:Dictionary={"passed":true,"source_fan_faces_checked":checks,"maximum_height_error":maximum_error,"source_revision":"949451032647e45e42c3aaef3f41b132c8af36e3","hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/terrain-source-topology.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit()
