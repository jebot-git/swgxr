extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := SwgFirstPersonController.new()
	world.add_child(player)
	await physics_frame
	var default_eye: bool = absf(player.camera.position.y - 1.65) < 0.0001
	player.avatar_height = 2.4
	var tall_eye: bool = absf(player.camera.position.y - 2.2) < 0.0001
	var forward_eye: bool = player.camera.position.z < -0.2 and player.camera.position.z >= -0.25
	var capsule: CapsuleShape3D = player.get_child(0).shape
	var physical_height: bool = absf(capsule.height - 2.4) < 0.0001
	player.camera_pitch = -0.7
	await physics_frame
	var pitch_persists: bool = absf(player.camera.rotation.x + 0.7) < 0.0001
	var first_person_head_hidden: bool = player.camera.cull_mask == 1
	player.camera_pitch = 0
	player.third_person = true
	var third_person_head_shown: bool = player.camera.cull_mask == 3
	var clear_distance: float = player.camera.position.z
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 2, 1.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	for i in range(4):
		await physics_frame
	var blocked_distance: float = player.camera.position.z
	var wall_stops_camera: bool = blocked_distance < 1.1 and blocked_distance > 0.5
	player.camera_orbit_yaw = PI
	await physics_frame
	var orbit_works: bool = player.camera.position.z < -3
	var passed := default_eye and tall_eye and forward_eye and physical_height and pitch_persists and first_person_head_hidden and third_person_head_shown and wall_stops_camera and orbit_works
	print(JSON.stringify({"test": "native_avatar_height_and_camera", "default_eye": default_eye, "tall_eye": tall_eye, "forward_eye_inside_capsule": forward_eye, "capsule_height": physical_height, "pitch_persists": pitch_persists, "first_person_head_hidden": first_person_head_hidden, "third_person_head_shown": third_person_head_shown, "clear_distance": clear_distance, "blocked_distance": blocked_distance, "wall_stops_camera": wall_stops_camera, "orbit_works": orbit_works, "passed": passed}))
	quit(0 if passed else 1)
