extends SceneTree

func _initialize() -> void:
	var builder := SwgMeshBuilder.new()
	var surface := {
		"vertices": [0,0,0, 1,0,0, 0,1,0],
		"normals": [0,0,1, 0,0,1, 0,0,1],
		"uv": [0,0, 1,0, 0,1], "indices": [0,2,1],
		"bones": [0,1,0,0, 0,1,0,0, 1,0,0,0],
		"weights": [0.5,0.5,0,0, 0.25,0.75,0,0, 1,0,0,0],
		"blend_shapes": {"face_width": {"vertices": [0,0,0, 0.1,0,0, -0.1,0,0]}}
	}
	var mesh := builder.create_avatar_mesh({"surfaces": [surface], "bone_count": 2, "blend_shapes": ["face_width", "unused_on_this_surface"]})
	if mesh == null:
		quit(1)
		return
	var arrays := mesh.surface_get_arrays(0)
	var morphs := mesh.surface_get_blend_shape_arrays(0)
	var passed: bool = mesh.get_blend_shape_mode() == Mesh.BLEND_SHAPE_MODE_RELATIVE and mesh.get_blend_shape_count() == 2
	passed = passed and arrays[Mesh.ARRAY_BONES].size() == 12 and arrays[Mesh.ARRAY_WEIGHTS].size() == 12
	passed = passed and is_equal_approx(arrays[Mesh.ARRAY_WEIGHTS][5], 0.75)
	passed = passed and morphs[0][Mesh.ARRAY_VERTEX][1].is_equal_approx(Vector3(0.1, 0, 0))
	passed = passed and morphs[1][Mesh.ARRAY_VERTEX][1].is_equal_approx(Vector3.ZERO)
	# The 8-influence path must preserve the extra joints and declare its format.
	surface.bones = [0,1,2,3,4,5,6,7, 0,1,2,3,4,5,6,7, 0,1,2,3,4,5,6,7]
	surface.weights = []
	for i in range(24): surface.weights.append(0.125)
	var eight := builder.create_avatar_mesh({"surfaces": [surface], "bone_count": 8})
	passed = passed and eight != null
	if eight != null:
		passed = passed and (eight.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0
		passed = passed and eight.surface_get_arrays(0)[Mesh.ARRAY_BONES][7] == 7
	print("AVATAR_MESH_PASS" if passed else "AVATAR_MESH_FAIL")
	quit(0 if passed else 1)
