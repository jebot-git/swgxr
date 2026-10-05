extends SceneTree
## Offline original-asset playback only; no live population, AI or GPU claim.
const Avatar = preload("res://scripts/avatar.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func run() -> void:
	var interface := XRServer.find_interface("OpenXR")
	check(interface == null or not interface.is_initialized(), "Requires --xr-mode off")
	var path := ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	var catalog := Avatar.read_json(path)
	check(not catalog.get("races", {}).is_empty(), "Combat appearance catalog missing")
	var clips_checked := 0
	for id: String in catalog.get("races", {}):
		var avatar := Avatar.new()
		root.add_child(avatar)
		avatar.load_catalog(path)
		var report: Dictionary = avatar.configure(id)
		check(str(report.get("error", "")).is_empty(), "Appearance failed: " + id)
		check(avatar.skeleton != null and not avatar.meshes.is_empty(), "Missing original skeleton or mesh: " + id)
		if avatar.animation_player != null:
			for state in ["idle", "walk", "run"]:
				check(avatar.animation_player.has_animation(state), id + " missing " + state)
				if not avatar.animation_player.has_animation(state):
					continue
				avatar.animation_player.play(state, 0)
				avatar.animation_player.seek(0, true)
				avatar.animation_player.advance(0)
				var initial: Array[Transform3D] = []
				for bone in range(avatar.skeleton.get_bone_count()):
					initial.append(avatar.skeleton.get_bone_pose(bone))
				var changed := false
				for fraction in [0.17, 0.39, 0.73]:
					avatar.animation_player.seek(avatar.animation_player.current_animation_length * fraction, true)
					avatar.animation_player.advance(0)
					for bone in range(initial.size()):
						var pose: Transform3D = avatar.skeleton.get_bone_pose(bone)
						check(pose.is_finite(), id + " nonfinite bone pose")
						changed = changed or not initial[bone].is_equal_approx(pose)
				check(changed, id + " has no bone movement in " + state)
				clips_checked += 1
		else:
			check(false, "Missing animation player: " + id)
		avatar.queue_free()
		await process_frame
	print(JSON.stringify({"test": "original_combat_population_asset_playback", "passed": errors.is_empty(), "appearances": catalog.get("races", {}).size(), "clips_checked": clips_checked, "errors": errors, "live_core3": false, "gpu_validation": false}))
	quit(0 if errors.is_empty() else 1)
