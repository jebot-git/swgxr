extends RefCounted
## Data-driven, presentation-only equipment. Original source bones own motion.
## Rigid equipment is intentionally separate from the avatar's skinned meshes.
const StageLoader = preload("res://scripts/stage_loader.gd")
const MAX_ATTACHMENTS := 16
const MAX_WARM_MODELS := 32
var loader := StageLoader.new()
var builder := SwgMeshBuilder.new()
var cache := {}
var serial := 0

func source_transform(value) -> Transform3D:
	if not value is Array or value.size()!=12:
		return Transform3D.IDENTITY
	# Source converter emits row-major3x4, already in the client's coordinates.
	var basis := Basis(Vector3(value[0],value[4],value[8]),Vector3(value[1],value[5],value[9]),Vector3(value[2],value[6],value[10]))
	return Transform3D(basis,Vector3(value[3],value[7],value[11]))

func get_model(path: String, directory: String) -> ArrayMesh:
	serial += 1
	if cache.has(path):
		cache[path].used = serial
		return cache[path].mesh
	if not FileAccess.file_exists(path): return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return null
	var surfaces: Array = data.get("surfaces",[])
	var mesh := builder.create_mesh(surfaces)
	if mesh==null: return null
	for index in range(mesh.get_surface_count()):
		mesh.surface_set_material(index,loader.make_material(surfaces[index],directory))
	cache[path] = {"mesh":mesh,"refs":0,"used":serial}
	return mesh

func attach(actor: Node3D, descriptors: Array, directory: String, indoor: bool) -> Dictionary:
	var result := {"items":[],"failures":[],"requested":descriptors.size()}
	var skeleton: Skeleton3D = actor.skeleton
	if skeleton==null:
		result.failures.append({"error":"Equipment target has no source skeleton"})
		return result
	for index in range(descriptors.size()):
		var source: Dictionary = descriptors[index]
		var failure := {"template":source.get("template",""),"source_slot":source.get("source_slot",""),"error":""}
		if index>=MAX_ATTACHMENTS:
			failure.error = "Per-NPC rigid attachment limit exceeded"
		elif str(source.get("bone","")).is_empty() or skeleton.find_bone(str(source.bone))<0:
			failure.error = "Original equipment attachment bone is unavailable: "+str(source.get("bone",""))
		elif str(source.get("local_transform_layout","row_major_3x4"))!="row_major_3x4" or not source.get("local_transform",[]) is Array or source.get("local_transform",[]).size()!=12:
			failure.error = "Equipment attachment transform is missing or unsupported"
		if not str(failure.error).is_empty():
			result.failures.append(failure)
			continue
		var local := source_transform(source.local_transform)
		if not local.origin.is_finite() or not local.basis.is_finite() or absf(local.basis.determinant())<0.000001:
			failure.error = "Equipment attachment transform is invalid"
			result.failures.append(failure)
			continue
		var path := str(source.get("model",""))
		if not path.is_absolute_path(): path=directory.path_join(path)
		var mesh := get_model(path,directory)
		if mesh==null:
			failure.error = "Original rigid equipment mesh is unavailable: "+path
			result.failures.append(failure)
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "SourceEquipment_%d" % index
		attachment.bone_name = str(source.bone)
		attachment.override_pose = false
		skeleton.add_child(attachment)
		var instance := MeshInstance3D.new()
		instance.name = str(source.get("template","Equipment")).get_file().get_basename()
		instance.mesh = mesh
		instance.transform = local
		instance.layers = 1
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_instance_shader_parameter("swg_indoor",1.0 if indoor else 0.0)
		instance.set_meta("scope","rigid_equipment")
		instance.set_meta("source_equipment",source)
		attachment.add_child(instance)
		cache[path].refs += 1
		result.items.append({"attachment":attachment,"instance":instance,"source":source,"model_path":path,"bone_index":skeleton.find_bone(str(source.bone)),"local_transform":local})
	trim_cache()
	return result

func release(items: Array) -> void:
	for item: Dictionary in items:
		var path := str(item.get("model_path",""))
		if cache.has(path): cache[path].refs=maxi(0,int(cache[path].refs)-1)
		if is_instance_valid(item.get("attachment")): item.attachment.queue_free()
	trim_cache()

func trim_cache() -> void:
	var unused: Array = []
	for path: String in cache:
		if cache[path].refs<=0: unused.append(path)
	unused.sort_custom(func(a,b): return cache[a].used<cache[b].used)
	while unused.size()>MAX_WARM_MODELS:
		cache.erase(unused.pop_front())
		# Materials retain textures; this lookup must not pin evicted models.
		loader.textures.clear()

func statistics() -> Dictionary:
	var references := 0
	var warm := 0
	for entry: Dictionary in cache.values():
		references += int(entry.refs)
		if entry.refs<=0: warm += 1
	return {"cached_models":cache.size(),"attached_items":references,"warm_models":warm,"max_warm_models":MAX_WARM_MODELS,"max_attachments_per_npc":MAX_ATTACHMENTS,"attachment_driver":"source skeleton BoneAttachment3D; override_pose=false","gameplay_colliders":0}
