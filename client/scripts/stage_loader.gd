extends RefCounted

const CellStage = preload("res://scripts/cell_stage.gd")

var report: Dictionary = {}
var textures := {}
var native_builder := SwgMeshBuilder.new()
var collision_builder := SwgCollisionBuilder.new()

func vec(value, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("z", 0)))
	return fallback

func load_stage(path: String) -> Node3D:
	report = {"error": "", "meshes": 0, "instances": 0, "triangles": 0, "collision_bodies": 0, "path": path}
	if not FileAccess.file_exists(path):
		report.error = "Asset stage missing. Run the local media importer first.\n" + path
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		report.error = "Invalid stage JSON: " + path
		return null
	var data: Dictionary = parsed
	var stage := CellStage.new()
	stage.classifier.configure(data.get("cells", {}))
	stage.name = "MosEisleyImportedStage"
	stage.set_meta("manifest", data)
	report["authored_floor_bodies"] = install_floors(stage, data.get("cells", {}))
	report["authored_extent_bodies"] = 0
	report["visual_collision_fallbacks"] = 0
	var mesh_cache := {}
	var collision_cache := {}
	for mesh_id in data.get("meshes", {}):
		var source: Dictionary = data.meshes[mesh_id]
		var surfaces: Array = source.get("surfaces", [])
		var mesh: ArrayMesh = native_builder.create_mesh(surfaces)
		if mesh == null:
			report.error = "Native mesh conversion rejected: " + str(mesh_id)
			stage.free()
			return null
		for i in range(mesh.get_surface_count()):
			mesh.surface_set_material(i, make_material(surfaces[i], path.get_base_dir()))
			var arrays := mesh.surface_get_arrays(i)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			report.triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		if mesh.get_surface_count() > 0:
			mesh_cache[mesh_id] = mesh
			# Native conversion shares one immutable shape per mesh.
			collision_cache[mesh_id] = native_builder.create_collision(mesh)
	report.meshes = mesh_cache.size()
	for entry in data.get("instances", []):
		var mesh_id = entry.get("mesh", "")
		if not mesh_cache.has(mesh_id):
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh_cache[mesh_id]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_instance_shader_parameter("swg_indoor", 1.0 if entry.has("cell_id") and not entry.get("is_exterior", false) else 0.0)
		instance.position = vec(entry.get("position", []))
		var q = entry.get("quaternion", [0, 0, 0, 1])
		if q.size() == 4:
			instance.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()
		if entry.has("scale"):
			instance.scale = vec(entry.scale, Vector3.ONE)
		instance.set_meta("source_template", entry.get("source_template", ""))
		instance.set_meta("cell_id", entry.get("cell_id", ""))
		instance.set_meta("building_object_id", entry.get("building_object_id", 0))
		if entry.get("is_exterior", false):
			stage.exterior_instances.append(instance)
		stage.add_child(instance)
		var body := make_collision_body(entry, data.get("collisions", {}), collision_cache[mesh_id], data.get("cells", {}))
		if body != null:
			instance.add_child(body)
			report.collision_bodies += 1
			if body.get_meta("authored_extent", false):
				report.authored_extent_bodies += 1
			else:
				report.visual_collision_fallbacks += 1

		report.instances += 1
	if report.instances == 0:
		report.error = "Stage contains no compatible mesh instances."
		stage.free()
		return null
	report["origin"] = data.get("origin", [0, 0, 0])
	report["spawn"] = data.get("spawn", [0, 2, 0])
	report["spawn_yaw"] = data.get("spawn_yaw", 0.0)
	report["warnings"] = data.get("warnings", [])
	report["provenance"] = data.get("provenance", {})
	return stage

func install_floors(parent: Node3D, cells: Dictionary, collect_bodies: Variant = null) -> int:
	var count := 0
	for id: String in cells:
		var shape: ConcavePolygonShape3D = collision_builder.build_floor(cells[id])
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Floor_" + id.replace(":", "_")
		body.collision_layer = 4
		body.collision_mask = 0
		body.set_meta("source_cell", id)
		body.set_meta("authored_floor", true)
		body.set_meta("source_layer", 4)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)
		if collect_bodies is Array: collect_bodies.append(body)
		count += 1
	return count

