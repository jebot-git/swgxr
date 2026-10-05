extends SceneTree

const Player = preload("res://scripts/player.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loader = StageLoader.new()
	var stage = loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	if stage == null:
		push_error(loader.report.error)
		quit(1)
		return
	root.add_child(stage)
	var player = Player.new()
	root.add_child(player)
	player.spawn_point = Vector3(-60.42, 1.2, 18.3)
	player.spawn_yaw = -3.1224
	player.reset_spawn()
	player.active = true
	player.testing = true
	stage.set_observer(player)
	for i in range(90):
		await physics_frame
	var start: Vector3 = player.position
	var steps_before: int = player.steps_taken
	player.test_input = Vector2(0, -1)
	for i in range(55):
		await physics_frame
	player.test_input = Vector2.ZERO
	for i in range(30):
		await physics_frame
	var top: Vector3 = player.position
	var stepped: int = player.steps_taken - steps_before
	var ascends: bool = top.z > 22.8 and top.y - start.y > 0.85 and player.is_on_floor() and stepped > 0
	player.test_input = Vector2(0, 1)
	for i in range(55):
		await physics_frame
	player.test_input = Vector2.ZERO
	for i in range(60):
		await physics_frame
	var bottom: Vector3 = player.position
	var descends: bool = bottom.z < 18.6 and absf(bottom.y - start.y) < 0.1 and player.is_on_floor()
	var passed: bool = ascends and descends
	print(JSON.stringify({"test": "native_original_ticket1_stairs", "source": "appearance/mesh/mun_tato_starport_s01_u01_r8_ticket1_mesh_r8.msh", "native": player is SwgFirstPersonController, "start": str(start), "top": str(top), "bottom": str(bottom), "steps": stepped, "ascends_without_jump": ascends, "descends": descends, "passed": passed}))
	print("IMPORTED_STAIR_SMOKE_PASS" if passed else "IMPORTED_STAIR_SMOKE_FAIL")
	quit(0 if passed else 1)
