extends SceneTree

const MASK = ["root", "spine1", "spine2", "spine3", "lthigh", "lshin", "lankle", "ltoe", "rthigh", "rshin", "rankle", "rtoe"]

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

func poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_pose(i))
	return result

func run() -> void:
	var directory := ProjectSettings.globalize_path("res://../runtime/assets/characters/")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json")))
	var reports: Array = []
	var all_passed := true
	for race: String in catalog.races:
		var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(catalog.races[race].body)))
		var skeleton := skeleton_from(model)
		var sampler := SwgBodyMotion.new()
		var passed := sampler.configure(skeleton)
		skeleton.global_transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.2), Vector3(4, 2, -17))
		var placement := skeleton.global_transform
		var sentinel := Quaternion.from_euler(Vector3(0.13, 0.21, -0.18))
		for i in range(skeleton.get_bone_count()):
			if not skeleton.get_bone_name(i) in MASK:
				skeleton.set_bone_pose_rotation(i, sentinel)
		var untouched := poses(skeleton)
		var clips := {}
		var tested := 0
		for state: String in ["idle", "walk", "run", "strafe_left", "strafe_right", "backpedal", "crouch", "crouch_walk", "stand_to_crouch", "crouch_to_stand"]:
			var animation := animation_from(model.animations[state])
			clips[state] = animation
			var report := sampler.sample(animation, animation.length * 0.2)
			passed = passed and report.valid and report.bones_written.size() == MASK.size() and report.target_tracks > 0
			var first := poses(skeleton)
			sampler.sample(animation, animation.length * 0.65)
			var second := poses(skeleton)
			var moved := false
			for i in range(skeleton.get_bone_count()):
				if skeleton.get_bone_name(i) in MASK:
					moved = moved or not first[i].is_equal_approx(second[i])
				else:
					passed = passed and second[i].is_equal_approx(untouched[i])
			passed = passed and moved
			tested += 1
		var walk: Animation = clips.walk
		var run_clip: Animation = clips.run
		sampler.sample(walk, 0.21)
		var walking := poses(skeleton)
		sampler.sample(run_clip, 0.17)
		var running := poses(skeleton)
		sampler.sample(run_clip, 0.17, walk, 0.21, 0.5)
		var blended := poses(skeleton)
		for name: String in MASK:
			var i := skeleton.find_bone(name)
			passed = passed and blended[i].origin.is_equal_approx(walking[i].origin.lerp(running[i].origin, 0.5))
			passed = passed and blended[i].basis.get_rotation_quaternion().angle_to(walking[i].basis.get_rotation_quaternion().slerp(running[i].basis.get_rotation_quaternion(), 0.5)) < 0.001
			# Simulate post-sample foot IK changing the current bone pose.
			skeleton.set_bone_pose_position(i, Vector3(5, 6, 7))
			skeleton.set_bone_pose_rotation(i, sentinel)
		sampler.sample(walk, 0.21 + walk.length)
		for name: String in MASK:
			var i := skeleton.find_bone(name)
			passed = passed and skeleton.get_bone_pose(i).is_equal_approx(walking[i])
		# Unsanitized root translation in an Animation must never become world
		# locomotion. Optional hip bob affects only the avatar pose.
		var synthetic := Animation.new()
		var root_track := synthetic.add_track(Animation.TYPE_POSITION_3D)
		synthetic.track_set_path(root_track, NodePath("Skeleton:root"))
		var root_index := skeleton.find_bone("root")
		var root_rest := skeleton.get_bone_rest(root_index).origin
		synthetic.position_track_insert_key(root_track, 0, root_rest + Vector3(90, 0.2, -90))
		var head_track := synthetic.add_track(Animation.TYPE_ROTATION_3D)
		synthetic.track_set_path(head_track, NodePath("Skeleton:head"))
		synthetic.rotation_track_insert_key(head_track, 0, Quaternion.IDENTITY)
		sampler.sample(synthetic, 0)
		passed = passed and skeleton.get_bone_pose_position(root_index).is_equal_approx(root_rest + Vector3(0, 0.2, 0))
		passed = passed and skeleton.get_bone_pose(skeleton.find_bone("head")).is_equal_approx(untouched[skeleton.find_bone("head")])
		sampler.sample(synthetic, 0, null, 0, 1, false)
		passed = passed and skeleton.get_bone_pose_position(root_index).is_equal_approx(root_rest)
		passed = passed and skeleton.global_transform.is_equal_approx(placement)
		passed = passed and not sampler.sample(walk, NAN).valid
		skeleton.free()
		passed = passed and not sampler.sample(walk, 0).valid
		reports.append({"race": race, "source_states_tested": tested, "passed": passed})
		all_passed = all_passed and passed
	var output := {"test": "native_masked_body_motion", "races": reports, "mask": MASK, "source_clip_blend": true, "tracking_bones_untouched": true, "root_horizontal_suppressed": true, "optional_hip_bob": true, "foot_ik_feedback_isolated": true, "passed": all_passed}
	print(JSON.stringify(output))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/body-motion-smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n")
	quit(0 if all_passed else 1)
