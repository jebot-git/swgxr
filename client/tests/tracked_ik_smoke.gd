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

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/characters/")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json")))
	var reports: Array = []
	var all_passed := true
	var max_error := 0.0
	for race: String in catalog.races:
		var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(catalog.races[race].body)))
		var skeleton := skeleton_from(model)
		var solver := SwgTrackedIK.new()
		var configured := solver.configure(skeleton)
		var passed := configured
		var initial_positions: Array[Vector3] = []
		var initial_scales: Array[Vector3] = []
		for i in range(skeleton.get_bone_count()):
			initial_positions.append(skeleton.get_bone_pose_position(i))
			initial_scales.append(skeleton.get_bone_pose_scale(i))
		var targets := {}
		for side: String in ["left", "right"]:
			var prefix := "l" if side == "left" else "r"
			var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + "arm")).origin
			var basis := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + "wrist")).basis
			targets[side + "_hand"] = Transform3D(Basis(Vector3.UP, 0.35) * basis, shoulder + Vector3(-0.1 if side == "left" else 0.1, -0.15, -0.35))
		var head_index := skeleton.find_bone("head")
		var head_start := skeleton.get_bone_global_pose(head_index)
		targets.head = Transform3D(Basis.from_euler(Vector3(-0.2, 0.4, 0.1)) * head_start.basis, head_start.origin)
		var report: Dictionary = solver.solve(targets, 1.0 / 90)
		for side: String in ["left", "right"]:
			passed = passed and report[side].valid and not report[side].clamped and float(report[side].error) < 0.0001
			max_error = maxf(max_error, float(report[side].error))
			var hand: Transform3D = report[side].hand
			var target: Transform3D = targets[side + "_hand"]
			passed = passed and hand.basis.is_equal_approx(target.basis)
		passed = passed and skeleton.get_bone_global_pose(head_index).basis.is_equal_approx(targets.head.basis)
		passed = passed and skeleton.get_bone_global_pose(head_index).origin.is_equal_approx(head_start.origin)
		# Long sequences must preserve each original segment and avoid cumulative
		# twist/translation drift. Cross singular and unreachable target ranges.
		var maximum_elbow_change := 0.0
		var previous_elbow: Vector3 = report.left.elbow
		for frame in range(120):
			var t := frame / 120.0 * TAU
			var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("larm")).origin
			var target: Transform3D = targets.left_hand
			target.origin = shoulder + Vector3(-0.1, -0.15 + 0.08 * sin(t), -0.35 + 0.08 * cos(t))
			targets.left_hand = target
			report = solver.solve(targets, 1.0 / 90)
			passed = passed and report.left.valid and float(report.left.solver_error) < 0.0001
			var elbow: Vector3 = report.left.elbow
			maximum_elbow_change = maxf(maximum_elbow_change, elbow.distance_to(previous_elbow))
			previous_elbow = elbow
		passed = passed and maximum_elbow_change < 0.1
		var before_loss := skeleton.get_bone_global_pose(skeleton.find_bone("lwrist"))
		var target: Transform3D = targets.left_hand
		target.origin = Vector3(9, 9, -9)
		targets.left_hand = target
		targets.left_tracked = false
		report = solver.solve(targets, 1.0 / 90)
		passed = passed and not report.has("left") and skeleton.get_bone_global_pose(skeleton.find_bone("lwrist")).is_equal_approx(before_loss)
		targets.left_tracked = true
		report = solver.solve(targets, 1.0 / 90)
		passed = passed and report.left.clamped and float(report.left.solver_error) < 0.0001
		target.origin = skeleton.get_bone_global_pose(skeleton.find_bone("larm")).origin
		targets.left_hand = target
		report = solver.solve(targets, 1.0 / 90)
		passed = passed and report.left.valid and report.left.clamped and float(report.left.solver_error) < 0.0001
		for i in range(skeleton.get_bone_count()):
			passed = passed and skeleton.get_bone_pose_position(i).is_equal_approx(initial_positions[i]) and skeleton.get_bone_pose_scale(i).is_equal_approx(initial_scales[i])
		# Scale/world placement changes belong to the wrapper, not the solver.
		skeleton.scale = Vector3.ONE * 1.4
		skeleton.position = Vector3(35, 4, -78)
		skeleton.rotation.y = 1.2
		report = solver.solve(targets, 1.0 / 90)
		passed = passed and float(report.left.solver_error) < 0.0001
		skeleton.free()
		passed = passed and solver.solve(targets, 1.0 / 90).valid == false
		reports.append({"race": race, "passed": passed, "maximum_elbow_frame_delta": maximum_elbow_change})
		all_passed = all_passed and passed
	var invalid := SwgTrackedIK.new()
	all_passed = all_passed and not invalid.configure(null)
	var output := {"test": "native_tracked_ik_actual_swg_skeletons", "races": reports, "max_reachable_hand_error": max_error, "native": true, "hardware_tested": false, "passed": all_passed}
	print(JSON.stringify(output))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/tracked-ik-smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n")
	quit(0 if all_passed else 1)
