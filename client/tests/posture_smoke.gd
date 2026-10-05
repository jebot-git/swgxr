extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func box(world: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = position
	world.add_child(body)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	box(world, Vector3(0, 1.5, 0), Vector3(3, 0.2, 4))
	var player := SwgFirstPersonController.new()
	world.add_child(player)
	player.position = Vector3(0, 0.1, 0)
	player.posture = 1
	player.testing = true
	player.active = true
	for i in range(60):
		await physics_frame
	var grounded_crouch: bool = player.is_on_floor() and player.posture == 1
	var blocked: bool = not player.request_posture(0) and player.posture == 1
	player.test_input = Vector2(1, 0)
	for i in range(100):
		await physics_frame
	player.test_input = Vector2.ZERO
	var stood: bool = player.request_posture(0) and player.posture == 0
	var prone: bool = player.request_posture(2) and player.camera.position.y < 0.7
	var before := player.position
	player.test_input = Vector2(0, -1)
	for i in range(30):
		await physics_frame
	player.test_input = Vector2.ZERO
	var crawls: bool = player.position.distance_to(before) > 0.3 and player.position.distance_to(before) < 0.8
	var sits: bool = player.request_posture(3)
	before = player.position
	player.test_input = Vector2(1, 0)
	for i in range(20):
		await physics_frame
	sits = sits and player.position.distance_to(before) < 0.01
	player.test_input = Vector2.ZERO
	player.request_posture(0)
	player.position.y += 1
	for i in range(2):
		await physics_frame
	var air_blocked: bool = not player.request_posture(2)
	var passed := grounded_crouch and blocked and stood and prone and crawls and sits and air_blocked
	print(JSON.stringify({"test": "native_posture_and_clearance", "grounded_crouch": grounded_crouch, "ceiling_blocks_standing": blocked, "stands_when_clear": stood, "prone_eye_height": prone, "bounded_crawl_speed": crawls, "sit_stops_movement": sits, "airborne_posture_blocked": air_blocked, "passed": passed}))
	quit(0 if passed else 1)
