extends SceneTree

var checks := 0
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
		push_error(label)
func triangle(id: int, indices: Array, neighbors: Array, flags: Array) -> Dictionary:
	return {"id": id, "indices": indices, "neighbors": neighbors, "edge_flags": flags, "portal_ids": [-1,-1,-1]}
func run() -> void:
	# The tall sloping island has an infinite plane through the feet, but its
	# finite geometry is above the walking capsule throughout the test path.
	var cell := {"is_exterior": true, "floor_vertices": [
		-2,0,-2, 2,0,-2, 2,0,2, -2,0,2,
		1,3,-1, 1,3,1, -2,-6,10], "floor_triangles": [
		triangle(0,[0,1,2],[-1,-1,1],[1,1,1]),
		triangle(1,[0,2,3],[0,-1,-1],[1,1,1]),
		triangle(2,[4,5,6],[-1,-1,-1],[0,1,1])]}
	var support := SwgGroundSupport.new()
	check(support.configure([{"cells":{"floor":cell}}]), "Original floor graph configures")
	var start := Vector3.ZERO
	var motion := Vector3(1.1,0,0)
	var found := support.sample_support(start,["floor"],.1,.1)
	check(found.valid and int(found.tri_id) != 2, "Feet attach to low finite floor, not extrapolated overhead plane")
	var guard := support.constrain_motion(start,motion,["floor"],.22)
	check(not guard.blocked and Vector3(guard.motion).is_equal_approx(motion), "Disconnected overhead floor does not invent a lateral walking wall")
	var physical := StaticBody3D.new()
	physical.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = SwgCollisionBuilder.new().build_floor(cell)
	physical.add_child(floor_shape)
	root.add_child(physical)
	var player := CharacterBody3D.new()
	player.collision_layer = 0
	player.collision_mask = 1
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .22
	var body_shape := CollisionShape3D.new()
	body_shape.shape = capsule
	player.add_child(body_shape)
	root.add_child(player)
	await physics_frame
	await physics_frame
	check(not player.test_move(Transform3D(Basis.IDENTITY,Vector3(0,.87,0)),motion), "Actual finite floor geometry clears the same walking capsule path")
	player.queue_free()
	physical.queue_free()
	await process_frame
	# A real edge across the reachable neighboring triangle must still stop
	# the radius before the center leaves the floor.
	var closed: Dictionary = cell.duplicate(true)
	closed.floor_triangles.resize(2)
	closed.floor_triangles[0].edge_flags[1] = 0
	support.configure([{"cells":{"floor":closed}}])
	var boundary := support.constrain_motion(Vector3(-1,0,1),Vector3(4,0,0),["floor"],.22)
	check(boundary.blocked and absf(float(boundary.motion.x)-2.78)<.001, "Swept footprint follows open adjacency and retains reached closed boundary")
	check(int(boundary.get("tri_id",-1))==0, "Real boundary belongs to the reached neighboring source triangle")
	var air := support.constrain_motion(Vector3(-1,3,1),Vector3(4,0,0),["floor"],.22)
	check(not air.blocked, "Unattached airborne motion is not constrained by distant floor edges")
	closed.floor_triangles[0].portal_ids[1] = 0
	support.configure([{"cells":{"floor":closed}}])
	check(not support.constrain_motion(Vector3(-1,0,1),Vector3(4,0,0),["floor"],.22).blocked, "Explicit portal retains its override of closed edge flag")
	# A persisted floor locator must not jump to a disconnected island merely
	# because that island overlaps X/Z and lies within the hop tolerance.
	var islands: Dictionary = cell.duplicate(true)
	islands.floor_vertices.resize(12)
	islands.floor_vertices.append_array([-.5,.2,-.5, .5,.2,-.5, .5,.2,.5, -.5,.2,.5])
	islands.floor_triangles.resize(2)
	islands.floor_triangles.append(triangle(2,[4,5,6],[-1,-1,3],[1,1,1]))
	islands.floor_triangles.append(triangle(3,[4,6,7],[2,-1,-1],[1,1,1]))
	support.configure([{"cells":{"floor":islands}}])
	var previous := support.sample_support(Vector3(-1,0,0),["floor"],.35,.35)
	var retained := support.sample_support(Vector3.ZERO,["floor"],.35,.35,previous)
	check(retained.valid and absf(float(retained.height))<.00001, "Persistent locator remains on its connected low floor under overlapping island")
	var capsule_args := 0
	for method: Dictionary in support.get_method_list():
		if method.name == "capsule_support": capsule_args = method.args.size()
	check(capsule_args == 6, "Native capsule support accepts authoritative attached-floor context")
	var retained_capsule: Dictionary
	if capsule_args == 6:
		retained_capsule = support.call("capsule_support",Vector3.ZERO,.22,["floor"],.35,.35,retained)
	else:
		retained_capsule = support.capsule_support(Vector3.ZERO,.22,["floor"],.35,.35)
	check(retained_capsule.valid and absf(float(retained_capsule.body_height))<.00001, "Capsule tangent support cannot independently lift onto disconnected island")
	var fresh := support.sample_support(Vector3(0,.25,0),["floor"],.1,.3)
	check(fresh.valid and absf(float(fresh.height)-.2)<.00001, "Fresh bounded reacquisition can land on the upper island")
	# A real connected seam remains traversable; closing that exact seam
	# prevents silently reattaching across it while the previous locator lives.
	var seam := {"floor_vertices":[-2,0,-1, 0,0,-1, 0,0,1, -2,0,1,
		0,.1,-1, 2,.1,-1, 0,.1,1, 2,.1,1],"floor_triangles":[
		triangle(0,[0,1,2],[-1,2,1],[1,1,1]), triangle(1,[0,2,3],[0,-1,-1],[1,1,1]),
		triangle(2,[4,5,6],[-1,3,0],[1,1,1]), triangle(3,[5,7,6],[-1,-1,2],[1,1,1])]}
	support.configure([{"cells":{"floor":seam}}])
	previous = support.sample_support(Vector3(-1,0,0),["floor"],.35,.35)
	var crossed := support.sample_support(Vector3(1,.1,0),["floor"],.35,.35,previous)
	check(crossed.valid and absf(float(crossed.height)-.1)<.00001, "Retained locator traverses an actual open neighboring floor seam")
	seam.floor_triangles[0].edge_flags[1] = 0
	support.configure([{"cells":{"floor":seam}}])
	check(not support.sample_support(Vector3(1,.1,0),["floor"],.35,.35,previous).valid, "Closed source seam cannot silently acquire an unreachable neighboring triangle")
	check(support.sample_support(Vector3(1,.1,0),["floor"],.35,.35).valid, "Reset locator still supports explicit teleport or fresh spawn reacquisition")
	var report := {"passed": errors.is_empty(), "checks":checks,"errors":errors,"finite_geometry_clearance":true,
		"unrelated_overhead_result":guard,"native_physics":true,"hardware_tested":false,"renderer":"dummy"}
	FileAccess.open("res://../runtime/evidence/source-floor-attachment-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
