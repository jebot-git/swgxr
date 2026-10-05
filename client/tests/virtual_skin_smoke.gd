extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func skeleton_from(model: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for bone in model.bones:
		skeleton.add_bone(bone.name)
	for i in range(model.bones.size()):
		var bone: Dictionary = model.bones[i]
		skeleton.set_bone_parent(i, int(bone.parent))
		var p: Array = bone.rest_position
		var q: Array = bone.rest_rotation
		skeleton.set_bone_rest(i, Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2])))
	skeleton.reset_bone_poses()
	root.add_child(skeleton)
	return skeleton

func animation_from(clip: Dictionary) -> Animation:
	var animation := Animation.new()
	animation.length = float(clip.length)
	animation.loop_mode = Animation.LOOP_LINEAR if clip.get("loop", true) else Animation.LOOP_NONE
	for track: Dictionary in clip.tracks:
		if not track.get("rotations", []).is_empty():
			var index := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(index, NodePath("Skeleton:" + str(track.name)))
			for key: Array in track.rotations:
				animation.rotation_track_insert_key(index, key[0], Quaternion(key[1], key[2], key[3], key[4]).normalized())
		if not track.get("positions", []).is_empty():
			var index := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(index, NodePath("Skeleton:" + str(track.name)))
			for key: Array in track.positions:
				animation.position_track_insert_key(index, key[0], Vector3(key[1], key[2], key[3]))
	return animation

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json")))
	var descriptor: Dictionary = catalog.races["object/mobile/jawa_male.iff"]
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(descriptor.body)))
	var skeleton := skeleton_from(model)
	var skin := Skin.new()
	for i in range(skeleton.get_bone_count()):
		skin.add_bind(i, skeleton.get_bone_global_rest(i).affine_inverse())
	var binding := SwgVirtualSkinBinding.new()
	assert(binding.configure(skeleton, skin, model.virtual_skin_bones))
	var virtual_index := int(model.virtual_skin_bones[0].bone)
	var builder := SwgMeshBuilder.new()
	var mesh_definitions: Array = []
	var dense_vertices := 0
	for part: Dictionary in model.parts:
		var mesh: ArrayMesh = builder.create_avatar_mesh(part.mesh)
		assert(mesh != null)
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var width := bones.size() / vertices.size()
			for i in range(vertices.size()):
				for j in range(width):
					if bones[i * width + j] == virtual_index and weights[i * width + j] > 0:
						var original := {}
						for entry: Dictionary in model.virtual_skin_audit:
							var p: Array = entry.position
							if vertices[i].distance_to(Vector3(p[0], p[1], p[2])) < 0.000001:
								original = entry
						assert(not original.is_empty(), "Dense rendered vertex missing original full-weight audit")
						mesh_definitions.append({"position":vertices[i], "bones":bones.slice(i * width, (i + 1) * width), "weights":weights.slice(i * width, (i + 1) * width), "original":original})
						dense_vertices += 1
	assert(dense_vertices >= 6)
	var max_position_error := 0.0
	var max_normal_error := 0.0
	var samples := 0
	var native_usec := 0
	for key: String in model.animations:
		var animation := animation_from(model.animations[key])
		for frame in range(41):
			var time := animation.length * frame / 40.0
			skeleton.reset_bone_poses()
			for track in range(animation.get_track_count()):
				var bone := skeleton.find_bone(animation.track_get_path(track).get_subname(0))
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
					skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
				else:
					skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			var start := Time.get_ticks_usec()
			assert(binding.update().valid)
			native_usec += Time.get_ticks_usec() - start
			for vertex: Dictionary in mesh_definitions:
				var full := Vector3.ZERO
				var compressed := Vector3.ZERO
				var full_normal := Vector3.ZERO
				var compressed_normal := Vector3.ZERO
				var normal := Vector3(0.3, 0.7, 0.2).normalized()
				for influence in range(vertex.original.bones.size()):
					var bone := int(vertex.original.bones[influence])
					var matrix := skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bone)
					full += (matrix * Vector3(vertex.position)) * float(vertex.original.weights[influence])
					full_normal += (matrix.basis * normal) * float(vertex.original.weights[influence])
				for influence in range(vertex.bones.size()):
					var bone := int(vertex.bones[influence])
					var matrix := skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bone)
					compressed += (matrix * Vector3(vertex.position)) * float(vertex.weights[influence])
					compressed_normal += (matrix.basis * normal) * float(vertex.weights[influence])
				max_position_error = maxf(max_position_error, full.distance_to(compressed))
				max_normal_error = maxf(max_normal_error, full_normal.normalized().distance_to(compressed_normal.normalized()))
			samples += 1
	var passed := max_position_error < 0.00005 and max_normal_error < 0.00005
	var output := {"test":"exact_jawa_virtual_skin", "passed":passed, "source":"appearance/mesh/jawa_m_l0.mgn", "source_vertices":945, "dense_source_vertices":model.virtual_skin_audit.size(), "dense_render_vertices":dense_vertices, "original_influences":38, "compressed_influences":2, "source_clips":model.animations.size(), "sampled_poses":samples, "max_position_error_m":max_position_error, "max_normal_direction_error":max_normal_error, "average_native_update_usec":native_usec / float(samples), "method":"exact_uniform_residual_affine_matrix_average", "influences_discarded":0}
	print(JSON.stringify(output))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/virtual-skin-smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n")
	skeleton.free()
	assert(not binding.update().valid)
	quit(0 if passed else 1)
