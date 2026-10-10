extends Node3D
## Static original sector geometry; native Core3 supplies moving ships separately.
const Loader = preload("res://scripts/stage_loader.gd")
var data: Dictionary = {}
var meshes: Dictionary = {}
var sky: ShaderMaterial
var loader := Loader.new()
var directory := ""
var zone := ""
var error := ""
var distant:Node3D

func texture(row: Dictionary) -> Texture2D:
	var path := directory.path_join(str(row.get("path", "")))
	if not FileAccess.file_exists(path): return null
	if not loader.textures.has(path):
		var image := Image.new()
		if image.load(path) != OK: return null
		image.generate_mipmaps(); loader.textures[path] = ImageTexture.create_from_image(image)
	return loader.textures[path]

func build(path: String) -> bool:
	directory = path.get_base_dir()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 2:
		error = "Original sector data missing. Install the updated testing data archive."; return false
	data = parsed; zone = str(data.source_zone)
	for key: String in data.meshes:
		var source: Dictionary = data.meshes[key]
		var mesh: ArrayMesh = loader.native_builder.create_mesh(source.surfaces)
		if mesh == null: error = "Invalid original sector mesh: " + key; return false
		for i in range(mesh.get_surface_count()): mesh.surface_set_material(i, loader.make_material(source.surfaces[i], directory))
		meshes[key] = mesh
	for record: Dictionary in data.instances:
		var node := MeshInstance3D.new(); node.mesh = meshes.get(record.mesh)
		node.position = loader.vec(record.position)
		var q: Array = record.get("quaternion", [0,0,0,1]); node.quaternion = Quaternion(q[0],q[1],q[2],q[3])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(node)
	for field: Dictionary in data.get("asteroidfield", []):
		var groups: Dictionary = {}
		for record: Dictionary in field.get("instances", []):
			if not groups.has(record.mesh): groups[record.mesh]=[]
			groups[record.mesh].append(record)
		for key: String in groups:
			var node:=MultiMeshInstance3D.new()
			node.multimesh=loader.native_builder.create_instances(meshes[key],groups[key])
			if node.multimesh==null:error="Invalid asteroid instances";node.free();return false
			node.visibility_range_end=float(field.get("MaxViewableDistance",4000))
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	var nebulae:=preload("res://space/nebulae.gd").new();add_child(nebulae);nebulae.build(data.get("nebula",[]))
	distant=Node3D.new();add_child(distant)
	var resources=preload("res://combat/original_assets.gd").new();resources.directory=ProjectSettings.globalize_path("res://../runtime/assets/space_effects")
	if resources.load_catalog():
		for record:Dictionary in data.environment.get("distant",[]):
			if not resources.catalog.particles.has(record.source):continue
			var effect:=preload("res://space/original_particles.gd").new();distant.add_child(effect)
			effect.position=loader.vec(record.position)
			var angles:Array=record.angles;effect.basis=Basis(Vector3.UP,-deg_to_rad(angles[0]))*Basis(Vector3.RIGHT,-deg_to_rad(angles[1]))*Basis(Vector3.BACK,deg_to_rad(angles[2]))
			effect.play(resources.catalog.particles[record.source],resources,true)
	build_sky()
	return true

func texture_array(rows:Array) -> Texture2DArray:
	var images:Array[Image]=[]
	for row:Dictionary in rows:
		var tex:=texture(row);var source:Image=tex.get_image() if tex!=null else Image.create(1,1,false,Image.FORMAT_RGBA8)
		source.convert(Image.FORMAT_RGBA8);source.resize(256,256,Image.INTERPOLATE_LANCZOS);source.generate_mipmaps();images.append(source)
	var result:=Texture2DArray.new()
	if not images.is_empty() and result.create_from_images(images)==OK:return result
	return null

