extends RefCounted
## Original user-provided SWG resources only; missing assets fail visibly.
var directory := ProjectSettings.globalize_path("res://../runtime/assets/combat")
var catalog: Dictionary = {}
var textures: Dictionary = {}
var meshes: Dictionary = {}
var audio: Dictionary = {}
var builder := SwgMeshBuilder.new()

func load_catalog() -> bool:
	var path := directory.path_join("assets.json")
	if not FileAccess.file_exists(path): return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return false
	catalog = data
	return true

func texture(path: String) -> Texture2D:
	if textures.has(path): return textures[path]
	var img := Image.load_from_file(directory.path_join(path))
	if img == null: return null
	textures[path] = ImageTexture.create_from_image(img)
	return textures[path]

func sound(path: String) -> AudioStream:
	if not audio.has(path): audio[path] = AudioStreamWAV.load_from_file(directory.path_join(path))
	return audio[path]

func model(key: String) -> Node3D:
	if not catalog.get("weapons",{}).has(key): return null
	var root := Node3D.new()
	for part in catalog.weapons[key].parts:
		var mesh_id: String = part.mesh
		if not meshes.has(mesh_id):
			var path: String = directory.path_join(catalog.meshes[mesh_id].path)
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var mesh: ArrayMesh = builder.create_mesh(data.surfaces)
			for i in range(mesh.get_surface_count()):
				var source: Dictionary = data.surfaces[i]
				var material := StandardMaterial3D.new()
				material.albedo_texture = texture(source.texture)
				material.roughness = 0.8
				if source.get("alpha",false): material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mesh.surface_set_material(i,material)
			meshes[mesh_id] = mesh
		var instance := MeshInstance3D.new()
		instance.mesh = meshes[mesh_id]
		root.add_child(instance)
	return root

func muzzle(key: String) -> Vector3:
	var p: Array = catalog.weapons[key].muzzle
	return Vector3(p[0],p[1],p[2])

func source_transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))

func stow_mount(race: String, hands: int, side: String) -> Dictionary:
	var definition: Dictionary = catalog.get("stow_mounts",{}).get(race,{}).get("mounts",{}).get("hip" if hands==1 else "back",{})
	if definition.is_empty(): return {}
	return {"anchor":definition.anchor_bone,"local":source_transform(definition.left_matrix if side=="left" else definition.matrix),"rest":source_transform(definition.anchor_rest_matrix),"carry":definition.get("carry_frame",{})}
