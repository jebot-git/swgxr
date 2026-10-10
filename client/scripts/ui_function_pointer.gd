extends XRToolsFunctionPointer
## Use the same aim as datapad, inventory, terminals and wrist controls.
func _process(delta: float) -> void:
	var controller:=XRHelpers.get_xr_controller(self)
	var rig:=XRHelpers.get_xr_origin(self)
	var pointer:=preload("res://scripts/rendered_finger_pointer.gd").pose(null,"",rig,controller)
	if not pointer.is_empty():
		var direction:Vector3=pointer.direction
		var up:=controller.global_basis.y
		if absf(direction.dot(up))>.99:up=controller.global_basis.x
		global_transform=Transform3D(Basis.looking_at(direction,up),pointer.ray_origin)
	super._process(delta)
