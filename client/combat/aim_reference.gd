extends MeshInstance3D
## Fixed 3m optical reference. No raycast, hit marker, lock or center point.
const DISTANCE := 3.0
var world_parent: Node

func _ready() -> void:
	world_parent=get_parent()

func update_head_aim(camera: Camera3D, showing: bool) -> void:
	# A local camera child shares the render/late-latched head pose. Copying a
	# world transform from a physics/render sample can jitter relative to view.
	# No world-space smoothing or lag: hit queries still use this same head axis.
	if get_parent()!=camera: reparent(camera,false)
	transform=Transform3D(Basis.IDENTITY,Vector3(0,0,-DISTANCE))
	visible=showing


func configure(source: Texture2D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18,0.18)
	mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://combat/reticle.gdshader")
	# Optical UI stays legible through scenery and avatars. This affects only
	# presentation; projectile collision and the world-space stereo anchor remain.
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.set_shader_parameter("source_art",source)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

func update_aim(reference: Transform3D, showing: bool) -> void:
	if is_instance_valid(world_parent) and get_parent()!=world_parent: reparent(world_parent,false)
	visible = showing
	if not showing: return
	# Broad artwork with no center mark supplies imprecision, not an off-axis
	# direction: ranged uses the barrel basis; melee uses the tracked head basis.
	var basis := reference.basis.orthonormalized()
	global_transform = Transform3D(basis,reference.origin-basis.z*DISTANCE)
