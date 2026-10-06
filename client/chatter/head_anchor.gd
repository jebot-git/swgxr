extends RefCounted
## Source head geometry, cached per actual skeleton; no guessed character height.
static func crown(actor:Node3D)->Variant:
	if not is_instance_valid(actor) or not is_instance_valid(actor.get("visual")):return null
	var avatar:Node3D=actor.visual;var skeleton:Skeleton3D=avatar.get("skeleton")
	if not is_instance_valid(skeleton):return null
	var signature:Array=[skeleton.get_instance_id()]
	# Asset attachment/replacement can finish after the Skeleton3D exists. Inspect
	# only identities here; source vertex scans happen once per completed layout.
	for part:MeshInstance3D in avatar.get("meshes"):
		if not is_instance_valid(part):continue
		signature.append([part.get_instance_id(),part.mesh.get_instance_id() if is_instance_valid(part.mesh) else 0,part.mesh.get_surface_count() if is_instance_valid(part.mesh) else 0])
	var descriptor:Dictionary=actor.get_meta("speech_head",{})
	if descriptor.get("signature",[])!=signature:
		descriptor=describe(avatar,skeleton);descriptor.signature=signature;actor.set_meta("speech_head",descriptor)
	if int(descriptor.get("bone",-1))<0 or not descriptor.get("valid",false):return null
	return skeleton.global_transform*skeleton.get_bone_global_pose(int(descriptor.bone))*descriptor.local_crown
static func describe(avatar:Node3D,skeleton:Skeleton3D)->Dictionary:
	var result:Dictionary={"skeleton_id":skeleton.get_instance_id(),"bone":-1,"valid":false}
	for name in ["head","head_base","fambaa_head"]:
		result.bone=skeleton.find_bone(name)
		if result.bone>=0:break
	if result.bone<0:return result
	var family:Dictionary={}
	for bone in range(skeleton.get_bone_count()):
		var ancestor:=bone
		while ancestor>=0:
			if ancestor==int(result.bone):family[bone]=true;break
			ancestor=skeleton.get_bone_parent(ancestor)
	var split:bool=avatar.get("meshes").any(func(part):return is_instance_valid(part) and part.get_meta("head_part",false))
	var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF);var count:=0
	for part:MeshInstance3D in avatar.get("meshes"):
		if not is_instance_valid(part) or not is_instance_valid(part.mesh) or (split and not part.get_meta("head_part",false)):continue
		for surface in range(part.mesh.get_surface_count()):
			var arrays:=part.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones:Variant=arrays[Mesh.ARRAY_BONES];var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
			var stride:int=bones.size()/vertices.size() if bones!=null and not vertices.is_empty() else 0
			for i in range(vertices.size()):
				var accepted:bool=part.get_meta("head_part",false)
				if not accepted and stride>0 and weights!=null:
					var influence:=0.0
					for j in range(stride):
						if family.has(int(bones[i*stride+j])):influence+=float(weights[i*stride+j])
					accepted=influence>=.5
				if accepted:
					var point:Vector3=part.transform*vertices[i];low=low.min(point);high=high.max(point);count+=1
	if count==0:return result
	var bind_crown:=Vector3((low.x+high.x)*.5,high.y,(low.z+high.z)*.5)
	result.local_crown=skeleton.get_bone_global_rest(int(result.bone)).affine_inverse()*bind_crown;result.valid=true;result.vertices=count;result.source="original_head_mesh_bounds"
	return result
