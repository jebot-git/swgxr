extends SceneTree

func _initialize() -> void:
	var builder := SwgMeshBuilder.new()
	var surface := {
		"vertices":[0,0,0, 1,0,0, 0,1,0, 0,2,0, 1,2,0, 0,3,0],
		"normals":[0,0,1, 0,0,1, 0,0,1, 0,0,1, 0,0,1, 0,0,1],
		"uv":[0,0, 1,0, 0,1, 0,0, 1,0, 0,1],
		"indices":[0,2,1, 3,5,4],
		"bones":[0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
		"weights":[1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
		"triangle_zones":[["chest"],["head"]],
		"blend_shapes":{"width":{"vertices":[0,0,0, .1,0,0, 0,0,0, 0,0,0, .2,0,0, 0,0,0]}}
	}
	var definition := {"bone_count":2,"surfaces":[surface],"blend_shapes":["width"]}
	var result: Dictionary = builder.partition_avatar(definition, [1], 0.45)
	assert(result.statistics.body_triangles == 1 and result.statistics.head_triangles == 1)
	assert(result.body.surfaces[0].indices == [0,2,1])
	assert(result.head.surfaces[0].indices == [3,5,4])
	assert(result.body.surfaces[0].triangle_zones == [["chest"]])
	assert(result.head.surfaces[0].triangle_zones == [["head"]])
	assert(surface.indices == [0,2,1,3,5,4], "Input source topology mutated")
	for part in [result.body,result.head]:
		assert(part.surfaces[0].vertices == surface.vertices)
		assert(part.surfaces[0].weights == surface.weights)
		assert(part.surfaces[0].blend_shapes == surface.blend_shapes)
		assert(builder.create_avatar_mesh(part) != null)
	assert(builder.partition_avatar(definition,[3],0.45).is_empty())
	assert(builder.partition_avatar(definition,[1],0.0).is_empty())
	print("AVATAR_PARTITION_PASS source topology, weights, morphs, zones and third-person union preserved")
	quit()
