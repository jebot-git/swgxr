extends MeshInstance3D
## Ground-following perimeter at the native stimpack's AoE center and radius.
const SEGMENTS := 96
var center := Vector3(INF,INF,INF)
var radius := -1.0
var until_refresh := 0.0
func _ready() -> void:
	mesh=ImmediateMesh.new();cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.albedo_color=Color(0.2,0.82,0.7,0.28)
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED;material_override=mat;visible=false
func update_circle(point: Vector3, meters: float, showing: bool, delta: float) -> void:
	visible=showing and point.is_finite() and is_finite(meters) and meters>0 and meters<=128
	if not visible:return
	until_refresh-=delta
	if until_refresh>0 and is_equal_approx(radius,meters) and center.distance_to(point)<0.08:return
	until_refresh=0.1;center=point;radius=meters
	var lines:=mesh as ImmediateMesh;lines.clear_surfaces()
	var points: Array=[]
	for i in range(SEGMENTS+1):
		var angle:=TAU*i/SEGMENTS;var p:=center+Vector3(cos(angle),0,sin(angle))*radius
		var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.5,p-Vector3.UP*2.5,7))
		points.append(Vector3(hit.position)+Vector3.UP*0.025 if not hit.is_empty() and Vector3(hit.normal).y>0.45 else null)
	var vertices:=PackedVector3Array()
	for i in range(SEGMENTS):
		if points[i]==null or points[i+1]==null:continue
		var a: Vector3=points[i];var b: Vector3=points[i+1]
		if absf(a.y-b.y)>0.4:continue # Do not bridge unsupported ledges.
		var width: Vector3=(b-a).normalized().cross(Vector3.UP)*0.012
		for v in [a-width,a+width,b+width,a-width,b+width,b-width]:vertices.append(to_local(v))
	if vertices.is_empty():visible=false;return
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in vertices:lines.surface_add_vertex(v)
	lines.surface_end()
