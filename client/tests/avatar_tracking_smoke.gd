extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var avatar := Avatar.new()
	root.add_child(avatar)
	var results: Array = []
	for race in ["human_male", "ithorian_male", "wookiee_male"]:
		var report: Dictionary = avatar.configure(race, {"profession":"crafting_artisan"})
		assert(report.error == "", report.error)
		avatar.set_tracking_mode(true)
		assert(not avatar.animation_player.active and not avatar.face_player.active)
		var left := avatar.skeleton.find_bone("lwrist")
		var right := avatar.skeleton.find_bone("rwrist")
		assert(not left in avatar.first_person_hidden_bones and not right in avatar.first_person_hidden_bones)
		var external_pose := Quaternion.from_euler(Vector3(0.1, 0.2, 0.3))
		avatar.skeleton.set_bone_pose_rotation(left, external_pose)
		assert(not avatar.play_action("emote_wave"))
		assert(not avatar.play_action("face_smile"))
		avatar.update_motion(1.0, 7.0, {"grounded":false,"velocity":Vector3(0,4,-7)})
		for frame in range(3):
			await process_frame
		assert(avatar.skeleton.get_bone_pose_rotation(left).is_equal_approx(external_pose), "Animation overwrote externally tracked joint")
		var body_triangles := 0
		var head_triangles := 0
		var forbidden_body_triangles := 0
		for mesh in avatar.meshes:
			assert(mesh.layers in [1,2])
			for si in range(mesh.mesh.get_surface_count()):
				var arrays: Array = mesh.mesh.surface_get_arrays(si)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if mesh.layers == 2:
					head_triangles += indices.size() / 3
					continue
				body_triangles += indices.size() / 3
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var width: int = bones.size() / vertices.size()
				for index in indices:
					var head_weight := 0.0
					for influence in range(width):
						if bones[index * width + influence] in avatar.first_person_hidden_bones:
							head_weight += weights[index * width + influence]
					if head_weight >= 0.45001:
						forbidden_body_triangles += 1
		assert(body_triangles > 0 and head_triangles > 0)
		assert(forbidden_body_triangles == 0, "Head-weighted geometry remains in first-person layer")
		avatar.set_tracking_mode(false)
		assert(avatar.animation_player.active and avatar.face_player.active)
		avatar.update_motion(0.1, 3.0)
		assert(avatar.current_animation == "walk", "Desktop animation did not resume")
		results.append({"race":race,"body_triangles":body_triangles,"head_triangles":head_triangles,"partitioned_neck_triangles":report.get("partitioned_head_triangles",0),"tracked_pose_retained":true,"desktop_resumed":true})
	print("AVATAR_TRACKING_PASS ", JSON.stringify(results))
	quit()
