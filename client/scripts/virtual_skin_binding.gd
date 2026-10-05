extends Node
## Original rare dense MGN weights remain exact through a virtual affine bind.
## AnimationPlayer still owns the skeleton; this node only updates shared Skin.
var avatar: Node3D
var bindings: Array[SwgVirtualSkinBinding] = []
var report := {"valid":false, "virtual_bones":0, "mode":"exact_affine_uniform_residual"}

func configure(source_avatar: Node3D, definitions: Array) -> bool:
	avatar = source_avatar
	process_priority = 100
	var skins := {}
	for mesh: MeshInstance3D in avatar.meshes:
		if mesh.skin != null:
			skins[mesh.skin.get_instance_id()] = mesh.skin
	for skin: Skin in skins.values():
		var binding := SwgVirtualSkinBinding.new()
		if not binding.configure(avatar.skeleton, skin, definitions):
			bindings.clear()
			return false
		bindings.append(binding)
	if bindings.is_empty():
		return false
	update_bindings()
	return bool(report.valid)

func update_bindings() -> void:
	for binding in bindings:
		report = binding.update()

func _process(_delta: float) -> void:
	if not is_instance_valid(avatar):
		return
	if avatar.animation_player != null and not avatar.animation_player.active:
		return
	update_bindings()
