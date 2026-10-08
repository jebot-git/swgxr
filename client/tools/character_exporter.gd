extends Node
const Avatar=preload("res://scripts/avatar.gd")
const Materials=preload("res://tools/avatar_export_materials.gd")
var errors:Array=[]
var report:Dictionary={}
var materials=Materials.new()
func fail(message:String)->Dictionary:
	errors.append(message);report.ok=false;report.errors=errors.duplicate();return report
func vector(value:Vector3)->Array:return [value.x,value.y,value.z]
func transform(value:Transform3D)->Dictionary:
	var q:=value.basis.get_rotation_quaternion()
	return {"translation":vector(value.origin),"rotation":[q.x,q.y,q.z,q.w],"scale":vector(value.basis.get_scale())}
func align(skeleton:Skeleton3D,bone:String,tip:String,target:Vector3)->bool:
	var index:=skeleton.find_bone(bone);var end:=skeleton.find_bone(tip)
	if index<0 or end<0:return false
	var start:=skeleton.get_bone_global_rest(index);var direction:=(skeleton.get_bone_global_rest(end).origin-start.origin).normalized()
	if direction.length_squared()<.5:return false
	var correction:=Basis(Quaternion(direction,target))
	var desired:=Transform3D(correction*start.basis,start.origin)
	var parent:=skeleton.get_bone_parent(index)
	skeleton.set_bone_rest(index,(skeleton.get_bone_global_rest(parent).affine_inverse() if parent>=0 else Transform3D.IDENTITY)*desired)
	return true
