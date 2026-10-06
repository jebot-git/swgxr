extends RefCounted
## Original item meshes, shared across slots/preview/temporary hand presentation.
const AvatarMaterials = preload("res://scripts/avatar_materials.gd")
const StageLoader = preload("res://scripts/stage_loader.gd")
const MAX_MODELS := 64
var directory := ""
var catalog: Dictionary = {}
var cache: Dictionary = {}
var serial := 0
var loader := StageLoader.new()
var builder := SwgMeshBuilder.new()

func configure(path := "") -> void:
	if path.is_empty(): path=ProjectSettings.globalize_path("res://../runtime/assets/inventory/catalog.json")
	directory=path.get_base_dir()
	if FileAccess.file_exists(path):
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: catalog=parsed

func descriptor(template: String) -> Dictionary:
	var key: String=str(catalog.get("aliases",{}).get(template,template))
	return catalog.get("items",{}).get(key,{})

func backpack_template(equipped: Dictionary) -> String:
	var actual:=str(equipped.get("template",equipped.get("shared_template","")))
	if not actual.is_empty(): return actual
	return str(catalog.get("generic_backpack",{}).get("template",""))

func model(template: String, customization: Dictionary = {}) -> ArrayMesh:
	var source:=descriptor(template)
	if source.get("status","")!="ready": return null
	var relative:=str(source.get("model",""))
	if relative.is_empty(): return null
	var path:=directory.path_join(relative)
	var key:=path+JSON.stringify(customization)
	serial+=1
	if cache.has(key):
		cache[key].used=serial
		return cache[key].mesh
	if not FileAccess.file_exists(path): return null
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return null
	var surfaces: Array=data.get("surfaces",[])
	var mesh: ArrayMesh=builder.create_avatar_mesh(data) if not data.get("blend_shapes",[]).is_empty() else builder.create_mesh(surfaces)
	if mesh==null: return null
	for i in range(mesh.get_surface_count()):
		if str(data.get("material_pipeline",source.get("material_pipeline","")))=="original_character":
			var character_material:=AvatarMaterials.create(surfaces[i],directory)
			AvatarMaterials.apply(character_material,customization)
			mesh.surface_set_material(i,character_material)
			continue
		# Source textures and alpha behavior, without scene lighting/shadows in UI.
		var source_material:=loader.make_material(surfaces[i],directory)
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=source_material.get_shader_parameter("albedo_color")
		material.albedo_texture=source_material.get_shader_parameter("albedo_texture")
		if bool(surfaces[i].get("alpha",false)):
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mesh.surface_set_material(i,material)
	cache[key]={"mesh":mesh,"used":serial}
	while cache.size()>MAX_MODELS:
		var oldest: String=cache.keys()[0]
		for entry_key: String in cache:
			if int(cache[entry_key].used)<int(cache[oldest].used): oldest=entry_key
		cache.erase(oldest)
		loader.textures.clear() # Mesh materials retain live textures; no unbounded lookup pins.
	return mesh

static func apply_morphs(node:MeshInstance3D,customization:Dictionary)->void:
	for i in range(node.mesh.get_blend_shape_count()):
		var name:=str(node.mesh.get_blend_shape_name(i))
		var value:=0.0
		for key in customization:
			if str(key).get_file()==name.get_file():value=float(customization[key])/255.0;break
		node.set_blend_shape_value(i,clampf(value,0,1))

func instance(template: String, max_extent: float, customization: Dictionary = {}) -> MeshInstance3D:
	var mesh:=model(template,customization)
	if mesh==null: return null
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	apply_morphs(node,customization)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bounds:=mesh.get_aabb()
	var extent:=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
	var scale_factor:=max_extent/maxf(extent,0.001)
	node.scale=Vector3.ONE*scale_factor
	node.position=-bounds.get_center()*scale_factor
	node.set_meta("source_template",template)
	return node

func statistics() -> Dictionary:
	return {"cached_models":cache.size(),"max_cached_models":MAX_MODELS,"catalog_items":catalog.get("items",{}).size()}