func build_sky() -> void:
	sky = ShaderMaterial.new(); sky.shader = preload("res://space/sector_sky.gdshader")
	var environment: Dictionary = data.environment
	for face: String in environment.skybox.faces:
		sky.set_shader_parameter("sky_"+face, texture(environment.skybox.faces[face]))
	sky.set_shader_parameter("sector_width", float(environment.width))
	sky.set_shader_parameter("star_count", float(environment.get("stars", {}).get("count", 0)))
	var ambient: Array = environment.get("ambient", [1,.2,.2,.2])
	sky.set_shader_parameter("ambient", Vector3(ambient[1],ambient[2],ambient[3]))
	if not environment.get("lights", []).is_empty():
		var light: Array = environment.lights[0].values
		sky.set_shader_parameter("light_color", Vector3(light[1],light[2],light[3]))
		sky.set_shader_parameter("light_direction", Vector3(-light[8],-light[9],light[10]).normalized())
	sky.set_shader_parameter("star_ramp",texture(environment.get("stars",{}).get("ramp",{})))
	var celestial_rows:Array=[];var celestial_points:Array[Vector4]=[]
	for celestial:Dictionary in environment.get("celestials",[]):
		for layer:String in ["back","front"]:
			if celestial.get(layer,{}).is_empty() or float(celestial.get(layer+"_size",0))<=0:continue
			celestial_rows.append(celestial[layer].get("MAIN",{}))
			var point:Array=celestial.position;celestial_points.append(Vector4(point[0],point[1],point[2],float(celestial[layer+"_size"])/3.0))
	var count:=mini(40,celestial_points.size())
	while celestial_points.size()<40:celestial_points.append(Vector4.ZERO)
	sky.set_shader_parameter("celestial_count",count);sky.set_shader_parameter("celestial_points",celestial_points)
	if count>0:sky.set_shader_parameter("celestial_textures",texture_array(celestial_rows))
	var halo_rows:Array=[];var halo_settings:Array[Vector2]=[]
	for i in range(8):
		var planet:Dictionary=environment.planets[i] if i<environment.planets.size() else {}
		var halo:Dictionary=planet.get("halo",{})
		halo_rows.append(halo.get("textures",{}).get("MAIN",{}));halo_settings.append(Vector2(float(halo.get("scale",0)),deg_to_rad(float(planet.get("halo_roll",0)))))
	sky.set_shader_parameter("halo_textures",texture_array(halo_rows));sky.set_shader_parameter("halo_settings",halo_settings)
	var centers: Array[Vector4] = []; var rotations: Array[Basis] = []; var clouds: Array[Vector4] = []; var surfaces:Array[Vector4]=[]
	for i in range(8):
		centers.append(Vector4.ZERO); rotations.append(Basis.IDENTITY); clouds.append(Vector4.ZERO);surfaces.append(Vector4(1,1,0,0))
		if i >= environment.planets.size(): continue
		var planet: Dictionary = environment.planets[i]; var surface: Dictionary = planet.surface
		var p: Array = planet.position; centers[i] = Vector4(p[0],p[1],p[2],surface.radius)
		var angles: Array = planet.angles
		rotations[i] = (Basis(Vector3.UP,-deg_to_rad(angles[0]))*Basis(Vector3.RIGHT,-deg_to_rad(angles[1]))*Basis(Vector3.BACK,deg_to_rad(angles[2]))).inverse()
		var textures: Dictionary = surface.textures
		surfaces[i]=Vector4(1 if textures.has("MASK") else float(surface.uv_scales[0]),1 if textures.has("MASK") else float(surface.uv_scales[1]),deg_to_rad(float(surface.rotation_degrees))/TAU,0)
		sky.set_shader_parameter("surface_"+str(i), texture(textures.get("MASK", textures.get("MAIN", {}))))
		if planet.has("clouds"):
			var layer: Dictionary = planet.clouds
			clouds[i] = Vector4(layer.radius,layer.uv_scales[0],layer.uv_scales[1],deg_to_rad(layer.rotation_degrees)/TAU)
			sky.set_shader_parameter("clouds_"+str(i), texture(layer.textures.get("MAIN", {})))
	sky.set_shader_parameter("planet_count", mini(8, environment.planets.size()))
	sky.set_shader_parameter("planets", centers); sky.set_shader_parameter("planet_rotations", rotations)
	sky.set_shader_parameter("cloud_settings", clouds);sky.set_shader_parameter("surface_settings",surfaces)

func observe(pose: Transform3D) -> void:
	transform = pose.affine_inverse()
	if is_instance_valid(distant):distant.position=pose.origin*(1.0-100.0/float(data.environment.width))
	sky.set_shader_parameter("ship_rotation", pose.basis)
	sky.set_shader_parameter("ship_position", pose.origin)
