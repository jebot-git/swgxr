extends SceneTree

const Player = preload("res://scripts/player.gd")
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("run")

func box(parent: Node, position: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)

func settle(position: Vector3) -> void:
	player.test_input = Vector2.ZERO
	player.spawn_point = position
	player.reset_spawn()
	for i in range(90):
		await physics_frame

func walk(direction: Vector2, frames: int) -> float:
	var peak: float = player.position.y
	player.test_input = direction
	for i in range(frames):
		await physics_frame
		peak = maxf(peak, player.position.y)
	player.test_input = Vector2.ZERO
	return peak

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(10, -0.5, -3), Vector3(40, 1, 30))
	for i in range(4):
		var height := (i + 1) * 0.25
		box(world, Vector3(0, height / 2.0, -1.9 - i * 0.8), Vector3(4, height, 0.8))
	box(world, Vector3(0, 0.5, -5.8), Vector3(4, 1, 2.2))
	box(world, Vector3(10, 0.45, -3), Vector3(4, 0.9, 3))
	box(world, Vector3(20, 0.15, -3), Vector3(4, 0.3, 3))
	box(world, Vector3(20, 2.15, -3), Vector3(4, 0.3, 6))
	player = Player.new()
	world.add_child(player)
	player.active = true
	player.testing = true
	await settle(Vector3(0, 1, 0))
	var before: int = player.steps_taken
	var stair_peak: float = await walk(Vector2(0, -1), 65)
	var ascent_position: Vector3 = player.position
	var ascent_steps: int = player.steps_taken - before
	var climbs := stair_peak > 0.95 and ascent_position.z < -5 and ascent_steps >= 3
	await walk(Vector2(0, 1), 65)
	for i in range(45):
		await physics_frame
	var descends: bool = player.position.y < 0.05 and player.is_on_floor()
	await settle(Vector3(10, 1, 0))
	before = player.steps_taken
	var high_wall_peak: float = await walk(Vector2(0, -1), 90)
	var high_wall_position: Vector3 = player.position
	var high_wall: bool = high_wall_position.z > -1.55 and high_wall_peak < 0.05 and player.steps_taken == before
	await settle(Vector3(20, 0.1, 0.5))
	var ceiling_peak: float = await walk(Vector2(0, -1), 90)
	var ceiling_position: Vector3 = player.position
	var ceiling_blocks: bool = ceiling_position.z > -1.55 and ceiling_peak < 0.25
	var passed: bool = climbs and descends and high_wall and ceiling_blocks
	print(JSON.stringify({"test": "native_stairs_headroom_and_high_wall", "native": player is SwgFirstPersonController, "climbs_without_jump": climbs, "ascent": str(ascent_position), "ascent_steps": ascent_steps, "stair_peak": stair_peak, "descends": descends, "high_wall_blocks": high_wall, "high_wall_position": str(high_wall_position), "ceiling_blocks": ceiling_blocks, "ceiling_position": str(ceiling_position), "ceiling_peak": ceiling_peak, "passed": passed}))
	print("STAIR_SMOKE_PASS" if passed else "STAIR_SMOKE_FAIL")
	quit(0 if passed else 1)
