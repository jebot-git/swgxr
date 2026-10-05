extends SceneTree

const StageLoader = preload("res://scripts/stage_loader.gd")
const Player = preload("res://scripts/player.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var assets := "res://../runtime/assets_review" if "--review-assets" in OS.get_cmdline_user_args() else "res://../runtime/assets"
	var loader := StageLoader.new()
	var stage = loader.load_stage(ProjectSettings.globalize_path(assets.path_join("mos_eisley/scene.json")))
	if stage == null:
		push_error(loader.report.error)
		quit(1)
		return
	root.add_child(stage)
	var player := Player.new()
	root.add_child(player)
	player.ground_provider = stage
	player.spawn_point = Vector3(-62.9, 1.2, 12.7)
	player.reset_spawn()
	player.testing = true
	player.active = true
	stage.set_observer(player)
	for i in range(90):
		await physics_frame
	var cell_ok: bool = stage.current_cell.get("cell_id", "") == "1106368:4"
	var shell_kept_visible := true
	var shell_disabled := true
	for instance in stage.exterior_instances:
		if int(instance.get_meta("building_object_id",0)) != 1106368:
			continue
		shell_kept_visible = shell_kept_visible and instance.visible
		for child in instance.get_children():
			if child is StaticBody3D:
				shell_disabled = shell_disabled and child.collision_layer == 0
	# Rendering and authored collision are separate. Walk through the former
	# collidable pale wall at x=-61.27 within the valid foyer floor polygon.
	player.test_input = Vector2(1, 0)
	for i in range(45):
		await physics_frame
	player.test_input = Vector2.ZERO
	var crosses_old_shell: bool = player.position.x > -60.0 and player.is_on_floor()
	var interior_position := player.position
	# A genuine room wall must still block the capsule.
	player.spawn_point = Vector3(-60, 1.2, 10)
	player.reset_spawn()
	for i in range(60):
		await physics_frame
	player.test_input = Vector2(-1, 0)
	for i in range(180):
		await physics_frame
	player.test_input = Vector2.ZERO
	var real_wall_blocks: bool = player.position.x > -69.2 and player.position.x < -68.0
	var wall_position := player.position
	player.active = false
	player.position = Vector3(-85, 0.6, 1.6)
	stage.update_cell()
	var exterior_restored: bool = stage.current_cell.is_empty()
	for instance in stage.exterior_instances:
		exterior_restored = exterior_restored and instance.visible
		for child in instance.get_children():
			if child is StaticBody3D:
				exterior_restored = exterior_restored and child.collision_layer == 1
	var ramp_cell: Dictionary = stage.classifier.classify(Vector3(-60.4, 1.2, 21))
	var ramp_classified: bool = ramp_cell.get("cell_id", "") == "1106368:8"
	var roof_excluded: bool = stage.classifier.classify(Vector3(-60, 50, 10)).is_empty()
	var passed: bool = cell_ok and shell_kept_visible and shell_disabled and crosses_old_shell and real_wall_blocks and exterior_restored and ramp_classified and roof_excluded
	print(JSON.stringify({"test": "actual_interior_exterior_cell_collision", "cell_correct": cell_ok, "shell_kept_visible": shell_kept_visible, "shell_collision_disabled": shell_disabled, "crossed_old_shell": crosses_old_shell, "interior_position": str(interior_position), "real_wall_blocks": real_wall_blocks, "wall_position": str(wall_position), "exterior_restored": exterior_restored, "ramp_classified": ramp_classified, "roof_excluded": roof_excluded}))
	print("CELL_COLLISION_PASS" if passed else "CELL_COLLISION_FAIL")
	quit(0 if passed else 1)