func export_character(envelope:Dictionary,output:String)->Dictionary:
	errors=[];materials=Materials.new();report={"ok":false,"errors":[],"renderer":"headless dummy","native_export":true,"format":"glTF2 intermediate","pose_policy":"customized geometry baked into rebound T-pose; no animations or tracking","forward":"+Z through explicit 180 degree Y root rotation","environment_lighting":"scene tint excluded; authored/client vertex colors retained","materials":[],"bones":[],"equipment":[]}
	var character:Dictionary=envelope.get("character",{})
	var appearance:Dictionary=character.get("appearance",{}).duplicate(true)
	if character.is_empty() or appearance.is_empty():return fail("Snapshot must contain character.appearance from the native character endpoint")
	if not appearance.has("customization") or not appearance.has("height") or not appearance.has("hair"):return fail("Snapshot lacks explicit customization, height or hair state")
	var equipment=character.get("equipment",appearance.get("equipment"))
	if not equipment is Array:return fail("Snapshot must contain an explicit authoritative equipment array")
	if appearance.has("equipment") and character.has("equipment") and appearance.equipment!=character.equipment:return fail("Snapshot equipment arrays disagree")
	var race:=str(appearance.get("race",character.get("race","")))
	if race.begins_with("object/"):race=race.get_file().trim_suffix(".iff").trim_prefix("shared_")
	if race.is_empty():return fail("Snapshot has no explicit character race")
	var height:=float(appearance.height)
	if not is_finite(height) or height<=0:return fail("Character height must be positive and finite")
	var hair=appearance.hair
	if hair is Dictionary:
		appearance.hair_template=str(hair.get("template",""));appearance.hair_customization=hair.get("customization",{})
		if appearance.hair_template.is_empty():return fail("Hair object lacks a source template")
	elif hair!=null:return fail("Hair must be a native object or explicit null")
	var avatar:=Avatar.new();add_child(avatar);avatar.set_process(false);avatar.set_physics_process(false);avatar.load_catalog()
	if not str(appearance.get("hair_template","")).is_empty():
		var matches:Array=avatar.catalog.get("races",{}).get(race,{}).get("hair",[]).filter(func(row):return appearance.hair_template in [row.get("template",""),row.get("shared_template","")])
		if matches.is_empty():return fail("Requested original hairstyle is not locally prepared: "+appearance.hair_template)
		var model:Dictionary=avatar.get_model(str(matches[0].get("model",matches[0].get("path",""))))
		if model.get("parts",[]).is_empty():return fail("Requested original hairstyle has no prepared geometry")
	var normalized:Array=equipment.duplicate(true)
	var intrinsic:Array=[]
	for item:Dictionary in normalized:
		if str(item.get("template","")) in ["object/weapon/melee/unarmed/unarmed_default_player.iff","object/weapon/melee/unarmed/shared_unarmed_default_player.iff"]:
			item.equipped_slots=["default_weapon"];intrinsic.append(str(item.get("id","")))
	var configured:Dictionary=avatar.configure(race,appearance,normalized)
	if not str(configured.get("error","")).is_empty():return fail(str(configured.error))
	if not configured.get("equipment_complete",false):report.equipment_failures=configured.get("equipment_failures",[]);return fail("Incomplete equipped appearance; export refused")
	report.character={"id":str(character.get("id","")),"name":str(character.get("name","")),"race":race};report.equipment=equipment.duplicate(true);report.intrinsic_nonvisual_equipment=intrinsic
	avatar.set_tracking_mode(true)
	for node in avatar.find_children("*","AnimationPlayer",true,false):node.get_parent().remove_child(node);node.free()
	var skeleton:Skeleton3D=avatar.skeleton
	skeleton.clear_bones_global_pose_override();skeleton.reset_bone_poses()
	var original:Array=[]
	for index in range(skeleton.get_bone_count()):original.append(skeleton.get_bone_global_rest(index))
	for side in ["l","r"]:
		var target:=Vector3.LEFT if side=="l" else Vector3.RIGHT
		if not align(skeleton,side+"arm",side+"forearm",target) or not align(skeleton,side+"forearm",side+"ulna",target) or not align(skeleton,side+"ulna",side+"wrist",target):return fail("Original rig cannot be rebound to the supported humanoid T-pose")
	var deltas:Array=[];var skin:=Skin.new()
	for index in range(skeleton.get_bone_count()):
		var rest:=skeleton.get_bone_global_rest(index);deltas.append(rest*Transform3D(original[index]).affine_inverse());skin.add_bind(index,rest.affine_inverse())
		report.bones.append({"name":skeleton.get_bone_name(index),"parent":skeleton.get_bone_parent(index),"source_global_rest":transform(original[index]),"global_rest":transform(rest)})
	skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()
	var exported_meshes:=0;var vertices:=0;var morphs:=0
	for instance:MeshInstance3D in avatar.meshes:
		var mesh:=ArrayMesh.new()
		for surface in range(instance.mesh.get_surface_count()):
			var arrays:Array=instance.mesh.surface_get_arrays(surface).duplicate(true)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var blends:Array=instance.mesh.surface_get_blend_shape_arrays(surface)
			for blend in range(blends.size()):
				var weight:=instance.get_blend_shape_value(blend)
				if is_zero_approx(weight):continue
				morphs+=1;var positions:PackedVector3Array=blends[blend][Mesh.ARRAY_VERTEX];var normal_deltas:PackedVector3Array=blends[blend][Mesh.ARRAY_NORMAL]
				for vertex in range(points.size()):points[vertex]+=positions[vertex]*weight;if normals.size()>vertex and normal_deltas.size()>vertex:normals[vertex]+=normal_deltas[vertex]*weight
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var influences:=weights.size()/points.size()
			if influences not in [4,8] or bones.size()!=weights.size():return fail("Unsupported skin weights on "+instance.name)
			for vertex in range(points.size()):
				var point:=Vector3.ZERO;var normal:=Vector3.ZERO;var total:=0.0
				for influence in range(influences):
					var weight:=weights[vertex*influences+influence];var bone:=bones[vertex*influences+influence]
					if weight<=0:continue
					if bone<0 or bone>=deltas.size():return fail("Skin weight references a missing bone")
					point+=Transform3D(deltas[bone])*points[vertex]*weight
					if normals.size()>vertex:normal+=Transform3D(deltas[bone]).basis*normals[vertex]*weight
					total+=weight
				if absf(total-1)>.01:return fail("Unnormalized original skin weights")
				points[vertex]=point
				if normals.size()>vertex:normals[vertex]=normal.normalized()
			arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TANGENT]=null
			var material:=materials.convert(instance.get_active_material(surface))
			if material==null or not materials.failures.is_empty():report.material_failures=materials.failures;return fail("Cannot faithfully convert original avatar material")
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if influences==8 else 0);mesh.surface_set_material(surface,material);vertices+=points.size()
		instance.mesh=mesh;instance.skin=skin;instance.layers=1;instance.show();exported_meshes+=1
	for item:Dictionary in avatar.rigid_equipment:
		var original_instance:MeshInstance3D=item.instance;var bone:int=item.bone_index
		var worn:Array=normalized.filter(func(row):return str(row.get("id",""))==str(original_instance.get_meta("equipment_id","")))
		if not worn.is_empty() and not worn[0].get("customization",{}).is_empty():return fail("Rigid equipment carries customization not supported by the client's static material path")
		var source_data:Dictionary=Avatar.read_json(item.model_path);materials.validate_paths(source_data,item.model_path.get_base_dir().get_base_dir())
		var mesh:=ArrayMesh.new();var placement:Transform3D=skeleton.get_bone_global_rest(bone)*Transform3D(item.local_transform)
		for surface in range(original_instance.mesh.get_surface_count()):
			var arrays:Array=original_instance.mesh.surface_get_arrays(surface).duplicate(true)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var bones:=PackedInt32Array();var weights:=PackedFloat32Array();bones.resize(points.size()*4);weights.resize(points.size()*4)
			for vertex in range(points.size()):
				points[vertex]=placement*points[vertex]
				if normals.size()>vertex:normals[vertex]=(placement.basis*normals[vertex]).normalized()
				bones[vertex*4]=bone;weights[vertex*4]=1
			arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights;arrays[Mesh.ARRAY_TANGENT]=null
			var material:=materials.convert(original_instance.get_active_material(surface))
			if material==null or not materials.failures.is_empty():report.material_failures=materials.failures;return fail("Cannot faithfully convert original rigid equipment material")
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(surface,material);vertices+=points.size()
		var instance:=MeshInstance3D.new();instance.name=original_instance.name;instance.mesh=mesh;instance.skin=skin;instance.skeleton=NodePath("..");skeleton.add_child(instance)
		item.attachment.get_parent().remove_child(item.attachment);item.attachment.free();exported_meshes+=1
	var export_root:=Node3D.new();export_root.name="CharacterExport";add_child(export_root);export_root.rotation.y=PI
	avatar.visual_root.reparent(export_root,false)
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var status:=document.append_from_scene(export_root,state)
	if status!=OK:return fail("Godot GLTF scene export failed: "+error_string(status))
	status=document.write_to_filesystem(state,output)
	if status!=OK:return fail("Godot GLTF write failed: "+error_string(status))
	var bytes:=FileAccess.get_file_as_bytes(output)
	if bytes.size()<20:return fail("Godot wrote an empty GLB")
	var gltf:Dictionary=JSON.parse_string(bytes.slice(20,20+bytes.decode_u32(12)).get_string_from_utf8())
	var nodes:Array=gltf.get("nodes",[]);var lookup:Dictionary={}
	for index in range(nodes.size()):lookup[str(nodes[index].get("name",""))]=index
	for bone:Dictionary in report.bones:
		bone.gltf_node=lookup.get(bone.name,-1)
		if bone.gltf_node<0:return fail("Exported skeleton lost bone name: "+bone.name)
	if gltf.get("skins",[]).is_empty() or not gltf.get("animations",[]).is_empty():return fail("Export does not contain a static skinned avatar")
	report.validated_assets=materials.provenance.duplicate()
	for path:String in Avatar.model_cache:
		if FileAccess.file_exists(path):report.validated_assets[path]=FileAccess.get_sha256(path)
	for item:Dictionary in avatar.rigid_equipment:
		if FileAccess.file_exists(item.model_path):report.validated_assets[item.model_path]=FileAccess.get_sha256(item.model_path)
	report.ok=true;report.materials=materials.evidence;report.meshes=exported_meshes;report.vertices=vertices;report.morph_applications=morphs;report.height_meters=avatar.height_meters;report.output_sha256=FileAccess.get_sha256(output)
	return report
