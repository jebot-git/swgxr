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

func original_joints(skeleton: Skeleton3D, prefix: String) -> Dictionary:
	var wrist := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + "wrist"))
	var joints := {}
	for digit: String in ["thumb", "index", "ring"]:
		var first := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + digit + "01")).origin
		var second := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + digit + "02")).origin
		var tip := second + (second - first).normalized() * 0.025
		joints[digit + ("_metacarpal" if digit == "thumb" else "_proximal")] = wrist.affine_inverse() * first
		joints[digit + ("_proximal" if digit == "thumb" else "_intermediate")] = wrist.affine_inverse() * second
		joints[digit + "_tip"] = wrist.affine_inverse() * tip
	return joints

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/characters/")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json")))
	var reports: Array = []
	var all_passed := true
	for race: String in catalog.races:
		var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(catalog.races[race].body)))
		var skeleton := skeleton_from(model)
		var solver := SwgFingerRetargeter.new()
		var passed := solver.configure(skeleton)
		var poses: Array[Quaternion] = []
		var positions: Array[Vector3] = []
		for i in range(skeleton.get_bone_count()):
			poses.append(skeleton.get_bone_pose_rotation(i))
			positions.append(skeleton.get_bone_pose_position(i))
		var tracked := {"left": original_joints(skeleton, "l"), "right": original_joints(skeleton, "r")}
		var report: Dictionary = solver.apply_controller({}, {})
		passed = passed and report.valid and report.unavailable_fingers == PackedStringArray(["middle", "little"])
		for i in range(skeleton.get_bone_count()):
			passed = passed and skeleton.get_bone_pose_rotation(i).is_equal_approx(poses[i])
		var fist := {"grip": 1.0, "trigger": 1.0, "thumb_touch": true}
		solver.apply_controller(fist, fist)
		var fist_angles := {}
		for prefix: String in ["l", "r"]:
			for digit: String in ["thumb", "index", "ring"]:
				for number: String in ["01", "02"]:
					var name := prefix + digit + number
					var index := skeleton.find_bone(name)
					var angle := poses[index].angle_to(skeleton.get_bone_pose_rotation(index))
					fist_angles[name] = angle
					passed = passed and angle > 0.4 and angle < 1.6
		# Grip while index is untouched points; released untouched thumb extends
		# independently, allowing the common controller thumbs-up state.
		var point := {"grip": 1.0, "trigger": 0.0, "thumb_touch": true}
		report = solver.apply_controller(point, point)
		passed = passed and report.left.index_curl == 0 and report.left.ring_curl == 1
		var up := {"grip": 1.0, "trigger": 1.0, "thumb_touch": false}
		report = solver.apply_controller(up, up)
		passed = passed and report.left.thumb_curl == 0 and report.left.index_curl == 1
		report = solver.apply_controller({"trigger_touch": true}, {"trigger_touch": true})
		passed = passed and report.left.index_curl > 0 and report.left.index_curl < 0.2
		for side: String in ["left", "right"]:
			var prefix := "l" if side == "left" else "r"
			solver.apply_controller({}, {})
			# A full arbitrary tracker wrist-coordinate rotation must not change
			# the retargeted pose: native mapping derives the anatomical palm.
			var joints: Dictionary = tracked[side].duplicate()
			var arbitrary := Basis.from_euler(Vector3(0.6, -1.1, 0.7))
			for key: String in joints:
				joints[key] = arbitrary * Vector3(joints[key])
			report = solver.apply_hand_joints(side, joints)
			passed = passed and report.valid and report.fingers_applied == 3
			for digit: String in ["thumb", "index", "ring"]:
				for number: String in ["01", "02"]:
					var index := skeleton.find_bone(prefix + digit + number)
					passed = passed and poses[index].angle_to(skeleton.get_bone_pose_rotation(index)) < 0.001
			# Bend just index and verify separate source index articulation while
			# root/arm/wrist transforms and other finger chains remain unchanged.
			joints = tracked[side].duplicate()
			var ip: Vector3 = joints.index_proximal
			var rp: Vector3 = joints.ring_proximal
			var forward := ((ip + rp) * 0.5).normalized()
			var across := (ip - rp).slide(forward).normalized()
			var index_direction: Vector3 = joints.index_intermediate - ip
			var curl := Basis(across, 0.85)
			joints.index_intermediate = ip + curl * index_direction
			joints.index_tip = Vector3(joints.index_intermediate) + curl * curl * index_direction.normalized() * 0.025
			report = solver.apply_hand_joints(side, joints)
			passed = passed and report.valid and poses[skeleton.find_bone(prefix + "index01")].angle_to(skeleton.get_bone_pose_rotation(skeleton.find_bone(prefix + "index01"))) > 0.6
		passed = passed and not solver.apply_hand_joints("left", {}).valid
		for i in range(skeleton.get_bone_count()):
			passed = passed and skeleton.get_bone_pose_position(i).is_equal_approx(positions[i])
			var name := skeleton.get_bone_name(i)
			if not ("thumb" in name or "index" in name or "ring" in name):
				passed = passed and skeleton.get_bone_pose_rotation(i).is_equal_approx(poses[i])
		skeleton.free()
		passed = passed and not solver.apply_controller({}, {}).valid
		reports.append({"race": race, "passed": passed, "fist_angles": fist_angles})
		all_passed = all_passed and passed
	var output := {"test": "native_sparse_finger_retarget", "races": reports, "independent_fingers": ["thumb", "index", "ring"], "missing_independent_fingers": ["middle", "little"], "open_point_fist_thumbs_up_touch": true, "arbitrary_tracker_wrist_axes": true, "native": true, "hardware_tested": false, "passed": all_passed}
	print(JSON.stringify({"test": output.test, "races": reports.size(), "passed": all_passed, "hardware_tested": false, "report": "runtime/evidence/finger-retarget-smoke.json"}))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/finger-retarget-smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n")
	quit(0 if all_passed else 1)
