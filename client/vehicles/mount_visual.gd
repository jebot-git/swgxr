extends Node3D
## Original creature body; authoritative ride transform owns locomotion.
const Avatar=preload("res://scripts/avatar.gd")
var avatar:Node3D
var reins:Array=[]
func configure(record:Dictionary,descriptor:Dictionary)->bool:
	avatar=Avatar.new();add_child(avatar)
	avatar.load_catalog(ProjectSettings.globalize_path("res://../"+str(descriptor.avatar_catalog)))
	avatar.configure(str(record.template),{"height":float(record.get("scale",1.0)),"customization":record.get("customization",{})})
	if avatar.meshes.is_empty():return false
	for mesh:MeshInstance3D in avatar.meshes:mesh.layers=1
	avatar.set_process(false)
	var anchor:Array=descriptor.get("rein_anchor",descriptor.seats[0].position)
	var scale_factor:float=float(record.get("scale",1.0))
	var end:=Vector3(anchor[0],anchor[1],anchor[2])*scale_factor
	var material:=StandardMaterial3D.new();material.albedo_color=Color("39291e");material.roughness=1.0
	for side in range(2):
		var point:Array=record.controls[side];var start:=Vector3(point[0],point[1],point[2]);var finish:=end+Vector3(-.12 if side==0 else .12,-.05,0)
		var middle:Vector3=(start+finish)*.5+Vector3.DOWN*.08
		var rein:=Node3D.new();add_child(rein);reins.append(rein)
		for segment in [[start,middle],[middle,finish]]:
			var mesh:=MeshInstance3D.new();var rope:=CylinderMesh.new();rope.top_radius=.007;rope.bottom_radius=.007;rope.radial_segments=5;rope.height=segment[0].distance_to(segment[1]);mesh.mesh=rope;mesh.material_override=material;rein.add_child(mesh)
			mesh.position=(segment[0]+segment[1])*.5
			var direction:Vector3=(segment[1]-segment[0]).normalized();mesh.basis=Basis(Quaternion(Vector3.UP,direction))
	return true
func advance(delta:float,speed:float,held:Dictionary={})->void:
	for side in range(reins.size()):reins[side].visible=bool(held.get("left_held" if side==0 else "right_held",false))
	avatar.update_motion(delta,absf(speed),{"local_velocity":Vector3(0,0,-speed)})
