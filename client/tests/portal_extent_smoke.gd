extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	# Deliberately closed coarse wall, an adjacent perpendicular wall, and floor.
	var vertices := [0,0,-4,0,0,4,0,4,4,0,4,-4, -3,0,-4,-3,0,4, -3,4,-4]
	var definition := {"type":"mesh","vertices":vertices,"indices":[0,1,2,0,2,3, 4,0,3,4,3,6, 4,5,1,4,1,0]}
	var portal := {"passable":true,"vertices":[0,0,-1,0,3,-1,0,3,1,0,0,1]}
	var shapes: Array = SwgCollisionBuilder.new().build_cell_extent(definition,[portal])
	var body := StaticBody3D.new();body.collision_layer=1
	for item: Dictionary in shapes:
		var child := CollisionShape3D.new();child.shape=item.shape;child.transform=item.transform;body.add_child(child)
	root.add_child(body)
	await physics_frame;await physics_frame
	var space := body.get_world_3d().direct_space_state
	var errors: Array[String] = []
	for sample in [{"point":Vector3(0,1.5,0),"blocked":false,"label":"open aperture"},{"point":Vector3(0,1.5,1.2),"blocked":true,"label":"side jamb"},{"point":Vector3(0,3.2,0),"blocked":true,"label":"lintel"},{"point":Vector3(0,1.5,-3),"blocked":true,"label":"remote shell"}]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(sample.point+Vector3.LEFT,sample.point+Vector3.RIGHT,1))
		if not hit.is_empty()!=sample.blocked:errors.append(sample.label)
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-0.2,1,0),Vector3(-0.2,-1,0),1))
	if floor_hit.is_empty():errors.append("authored floor removed")
	var adjacent := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1,1,-3),Vector3(-1,1,-5),1))
	if adjacent.is_empty():errors.append("perpendicular wall removed")
	var report := {"passed":errors.is_empty(),"errors":errors,"test":"finite_portal_extent_aperture_preserves_shell_and_floor"}
	FileAccess.open("res://../runtime/evidence/portal-extent-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));body.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
