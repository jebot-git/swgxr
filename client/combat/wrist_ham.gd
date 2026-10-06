extends Node3D
## Three small holographic bars; wounds block the right-hand capacity segment.
var pools: RefCounted
var bars: Array[Dictionary] = []
var report: Array = []
var avatar: Node3D
var side := "right"
var mount_frame:=preload("res://scripts/forearm_mount.gd").new()
const WRIST_CLEARANCE := 0.085

func _enter_tree() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func panel(size: Vector2, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)
	return mesh

func _ready() -> void:
	var backing:=panel(Vector2(.17,.065),Color(.72,.78,1.12,1))
	backing.position.z=-.001
	backing.material_override.albedo_texture=preload("res://resources/ui/wenrexa_hologram/panel_wide.png")
	for index in range(3):
		var y := (1 - index) * 0.015
		var background := panel(Vector2(0.10, 0.01), Color(0.04, 0.1, 0.13, 0.65))
		background.position = Vector3(0, y, 0)
		var fill := panel(Vector2(0.10, 0.008), [Color(0.96, 0.3, 0.3, 0.85), Color(0.25, 0.9, 0.4, 0.85), Color(0.3, 0.65, 1, 0.85)][index])
		var blocker := panel(Vector2(0.10, 0.008), Color(0.38, 0.38, 0.43, 0.95))
		var label := Label3D.new(); label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size = 24
		label.pixel_size = 0.0003
		label.outline_size = 2
		label.modulate = Color(0.6, 0.95, 1, 0.8)
		label.position = Vector3(-0.062, y, 0.002)
		label.text = ["H", "A", "M"][index]
		add_child(label)
		var wound_label := Label3D.new(); wound_label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		wound_label.font_size = 20
		wound_label.pixel_size = 0.00025
		wound_label.position = Vector3(0.065, y, 0.002)
		add_child(wound_label)
		bars.append({"fill":fill, "blocker":blocker, "wounds":wound_label, "y":y})

func update_readout(mount: Transform3D, _camera: Vector3, enabled: bool) -> void:
	visible = enabled and pools != null
	if not visible: return
	var skeleton: Skeleton3D=avatar.get("skeleton") if is_instance_valid(avatar) else null
	global_transform=mount_frame.resolve(skeleton,side,mount)
	report = pools.readout()
	for index in range(bars.size()):
		var bar := bars[index]
		var value: Dictionary = report[index]
		bar.fill.visible = value.valid and value.fill > 0
		bar.blocker.visible = value.valid and value.blocker > 0
		bar.fill.scale.x = maxf(0.001, float(value.fill))
		bar.fill.position = Vector3(-0.05 + 0.05 * float(value.fill), bar.y, 0.001)
		bar.blocker.scale.x = maxf(0.001, float(value.blocker))
		bar.blocker.position = Vector3(0.05 - 0.05 * float(value.blocker), bar.y, 0.002)
		bar.wounds.text = "—" if not value.valid else ("−%d" % int(value.wounds) if value.wounds > 0 else "")
