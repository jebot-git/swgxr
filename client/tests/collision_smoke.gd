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

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	box(world, Vector3(0, 1.5, -3), Vector3(8, 3, 0.4))
	player = Player.new()
	world.add_child(player)
	player.spawn_point = Vector3(0, 1, 0)
	player.reset_spawn()
	player.active = true
	player.testing = true
	for i in range(120):
		await physics_frame
	var grounded := player.is_on_floor()
	var floor_y: float = player.position.y
	player.test_input = Vector2(0, -1)
	for i in range(120):
		await physics_frame
	var wall_stopped: bool = player.position.z > -2.51 and player.position.z < -2.0
	var stop_position := player.position
	player.test_input = Vector2(1, -1).normalized()
	for i in range(30):
		await physics_frame
	var slides: bool = player.position.x > 0.9 and player.position.z > -2.51
	player.reset_spawn()
	var reset_ok: bool = player.position.distance_to(player.spawn_point) < 0.001
	print(JSON.stringify({"test": "capsule_floor_wall_slide_reset", "grounded": grounded, "floor_y": floor_y, "wall_stopped": wall_stopped, "stop_position": str(stop_position), "slides": slides, "reset": reset_ok}))
	var passed: bool = grounded and absf(floor_y) < 0.03 and wall_stopped and slides and reset_ok
	print("COLLISION_SMOKE_PASS" if passed else "COLLISION_SMOKE_FAIL")
	quit(0 if passed else 1)
