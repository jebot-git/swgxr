extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var avatar := Avatar.new()
	world.add_child(avatar)
	var report: Dictionary = avatar.configure("human_male")
	var expected := {"idle": [Vector3.ZERO, true, 0, 0], "walk": [Vector3(0, 0, -5.2), true, 0, 0], "run": [Vector3(0, 0, -9), true, 0, 0], "strafe_left": [Vector3(-3, 0, 0), true, 0, 0], "strafe_right": [Vector3(3, 0, 0), true, 0, 0], "backpedal": [Vector3(0, 0, 3), true, 0, 0], "jump": [Vector3(0, 5, 0), false, 0, 0], "fall": [Vector3(0, -5, 0), false, 0, 0], "crouch": [Vector3.ZERO, true, 1, 0], "crouch_walk": [Vector3(0, 0, -2), true, 1, 0], "prone": [Vector3.ZERO, true, 2, 0], "crawl": [Vector3(0, 0, -1), true, 2, 0], "sit": [Vector3.ZERO, true, 3, 0], "turn_left": [Vector3.ZERO, true, 0, 1], "turn_right": [Vector3.ZERO, true, 0, -1]}
	var cases := {}
	var passed := str(report.get("error", "")).is_empty()
	for state in expected:
		var values: Array = expected[state]
		cases[state] = avatar.select_motion_state(values[0], values[1], values[2], values[3]) == state
		passed = passed and cases[state]
	avatar.update_motion(0.016, 5.2)
	avatar.animation_player.play("walk", 0)
	avatar.animation_player.seek(0, true)
	avatar.animation_player.advance(0)
	var start: Array[Quaternion] = []
	for bone in range(avatar.skeleton.get_bone_count()):
		start.append(avatar.skeleton.get_bone_pose_rotation(bone))
	avatar.animation_player.advance(0.3)
	var changed := false
	for bone in range(start.size()):
		changed = changed or start[bone].angle_to(avatar.skeleton.get_bone_pose_rotation(bone)) > 0.01
	var face: bool = avatar.play_action("face_smile")
	var body: bool = avatar.play_action("emote_bow")
	var concurrent: bool = face and body and avatar.face_player.current_animation == "face_smile" and avatar.animation_player.current_animation == "emote_bow"
	avatar.update_motion(0.016, 5.2)
	var cancels_emote: bool = avatar.current_animation == "walk"
	avatar.update_motion(0.016, 0, {"grounded": false, "velocity": Vector3(0, 5, 0)})
	var air: bool = avatar.motion_state == "jump" and avatar.current_animation == "jump"
	avatar.update_motion(0.3, 0, {"grounded": false, "velocity": Vector3(0, -5, 0)})
	air = air and avatar.motion_state == "fall"
	avatar.update_motion(0.016, 0, {"grounded": true, "velocity": Vector3.ZERO})
	var lands: bool = avatar.motion_state == "land" and avatar.body_action == "landing"
	passed = passed and changed and concurrent and cancels_emote and air and lands
	print(JSON.stringify({"test": "original_animation_state_playback", "states": cases, "bone_motion_changes": changed, "independent_face_and_body": concurrent, "movement_cancels_emote": cancels_emote, "air_tracks_physics": air, "landing_phase": lands, "source": report.get("animation_source", ""), "clips": report.get("animation_states", []).size(), "actions": report.get("animation_actions", []).size(), "passed": passed}))
	quit(0 if passed else 1)
