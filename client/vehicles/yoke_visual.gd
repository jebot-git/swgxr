extends RefCounted
## Split only audited complete original components; source hull and materials
## stay shared and unchanged. All six supported vehicle keys bound this cache.
var cache:Dictionary={}
func meshes(template:String, mesh:ArrayMesh, descriptor:Dictionary)->Dictionary:
	if cache.has(template):return cache[template]
	var geometry:Dictionary=descriptor.get("steering_geometry",{})
	if geometry.get("status","")!="ready":return {}
	var surface:int=geometry.surface
	if surface<0 or surface>=mesh.get_surface_count():return {}
	var selected:Dictionary={}
	for triangle in geometry.triangles:selected[int(triangle)]=true
	var body:=ArrayMesh.new();var yoke:=ArrayMesh.new()
	for index in range(mesh.get_surface_count()):
		var arrays:Array=mesh.surface_get_arrays(index)
		if index!=surface:
			body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			body.surface_set_material(body.get_surface_count()-1,mesh.surface_get_material(index))
			continue
		var source:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var remaining:=PackedInt32Array();var steering:=PackedInt32Array()
		for triangle in range(source.size()/3):
			for corner in range(3):
				if selected.has(triangle):steering.append(source[triangle*3+corner])
				else:remaining.append(source[triangle*3+corner])
		if steering.size()!=selected.size()*3:return {}
		var part:=arrays.duplicate();part[Mesh.ARRAY_INDEX]=steering
		yoke.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,part);yoke.surface_set_material(0,mesh.surface_get_material(index))
		if not remaining.is_empty():
			arrays[Mesh.ARRAY_INDEX]=remaining;body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			body.surface_set_material(body.get_surface_count()-1,mesh.surface_get_material(index))
	var result:Dictionary={"body":body,"yoke":yoke,"triangles":selected.size()}
	if cache.size()<6:cache[template]=result
	return result
