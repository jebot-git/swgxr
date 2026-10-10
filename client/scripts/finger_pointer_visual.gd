extends Node3D
## UI contact cue only. The mathematical ray is never drawn for the player.
var dot: MeshInstance3D
func _ready() -> void:
	top_level=true
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("a7ffff");material.no_depth_test=true;material.render_priority=120
	dot=MeshInstance3D.new();add_child(dot)
	var sphere:=SphereMesh.new();sphere.radius=.0025;sphere.height=.005;sphere.radial_segments=8;sphere.rings=4
	dot.mesh=sphere;dot.material_override=material
	dot.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()
func update_pointer(_origin: Vector3, hit: Dictionary) -> void:
	visible=not hit.is_empty() and hit.get("world") is Vector3
	if visible:dot.global_position=hit.world
