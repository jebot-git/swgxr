extends SceneTree
var errors: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)
func platform(world: Node3D, center: Vector3, size: Vector3, layer: int) -> void:
	var node := StaticBody3D.new()
	node.position = center
	node.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	node.add_child(shape)
	world.add_child(node)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	platform(world, Vector3(0,-0.1,0), Vector3(2,0.2,2), 1)
	platform(world, Vector3(0,0.15,0), Vector3(2,0.2,2), 2)
	platform(world, Vector3(2,0.2,0), Vector3(1,0.2,2), 1)
	var rig = load("res://xr/player_rig.tscn").instantiate()
	world.add_child(rig)
	var body: CharacterBody3D = rig.get_node("PlayerBody")
	body.set_physics_process(false)
	var driver = load("res://scripts/tracked_avatar.gd").new()
	world.add_child(driver)
	driver.body = body
	driver.set_process(false)
	await physics_frame
	await physics_frame
	body.collision_mask = 1
	var interior: Dictionary = driver.foot_ground(Vector3.ZERO, 0.0)
	check(not interior.is_empty() and absf(interior.position.y) < 0.001, "Interior feet sampled terrain instead of structure floor")
	body.collision_mask = 3
	var exterior: Dictionary = driver.foot_ground(Vector3.ZERO, 0.0)
	check(not exterior.is_empty() and absf(exterior.position.y-0.25) < 0.001, "Exterior feet did not include terrain")
	body.collision_mask = 1
	var step: Dictionary = driver.foot_ground(Vector3(2,0,0), 0.0)
	check(not step.is_empty() and absf(step.position.y-0.3) < 0.001, "Foot probe failed on a raised stair")
	check(driver.foot_ground(Vector3(8,0,0), 0.0).is_empty(), "Foot IK invented support across an empty gap")
	var report := {"test":"tracked_feet_collision_mask_and_support", "passed":errors.is_empty(), "errors":errors, "hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/tracked-ground-smoke.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
