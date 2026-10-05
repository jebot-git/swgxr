extends RefCounted
## Positional grab zones follow room-scale head translation and headset facing yaw.
## Pitch/roll and animated bones never rotate the activation volumes.
static func at(head: Node3D, rig: Node3D, offset: Vector3) -> Transform3D:
	if not is_instance_valid(head) or not is_instance_valid(rig): return Transform3D.IDENTITY
	return from_pose(head.global_transform,rig.global_transform,offset)
static func from_pose(head: Transform3D, rig: Transform3D, offset: Vector3) -> Transform3D:
	var forward:=(-head.basis.z).slide(Vector3.UP)
	# At the vertical poles the headset has no meaningful projected facing.
	if forward.length_squared()<0.0001: forward=(-rig.basis.z).slide(Vector3.UP)
	if forward.length_squared()<0.0001: forward=Vector3.FORWARD
	forward=forward.normalized()
	var yaw:=Basis.looking_at(forward,Vector3.UP)
	return Transform3D(Basis.IDENTITY,head.origin+yaw*offset)
static func hip(head: Node3D, rig: Node3D, side: String) -> Transform3D:
	return at(head,rig,Vector3(-0.22 if side=="left" else 0.22,-0.75,0))
static func shoulder(head: Node3D, rig: Node3D, side: String) -> Transform3D:
	return at(head,rig,Vector3(-0.22 if side=="left" else 0.22,-0.20,0.15))
static func back(head: Node3D, rig: Node3D) -> Transform3D:
	return at(head,rig,Vector3(0,-0.50,0.25))