func make_collision_body(entry: Dictionary, definitions: Dictionary, fallback: Shape3D, cells: Dictionary = {}) -> StaticBody3D:
	if not entry.get("collision", true) or not entry.get("collision_owner", true):
		return null
	var source: Dictionary = definitions.get(str(entry.get("collision_id", "")), {})
	var portals: Array = []
	var cell: Dictionary = cells.get(str(entry.get("cell_id", "")), {})
	# Only the cell's authored shell has portal closure faces. Decorations can
	# share cell membership without becoming eligible for doorway subtraction.
	if not cell.is_empty() and not str(cell.get("collision_id", "")).is_empty() and entry.get("collision_id", "") == cell.collision_id:
		var q: Array = entry.get("quaternion", [0,0,0,1])
		var basis := Basis(Quaternion(float(q[0]),float(q[1]),float(q[2]),float(q[3])).normalized())
		if entry.has("scale"): basis = basis.scaled(vec(entry.scale, Vector3.ONE))
		var inverse := Transform3D(basis,vec(entry.get("position", []))).affine_inverse()
		for portal: Dictionary in cell.get("portals", []):
			var local := portal.duplicate()
			local["exterior_shell"] = bool(cell.get("is_exterior",false))
			var vertices: Array = []
			var original: Array = portal.get("vertices", [])
			for i in range(0,original.size(),3):
				var point := inverse * Vector3(original[i],original[i+1],original[i+2])
				vertices.append_array([point.x,point.y,point.z])
			local["vertices"] = vertices
			portals.append(local)
	var shapes: Array = collision_builder.build_cell_extent(source.get("extent", {}), portals) if not portals.is_empty() else collision_builder.build_extent(source.get("extent", {}))
	var authored := not shapes.is_empty()
	# Keep an explicit compatibility fallback for assets whose source declares
	# no collision extent; source POB walls with valid extents never use LOD faces.
	if shapes.is_empty():
		if source.get("status", "") == "null":
			return null
		if entry.get("is_exterior", false) and entry.has("cell_id"):
			return null
		if fallback == null:
			return null
		shapes = [{"shape":fallback,"transform":Transform3D.IDENTITY}]
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("authored_extent", authored)
	body.set_meta("source_cell", entry.get("cell_id", ""))
	body.set_meta("source_layer", 1)
	body.set_meta("collision_source", entry.get("collision_id", "visual_mesh_fallback"))
	for item: Dictionary in shapes:
		var collider := CollisionShape3D.new()
		collider.shape = item.shape
		collider.transform = item.transform
		body.add_child(collider)
	return body

func make_material(surface: Dictionary, directory: String, allow_disk_load := true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/static_baked.gdshader")
	material.set_shader_parameter("use_vertex_color", true)
	material.set_shader_parameter("alpha_cutout", bool(surface.get("alpha", false)))
	var color = surface.get("color", [0.73, 0.61, 0.44])
	material.set_shader_parameter("albedo_color", Color(float(color[0]), float(color[1]), float(color[2])))
	var texture_path: String = surface.get("texture", "")
	if not texture_path.is_empty():
		if not texture_path.is_absolute_path():
			texture_path = directory.path_join(texture_path)
		if allow_disk_load and not textures.has(texture_path) and FileAccess.file_exists(texture_path):
			var img := Image.load_from_file(texture_path)
			if img != null:
				img.generate_mipmaps()
				textures[texture_path] = ImageTexture.create_from_image(img)
		if textures.has(texture_path):
			material.set_shader_parameter("albedo_texture", textures[texture_path])
			material.set_shader_parameter("has_texture", true)
			material.set_shader_parameter("albedo_color", Color.WHITE)
	return material
