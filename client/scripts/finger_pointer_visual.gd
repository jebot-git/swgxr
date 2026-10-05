extends Node3D
## A short visible ray starts at the same rendered fingertip used for hit testing.
var beam: MeshInstance3D
var dot: MeshInstance3D
func _ready() -> void:
	top_level=true
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("a7ffff");material.no_depth_test=true;material.render_priority=120
	beam=MeshInstance3D.new();add_child(beam)
	var cylinder:=CylinderMesh.new();cylinder.top_radius=.0007;cylinder.bottom_radius=.0007;cylinder.height=1;cylinder.radial_segments=6
	beam.mesh=cylinder;beam.material_override=material
	dot=MeshInstance3D.new();add_child(dot)
	var sphere:=SphereMesh.new();sphere.radius=.0025;sphere.height=.005;sphere.radial_segments=8;sphere.rings=4
	dot.mesh=sphere;dot.material_override=material
	for mesh in [beam,dot]:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()
func update_pointer(tip: Vector3, hit: Dictionary) -> void:
	visible=not hit.is_empty() and hit.get("world") is Vector3
	if not visible:return
	var end: Vector3=hit.world
	dot.global_position=end
	var difference:=end-tip
	var length:=difference.length()
	beam.visible=length>.003
	if not beam.visible:return
	var y:=difference/length
	var x:=y.cross(Vector3.UP if absf(y.y)<.95 else Vector3.RIGHT).normalized()
	beam.global_transform=Transform3D(Basis(x,y,x.cross(y)).scaled(Vector3(1,length,1)),(tip+end)*.5)
